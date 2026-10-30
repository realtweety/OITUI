// OITIInstallDump.xm -- the read-only install progress dump (OITI diagnostics).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 1, Diagnostics): the snapshot and sampling code
// that finds where the App Store and system installers keep download progress. Four of its helpers
// (OITIInstallIvarScalarText, OITIInstallObjectGetter, OITIInstallSharedInstance, OITIInstallApplicationForBundleID)
// are also called by the App Store download source in Tweak.xm; they are declared in OITIDiagnostics.h and are a
// candidate to move into Shared when that round comes. Reference: DIAGNOSTICS.md, "Install progress dump".

#import "Shared/OITIShared.h"
#import "Diagnostics/OITIDiagnostics.h"

// =============================================================================================
// MARK: Install progress dump (read-only)
// =============================================================================================

// Download Progress, stage 2, step 1. Before any real App Store source is written, this records what SpringBoard
// actually exposes about an install that is running: the Home Screen icon's progress parts, placeholder objects,
// and any NSProgress with real byte counts versus a bare fraction. Nothing is hooked and nothing is changed.
//
// How it stays read-only and low risk:
//  * It only runs at DiagnosticsLevel >= 1, on request (touch /tmp/OITIInstallDump.trigger, or Darwin notification
//    com.wilburt.oiti/InstallDump). Nothing runs at level 0 and no timer exists for it.
//  * By default it calls NO method on private objects, except a few explicit accessors (shared instances, `icon`,
//    `iconManager`, `iconModel`, identifier getters and an explicit list of collection getters such as `allApplications`).
//    Everything else is read from instance variables (memory reads) and from the public NSProgress API. Build -a called
//    "getters" chosen by keyword and crashed SpringBoard: a method named -[FBSApplicationPlaceholderProgress
//    _queue_updateFromProgress] matched, and it asserts that it runs on its own queue. A name filter cannot tell an action
//    from a getter on private classes, so the keyword filter now only decides what to LIST, never what to call.
//  * Build -b ran on the device without a crash. Build -c adds the placeholder layer (SBApplicationPlaceholderController
//    -placeholdersByDisplayID, the icon's applicationPlaceholder) and follows objects three levels deep, still by ivars.
//  * InstallDumpCallGetters=YES additionally calls zero-argument getters that the class declares as @property getters
//    (and still passes the name checks). Off by default; for a second pass once the ivars have shown where to look.
//  * Every class and selector is looked up by name at run time and is optional. Nothing here is a fact about iOS 16:
//    the class lists and probes are guesses to check, and the output says which ones exist.
//  * Output is bounded (line budgets, item caps, a visit cap on the view walk) and goes to the INSTALL tag only.
// The first part is a snapshot; then a few compact samples (InstallDumpSamples, default 6, every
// InstallDumpIntervalSeconds, default 2) show whether values move and how often. Apple Mode does not switch this
// off: it is a diagnostic like the other dumps and changes nothing on screen.


static const NSUInteger kOITIInstallClassListCap = 120;
static const NSUInteger kOITIInstallProbeMethodCap = 30;
static const NSUInteger kOITIInstallCandidateCap = 12;
static const NSUInteger kOITIInstallItemCap = 800;
static const NSUInteger kOITIInstallViewVisitCap = 40000;
static const NSUInteger kOITIInstallViewDepthCap = 60;
static const NSUInteger kOITIInstallViewMatchCap = 12;

static BOOL sInstallDumpRunning = NO;
static NSUInteger sInstallDumpCount = 0;
static NSString *sInstallPhase = @"snapshot";
static NSMutableArray<NSString *> *sInstallFindings;   // per scan: "NSPROGRESS ..." and "FRACTION ..." lines for the verdict

static void OITIInstallLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void OITIInstallLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    [sLog logTag:@"INSTALL" format:@"[%@] %@", sInstallPhase, message];
}

static NSArray<NSString *> *OITIInstallWideKeywords(void) {
    return @[@"progress", @"fraction", @"percent", @"install", @"download", @"byte", @"total", @"completed", @"expected",
             @"unit", @"state", @"paus", @"cancel", @"placeholder", @"updat", @"status", @"phase", @"throughput", @"remaining"];
}

// Words that mean "something is in progress" when a getter with that name returns a non-zero or non-nil value.
static NSArray<NSString *> *OITIInstallActiveKeywords(void) {
    return @[@"progress", @"fraction", @"percent", @"download", @"installing", @"updating", @"paused", @"placeholder"];
}

// Collection getters that are called by name even when they are plain methods (no verb in the name, no side effects expected).
static NSSet<NSString *> *OITIInstallExplicitCollectionGetters(void) {
    static NSSet<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[@"allApplications", @"allBundleIdentifiers", @"allPlaceholders", @"placeholders",
                                      @"allApplicationPlaceholders", @"placeholdersByDisplayID", @"leafIcons", @"allLeafIcons"]];
    });
    return names;
}

static NSArray<NSString *> *OITIInstallCollectionKeywords(void) {
    return @[@"placeholder", @"applications", @"bundleidentifiers", @"leaficons"];
}

// YES when `name` starts with one of `verbs` as a whole word (the next character is upper case, or the name ends).
static BOOL OITIInstallHasVerbPrefix(NSString *name, NSArray<NSString *> *verbs) {
    NSCharacterSet *upper = [NSCharacterSet uppercaseLetterCharacterSet];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for (NSString *verb in verbs) {
        if (![name hasPrefix:verb]) continue;
        if (name.length == verb.length) return YES;
        unichar next = [name characterAtIndex:verb.length];
        if ([upper characterIsMember:next] || [digits characterIsMember:next]) return YES;
    }
    return NO;
}

static BOOL OITIInstallIsBlockedName(NSString *name) {
    static NSArray<NSString *> *verbs;
    static NSArray<NSString *> *exact;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        verbs = @[@"init", @"copy", @"mutableCopy", @"new", @"alloc", @"dealloc", @"retain", @"release", @"autorelease",
                  @"start", @"stop", @"cancel", @"pause", @"resume", @"remove", @"delete", @"clear", @"reset", @"finish",
                  @"complete", @"begin", @"end", @"kick", @"trigger", @"send", @"post", @"open", @"launch", @"uninstall",
                  @"perform", @"run", @"fire", @"invalidate", @"resign", @"become", @"dismiss", @"hide", @"show", @"reload",
                  @"refresh", @"sync", @"flush", @"purge", @"rebuild", @"notify", @"enable", @"disable", @"commit", @"save",
                  @"load", @"fetch", @"request", @"prepare", @"schedule", @"register", @"unregister", @"activate",
                  @"deactivate", @"suspend", @"terminate", @"kill", @"force", @"retry", @"restore", @"revert", @"accept",
                  @"approve"];
        exact = @[@"hash", @"description", @"debugDescription", @"superclass", @"class", @"self", @"zone", @"isProxy",
                  @"retainCount"];
    });
    if (!name.length) return YES;
    if ([exact containsObject:name]) return YES;
    return OITIInstallHasVerbPrefix(name, verbs);
}

// "install", "download" and "update" are verbs and nouns. A getter that starts with one is only called when the next word
// makes it a noun (installState, downloadProgress, updateType) or the word continues in lower case (installed,
// downloading). A bare -install, -download or -updateSomething is never called.
static BOOL OITIInstallActionPrefixOK(NSString *name) {
    NSCharacterSet *upper = [NSCharacterSet uppercaseLetterCharacterSet];
    NSArray<NSString *> *nouns = @[@"State", @"Progress", @"Type", @"Phase", @"Status", @"Percent", @"Fraction", @"Count",
                                   @"Bytes", @"Size", @"Date", @"Error", @"ID", @"Identifier", @"Source", @"Reason", @"Info",
                                   @"Options", @"URL", @"Token", @"Task", @"Session", @"Coordinator"];
    for (NSString *verb in @[@"install", @"download", @"update"]) {
        if (![name hasPrefix:verb]) continue;
        if (name.length == verb.length) return NO;
        if (![upper characterIsMember:[name characterAtIndex:verb.length]]) return YES;
        NSString *rest = [name substringFromIndex:verb.length];
        for (NSString *noun in nouns) {
            if ([rest hasPrefix:noun]) return YES;
        }
        return NO;
    }
    return YES;
}

static BOOL OITIInstallNameAllowed(const char *cname, NSArray<NSString *> *keywords) {
    if (!cname || strchr(cname, ':') || cname[0] == '.') return NO;
    NSString *name = @(cname);
    while ([name hasPrefix:@"_"]) name = [name substringFromIndex:1];
    if (OITIInstallIsBlockedName(name) || !OITIInstallActionPrefixOK(name)) return NO;
    NSString *lower = name.lowercaseString;
    for (NSString *keyword in keywords) {
        if ([lower containsString:keyword]) return YES;
    }
    return NO;
}

// Getter names of the properties `cls` itself declares (not inherited ones).
static NSSet<NSString *> *OITIInstallPropertyGetters(Class cls) {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    NSMutableSet<NSString *> *names = [NSMutableSet setWithCapacity:count];
    for (unsigned int i = 0; i < count; i++) {
        char *custom = property_copyAttributeValue(properties[i], "G");
        const char *name = custom ? custom : property_getName(properties[i]);
        if (name) [names addObject:@(name)];
        free(custom);
    }
    free(properties);
    return names;
}

static BOOL sInstallCallGetters = NO;   // InstallDumpCallGetters, read when a run starts

static BOOL OITIInstallContainsWord(NSString *text, NSString *word) {
    return [text rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSString *OITIInstallObjectText(id object) {
    if (!object) return @"nil";
    if ([object isKindOfClass:[NSString class]]) {
        NSString *value = (NSString *)object;
        if (value.length > 100) value = [[value substringToIndex:100] stringByAppendingString:@"…"];
        return [NSString stringWithFormat:@"\"%@\"", value];
    }
    if ([object isKindOfClass:[NSNumber class]] || [object isKindOfClass:[NSDate class]]) return [object description];
    if ([object isKindOfClass:[NSURL class]]) {
        NSString *value = ((NSURL *)object).absoluteString ?: @"";
        return value.length > 100 ? [[value substringToIndex:100] stringByAppendingString:@"…"] : value;
    }
    if ([object isKindOfClass:[NSData class]]) return [NSString stringWithFormat:@"NSData(%lu bytes)", (unsigned long)((NSData *)object).length];
    if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]] || [object isKindOfClass:[NSOrderedSet class]]) {
        NSUInteger count = [object isKindOfClass:[NSArray class]] ? ((NSArray *)object).count
                         : [object isKindOfClass:[NSSet class]] ? ((NSSet *)object).count : ((NSOrderedSet *)object).count;
        return [NSString stringWithFormat:@"%@(count=%lu)", NSStringFromClass([object class]), (unsigned long)count];
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        NSMutableArray<NSString *> *keys = [NSMutableArray array];
        for (id key in dictionary) {
            if (keys.count >= 6) break;
            [keys addObject:[key description]];
        }
        return [NSString stringWithFormat:@"%@(count=%lu keys=%@)", NSStringFromClass([object class]),
                (unsigned long)dictionary.count, [keys componentsJoinedByString:@","]];
    }
    return [NSString stringWithFormat:@"%@@%p", NSStringFromClass([object class]), (__bridge void *)object];
}

// Calls a zero-argument getter that returns a number or an object. Returns NO when it could not be called.
// `text` describes the result, `number` holds a numeric result (NAN for objects), `object` an object result.
static BOOL OITIInstallCallGetter(id target, Method method, NSString **textOut, double *numberOut, id *objectOut) {
    SEL selector = method_getName(method);
    char *rawType = method_copyReturnType(method);
    if (!rawType) return NO;
    char kind = rawType[0];
    BOOL isBlock = (kind == '@' && rawType[1] == '?');
    free(rawType);
    if (isBlock || kind == 0 || !strchr("BcCiIsSlLqQfd@", kind)) return NO;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) return NO;

    NSString *text = nil;
    double number = NAN;
    __unsafe_unretained id object = nil;
    @try {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = target;
        invocation.selector = selector;
        [invocation invoke];
        switch (kind) {
            case 'B': { bool v = false; [invocation getReturnValue:&v]; number = v ? 1 : 0; text = v ? @"YES" : @"NO"; break; }
            case 'c': { signed char v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%d", (int)v]; break; }
            case 'C': { unsigned char v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%u", (unsigned)v]; break; }
            case 'i': { int v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%d", v]; break; }
            case 'I': { unsigned int v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%u", v]; break; }
            case 's': { short v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%d", (int)v]; break; }
            case 'S': { unsigned short v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%u", (unsigned)v]; break; }
            case 'l': { int32_t v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%d", (int)v]; break; }
            case 'L': { uint32_t v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%u", (unsigned)v]; break; }
            case 'q': { long long v = 0; [invocation getReturnValue:&v]; number = (double)v; text = [NSString stringWithFormat:@"%lld", v]; break; }
            case 'Q': { unsigned long long v = 0; [invocation getReturnValue:&v]; number = (double)v; text = [NSString stringWithFormat:@"%llu", v]; break; }
            case 'f': { float v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%.4f", (double)v]; break; }
            case 'd': { double v = 0; [invocation getReturnValue:&v]; number = v; text = [NSString stringWithFormat:@"%.4f", v]; break; }
            case '@': { [invocation getReturnValue:&object]; text = OITIInstallObjectText(object); break; }
            default: return NO;
        }
    } @catch (NSException *exception) {
        text = [NSString stringWithFormat:@"(threw %@)", exception.name];
        number = NAN;
        object = nil;
    }
    if (textOut) *textOut = text;
    if (numberOut) *numberOut = number;
    if (objectOut) *objectOut = object;
    return YES;
}

// Reads a scalar instance variable by offset. Returns nil for types it does not handle.
NSString *OITIInstallIvarScalarText(id object, Ivar ivar, const char *type, double *numberOut) {
    const uint8_t *base = (const uint8_t *)(__bridge const void *)object;
    const void *location = base + ivar_getOffset(ivar);
    double number = NAN;
    NSString *text = nil;
    switch (type[0]) {
        case 'B': { bool v; memcpy(&v, location, sizeof v); number = v ? 1 : 0; text = v ? @"YES" : @"NO"; break; }
        case 'c': { signed char v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%d", (int)v]; break; }
        case 'C': { unsigned char v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%u", (unsigned)v]; break; }
        case 'i': { int v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%d", v]; break; }
        case 'I': { unsigned int v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%u", v]; break; }
        case 's': { short v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%d", (int)v]; break; }
        case 'S': { unsigned short v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%u", (unsigned)v]; break; }
        case 'l': { int32_t v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%d", (int)v]; break; }
        case 'L': { uint32_t v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%u", (unsigned)v]; break; }
        case 'q': { long long v; memcpy(&v, location, sizeof v); number = (double)v; text = [NSString stringWithFormat:@"%lld", v]; break; }
        case 'Q': { unsigned long long v; memcpy(&v, location, sizeof v); number = (double)v; text = [NSString stringWithFormat:@"%llu", v]; break; }
        case 'f': { float v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%.4f", (double)v]; break; }
        case 'd': { double v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%.4f", v]; break; }
        default: return nil;
    }
    if (numberOut) *numberOut = number;
    return text;
}

static NSString *OITIInstallProgressText(NSProgress *progress) {
    NSMutableString *text = [NSMutableString string];
    @try {
        [text appendFormat:@"fraction=%.4f completed=%lld total=%lld indeterminate=%d paused=%d cancelled=%d finished=%d",
         progress.fractionCompleted, (long long)progress.completedUnitCount, (long long)progress.totalUnitCount,
         (int)progress.indeterminate, (int)progress.paused, (int)progress.cancelled, (int)progress.finished];
        if (progress.kind) [text appendFormat:@" kind=%@", progress.kind];
        if (progress.fileOperationKind) [text appendFormat:@" fileOperationKind=%@", progress.fileOperationKind];
        if (progress.throughput) [text appendFormat:@" throughput=%@", progress.throughput];
        if (progress.estimatedTimeRemaining) [text appendFormat:@" eta=%@", progress.estimatedTimeRemaining];
        if (progress.fileTotalCount) [text appendFormat:@" fileTotalCount=%@", progress.fileTotalCount];
        if (progress.fileCompletedCount) [text appendFormat:@" fileCompletedCount=%@", progress.fileCompletedCount];
        if (progress.fileURL) [text appendFormat:@" fileURL=%@", OITIInstallObjectText(progress.fileURL)];
        NSString *description = progress.localizedDescription;
        if (description.length) [text appendFormat:@" description=%@", OITIInstallObjectText(description)];
        NSString *additional = progress.localizedAdditionalDescription;
        if (additional.length) [text appendFormat:@" additional=%@", OITIInstallObjectText(additional)];
        NSDictionary *info = progress.userInfo;
        if (info.count) {
            NSMutableArray<NSString *> *pairs = [NSMutableArray array];
            for (id key in info) {
                if (pairs.count >= 8) break;
                id value = info[key];
                NSString *valueText = [value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]]
                    ? [value description] : NSStringFromClass([value class]);
                if (valueText.length > 40) valueText = [valueText substringToIndex:40];
                [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, valueText]];
            }
            [text appendFormat:@" userInfo{%@}", [pairs componentsJoinedByString:@", "]];
        }
    } @catch (NSException *exception) {
        [text appendFormat:@" (threw %@)", exception.name];
    }
    return text;
}

// Heuristic only: says what the unit counts probably are, from the total.
static NSString *OITIInstallProgressUnits(NSProgress *progress) {
    long long total = progress.totalUnitCount;
    if (progress.indeterminate || total <= 0) return @"units: no total (fraction at most)";
    if (total == 100) return @"units: total is 100, so probably a percentage and not bytes";
    if (total == 1) return @"units: total is 1, so probably a bare fraction";
    if (total >= 1000000) return @"units: large total, probably BYTES";
    return @"units: unclear, small total; check fileOperationKind and userInfo";
}

static BOOL OITIInstallLooksRelevant(id object) {
    if (!object) return NO;
    if ([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]] ||
        [object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]] ||
        [object isKindOfClass:[NSDictionary class]] || [object isKindOfClass:[NSURL class]]) return NO;
    NSString *name = NSStringFromClass([object class]);
    for (NSString *word in @[@"Progress", @"Install", @"Download", @"Placeholder", @"Coordinator", @"Transfer"]) {
        if (OITIInstallContainsWord(name, word)) return YES;
    }
    return NO;
}

id OITIInstallObjectGetter(id object, NSString *selectorName) {
    if (!object) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod([object class], selector);
    if (!method) return nil;
    char *type = method_copyReturnType(method);
    BOOL isObject = type && type[0] == '@' && type[1] != '?';
    free(type);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!isObject || !signature || signature.numberOfArguments != 2) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (NSException *exception) {
        return nil;
    }
}

// Text of one explicitly named zero-argument accessor (used for a few well-known icon accessors only).
static NSString *OITIInstallExplicitGetterText(id object, NSString *name) {
    if (!object) return @"nil";
    Method method = class_getInstanceMethod([object class], NSSelectorFromString(name));
    if (!method) return @"(no such method)";
    NSString *text = nil;
    double number = NAN;
    id result = nil;
    return OITIInstallCallGetter(object, method, &text, &number, &result) ? text : @"(not callable)";
}

id OITIInstallSharedInstance(Class cls, NSString **how) {
    if (!cls) return nil;
    for (NSString *name in @[@"sharedInstanceIfExists", @"sharedInstance", @"sharedController", @"sharedManager"]) {
        SEL selector = NSSelectorFromString(name);
        if (![cls respondsToSelector:selector]) continue;
        id instance = nil;
        @try {
            instance = ((id (*)(Class, SEL))objc_msgSend)(cls, selector);
        } @catch (NSException *exception) {
            instance = nil;
        }
        if (instance) {
            if (how) *how = name;
            return instance;
        }
    }
    return nil;
}

// Short identification for an app, placeholder or icon: whichever of these getters exist.
static NSString *OITIInstallLabel(id object) {
    if (!object) return @"(none)";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *name in @[@"bundleIdentifier", @"applicationBundleID", @"bundleID", @"leafIdentifier", @"displayName"]) {
        id value = OITIInstallObjectGetter(object, name);
        if ([value isKindOfClass:[NSString class]] && ((NSString *)value).length) {
            [parts addObject:[NSString stringWithFormat:@"%@=%@", name, value]];
        }
    }
    return parts.count ? [parts componentsJoinedByString:@" "] : @"(no identifier getter answered)";
}

// Signs of an install in progress on an app, icon or view: instance variables with progress-like names that hold a
// non-zero number or a non-nil object. Property getters are only called when InstallDumpCallGetters is on.
static NSArray<NSString *> *OITIInstallActiveSignals(id object) {
    if (!object) return @[];
    NSMutableArray<NSString *> *signals = [NSMutableArray array];
    for (Class cls = [object class]; cls && cls != [NSObject class] && signals.count < 8; cls = class_getSuperclass(cls)) {
        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        for (unsigned int i = 0; i < ivarCount && signals.count < 8; i++) {
            const char *name = ivar_getName(ivars[i]);
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!name || !type || !type[0]) continue;
            NSString *lower = @(name).lowercaseString;
            BOOL match = NO;
            for (NSString *word in OITIInstallActiveKeywords()) {
                if ([lower containsString:word]) { match = YES; break; }
            }
            if (!match || [lower containsString:@"showsprogress"]) continue;
            if (type[0] == '@') {
                id value = object_getIvar(object, ivars[i]);
                BOOL active = value && (![value isKindOfClass:[NSNumber class]] || [(NSNumber *)value doubleValue] != 0);
                if (active) [signals addObject:[NSString stringWithFormat:@"ivar %s=%@", name, OITIInstallObjectText(value)]];
            } else {
                double number = NAN;
                NSString *text = OITIInstallIvarScalarText(object, ivars[i], type, &number);
                if (text && !isnan(number) && number != 0) [signals addObject:[NSString stringWithFormat:@"ivar %s=%@", name, text]];
            }
        }
        free(ivars);
        if (!sInstallCallGetters) continue;
        NSSet<NSString *> *properties = OITIInstallPropertyGetters(cls);
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count && signals.count < 8; i++) {
            const char *cname = sel_getName(method_getName(methods[i]));
            if (!cname || ![properties containsObject:@(cname)]) continue;
            if (!OITIInstallNameAllowed(cname, OITIInstallActiveKeywords())) continue;
            NSString *text = nil;
            double number = NAN;
            id result = nil;
            if (!OITIInstallCallGetter(object, methods[i], &text, &number, &result)) continue;
            BOOL active = NO;
            if (!isnan(number)) {
                active = number != 0;
            } else if (result) {
                active = ![result isKindOfClass:[NSNumber class]] || [(NSNumber *)result doubleValue] != 0;
            }
            if (active) [signals addObject:[NSString stringWithFormat:@"%s=%@", cname, text]];
        }
        free(methods);
    }
    return signals;
}

// Describes one object: class chain, progress-related getters and instance variables, following objects that look
// relevant (an NSProgress, an installer, a placeholder) up to three levels. An NSProgress is always described fully.
// `compact` (the samples) logs only NSProgress objects and numeric progress values.
static void OITIInstallDescribe(id object, NSString *label, NSUInteger depth, NSMutableSet<NSValue *> *seen,
                                NSInteger *budget, BOOL compact) {
    if (!object || *budget <= 0 || depth > 3) return;
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)object];
    if ([seen containsObject:key]) return;
    [seen addObject:key];

    if ([object isKindOfClass:[NSProgress class]]) {
        NSProgress *progress = (NSProgress *)object;
        NSString *text = OITIInstallProgressText(progress);
        NSString *units = OITIInstallProgressUnits(progress);
        OITIInstallLog(@"PROGRESS %@ NSProgress@%p %@ | %@", label, (__bridge void *)object, text, units);
        (*budget)--;
        [sInstallFindings addObject:[NSString stringWithFormat:@"NSPROGRESS %@ %@ | %@", label, text, units]];
        return;
    }

    Class stop = [object isKindOfClass:[UIView class]] ? [UIView class] : [NSObject class];
    if (!compact) {
        NSMutableArray<NSString *> *chain = [NSMutableArray array];
        for (Class cls = [object class]; cls; cls = class_getSuperclass(cls)) [chain addObject:NSStringFromClass(cls)];
        OITIInstallLog(@"OBJECT %@ %@@%p chain=%@", label, NSStringFromClass([object class]), (__bridge void *)object,
                       [chain componentsJoinedByString:@" > "]);
        (*budget)--;
    }
    NSUInteger follows = 0;

    for (Class cls = [object class]; cls && cls != stop && cls != [NSObject class] && *budget > 0; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        NSSet<NSString *> *properties = OITIInstallPropertyGetters(cls);
        NSMutableArray<NSString *> *listed = [NSMutableArray array];
        NSUInteger shown = 0;
        for (unsigned int i = 0; i < count && *budget > 0 && shown < kOITIInstallProbeMethodCap; i++) {
            const char *cname = sel_getName(method_getName(methods[i]));
            if (!cname || strchr(cname, ':') || cname[0] == '.') continue;
            NSString *lowerName = @(cname).lowercaseString;
            BOOL wide = NO;
            for (NSString *word in OITIInstallWideKeywords()) {
                if ([lowerName containsString:word]) { wide = YES; break; }
            }
            if (!wide) continue;
            BOOL isProperty = [properties containsObject:@(cname)];
            if (!compact && listed.count < 24) [listed addObject:[NSString stringWithFormat:@"%s%@", cname, isProperty ? @"(p)" : @""]];
            // Never called by default. With InstallDumpCallGetters, only declared property getters that pass the name checks.
            if (!sInstallCallGetters || !isProperty || !OITIInstallNameAllowed(cname, OITIInstallWideKeywords())) continue;
            NSString *text = nil;
            double number = NAN;
            id result = nil;
            if (!OITIInstallCallGetter(object, methods[i], &text, &number, &result)) continue;
            shown++;
            NSString *lower = lowerName;
            BOOL progressName = [lower containsString:@"progress"] || [lower containsString:@"fraction"] || [lower containsString:@"percent"];
            BOOL valueName = progressName || [lower containsString:@"byte"] || [lower containsString:@"completed"] || [lower containsString:@"total"];
            if (!isnan(number) && progressName) {
                [sInstallFindings addObject:[NSString stringWithFormat:@"FRACTION %@ -%s = %@", label, cname, text]];
            }
            if (!compact || (!isnan(number) && valueName)) {
                OITIInstallLog(@"GET %@ -%s = %@", label, cname, text);
                (*budget)--;
            }
            if (result && depth < 3 && follows < 6 &&
                ([result isKindOfClass:[NSProgress class]] || OITIInstallLooksRelevant(result))) {
                follows++;
                OITIInstallDescribe(result, [NSString stringWithFormat:@"%@.%s", label, cname], depth + 1, seen, budget, compact);
            }
        }
        if (listed.count) {
            OITIInstallLog(@"METHODS %@ %@ (names only, not called; (p) = declared property): %@", label, NSStringFromClass(cls),
                           [listed componentsJoinedByString:@", "]);
            (*budget)--;
        }
        free(methods);
    }

    for (Class cls = [object class]; cls && cls != stop && cls != [NSObject class] && *budget > 0; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count && *budget > 0; i++) {
            const char *name = ivar_getName(ivars[i]);
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!name || !type || !type[0]) continue;
            NSString *lower = @(name).lowercaseString;
            BOOL interesting = NO;
            for (NSString *word in OITIInstallWideKeywords()) {
                if ([lower containsString:word]) { interesting = YES; break; }
            }
            if (type[0] == '@') {
                // Only touch an object instance variable when its name is progress-related or its declared class is
                // (an unsafe_unretained ivar to a freed object would otherwise be messaged for no reason).
                BOOL typedRelevant = NO;
                if (type[1] == '"') {
                    NSString *declared = @(type + 2);
                    NSRange quote = [declared rangeOfString:@"\""];
                    if (quote.location != NSNotFound) declared = [declared substringToIndex:quote.location];
                    for (NSString *word in @[@"Progress", @"Install", @"Download", @"Placeholder", @"Coordinator", @"Transfer"]) {
                        if (OITIInstallContainsWord(declared, word)) { typedRelevant = YES; break; }
                    }
                }
                if (!interesting && !typedRelevant) continue;
                id value = object_getIvar(object, ivars[i]);
                BOOL follow = value && ([value isKindOfClass:[NSProgress class]] || OITIInstallLooksRelevant(value));
                if (!compact) {
                    OITIInstallLog(@"IVAR %@ %s = %@ [%s]", label, name, OITIInstallObjectText(value), type);
                    (*budget)--;
                }
                if (follow && depth < 3 && follows < 6) {
                    follows++;
                    OITIInstallDescribe(value, [NSString stringWithFormat:@"%@.%s", label, name], depth + 1, seen, budget, compact);
                }
            } else if (interesting) {
                double number = NAN;
                NSString *text = OITIInstallIvarScalarText(object, ivars[i], type, &number);
                if (!text) continue;
                BOOL progressName = [lower containsString:@"progress"] || [lower containsString:@"fraction"] || [lower containsString:@"percent"];
                if (!isnan(number) && progressName) {
                    [sInstallFindings addObject:[NSString stringWithFormat:@"FRACTION %@ ivar %s = %@", label, name, text]];
                }
                if (!compact || progressName) {
                    OITIInstallLog(@"IVAR %@ %s = %@ [%s]", label, name, text, type);
                    (*budget)--;
                }
            }
        }
        free(ivars);
    }
}

// ---- The applications, placeholders and icons SpringBoard knows about -------------------------------------------

static NSArray *OITIInstallItemsFromResult(id result) {
    if ([result isKindOfClass:[NSArray class]]) return result;
    if ([result isKindOfClass:[NSSet class]]) return [(NSSet *)result allObjects];
    if ([result isKindOfClass:[NSOrderedSet class]]) return [(NSOrderedSet *)result array];
    if ([result isKindOfClass:[NSDictionary class]]) return [(NSDictionary *)result allValues];
    return nil;
}

id OITIInstallApplicationForBundleID(id applicationController, NSString *bundleID) {
    SEL selector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (!applicationController || ![applicationController respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL, id))objc_msgSend)(applicationController, selector, bundleID);
    } @catch (NSException *exception) {
        return nil;
    }
}

// Calls every collection getter of `owner` that names applications, placeholders or icons and adds what it holds.
static void OITIInstallGather(id owner, NSString *ownerName, id applicationController, NSMutableArray *items,
                              NSMutableSet<NSValue *> *itemSeen, BOOL compact) {
    if (!owner) return;
    for (Class cls = [owner class]; cls && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        NSSet<NSString *> *properties = OITIInstallPropertyGetters(cls);
        for (unsigned int i = 0; i < count; i++) {
            const char *cname = sel_getName(method_getName(methods[i]));
            if (!cname) continue;
            BOOL explicitName = [OITIInstallExplicitCollectionGetters() containsObject:@(cname)];
            BOOL property = [properties containsObject:@(cname)] && OITIInstallNameAllowed(cname, OITIInstallCollectionKeywords());
            if (!explicitName && !property) continue;
            NSString *text = nil;
            double number = NAN;
            id result = nil;
            if (!OITIInstallCallGetter(owner, methods[i], &text, &number, &result)) continue;
            NSArray *found = OITIInstallItemsFromResult(result);
            if (!found) continue;
            NSUInteger taken = 0, added = 0;
            for (id item in found) {
                if (taken++ >= kOITIInstallItemCap) break;
                id candidate = [item isKindOfClass:[NSString class]]
                    ? OITIInstallApplicationForBundleID(applicationController, item) : item;
                if (!candidate) continue;
                NSValue *key = [NSValue valueWithPointer:(__bridge const void *)candidate];
                if ([itemSeen containsObject:key]) continue;
                [itemSeen addObject:key];
                [items addObject:candidate];
                added++;
            }
            if (!compact) {
                OITIInstallLog(@"SOURCE %@ -%s -> %lu item(s), %lu new", ownerName, cname, (unsigned long)found.count, (unsigned long)added);
            }
        }
        free(methods);
    }
}

static void OITIInstallScanApps(BOOL compact, NSMutableSet<NSValue *> *seen, NSInteger *budget) {
    NSString *appHow = nil, *placeholderHow = nil, *iconHow = nil;
    id applicationController = OITIInstallSharedInstance(NSClassFromString(@"SBApplicationController"), &appHow);
    id placeholderController = OITIInstallSharedInstance(NSClassFromString(@"SBApplicationPlaceholderController"), &placeholderHow);
    id iconController = OITIInstallSharedInstance(NSClassFromString(@"SBIconController"), &iconHow);
    id iconManager = OITIInstallObjectGetter(iconController, @"iconManager");
    id iconModel = OITIInstallObjectGetter(iconManager, @"iconModel") ?: OITIInstallObjectGetter(iconController, @"iconModel");
    if (!compact) {
        OITIInstallLog(@"CONTROLLERS SBApplicationController=%@ (%@) SBApplicationPlaceholderController=%@ (%@) SBIconController=%@ (%@) iconManager=%@ iconModel=%@",
                       OITIInstallObjectText(applicationController), appHow ?: @"-",
                       OITIInstallObjectText(placeholderController), placeholderHow ?: @"-",
                       OITIInstallObjectText(iconController), iconHow ?: @"-",
                       OITIInstallObjectText(iconManager), OITIInstallObjectText(iconModel));
    }

    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet<NSValue *> *itemSeen = [NSMutableSet set];
    OITIInstallGather(applicationController, @"SBApplicationController", applicationController, items, itemSeen, compact);
    OITIInstallGather(placeholderController, @"SBApplicationPlaceholderController", applicationController, items, itemSeen, compact);
    OITIInstallGather(iconModel, @"iconModel", applicationController, items, itemSeen, compact);

    NSMutableDictionary<NSString *, NSNumber *> *histogram = [NSMutableDictionary dictionary];
    for (id item in items) {
        NSString *name = NSStringFromClass([item class]);
        histogram[name] = @(histogram[name].unsignedIntegerValue + 1);
    }
    if (!compact) {
        NSArray<NSString *> *names = [histogram keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [b compare:a];
        }];
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (NSString *name in names) {
            if (parts.count >= 10) break;
            [parts addObject:[NSString stringWithFormat:@"%@=%@", name, histogram[name]]];
        }
        OITIInstallLog(@"ITEMS %lu object(s) from the controllers: %@", (unsigned long)items.count,
                       parts.count ? [parts componentsJoinedByString:@", "] : @"(none: no collection getter answered)");
    }

    NSUInteger candidates = 0;
    for (id item in items) {
        BOOL placeholderClass = OITIInstallContainsWord(NSStringFromClass([item class]), @"Placeholder");
        NSArray<NSString *> *signals = OITIInstallActiveSignals(item);
        if (!placeholderClass && !signals.count) continue;
        if (++candidates > kOITIInstallCandidateCap) continue;
        OITIInstallLog(@"CANDIDATE #%lu %@ %@ placeholderClass=%d active=[%@]", (unsigned long)candidates,
                       NSStringFromClass([item class]), OITIInstallLabel(item), (int)placeholderClass,
                       [signals componentsJoinedByString:@", "]);
        OITIInstallDescribe(item, [NSString stringWithFormat:@"cand%lu", (unsigned long)candidates], 0, seen, budget, compact);
    }
    if (!compact || !candidates) {
        OITIInstallLog(@"CANDIDATES %lu (shown up to %lu): placeholder-class objects, or objects with a progress-like getter that is non-zero",
                       (unsigned long)candidates, (unsigned long)kOITIInstallCandidateCap);
    }
}

// ---- The icon views and progress views on screen ---------------------------------------------------------------

static NSArray<UIWindow *> *OITIInstallWindows(NSString **source) {
    SEL selector = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");
    if ([UIWindow respondsToSelector:selector]) {
        NSArray *windows = nil;
        @try {
            windows = ((NSArray *(*)(Class, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class], selector, YES, NO);
        } @catch (NSException *exception) {
            windows = nil;
        }
        if ([windows isKindOfClass:[NSArray class]] && windows.count) {
            *source = @"+[UIWindow allWindowsIncludingInternalWindows:onlyVisibleWindows:]";
            return windows;
        }
    }
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    *source = @"connectedScenes";
    return windows;
}

static void OITIInstallWalk(UIView *view, NSUInteger depth, BOOL inIconView, NSUInteger *visited,
                            NSMutableArray<UIView *> *progressViews, NSMutableArray<UIView *> *iconViews) {
    if (!view || *visited >= kOITIInstallViewVisitCap || depth > kOITIInstallViewDepthCap) return;
    (*visited)++;
    NSString *name = NSStringFromClass([view class]);
    BOOL isIconView = [name hasSuffix:@"IconView"];
    BOOL generic = [name hasPrefix:@"UI"] || [name hasPrefix:@"_UI"];
    if (OITIInstallContainsWord(name, @"Progress") && (!generic || inIconView) && progressViews.count < 200) {
        [progressViews addObject:view];
    }
    if (isIconView && iconViews.count < 600) [iconViews addObject:view];
    for (UIView *subview in view.subviews) {
        OITIInstallWalk(subview, depth + 1, inIconView || isIconView, visited, progressViews, iconViews);
    }
}

static NSString *OITIInstallViewPath(UIView *view) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    UIView *current = view;
    for (NSUInteger i = 0; current && i < 6; i++) {
        [names insertObject:NSStringFromClass([current class]) atIndex:0];
        current = current.superview;
    }
    return [names componentsJoinedByString:@" > "];
}

static void OITIInstallScanViews(BOOL compact, NSMutableSet<NSValue *> *seen, NSInteger *budget) {
    NSString *source = nil;
    NSArray<UIWindow *> *windows = OITIInstallWindows(&source);
    NSMutableArray<UIView *> *progressViews = [NSMutableArray array];
    NSMutableArray<UIView *> *iconViews = [NSMutableArray array];
    NSUInteger visited = 0;
    for (UIWindow *window in windows) OITIInstallWalk(window, 0, NO, &visited, progressViews, iconViews);
    if (!compact) {
        OITIInstallLog(@"VIEWS source=%@ windows=%lu visited=%lu iconViews=%lu progressViews=%lu%@", source,
                       (unsigned long)windows.count, (unsigned long)visited, (unsigned long)iconViews.count,
                       (unsigned long)progressViews.count, visited >= kOITIInstallViewVisitCap ? @" (visit cap hit)" : @"");
    }

    NSUInteger shown = 0;
    for (UIView *view in progressViews) {
        if (++shown > kOITIInstallViewMatchCap) break;
        OITIInstallLog(@"PROGRESSVIEW #%lu %@ | %@", (unsigned long)shown, OITIInstallViewPath(view), OITIViewLine(view));
        OITIInstallDescribe(view, [NSString stringWithFormat:@"progressView%lu", (unsigned long)shown], 0, seen, budget, compact);
        // The icon that owns this progress view, and the placeholder behind it (explicit accessors only).
        UIView *owner = view.superview;
        while (owner && ![NSStringFromClass([owner class]) hasSuffix:@"IconView"]) owner = owner.superview;
        id ownerIcon = OITIInstallObjectGetter(owner, @"icon");
        if (ownerIcon) {
            id placeholder = OITIInstallObjectGetter(ownerIcon, @"applicationPlaceholder");
            OITIInstallLog(@"PROGRESSICON #%lu owner=%@ icon=%@ %@ progressPercent=%@ progressState=%@ progressPaused=%@ placeholder=%@",
                           (unsigned long)shown, NSStringFromClass([owner class]), OITIInstallObjectText(ownerIcon),
                           OITIInstallLabel(ownerIcon), OITIInstallExplicitGetterText(ownerIcon, @"progressPercent"),
                           OITIInstallExplicitGetterText(ownerIcon, @"progressState"),
                           OITIInstallExplicitGetterText(ownerIcon, @"isProgressPaused"), OITIInstallObjectText(placeholder));
            OITIInstallDescribe(ownerIcon, [NSString stringWithFormat:@"progressIcon%lu", (unsigned long)shown], 0, seen, budget, compact);
            OITIInstallDescribe(placeholder, [NSString stringWithFormat:@"placeholder%lu", (unsigned long)shown], 0, seen, budget, compact);
        }
    }

    NSUInteger active = 0;
    for (UIView *view in iconViews) {
        id icon = OITIInstallObjectGetter(view, @"icon");
        NSArray<NSString *> *signals = [OITIInstallActiveSignals(view) arrayByAddingObjectsFromArray:OITIInstallActiveSignals(icon)];
        BOOL placeholderIcon = icon && OITIInstallContainsWord(NSStringFromClass([icon class]), @"Placeholder");
        if (!signals.count && !placeholderIcon) continue;
        if (++active > kOITIInstallViewMatchCap) continue;
        OITIInstallLog(@"ICONVIEW #%lu %@ | icon=%@ %@ placeholderIcon=%d active=[%@]", (unsigned long)active,
                       OITIInstallViewPath(view), OITIInstallObjectText(icon), OITIInstallLabel(icon), (int)placeholderIcon,
                       [signals componentsJoinedByString:@", "]);
        OITIInstallDescribe(view, [NSString stringWithFormat:@"iconView%lu", (unsigned long)active], 0, seen, budget, compact);
        OITIInstallDescribe(icon, [NSString stringWithFormat:@"icon%lu", (unsigned long)active], 0, seen, budget, compact);
    }
    if (!compact) {
        OITIInstallLog(@"ICONVIEWS %lu with progress or placeholder signals (shown up to %lu)", (unsigned long)active,
                       (unsigned long)kOITIInstallViewMatchCap);
        if (!iconViews.count) {
            OITIInstallLog(@"HINT no icon views were found: open the Home Screen page that shows the installing icon, then run the dump again");
        }
    }
}

// ---- Class discovery (snapshot only) -----------------------------------------------------------------------------

static void OITIInstallListClasses(void) {
    NSArray<NSString *> *patterns = @[@"placeholder", @"install", @"download", @"iconprogress", @"progressview", @"progressbar"];
    NSArray<NSString *> *skipPrefixes = @[@"UI", @"_UI", @"NS", @"_NS", @"CA", @"AV", @"WK", @"__"];
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *priority = [NSMutableArray array];
    NSMutableArray<NSString *> *others = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *cname = class_getName(classes[i]);
        if (!cname) continue;
        NSString *name = @(cname);
        BOOL skip = NO;
        for (NSString *prefix in skipPrefixes) {
            if ([name hasPrefix:prefix]) { skip = YES; break; }
        }
        if (skip) continue;
        NSString *lower = name.lowercaseString;
        BOOL match = NO;
        for (NSString *pattern in patterns) {
            if ([lower containsString:pattern]) { match = YES; break; }
        }
        if (!match) continue;
        const char *image = class_getImageName(classes[i]);
        const char *slash = image ? strrchr(image, '/') : NULL;
        Class parent = class_getSuperclass(classes[i]);
        NSString *entry = [NSString stringWithFormat:@"%@ : %s  image=%s", name, parent ? class_getName(parent) : "(root)",
                           slash ? slash + 1 : (image ?: "?")];
        BOOL isPriority = [name hasPrefix:@"SB"] || [name hasPrefix:@"IX"] || [name hasPrefix:@"MI"] ||
                          [name hasPrefix:@"FBS"] || [name hasPrefix:@"AS"];
        [(isPriority ? priority : others) addObject:entry];
    }
    free(classes);
    [priority sortUsingSelector:@selector(compare:)];
    [others sortUsingSelector:@selector(compare:)];
    NSArray<NSString *> *all = [priority arrayByAddingObjectsFromArray:others];
    OITIInstallLog(@"CLASSES %lu loaded class(es) match placeholder / install / download / progress view (SB, IX, MI, FBS and AS names first; UIKit, Foundation and CoreAnimation names skipped)",
                   (unsigned long)all.count);
    NSUInteger shown = 0;
    for (NSString *entry in all) {
        if (shown++ >= kOITIInstallClassListCap) {
            OITIInstallLog(@"CLASSES (list truncated at %lu)", (unsigned long)kOITIInstallClassListCap);
            break;
        }
        OITIInstallLog(@"CLASSES %@", entry);
    }
}

// Candidate classes from OVERVIEW.md. They are guesses: the output says which of them exist and lists their own methods
// that mention progress, install, download, placeholder, fractions or bytes.
static void OITIInstallProbeClasses(void) {
    NSArray<NSString *> *names = @[@"SBApplicationPlaceholder", @"SBApplicationPlaceholderController", @"SBApplicationController",
                                   @"SBApplication", @"SBIconController", @"SBHIconManager", @"SBIconModel", @"SBLeafIcon",
                                   @"SBApplicationIcon", @"SBIconView", @"SBIconProgressView", @"IXAppInstallCoordinator",
                                   @"IXPlaceholder", @"FBSApplicationPlaceholder", @"FBSApplicationPlaceholderProgress",
                                   @"SBHProxiedApplicationPlaceholder", @"SBApplicationPlaceholderProxy"];
    NSArray<NSString *> *words = @[@"progress", @"install", @"download", @"placeholder", @"fraction", @"percent", @"byte",
                                   @"paus", @"updat", @"status", @"phase"];
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (!cls) {
            OITIInstallLog(@"CLASSPROBE %@ not loaded in this process", name);
            continue;
        }
        NSMutableArray<NSString *> *chain = [NSMutableArray array];
        for (Class c = cls; c; c = class_getSuperclass(c)) [chain addObject:NSStringFromClass(c)];
        const char *image = class_getImageName(cls);
        const char *slash = image ? strrchr(image, '/') : NULL;
        OITIInstallLog(@"CLASSPROBE %@ present chain=%@ image=%s", name, [chain componentsJoinedByString:@" > "],
                       slash ? slash + 1 : (image ?: "?"));
        for (NSString *kind in @[@"-", @"+"]) {
            Class source = [kind isEqualToString:@"-"] ? cls : object_getClass(cls);
            unsigned int count = 0;
            Method *methods = class_copyMethodList(source, &count);
            NSUInteger shown = 0;
            for (unsigned int i = 0; i < count; i++) {
                const char *cname = sel_getName(method_getName(methods[i]));
                NSString *lower = @(cname).lowercaseString;
                BOOL match = NO;
                for (NSString *word in words) {
                    if ([lower containsString:word]) { match = YES; break; }
                }
                if (!match) continue;
                if (shown++ >= kOITIInstallProbeMethodCap) {
                    OITIInstallLog(@"CLASSPROBE %@ %@ (more matching methods not shown)", name, kind);
                    break;
                }
                const char *types = method_getTypeEncoding(methods[i]);
                OITIInstallLog(@"CLASSPROBE %@ %@%s [%s]", name, kind, cname, types ?: "?");
            }
            free(methods);
        }
    }
}

// ---- One scan, the snapshot, the samples ------------------------------------------------------------------------

static void OITIInstallVerdict(BOOL compact) {
    NSMutableArray<NSString *> *progress = [NSMutableArray array];
    NSMutableArray<NSString *> *fractions = [NSMutableArray array];
    for (NSString *finding in sInstallFindings) {
        if ([finding hasPrefix:@"NSPROGRESS "]) [progress addObject:finding];
        else [fractions addObject:finding];
    }
    if (compact) {
        OITIInstallLog(@"SUMMARY nsprogress=%lu fraction-values=%lu", (unsigned long)progress.count, (unsigned long)fractions.count);
        return;
    }
    for (NSString *finding in progress) OITIInstallLog(@"VERDICT %@", finding);
    if (!progress.count) {
        OITIInstallLog(@"VERDICT no NSProgress was reachable from the candidates, the icon views or the progress views");
    }
    NSUInteger shown = 0;
    for (NSString *finding in fractions) {
        if (shown++ >= 10) break;
        OITIInstallLog(@"VERDICT %@", finding);
    }
    if (!fractions.count) OITIInstallLog(@"VERDICT no numeric progress, fraction or percent value was found");
    OITIInstallLog(@"VERDICT how to read this: an NSPROGRESS line whose total is large (byte-like) and whose completed value grows between samples means real byte counts; total 100 or only FRACTION lines means a fraction only; nothing at all means the install was not visible (is the icon on the visible Home Screen page, and was the download running?)");
}

static void OITIInstallScan(BOOL compact) {
    sInstallFindings = [NSMutableArray array];
    NSMutableSet<NSValue *> *seen = [NSMutableSet set];
    NSInteger budget = compact ? 40 : 240;
    OITIInstallScanApps(compact, seen, &budget);
    OITIInstallScanViews(compact, seen, &budget);
    OITIInstallVerdict(compact);
    if (budget <= 0) OITIInstallLog(@"(output budget used up: some objects were not described)");
}

static void OITIInstallSamples(NSUInteger index, NSInteger total, NSInteger done, double interval) {
    if (done >= total) {
        sInstallPhase = @"snapshot";
        OITIInstallLog(@"=== END #%lu (%ld sample(s)) ===", (unsigned long)index, (long)total);
        sInstallDumpRunning = NO;
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * (double)NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!sLog.enabled || sLog.level < 1) {
            sInstallDumpRunning = NO;
            return;
        }
        sInstallPhase = [NSString stringWithFormat:@"sample %ld/%ld +%.0fs", (long)(done + 1), (long)total,
                         interval * (double)(done + 1)];
        @try {
            OITIInstallScan(YES);
        } @catch (NSException *exception) {
            OITIInstallLog(@"ERROR exception %@: %@", exception.name, exception.reason);
        }
        OITIInstallSamples(index, total, done + 1, interval);
    });
}

void OITIRunInstallDump(NSString *reason) {
    if (!sLog.enabled || sLog.level < 1) {
        [sLog logTag:@"INSTALL" format:@"install dump request ignored: DiagnosticsLevel is 0 (set it to 1 or 2 and respring)"];
        return;
    }
    if (sInstallDumpRunning) {
        [sLog logTag:@"INSTALL" format:@"install dump request ignored: the previous one is still taking samples"];
        return;
    }
    sInstallDumpRunning = YES;
    NSUInteger index = ++sInstallDumpCount;
    NSInteger samples = MAX(0, MIN(30, [sOITIPreferences integerForKey:@"InstallDumpSamples" default:6]));
    double interval = [sOITIPreferences floatForKey:@"InstallDumpIntervalSeconds" default:2.0];
    interval = isfinite(interval) ? MAX(1.0, MIN(10.0, interval)) : 2.0;
    sInstallCallGetters = [sOITIPreferences boolForKey:@"InstallDumpCallGetters" default:NO];
    sInstallPhase = @"snapshot";
    OITIInstallLog(@"=== BEGIN #%lu reason=%@ build=%@ os=%@ machine=%@ samples=%ld every %.0f s callGetters=%d ===", (unsigned long)index, reason,
                   kOITIBuildTag, [NSProcessInfo processInfo].operatingSystemVersionString, [OITDeviceInfo machineIdentifier],
                   (long)samples, interval, (int)sInstallCallGetters);
    @try {
        if (index == 1) {
            OITIInstallListClasses();
            OITIInstallProbeClasses();
        } else {
            OITIInstallLog(@"CLASSES and CLASSPROBE are written by the first run after a respring only");
        }
        OITIInstallScan(NO);
    } @catch (NSException *exception) {
        OITIInstallLog(@"ERROR exception %@: %@", exception.name, exception.reason);
    }
    OITIInstallSamples(index, samples, 0, interval);
}
