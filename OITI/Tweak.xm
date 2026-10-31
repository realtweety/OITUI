// OITI -- Dynamic Island positioning/appearance module for OITUI (fork of VisibleIsland by ethxnn88).
//
// OITI 0.2.0 notification stack (owner-tested on iPhone 8 Plus / iOS 16.7.16; still experimental). Build tag: see kOITIBuildTag.
//
// ISLAND NOTIFICATIONS (new in 0.2.0): an incoming notification banner is shown as a real Island element (app icon, title,
// message) instead of the stock banner. Custom Island notifications are off by default (`islandNotificationsEnabled = NO`)
// and fail soft: when any step is not possible the stock banner is left alone. Stack mode defaults on, but is dormant while
// the parent notification feature is off.
//   Observe:  at launch the banner post method of SBNotificationBannerDestination (postNotificationRequest*, found by name
//             pattern and hooked with the runtime only when its type encoding is v32@0:8@16@24 or v24@0:8@16; the original
//             always runs first) hands OITI every banner request. NOTIF lines log it at level 1.
//   Present:  with islandNotificationsEnabled (OITI > Notifications, default OFF) OITI builds an element: an instance of a runtime
//             subclass of SBSystemApertureProvidedContentElement (OITINotificationElement) that declares hasAlertBehavior and
//             carries leading (app icon), trailing (short headline), primary (title) and secondary (message) views, each wrapped
//             in a SBUISystemApertureCustomContentProvider held by a SBUISystemApertureContentProvider. It is registered with
//             -[SBSystemApertureController registerElement:], the registrar SpringBoard's own providers use, and Apple's code
//             hosts it like any other element. With islandNotificationStackEnabled (default ON), up to four stay registered:
//             in Expanded/Wide style the newest prefers that layout and older notices render as distinct rounded cards inside
//             its secondary content; Compact keeps all four compact. The older cards share the outer expanded Island card.
//             New notices evict the oldest; each item's timeout restarts when it is demoted to compact or promoted.
//             With stacking OFF, only one item is kept and new notices replace it. Settings warns the stack is usable but unpolished.
//   Hide:     islandNotificationsHideBanner (default OFF) fades the stock banner window out until the banner is gone. It only does
//             so after the element registered.
//   Style:    IslandNotificationsStyle (0 Compact, 1 Wide, 2 Expanded; default 2) = layout modes min / max / preferred
//             1/1/1, 1/2/2 and 1/3/3. Expanded is the tuned look; Compact and Wide are experimental.
//   Content:  no title -> the app name is the headline (or the message when there is no app name); a subtitle is folded into the
//             message ("subtitle: message"); IslandNotificationsMessageLines (1 to 4, default 2); IslandNotificationsDuration
//             (2 to 10 s, default 4); IslandNotificationsCornerExtra (points added to the corner radius while the element is up,
//             default 0, restored afterwards).
//   Touch:    a tap runs what tapping the stock banner runs (NCNotificationViewController -_executeDefaultAction: on the still-alive
//             but faded banner), so it opens the conversation or screen the notification would open; if that banner is gone it falls
//             back to the default action's URL and then to launching the app. Swipe up dismisses. Recognizers sit on Apple's
//             SAUIElementView and on the Island window (the window ones only take touches that start inside the element) and are
//             removed with the element.
//   Haptic:   NotificationHaptic (default OFF) plays one short light haptic per banner request, independent of the Island
//             notification setting. It does not fire for notifications delivered straight to the lock screen.
//   Safety:   -[SAUISystemApertureManager _reevaluatePromotedElements] is wrapped. While one of OITI's elements is live, an exception
//             there (where a malformed element crashed SpringBoard during development) is caught and logged (ELEMENT GUARD) and the
//             element is invalidated; after 5 catches element creation stays off until the next respring. With none of OITI's
//             elements live the exception is rethrown unchanged. The element's identifier is an OITIElementIdentifierStub, because
//             Apple calls -elementIdentifier and -clientIdentifier ("com.apple.springboard") on it.
//   Diagnostics: the element trace, VCFOR / VCINIT / AUTH and real-element logging live in the OITIDiagnosticHooks group, installed
//             only at DiagnosticsLevel >= 1. Developer tools (level 1): touch /tmp/OITIPoC.trigger shows a test element,
//             /tmp/OITIPoCSample.txt (title, message, bundle id, subtitle, one per line) sets its text,
//             IslandNotificationsHelloOnBoot runs it 10 s after launch, IslandNotificationsDevLayout and
//             IslandNotificationsPoCRegistrar (0 controller, 1 manager) override internals. Log tags: NOTIF (banner hook) and
//             ELEMENT (the element's life, see DIAGNOSTICS.md).
//   Every ObjC call into Apple's private classes is looked up at run time (NSClassFromString, respondsToSelector, @try) and
//   fails soft with an ELEMENT or NOTIF log line.
//
// STATUS BAR FIX: with the Island spoof on, some notch iPhones showed a red "rdar:45025538" status bar. UIKit returned no
// provider class for the spoofed device (nil) and fell back to its placeholder. Two hooks that always call %orig watch
// the provider choice (+[_UIStatusBarVisualProvider_iOS visualProviderSubclassForScreen:visualProviderInfo:]) and each
// _UIStatusBar's _prepareVisualProviderIfNeeded. The provider hook can replace UIKit's answer, governed by the Status Bar
// Layout picker on the settings page (auto by default, off, or a named class); see "Status bar provider choice". It only
// acts while the Island is on. Confirmed on an iPhone 13 mini (iOS 16.5.1) by a tester running the previous build; the
// native-provider table and nil handling added after reading his log are not yet re-tested on that phone. CHOICE is
// logged at level 0 (one line per distinct combination); the boot report and LIVE lines need level 1.
//
// Step 1 (device table, single %orig, didMoveToWindow fixes, matching defaults, clamped divisor, setFrame
// fall-through) is unchanged. Step 2 adds only logging, diagnostics and safety; no hook changes what it does:
//   1. OITLogger logging (/tmp/OITIDebug.log), see "Log tags" below.
//   2. Respring-loop guard: after repeated short-lived SpringBoard launches, OITI's hooks are not installed
//      (safe mode) until the safe-mode file is cleared. A respring requested from OITI's own settings (Respring
//      button, Clear Safe Mode) leaves OITIRespringIntent.plist and is not counted (see OVERVIEW.md).
//      The settings pages show a safe-mode banner with a Clear Safe Mode & Respring button.
//   3. Startup self-check of the MobileGestalt spoof (islandEnabled vs. the cache, and the restore breadcrumb).
//   4. On-demand dump of the Island window's view tree, view-controller tree, Apple's "aperture" classes and
//      the methods/ivars of any classes you list. This is the data the Step 3 research needs.
//   5. OITI now only does anything in SpringBoard. Its plist filter also loads it into every UIKit app; the
//      hooked classes only exist in SpringBoard, so apps used to run the constructor for nothing.
//   6. STATUSBAR report (level 1): screen geometry, every provider class on the device, any
//      UIStatusBarVisualProviderClassName override and the Status Bar Layout setting. Written 4 s after launch and with
//      every dump.
//   7. STATUSBAR CHOICE (level 0) and LIVE (level 1) lines: the provider class UIKit chose for the screen, what OITI
//      returned, and the class each live status bar ended up with. Status Bar Layout (key StatusBarLayout) decides
//      whether the choice is replaced.
//
// DOWNLOAD PROGRESS (stage 2: the test download and App Store downloads): key DownloadProgressEnabled (default off, Settings
// > OITI > Download Progress). While a download is tracked, one of two looks (setting DownloadProgressStyle) shows a progress
// bar with the percentage, and for sources that know sizes also the downloaded size, the total size and the speed. MINIMAL
// (default) is not an Apple element at all: it is a black pill in a window of its own (OITIDownloadPill), placed over the
// Island (its rectangle is found in the Island's window, with a computed fallback) with the Island's height kept empty at its
// top; its width, bottom padding and vertical nudge are settings. DETAILED is an ordinary OITI Island element (reason
// "download-progress", expanded layout), so the breadcrumb, the recovery window, the stack and swipe-to-dismiss apply to it;
// it needs preferredAlertingDuration: to answer 24 h for it and has drop detection (see OITIDownloadsRefresh). Either look
// ends when the downloads finish (a short "complete" state), when a limit is reached (DownloadIdleAfterMB downloaded or
// DownloadIdleAfterSeconds on screen, 0 = never; the size limit only applies to byte-based downloads), or when it is swiped
// away. After a limit or a dismissal it stays away until the next download starts; the download itself carries on.
// The tracker takes two kinds of input and aggregates several downloads: bytes (OITIDownloadUpdate: sizes, speed and a size
// limit) and a fraction (OITIDownloadUpdateFraction: percentage and an estimate of the time left from how fast the fraction
// moves; no sizes, no speed). Sources: the test download started and stopped from the settings page (Darwin notifications
// com.wilburt.oiti/TestDownloadStart and TestDownloadStop, size DownloadTestSizeMB; bytes, or a whole-percent fraction with
// DownloadTestFractionOnly set by defaults write) and the App Store source (key DownloadAppStoreEnabled, default off; see
// "App Store source" below). Apple Mode forces everything off. Browsers (Safari, Chrome, Arc) are stage 3, a separate
// project. The INSTALL dump (Diagnostics/OITIInstallDump.xm) is the read-only tool the App Store source was designed from.
//
// ELEMENT CRASH RECOVERY: while any of OITI's Island elements (a notice or the startup Hello) is live, the
// file OITILiveElement.plist exists; it is written just before the element is registered and deleted when the last one
// leaves. A file found at launch means the previous SpringBoard ended while an OITI element was live (a crash, or a
// respring from somewhere other than OITI's own settings). That launch then keeps Island notifications and the
// startup animation off for 120 s (the stock banner is used), which is when a re-delivered notification would
// otherwise rebuild the element that crashed. The rest of OITI keeps working. This ends such a loop after one crash
// instead of the five that trip safe mode, and complements the in-process promotion guard.
//
// APPLE MODE: key appleMode (OITI main page). While on, every Island customization behaves as if it were
// off and the Island is the stock iOS one: custom position, custom scale, Island size, color, opacity, outline hiding,
// hide when not in use, custom notification position, Island Notifications (and hiding the banner for them) and the
// startup animation. Kept as the user set them: Enable Dynamic Island, Fix Island Position, Fix Notification
// Positioning, the Status Bar Layout fix, safe mode and diagnostics. The stored settings are never changed, so
// turning Apple Mode off brings every customization back as it was. Applied in one place (preferencesChanged).
//
// X/Y SCALE: separate width and height scales applied as one non-uniform transform on the Island window.
// Contents stretch with it. They are RELATIVE to Apple's own size: 1.0 is the stock Island. Apple's window is a canvas
// stretched to the screen width by its own uniform transform (1.15 on an iPhone 8 Plus), and setting a transform
// replaces that one, so the applied transform is Apple's canvas scale times the slider value. Prefs keys
// RelativeScaleX and RelativeScaleY (clamped like the old ones). The earlier absolute keys scale, scaleX and scaleY
// are no longer read and are not migrated. Changing any setting asks the Island window to lay out again, so changes
// show up immediately instead of at the next layout Apple happens to do.
//
// ISLAND SIZE (confirmed by a dump experiment and on the device): Apple builds the Island from
// SBUISystemApertureLayoutMetrics. Its sensorRegionSize getter is the root input: _inertSize, minimumCompactSize, the
// compact padding areas and the minimum corner radius are all derived from it (a hook on _inertSize alone changed
// derived numbers but no pill sizes, so only sensorRegionSize is hooked). Scaling what it returns makes the Island
// itself smaller or larger while icons, artwork and text keep their normal size, which the window transform cannot do.
// 1.0 = Apple's own size. Set on the OITI > Scale page (Island Size sliders) or with -float defaults. Changes apply
// live: Apple reads the getter again on its next layout, and OITIRefreshIslandLayout asks the Island windows to lay
// out whenever a setting changes (confirmed on-device, no respring needed). Prefs keys (domain com.wilburt.oiti.prefs), each clamped to 0.3 - 2.0:
//   MetricsSensorWidthScale     MetricsSensorHeightScale
//
// Log file:      /tmp/OITIDebug.log   (rotates at 6 MB to /tmp/OITIDebug.log.1)
// Dump trigger:  touch /tmp/OITIDump.trigger        (polled once a second; detected by modification time)
//                or Darwin notification com.wilburt.oiti/Dump
// Class query:   put class names, one per line, in /tmp/OITIClassQuery.txt before triggering a dump
// Install dump:  touch /tmp/OITIInstallDump.trigger  (or Darwin notification com.wilburt.oiti/InstallDump). Read-only look at
//                what SpringBoard exposes about an install in progress (INSTALL tag, needs DiagnosticsLevel >= 1; see the
//                Diagnostics/OITIInstallDump.xm and DIAGNOSTICS.md). Ran on the device, build OITI-exp-2026-10-24-c (build -a crashed SpringBoard, -b and -c ran fine).
// Clear safe mode: the banner on any OITI settings page, or rm /var/mobile/Library/Preferences/OITISafeMode.plist
//                (or notification com.wilburt.oiti/ClearSafeMode), then respring
// Prefs keys (domain com.wilburt.oiti.prefs, set with `defaults write`, no UI yet):
//   DiagnosticsEnabled (bool, default YES)      DiagnosticsLevel (0-2, default 0)
//   SafeModeGuardEnabled (bool, default YES)    SafeModeMaxLaunches (int, default 5)
//   SafeModeWindowSeconds (int, default 120)    SafeModeStableSeconds (int, default 45)
//   SafeModeRestoreGestalt (bool, default NO)   -- on a trip, also run the OITIRestoreGestalt helper
//   InstallDumpSamples (int 0-30, default 6)    InstallDumpIntervalSeconds (1-10, default 2)   -- the install dump's samples
//   InstallDumpCallGetters (bool, default NO)   -- install dump: also call declared property getters of private objects
//
// Log tags: SESSION PREF GUARD SAFE CHECK STATUSBAR ISLAND LAYOUT CURTAIN GAINMAP COLOR TOUCHPASS BANNER APERTURE DUMP CLASSQ NOTIF ELEMENT DOWNLOAD INSTALL
// Levels:   0 = unconditional lines only, 1 = events and state changes, 2 = adds rate-limited per-call lines.
// Default is 0, so a normal install writes only the SESSION, GUARD, SAFE and CHECK lines (about a dozen per boot,
// including every warning, plus one STATUSBAR CHOICE line per distinct provider choice), runs no polling timer and tracks no windows for dumps. For development raise it:
//   defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1     (then sbreload)

// SOURCE LAYOUT (v0.3.0 module split, in progress; plan and order in OVERVIEW.md, "The Great Split"):
//   Diagnostics/   the dumps and their triggers (done, round 1). Read-only, gated behind DiagnosticsLevel.
//   Shared/        OITIApplePrivate.h (Apple's private class declarations) and OITIShared.h (state and helpers that more
//                  than one file uses). The definitions of that shared state still live below until the Shared round.
//   DownloadProgress/  the download tracker, the Minimal pill, the progress views and the App Store source (done, round 2).
//   IslandSize/        the Island's position, size, scale and appearance hooks (done, round 3).
//   IslandNotifications/  Island notifications: the presenter, element, views, banner hide, actions and hooks (done, round 4).
//   Everything else is still in this file and moves one module per round. Imports are relative to the OITI folder.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import <string.h>
#import <spawn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <unistd.h>
#import <OITCore/OITCore.h>
#import "OITIDeviceProfiles.h"
#import "Shared/OITIShared.h"
#import "Diagnostics/OITIDiagnostics.h"
#import "DownloadProgress/OITIDownloadProgress.h"
#import "IslandSize/OITIIslandSize.h"
#import "IslandNotifications/OITIIslandNotifications.h"

extern char **environ;

extern NSString * const kOITIBuildTag = @"OITI-exp-2026-10-26-a";
static NSString * const kOITIPrefsDomain = @"com.wilburt.oiti.prefs";
static NSString * const kOITIPrefsChangedNotification = @"com.wilburt.oiti/PrefsChanged";
static NSString * const kOITIClearSafeModeNotification = @"com.wilburt.oiti/ClearSafeMode";
static NSString * const kOITITestDownloadStartNotification = @"com.wilburt.oiti/TestDownloadStart";
static NSString * const kOITITestDownloadStopNotification = @"com.wilburt.oiti/TestDownloadStop";

static NSString * const kOITILogPath = @"/tmp/OITIDebug.log";
static NSString * const kOITIStartupHelloLastPlayedKey = @"IslandStartupHelloLastPlayedAt";
static NSString * const kOITIStartupHelloVideoPath = @"/var/jb/Library/Application Support/OITI/StartupHello.mp4";
static const NSTimeInterval kOITIStartupHelloCooldown = 300.0;
const NSTimeInterval kOITIStartupHelloPrototypeDuration = 8.0;

static NSString * const kOITIBootLogPath = @"/var/mobile/Library/Preferences/OITIBootLog.plist";
static NSString * const kOITISafeModePath = @"/var/mobile/Library/Preferences/OITISafeMode.plist";
// Written by OITI's settings pages just before they ask for a respring (Respring button, Clear Safe Mode). The loop
// guard consumes it: a respring the user asked for is not a crash, so that launch is not counted. Older than
// kOITIRespringIntentMaxAge seconds it is ignored.
static NSString * const kOITIRespringIntentPath = @"/var/mobile/Library/Preferences/OITIRespringIntent.plist";
static const NSTimeInterval kOITIRespringIntentMaxAge = 30.0;
// Exists while one of OITI's Island elements is live (see ELEMENT CRASH RECOVERY above).
NSString * const kOITILiveElementPath = @"/var/mobile/Library/Preferences/OITILiveElement.plist";
const NSTimeInterval kOITIElementRecoveryWindow = 120.0;
CFAbsoluteTime sElementRecoveryUntil = 0;     // while in the future, no Island element is created
BOOL sLaunchWasRequestedRespring = NO;        // this launch followed a respring asked for in OITI's settings
static NSString * const kOITIGestaltBackupBreadcrumbPath = @"/var/mobile/Library/Preferences/OITIGestaltBackup.plist";
static NSString * const kOITIGestaltPlistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static NSString * const kOITIGestaltCacheExtraKey = @"CacheExtra";
static NSString * const kOITIGestaltNestedKey = @"oPeik/9e8lQWMszEjbPzng";
static NSString * const kOITIGestaltLeafKey = @"ArtworkDeviceSubType";
static const char * const kOITIRestoreHelperPath = "/var/jb/usr/libexec/OITIRestoreGestalt";


CGFloat red = 0.0;
CGFloat green = 0.0;
CGFloat blue = 0.0;
CGFloat alpha = 1.0;

CGFloat scaleX = 1.0;   // RelativeScaleX: 1.0 = Apple's own size
CGFloat scaleY = 1.0;   // RelativeScaleY

// Island size multipliers applied to sensorRegionSize from SBUISystemApertureLayoutMetrics.
// 1.0 = Apple's own value (no change). See the header comment.
CGFloat sMetricsSensorX = 1.0;
CGFloat sMetricsSensorY = 1.0;
// The last value Apple's own getter returned before our multiplier, kept for the dump (zero = not called yet).
CGSize sRawSensorRegionSize;

CGFloat xPos = 0;
CGFloat yPos = 20.5;
CGFloat xNot = 0.0;
CGFloat yNot = 40;

BOOL fixEnabled;
BOOL islandEnabled;
BOOL posEnabled;
BOOL hideEnabled;
BOOL notificationFix;
BOOL notEnabled;
BOOL colorEnabled;
BOOL transEnabled;
BOOL scaleEnabled;
BOOL lineDisabled;
BOOL islandNotificationsEnabled;       // OITI > Notifications: show notifications as an Island element (default NO)
BOOL islandNotificationsHideBanner;    // also fade the stock banner window out while our element is up (default NO)
BOOL sIslandNotificationStackEnabled = YES; // Experimental multi-notification stack (default YES for existing behavior)
BOOL sAppleMode;                        // appleMode: every customization below is forced off while YES
BOOL islandStartupHelloEnabled;        // OITI > Startup Animation prototype (default NO)
BOOL sStartupHelloObservationWindowOpen;
BOOL sStartupHelloActivitySeen;
static BOOL sStartupHelloReadinessLogged;
static int sStartupHelloPolls;   // once-a-second readiness checks so far; the check gives up after 180 (3 minutes)
CGFloat sIslandNoticeDuration = 4.0;   // seconds, key IslandNotificationsDuration, clamped 1 - 15

// Diagnostics and safe-mode settings (prefs keys listed in the header comment).
static BOOL sGuardEnabled = YES;
static NSInteger sGuardMaxLaunches = 5;
static NSInteger sGuardWindowSeconds = 120;
static NSInteger sGuardStableSeconds = 45;
static BOOL sGuardRestoreGestalt = NO;


// Shared state: declared in Shared/OITIShared.h. The definitions stay here until the Shared round moves them.
OITLogger *sLog;
// Weak references: the research hooks observe Apple's manager but must not keep it alive.
NSHashTable *sObservedApertureManagers;
OITPreferences *sOITIPreferences;
static NSDictionary<NSString *, NSNumber *> *sLastPrefSnapshot;
BOOL sSafeModeActive = NO;

// Weak references to the live instances our hooks have seen; used only by the dump.
NSHashTable<UIView *> *sApertureWindows;
NSHashTable<UIView *> *sLiveApertureWindows;   // always maintained: used to re-layout after a setting changes
NSHashTable<UIView *> *sBannerWindows;


NSString *OITIObjectSummary(id object) {
    if (!object) return @"nil";
    if ([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]]) {
        NSString *value = [object description];
        return value.length > 120 ? [[value substringToIndex:120] stringByAppendingString:@"…"] : value;
    }
    return [NSString stringWithFormat:@"%@@%p", NSStringFromClass([object class]), (__bridge void *)object];
}


static void OITIRunStartupHello(void);


// Resolved once. NULL means "this device has no built-in offsets" (for example an iPhone 8 / 8 Plus).
const OITIDeviceProfile *OITICurrentProfile(void) {
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

NSDictionary<NSString *, NSNumber *> *OITIPrefSnapshot(void) {
    return @{
        @"fixEnabled": @(fixEnabled), @"islandEnabled": @(islandEnabled), @"posEnabled": @(posEnabled),
        @"hideEnabled": @(hideEnabled), @"notificationFix": @(notificationFix), @"notEnabled": @(notEnabled),
        @"colorEnabled": @(colorEnabled), @"transEnabled": @(transEnabled), @"scaleEnabled": @(scaleEnabled), @"appleMode": @(sAppleMode), @"downloadProgress": @(sDownloadProgressEnabled), @"downloadAppStore": @(sDownloadAppStoreEnabled),
        @"downloadStyle": @(sDownloadStyle), @"pillW": @(sDownloadPillWidth), @"pillBottom": @(sDownloadPillBottomPadding), @"pillNudge": @(sDownloadPillNudgeY), @"downloadIdleMB": @(sDownloadIdleAfterMB), @"downloadIdleSeconds": @(sDownloadIdleAfterSeconds),
        @"lineDisabled": @(lineDisabled),
        @"xPos": @(xPos), @"yPos": @(yPos), @"xNot": @(xNot), @"yNot": @(yNot),
        @"red": @(red), @"green": @(green), @"blue": @(blue), @"alpha": @(alpha), @"scaleX": @(scaleX), @"scaleY": @(scaleY),
        @"MetricsSensorW": @(sMetricsSensorX), @"MetricsSensorH": @(sMetricsSensorY),
        @"islandNotificationsEnabled": @(islandNotificationsEnabled),
        @"islandNotificationsHideBanner": @(islandNotificationsHideBanner),
        @"islandNotificationStackEnabled": @(sIslandNotificationStackEnabled),
        @"IslandStartupHelloEnabled": @(islandStartupHelloEnabled),
        @"IslandNotificationsDuration": @(sIslandNoticeDuration),
        @"IslandNotificationsStyle": @([sOITIPreferences floatForKey:@"IslandNotificationsStyle" default:2]),
        @"NotificationHaptic": @([sOITIPreferences boolForKey:@"NotificationHaptic" default:NO]),
        @"IslandNotificationsMessageLines": @([sOITIPreferences floatForKey:@"IslandNotificationsMessageLines" default:2]),
    };
}

NSString *OITIPrefSnapshotString(NSDictionary<NSString *, NSNumber *> *snapshot) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in [snapshot.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, snapshot[key]]];
    }
    return [parts componentsJoinedByString:@" "];
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

    // A respring requested from OITI's settings pages is not a crash. The marker is consumed either way (a stale
    // one is deleted and ignored), and a fresh one means the previous SpringBoard was healthy enough to be asked
    // to restart, so the launch history is forgotten instead of grown.
    NSDictionary *intent = [NSDictionary dictionaryWithContentsOfFile:kOITIRespringIntentPath];
    if (intent) {
        [[NSFileManager defaultManager] removeItemAtPath:kOITIRespringIntentPath error:nil];
        id intentTime = intent[@"time"];
        NSTimeInterval intentAge = [intentTime isKindOfClass:[NSNumber class]] ? now - [intentTime doubleValue] : -1;
        if (intentAge >= 0 && intentAge < kOITIRespringIntentMaxAge) {
            [@{ @"launches": @[] } writeToFile:kOITIBootLogPath atomically:YES];
            sLaunchWasRequestedRespring = YES;
            [sLog logTag:@"GUARD" format:@"respring requested from OITI settings %.0f s ago: launch not counted, history cleared",
             intentAge];
            return NO;
        }
        [sLog logTag:@"GUARD" format:@"ignored a stale respring marker (age %.0f s)", intentAge];
    }

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
// MARK: Status bar provider choice: log, and an opt-in fix
// =============================================================================================

// With the Island spoof on, some notch iPhones get UIKit's placeholder provider (_UIStatusBarVisualProvider_Fallback,
// the red "rdar:45025538" bar). UIKit picks the provider in +visualProviderSubclassForScreen:visualProviderInfo:.
// This hook always calls %orig and logs the answer. What it does with it depends on the Status Bar Layout setting
// (key StatusBarLayout in com.wilburt.oiti.prefs, a picker on the OITI settings page, default "auto"):
//   "off"   never changes UIKit's answer.
//   "auto"  while the Island is on and the device is a notch iPhone in the table, return its native Split provider
//           when UIKit chose nothing (nil, what a 13 mini returns under the spoof) or Fallback, or (for the 828 and 1080
//           pixel screens, the widths reported to show the red bar) when UIKit chose anything else. Other devices, and any device UIKit already
//           handles, are left alone.
//   <class> a _UIStatusBarVisualProvider_* class name: return that class while the Island is on (for trying layouts).
// A wrong class can crash SpringBoard, which the respring-loop guard turns into safe mode (hooks off) after 5 launches.
// The provider is chosen when a status bar is built, so a changed setting needs a respring.
//
// The native provider "auto" returns comes from, in order: the record this phone wrote about itself (below), the
// table of models read from real logs, and a guess by native pixel width. The record is written the first time a
// launch with the Island off builds a status bar (unproven on a notch iPhone: the 8 Plus runs it inert).

@interface _UIStatusBarVisualProvider_iOS : NSObject
@end

@interface _UIStatusBar : UIView
- (Class)_visualProviderClass;
- (NSString *)_visualProviderClassName;
- (id)visualProviderInfo;
- (id)targetScreen;
@end

static NSString * const kOITIProviderPrefix = @"_UIStatusBarVisualProvider_";
static NSString * const kOITIFallbackProviderName = @"_UIStatusBarVisualProvider_Fallback";
static NSString * const kOITIStatusBarLayoutKey = @"StatusBarLayout";
static NSString * const kOITIStatusBarLayoutAuto = @"auto";
static NSString * const kOITIStatusBarLayoutOff = @"off";
static NSMutableSet<NSString *> *sLoggedProviderChoices;
static NSHashTable *sLoggedStatusBars;
static NSUInteger sLiveStatusBarLogCount = 0;

// The provider UIKit chose natively on this phone (Island off), written by OITIMaybeLearnNativeProvider and read back
// by "auto". Flat plist next to the other OITI state files. Not removed on uninstall.
static NSString * const kOITINativeProviderPath = @"/var/mobile/Library/Preferences/OITINativeProvider.plist";
static BOOL sIslandEnabledAtLaunch = NO;          // set in %ctor from the first preferences load
static BOOL sNativeProviderLearnAttempted = NO;   // one attempt per launch
static BOOL sLearnedNativeProviderLoaded = NO;
static NSString *sLearnedNativeProvider = nil;

static NSInteger OITINativePixelWidth(UIScreen *screen) {
    CGSize pixels = screen.nativeBounds.size;
    return (NSInteger)llround(MIN(pixels.width, pixels.height));
}

// The record this phone wrote about itself, or nil. Read once per launch and kept. It is only trusted for the same
// machine identifier (a restored backup from another phone is ignored) and only if it names a real provider class
// name (never Fallback).
NSString *OITILearnedNativeProviderName(void) {
    @synchronized (kOITINativeProviderPath) {
        if (!sLearnedNativeProviderLoaded) {
            sLearnedNativeProviderLoaded = YES;
            NSDictionary *record = [NSDictionary dictionaryWithContentsOfFile:kOITINativeProviderPath];
            id name = record[@"provider"];
            id machine = record[@"machine"];
            if ([name isKindOfClass:[NSString class]] && [machine isKindOfClass:[NSString class]] &&
                [machine isEqualToString:[OITDeviceInfo machineIdentifier]] &&
                [name hasPrefix:kOITIProviderPrefix] && ![name isEqualToString:kOITIFallbackProviderName]) {
                sLearnedNativeProvider = name;
            }
        }
        return sLearnedNativeProvider;
    }
}

// The provider UIKit uses natively (Island off) for a device. Order: the record this phone wrote (learned), then a
// model read from that device's own log ("CHOICE UIKit chose ..." with islandEnabled=0; table), then a guess by
// native pixel width using the names in the STATUSBAR PROVIDER dump (width guess, an estimate until someone reports a
// log). *source says which one answered, nil when none did.
NSString *OITINativeProviderNameForScreen(UIScreen *screen, NSString **source) {
    NSString *name = nil;
    NSString *from = nil;
    NSString *learned = OITILearnedNativeProviderName();
    if (learned) {
        name = learned;
        from = @"learned record";
    } else if ([[OITDeviceInfo machineIdentifier] isEqualToString:@"iPhone14,4"]) {
        name = @"_UIStatusBarVisualProvider_Split1080_Wide";   // iPhone 13 mini
        from = @"table";
    } else {
        switch (OITINativePixelWidth(screen)) {
            case 828:  name = @"_UIStatusBarVisualProvider_Split828"; break;
            case 1080: name = @"_UIStatusBarVisualProvider_Split1080"; break;
            case 1125: name = @"_UIStatusBarVisualProvider_Split1125"; break;
            case 1170: name = @"_UIStatusBarVisualProvider_Split1170"; break;
            case 1242: name = @"_UIStatusBarVisualProvider_Split1242"; break;
            case 1284: name = @"_UIStatusBarVisualProvider_Split1284"; break;
            default: break;
        }
        if (name) from = @"width guess";
    }
    if (source) *source = from;
    return name;
}

// Only classes named _UIStatusBarVisualProvider_* are accepted, so a typo cannot return an unrelated class.
static Class OITIProviderClassNamed(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || ![name hasPrefix:kOITIProviderPrefix]) return Nil;
    return NSClassFromString(name);
}

static NSString *OITIStatusBarLayoutSetting(void) {
    NSString *layout = [sOITIPreferences stringForKey:kOITIStatusBarLayoutKey default:kOITIStatusBarLayoutAuto];
    return layout.length ? layout : kOITIStatusBarLayoutAuto;
}

// Writes the provider UIKit chose natively on this phone, so "auto" does not depend on a table built from other
// people's logs. It only runs when UIKit's answer is certainly native: the Island was off when SpringBoard started
// (the MobileGestalt value is read once per process, so a phone that started with the spoof stays spoofed until the
// next respring) and is still off, the phone is a notch iPhone in the table, and UIKit chose a real provider (not
// nil, not Fallback). The file checks run off the main thread: the cache must not hold the spoofed value and no
// UIStatusBarVisualProviderClassName override may be set, since either would make UIKit's answer not native.
// One attempt per launch, and nothing is rewritten when the record already says the same.
static void OITIMaybeLearnNativeProvider(Class chosen, UIScreen *screen) {
    if (sNativeProviderLearnAttempted) return;
    if (islandEnabled || sIslandEnabledAtLaunch) return;
    if (screen != [UIScreen mainScreen]) return;
    sNativeProviderLearnAttempted = YES;
    if (!OITICurrentProfile()) {
        [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: %@ is not in the device table, so there is no status bar fix to feed and nothing is recorded",
         [OITDeviceInfo machineIdentifier]];
        return;
    }

    NSString *name = chosen ? NSStringFromClass(chosen) : nil;
    NSString *machine = [OITDeviceInfo machineIdentifier];
    NSString *bounds = NSStringFromCGRect(screen.nativeBounds);
    if (!name || ![name hasPrefix:kOITIProviderPrefix] || [name isEqualToString:kOITIFallbackProviderName]) {
        [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: UIKit chose %@ with the Island off, which is not a usable native provider", name ?: @"nil"];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @try {
            id overrideValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("UIStatusBarVisualProviderClassName"),
                                                                      CFSTR("com.apple.UIKit")));
            if (overrideValue) {
                [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: UIStatusBarVisualProviderClassName override is set (%@), so UIKit's answer may not be native", overrideValue];
                return;
            }
            NSDictionary *cache = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
            if (!cache) {
                [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: the MobileGestalt cache is not readable, cannot confirm the spoof is absent"];
                return;
            }
            id extra = cache[kOITIGestaltCacheExtraKey];
            id nested = [extra isKindOfClass:[NSDictionary class]] ? extra[kOITIGestaltNestedKey] : nil;
            id subtype = [nested isKindOfClass:[NSDictionary class]] ? nested[kOITIGestaltLeafKey] : nil;
            if ([subtype isKindOfClass:[NSNumber class]] && [subtype integerValue] == 2556 && !OITIMachineHasNativeIsland(machine)) {
                [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: the cache holds the spoofed ArtworkDeviceSubType 2556, so UIKit's answer is not native"];
                return;
            }

            NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kOITINativeProviderPath];
            if ([existing[@"machine"] isEqual:machine] && [existing[@"provider"] isEqual:name]) {
                [sLog logTag:@"STATUSBAR" format:@"LEARN record already holds %@ for %@", name, machine];
                return;
            }
            NSDictionary *record = @{
                @"machine": machine ?: @"",
                @"provider": name,
                @"nativeBounds": bounds ?: @"",
                @"os": [NSProcessInfo processInfo].operatingSystemVersionString ?: @"",
                @"build": kOITIBuildTag,
                @"time": @([[NSDate date] timeIntervalSince1970]),
            };
            BOOL written = [record writeToFile:kOITINativeProviderPath atomically:YES];
            [sLog logTag:@"STATUSBAR" format:@"LEARN %@: native provider for %@ is %@ (nativeBounds=%@, previous record=%@)",
             written ? @"recorded" : @"WRITE FAILED", machine, name, bounds, existing[@"provider"] ?: @"(none)"];
            if (written) {
                @synchronized (kOITINativeProviderPath) {
                    sLearnedNativeProvider = name;
                    sLearnedNativeProviderLoaded = YES;
                }
            }
        } @catch (NSException *exception) {
            [sLog logTag:@"STATUSBAR" format:@"LEARN ERROR exception %@: %@", exception.name, exception.reason];
        }
    });
}

static Class OITIStatusBarProviderDecision(Class chosen, id screenArgument, id info) {
    Class result = chosen;
    @try {
        UIScreen *screen = [screenArgument isKindOfClass:[UIScreen class]] ? (UIScreen *)screenArgument : [UIScreen mainScreen];
        OITIMaybeLearnNativeProvider(chosen, screen);
        NSString *layout = OITIStatusBarLayoutSetting();
        NSString *chosenName = chosen ? NSStringFromClass(chosen) : @"nil";
        NSInteger width = OITINativePixelWidth(screen);
        Class replacement = Nil;
        NSString *decision = nil;
        NSString *nativeSource = nil;

        if (!islandEnabled) {
            decision = @"idle: Island is off";
        } else if ([layout isEqualToString:kOITIStatusBarLayoutOff]) {
            decision = @"idle: Status Bar Layout is Off";
        } else if ([layout isEqualToString:kOITIStatusBarLayoutAuto]) {
            NSString *nativeName = OITICurrentProfile() ? OITINativeProviderNameForScreen(screen, &nativeSource) : nil;
            Class native = nativeName ? OITIProviderClassNamed(nativeName) : Nil;
            if (!native) {
                decision = @"auto idle: no native provider known for this device";
            } else if (chosen == native) {
                decision = @"auto idle: UIKit already chose the native provider";
            } else if (!chosen || [chosenName isEqualToString:kOITIFallbackProviderName]) {
                replacement = native;
                decision = @"auto replaced UIKit's empty or Fallback choice with the native provider";
            } else if (width == 828 || width == 1080) {
                replacement = native;
                decision = @"auto replaced UIKit's choice on a width reported to show the red bar";
            } else {
                decision = @"auto idle: UIKit chose a real provider";
            }
        } else {
            Class forced = OITIProviderClassNamed(layout);
            if (forced) {
                replacement = forced;
                decision = @"forced the selected layout";
            } else {
                decision = @"selected layout is not a loaded _UIStatusBarVisualProvider_* class, ignored";
            }
        }

        if (nativeSource) decision = [decision stringByAppendingFormat:@" [native provider from %@]", nativeSource];
        if (replacement) result = replacement;

        NSString *replacementName = replacement ? NSStringFromClass(replacement) : @"-";
        NSString *signature = [NSString stringWithFormat:@"%@|%@|%d|%@|%@", chosenName, replacementName,
                               islandEnabled, layout, NSStringFromCGRect(screen.nativeBounds)];
        BOOL firstTime = NO;
        if (sLoggedProviderChoices) {
            @synchronized (sLoggedProviderChoices) {
                if (sLoggedProviderChoices.count < 16 && ![sLoggedProviderChoices containsObject:signature]) {
                    [sLoggedProviderChoices addObject:signature];
                    firstTime = YES;
                }
            }
        }
        if (firstTime) {
            NSString *infoText = info ? [[info description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] : @"nil";
            if (infoText.length > 300) infoText = [infoText substringToIndex:300];
            [sLog logTag:@"STATUSBAR" format:@"CHOICE UIKit chose %@ | screen nativeBounds=%@ scale=%.2f | islandEnabled=%d layout=%@ | %@ -> returning %@ | info=%@",
             chosenName, NSStringFromCGRect(screen.nativeBounds), (double)screen.scale, islandEnabled, layout,
             decision, result ? NSStringFromClass(result) : @"nil", infoText];
        }
    } @catch (NSException *exception) {
        [sLog logTag:@"STATUSBAR" format:@"CHOICE ERROR exception %@: %@ (returning UIKit's own answer)",
         exception.name, exception.reason];
        result = chosen;
    }
    return result;
}

// One line per live _UIStatusBar (the persistent one, the app switcher's and the cover sheet's): the provider class it
// actually ended up with, which can differ from the CHOICE line if something else sets the class name.
static void OITILogLiveStatusBar(_UIStatusBar *bar) {
    if (!sLog.enabled || sLog.level < 1 || !sLoggedStatusBars) return;
    @try {
        @synchronized (sLoggedStatusBars) {
            if (sLiveStatusBarLogCount >= 24 || [sLoggedStatusBars containsObject:bar]) return;
            [sLoggedStatusBars addObject:bar];
            sLiveStatusBarLogCount++;
        }
        Class providerClass = [bar _visualProviderClass];
        NSString *className = [bar respondsToSelector:@selector(_visualProviderClassName)] ? [bar _visualProviderClassName] : nil;
        id target = [bar targetScreen];
        [sLog logTag:@"STATUSBAR" format:@"LIVE %p provider=%@ className=%@ target=%@ window=%@ alpha=%.2f hidden=%d",
         (__bridge void *)bar, providerClass ? NSStringFromClass(providerClass) : @"nil", className ?: @"(none)",
         [target isKindOfClass:[UIScreen class]] ? NSStringFromCGRect([(UIScreen *)target bounds]) : @"nil",
         bar.window ? NSStringFromClass([bar.window class]) : @"nil", (double)bar.alpha, bar.hidden];
    } @catch (NSException *exception) {
        [sLog logTag:@"STATUSBAR" format:@"LIVE ERROR exception %@: %@", exception.name, exception.reason];
    }
}

// =============================================================================================
// MARK: Hello startup animation (the Island notifications are in IslandNotifications/)
// =============================================================================================


NSMutableDictionary *sStartupHelloItem;


void OITICancelStartupHello(NSString *reason) {
    NSDictionary *item = sStartupHelloItem;
    if (!item) return;
    [sLog logLevel:1 tag:@"HELLO" format:@"yielding startup card to Island activity (%@)", reason];
    OITIRemoveNoticeItem(item, reason ?: @"interrupted");
}


@implementation OITIStartupVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }

- (instancetype)initWithURL:(NSURL *)url {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    _player = [AVPlayer playerWithPlayerItem:item];
    _player.muted = YES;
    AVPlayerLayer *playerLayer = (AVPlayerLayer *)self.layer;
    playerLayer.player = _player;
    // Keep the familiar 16:9 Island content frame; the video is pre-cropped with safe margins
    // so aspect-fill enlarges the word without cutting off either end.
    playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.backgroundColor = UIColor.blackColor;
    self.layer.cornerRadius = 24.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.isAccessibilityElement = NO;
    return self;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(260.0, 146.0); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(260.0, 146.0); }
- (NSTimeInterval)mediaDuration {
    NSTimeInterval duration = CMTimeGetSeconds(self.player.currentItem.duration);
    return isfinite(duration) && duration > 0 ? duration : 0;
}
- (void)startPlayback { [self.player seekToTime:kCMTimeZero]; [self.player play]; }
- (void)stopPlayback {
    [self.player pause];
    [self.player replaceCurrentItemWithPlayerItem:nil];
}
@end

OITIStartupVideoView *OITIBuildStartupVideoView(void) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:kOITIStartupHelloVideoPath]) {
        [sLog logLevel:1 tag:@"HELLO" format:@"video asset missing at %@; retaining the placeholder card", kOITIStartupHelloVideoPath];
        return nil;
    }
    NSURL *url = [NSURL fileURLWithPath:kOITIStartupHelloVideoPath];
    OITIStartupVideoView *view = [[OITIStartupVideoView alloc] initWithURL:url];
    if (view) [sLog logLevel:1 tag:@"HELLO" format:@"created muted, single-play video view duration=%.2fs", (double)view.mediaDuration];
    return view;
}


static BOOL OITIStartupHelloIsAtUnlockedHomeScreen(BOOL *stateAvailable) {
    if (stateAvailable) *stateAvailable = NO;
    Class lockClass = NSClassFromString(@"SBLockScreenManager");
    id lockManager = OITISafeObject(lockClass, @"sharedInstance");
    BOOL lockStateAvailable = NO;
    BOOL locked = OITISafeBool(lockManager, @"isUILocked", &lockStateAvailable);

    Class workspaceClass = NSClassFromString(@"SBMainWorkspace");
    id workspace = OITISafeObject(workspaceClass, @"sharedInstance");
    BOOL homeStateAvailable = NO;
    BOOL springBoardFrontmost = OITISafeBool(workspace, @"isSpringBoardActive", &homeStateAvailable);

    BOOL unlocked = lockStateAvailable && !locked && UIApplication.sharedApplication.protectedDataAvailable;
    BOOL atHome = homeStateAvailable && springBoardFrontmost;
    if (stateAvailable) *stateAvailable = lockStateAvailable && homeStateAvailable;
    return unlocked && atHome;
}

static BOOL OITIStartupHelloHasActiveSystemElement(void) {
    id manager = sRegisteringManager ?: sSeenManager;
    id elements = OITISafeObject(manager, @"registeredElements");
    if (![elements conformsToProtocol:@protocol(NSFastEnumeration)]) return NO;
    for (id element in elements) {
        if (!OITIIsOurElement(element) && !OITIIsBaselineLockElement(element) &&
            !OITIIsChargingSystemElement(element)) return YES;
    }
    return NO;
}

static void OITIRunStartupHello(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!islandStartupHelloEnabled) { sStartupHelloObservationWindowOpen = NO; return; }
        if (!islandEnabled) {
            sStartupHelloObservationWindowOpen = NO;
            [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype skipped because the Dynamic Island is disabled"];
            return;
        }
        BOOL stateAvailable = NO;
        if (!OITIStartupHelloIsAtUnlockedHomeScreen(&stateAvailable)) {
            sStartupHelloObservationWindowOpen = NO;
            if (!stateAvailable) {
                if (!sStartupHelloReadinessLogged) {
                    [sLog logLevel:1 tag:@"HELLO" format:@"waiting for unlock/Home Screen state (SpringBoard state selectors unavailable or not ready)"];
                    sStartupHelloReadinessLogged = YES;
                }
            } else if (sStartupHelloReadinessLogged) {
                [sLog logLevel:1 tag:@"HELLO" format:@"waiting until unlocked on the Home Screen"];
                sStartupHelloReadinessLogged = NO;
            }
            if (++sStartupHelloPolls > 180) {
                [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype gave up waiting for an unlocked Home Screen after %d checks", sStartupHelloPolls - 1];
                return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ OITIRunStartupHello(); });
            return;
        }
        sStartupHelloReadinessLogged = NO;
        sStartupHelloObservationWindowOpen = YES;
        if (sStartupHelloActivitySeen || OITIStartupHelloHasActiveSystemElement()) {
            sStartupHelloObservationWindowOpen = NO;
            [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype skipped because Island activity is already present"];
            return;
        }
        if (sStartupHelloItem || sIslandNoticeItems.count) {
            sStartupHelloObservationWindowOpen = NO;
            [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype skipped because an OITI Island item is already active"];
            return;
        }
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        NSTimeInterval last = [sOITIPreferences floatForKey:kOITIStartupHelloLastPlayedKey default:0];
        if (last > 0 && now >= last && now - last < kOITIStartupHelloCooldown) {
            sStartupHelloObservationWindowOpen = NO;
            [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype suppressed by five-minute cooldown (%.0f seconds remain)",
             kOITIStartupHelloCooldown - (now - last)];
            return;
        }
        // Persist only after the Island element was registered, so a failed presentation does not consume the cooldown.
        NSDictionary *info = @{ @"bundleID": @"com.apple.Preferences", @"appName": @"Insula",
                                @"title": @"Hello", @"subtitle": @"", @"message": @"Startup animation prototype" };
        BOOL shown = OITIPresentNoticeElement(info, @"startup-hello");
        sStartupHelloObservationWindowOpen = NO;
        if (shown) {
            [sOITIPreferences setObject:@(now) forKey:kOITIStartupHelloLastPlayedKey];
            [sOITIPreferences synchronize];
        }
        [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype %@", shown ? @"presented" : @"could not be presented"];
    });
}


// Status bar provider choice. A separate group so it installs and fails independently of the Island hooks. It is
// installed under the same safe-mode rule, so safe mode turns it off too.
%group OITIStatusBarHooks

%hook _UIStatusBarVisualProvider_iOS

+ (Class)visualProviderSubclassForScreen:(id)screen visualProviderInfo:(id)info {
    Class chosen = %orig;
    return OITIStatusBarProviderDecision(chosen, screen, info);
}

%end

%hook _UIStatusBar

- (void)_prepareVisualProviderIfNeeded {
    %orig;
    OITILogLiveStatusBar(self);
}

%end

%end

// =============================================================================================
// MARK: Preferences
// =============================================================================================

// Asks the Island windows to lay out again so new settings (scale, position) apply immediately. The layoutSubviews
// hook does the actual work. Harmless when no window has been seen yet (or in safe mode, when no hook exists).
//
// The custom color, transparency and outline settings are applied in the layoutSubviews of two inner view classes, and
// setNeedsLayout on a window does not reach them, so those views are marked too. The custom banner position lives in
// the banner window's frame, which is set again here. Turning the banner position OFF only takes effect the next time
// the system sets the banner frame (the next banner), because OITI does not know the original frame.
static void OITIMarkOverrideViewsForLayout(UIView *view, NSUInteger depth) {
    static Class contentClass;
    static Class passThroughClass;
    if (!contentClass) contentClass = NSClassFromString(@"_SBSystemApertureContainerViewContentView");
    if (!passThroughClass) passThroughClass = NSClassFromString(@"SBFTouchPassThroughView");
    if ((contentClass && [view isKindOfClass:contentClass]) || (passThroughClass && [view isKindOfClass:passThroughClass])) {
        [view setNeedsLayout];
    }
    if (depth >= 12) return;
    for (UIView *subview in view.subviews) OITIMarkOverrideViewsForLayout(subview, depth + 1);
}

static void OITIRefreshIslandLayout(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *window in sLiveApertureWindows.allObjects) {
            [window setNeedsLayout];
            OITIMarkOverrideViewsForLayout(window, 0);
        }
        if (notificationFix || notEnabled) {
            for (UIView *banner in sBannerWindows.allObjects) {
                CGRect current = banner.frame;
                banner.frame = current;   // the setFrame: hook applies the override
            }
        }
    });
}

static void preferencesChanged(void) {
    BOOL islandNotificationsWereEnabled = islandNotificationsEnabled;
    BOOL islandNotificationStackWasEnabled = sIslandNotificationStackEnabled;
    BOOL startupHelloWasEnabled = islandStartupHelloEnabled;
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
    islandNotificationsEnabled = [sOITIPreferences boolForKey:@"islandNotificationsEnabled" default:NO];
    islandNotificationsHideBanner = [sOITIPreferences boolForKey:@"islandNotificationsHideBanner" default:NO];
    sIslandNotificationStackEnabled = [sOITIPreferences boolForKey:@"islandNotificationStackEnabled" default:YES];
    islandStartupHelloEnabled = [sOITIPreferences boolForKey:@"IslandStartupHelloEnabled" default:NO];
    BOOL downloadProgressWasEnabled = sDownloadProgressEnabled;
    sDownloadProgressEnabled = [sOITIPreferences boolForKey:@"DownloadProgressEnabled" default:NO];
    sDownloadAppStoreEnabled = [sOITIPreferences boolForKey:@"DownloadAppStoreEnabled" default:NO];
    sDownloadTestFractionOnly = [sOITIPreferences boolForKey:@"DownloadTestFractionOnly" default:NO];
    CGFloat downloadIdleMB = [sOITIPreferences floatForKey:@"DownloadIdleAfterMB" default:0.0];
    sDownloadIdleAfterMB = isfinite(downloadIdleMB) ? MAX(0.0, MIN(5000.0, downloadIdleMB)) : 0.0;
    CGFloat downloadIdleSeconds = [sOITIPreferences floatForKey:@"DownloadIdleAfterSeconds" default:0.0];
    sDownloadIdleAfterSeconds = isfinite(downloadIdleSeconds) ? MAX(0.0, MIN(900.0, downloadIdleSeconds)) : 0.0;
    NSInteger downloadPreviousStyle = sDownloadStyle;
    sDownloadStyle = (NSInteger)lround([sOITIPreferences floatForKey:@"DownloadProgressStyle" default:0.0]) == 1 ? 1 : 0;
    CGFloat pillWidth = [sOITIPreferences floatForKey:@"DownloadPillWidth" default:296.0];
    sDownloadPillWidth = isfinite(pillWidth) ? MAX(200.0, MIN(380.0, pillWidth)) : 296.0;
    CGFloat pillBottom = [sOITIPreferences floatForKey:@"DownloadPillBottomPadding" default:10.0];
    sDownloadPillBottomPadding = isfinite(pillBottom) ? MAX(0.0, MIN(40.0, pillBottom)) : 10.0;
    CGFloat pillNudge = [sOITIPreferences floatForKey:@"DownloadPillNudgeY" default:0.0];
    sDownloadPillNudgeY = isfinite(pillNudge) ? MAX(-30.0, MIN(30.0, pillNudge)) : 0.0;
    dispatch_async(dispatch_get_main_queue(), ^{ [sDownloadPill relayout]; });   // live size changes
    CGFloat downloadTestMB = [sOITIPreferences floatForKey:@"DownloadTestSizeMB" default:800.0];
    sDownloadTestSizeMB = isfinite(downloadTestMB) ? MAX(50.0, MIN(5000.0, downloadTestMB)) : 800.0;

    // Apple Mode: force every customization off here, after the stored values are read and before anything below
    // compares old and new state, so turning it on behaves exactly like switching each feature off (stack cleared,
    // startup animation cancelled, transforms reset). The stored preferences are not touched.
    BOOL appleModeWasOn = sAppleMode;
    sAppleMode = [sOITIPreferences boolForKey:@"appleMode" default:NO];
    if (sAppleMode) {
        posEnabled = NO;
        hideEnabled = NO;
        notEnabled = NO;
        colorEnabled = NO;
        transEnabled = NO;
        scaleEnabled = NO;
        lineDisabled = NO;
        islandNotificationsEnabled = NO;
        islandNotificationsHideBanner = NO;
        islandStartupHelloEnabled = NO;
        sDownloadProgressEnabled = NO;
        sDownloadAppStoreEnabled = NO;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ OITIAppStoreSourceRefresh(); });   // starts or stops the App Store source
    if (sDownloadProgressEnabled != downloadProgressWasEnabled || sDownloadStyle != downloadPreviousStyle) {
        BOOL restyle = sDownloadStyle != downloadPreviousStyle;
        dispatch_async(dispatch_get_main_queue(), ^{
            // A new look needs a new view, so the old one is removed and the refresh presents the next.
            if (restyle && sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"restyle");
            if (restyle) OITIDownloadPillDismiss(@"restyle");
            OITIDownloadsRefresh();   // present or remove the view for the new setting
        });
    }
    if (sAppleMode != appleModeWasOn && sLog) {
        [sLog logTag:@"PREF" format:@"Apple Mode %@: Island customizations are %@", sAppleMode ? @"ON" : @"OFF",
         sAppleMode ? @"forced off (stock Island)" : @"back to the user's settings"];
    }
    CGFloat noticeDuration = [sOITIPreferences floatForKey:@"IslandNotificationsDuration" default:4.0];
    sIslandNoticeDuration = isfinite(noticeDuration) ? MAX(1.0, MIN(15.0, noticeDuration)) : 4.0;

    if (startupHelloWasEnabled && !islandStartupHelloEnabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            OITICancelStartupHello(@"disabled-in-settings");
        });
    }

    if (islandNotificationStackWasEnabled && !sIslandNotificationStackEnabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<NSDictionary *> *items = [sIslandNoticeItems copy];
            if (items.count > 1) {
                for (NSUInteger i = 0; i + 1 < items.count; i++) {
                    OITIRemoveNoticeItem(items[i], @"stack-disabled");
                }
            }
            [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK disabled from Settings; retained newest item and cleared older items"];
        });
    }

    if (islandNotificationsWereEnabled && !islandNotificationsEnabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<NSDictionary *> *items = [sIslandNoticeItems copy];
            for (NSDictionary *item in items) OITIRemoveNoticeItem(item, @"feature-disabled");
            if (sBannerHideActive) {
                OITIRestoreBannerWindows();
                sBannerHideActive = NO;
            }
            [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK cleared because Island Notifications was turned off"];
        });
    }

    // Defaults match the globals above (and the prefs UI).
    xPos = [sOITIPreferences floatForKey:@"xPos" default:0.0];
    yPos = [sOITIPreferences floatForKey:@"yPos" default:20.5];
    xNot = [sOITIPreferences floatForKey:@"xNot" default:0.0];
    yNot = [sOITIPreferences floatForKey:@"yNot" default:40.0];
    red = [sOITIPreferences floatForKey:@"red" default:0.0];
    green = [sOITIPreferences floatForKey:@"green" default:0.0];
    blue = [sOITIPreferences floatForKey:@"blue" default:0.0];
    alpha = [sOITIPreferences floatForKey:@"alpha" default:1.0];
    scaleX = [sOITIPreferences floatForKey:@"RelativeScaleX" default:1.0];
    scaleY = [sOITIPreferences floatForKey:@"RelativeScaleY" default:1.0];

    // Island size multipliers (Apple's layout reads them again on its next layout, so changes apply live).
    sMetricsSensorX = OITIClampMetricsFactor([sOITIPreferences floatForKey:@"MetricsSensorWidthScale" default:1.0]);
    sMetricsSensorY = OITIClampMetricsFactor([sOITIPreferences floatForKey:@"MetricsSensorHeightScale" default:1.0]);
    if (sAppleMode) {
        sMetricsSensorX = 1.0;
        sMetricsSensorY = 1.0;
    }

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
    sObservedApertureManagers = [NSHashTable weakObjectsHashTable];
    sBannerWindows = [NSHashTable weakObjectsHashTable];
    sLiveApertureWindows = [NSHashTable weakObjectsHashTable];
    sLoggedProviderChoices = [NSMutableSet set];
    sLoggedStatusBars = [NSHashTable weakObjectsHashTable];

    preferencesChanged();
    sIslandEnabledAtLaunch = islandEnabled;
    sStartupHelloObservationWindowOpen = NO;

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
        OITIEvaluateElementBreadcrumb();
        OITObserveDarwinNotification(kOITITestDownloadStartNotification, ^{
            dispatch_async(dispatch_get_main_queue(), ^{ OITIFakeDownloadStart(); });
        });
        OITObserveDarwinNotification(kOITITestDownloadStopNotification, ^{
            dispatch_async(dispatch_get_main_queue(), ^{ OITIFakeDownloadStop(); });
        });
        OITIInstallIslandSizeHooks();
        OITIInstallResearchHooks();
        if (sLog.enabled && sLog.level >= 1) {
            OITIInstallDiagnosticHooks();
        }
        OITIInstallIslandNotificationHooks();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            OITIRunStartupHello();
            if (sLog.enabled && sLog.level >= 1 &&
                [sOITIPreferences boolForKey:@"IslandNotificationsHelloOnBoot" default:NO]) {
                OITIRunPoCElement(@"boot+10s");
            }
        });
        %init(OITIStatusBarHooks);
        [sLog logTag:@"SESSION" format:@"READY hooks installed (profile=%d diagnostics=%d level=%ld)",
         OITICurrentProfile() != NULL, sLog.enabled, (long)sLog.level];
    }

    OITIObserveDumpNotification();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        OITIRunStartupSelfCheck();
    });

    // Status bar provider report. UIScreen and UIKit class methods are read on the main thread, after the
    // status bar has had time to be built, and it also runs in safe mode (diagnostics still work there).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        OITIRunStatusBarDiagnostic(@"boot");
    });
}
