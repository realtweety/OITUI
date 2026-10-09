// Quoted on purpose: resolves to this project's own include/OITCore/OITLog.h (via -Iinclude/OITCore) instead of
// a possibly older copy installed in $THEOS/include/OITCore by an earlier build.
#import "OITLog.h"
#import <os/log.h>
#import <os/lock.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <fcntl.h>
#import <unistd.h>
#import <time.h>
#import <dlfcn.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/utsname.h>

#if defined(__has_feature)
#  if __has_feature(ptrauth_calls)
#    import <ptrauth.h>
#    define OITLogStripPointer(p) ptrauth_strip((p), ptrauth_key_return_address)
#  endif
#endif
#ifndef OITLogStripPointer
#  define OITLogStripPointer(p) (p)
#endif

// =============================================================================================
// Legacy API (unchanged behavior)
// =============================================================================================

static BOOL sOITLogEnabled = NO;

void OITLogSetEnabled(BOOL enabled) {
    sOITLogEnabled = enabled;
}

BOOL OITLogIsEnabled(void) {
    return sOITLogEnabled;
}

void OITLog(NSString *format, ...) {
    if (!sOITLogEnabled) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log(OS_LOG_DEFAULT, "[OITCore] %{public}@", message);
}

// =============================================================================================
// OITLogger
// =============================================================================================

#define kOITLoggerRateSlots 64

// If the writer queue has this many lines pending, further lines are dropped (and counted) instead of queued.
static const NSInteger kOITLoggerMaxPending = 4000;
static const NSUInteger kOITLoggerMaxStackFrames = 16;
static const NSUInteger kOITLoggerMaxScanFrames = 48;

typedef struct {
    char key[32];
    uint64_t windowStartNs;
    NSUInteger count;
    NSUInteger suppressed;
} OITLogRateSlot;

// Rootless tweaks load from .../Library/MobileSubstrate/DynamicLibraries/ (the /var/jb prefix can appear as
// either the symlink or the resolved preboot path, so only the stable tail is matched).
static BOOL OITLogPathIsTweakImage(const char *path) {
    return strstr(path, "/MobileSubstrate/DynamicLibraries/") != NULL ||
           strstr(path, "/TweakInject/") != NULL;
}

@interface OITLogger () {
    dispatch_queue_t _queue;
    NSDateFormatter *_formatter;            // touched only on _queue
    os_unfair_lock _lock;                   // guards _slots, _slotCount, _budgets
    OITLogRateSlot _slots[kOITLoggerRateSlots];
    NSUInteger _slotCount;
    NSMutableDictionary<NSString *, NSNumber *> *_budgets;
    uint64_t _startNs;
    _Atomic NSUInteger _seq;
    _Atomic NSInteger _pending;
    _Atomic NSUInteger _overflowDropped;
}
@end

@implementation OITLogger

+ (instancetype)loggerWithName:(NSString *)name path:(NSString *)path {
    return [[self alloc] initWithName:name path:path];
}

- (instancetype)initWithName:(NSString *)name path:(NSString *)path {
    if ((self = [super init])) {
        _name = [name copy] ?: @"log";
        _path = [path copy];
        _enabled = YES;
        _level = 0;   // quiet by default: callers raise it from a preference
        _maxFileBytes = 6ull * 1024ull * 1024ull;
        _lock = OS_UNFAIR_LOCK_INIT;
        _budgets = [NSMutableDictionary dictionary];
        _startNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        atomic_init(&_seq, 0);
        atomic_init(&_pending, 0);
        atomic_init(&_overflowDropped, 0);

        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                             QOS_CLASS_UTILITY, 0);
        NSString *label = [@"com.wilburt.oitcore.log." stringByAppendingString:_name];
        _queue = dispatch_queue_create(label.UTF8String, attr);
    }
    return self;
}

- (BOOL)isLoggingAtLevel:(NSInteger)level {
    return self.enabled && self.level >= level;
}

// ---- File writing (runs on _queue) ----

// open/append/close per line, so deleting the file while running just starts a fresh one.
- (void)appendLineToFile:(NSString *)line {
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length || !self.path.length) return;

    const char *path = self.path.fileSystemRepresentation;
    int fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0666);
    if (fd < 0) return;
    // Lets both root (SSH) and mobile (SpringBoard) append to the same file. Harmless if we do not own it.
    (void)fchmod(fd, 0666);

    struct stat st;
    if (fstat(fd, &st) == 0 && (unsigned long long)st.st_size > self.maxFileBytes) {
        NSString *rotated = [self.path stringByAppendingString:@".1"];
        if (rename(path, rotated.fileSystemRepresentation) == 0) {
            close(fd);
            fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0666);
            if (fd < 0) return;
            (void)fchmod(fd, 0666);
        } else {
            (void)ftruncate(fd, 0);
        }
    }
    (void)write(fd, data.bytes, data.length);
    close(fd);
}

- (void)enqueueTag:(NSString *)tag message:(NSString *)message {
    NSInteger pending = atomic_fetch_add_explicit(&_pending, 1, memory_order_relaxed);
    if (pending >= kOITLoggerMaxPending) {
        atomic_fetch_sub_explicit(&_pending, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&_overflowDropped, 1, memory_order_relaxed);
        return;
    }

    NSTimeInterval wall = [[NSDate date] timeIntervalSince1970];
    double mono = (double)(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - _startNs) / 1e9;
    NSUInteger seq = atomic_fetch_add_explicit(&_seq, 1, memory_order_relaxed) + 1;
    NSUInteger tick = self.tick;
    BOOL isMain = [NSThread isMainThread];

    dispatch_async(_queue, ^{
        if (!self->_formatter) {
            self->_formatter = [NSDateFormatter new];
            self->_formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            self->_formatter.dateFormat = @"MM-dd HH:mm:ss.SSS";
        }
        NSString *stamp = [self->_formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:wall]];

        NSUInteger dropped = atomic_exchange_explicit(&self->_overflowDropped, 0, memory_order_relaxed);
        if (dropped) {
            NSString *note = [NSString stringWithFormat:@"%@ +%.3f #- B t%lu [LOG] (%lu line(s) dropped: writer backlog)\n",
                              stamp, mono, (unsigned long)tick, (unsigned long)dropped];
            [self appendLineToFile:note];
        }

        NSString *line = [NSString stringWithFormat:@"%@ +%.3f #%lu %@ t%lu [%@] %@\n",
                          stamp, mono, (unsigned long)seq, isMain ? @"M" : @"B",
                          (unsigned long)tick, tag, message];
        [self appendLineToFile:line];
        atomic_fetch_sub_explicit(&self->_pending, 1, memory_order_relaxed);
    });
}

// ---- Logging entry points ----

- (void)logTag:(NSString *)tag format:(NSString *)format, ... {
    if (!self.enabled) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self enqueueTag:tag message:message];
}

- (void)logLevel:(NSInteger)level tag:(NSString *)tag format:(NSString *)format, ... {
    if (![self isLoggingAtLevel:level]) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self enqueueTag:tag message:message];
}

// ---- Rate limiting ----

- (BOOL)allowTag:(NSString *)tag rateKey:(NSString *)key perSecond:(NSUInteger)perSecond {
    if (!self.enabled) return NO;
    const char *cKey = key.UTF8String ?: "";
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    BOOL allowed = NO;
    NSUInteger suppressed = 0;

    os_unfair_lock_lock(&_lock);
    OITLogRateSlot *slot = NULL;
    for (NSUInteger i = 0; i < _slotCount; i++) {
        if (strncmp(_slots[i].key, cKey, sizeof(_slots[i].key) - 1) == 0) {
            slot = &_slots[i];
            break;
        }
    }
    if (!slot && _slotCount < kOITLoggerRateSlots) {
        slot = &_slots[_slotCount++];
        memset(slot, 0, sizeof(*slot));
        strncpy(slot->key, cKey, sizeof(slot->key) - 1);
        slot->windowStartNs = now;
    }
    if (!slot) {
        // Out of slots: do not rate limit rather than lose lines silently.
        os_unfair_lock_unlock(&_lock);
        return YES;
    }
    if (now - slot->windowStartNs >= 1000000000ull) {
        slot->windowStartNs = now;
        slot->count = 0;
    }
    if (slot->count < perSecond) {
        slot->count++;
        allowed = YES;
        suppressed = slot->suppressed;
        slot->suppressed = 0;
    } else {
        slot->suppressed++;
    }
    os_unfair_lock_unlock(&_lock);

    if (allowed && suppressed) {
        [self logTag:tag format:@"(%lu '%s' line(s) dropped by rate limit)", (unsigned long)suppressed, cKey];
    }
    return allowed;
}

// ---- Stack traces ----

- (void)logStackWithTag:(NSString *)tag budgetKey:(NSString *)budgetKey budget:(NSUInteger)budget note:(NSString *)note {
    if (!self.enabled) return;

    os_unfair_lock_lock(&_lock);
    NSUInteger used = _budgets[budgetKey].unsignedIntegerValue;
    BOOL allowed = used < budget;
    if (allowed) _budgets[budgetKey] = @(used + 1);
    os_unfair_lock_unlock(&_lock);
    if (!allowed) return;

    NSArray<NSNumber *> *addresses = [NSThread callStackReturnAddresses];
    NSArray<NSString *> *symbols = [NSThread callStackSymbols];
    NSSet<NSString *> *ignored = [NSSet setWithArray:self.ignoredImageNames ?: @[]];

    NSMutableArray<NSString *> *thirdParty = [NSMutableArray array];
    NSUInteger scan = MIN(addresses.count, kOITLoggerMaxScanFrames);
    for (NSUInteger i = 1; i < scan; i++) {   // frame 0 is this method
        void *address = (void *)(uintptr_t)addresses[i].unsignedLongLongValue;
        address = OITLogStripPointer(address);
        Dl_info info;
        if (!dladdr(address, &info) || !info.dli_fname) continue;
        if (!OITLogPathIsTweakImage(info.dli_fname)) continue;
        const char *slash = strrchr(info.dli_fname, '/');
        NSString *imageName = [NSString stringWithUTF8String:slash ? slash + 1 : info.dli_fname];
        if (!imageName.length || [ignored containsObject:imageName] || [thirdParty containsObject:imageName]) continue;
        [thirdParty addObject:imageName];
    }

    [self logTag:tag format:@"STACK %@ third-party=[%@]", note ?: @"", [thirdParty componentsJoinedByString:@", "]];
    NSUInteger frameLimit = MIN(symbols.count, 1 + kOITLoggerMaxStackFrames);
    for (NSUInteger i = 1; i < frameLimit; i++) {
        [self logTag:tag format:@"  #%lu %@", (unsigned long)(i - 1), symbols[i]];
    }
}

// ---- Session header ----

- (void)logSessionStartWithBuildTag:(NSString *)buildTag {
    struct utsname u;
    uname(&u);
    NSProcessInfo *info = [NSProcessInfo processInfo];
    [self logTag:@"SESSION" format:@"START build=%@ pid=%d proc=%@ os=%@ machine=%s",
     buildTag ?: @"?", getpid(), info.processName, info.operatingSystemVersionString, u.machine];
}

// ---- State-change helper ----

- (BOOL)noteSignature:(NSString *)signature forObject:(id)object {
    if (!object || !signature) return NO;
    const void *key = (__bridge const void *)self;   // one slot per logger
    NSString *last = objc_getAssociatedObject(object, key);
    if (last && [last isEqualToString:signature]) return NO;
    objc_setAssociatedObject(object, key, signature, OBJC_ASSOCIATION_COPY);
    return YES;
}

- (void)flush {
    dispatch_sync(_queue, ^{});
}

@end
