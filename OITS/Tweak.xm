// =====================================================================================
// OITS Tweak.xm -- DIAGNOSTIC BUILD  (build tag: see kOITSBuildTag)
//
// Functionally identical to the Stage 2 build EXCEPT:
//   1. Massive logging/diagnostics added (see log tag glossary below).
//   2. sPrevious*Enabled flags are now actually assigned in OITSReloadPreferences. Before,
//      they were never updated, so "reset on disable" could never fire. Now it does.
//   3. Logging is written asynchronously on a private queue, with rate limiting, so it does
//      not stall SpringBoard's main thread. Log rotates at ~6 MB (/tmp/OITSDebug.log.1).
//
// Log file:      /tmp/OITSDebug.log
// Dump trigger:  touch /tmp/OITSDump.trigger   (or Darwin notification com.wilburt.oits/DumpState)
// Prefs keys:    DiagnosticsEnabled (bool, default YES), DiagnosticsLevel (0-2, default 0)
//   level 0 = legacy logs only, 1 = events/state changes/heartbeat, 2 = + every hooked call
//   Default is 0: a normal install writes only the few legacy/session/PREF lines and the MAINSTALL warning, does no
//   visibility watchdog, heartbeat, baseline dump or system-notification tap. For development raise it:
//     defaults write com.wilburt.oits.prefs DiagnosticsLevel -int 2     (then sbreload)
//
// Tags: SESSION PREF GEN REFUSED APPLY STATE VIS TRACK SKIP DEAD MOVE REMOVE SYS-SET SETFRAME
//       LAYOUT SUBVIEW DISCOVER HB WARN TICKGAP TICKSLOW MAINSTALL ENFORCER DUMP NOTIF DARWIN
// =====================================================================================

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <stdarg.h>
#import <string.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/utsname.h>
#import <os/lock.h>
#import <objc/runtime.h>
#import <OITCore/OITCore.h>

static NSString * const kOITSBuildTag = @"OITS-diag-2026-09-29-a";
static NSString * const kOITSPrefsDomain = @"com.wilburt.oits.prefs";
static NSString * const kOITSPrefsChangedNotification = @"com.wilburt.oits/PrefsChanged";
static NSString * const kOITSDumpNotification = @"com.wilburt.oits/DumpState";
static NSString * const kOITSLogPath = @"/tmp/OITSDebug.log";
static NSString * const kOITSLogRotatedPath = @"/tmp/OITSDebug.log.1";
static NSString * const kOITSDumpTriggerPath = @"/tmp/OITSDump.trigger";
static const off_t kOITSLogMaxBytes = 6 * 1024 * 1024;
static const CGFloat kOITSCenterToleranceInPoints = 2.0;
static const CGFloat kOITSDriftToleranceInPoints = 0.5;
static const NSUInteger kOITSDiscoveryIntervalTicks = 10;
static const NSUInteger kOITSMaxTraverseDepth = 40;
static const NSTimeInterval kOITSStartupDelaySeconds = 3.0;
static const NSUInteger kOITSMaxRemovalEventLogs = 60;
static const NSUInteger kOITSMaxSuppressionLogs = 60;
static const NSUInteger kOITSMaxStackLogs = 80;
static const NSUInteger kOITSMaxAutoDumps = 8;
static const NSUInteger kOITSDumpMaxLines = 500;
static const NSUInteger kOITSHeartbeatSeconds = 3;

static OITPreferences *sOITSPreferences;
static BOOL sSpringBoardIsReadyForWindowAccess = NO;
static NSUInteger sRemovalEventLogCount = 0;
static NSUInteger sSuppressionLogCount = 0;

static BOOL sClockRepositionEnabled = NO;
static BOOL sPreviousClockEnabled = NO;
static BOOL sClockHidden = NO;
static CGFloat sClockLeadingOffset = 16.0;
static NSHashTable<UIView *> *sTrackedClockViews;
static Class sStatusBarStringViewClass;
static const void *kOITSClockNaturalXKey = &kOITSClockNaturalXKey;

static BOOL sBatteryRepositionEnabled = NO;
static BOOL sPreviousBatteryEnabled = NO;
static BOOL sBatteryHidden = NO;
static CGFloat sBatteryLeadingOffset = 384.0;
static NSHashTable<UIView *> *sTrackedBatteryViews;
static Class sStaticBatteryViewClass;
static Class sBatteryViewAltClass;
static const void *kOITSBatteryNaturalXKey = &kOITSBatteryNaturalXKey;

static BOOL sWifiRepositionEnabled = NO;
static BOOL sPreviousWifiEnabled = NO;
static BOOL sWifiHidden = NO;
static CGFloat sWifiLeadingOffset = 76.0;
static NSHashTable<UIView *> *sTrackedWifiViews;
static Class sStatusBarWifiSignalViewClass;
static const void *kOITSWifiNaturalXKey = &kOITSWifiNaturalXKey;

static BOOL sCellularRepositionEnabled = NO;
static BOOL sPreviousCellularEnabled = NO;
static BOOL sCellularHidden = NO;
static CGFloat sCellularLeadingOffset = 6.0;
static NSHashTable<UIView *> *sTrackedCellularViews;
static const void *kOITSCellularNaturalXKey = &kOITSCellularNaturalXKey;

static BOOL sCarrierTextRepositionEnabled = NO;
static BOOL sPreviousCarrierTextEnabled = NO;
static BOOL sCarrierTextHidden = NO;
static CGFloat sCarrierTextLeadingOffset = 28.0;
static NSHashTable<UIView *> *sTrackedCarrierTextViews;
static const void *kOITSCarrierTextNaturalXKey = &kOITSCarrierTextNaturalXKey;

static BOOL sNetworkTypeRepositionEnabled = NO;
static BOOL sPreviousNetworkTypeEnabled = NO;
static BOOL sNetworkTypeHidden = NO;
static CGFloat sNetworkTypeLeadingOffset = 80.0;
static NSHashTable<UIView *> *sTrackedNetworkTypeViews;
static Class sCellularNetworkTypeViewClass;
static const void *kOITSNetworkTypeNaturalXKey = &kOITSNetworkTypeNaturalXKey;

// ---- Diagnostics state ----
static BOOL sOITSDiagEnabled = YES;
static NSInteger sOITSDiagLevel = 0;
static BOOL sOITSInternalChange = NO;          // YES only while OITS itself is writing hidden/transform
static NSUInteger sOITSCurrentTick = 0;
static NSUInteger sOITSLogSeq = 0;
static CFTimeInterval sOITSLogStartMono = 0;
static NSUInteger sOITSStackLogCount = 0;
static NSUInteger sOITSAutoDumpCount = 0;
static NSHashTable<UIView *> *sDiagForegroundViews;
static NSHashTable<UIView *> *sDiagStatusBarViews;
static NSString *sOITSLastDiscoverySig;
static const void *kOITSLastSigKey = &kOITSLastSigKey;
static const void *kOITSLastVisKey = &kOITSLastVisKey;
static const void *kOITSTrackedAtKey = &kOITSTrackedAtKey;
static const void *kOITSSkipLoggedKey = &kOITSSkipLoggedKey;

// =====================================================================================
// MARK: Logging core
// =====================================================================================

static void OITSLogImpl(NSString *tag, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static void OITSDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

static dispatch_queue_t OITSLogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.wilburt.oits.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

// open/append/close per line so `rm /tmp/OITSDebug.log` while running just starts a fresh file.
static void OITSAppendToLogFile(NSString *line) {
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return;
    const char *path = [kOITSLogPath fileSystemRepresentation];
    int fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0666);
    if (fd < 0) return;
    struct stat st;
    if (fstat(fd, &st) == 0 && st.st_size > kOITSLogMaxBytes) {
        if (rename(path, [kOITSLogRotatedPath fileSystemRepresentation]) == 0) {
            close(fd);
            fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0666);
            if (fd < 0) return;
        } else {
            (void)ftruncate(fd, 0);
        }
    }
    (void)write(fd, data.bytes, data.length);
    close(fd);
}

static void OITSLogv(NSString *tag, NSString *format, va_list args) {
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    NSTimeInterval wall = [[NSDate date] timeIntervalSince1970];
    CFTimeInterval mono = CACurrentMediaTime() - sOITSLogStartMono;
    NSUInteger seq = __sync_add_and_fetch(&sOITSLogSeq, 1);
    NSUInteger tick = sOITSCurrentTick;
    BOOL isMain = [NSThread isMainThread];
    dispatch_async(OITSLogQueue(), ^{
        static NSDateFormatter *formatter;
        if (!formatter) {
            formatter = [NSDateFormatter new];
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.dateFormat = @"MM-dd HH:mm:ss.SSS";
        }
        NSString *stamp = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:wall]];
        NSString *line = [NSString stringWithFormat:@"%@ +%.3f #%lu %@ t%lu [%@] %@\n",
                          stamp, mono, (unsigned long)seq, isMain ? @"M" : @"B",
                          (unsigned long)tick, tag, message];
        OITSAppendToLogFile(line);
    });
}

static void OITSLogImpl(NSString *tag, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    OITSLogv(tag, format, args);
    va_end(args);
}

// Legacy entry point -- always logs, regardless of diagnostics level.
static void OITSDebugLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    OITSLogv(@"GEN", format, args);
    va_end(args);
}

// ---- Rate limiter: at most `maxPerSecond` lines per key per second; counts what it drops ----
typedef struct {
    char key[32];
    CFTimeInterval windowStart;
    NSUInteger count;
    NSUInteger suppressed;
} OITSRateSlot;

static OITSRateSlot sOITSRateSlots[64];
static NSUInteger sOITSRateSlotCount = 0;
static os_unfair_lock sOITSRateLock = OS_UNFAIR_LOCK_INIT;

static BOOL OITSRateAllow(const char *key, NSUInteger maxPerSecond, NSUInteger *suppressedOut) {
    if (suppressedOut) *suppressedOut = 0;
    if (!key) return YES;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL allowed = NO;
    os_unfair_lock_lock(&sOITSRateLock);
    OITSRateSlot *slot = NULL;
    for (NSUInteger i = 0; i < sOITSRateSlotCount; i++) {
        if (strncmp(sOITSRateSlots[i].key, key, sizeof(sOITSRateSlots[i].key) - 1) == 0) {
            slot = &sOITSRateSlots[i];
            break;
        }
    }
    if (!slot && sOITSRateSlotCount < 64) {
        slot = &sOITSRateSlots[sOITSRateSlotCount++];
        memset(slot, 0, sizeof(*slot));
        strncpy(slot->key, key, sizeof(slot->key) - 1);
        slot->windowStart = now;
    }
    if (!slot) {
        os_unfair_lock_unlock(&sOITSRateLock);
        return YES;
    }
    if (now - slot->windowStart >= 1.0) {
        slot->windowStart = now;
        slot->count = 0;
    }
    if (slot->count < maxPerSecond) {
        slot->count++;
        allowed = YES;
        if (suppressedOut) *suppressedOut = slot->suppressed;
        slot->suppressed = 0;
    } else {
        slot->suppressed++;
    }
    os_unfair_lock_unlock(&sOITSRateLock);
    return allowed;
}

// NOTE: `tag`, `key`, `perSec` and `level` must not contain top-level commas.
#define OITSLOG(level, tag, ...) \
    do { \
        if (sOITSDiagEnabled && sOITSDiagLevel >= (level)) { \
            OITSLogImpl((tag), __VA_ARGS__); \
        } \
    } while (0)

#define OITSLOG_RATED(level, tag, key, perSec, ...) \
    do { \
        if (sOITSDiagEnabled && sOITSDiagLevel >= (level)) { \
            const char *_oitsKey = (key); \
            NSUInteger _oitsSup = 0; \
            if (OITSRateAllow(_oitsKey, (perSec), &_oitsSup)) { \
                if (_oitsSup) OITSLogImpl((tag), @"(%lu '%s' line(s) dropped by rate limit)", (unsigned long)_oitsSup, _oitsKey); \
                OITSLogImpl((tag), __VA_ARGS__); \
            } \
        } \
    } while (0)

// =====================================================================================
// MARK: View description helpers
// =====================================================================================

static NSString *OITSRectDesc(CGRect r) {
    return [NSString stringWithFormat:@"{{%.2f,%.2f},{%.2f,%.2f}}", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static NSString *OITSTransformDesc(CGAffineTransform t) {
    return [NSString stringWithFormat:@"a=%.4f b=%.4f c=%.4f d=%.4f tx=%.2f ty=%.2f", t.a, t.b, t.c, t.d, t.tx, t.ty];
}

static NSString *OITSViewBrief(UIView *v) {
    if (!v) return @"nil";
    return [NSString stringWithFormat:@"%@@%p", NSStringFromClass([v class]), v];
}

static NSString *OITSTextOfView(UIView *v) {
    if (![v respondsToSelector:@selector(text)]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id value = [v performSelector:@selector(text)];
#pragma clang diagnostic pop
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

static NSString *OITSTextColorDesc(UIView *v) {
    if (![v respondsToSelector:@selector(textColor)]) return nil;
    UIColor *color = [(UILabel *)v textColor];
    if (!color) return @"nil";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.2f,%.2f,%.2f,%.2f)", r, g, b, a];
    }
    return [NSString stringWithFormat:@"%@ a=%.2f", color, CGColorGetAlpha(color.CGColor)];
}

static NSString *OITSLabelForView(UIView *v) {
    if ([sTrackedClockViews containsObject:v]) return @"clock";
    if ([sTrackedBatteryViews containsObject:v]) return @"battery";
    if ([sTrackedWifiViews containsObject:v]) return @"wifi";
    if ([sTrackedCellularViews containsObject:v]) return @"cellular";
    if ([sTrackedCarrierTextViews containsObject:v]) return @"carrier";
    if ([sTrackedNetworkTypeViews containsObject:v]) return @"network";
    if ([sDiagForegroundViews containsObject:v]) return @"foreground";
    if ([sDiagStatusBarViews containsObject:v]) return @"statusbar";
    return @"other";
}

static NSNumber *OITSNaturalXOfView(UIView *v) {
    const void *keys[] = {
        kOITSClockNaturalXKey, kOITSBatteryNaturalXKey, kOITSWifiNaturalXKey,
        kOITSCellularNaturalXKey, kOITSCarrierTextNaturalXKey, kOITSNetworkTypeNaturalXKey
    };
    for (NSUInteger i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        NSNumber *n = objc_getAssociatedObject(v, keys[i]);
        if (n) return n;
    }
    return nil;
}

static NSString *OITSWindowDesc(UIWindow *w) {
    if (!w) return @"nil";
    UIWindowScene *scene = w.windowScene;
    return [NSString stringWithFormat:@"%@@%p lvl=%.0f hid=%d a=%.2f frame=%@ scene=%@ role=%@ act=%ld",
            NSStringFromClass([w class]), w, w.windowLevel, w.hidden, w.alpha, OITSRectDesc(w.frame),
            scene ? NSStringFromClass([scene class]) : @"nil",
            scene.session.role ?: @"nil", (long)scene.activationState];
}

static NSString *OITSAncestorChain(UIView *v, NSUInteger maxDepth) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *cur = v.superview;
    NSUInteger n = 0;
    while (cur && n < maxDepth) {
        [parts addObject:[NSString stringWithFormat:@"%@@%p[h%d a%.2f sc%.3f tx%.1f]",
                          NSStringFromClass([cur class]), cur, cur.hidden, cur.alpha,
                          cur.transform.a, cur.transform.tx]];
        cur = cur.superview;
        n++;
    }
    return [parts componentsJoinedByString:@" < "];
}

static NSString *OITSViewDetail(UIView *v) {
    if (!v) return @"nil";
    NSMutableString *s = [NSMutableString stringWithFormat:
        @"%@ frame=%@ bounds=%@ center=(%.2f,%.2f) tf={%@} hid=%d alpha=%.2f layerOp=%.2f clips=%d",
        OITSViewBrief(v), OITSRectDesc(v.frame), OITSRectDesc(v.bounds), v.center.x, v.center.y,
        OITSTransformDesc(v.transform), v.hidden, v.alpha, v.layer.opacity, v.clipsToBounds];
    NSNumber *natural = OITSNaturalXOfView(v);
    if (natural) [s appendFormat:@" naturalX=%.2f", natural.doubleValue];
    NSString *text = OITSTextOfView(v);
    if (text) [s appendFormat:@" text=\"%@\" textColor=%@", text, OITSTextColorDesc(v) ?: @"?"];
    NSArray<NSString *> *anims = v.layer.animationKeys;
    if (anims.count) [s appendFormat:@" anims=[%@]", [anims componentsJoinedByString:@","]];
    if (v.layer.mask) [s appendString:@" HAS-MASK"];
    [s appendFormat:@" win=%@ sup=%@", v.window ? [NSString stringWithFormat:@"%p", v.window] : @"nil", OITSViewBrief(v.superview)];
    return s;
}

static NSString *OITSSubviewSummary(UIView *v) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger n = 0;
    for (UIView *sub in v.subviews) {
        if (n++ >= 14) { [parts addObject:@"..."]; break; }
        NSString *text = OITSTextOfView(sub);
        [parts addObject:[NSString stringWithFormat:@"%@%@%@ x=%.1f h%d a%.2f",
                          NSStringFromClass([sub class]), text ? @"[" : @"", text ? [text stringByAppendingString:@"]"] : @"",
                          sub.frame.origin.x, sub.hidden, sub.alpha]];
    }
    return [NSString stringWithFormat:@"%lu: %@", (unsigned long)v.subviews.count, [parts componentsJoinedByString:@"; "]];
}

// Returns nil when the view is fully visible; otherwise a short reason.
// Reasons starting with "partial" mean visible-but-clipped (not treated as a disappearance).
static NSString *OITSVisibilityProblem(UIView *v) {
    UIWindow *w = v.window;
    if (!w) return @"no-window";
    if (w.hidden) return @"window-hidden";
    if (w.alpha < 0.01) return @"window-alpha~0";
    CGFloat cumulative = 1.0;
    for (UIView *a = v; a; a = a.superview) {
        if (a.hidden) return [NSString stringWithFormat:@"hidden@%@", NSStringFromClass([a class])];
        if (a.alpha < 0.01) return [NSString stringWithFormat:@"alpha~0@%@", NSStringFromClass([a class])];
        if (a.layer.opacity < 0.01f) return [NSString stringWithFormat:@"layerOpacity~0@%@", NSStringFromClass([a class])];
        cumulative *= a.alpha;
    }
    if (cumulative < 0.01) return @"cumulative-alpha~0";
    if (v.bounds.size.width <= 0.0 || v.bounds.size.height <= 0.0) return @"empty-bounds";
    CGRect inWindow = [v convertRect:v.bounds toView:nil];
    CGRect onScreen = [w convertRect:inWindow toWindow:nil];
    CGRect screen = UIScreen.mainScreen.bounds;
    CGRect visible = CGRectIntersection(onScreen, screen);
    if (CGRectIsEmpty(visible)) return [NSString stringWithFormat:@"offscreen rect=%@", OITSRectDesc(onScreen)];
    CGFloat fullArea = onScreen.size.width * onScreen.size.height;
    CGFloat visibleArea = visible.size.width * visible.size.height;
    if (fullArea > 0.0 && (visibleArea / fullArea) < 0.98) {
        return [NSString stringWithFormat:@"partial %.0f%% on-screen rect=%@", (visibleArea / fullArea) * 100.0, OITSRectDesc(onScreen)];
    }
    return nil;
}

static NSString *OITSCompactStack(NSUInteger skip, NSUInteger maxFrames) {
    NSArray<NSString *> *symbols = [NSThread callStackSymbols];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSUInteger i = skip; i < symbols.count && out.count < maxFrames; i++) {
        NSArray<NSString *> *raw = [symbols[i] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (NSString *p in raw) {
            if (p.length) [parts addObject:p];
        }
        if (parts.count >= 4) {
            NSString *tail = [[parts subarrayWithRange:NSMakeRange(3, parts.count - 3)] componentsJoinedByString:@" "];
            [out addObject:[NSString stringWithFormat:@"%@:%@", parts[1], tail]];
        } else {
            [out addObject:symbols[i]];
        }
    }
    return [out componentsJoinedByString:@" <- "];
}

static NSString *OITSStackIfBudget(void) {
    if (sOITSStackLogCount >= kOITSMaxStackLogs) return @"(stack budget exhausted)";
    sOITSStackLogCount++;
    return OITSCompactStack(2, 9);
}

// =====================================================================================
// MARK: Internal setters (flag our own writes so hooks can tell OITS from the system)
// =====================================================================================

static void OITSSetTransformInternal(UIView *view, CGAffineTransform t) {
    sOITSInternalChange = YES;
    view.transform = t;
    sOITSInternalChange = NO;
}

static void OITSSetHiddenInternal(UIView *view, BOOL hidden, NSString *label) {
    OITSLOG_RATED(1, @"APPLY", "APPLY-hide", 20, @"%@ %@ hidden %d -> %d (OITS)", label, OITSViewBrief(view), view.hidden, hidden);
    sOITSInternalChange = YES;
    view.hidden = hidden;
    sOITSInternalChange = NO;
}

// =====================================================================================
// MARK: Diagnostic event helpers (called from the diagnostic hooks)
// =====================================================================================

static void OITSDiagSetHidden(UIView *v, BOOL newValue) {
    if (sOITSInternalChange || !sOITSDiagEnabled || sOITSDiagLevel < 1) return;
    if (v.hidden == newValue) return;
    NSString *label = OITSLabelForView(v);
    BOOL interesting = ![label isEqualToString:@"other"];
    if (!interesting && sOITSDiagLevel < 2) return;
    NSString *key = [NSString stringWithFormat:@"SYS-hid-%@", label];
    OITSLOG_RATED(1, @"SYS-SET", key.UTF8String, 20, @"%@ %@ setHidden:%d (was %d) by=SYSTEM stack=%@ | %@",
                  label, OITSViewBrief(v), newValue, v.hidden, interesting ? OITSStackIfBudget() : @"-", OITSAncestorChain(v, 4));
}

static void OITSDiagSetAlpha(UIView *v, CGFloat newValue) {
    if (sOITSInternalChange || !sOITSDiagEnabled || sOITSDiagLevel < 1) return;
    if (fabs(newValue - v.alpha) < 0.001) return;
    NSString *label = OITSLabelForView(v);
    BOOL interesting = ![label isEqualToString:@"other"];
    if (!interesting && sOITSDiagLevel < 2) return;
    NSString *key = [NSString stringWithFormat:@"SYS-alpha-%@", label];
    OITSLOG_RATED(1, @"SYS-SET", key.UTF8String, 20, @"%@ %@ setAlpha:%.2f (was %.2f) by=SYSTEM stack=%@",
                  label, OITSViewBrief(v), newValue, v.alpha, interesting ? OITSStackIfBudget() : @"-");
}

static void OITSDiagSetTransform(UIView *v, CGAffineTransform t) {
    if (sOITSInternalChange || !sOITSDiagEnabled || sOITSDiagLevel < 1) return;
    if (CGAffineTransformEqualToTransform(t, v.transform)) return;
    NSString *label = OITSLabelForView(v);
    BOOL interesting = ![label isEqualToString:@"other"];
    if (!interesting && sOITSDiagLevel < 2) return;
    NSString *key = [NSString stringWithFormat:@"SYS-tf-%@", label];
    OITSLOG_RATED(1, @"SYS-SET", key.UTF8String, 20, @"%@ %@ setTransform {%@} (was {%@}) by=SYSTEM stack=%@",
                  label, OITSViewBrief(v), OITSTransformDesc(t), OITSTransformDesc(v.transform), interesting ? OITSStackIfBudget() : @"-");
}

static void OITSDiagMoveToWindow(UIView *v) {
    if (!sOITSDiagEnabled || sOITSDiagLevel < 1) return;
    NSString *label = OITSLabelForView(v);
    NSString *key = [NSString stringWithFormat:@"MOVE-%@", label];
    OITSLOG_RATED(1, @"MOVE", key.UTF8String, 20, @"%@ %@ didMoveToWindow -> %@ | %@", label, OITSViewBrief(v),
                  v.window ? OITSWindowDesc(v.window) : @"nil", OITSViewDetail(v));
}

static void OITSDiagRemoveFromSuperview(UIView *v) {
    if (!sOITSDiagEnabled || sOITSDiagLevel < 1) return;
    NSString *label = OITSLabelForView(v);
    BOOL interesting = ![label isEqualToString:@"other"];
    if (!interesting && sOITSDiagLevel < 2) return;
    NSString *key = [NSString stringWithFormat:@"REMOVE-%@", label];
    OITSLOG_RATED(1, @"REMOVE", key.UTF8String, 20, @"%@ %@ removeFromSuperview (superview=%@) stack=%@ | %@",
                  label, OITSViewBrief(v), OITSViewBrief(v.superview), interesting ? OITSStackIfBudget() : @"-", OITSViewDetail(v));
}

static void OITSDiagFrameEvent(UIView *v, NSString *label, CGRect incoming, BOOL hadTransform) {
    if (!sOITSDiagEnabled || sOITSDiagLevel < 2) return;
    NSString *key = [NSString stringWithFormat:@"SETFRAME-%@", label];
    OITSLOG_RATED(2, @"SETFRAME", key.UTF8String, 30, @"%@ %@ incoming=%@ hadNonIdentityTransform=%d tracked=%d naturalX=%@ frameNow=%@",
                  label, OITSViewBrief(v), OITSRectDesc(incoming), hadTransform,
                  ![[OITSLabelForView(v) lowercaseString] isEqualToString:@"other"],
                  (id)OITSNaturalXOfView(v) ?: @"nil", OITSRectDesc(v.frame));
}

static void OITSDiagNoteForegroundView(UIView *v) {
    if (!sDiagForegroundViews) sDiagForegroundViews = [NSHashTable weakObjectsHashTable];
    [sDiagForegroundViews addObject:v];
}

static void OITSDiagNoteStatusBarView(UIView *v) {
    if (!sDiagStatusBarViews) sDiagStatusBarViews = [NSHashTable weakObjectsHashTable];
    [sDiagStatusBarViews addObject:v];
}

static void OITSDiagLayoutEvent(UIView *fg) {
    OITSLOG_RATED(2, @"LAYOUT", "LAYOUT", 10, @"foreground %@ bounds=%@ frame=%@ tf={%@} hid=%d alpha=%.2f subviews=%@",
                  OITSViewBrief(fg), OITSRectDesc(fg.bounds), OITSRectDesc(fg.frame), OITSTransformDesc(fg.transform),
                  fg.hidden, fg.alpha, OITSSubviewSummary(fg));
}

static void OITSDiagSubviewChange(UIView *parent, UIView *sub, BOOL added) {
    OITSLOG_RATED(2, @"SUBVIEW", "SUBVIEW", 40, @"%@ %@ %@ | text=%@ frame=%@ hid=%d",
                  OITSViewBrief(parent), added ? @"+add" : @"-remove", OITSViewBrief(sub),
                  OITSTextOfView(sub) ?: @"-", OITSRectDesc(sub.frame), sub.hidden);
}

static void OITSNoteTracked(NSString *label, UIView *view, NSString *source) {
    objc_setAssociatedObject(view, kOITSTrackedAtKey, @(CACurrentMediaTime()), OBJC_ASSOCIATION_RETAIN);
    OITSLOG_RATED(1, @"TRACK", "TRACK", 40, @"%@ now tracked via %@ | %@ | ancestors: %@",
                  label, source, OITSViewDetail(view), OITSAncestorChain(view, 8));
}

// Logged once per view so the periodic discovery walk doesn't spam.
static void OITSLogSkipOnce(NSString *label, UIView *view, NSString *reason) {
    if (!sOITSDiagEnabled || sOITSDiagLevel < 2) return;
    if (objc_getAssociatedObject(view, kOITSSkipLoggedKey)) return;
    objc_setAssociatedObject(view, kOITSSkipLoggedKey, @YES, OBJC_ASSOCIATION_RETAIN);
    OITSLOG_RATED(2, @"SKIP", "SKIP", 20, @"%@ candidate NOT tracked: %@ | %@ | ancestors: %@",
                  label, reason, OITSViewDetail(view), OITSAncestorChain(view, 8));
}

// Logs whenever the tracked view's meaningful state changes (hidden/alpha/tx/frame/superview/window/text).
static void OITSLogStateIfChanged(UIView *v, NSString *label) {
    if (!sOITSDiagEnabled || sOITSDiagLevel < 1) return;
    NSString *text = OITSTextOfView(v);
    NSString *sig = [NSString stringWithFormat:@"win=%p sup=%p hid=%d a=%.2f tx=%.2f fx=%.2f fy=%.2f bw=%.2f bh=%.2f txt=%@",
                     v.window, v.superview, v.hidden, v.alpha, v.transform.tx,
                     v.frame.origin.x, v.frame.origin.y, v.bounds.size.width, v.bounds.size.height, text ?: @"-"];
    NSString *prev = objc_getAssociatedObject(v, kOITSLastSigKey);
    if ([prev isEqualToString:sig]) return;
    objc_setAssociatedObject(v, kOITSLastSigKey, sig, OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSString *key = [NSString stringWithFormat:@"STATE-%@", label];
    OITSLOG_RATED(1, @"STATE", key.UTF8String, 30, @"%@ %@ changed | was=[%@] now=[%@] | %@",
                  label, OITSViewBrief(v), prev ?: @"(first)", sig, OITSViewDetail(v));
}

// =====================================================================================
// MARK: Core repositioning logic (behavior unchanged from Stage 2; logging added)
// =====================================================================================

static CGFloat OITSClampedOffsetForWidth(CGFloat desiredOffset, CGFloat viewWidth, CGFloat parentScale) {
    // desiredOffset here is already a LOCAL-space value (see OITSReapplyTransform) -- the
    // bound it's clamped against must be the local-space screen width too, not the real one.
    CGFloat localScreenWidth = UIScreen.mainScreen.bounds.size.width / parentScale;
    CGFloat maxX = MAX(0.0, localScreenWidth - viewWidth);
    return MAX(0.0, MIN(desiredOffset, maxX));
}

static void OITSReapplyTransform(UIView *view, const void *naturalXKey, CGFloat desiredOffset, NSString *label) {
    NSNumber *naturalX = objc_getAssociatedObject(view, naturalXKey);
    if (!naturalX) return;
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    // Some status bar visual providers (e.g. the Split-family ones) lay content out for a
    // narrower reference width and stretch the whole _UIStatusBarForegroundView back out with
    // a uniform scale transform to fill the real screen. A child's own frame/transform is
    // always expressed in ITS superview's bounds space (i.e. pre-stretch), so a desiredOffset
    // meant as a real on-screen position has to be converted into that local space first --
    // otherwise it lands at desiredOffset * parentScale on screen, not at desiredOffset.
    // Under the standard (unscaled) provider parentScale is 1.0, so this is a no-op there.
    CGFloat parentScale = view.superview.transform.a;
    CGFloat rawParentScale = parentScale;
    if (!isfinite(parentScale) || parentScale < 0.01) parentScale = 1.0;
    CGFloat localDesiredOffset = desiredOffset / parentScale;
    CGFloat clampedOffset = OITSClampedOffsetForWidth(localDesiredOffset, view.bounds.size.width, parentScale);
    CGFloat delta = clampedOffset - naturalX.doubleValue;
    if (!isfinite(delta) || fabs(delta) > screenWidth) {
        OITSLOG_RATED(0, @"REFUSED", "REFUSED", 5,
                      @"%@ bad delta=%.1f naturalX=%.1f desiredOffset=%.1f localDesired=%.1f clamped=%.1f parentScale=%.3f (raw %.3f) viewW=%.2f | %@",
                      label, delta, naturalX.doubleValue, desiredOffset, localDesiredOffset, clampedOffset,
                      parentScale, rawParentScale, view.bounds.size.width, OITSViewDetail(view));
        return;
    }
    CGFloat currentTx = view.transform.tx;
    if (fabs(currentTx - delta) > kOITSDriftToleranceInPoints) {
        OITSSetTransformInternal(view, CGAffineTransformMakeTranslation(delta, 0));
        OITSLOG_RATED(1, @"APPLY", "APPLY", 40,
                      @"%@ %@ tx %.2f -> %.2f | naturalX=%.2f desired=%.2f localDesired=%.2f clamped=%.2f parentScale=%.4f (raw %.4f) viewW=%.2f sup=%@",
                      label, OITSViewBrief(view), currentTx, delta, naturalX.doubleValue, desiredOffset, localDesiredOffset,
                      clampedOffset, parentScale, rawParentScale, view.bounds.size.width, OITSViewBrief(view.superview));
    }
}

// Also clears any hide state -- if reposition gets disabled while a view
// was hidden, this guarantees it becomes visible again rather than staying
// invisible with nothing left tracking it.
static void OITSResetAndForgetTrackedViews(NSHashTable<UIView *> *trackedSet, const void *naturalXKey, NSString *label) {
    if (!trackedSet) return;
    NSUInteger resetCount = 0;
    for (UIView *view in trackedSet) {
        if (!CGAffineTransformIsIdentity(view.transform)) {
            OITSSetTransformInternal(view, CGAffineTransformIdentity);
            resetCount++;
        }
        if (view.hidden) OITSSetHiddenInternal(view, NO, label);
        objc_setAssociatedObject(view, naturalXKey, nil, OBJC_ASSOCIATION_RETAIN);
    }
    [trackedSet removeAllObjects];
    OITSDebugLog(@"Reset-on-disable: %@ -- reset %lu transform(s), forgot all tracking", label, (unsigned long)resetCount);
}

// Under some status bar visual providers the clock doesn't render near screen-center, so the
// usual center check fails to identify it. But when it's the ONLY _UIStatusBarStringView
// among its own siblings, there's no ambiguity to resolve -- it must be the clock, since
// carrier text and network type would only ever be candidates when there's more than one.
static BOOL OITSIsOnlyStringViewSibling(UIView *view) {
    UIView *superview = view.superview;
    if (!superview || !sStatusBarStringViewClass) return NO;
    NSUInteger matchCount = 0;
    for (UIView *sibling in superview.subviews) {
        if ([sibling isKindOfClass:sStatusBarStringViewClass]) matchCount++;
        if (matchCount > 1) return NO;
    }
    return matchCount == 1;
}

static void OITSFindCenteredStringViews(UIView *view, CGFloat screenCenterX, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    if (sStatusBarStringViewClass && [view isKindOfClass:sStatusBarStringViewClass]) {
        if (![sTrackedClockViews containsObject:view]) {
            NSNumber *naturalX = objc_getAssociatedObject(view, kOITSClockNaturalXKey);
            if (naturalX) {
                [sTrackedClockViews addObject:view];
                OITSNoteTracked(@"clock", view, @"discovery(existing naturalX)");
            } else if (CGAffineTransformIsIdentity(view.transform)) {
                CGFloat centerX = CGRectGetMidX(view.frame);
                BOOL isNearCenter = fabs(centerX - screenCenterX) <= kOITSCenterToleranceInPoints;
                BOOL onlySibling = OITSIsOnlyStringViewSibling(view);
                if (isNearCenter || onlySibling) {
                    objc_setAssociatedObject(view, kOITSClockNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
                    [sTrackedClockViews addObject:view];
                    OITSNoteTracked(@"clock", view, [NSString stringWithFormat:@"discovery(nearCenter=%d onlySibling=%d centerX=%.2f screenCenterX=%.2f)",
                                                     isNearCenter, onlySibling, centerX, screenCenterX]);
                } else {
                    OITSLogSkipOnce(@"clock", view, [NSString stringWithFormat:@"not near center and not only string sibling (centerX=%.2f screenCenterX=%.2f)", centerX, screenCenterX]);
                }
            } else {
                OITSLogSkipOnce(@"clock", view, @"non-identity transform and no naturalX recorded");
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindCenteredStringViews(subview, screenCenterX, depth + 1);
    }
}

static void OITSFindBatteryViews(UIView *view, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    BOOL isBatteryView = (sStaticBatteryViewClass && [view isKindOfClass:sStaticBatteryViewClass]) ||
                         (sBatteryViewAltClass && [view isKindOfClass:sBatteryViewAltClass]);
    if (isBatteryView) {
        if (![sTrackedBatteryViews containsObject:view]) {
            NSNumber *naturalX = objc_getAssociatedObject(view, kOITSBatteryNaturalXKey);
            if (naturalX) {
                [sTrackedBatteryViews addObject:view];
                OITSNoteTracked(@"battery", view, @"discovery(existing naturalX)");
            } else if (CGAffineTransformIsIdentity(view.transform)) {
                objc_setAssociatedObject(view, kOITSBatteryNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
                [sTrackedBatteryViews addObject:view];
                OITSNoteTracked(@"battery", view, @"discovery(new naturalX)");
            } else {
                OITSLogSkipOnce(@"battery", view, @"non-identity transform and no naturalX recorded");
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindBatteryViews(subview, depth + 1);
    }
}

static void OITSFindWifiViews(UIView *view, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    if (sStatusBarWifiSignalViewClass && [view isKindOfClass:sStatusBarWifiSignalViewClass]) {
        if (![sTrackedWifiViews containsObject:view]) {
            NSNumber *naturalX = objc_getAssociatedObject(view, kOITSWifiNaturalXKey);
            if (naturalX) {
                [sTrackedWifiViews addObject:view];
                OITSNoteTracked(@"wifi", view, @"discovery(existing naturalX)");
            } else if (CGAffineTransformIsIdentity(view.transform)) {
                objc_setAssociatedObject(view, kOITSWifiNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
                [sTrackedWifiViews addObject:view];
                OITSNoteTracked(@"wifi", view, @"discovery(new naturalX)");
            } else {
                OITSLogSkipOnce(@"wifi", view, @"non-identity transform and no naturalX recorded");
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindWifiViews(subview, depth + 1);
    }
}

static BOOL OITSClassNameLooksLikeCellularSignalView(UIView *view) {
    NSString *className = NSStringFromClass([view class]);
    return [className containsString:@"Cellular"] && [className hasSuffix:@"SignalView"];
}

static void OITSFindCellularViews(UIView *view, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    if (OITSClassNameLooksLikeCellularSignalView(view)) {
        if (![sTrackedCellularViews containsObject:view]) {
            NSNumber *naturalX = objc_getAssociatedObject(view, kOITSCellularNaturalXKey);
            if (naturalX) {
                [sTrackedCellularViews addObject:view];
                OITSNoteTracked(@"cellular", view, @"discovery(existing naturalX)");
            } else if (CGAffineTransformIsIdentity(view.transform)) {
                objc_setAssociatedObject(view, kOITSCellularNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
                [sTrackedCellularViews addObject:view];
                OITSNoteTracked(@"cellular", view, @"discovery(new naturalX)");
            } else {
                OITSLogSkipOnce(@"cellular", view, @"non-identity transform and no naturalX recorded");
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindCellularViews(subview, depth + 1);
    }
}

// Network type ("LTE", "5G", etc.) turns out to always render via this dedicated class, not as
// a generic leftover string view the way OITSClassifyCarrierAndNetworkChildren below assumed --
// that assumption was never correct, on any provider, so this replaces it outright.
static void OITSFindNetworkTypeViews(UIView *view, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    if (sCellularNetworkTypeViewClass && [view isKindOfClass:sCellularNetworkTypeViewClass]) {
        if (![sTrackedNetworkTypeViews containsObject:view]) {
            NSNumber *naturalX = objc_getAssociatedObject(view, kOITSNetworkTypeNaturalXKey);
            if (naturalX) {
                [sTrackedNetworkTypeViews addObject:view];
                OITSNoteTracked(@"network", view, @"discovery(existing naturalX)");
            } else if (CGAffineTransformIsIdentity(view.transform)) {
                objc_setAssociatedObject(view, kOITSNetworkTypeNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
                [sTrackedNetworkTypeViews addObject:view];
                OITSNoteTracked(@"network", view, @"discovery(new naturalX)");
            } else {
                OITSLogSkipOnce(@"network", view, @"non-identity transform and no naturalX recorded");
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindNetworkTypeViews(subview, depth + 1);
    }
}

static void OITSClassifyCarrierAndNetworkChildren(UIView *foregroundView, CGFloat screenCenterX) {
    NSMutableArray<UIView *> *leftoverStringViews = [NSMutableArray array];
    for (UIView *subview in foregroundView.subviews) {
        if (!sStatusBarStringViewClass || ![subview isKindOfClass:sStatusBarStringViewClass]) continue;
        if ([sTrackedCarrierTextViews containsObject:subview]) continue;
        if ([sTrackedClockViews containsObject:subview]) continue;
        CGFloat centerX = CGRectGetMidX(subview.frame);
        if (fabs(centerX - screenCenterX) <= kOITSCenterToleranceInPoints) continue;
        if (!CGAffineTransformIsIdentity(subview.transform)) continue;
        [leftoverStringViews addObject:subview];
    }
    if (leftoverStringViews.count == 0) return;

    [leftoverStringViews sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = CGRectGetMinX(a.frame);
        CGFloat bx = CGRectGetMinX(b.frame);
        if (ax < bx) return NSOrderedAscending;
        if (ax > bx) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    if (leftoverStringViews.count > 0 && sCarrierTextRepositionEnabled) {
        UIView *view = leftoverStringViews[0];
        objc_setAssociatedObject(view, kOITSCarrierTextNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
        [sTrackedCarrierTextViews addObject:view];
        OITSNoteTracked(@"carrier", view, [NSString stringWithFormat:@"leftover-string heuristic (%lu candidate(s) in foreground %@)",
                                           (unsigned long)leftoverStringViews.count, OITSViewBrief(foregroundView)]);
    }
}

static void OITSWalkForForegroundViews(UIView *view, CGFloat screenCenterX, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    static Class foregroundViewClass;
    if (!foregroundViewClass) foregroundViewClass = NSClassFromString(@"_UIStatusBarForegroundView");
    if (foregroundViewClass && [view isKindOfClass:foregroundViewClass]) {
        OITSDiagNoteForegroundView(view);
        OITSClassifyCarrierAndNetworkChildren(view, screenCenterX);
    }
    for (UIView *subview in view.subviews) {
        OITSWalkForForegroundViews(subview, screenCenterX, depth + 1);
    }
}

static NSMutableOrderedSet<UIWindow *> *OITSCollectWindows(void) {
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    return windows;
}

// =====================================================================================
// MARK: Full status bar hierarchy dump + visibility watchdog
// =====================================================================================

static void OITSDumpSubtree(UIView *view, NSUInteger depth, BOOL inStatusBar, NSUInteger *linesLeft) {
    if (!view || depth > kOITSMaxTraverseDepth || *linesLeft == 0) return;
    NSString *cls = NSStringFromClass([view class]);
    BOOL isRoot = [cls containsString:@"StatusBar"];
    BOOL nowIn = inStatusBar || isRoot;
    if (nowIn) {
        if (isRoot && !inStatusBar) {
            OITSLogImpl(@"DUMP", @"ROOT %@ ancestors: %@", OITSViewBrief(view), OITSAncestorChain(view, 12));
        }
        (*linesLeft)--;
        NSString *indent = [@"" stringByPaddingToLength:MIN(depth, (NSUInteger)30) * 2 withString:@" " startingAtIndex:0];
        OITSLogImpl(@"DUMP", @"%@[%@] %@ subviews=%lu vis=%@", indent, OITSLabelForView(view), OITSViewDetail(view),
                    (unsigned long)view.subviews.count, OITSVisibilityProblem(view) ?: @"visible");
    }
    for (UIView *sub in view.subviews) {
        OITSDumpSubtree(sub, depth + 1, nowIn, linesLeft);
    }
}

static void OITSDumpTrackedSummary(NSHashTable<UIView *> *set, NSString *label) {
    for (UIView *v in set) {
        OITSLogImpl(@"DUMP", @"TRACKED %@ vis=%@ | %@", label, OITSVisibilityProblem(v) ?: @"visible", OITSViewDetail(v));
    }
}

static void OITSDumpStatusBarHierarchy(NSString *reason) {
    if (!sSpringBoardIsReadyForWindowAccess) {
        OITSLogImpl(@"DUMP", @"requested (%@) before SpringBoard ready; ignored", reason);
        return;
    }
    OITSLogImpl(@"DUMP", @"===== BEGIN reason=%@ tick=%lu =====", reason, (unsigned long)sOITSCurrentTick);
    NSMutableOrderedSet<UIWindow *> *windows = OITSCollectWindows();
    NSUInteger index = 0;
    for (UIWindow *w in windows) {
        OITSLogImpl(@"DUMP", @"window[%lu] %@ subviews=%lu", (unsigned long)index++, OITSWindowDesc(w), (unsigned long)w.subviews.count);
    }
    NSUInteger linesLeft = kOITSDumpMaxLines;
    for (UIWindow *w in windows) {
        OITSDumpSubtree(w, 0, NO, &linesLeft);
    }
    OITSDumpTrackedSummary(sTrackedClockViews, @"clock");
    OITSDumpTrackedSummary(sTrackedBatteryViews, @"battery");
    OITSDumpTrackedSummary(sTrackedWifiViews, @"wifi");
    OITSDumpTrackedSummary(sTrackedCellularViews, @"cellular");
    OITSDumpTrackedSummary(sTrackedCarrierTextViews, @"carrier");
    OITSDumpTrackedSummary(sTrackedNetworkTypeViews, @"network");
    OITSLogImpl(@"DUMP", @"===== END (lines left in budget: %lu) =====", (unsigned long)linesLeft);
}

static void OITSEvaluateViewVisibility(UIView *v, NSString *label) {
    NSString *problem = OITSVisibilityProblem(v);
    NSString *now = problem ?: @"visible";
    NSString *prev = objc_getAssociatedObject(v, kOITSLastVisKey);
    if ([prev isEqualToString:now]) return;
    objc_setAssociatedObject(v, kOITSLastVisKey, now, OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSString *key = [NSString stringWithFormat:@"VIS-%@", label];
    OITSLOG_RATED(1, @"VIS", key.UTF8String, 20, @"%@ %@ visibility: %@ -> %@ | %@ | ancestors: %@",
                  label, OITSViewBrief(v), prev ?: @"(first)", now, OITSViewDetail(v), OITSAncestorChain(v, 8));
    if (problem && ![problem hasPrefix:@"partial"] && [prev isEqualToString:@"visible"] && sOITSAutoDumpCount < kOITSMaxAutoDumps) {
        sOITSAutoDumpCount++;
        OITSDumpStatusBarHierarchy([NSString stringWithFormat:@"auto #%lu: %@ %@ became invisible (%@)",
                                    (unsigned long)sOITSAutoDumpCount, label, OITSViewBrief(v), problem]);
    }
}

static void OITSEvalSet(NSHashTable<UIView *> *set, NSString *label, BOOL logState) {
    for (UIView *v in set) {
        OITSEvaluateViewVisibility(v, label);
        if (logState) OITSLogStateIfChanged(v, label);
    }
}

static void OITSDiagEvaluateAll(void) {
    if (!sOITSDiagEnabled || sOITSDiagLevel < 1 || !sSpringBoardIsReadyForWindowAccess) return;
    OITSEvalSet(sTrackedClockViews, @"clock", NO);
    OITSEvalSet(sTrackedBatteryViews, @"battery", NO);
    OITSEvalSet(sTrackedWifiViews, @"wifi", NO);
    OITSEvalSet(sTrackedCellularViews, @"cellular", NO);
    OITSEvalSet(sTrackedCarrierTextViews, @"carrier", NO);
    OITSEvalSet(sTrackedNetworkTypeViews, @"network", NO);
    OITSEvalSet(sDiagForegroundViews, @"foreground", YES);
    OITSEvalSet(sDiagStatusBarViews, @"statusbar", YES);
}

// =====================================================================================
// MARK: Discovery
// =====================================================================================

static void OITSDiscoverAllTargets(void) {
    if (!UIApplication.sharedApplication) return;
    if (!sTrackedClockViews) sTrackedClockViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedBatteryViews) sTrackedBatteryViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedWifiViews) sTrackedWifiViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedCellularViews) sTrackedCellularViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedCarrierTextViews) sTrackedCarrierTextViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedNetworkTypeViews) sTrackedNetworkTypeViews = [NSHashTable weakObjectsHashTable];
    if (!sStatusBarStringViewClass) sStatusBarStringViewClass = NSClassFromString(@"_UIStatusBarStringView");
    if (!sStaticBatteryViewClass) sStaticBatteryViewClass = NSClassFromString(@"_UIStaticBatteryView");
    if (!sBatteryViewAltClass) sBatteryViewAltClass = NSClassFromString(@"_UIBatteryView");
    if (!sStatusBarWifiSignalViewClass) sStatusBarWifiSignalViewClass = NSClassFromString(@"_UIStatusBarWifiSignalView");
    if (!sCellularNetworkTypeViewClass) sCellularNetworkTypeViewClass = NSClassFromString(@"_UIStatusBarCellularNetworkTypeView");

    NSMutableOrderedSet<UIWindow *> *windows = OITSCollectWindows();

    CGFloat screenCenterX = UIScreen.mainScreen.bounds.size.width * 0.5;
    for (UIWindow *window in windows) {
        if (sClockRepositionEnabled) OITSFindCenteredStringViews(window, screenCenterX, 0);
        if (sBatteryRepositionEnabled) OITSFindBatteryViews(window, 0);
        if (sWifiRepositionEnabled) OITSFindWifiViews(window, 0);
        if (sCellularRepositionEnabled) OITSFindCellularViews(window, 0);
        if (sNetworkTypeRepositionEnabled) OITSFindNetworkTypeViews(window, 0);
        if (sCarrierTextRepositionEnabled) {
            OITSWalkForForegroundViews(window, screenCenterX, 0);
        }
    }

    if (sOITSDiagEnabled && sOITSDiagLevel >= 1) {
        NSString *sig = [NSString stringWithFormat:@"windows=%lu tracked: clock=%lu battery=%lu wifi=%lu cellular=%lu carrier=%lu network=%lu",
                         (unsigned long)windows.count, (unsigned long)sTrackedClockViews.count, (unsigned long)sTrackedBatteryViews.count,
                         (unsigned long)sTrackedWifiViews.count, (unsigned long)sTrackedCellularViews.count,
                         (unsigned long)sTrackedCarrierTextViews.count, (unsigned long)sTrackedNetworkTypeViews.count];
        if (![sig isEqualToString:sOITSLastDiscoverySig]) {
            NSString *previous = sOITSLastDiscoverySig;
            sOITSLastDiscoverySig = sig;
            NSMutableArray<NSString *> *windowDescs = [NSMutableArray array];
            for (UIWindow *w in windows) [windowDescs addObject:OITSWindowDesc(w)];
            OITSLogImpl(@"DISCOVER", @"changed: %@ (was: %@) | windows: %@", sig, previous ?: @"(none)", [windowDescs componentsJoinedByString:@" || "]);
        }
    }
}

// =====================================================================================
// MARK: Enforcer
// =====================================================================================

static void OITSCorrectSet(NSHashTable<UIView *> *set, BOOL hide, const void *naturalKey, CGFloat offset, NSString *label) {
    for (UIView *view in set) {
        if (!view.window) continue;
        if (hide) {
            if (!view.hidden) OITSSetHiddenInternal(view, YES, label);
        } else {
            if (view.hidden) OITSSetHiddenInternal(view, NO, label);
            OITSReapplyTransform(view, naturalKey, offset, label);
        }
        OITSLogStateIfChanged(view, label);
    }
}

@interface OITSPositionEnforcer : NSObject
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSUInteger tickCounter;
@property (nonatomic, assign) CFTimeInterval lastTickMono;
@end

@implementation OITSPositionEnforcer

- (void)start {
    if (self.displayLink) return;
    if (!sSpringBoardIsReadyForWindowAccess) return;
    self.tickCounter = 0;
    self.lastTickMono = 0;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    OITSLOG(1, @"ENFORCER", @"display link STARTED");
}

- (void)stop {
    if (self.displayLink) OITSLOG(1, @"ENFORCER", @"display link STOPPED after %lu tick(s)", (unsigned long)self.tickCounter);
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (BOOL)cleanDeadViewsFromSet:(NSHashTable<UIView *> *)trackedSet label:(NSString *)label {
    if (!trackedSet) return NO;
    BOOL anyRemoved = NO;
    NSMutableArray<UIView *> *dead = [NSMutableArray array];
    for (UIView *view in trackedSet) {
        if (!view.window) {
            [dead addObject:view];
            anyRemoved = YES;
        }
    }
    for (UIView *deadView in dead) {
        NSNumber *trackedAt = objc_getAssociatedObject(deadView, kOITSTrackedAtKey);
        OITSLOG_RATED(1, @"DEAD", "DEAD", 20, @"%@ view left its window (tracked for %.1fs): %@ | lastSig=[%@] | ancestors: %@",
                      label, trackedAt ? CACurrentMediaTime() - trackedAt.doubleValue : -1.0, OITSViewDetail(deadView),
                      objc_getAssociatedObject(deadView, kOITSLastSigKey) ?: @"-", OITSAncestorChain(deadView, 6));
        [trackedSet removeObject:deadView];
    }
    if (anyRemoved && sRemovalEventLogCount < kOITSMaxRemovalEventLogs) {
        sRemovalEventLogCount++;
        OITSDebugLog(@"[event #%lu] tick=%lu: removed %lu dead %@ view(s)",
                    (unsigned long)sRemovalEventLogCount, (unsigned long)self.tickCounter,
                    (unsigned long)dead.count, label);
    }
    return anyRemoved;
}

- (void)correctAllTrackedViews {
    BOOL anyRemoved = NO;
    if (sClockRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedClockViews label:@"clock"];
    if (sBatteryRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedBatteryViews label:@"battery"];
    if (sWifiRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedWifiViews label:@"wifi"];
    if (sCellularRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedCellularViews label:@"cellular"];
    if (sCarrierTextRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedCarrierTextViews label:@"carrierText"];
    if (sNetworkTypeRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedNetworkTypeViews label:@"networkType"];

    if (anyRemoved) {
        OITSDiscoverAllTargets();
        if (sRemovalEventLogCount <= kOITSMaxRemovalEventLogs) {
            OITSDebugLog(@"after rediscovery: tracking %lu clock, %lu battery, %lu wifi, %lu cellular, %lu carrier, %lu network",
                        (unsigned long)sTrackedClockViews.count, (unsigned long)sTrackedBatteryViews.count,
                        (unsigned long)sTrackedWifiViews.count, (unsigned long)sTrackedCellularViews.count,
                        (unsigned long)sTrackedCarrierTextViews.count, (unsigned long)sTrackedNetworkTypeViews.count);
        }
    }

    if (sClockRepositionEnabled) OITSCorrectSet(sTrackedClockViews, sClockHidden, kOITSClockNaturalXKey, sClockLeadingOffset, @"clock");
    if (sBatteryRepositionEnabled) OITSCorrectSet(sTrackedBatteryViews, sBatteryHidden, kOITSBatteryNaturalXKey, sBatteryLeadingOffset, @"battery");
    if (sWifiRepositionEnabled) OITSCorrectSet(sTrackedWifiViews, sWifiHidden, kOITSWifiNaturalXKey, sWifiLeadingOffset, @"wifi");
    if (sCellularRepositionEnabled) OITSCorrectSet(sTrackedCellularViews, sCellularHidden, kOITSCellularNaturalXKey, sCellularLeadingOffset, @"cellular");
    if (sCarrierTextRepositionEnabled) OITSCorrectSet(sTrackedCarrierTextViews, sCarrierTextHidden, kOITSCarrierTextNaturalXKey, sCarrierTextLeadingOffset, @"carrier");
    if (sNetworkTypeRepositionEnabled) OITSCorrectSet(sTrackedNetworkTypeViews, sNetworkTypeHidden, kOITSNetworkTypeNaturalXKey, sNetworkTypeLeadingOffset, @"network");
}

- (void)tick:(__unused CADisplayLink *)link {
    if (!sSpringBoardIsReadyForWindowAccess) return;
    if (!sClockRepositionEnabled && !sBatteryRepositionEnabled && !sWifiRepositionEnabled &&
        !sCellularRepositionEnabled && !sCarrierTextRepositionEnabled && !sNetworkTypeRepositionEnabled) return;
    CFTimeInterval t0 = CACurrentMediaTime();
    self.tickCounter++;
    sOITSCurrentTick = self.tickCounter;
    if (self.lastTickMono > 0.0 && (t0 - self.lastTickMono) > 0.1) {
        OITSLOG_RATED(1, @"TICKGAP", "TICKGAP", 5, @"%.0f ms since previous tick (main thread blocked, or display link paused e.g. screen off/app transition)",
                      (t0 - self.lastTickMono) * 1000.0);
    }
    self.lastTickMono = t0;
    if (self.tickCounter == 1 || self.tickCounter % kOITSDiscoveryIntervalTicks == 0) {
        OITSDiscoverAllTargets();
    }
    [self correctAllTrackedViews];
    if (self.tickCounter % 6 == 0) OITSDiagEvaluateAll();
    CFTimeInterval elapsed = CACurrentMediaTime() - t0;
    if (elapsed > 0.004) {
        OITSLOG_RATED(1, @"TICKSLOW", "TICKSLOW", 5, @"tick #%lu took %.2f ms", (unsigned long)self.tickCounter, elapsed * 1000.0);
    }
}

@end

static OITSPositionEnforcer *sPositionEnforcer;

// =====================================================================================
// MARK: Heartbeat, trigger-file dump, main-thread stall detector
// =====================================================================================

static dispatch_source_t sOITSDiagTimer;
static CFTimeInterval sOITSLastTimerMono = 0;
static NSUInteger sOITSTimerCount = 0;
static struct timespec sOITSLastTriggerMtime;

static void OITSHeartbeatSet(NSHashTable<UIView *> *set, NSString *label, const void *naturalKey, CGFloat offset, BOOL hideFlag) {
    for (UIView *v in set) {
        NSNumber *natural = objc_getAssociatedObject(v, naturalKey);
        OITSLOG(2, @"HB", @"  %@ %@ tx=%.2f naturalX=%@ desired=%.1f hidePref=%d parentScale=%.4f vis=%@ text=%@ win=%p",
                label, OITSViewBrief(v), v.transform.tx, natural ? (id)natural : (id)@"nil", offset, hideFlag,
                v.superview.transform.a, OITSVisibilityProblem(v) ?: @"visible", OITSTextOfView(v) ?: @"-", v.window);
    }
}

static void OITSWarnIfUntracked(BOOL enabled, NSHashTable<UIView *> *set, NSString *label) {
    if (enabled && set.count == 0) {
        OITSLOG_RATED(1, @"WARN", "WARN-untracked", 4, @"%@ reposition is ENABLED but nothing is tracked", label);
    }
}

static void OITSHeartbeat(void) {
    if (!sOITSDiagEnabled || sOITSDiagLevel < 1 || !sSpringBoardIsReadyForWindowAccess) return;
    OITSLogImpl(@"HB", @"enforcer=%d ticks=%lu | enabled c%d b%d w%d s%d t%d n%d | tracked c%lu b%lu w%lu s%lu t%lu n%lu | foreground=%lu statusbar=%lu",
                sPositionEnforcer.displayLink != nil, (unsigned long)sPositionEnforcer.tickCounter,
                sClockRepositionEnabled, sBatteryRepositionEnabled, sWifiRepositionEnabled,
                sCellularRepositionEnabled, sCarrierTextRepositionEnabled, sNetworkTypeRepositionEnabled,
                (unsigned long)sTrackedClockViews.count, (unsigned long)sTrackedBatteryViews.count,
                (unsigned long)sTrackedWifiViews.count, (unsigned long)sTrackedCellularViews.count,
                (unsigned long)sTrackedCarrierTextViews.count, (unsigned long)sTrackedNetworkTypeViews.count,
                (unsigned long)sDiagForegroundViews.count, (unsigned long)sDiagStatusBarViews.count);
    OITSHeartbeatSet(sTrackedClockViews, @"clock", kOITSClockNaturalXKey, sClockLeadingOffset, sClockHidden);
    OITSHeartbeatSet(sTrackedBatteryViews, @"battery", kOITSBatteryNaturalXKey, sBatteryLeadingOffset, sBatteryHidden);
    OITSHeartbeatSet(sTrackedWifiViews, @"wifi", kOITSWifiNaturalXKey, sWifiLeadingOffset, sWifiHidden);
    OITSHeartbeatSet(sTrackedCellularViews, @"cellular", kOITSCellularNaturalXKey, sCellularLeadingOffset, sCellularHidden);
    OITSHeartbeatSet(sTrackedCarrierTextViews, @"carrier", kOITSCarrierTextNaturalXKey, sCarrierTextLeadingOffset, sCarrierTextHidden);
    OITSHeartbeatSet(sTrackedNetworkTypeViews, @"network", kOITSNetworkTypeNaturalXKey, sNetworkTypeLeadingOffset, sNetworkTypeHidden);
    OITSWarnIfUntracked(sClockRepositionEnabled, sTrackedClockViews, @"clock");
    OITSWarnIfUntracked(sBatteryRepositionEnabled, sTrackedBatteryViews, @"battery");
    OITSWarnIfUntracked(sWifiRepositionEnabled, sTrackedWifiViews, @"wifi");
    OITSWarnIfUntracked(sCellularRepositionEnabled, sTrackedCellularViews, @"cellular");
    OITSWarnIfUntracked(sNetworkTypeRepositionEnabled, sTrackedNetworkTypeViews, @"network");
}

static void OITSPrimeTriggerFile(void) {
    struct stat st;
    if (stat([kOITSDumpTriggerPath fileSystemRepresentation], &st) == 0) {
        sOITSLastTriggerMtime = st.st_mtimespec;
    } else {
        sOITSLastTriggerMtime.tv_sec = 0;
        sOITSLastTriggerMtime.tv_nsec = 0;
    }
}

static void OITSDiagTimerFired(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (sOITSLastTimerMono > 0.0 && (now - sOITSLastTimerMono) > 2.5) {
        OITSLogImpl(@"MAINSTALL", @"1s main-queue timer fired %.2fs after the previous one -> main thread was blocked/starved for ~%.2fs",
                    now - sOITSLastTimerMono, now - sOITSLastTimerMono - 1.0);
    }
    sOITSLastTimerMono = now;
    sOITSTimerCount++;
    if (!sOITSDiagEnabled) return;

    struct stat st;
    if (stat([kOITSDumpTriggerPath fileSystemRepresentation], &st) == 0) {
        if (st.st_mtimespec.tv_sec != sOITSLastTriggerMtime.tv_sec || st.st_mtimespec.tv_nsec != sOITSLastTriggerMtime.tv_nsec) {
            sOITSLastTriggerMtime = st.st_mtimespec;
            OITSDumpStatusBarHierarchy(@"trigger file touched");
        }
    }
    OITSDiagEvaluateAll();
    if (sOITSTimerCount % kOITSHeartbeatSeconds == 0) OITSHeartbeat();
}

static void OITSStartDiagnosticsTimer(void) {
    if (sOITSDiagTimer) return;
    OITSPrimeTriggerFile();
    sOITSDiagTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(sOITSDiagTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(sOITSDiagTimer, ^{
        OITSDiagTimerFired();
    });
    dispatch_resume(sOITSDiagTimer);
}

// =====================================================================================
// MARK: Enforcer state + preferences
// =====================================================================================

static void OITSUpdateEnforcerState(void) {
    if (!sSpringBoardIsReadyForWindowAccess) return;
    if (!sPositionEnforcer) sPositionEnforcer = [OITSPositionEnforcer new];
    if (sClockRepositionEnabled || sBatteryRepositionEnabled || sWifiRepositionEnabled ||
        sCellularRepositionEnabled || sCarrierTextRepositionEnabled || sNetworkTypeRepositionEnabled) {
        [sPositionEnforcer start];
    } else {
        [sPositionEnforcer stop];
    }
}

static NSString *sOITSLastPrefsSummary;

static void OITSReloadPreferences(void) {
    if (!sOITSPreferences) {
        sOITSPreferences = [OITPreferences preferencesWithDomain:kOITSPrefsDomain];
    } else {
        [sOITSPreferences reload];
    }

    BOOL newClockEnabled = [sOITSPreferences boolForKey:@"ClockRepositionEnabled" default:NO];
    BOOL newBatteryEnabled = [sOITSPreferences boolForKey:@"BatteryRepositionEnabled" default:NO];
    BOOL newWifiEnabled = [sOITSPreferences boolForKey:@"WifiSignalRepositionEnabled" default:NO];
    BOOL newCellularEnabled = [sOITSPreferences boolForKey:@"CellularSignalRepositionEnabled" default:NO];
    BOOL newCarrierTextEnabled = [sOITSPreferences boolForKey:@"CarrierTextRepositionEnabled" default:NO];
    BOOL newNetworkTypeEnabled = [sOITSPreferences boolForKey:@"NetworkTypeRepositionEnabled" default:NO];

    sOITSDiagEnabled = [sOITSPreferences boolForKey:@"DiagnosticsEnabled" default:YES];
    NSInteger level = (NSInteger)[sOITSPreferences floatForKey:@"DiagnosticsLevel" default:0.0];
    sOITSDiagLevel = MAX(0, MIN(2, level));

    if (sPreviousClockEnabled && !newClockEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedClockViews, kOITSClockNaturalXKey, @"clock");
    }
    if (sPreviousBatteryEnabled && !newBatteryEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedBatteryViews, kOITSBatteryNaturalXKey, @"battery");
    }
    if (sPreviousWifiEnabled && !newWifiEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedWifiViews, kOITSWifiNaturalXKey, @"wifi");
    }
    if (sPreviousCellularEnabled && !newCellularEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedCellularViews, kOITSCellularNaturalXKey, @"cellular");
    }
    if (sPreviousCarrierTextEnabled && !newCarrierTextEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedCarrierTextViews, kOITSCarrierTextNaturalXKey, @"carrierText");
    }
    if (sPreviousNetworkTypeEnabled && !newNetworkTypeEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedNetworkTypeViews, kOITSNetworkTypeNaturalXKey, @"networkType");
    }

    // FIX (diag build): these were never assigned before, so the reset-on-disable blocks above
    // could never fire. Assigned only after the checks so they compare against the old state.
    sPreviousClockEnabled = newClockEnabled;
    sPreviousBatteryEnabled = newBatteryEnabled;
    sPreviousWifiEnabled = newWifiEnabled;
    sPreviousCellularEnabled = newCellularEnabled;
    sPreviousCarrierTextEnabled = newCarrierTextEnabled;
    sPreviousNetworkTypeEnabled = newNetworkTypeEnabled;

    sClockRepositionEnabled = newClockEnabled;
    sBatteryRepositionEnabled = newBatteryEnabled;
    sWifiRepositionEnabled = newWifiEnabled;
    sCellularRepositionEnabled = newCellularEnabled;
    sCarrierTextRepositionEnabled = newCarrierTextEnabled;
    sNetworkTypeRepositionEnabled = newNetworkTypeEnabled;
    sClockLeadingOffset = [sOITSPreferences floatForKey:@"ClockLeadingOffset" default:16.0];
    sBatteryLeadingOffset = [sOITSPreferences floatForKey:@"BatteryLeadingOffset" default:384.0];
    sWifiLeadingOffset = [sOITSPreferences floatForKey:@"WifiSignalLeadingOffset" default:76.0];
    sCellularLeadingOffset = [sOITSPreferences floatForKey:@"CellularSignalLeadingOffset" default:6.0];
    sCarrierTextLeadingOffset = [sOITSPreferences floatForKey:@"CarrierTextLeadingOffset" default:28.0];
    sNetworkTypeLeadingOffset = [sOITSPreferences floatForKey:@"NetworkTypeLeadingOffset" default:80.0];
    sClockHidden = [sOITSPreferences boolForKey:@"ClockHidden" default:NO];
    sBatteryHidden = [sOITSPreferences boolForKey:@"BatteryHidden" default:NO];
    sWifiHidden = [sOITSPreferences boolForKey:@"WifiSignalHidden" default:NO];
    sCellularHidden = [sOITSPreferences boolForKey:@"CellularSignalHidden" default:NO];
    sCarrierTextHidden = [sOITSPreferences boolForKey:@"CarrierTextHidden" default:NO];
    sNetworkTypeHidden = [sOITSPreferences boolForKey:@"NetworkTypeHidden" default:NO];

    NSString *summary = [NSString stringWithFormat:
        @"clock[en=%d off=%.1f hide=%d] battery[en=%d off=%.1f hide=%d] wifi[en=%d off=%.1f hide=%d] cellular[en=%d off=%.1f hide=%d] carrier[en=%d off=%.1f hide=%d] network[en=%d off=%.1f hide=%d] diag[en=%d level=%ld]",
        sClockRepositionEnabled, sClockLeadingOffset, sClockHidden,
        sBatteryRepositionEnabled, sBatteryLeadingOffset, sBatteryHidden,
        sWifiRepositionEnabled, sWifiLeadingOffset, sWifiHidden,
        sCellularRepositionEnabled, sCellularLeadingOffset, sCellularHidden,
        sCarrierTextRepositionEnabled, sCarrierTextLeadingOffset, sCarrierTextHidden,
        sNetworkTypeRepositionEnabled, sNetworkTypeLeadingOffset, sNetworkTypeHidden,
        sOITSDiagEnabled, (long)sOITSDiagLevel];
    BOOL unchanged = [summary isEqualToString:sOITSLastPrefsSummary];
    sOITSLastPrefsSummary = summary;
    OITSLogImpl(@"PREF", @"reload (%@): %@", unchanged ? @"no change" : @"CHANGED", summary);

    OITSUpdateEnforcerState();
}

// =====================================================================================
// MARK: Private class interfaces
// =====================================================================================

@interface _UIStatusBarStringView : UIView
@property (nonatomic, assign) BOOL showsAlternateText;
@property (nonatomic, copy) NSString *alternateText;
- (BOOL)wantsCrossfade;
@end

@interface _UIStatusBarForegroundView : UIView
@end

@interface _UIStaticBatteryView : UIView
@end

@interface _UIStatusBarWifiSignalView : UIView
@property (nonatomic, assign) BOOL needsCycleAnimationUpdate;
@end

@interface _UIStatusBarCellularSignalView : UIView
@end

@interface _UIBatteryView : UIView
@end

@interface _UIStatusBarCellularNetworkTypeView : UIView
@end

@interface _UIStatusBar : UIView
@end

// =====================================================================================
// MARK: Hooks
// =====================================================================================

// Diagnostic-only hooks on the status bar roots. They never change behavior: they log who
// hides / fades / rescales / detaches the status bar, which is the "whole bar vanished" symptom.
%hook _UIStatusBar

- (void)setHidden:(BOOL)hidden {
    OITSDiagSetHidden(self, hidden);
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    OITSDiagSetAlpha(self, alpha);
    %orig(alpha);
}

- (void)didMoveToWindow {
    %orig;
    OITSDiagNoteStatusBarView(self);
    OITSDiagMoveToWindow(self);
}

- (void)removeFromSuperview {
    OITSDiagRemoveFromSuperview(self);
    %orig;
}

%end

%hook _UIStatusBarForegroundView

- (void)layoutSubviews {
    %orig;
    OITSDiagNoteForegroundView(self);
    OITSDiagLayoutEvent(self);
    if (!sSpringBoardIsReadyForWindowAccess) return;
    if (!sClockRepositionEnabled && !sBatteryRepositionEnabled && !sWifiRepositionEnabled &&
        !sCellularRepositionEnabled && !sCarrierTextRepositionEnabled && !sNetworkTypeRepositionEnabled) return;
    if (!sStatusBarStringViewClass) sStatusBarStringViewClass = NSClassFromString(@"_UIStatusBarStringView");
    if (!sStaticBatteryViewClass) sStaticBatteryViewClass = NSClassFromString(@"_UIStaticBatteryView");
    if (!sBatteryViewAltClass) sBatteryViewAltClass = NSClassFromString(@"_UIBatteryView");
    if (!sStatusBarWifiSignalViewClass) sStatusBarWifiSignalViewClass = NSClassFromString(@"_UIStatusBarWifiSignalView");
    if (!sCellularNetworkTypeViewClass) sCellularNetworkTypeViewClass = NSClassFromString(@"_UIStatusBarCellularNetworkTypeView");
    if (!sTrackedClockViews) sTrackedClockViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedBatteryViews) sTrackedBatteryViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedWifiViews) sTrackedWifiViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedCellularViews) sTrackedCellularViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedCarrierTextViews) sTrackedCarrierTextViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedNetworkTypeViews) sTrackedNetworkTypeViews = [NSHashTable weakObjectsHashTable];
    CGFloat screenCenterX = UIScreen.mainScreen.bounds.size.width * 0.5;
    if (sClockRepositionEnabled) OITSFindCenteredStringViews(self, screenCenterX, 0);
    if (sBatteryRepositionEnabled) OITSFindBatteryViews(self, 0);
    if (sWifiRepositionEnabled) OITSFindWifiViews(self, 0);
    if (sCellularRepositionEnabled) OITSFindCellularViews(self, 0);
    if (sNetworkTypeRepositionEnabled) OITSFindNetworkTypeViews(self, 0);
    if (sCarrierTextRepositionEnabled) {
        OITSClassifyCarrierAndNetworkChildren(self, screenCenterX);
    }
}

- (void)setHidden:(BOOL)hidden {
    OITSDiagSetHidden(self, hidden);
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    OITSDiagSetAlpha(self, alpha);
    %orig(alpha);
}

- (void)setTransform:(CGAffineTransform)transform {
    OITSDiagSetTransform(self, transform);
    %orig(transform);
}

- (void)didMoveToWindow {
    %orig;
    OITSDiagNoteForegroundView(self);
    OITSDiagMoveToWindow(self);
}

- (void)removeFromSuperview {
    OITSDiagRemoveFromSuperview(self);
    %orig;
}

- (void)didAddSubview:(UIView *)subview {
    %orig(subview);
    OITSDiagSubviewChange(self, subview, YES);
}

- (void)willRemoveSubview:(UIView *)subview {
    OITSDiagSubviewChange(self, subview, NO);
    %orig(subview);
}

%end

%hook _UIStatusBarStringView

- (void)setFrame:(CGRect)frame {
    if (!sClockRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    BOOL hadTransform = !CGAffineTransformIsIdentity(self.transform);
    if (hadTransform) {
        OITSSetTransformInternal(self, CGAffineTransformIdentity);
    }
    %orig(frame);

    CGFloat screenCenterX = UIScreen.mainScreen.bounds.size.width * 0.5;
    CGFloat incomingCenterX = CGRectGetMidX(frame);
    BOOL isNearCenter = fabs(incomingCenterX - screenCenterX) <= kOITSCenterToleranceInPoints;
    BOOL onlySibling = OITSIsOnlyStringViewSibling(self);
    if (isNearCenter || onlySibling) {
        if (!sTrackedClockViews) sTrackedClockViews = [NSHashTable weakObjectsHashTable];
        [sTrackedClockViews addObject:self];
        objc_setAssociatedObject(self, kOITSClockNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
    }
    OITSDiagFrameEvent(self, @"clock", frame, hadTransform);
}

- (void)_updateAlternateTextTimer {
    if (sClockRepositionEnabled && sSpringBoardIsReadyForWindowAccess && sTrackedClockViews && [sTrackedClockViews containsObject:self]) {
        if (sSuppressionLogCount < kOITSMaxSuppressionLogs) {
            sSuppressionLogCount++;
            OITSDebugLog(@"[suppress #%lu] blocked _updateAlternateTextTimer on tracked clock view", (unsigned long)sSuppressionLogCount);
        }
        return;
    }
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    OITSDiagSetHidden(self, hidden);
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    OITSDiagSetAlpha(self, alpha);
    %orig(alpha);
}

- (void)setTransform:(CGAffineTransform)transform {
    OITSDiagSetTransform(self, transform);
    %orig(transform);
}

- (void)didMoveToWindow {
    %orig;
    OITSDiagMoveToWindow(self);
}

- (void)removeFromSuperview {
    OITSDiagRemoveFromSuperview(self);
    %orig;
}

%end

%hook _UIStaticBatteryView

- (void)setFrame:(CGRect)frame {
    if (!sBatteryRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    BOOL hadTransform = !CGAffineTransformIsIdentity(self.transform);
    if (hadTransform) {
        OITSSetTransformInternal(self, CGAffineTransformIdentity);
    }
    %orig(frame);

    if (!sTrackedBatteryViews) sTrackedBatteryViews = [NSHashTable weakObjectsHashTable];
    [sTrackedBatteryViews addObject:self];
    objc_setAssociatedObject(self, kOITSBatteryNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
    OITSDiagFrameEvent(self, @"battery", frame, hadTransform);
}

- (void)setHidden:(BOOL)hidden {
    OITSDiagSetHidden(self, hidden);
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    OITSDiagSetAlpha(self, alpha);
    %orig(alpha);
}

- (void)setTransform:(CGAffineTransform)transform {
    OITSDiagSetTransform(self, transform);
    %orig(transform);
}

- (void)didMoveToWindow {
    %orig;
    OITSDiagMoveToWindow(self);
}

- (void)removeFromSuperview {
    OITSDiagRemoveFromSuperview(self);
    %orig;
}

%end

%hook _UIStatusBarWifiSignalView

- (void)setFrame:(CGRect)frame {
    if (!sWifiRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    BOOL hadTransform = !CGAffineTransformIsIdentity(self.transform);
    if (hadTransform) {
        OITSSetTransformInternal(self, CGAffineTransformIdentity);
    }
    %orig(frame);

    if (!sTrackedWifiViews) sTrackedWifiViews = [NSHashTable weakObjectsHashTable];
    [sTrackedWifiViews addObject:self];
    objc_setAssociatedObject(self, kOITSWifiNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
    OITSDiagFrameEvent(self, @"wifi", frame, hadTransform);
}

- (void)_updateCycleAnimationNow {
    if (sWifiRepositionEnabled && sSpringBoardIsReadyForWindowAccess && sTrackedWifiViews && [sTrackedWifiViews containsObject:self]) {
        if (sSuppressionLogCount < kOITSMaxSuppressionLogs) {
            sSuppressionLogCount++;
            OITSDebugLog(@"[suppress #%lu] blocked _updateCycleAnimationNow on tracked wifi view", (unsigned long)sSuppressionLogCount);
        }
        return;
    }
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    OITSDiagSetHidden(self, hidden);
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    OITSDiagSetAlpha(self, alpha);
    %orig(alpha);
}

- (void)setTransform:(CGAffineTransform)transform {
    OITSDiagSetTransform(self, transform);
    %orig(transform);
}

- (void)didMoveToWindow {
    %orig;
    OITSDiagMoveToWindow(self);
}

- (void)removeFromSuperview {
    OITSDiagRemoveFromSuperview(self);
    %orig;
}

%end

%hook _UIStatusBarCellularSignalView

- (void)setFrame:(CGRect)frame {
    if (!sCellularRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    BOOL hadTransform = !CGAffineTransformIsIdentity(self.transform);
    if (hadTransform) {
        OITSSetTransformInternal(self, CGAffineTransformIdentity);
    }
    %orig(frame);

    if (!sTrackedCellularViews) sTrackedCellularViews = [NSHashTable weakObjectsHashTable];
    [sTrackedCellularViews addObject:self];
    objc_setAssociatedObject(self, kOITSCellularNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
    OITSDiagFrameEvent(self, @"cellular", frame, hadTransform);
}

- (void)setHidden:(BOOL)hidden {
    OITSDiagSetHidden(self, hidden);
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    OITSDiagSetAlpha(self, alpha);
    %orig(alpha);
}

- (void)setTransform:(CGAffineTransform)transform {
    OITSDiagSetTransform(self, transform);
    %orig(transform);
}

- (void)didMoveToWindow {
    %orig;
    OITSDiagMoveToWindow(self);
}

- (void)removeFromSuperview {
    OITSDiagRemoveFromSuperview(self);
    %orig;
}

%end

%hook _UIBatteryView

- (void)setFrame:(CGRect)frame {
    if (!sBatteryRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    BOOL hadTransform = !CGAffineTransformIsIdentity(self.transform);
    if (hadTransform) {
        OITSSetTransformInternal(self, CGAffineTransformIdentity);
    }
    %orig(frame);

    if (!sTrackedBatteryViews) sTrackedBatteryViews = [NSHashTable weakObjectsHashTable];
    [sTrackedBatteryViews addObject:self];
    objc_setAssociatedObject(self, kOITSBatteryNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
    OITSDiagFrameEvent(self, @"battery", frame, hadTransform);
}

- (void)setHidden:(BOOL)hidden {
    OITSDiagSetHidden(self, hidden);
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    OITSDiagSetAlpha(self, alpha);
    %orig(alpha);
}

- (void)setTransform:(CGAffineTransform)transform {
    OITSDiagSetTransform(self, transform);
    %orig(transform);
}

- (void)didMoveToWindow {
    %orig;
    OITSDiagMoveToWindow(self);
}

- (void)removeFromSuperview {
    OITSDiagRemoveFromSuperview(self);
    %orig;
}

%end

%hook _UIStatusBarCellularNetworkTypeView

- (void)setFrame:(CGRect)frame {
    if (!sNetworkTypeRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    BOOL hadTransform = !CGAffineTransformIsIdentity(self.transform);
    if (hadTransform) {
        OITSSetTransformInternal(self, CGAffineTransformIdentity);
    }
    %orig(frame);

    if (!sTrackedNetworkTypeViews) sTrackedNetworkTypeViews = [NSHashTable weakObjectsHashTable];
    [sTrackedNetworkTypeViews addObject:self];
    objc_setAssociatedObject(self, kOITSNetworkTypeNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
    OITSDiagFrameEvent(self, @"network", frame, hadTransform);
}

- (void)setHidden:(BOOL)hidden {
    OITSDiagSetHidden(self, hidden);
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    OITSDiagSetAlpha(self, alpha);
    %orig(alpha);
}

- (void)setTransform:(CGAffineTransform)transform {
    OITSDiagSetTransform(self, transform);
    %orig(transform);
}

- (void)didMoveToWindow {
    %orig;
    OITSDiagMoveToWindow(self);
}

- (void)removeFromSuperview {
    OITSDiagRemoveFromSuperview(self);
    %orig;
}

%end

// =====================================================================================
// MARK: Constructor
// =====================================================================================

// Only notification names containing one of these fragments get logged (keeps the tap cheap/quiet).
static BOOL OITSNotificationNameIsInteresting(NSString *name) {
    static NSArray<NSString *> *fragments;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fragments = @[@"StatusBar", @"Statusbar", @"Frontmost", @"Foreground", @"Activate", @"Deactivate",
                      @"Launch", @"Transition", @"Scene", @"AppSwitcher", @"Lock", @"Blank", @"Orientation",
                      @"Cellular", @"Radio", @"Signal", @"Battery", @"WiFi", @"Wifi", @"Clock", @"Locale",
                      @"TimeZone", @"Airplane", @"Network"];
    });
    if (!name.length) return NO;
    for (NSString *fragment in fragments) {
        if ([name containsString:fragment]) return YES;
    }
    return NO;
}

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

    sOITSLogStartMono = CACurrentMediaTime();
    struct utsname systemInfo;
    uname(&systemInfo);
    OITSLogImpl(@"SESSION", @"START build=%@ compiled=%s %s pid=%d proc=%@ os=%@ machine=%s",
                kOITSBuildTag, __DATE__, __TIME__, getpid(), NSProcessInfo.processInfo.processName,
                NSProcessInfo.processInfo.operatingSystemVersionString, systemInfo.machine);
    OITSDebugLog(@"=== ctor (clock/battery/wifi/cellular/carrier/network + hide + diagnostics) ===");
    OITSReloadPreferences();
    OITSStartDiagnosticsTimer();

    OITObserveDarwinNotification(kOITSPrefsChangedNotification, ^{
        OITSLOG(1, @"DARWIN", @"prefs-changed notification received");
        OITSReloadPreferences();
    });

    OITObserveDarwinNotification(kOITSDumpNotification, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            OITSDumpStatusBarHierarchy(@"darwin notification com.wilburt.oits/DumpState");
        });
    });

    // Correlate disappearances with system events (lock state, network changes, ...).
    NSArray<NSString *> *systemDarwinNames = @[@"com.apple.springboard.lockstate",
                                               @"com.apple.springboard.hasBlankedScreen",
                                               @"com.apple.springboard.lockcomplete",
                                               @"com.apple.system.config.network_change"];
    for (NSString *darwinName in systemDarwinNames) {
        NSString *captured = darwinName;
        OITObserveDarwinNotification(captured, ^{
            OITSLOG(1, @"DARWIN", @"%@ fired", captured);
        });
    }

    if (sOITSDiagEnabled && sOITSDiagLevel >= 2) {
        [[NSNotificationCenter defaultCenter] addObserverForName:nil object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSString *name = note.name;
            if (!OITSNotificationNameIsInteresting(name)) return;
            OITSLOG_RATED(2, @"NOTIF", "NOTIF", 40, @"%@ (object class: %@)", name, note.object ? NSStringFromClass([note.object class]) : @"nil");
        }];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOITSStartupDelaySeconds * NSEC_PER_SEC)),
                  dispatch_get_main_queue(), ^{
        OITSDebugLog(@"=== startup delay elapsed ===");
        sSpringBoardIsReadyForWindowAccess = YES;
        OITSLogImpl(@"SESSION", @"READY device=%@ systemVersion=%@ screen=%@ scale=%.1f",
                    UIDevice.currentDevice.name, UIDevice.currentDevice.systemVersion,
                    OITSRectDesc(UIScreen.mainScreen.bounds), UIScreen.mainScreen.scale);
        OITSUpdateEnforcerState();
        // Baseline dump a couple of seconds after ready, so we know the "healthy" layout.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                      dispatch_get_main_queue(), ^{
            if (sOITSDiagEnabled && sOITSDiagLevel >= 1) OITSDumpStatusBarHierarchy(@"baseline (2s after ready)");
        });
    });
}
