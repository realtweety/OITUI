// OITI -- Dynamic Island positioning/appearance module for OITUI (fork of VisibleIsland by ethxnn88).
//
// STEP 2 BUILD (UNTESTED on-device). Build tag: see kOITIBuildTag.
//
// Step 1 (device table, single %orig, didMoveToWindow fixes, matching defaults, clamped divisor, setFrame
// fall-through) is unchanged. Step 2 adds only logging, diagnostics and safety; no hook changes what it does:
//   1. OITLogger logging (/tmp/OITIDebug.log), see "Log tags" below.
//   2. Respring-loop guard: after repeated short-lived SpringBoard launches, OITI's hooks are not installed
//      (safe mode) until the safe-mode file is cleared.
//   3. Startup self-check of the MobileGestalt spoof (islandEnabled vs. the cache, and the restore breadcrumb).
//   4. On-demand dump of the Island window's view tree, view-controller tree, Apple's "aperture" classes and
//      the methods/ivars of any classes you list. This is the data the Step 3 research needs.
//   5. OITI now only does anything in SpringBoard. Its plist filter also loads it into every UIKit app; the
//      hooked classes only exist in SpringBoard, so apps used to run the constructor for nothing.
//
// X/Y SCALE (UNTESTED): the single "scale" value is replaced by separate width (scaleX) and height (scaleY) scales
// applied as one non-uniform transform on the Island window. Contents stretch with it. An existing single "scale"
// value is used for both axes until scaleX/scaleY are set. Changing any setting now asks the Island window to lay out
// again, so changes show up immediately instead of at the next layout Apple happens to do.
//
// Log file:      /tmp/OITIDebug.log   (rotates at 6 MB to /tmp/OITIDebug.log.1)
// Dump trigger:  touch /tmp/OITIDump.trigger        (polled once a second; detected by modification time)
//                or Darwin notification com.wilburt.oiti/Dump
// Class query:   put class names, one per line, in /tmp/OITIClassQuery.txt before triggering a dump
// Clear safe mode: rm /var/mobile/Library/Preferences/OITISafeMode.plist  (or notification
//                com.wilburt.oiti/ClearSafeMode), then respring
// Prefs keys (domain com.wilburt.oiti.prefs, set with `defaults write`, no UI yet):
//   DiagnosticsEnabled (bool, default YES)      DiagnosticsLevel (0-2, default 0)
//   SafeModeGuardEnabled (bool, default YES)    SafeModeMaxLaunches (int, default 5)
//   SafeModeWindowSeconds (int, default 120)    SafeModeStableSeconds (int, default 45)
//   SafeModeRestoreGestalt (bool, default NO)   -- on a trip, also run the OITIRestoreGestalt helper
//
// Log tags: SESSION PREF GUARD SAFE CHECK ISLAND LAYOUT CURTAIN GAINMAP COLOR TOUCHPASS BANNER DUMP CLASSQ
// Levels:   0 = unconditional lines only, 1 = events and state changes, 2 = adds rate-limited per-call lines.
// Default is 0, so a normal install writes only the SESSION, GUARD, SAFE and CHECK lines (about a dozen per boot,
// including every warning), runs no polling timer and tracks no windows for dumps. For development raise it:
//   defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1     (then sbreload)

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <math.h>
#import <string.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>
#import <OITCore/OITCore.h>
#import "OITIDeviceProfiles.h"

extern char **environ;

static NSString * const kOITIBuildTag = @"OITI-exp-2026-10-09-b";
static NSString * const kOITIPrefsDomain = @"com.wilburt.oiti.prefs";
static NSString * const kOITIPrefsChangedNotification = @"com.wilburt.oiti/PrefsChanged";
static NSString * const kOITIDumpNotification = @"com.wilburt.oiti/Dump";
static NSString * const kOITIClearSafeModeNotification = @"com.wilburt.oiti/ClearSafeMode";

static NSString * const kOITILogPath = @"/tmp/OITIDebug.log";
static NSString * const kOITIDumpTriggerPath = @"/tmp/OITIDump.trigger";
static NSString * const kOITIClassQueryPath = @"/tmp/OITIClassQuery.txt";

static NSString * const kOITIBootLogPath = @"/var/mobile/Library/Preferences/OITIBootLog.plist";
static NSString * const kOITISafeModePath = @"/var/mobile/Library/Preferences/OITISafeMode.plist";
static NSString * const kOITIGestaltBackupBreadcrumbPath = @"/var/mobile/Library/Preferences/OITIGestaltBackup.plist";
static NSString * const kOITIGestaltPlistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static NSString * const kOITIGestaltCacheExtraKey = @"CacheExtra";
static NSString * const kOITIGestaltNestedKey = @"oPeik/9e8lQWMszEjbPzng";
static NSString * const kOITIGestaltLeafKey = @"ArtworkDeviceSubType";
static const char * const kOITIRestoreHelperPath = "/var/jb/usr/libexec/OITIRestoreGestalt";

static const NSUInteger kOITIDumpMaxLines = 800;
static const NSUInteger kOITIDumpMaxDepth = 16;
static const NSUInteger kOITIClassListMaxLines = 800;
static const NSUInteger kOITIClassQueryMethodCap = 250;

static CGFloat red = 0.0;
static CGFloat green = 0.0;
static CGFloat blue = 0.0;
static CGFloat alpha = 1.0;

static CGFloat scale = 1.0;    // legacy single scale; only a fallback for scaleX/scaleY now
static CGFloat scaleX = 1.0;
static CGFloat scaleY = 1.0;

static CGFloat xPos = 0;
static CGFloat yPos = 20.5;
static CGFloat xNot = 0.0;
static CGFloat yNot = 40;

static BOOL fixEnabled;
static BOOL islandEnabled;
static BOOL posEnabled;
static BOOL hideEnabled;
static BOOL notificationFix;
static BOOL notEnabled;
static BOOL colorEnabled;
static BOOL transEnabled;
static BOOL scaleEnabled;
static BOOL lineDisabled;

// Diagnostics and safe-mode settings (prefs keys listed in the header comment).
static BOOL sGuardEnabled = YES;
static NSInteger sGuardMaxLaunches = 5;
static NSInteger sGuardWindowSeconds = 120;
static NSInteger sGuardStableSeconds = 45;
static BOOL sGuardRestoreGestalt = NO;

static const void *kOITIAppliedScaleKey = &kOITIAppliedScaleKey;
static const void *kOITIHiddenByUsKey = &kOITIHiddenByUsKey;
static const void *kOITIColorAppliedKey = &kOITIColorAppliedKey;

static OITLogger *sLog;
static OITPreferences *sOITIPreferences;
static NSDictionary<NSString *, NSNumber *> *sLastPrefSnapshot;
static BOOL sSafeModeActive = NO;

// Weak references to the live instances our hooks have seen; used only by the dump.
static NSHashTable<UIView *> *sApertureWindows;
static NSHashTable<UIView *> *sLiveApertureWindows;   // always maintained: used to re-layout after a setting changes
static NSHashTable<UIView *> *sBannerWindows;
static BOOL sAutoDumpScheduled = NO;
static NSUInteger sDumpCount = 0;
static dispatch_source_t sDumpTriggerTimer;
static int64_t sLastTriggerMtimeNs = 0;

@interface SBSystemApertureWindow : UIView
@end

@interface _SBSystemApertureMagiciansCurtainView : UIView
@end

@interface SBBannerWindow : UIView
@end

@interface _SBGainMapView : UIView
@end

@interface _SBSystemApertureContainerViewContentView : UIView
@end

@interface SBFTouchPassThroughView : UIView
@end

static CGFloat OITISafeScaleValue(CGFloat value) {
    if (!isfinite(value)) return 1.0;
    if (value < 0.05) return 1.0;
    if (value > 3.0) return 3.0;
    return value;
}

// Resolved once. NULL means "this device has no built-in offsets" (for example an iPhone 8 / 8 Plus).
static const OITIDeviceProfile *OITICurrentProfile(void) {
    static const OITIDeviceProfile *profile;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        profile = OITIProfileForModel([OITDeviceInfo machineIdentifier]);
    });
    return profile;
}

// =============================================================================================
// MARK: Preferences snapshot (for CHANGED logging and the dump)
// =============================================================================================

static NSDictionary<NSString *, NSNumber *> *OITIPrefSnapshot(void) {
    return @{
        @"fixEnabled": @(fixEnabled), @"islandEnabled": @(islandEnabled), @"posEnabled": @(posEnabled),
        @"hideEnabled": @(hideEnabled), @"notificationFix": @(notificationFix), @"notEnabled": @(notEnabled),
        @"colorEnabled": @(colorEnabled), @"transEnabled": @(transEnabled), @"scaleEnabled": @(scaleEnabled),
        @"lineDisabled": @(lineDisabled),
        @"xPos": @(xPos), @"yPos": @(yPos), @"xNot": @(xNot), @"yNot": @(yNot),
        @"red": @(red), @"green": @(green), @"blue": @(blue), @"alpha": @(alpha), @"scale": @(scale), @"scaleX": @(scaleX), @"scaleY": @(scaleY),
    };
}

static NSString *OITIPrefSnapshotString(NSDictionary<NSString *, NSNumber *> *snapshot) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in [snapshot.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, snapshot[key]]];
    }
    return [parts componentsJoinedByString:@" "];
}

// =============================================================================================
// MARK: Island position (unchanged from Step 1)
// =============================================================================================

// Moves the Island window to the built-in (fixEnabled) or custom (posEnabled) position.
// The built-in table wins when both are on, as before. On a device with no table entry, "fixEnabled" falls back
// to the custom position.
static void OITIApplyIslandPosition(UIView *window) {
    CGFloat sx = scaleEnabled ? OITISafeScaleValue(scaleX) : 1.0;
    CGFloat sy = scaleEnabled ? OITISafeScaleValue(scaleY) : 1.0;
    CGRect frame = window.frame;
    const OITIDeviceProfile *profile = fixEnabled ? OITICurrentProfile() : NULL;

    if (profile) {
        frame.origin.y = profile->islandY / sy;
    } else if (posEnabled) {
        frame.origin.y = yPos / sy;
        // Original behavior: with scaling on, only override x when it is set; without scaling, always set it.
        if (!scaleEnabled || xPos > 0) frame.origin.x = xPos / sx;
    } else {
        return;
    }

    if (!CGRectEqualToRect(frame, window.frame)) window.frame = frame;
}

// Notification banner window position. Returns YES and fills `out` when an override applies.
//  - notificationFix: use the device's built-in banner position. Devices with no table entry are left untouched.
//  - notEnabled: custom origin (xNot, yNot); devices with no table entry keep the system's size.
static BOOL OITIBannerFrame(CGRect incoming, CGRect *out) {
    const OITIDeviceProfile *profile = OITICurrentProfile();
    if (notificationFix) {
        if (!profile) return NO;
        *out = CGRectMake(0, profile->bannerY, profile->bannerWidth, profile->bannerHeight);
        return YES;
    }
    if (notEnabled) {
        CGSize size = profile ? CGSizeMake(profile->bannerWidth, profile->bannerHeight) : incoming.size;
        *out = CGRectMake(xNot, yNot, size.width, size.height);
        return YES;
    }
    return NO;
}

// =============================================================================================
// MARK: Dump helpers
// =============================================================================================

static NSString *OITIColorDesc(UIColor *color) {
    if (!color) return @"nil";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.2f,%.2f,%.2f,%.2f)", r, g, b, a];
    }
    return [NSString stringWithFormat:@"%@", color];
}

static NSString *OITITextOfView(UIView *view) {
    if (![view respondsToSelector:@selector(text)]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id value = [view performSelector:@selector(text)];
#pragma clang diagnostic pop
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

static NSString *OITIViewLine(UIView *view) {
    NSMutableString *line = [NSMutableString stringWithFormat:@"%@@%p frame=%@ bounds=%@ alpha=%.2f subviews=%lu",
                             NSStringFromClass([view class]), view, NSStringFromCGRect(view.frame),
                             NSStringFromCGRect(view.bounds), view.alpha, (unsigned long)view.subviews.count];
    if (view.hidden) [line appendString:@" HIDDEN"];
    if (!CGAffineTransformIsIdentity(view.transform)) {
        [line appendFormat:@" transform=%@", NSStringFromCGAffineTransform(view.transform)];
    }
    if (!view.userInteractionEnabled) [line appendString:@" noInteraction"];
    if (view.clipsToBounds) [line appendString:@" clips"];
    if (view.layer.cornerRadius > 0) [line appendFormat:@" cornerRadius=%.1f", view.layer.cornerRadius];
    if (view.backgroundColor) [line appendFormat:@" bg=%@", OITIColorDesc(view.backgroundColor)];
    if (![view.layer isMemberOfClass:[CALayer class]]) {
        [line appendFormat:@" layer=%@", NSStringFromClass([view.layer class])];
    }
    NSString *text = OITITextOfView(view);
    if (text.length) [line appendFormat:@" text=\"%@\"", text];
    UIResponder *next = view.nextResponder;
    if ([next isKindOfClass:[UIViewController class]]) {
        [line appendFormat:@" vc=%@@%p", NSStringFromClass([next class]), next];
    }
    return line;
}

static void OITIDumpViewTree(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (!view) return;
    if (*budget == 0) return;
    (*budget)--;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    [sLog logTag:@"DUMP" format:@"TREE %@%@", indent, OITIViewLine(view)];
    if (depth >= kOITIDumpMaxDepth) {
        if (view.subviews.count) {
            [sLog logTag:@"DUMP" format:@"TREE %@  ...(%lu subview(s) not shown, depth limit)",
             indent, (unsigned long)view.subviews.count];
        }
        return;
    }
    for (UIView *subview in view.subviews) {
        OITIDumpViewTree(subview, depth + 1, budget);
    }
}

static void OITIDumpViewControllerTree(UIViewController *controller, NSUInteger depth, NSString *relation) {
    if (!controller || depth > 8) return;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    [sLog logTag:@"DUMP" format:@"VC %@%@%@@%p view=%@", indent, relation,
     NSStringFromClass([controller class]), controller,
     controller.isViewLoaded ? NSStringFromClass([controller.view class]) : @"(not loaded)"];
    for (UIViewController *child in controller.childViewControllers) {
        OITIDumpViewControllerTree(child, depth + 1, @"child ");
    }
    if (controller.presentedViewController) {
        OITIDumpViewControllerTree(controller.presentedViewController, depth + 1, @"presented ");
    }
}

static void OITIDumpTrackedWindow(UIView *view, NSString *label) {
    [sLog logTag:@"DUMP" format:@"WINDOW %@ %@", label, OITIViewLine(view)];
    if ([view isKindOfClass:[UIWindow class]]) {
        UIWindow *window = (UIWindow *)view;
        [sLog logTag:@"DUMP" format:@"WINDOW %@ level=%.1f key=%d scene=%@ rootVC=%@", label,
         window.windowLevel, window.isKeyWindow,
         window.windowScene ? NSStringFromClass([window.windowScene class]) : @"nil",
         window.rootViewController ? NSStringFromClass([window.rootViewController class]) : @"nil"];
        OITIDumpViewControllerTree(window.rootViewController, 0, @"root ");
    }
    NSUInteger budget = kOITIDumpMaxLines;
    OITIDumpViewTree(view, 0, &budget);
    if (budget == 0) {
        [sLog logTag:@"DUMP" format:@"TREE (output truncated at %lu lines)", (unsigned long)kOITIDumpMaxLines];
    }
}

static void OITIDumpEnvironment(void) {
    UIScreen *screen = [UIScreen mainScreen];
    const OITIDeviceProfile *profile = OITICurrentProfile();
    [sLog logTag:@"DUMP" format:@"ENV build=%@ machine=%@ os=%@ screen=%@ scale=%.1f",
     kOITIBuildTag, [OITDeviceInfo machineIdentifier],
     [NSProcessInfo processInfo].operatingSystemVersionString,
     NSStringFromCGRect(screen.bounds), screen.scale];
    if (profile) {
        [sLog logTag:@"DUMP" format:@"ENV profile islandY=%.2f bannerY=%.2f bannerSize=%.1fx%.1f verified=%d",
         (double)profile->islandY, (double)profile->bannerY, (double)profile->bannerWidth,
         (double)profile->bannerHeight, (int)profile->verified];
    } else {
        [sLog logTag:@"DUMP" format:@"ENV profile=none (no built-in offsets for this device)"];
    }
    [sLog logTag:@"DUMP" format:@"ENV isFullScreenDevice=%d hasDynamicIsland=%d safeMode=%d",
     [OITDeviceInfo isFullScreenDevice], [OITDeviceInfo hasDynamicIsland], sSafeModeActive];
    [sLog logTag:@"DUMP" format:@"PREFS %@", OITIPrefSnapshotString(OITIPrefSnapshot())];
}

static void OITIDumpWindowsOverview(void) {
    NSUInteger index = 0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            BOOL tracked = [sApertureWindows containsObject:window] || [sBannerWindows containsObject:window];
            [sLog logTag:@"DUMP" format:@"WINDOWS #%lu %@@%p level=%.1f hidden=%d frame=%@ tracked=%d",
             (unsigned long)index++, NSStringFromClass([window class]), window, window.windowLevel,
             window.hidden, NSStringFromCGRect(window.frame), tracked];
        }
    }
    if (index == 0) {
        [sLog logTag:@"DUMP" format:@"WINDOWS none visible through connectedScenes (SpringBoard windows are often not listed there)"];
    }
}

// Apple's Island classes: every loaded class whose name contains "aperture", with the image that owns it.
static void OITIDumpApertureClasses(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (!name || !strcasestr(name, "aperture")) continue;
        const char *image = class_getImageName(classes[i]);
        const char *slash = image ? strrchr(image, '/') : NULL;
        Class super = class_getSuperclass(classes[i]);
        [lines addObject:[NSString stringWithFormat:@"%s : %s  image=%s", name,
                          super ? class_getName(super) : "(root)", slash ? slash + 1 : (image ?: "?")]];
    }
    free(classes);
    [lines sortUsingSelector:@selector(compare:)];
    [sLog logTag:@"DUMP" format:@"CLASSES %lu loaded class(es) with \"aperture\" in the name", (unsigned long)lines.count];
    NSUInteger shown = 0;
    for (NSString *line in lines) {
        if (shown++ >= kOITIClassListMaxLines) {
            [sLog logTag:@"DUMP" format:@"CLASSES (truncated at %lu)", (unsigned long)kOITIClassListMaxLines];
            break;
        }
        [sLog logTag:@"DUMP" format:@"CLASSES %@", line];
    }
}

static void OITIDumpMethods(Class cls, NSString *kind) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    [sLog logTag:@"CLASSQ" format:@"  %@ methods: %u", kind, count];
    for (unsigned int i = 0; i < count && i < kOITIClassQueryMethodCap; i++) {
        const char *types = method_getTypeEncoding(methods[i]);
        [sLog logTag:@"CLASSQ" format:@"    %@ %s  [%s]", kind, sel_getName(method_getName(methods[i])), types ?: "?"];
    }
    if (count > kOITIClassQueryMethodCap) {
        [sLog logTag:@"CLASSQ" format:@"    (%u more %@ method(s) not shown)", count - (unsigned int)kOITIClassQueryMethodCap, kind];
    }
    free(methods);
}

// Describes every class named in /tmp/OITIClassQuery.txt: superclass chain, protocols, ivars and methods.
static void OITIDumpQueriedClasses(void) {
    NSString *contents = [NSString stringWithContentsOfFile:kOITIClassQueryPath encoding:NSUTF8StringEncoding error:nil];
    if (!contents.length) {
        [sLog logTag:@"CLASSQ" format:@"no class query (%@ missing or empty)", kOITIClassQueryPath];
        return;
    }
    for (NSString *rawLine in [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *name = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!name.length || [name hasPrefix:@"#"]) continue;
        Class cls = NSClassFromString(name);
        if (!cls) {
            [sLog logTag:@"CLASSQ" format:@"%@ -- class not found in this process", name];
            continue;
        }
        NSMutableArray<NSString *> *chain = [NSMutableArray array];
        for (Class c = cls; c; c = class_getSuperclass(c)) [chain addObject:NSStringFromClass(c)];
        const char *image = class_getImageName(cls);
        [sLog logTag:@"CLASSQ" format:@"%@  chain=%@  image=%s", name, [chain componentsJoinedByString:@" > "], image ?: "?"];

        unsigned int protocolCount = 0;
        Protocol * __unsafe_unretained *protocols = class_copyProtocolList(cls, &protocolCount);
        NSMutableArray<NSString *> *protocolNames = [NSMutableArray array];
        for (unsigned int i = 0; i < protocolCount; i++) [protocolNames addObject:@(protocol_getName(protocols[i]))];
        free(protocols);
        [sLog logTag:@"CLASSQ" format:@"  protocols: %@", protocolNames.count ? [protocolNames componentsJoinedByString:@", "] : @"(none)"];

        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        [sLog logTag:@"CLASSQ" format:@"  ivars: %u", ivarCount];
        for (unsigned int i = 0; i < ivarCount && i < 60; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            [sLog logTag:@"CLASSQ" format:@"    %s  [%s]", ivar_getName(ivars[i]) ?: "?", type ?: "?"];
        }
        free(ivars);

        OITIDumpMethods(cls, @"-");
        OITIDumpMethods(object_getClass(cls), @"+");
    }
}

static void OITIRunDump(NSString *reason) {
    if (!sLog.enabled) return;
    NSUInteger index = ++sDumpCount;
    [sLog logTag:@"DUMP" format:@"=== BEGIN #%lu reason=%@ ===", (unsigned long)index, reason];
    OITIDumpEnvironment();
    OITIDumpWindowsOverview();

    NSArray<UIView *> *apertureWindows = sApertureWindows.allObjects;
    NSArray<UIView *> *bannerWindows = sBannerWindows.allObjects;
    if (!apertureWindows.count) {
        [sLog logTag:@"DUMP" format:@"WINDOW no SBSystemApertureWindow seen yet (hooks not installed, safe mode, or the Island has not laid out)"];
    }
    for (UIView *window in apertureWindows) OITIDumpTrackedWindow(window, @"SBSystemApertureWindow");
    for (UIView *window in bannerWindows) OITIDumpTrackedWindow(window, @"SBBannerWindow");

    OITIDumpApertureClasses();
    OITIDumpQueriedClasses();
    [sLog logTag:@"DUMP" format:@"=== END #%lu ===", (unsigned long)index];
}

static int64_t OITITriggerFileMtimeNs(void) {
    struct stat st;
    if (stat(kOITIDumpTriggerPath.fileSystemRepresentation, &st) != 0) return 0;
    return (int64_t)st.st_mtimespec.tv_sec * 1000000000ll + (int64_t)st.st_mtimespec.tv_nsec;
}

// Polls the trigger file once a second, but only while diagnostics are on (DiagnosticsLevel >= 1), so a normal
// install runs no timer at all. Detects by modification time, never deletes (/tmp is sticky).
static void OITIUpdateDumpTrigger(void) {
    BOOL wanted = sLog.enabled && sLog.level >= 1;
    if (wanted && !sDumpTriggerTimer) {
        sLastTriggerMtimeNs = OITITriggerFileMtimeNs();
        sDumpTriggerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(sDumpTriggerTimer,
                                  dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                                  NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(sDumpTriggerTimer, ^{
            if (!sLog.enabled || sLog.level < 1) return;
            int64_t mtime = OITITriggerFileMtimeNs();
            if (mtime != 0 && mtime != sLastTriggerMtimeNs) {
                sLastTriggerMtimeNs = mtime;
                OITIRunDump(@"trigger-file");
            }
        });
        dispatch_resume(sDumpTriggerTimer);
        [sLog logLevel:1 tag:@"DUMP" format:@"trigger polling started (touch %@)", kOITIDumpTriggerPath];
    } else if (!wanted && sDumpTriggerTimer) {
        dispatch_source_cancel(sDumpTriggerTimer);
        sDumpTriggerTimer = nil;
    }
}

// The Darwin notification is passive (no timer), so it is registered once at launch.
static void OITIObserveDumpNotification(void) {
    OITObserveDarwinNotification(kOITIDumpNotification, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sLog.enabled && sLog.level >= 1) {
                OITIRunDump(@"darwin-notification");
            } else {
                [sLog logTag:@"DUMP" format:@"dump request ignored: DiagnosticsLevel is 0 (set it to 1 or 2 and respring)"];
            }
        });
    });
}

// One baseline dump a few seconds after the Island first lays out.
static void OITIScheduleAutoDump(void) {
    if (sAutoDumpScheduled) return;
    sAutoDumpScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (sLog.enabled && sLog.level >= 1) OITIRunDump(@"auto-baseline");
    });
}

// =============================================================================================
// MARK: Respring-loop guard
// =============================================================================================

static void OITIRunRestoreHelper(void) {
    if (access(kOITIRestoreHelperPath, X_OK) != 0) {
        [sLog logTag:@"SAFE" format:@"restore helper not found or not executable at %s", kOITIRestoreHelperPath];
        return;
    }
    pid_t pid = 0;
    char *argv[] = { (char *)kOITIRestoreHelperPath, NULL };
    int rc = posix_spawn(&pid, kOITIRestoreHelperPath, NULL, NULL, argv, environ);
    if (rc != 0) {
        [sLog logTag:@"SAFE" format:@"posix_spawn of restore helper failed rc=%d", rc];
        return;
    }
    [sLog logTag:@"SAFE" format:@"restore helper started pid=%d", pid];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int status = 0;
        waitpid(pid, &status, 0);
        [sLog logTag:@"SAFE" format:@"restore helper exited status=%d", WIFEXITED(status) ? WEXITSTATUS(status) : -1];
    });
}

// Returns YES when OITI must stay in safe mode (hooks not installed) for this launch.
static BOOL OITIEvaluateLoopGuard(void) {
    if (!sGuardEnabled) {
        [sLog logTag:@"GUARD" format:@"disabled by SafeModeGuardEnabled"];
        return NO;
    }

    NSDictionary *flag = [NSDictionary dictionaryWithContentsOfFile:kOITISafeModePath];
    if ([flag[@"tripped"] boolValue]) {
        [sLog logTag:@"SAFE" format:@"safe mode still active (tripped at %@, reason: %@). Clear with: rm %@",
         flag[@"time"], flag[@"reason"], kOITISafeModePath];
        return YES;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDictionary *bootLog = [NSDictionary dictionaryWithContentsOfFile:kOITIBootLogPath];
    NSMutableArray<NSNumber *> *launches = [NSMutableArray array];
    id stored = bootLog[@"launches"];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)stored) {
            if (![entry isKindOfClass:[NSNumber class]]) continue;
            NSTimeInterval age = now - [entry doubleValue];
            if (age >= 0 && age < (NSTimeInterval)sGuardWindowSeconds) [launches addObject:entry];
        }
    }
    [launches addObject:@(now)];
    while (launches.count > 16) [launches removeObjectAtIndex:0];
    [@{ @"launches": launches } writeToFile:kOITIBootLogPath atomically:YES];

    [sLog logTag:@"GUARD" format:@"SpringBoard launches in the last %ld s: %lu (trip at %ld)",
     (long)sGuardWindowSeconds, (unsigned long)launches.count, (long)sGuardMaxLaunches];

    if ((NSInteger)launches.count >= sGuardMaxLaunches) {
        NSString *reason = [NSString stringWithFormat:@"%lu SpringBoard launches within %ld s",
                            (unsigned long)launches.count, (long)sGuardWindowSeconds];
        [@{ @"tripped": @YES, @"time": @(now), @"reason": reason, @"build": kOITIBuildTag }
            writeToFile:kOITISafeModePath atomically:YES];
        [sLog logTag:@"SAFE" format:@"TRIPPED: %@. OITI hooks will not be installed. Clear with: rm %@",
         reason, kOITISafeModePath];
        if (sGuardRestoreGestalt) {
            [sLog logTag:@"SAFE" format:@"SafeModeRestoreGestalt is on: running the restore helper"];
            OITIRunRestoreHelper();
        } else {
            [sLog logTag:@"SAFE" format:@"SafeModeRestoreGestalt is off: the MobileGestalt spoof was left as is"];
        }
        return YES;
    }

    // A launch that stays up long enough is not part of a loop: forget the history.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)sGuardStableSeconds * (int64_t)NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [@{ @"launches": @[] } writeToFile:kOITIBootLogPath atomically:YES];
        [sLog logTag:@"GUARD" format:@"stable for %ld s: launch history cleared", (long)sGuardStableSeconds];
    });
    return NO;
}

// =============================================================================================
// MARK: Startup self-check (MobileGestalt spoof)
// =============================================================================================

// 2556 is the spoofed value. iOS 16 only ever runs on one model that natively reports it (iPhone 14 Pro).
// Keep in sync with OITIMachineHasNativeIsland in OITIRootListController.m.
static BOOL OITIMachineHasNativeIsland(NSString *machine) {
    return [machine isEqualToString:@"iPhone15,2"];
}

static void OITIRunStartupSelfCheck(void) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
    if (!plist) {
        [sLog logTag:@"CHECK" format:@"WARN MobileGestalt cache not readable at the expected path; cannot verify the spoof"];
        return;
    }
    id value = ((NSDictionary *)((NSDictionary *)plist[kOITIGestaltCacheExtraKey])[kOITIGestaltNestedKey])[kOITIGestaltLeafKey];
    BOOL isSpoofed = [value isKindOfClass:[NSNumber class]] && [value integerValue] == 2556;

    NSString *machine = [OITDeviceInfo machineIdentifier];
    BOOL nativeIsland = OITIMachineHasNativeIsland(machine);

    NSDictionary *breadcrumb = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltBackupBreadcrumbPath];
    BOOL haveBreadcrumb = [breadcrumb[@"BackupCaptured"] boolValue];
    BOOL originalPresent = [breadcrumb[@"OriginalValuePresent"] boolValue];
    id originalValue = breadcrumb[@"OriginalValue"];
    BOOL backupSuspect = [breadcrumb[@"CaptureSuspect"] boolValue];
    // The backup says the "original" value was the spoof value, on hardware that is not Island hardware: it was
    // captured while the spoof was already active, so restoring it can never remove the spoof.
    BOOL backupHoldsSpoofValue = haveBreadcrumb && originalPresent &&
        [originalValue isKindOfClass:[NSNumber class]] && [originalValue integerValue] == 2556 && !nativeIsland;

    [sLog logTag:@"CHECK" format:@"ArtworkDeviceSubType in cache=%@ islandEnabled=%d machine=%@ nativeIsland=%d | breadcrumb=%d originalPresent=%d original=%@ captureSuspect=%d",
     value ?: @"(absent)", islandEnabled, machine, nativeIsland, haveBreadcrumb, originalPresent,
     originalValue ?: @"(none)", backupSuspect];

    BOOL warned = NO;
    if (backupHoldsSpoofValue) {
        warned = YES;
        [sLog logTag:@"CHECK" format:@"WARN the restore breadcrumb records 2556 as the ORIGINAL ArtworkDeviceSubType, but 2556 is the spoof value and %@ is not Dynamic Island hardware. The backup was captured while the spoof was already active, so restoring it cannot remove the spoof (this also affects the prerm helper). Open OITI's settings page once: it repairs the backup. Then check the next CHECK line after a respring.", machine];
    }
    if (islandEnabled && !isSpoofed) {
        warned = YES;
        [sLog logTag:@"CHECK" format:@"WARN islandEnabled is ON but the cache does not hold 2556: the Island spoof is not active (iOS update rebuilt the cache, or something restored it)"];
    } else if (!islandEnabled && isSpoofed) {
        warned = YES;
        if (backupHoldsSpoofValue) {
            [sLog logTag:@"CHECK" format:@"WARN islandEnabled is OFF but the cache still holds 2556, and the poisoned backup (above) cannot remove it. Repair the backup first, then turn islandEnabled off again."];
        } else {
            [sLog logTag:@"CHECK" format:@"WARN islandEnabled is OFF but the cache still holds 2556: a stale spoof was left behind (the restore did not run, or did not take effect)"];
        }
    }
    if (islandEnabled && !haveBreadcrumb) {
        warned = YES;
        [sLog logTag:@"CHECK" format:@"WARN islandEnabled is ON but there is no restore breadcrumb: the prerm helper cannot restore the original value"];
    }
    if (backupSuspect && !backupHoldsSpoofValue) {
        [sLog logTag:@"CHECK" format:@"INFO the backup was repaired: the original is recorded as absent, so turning islandEnabled off (or uninstalling) removes the key and lets iOS recompute the real value"];
    }
    if (!warned) {
        [sLog logTag:@"CHECK" format:@"OK spoof state matches islandEnabled"];
    }
}

// =============================================================================================
// MARK: Hooks
// =============================================================================================

%group OITIHooks

%hook SBSystemApertureWindow

- (void)layoutSubviews {
    CGRect before = self.frame;

    if (scaleEnabled) {
        CGAffineTransform wanted = CGAffineTransformMakeScale(OITISafeScaleValue(scaleX), OITISafeScaleValue(scaleY));
        if (!CGAffineTransformEqualToTransform(self.transform, wanted)) self.transform = wanted;
        objc_setAssociatedObject(self, kOITIAppliedScaleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (objc_getAssociatedObject(self, kOITIAppliedScaleKey)) {
        // Turning scaling off resets the old transform live.
        self.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(self, kOITIAppliedScaleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    %orig;
    CGRect afterOrig = self.frame;
    OITIApplyIslandPosition(self);

    if (![sLiveApertureWindows containsObject:self]) [sLiveApertureWindows addObject:self];

    if ([sLog isLoggingAtLevel:1]) {
        [sApertureWindows addObject:self];
        OITIScheduleAutoDump();
        NSString *signature = [NSString stringWithFormat:@"frame=%@ bounds=%@ xf=%@ fix=%d pos=%d scale=%d sx=%.3f sy=%.3f",
                               NSStringFromCGRect(self.frame), NSStringFromCGRect(self.bounds),
                               NSStringFromCGAffineTransform(self.transform),
                               fixEnabled, posEnabled, scaleEnabled, scaleX, scaleY];
        if ([sLog noteSignature:signature forObject:self]) {
            [sLog logLevel:1 tag:@"ISLAND" format:@"%@@%p changed: %@ (profile=%d)",
             NSStringFromClass([self class]), self, signature, OITICurrentProfile() != NULL];
        }
    }
    OITLOGGER_LOG_RATED(sLog, 2, @"LAYOUT", @"island.layout", 5,
                        @"before=%@ afterOrig=%@ final=%@",
                        NSStringFromCGRect(before), NSStringFromCGRect(afterOrig), NSStringFromCGRect(self.frame));
}

%end

%hook _SBSystemApertureMagiciansCurtainView

- (void)didMoveToWindow {
    %orig;
    BOOL shouldHide = fixEnabled || posEnabled || scaleEnabled;
    if (shouldHide) {
        if (!self.hidden) self.hidden = YES;
        objc_setAssociatedObject(self, kOITIHiddenByUsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (objc_getAssociatedObject(self, kOITIHiddenByUsKey)) {
        // Only undo our own hiding, instead of force-unhiding a view Apple may have hidden itself.
        self.hidden = NO;
        objc_setAssociatedObject(self, kOITIHiddenByUsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    OITLOGGER_LOG_RATED(sLog, 1, @"CURTAIN", @"curtain", 4,
                        @"%@@%p didMoveToWindow window=%@ shouldHide=%d hidden=%d ours=%d",
                        NSStringFromClass([self class]), self, self.window ? @"yes" : @"no", shouldHide,
                        self.hidden, objc_getAssociatedObject(self, kOITIHiddenByUsKey) != nil);
}

%end

%hook _SBGainMapView

- (void)didMoveToWindow {
    %orig;
    if (hideEnabled && self.superview) {
        OITLOGGER_LOG(sLog, 1, @"GAINMAP", @"%@@%p removed from %@",
                      NSStringFromClass([self class]), self, NSStringFromClass([self.superview class]));
        [self removeFromSuperview];
    }
}

%end

%hook _SBSystemApertureContainerViewContentView

- (void)layoutSubviews {
    UIColor *backgroundColor = [self backgroundColor];
    BOOL ours = objc_getAssociatedObject(self, kOITIColorAppliedKey) != nil;

    if (colorEnabled) {
        // Only touch the color when nothing set one, or when the color is the one we applied earlier
        // (so changing the color in prefs takes effect without a respring).
        if (!backgroundColor || ours) {
            UIColor *customColor = [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
            if (!backgroundColor || ![backgroundColor isEqual:customColor]) {
                [self setBackgroundColor:customColor];
                OITLOGGER_LOG_RATED(sLog, 1, @"COLOR", @"color.apply", 4,
                                    @"%@@%p background %@ -> %@", NSStringFromClass([self class]), self,
                                    OITIColorDesc(backgroundColor), OITIColorDesc(customColor));
            }
            objc_setAssociatedObject(self, kOITIColorAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            OITLOGGER_LOG_RATED(sLog, 2, @"COLOR", @"color.skip", 2,
                                @"%@@%p not overriding: something else set %@",
                                NSStringFromClass([self class]), self, OITIColorDesc(backgroundColor));
        }
    } else if (ours) {
        [self setBackgroundColor:nil];
        objc_setAssociatedObject(self, kOITIColorAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        OITLOGGER_LOG(sLog, 1, @"COLOR", @"%@@%p color override removed", NSStringFromClass([self class]), self);
    }
    %orig;
}

%end

%hook SBFTouchPassThroughView

- (void)layoutSubviews {
    %orig;

    if (!transEnabled && !lineDisabled) return;

    // SBFTouchPassThroughView is used pervasively throughout SpringBoard (Dock, folders, notification banners,
    // home screen icons, etc.), and the subviews.count == 4 heuristic below is NOT specific enough on its own.
    // Scoping to instances actually inside SBSystemApertureWindow avoids matching unrelated views.
    // KNOWN FRAGILE: the index-based subview picks may change between iOS versions.
    static Class apertureWindowClass;
    if (!apertureWindowClass) apertureWindowClass = NSClassFromString(@"SBSystemApertureWindow");
    if (!apertureWindowClass || !OITViewHasAncestorOfClass(self, apertureWindowClass)) return;

    NSUInteger subviewCount = self.subviews.count;
    if (subviewCount != 4) {
        // The heuristic did not match an Island-scoped instance. Log when the count changes, so a miss shows up.
        if ([sLog isLoggingAtLevel:1] &&
            [sLog noteSignature:[NSString stringWithFormat:@"miss:%lu", (unsigned long)subviewCount] forObject:self]) {
            [sLog logLevel:1 tag:@"TOUCHPASS" format:@"%@@%p inside the Island window has %lu subview(s), not 4: transparency/line hiding NOT applied",
             NSStringFromClass([self class]), self, (unsigned long)subviewCount];
        }
        return;
    }

    if (transEnabled) {
        UIView *targetSubview = self.subviews[2];
        if (targetSubview.alpha == 1.0 && targetSubview.userInteractionEnabled == 0) {
            targetSubview.alpha = alpha;
            OITLOGGER_LOG_RATED(sLog, 2, @"TOUCHPASS", @"touchpass.trans", 4,
                                @"transparency applied alpha=%.2f to %@", alpha, NSStringFromClass([targetSubview class]));
        }
    }
    if (lineDisabled) {
        UIView *lineView = self.subviews[1];
        if (lineView.alpha == 1.0 && lineView.userInteractionEnabled == 0) {
            lineView.hidden = YES;
            OITLOGGER_LOG_RATED(sLog, 2, @"TOUCHPASS", @"touchpass.line", 4,
                                @"line hidden: %@", NSStringFromClass([lineView class]));
        }
    }
}

%end

%hook SBBannerWindow

- (CGRect)frame {
    CGRect original = %orig;
    CGRect overridden;
    return OITIBannerFrame(original, &overridden) ? overridden : original;
}

- (void)setFrame:(CGRect)frame {
    CGRect overridden;
    BOOL didOverride = OITIBannerFrame(frame, &overridden);
    CGRect used = didOverride ? overridden : frame;

    if ([sLog isLoggingAtLevel:1]) {
        [sBannerWindows addObject:self];
        NSString *signature = [NSString stringWithFormat:@"in=%@ used=%@ ov=%d", NSStringFromCGRect(frame),
                               NSStringFromCGRect(used), didOverride];
        if ([sLog noteSignature:signature forObject:self]) {
            [sLog logLevel:1 tag:@"BANNER" format:@"%@@%p setFrame %@ (notificationFix=%d custom=%d profile=%d)",
             NSStringFromClass([self class]), self, signature, notificationFix, notEnabled, OITICurrentProfile() != NULL];
        }
    }
    %orig(used);
}

%end

%end

// =============================================================================================
// MARK: Preferences
// =============================================================================================

// Asks the Island windows to lay out again so new settings (scale, position) apply immediately. The layoutSubviews
// hook does the actual work. Harmless when no window has been seen yet (or in safe mode, when no hook exists).
static void OITIRefreshIslandLayout(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *window in sLiveApertureWindows.allObjects) {
            [window setNeedsLayout];
        }
    });
}

static void preferencesChanged(void) {
    if (!sOITIPreferences) {
        sOITIPreferences = [OITPreferences preferencesWithDomain:kOITIPrefsDomain];
    } else {
        [sOITIPreferences reload];
    }

    fixEnabled = [sOITIPreferences boolForKey:@"fixEnabled" default:NO];
    islandEnabled = [sOITIPreferences boolForKey:@"islandEnabled" default:NO];
    posEnabled = [sOITIPreferences boolForKey:@"posEnabled" default:NO];
    hideEnabled = [sOITIPreferences boolForKey:@"hideEnabled" default:NO];
    notificationFix = [sOITIPreferences boolForKey:@"notificationFix" default:NO];
    notEnabled = [sOITIPreferences boolForKey:@"notEnabled" default:NO];
    colorEnabled = [sOITIPreferences boolForKey:@"colorEnabled" default:NO];
    transEnabled = [sOITIPreferences boolForKey:@"transEnabled" default:NO];
    scaleEnabled = [sOITIPreferences boolForKey:@"scaleEnabled" default:NO];
    lineDisabled = [sOITIPreferences boolForKey:@"lineDisabled" default:NO];

    // Defaults match the globals above (and the prefs UI).
    xPos = [sOITIPreferences floatForKey:@"xPos" default:0.0];
    yPos = [sOITIPreferences floatForKey:@"yPos" default:20.5];
    xNot = [sOITIPreferences floatForKey:@"xNot" default:0.0];
    yNot = [sOITIPreferences floatForKey:@"yNot" default:40.0];
    red = [sOITIPreferences floatForKey:@"red" default:0.0];
    green = [sOITIPreferences floatForKey:@"green" default:0.0];
    blue = [sOITIPreferences floatForKey:@"blue" default:0.0];
    alpha = [sOITIPreferences floatForKey:@"alpha" default:1.0];
    scale = [sOITIPreferences floatForKey:@"scale" default:1.0];     // legacy single scale
    scaleX = [sOITIPreferences floatForKey:@"scaleX" default:scale];  // falls back to the legacy value
    scaleY = [sOITIPreferences floatForKey:@"scaleY" default:scale];

    // Diagnostics and safe-mode settings (no prefs UI yet; set with `defaults write`).
    sLog.enabled = [sOITIPreferences boolForKey:@"DiagnosticsEnabled" default:YES];
    sLog.level = MAX(0, MIN(2, [sOITIPreferences integerForKey:@"DiagnosticsLevel" default:0]));
    sGuardEnabled = [sOITIPreferences boolForKey:@"SafeModeGuardEnabled" default:YES];
    sGuardMaxLaunches = MAX(2, [sOITIPreferences integerForKey:@"SafeModeMaxLaunches" default:5]);
    sGuardWindowSeconds = MAX(10, [sOITIPreferences integerForKey:@"SafeModeWindowSeconds" default:120]);
    sGuardStableSeconds = MAX(5, [sOITIPreferences integerForKey:@"SafeModeStableSeconds" default:45]);
    sGuardRestoreGestalt = [sOITIPreferences boolForKey:@"SafeModeRestoreGestalt" default:NO];

    NSDictionary<NSString *, NSNumber *> *snapshot = OITIPrefSnapshot();
    if (!sLastPrefSnapshot) {
        [sLog logLevel:1 tag:@"PREF" format:@"initial: %@", OITIPrefSnapshotString(snapshot)];
    } else if ([snapshot isEqualToDictionary:sLastPrefSnapshot]) {
        [sLog logLevel:2 tag:@"PREF" format:@"reload: no change"];
    } else {
        NSMutableArray<NSString *> *changes = [NSMutableArray array];
        for (NSString *key in [snapshot.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if (![snapshot[key] isEqualToNumber:sLastPrefSnapshot[key]]) {
                [changes addObject:[NSString stringWithFormat:@"%@: %@ -> %@", key, sLastPrefSnapshot[key], snapshot[key]]];
            }
        }
        [sLog logLevel:1 tag:@"PREF" format:@"CHANGED %@", [changes componentsJoinedByString:@", "]];
    }
    sLastPrefSnapshot = snapshot;

    OITIUpdateDumpTrigger();
    OITIRefreshIslandLayout();
}

%ctor {
    // OITI.plist also loads this dylib into every UIKit app, but every class hooked below exists only in
    // SpringBoard, so there is nothing to do anywhere else.
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

    sLog = [OITLogger loggerWithName:@"oiti" path:kOITILogPath];
    sLog.ignoredImageNames = @[@"OITI.dylib", @"OITCore.dylib"];
    [sLog logSessionStartWithBuildTag:kOITIBuildTag];

    sApertureWindows = [NSHashTable weakObjectsHashTable];
    sBannerWindows = [NSHashTable weakObjectsHashTable];
    sLiveApertureWindows = [NSHashTable weakObjectsHashTable];

    preferencesChanged();

    OITObserveDarwinNotification(kOITIPrefsChangedNotification, ^{
        preferencesChanged();
    });
    OITObserveDarwinNotification(kOITIClearSafeModeNotification, ^{
        BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:kOITISafeModePath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:kOITIBootLogPath error:nil];
        [sLog logTag:@"SAFE" format:@"clear requested: safe-mode file %@. Respring to re-enable OITI's hooks.",
         removed ? @"removed" : @"was not present"];
    });

    sSafeModeActive = OITIEvaluateLoopGuard();
    if (sSafeModeActive) {
        [sLog logTag:@"SESSION" format:@"SAFE MODE: OITI hooks NOT installed. Diagnostics and dumps still work."];
    } else {
        %init(OITIHooks);
        [sLog logTag:@"SESSION" format:@"READY hooks installed (profile=%d diagnostics=%d level=%ld)",
         OITICurrentProfile() != NULL, sLog.enabled, (long)sLog.level];
    }

    OITIObserveDumpNotification();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        OITIRunStartupSelfCheck();
    });
}
