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
static const NSTimeInterval kOITIStartupHelloPrototypeDuration = 8.0;

static NSString * const kOITIBootLogPath = @"/var/mobile/Library/Preferences/OITIBootLog.plist";
static NSString * const kOITISafeModePath = @"/var/mobile/Library/Preferences/OITISafeMode.plist";
// Written by OITI's settings pages just before they ask for a respring (Respring button, Clear Safe Mode). The loop
// guard consumes it: a respring the user asked for is not a crash, so that launch is not counted. Older than
// kOITIRespringIntentMaxAge seconds it is ignored.
static NSString * const kOITIRespringIntentPath = @"/var/mobile/Library/Preferences/OITIRespringIntent.plist";
static const NSTimeInterval kOITIRespringIntentMaxAge = 30.0;
// Exists while one of OITI's Island elements is live (see ELEMENT CRASH RECOVERY above).
static NSString * const kOITILiveElementPath = @"/var/mobile/Library/Preferences/OITILiveElement.plist";
static const NSTimeInterval kOITIElementRecoveryWindow = 120.0;
static CFAbsoluteTime sElementRecoveryUntil = 0;     // while in the future, no Island element is created
static BOOL sLaunchWasRequestedRespring = NO;        // this launch followed a respring asked for in OITI's settings
static NSString * const kOITIGestaltBackupBreadcrumbPath = @"/var/mobile/Library/Preferences/OITIGestaltBackup.plist";
static NSString * const kOITIGestaltPlistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static NSString * const kOITIGestaltCacheExtraKey = @"CacheExtra";
static NSString * const kOITIGestaltNestedKey = @"oPeik/9e8lQWMszEjbPzng";
static NSString * const kOITIGestaltLeafKey = @"ArtworkDeviceSubType";
static const char * const kOITIRestoreHelperPath = "/var/jb/usr/libexec/OITIRestoreGestalt";


static CGFloat red = 0.0;
static CGFloat green = 0.0;
static CGFloat blue = 0.0;
static CGFloat alpha = 1.0;

static CGFloat scaleX = 1.0;   // RelativeScaleX: 1.0 = Apple's own size
static CGFloat scaleY = 1.0;   // RelativeScaleY

// Island size multipliers applied to sensorRegionSize from SBUISystemApertureLayoutMetrics.
// 1.0 = Apple's own value (no change). See the header comment.
CGFloat sMetricsSensorX = 1.0;
CGFloat sMetricsSensorY = 1.0;
// The last value Apple's own getter returned before our multiplier, kept for the dump (zero = not called yet).
CGSize sRawSensorRegionSize;

static CGFloat xPos = 0;
static CGFloat yPos = 20.5;
static CGFloat xNot = 0.0;
static CGFloat yNot = 40;

static BOOL fixEnabled;
BOOL islandEnabled;
static BOOL posEnabled;
static BOOL hideEnabled;
static BOOL notificationFix;
static BOOL notEnabled;
static BOOL colorEnabled;
static BOOL transEnabled;
static BOOL scaleEnabled;
static BOOL lineDisabled;
static BOOL islandNotificationsEnabled;       // OITI > Notifications: show notifications as an Island element (default NO)
static BOOL islandNotificationsHideBanner;    // also fade the stock banner window out while our element is up (default NO)
static BOOL sIslandNotificationStackEnabled = YES; // Experimental multi-notification stack (default YES for existing behavior)
static BOOL sAppleMode;                        // appleMode: every customization below is forced off while YES
static BOOL sDownloadProgressEnabled;          // DownloadProgressEnabled (default NO)
static BOOL sDownloadAppStoreEnabled;          // DownloadAppStoreEnabled (default NO): feed the tracker from App Store downloads
static BOOL sDownloadTestFractionOnly;         // DownloadTestFractionOnly (default NO, defaults write only): the test download reports a percentage only
static CGFloat sDownloadIdleAfterMB = 0;       // DownloadIdleAfterMB: return the Island to idle after this many MB downloaded, 0 = never
static CGFloat sDownloadIdleAfterSeconds = 0;  // DownloadIdleAfterSeconds: the same after this long on screen, 0 = never
static CGFloat sDownloadTestSizeMB = 800;      // DownloadTestSizeMB: size of the test download
static NSInteger sDownloadStyle = 0;           // DownloadProgressStyle: 0 minimal (default), 1 detailed
static CGFloat sDownloadPillWidth = 296;         // DownloadPillWidth: the Minimal pill, in points (never narrower than the Island plus a margin)
static CGFloat sDownloadPillBottomPadding = 10;  // DownloadPillBottomPadding: space under the content
static CGFloat sDownloadPillNudgeY = 0;          // DownloadPillNudgeY: moves the pill up or down from the Island's top
static BOOL islandStartupHelloEnabled;        // OITI > Startup Animation prototype (default NO)
static BOOL sStartupHelloObservationWindowOpen;
static BOOL sStartupHelloActivitySeen;
static BOOL sStartupHelloReadinessLogged;
static int sStartupHelloPolls;   // once-a-second readiness checks so far; the check gives up after 180 (3 minutes)
static CGFloat sIslandNoticeDuration = 4.0;   // seconds, key IslandNotificationsDuration, clamped 1 - 15

// Diagnostics and safe-mode settings (prefs keys listed in the header comment).
static BOOL sGuardEnabled = YES;
static NSInteger sGuardMaxLaunches = 5;
static NSInteger sGuardWindowSeconds = 120;
static NSInteger sGuardStableSeconds = 45;
static BOOL sGuardRestoreGestalt = NO;

static const void *kOITIAppliedScaleKey = &kOITIAppliedScaleKey;
static const void *kOITIHiddenByUsKey = &kOITIHiddenByUsKey;
static const void *kOITIColorAppliedKey = &kOITIColorAppliedKey;
// Island transparency and outline hiding: the alpha OITI last set on a view / a flag that OITI hid it, so a changed
// or switched-off setting applies live without fighting Apple's own changes to the same view.
static const void *kOITITransparencyAppliedKey = &kOITITransparencyAppliedKey;
static const void *kOITILineHiddenKey = &kOITILineHiddenKey;
static const void *kOITIPassThroughTouchedKey = &kOITIPassThroughTouchedKey;

// Shared state: declared in Shared/OITIShared.h. The definitions stay here until the Shared round moves them.
OITLogger *sLog;
// Weak references: the research hooks observe Apple's manager but must not keep it alive.
NSHashTable *sObservedApertureManagers;
OITPreferences *sOITIPreferences;
static NSDictionary<NSString *, NSNumber *> *sLastPrefSnapshot;
BOOL sSafeModeActive = NO;

// Weak references to the live instances our hooks have seen; used only by the dump.
NSHashTable<UIView *> *sApertureWindows;
static NSHashTable<UIView *> *sLiveApertureWindows;   // always maintained: used to re-layout after a setting changes
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
static void OITIRefreshNewestNoticeComposite(void);


static CGFloat OITISafeScaleValue(CGFloat value) {
    if (!isfinite(value)) return 1.0;
    if (value < 0.05) return 1.0;
    if (value > 3.0) return 3.0;
    return value;
}

// Apple's own scale for the Island window: its canvas (360 x 640 on the 8 Plus) is stretched to the screen width by a
// uniform transform (1.15 there). Setting a transform replaces Apple's, so a scale relative to stock multiplies this
// back in. The shorter sides are compared so it holds in either orientation. Falls back to 1.0 if the numbers are
// not sane.
static CGFloat OITIAppleCanvasScale(UIView *window) {
    CGSize canvas = window.bounds.size;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat canvasSide = MIN(canvas.width, canvas.height);
    CGFloat screenSide = MIN(screen.width, screen.height);
    if (canvasSide < 1.0 || screenSide < 1.0) return 1.0;
    CGFloat factor = screenSide / canvasSide;
    return (isfinite(factor) && factor >= 0.5 && factor <= 3.0) ? factor : 1.0;
}

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
// MARK: Hooks
// =============================================================================================

// Experimental Island size multipliers: keep them in a range that cannot collapse or explode the layout.
static CGFloat OITIClampMetricsFactor(CGFloat value) {
    if (!isfinite(value)) return 1.0;
    return MAX(0.3, MIN(2.0, value));
}

static CGSize OITIApplyMetricsFactor(CGSize size, CGFloat factorX, CGFloat factorY) {
    if (factorX == 1.0 && factorY == 1.0) return size;   // exact pass-through when unused
    return CGSizeMake(size.width * factorX, size.height * factorY);
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
// MARK: Island notifications (beta)
// =============================================================================================

// Apple's SAUISystemApertureManager instances. sRegisteringManager is the one that last registered an element (the
// manager for the Island content scene); sSeenManager is the first one that answered orderedElementViewControllers.
// Weak: we must not keep Apple's objects alive.
static __weak id sRegisteringManager;
static __weak id sSeenManager;
static __weak id sSystemApertureController;   // SBSystemApertureController: the registrar real providers use

// Strong references to the elements we registered (element, provider, registration, view), so ARC does not release
// them while the Island still shows them.
static NSMutableArray<NSDictionary *> *sIslandNoticeItems;
static id sPendingNoticeRequest;   // the NCNotificationRequest being presented, kept with its element for the tap action
static NSMutableDictionary *sStartupHelloItem;
static NSMutableDictionary *sDownloadItem;   // the Island element showing download progress, or nil
static CFAbsoluteTime sDownloadShownAt = 0;  // when it went up, for the time limit
static NSUInteger sDownloadDropCount = 0;    // times the system ended the element on its own during this download
// What Apple is told for "preferredAlertingDuration:" for a download element. Apple ends an alert after that long and
// OITI is not told, so for a download it has to be far longer than any download (the notice duration, a few seconds,
// is right only for notices).
static const double kOITIDownloadAlertDuration = 86400.0;
static void OITIDownloadItemRemoved(NSDictionary *item, NSString *reason);
static const NSUInteger kOITINoticeStackLimit = 4;   // one expanded plus three compact, or four compact
static void OITIDismissNoticeItem(NSDictionary *item);
static void OITIRestoreCorners(void);
static void OITICancelStartupHello(NSString *reason);

@interface OITIStartupVideoView : UIView
@property (nonatomic, strong, readonly) AVPlayer *player;
- (instancetype)initWithURL:(NSURL *)url;
- (NSTimeInterval)mediaDuration;
- (void)startPlayback;
- (void)stopPlayback;
@end

// Layout-mode numbers copied from the first real (Apple) element that registers, so our element can use values Apple
// itself uses instead of guessed enum numbers. Keys: preferred, minimum, maximum.
static NSDictionary<NSString *, NSNumber *> *sRealLayoutValues;
static BOOL sPoCOurRegistrationInFlight = NO;
static BOOL sPoCDisabledAfterFailure = NO;   // set after 5 guard catches; cleared only by a respring
static int sPoCFailureCount = 0;

static const void *kOITIBannerOriginalAlphaKey = &kOITIBannerOriginalAlphaKey;
static BOOL sBannerHideActive = NO;
static BOOL sBannerHideSawBanner = NO;
static BOOL sBannerHideCanProbe = NO;
static CFAbsoluteTime sBannerHideStart = 0;
static __weak id sBannerHideDestination;


// Apple's element code calls -elementIdentifier on the "identifier" argument (a plain NSString crashed with
// "-[__NSCFString elementIdentifier]: unrecognized selector"), so the identifier must be an object. This stub answers
// elementIdentifier with our string and logs every other selector Apple sends it (once each), answering with the string
// for anything identifier-like and nil otherwise. The ELEMENT STUB lines show what Apple really wants from it.
@interface OITIElementIdentifierStub : NSObject <NSCopying>
@property (nonatomic, copy) NSString *value;
@end

static NSMutableSet<NSString *> *sStubSelectorsSeen;

@implementation OITIElementIdentifierStub
- (id)elementIdentifier { return self.value; }
- (id)clientIdentifier { return @"com.apple.springboard"; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return self.value ?: @"OITIElementIdentifierStub"; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [super methodSignatureForSelector:selector] ?: [NSMethodSignature signatureWithObjCTypes:"@@:"];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    NSString *name = NSStringFromSelector(invocation.selector);
    @synchronized ([OITIElementIdentifierStub class]) {
        if (!sStubSelectorsSeen) sStubSelectorsSeen = [NSMutableSet set];
        if (![sStubSelectorsSeen containsObject:name]) {
            [sStubSelectorsSeen addObject:name];
            [sLog logTag:@"ELEMENT" format:@"STUB identifier was sent -%@ (answering with %@)", name,
             [name rangeOfString:@"dentifier" options:NSCaseInsensitiveSearch].location != NSNotFound ? @"the string" : @"nil"];
        }
    }
    id result = [name rangeOfString:@"dentifier" options:NSCaseInsensitiveSearch].location != NSNotFound ? self.value : nil;
    [invocation setReturnValue:&result];
}
@end

// Returns an object-valued, no-argument selector's result, or nil if the object does not implement it with that shape.
static id OITISafeObject(id object, NSString *selectorName) {
    if (!object || !selectorName.length) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, "@") != 0) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:selector];
#pragma clang diagnostic pop
}

static NSString *OITISafeString(id object, NSString *selectorName) {
    id value = OITISafeObject(object, selectorName);
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

static NSNumber *OITIKVCNumber(id object, NSString *key) {
    if (!object) return nil;
    @try {
        id value = [object valueForKey:key];
        return [value isKindOfClass:[NSNumber class]] ? (NSNumber *)value : nil;
    } @catch (NSException *exception) {
        return nil;
    }
}

static id OITIKVCObject(id object, NSString *key) {
    if (!object) return nil;
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}

// Which parts an element has (class name or nil). Real elements versus ours: the nil that breaks Apple's code is in here.
static NSString *OITIElementPartsSummary(id element) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in @[@"viewProvider", @"elementHost", @"layoutHost", @"leadingView", @"trailingView", @"minimalView",
                            @"primaryView", @"secondaryView", @"actionView", @"element"]) {
        id value = OITIKVCObject(element, key);
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, value ? NSStringFromClass([value class]) : @"nil"]];
    }
    return [parts componentsJoinedByString:@" "];
}

// "[idA, idB]" for an array of elements (their elementIdentifier), for the authority ordering log.
static NSString *OITIElementIdentifierList(id elements) {
    if (![elements conformsToProtocol:@protocol(NSFastEnumeration)]) return OITIObjectSummary(elements);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id element in elements) {
        id identifier = OITIKVCObject(element, @"elementIdentifier");
        [names addObject:[NSString stringWithFormat:@"%@", identifier ?: NSStringFromClass([element class])]];
    }
    return [NSString stringWithFormat:@"[%@]", [names componentsJoinedByString:@", "]];
}

// One line describing an element: class, both identifiers, layout modes.
static NSString *OITIElementValuesSummary(id element) {
    id elementID = OITIKVCObject(element, @"elementIdentifier");
    id clientID = OITIKVCObject(element, @"clientIdentifier");
    return [NSString stringWithFormat:@"%@ elementIdentifier=%@(%@) clientIdentifier=%@(%@) layoutMode=%@ preferred=%@ min=%@ max=%@",
            NSStringFromClass([element class]), elementID, elementID ? NSStringFromClass([elementID class]) : @"nil",
            clientID, clientID ? NSStringFromClass([clientID class]) : @"nil",
            OITIKVCNumber(element, @"layoutMode"), OITIKVCNumber(element, @"preferredLayoutMode"),
            OITIKVCNumber(element, @"minimumSupportedLayoutMode"), OITIKVCNumber(element, @"maximumSupportedLayoutMode")];
}

// Called after Apple registers one of its own elements: log its values and remember the first set of layout modes.
static void OITICaptureRealElement(id element) {
    if (!element) return;
    if ([sLog isLoggingAtLevel:1]) {
        [sLog logTag:@"ELEMENT" format:@"REAL element %@", OITIElementValuesSummary(element)];
        [sLog logTag:@"ELEMENT" format:@"REAL parts   %@: %@", NSStringFromClass([element class]), OITIElementPartsSummary(element)];
    }
    if (sRealLayoutValues) return;
    NSNumber *preferred = OITIKVCNumber(element, @"preferredLayoutMode");
    NSNumber *minimum = OITIKVCNumber(element, @"minimumSupportedLayoutMode");
    NSNumber *maximum = OITIKVCNumber(element, @"maximumSupportedLayoutMode");
    if (preferred && minimum && maximum) {
        sRealLayoutValues = @{ @"preferred": preferred, @"minimum": minimum, @"maximum": maximum };
        [sLog logTag:@"ELEMENT" format:@"remembered real layout values preferred=%@ min=%@ max=%@ from %@", preferred, minimum, maximum,
         NSStringFromClass([element class])];
    }
}

// ---- Trace of what Apple asks OITI's element ------------------------------------------------
static NSMutableSet<NSString *> *sTraceSeen;
static NSInteger OITINoticeStyle(void);

static BOOL OITIIsOurElement(id element) {
    if (!element || !sIslandNoticeItems.count) return NO;
    for (NSDictionary *item in sIslandNoticeItems) {
        if (item[@"element"] == element) return YES;
    }
    return NO;
}

// The item (notice, Hello or download) an element belongs to, or nil.
static NSDictionary *OITIItemForElement(id element) {
    if (!element) return nil;
    for (NSDictionary *item in sIslandNoticeItems) {
        if (item[@"element"] == element) return item;
    }
    return nil;
}

// The charging activity is an ordinary system aperture element. Let Hello play ahead of it,
// then allow SpringBoard to promote charging after Hello is removed. Other system activities
// (especially calls) keep the normal immediate-yield behavior.
static BOOL OITIIsChargingSystemElement(id element) {
    id identifier = OITIKVCObject(element, @"elementIdentifier");
    return [identifier isKindOfClass:[NSString class]] &&
           [identifier isEqualToString:@"SBChargingSystemApertureElementProvider"];
}

// SpringBoard only promotes one alert at a time. Keep the newest notice in the alert lane and let
// older notices participate as compact activities so the aperture can present them alongside it.
static BOOL OITIIsNewestNoticeElement(id element) {
    return element && sIslandNoticeItems.count && sIslandNoticeItems.lastObject[@"element"] == element;
}

static BOOL OITIIsAlertNoticeElement(id element) {
    if (OITIItemForElement(element)[@"download"]) return OITIIsNewestNoticeElement(element);   // wide or expanded, whatever the notification style is
    return OITINoticeStyle() != 0 && OITIIsNewestNoticeElement(element);
}

static NSInteger OITINoticeStyle(void) {
    NSInteger style = (NSInteger)lround([sOITIPreferences floatForKey:@"IslandNotificationsStyle" default:2]);
    return MAX(0, MIN(2, style));   // 0 compact, 1 wide, 2 expanded
}

// Existing items remain registered while their preferred mode changes. Registering or invalidating an item
// causes Apple's authority to reevaluate the ordering and choose the new preferred layout.
static void OITIScheduleNoticeTimeout(NSMutableDictionary *item);

static void OITISetNoticeLayout(NSDictionary *item, NSInteger style, BOOL isNewest) {
    id element = item[@"element"];
    if (!element) return;
    if (item[@"download"]) style = 2;   // the Detailed download look is the expanded layout, whatever the notification style is

    BOOL compact = (style == 0) || !isNewest;
    NSInteger layoutVariant = compact ? 1 : (style == 1 ? 6 : 5);
    NSInteger devVariant = (NSInteger)lround([sOITIPreferences floatForKey:@"IslandNotificationsDevLayout" default:-1]);
    if (isNewest && devVariant >= 0) layoutVariant = devVariant;
    NSInteger minimum = 1, preferred = 1, maximum = 1;
    if (layoutVariant == 2 && sRealLayoutValues) {
        minimum = sRealLayoutValues[@"minimum"].integerValue;
        preferred = sRealLayoutValues[@"preferred"].integerValue;
        maximum = sRealLayoutValues[@"maximum"].integerValue;
    } else if (layoutVariant == 3) {
        preferred = 2; maximum = 3;
    } else if (layoutVariant == 4) {
        minimum = -1; preferred = 2; maximum = 2;
    } else if (layoutVariant == 5) {
        preferred = 3; maximum = 3;
    } else if (layoutVariant == 6) {
        preferred = 2; maximum = 2;
    }
    SEL setPreferred = NSSelectorFromString(@"setPreferredLayoutMode:");
    SEL setMinimum = NSSelectorFromString(@"setMinimumSupportedLayoutMode:");
    SEL setMaximum = NSSelectorFromString(@"setMaximumSupportedLayoutMode:");
    @try {
        if ([element respondsToSelector:setMinimum]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(element, setMinimum, minimum);
        if ([element respondsToSelector:setMaximum]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(element, setMaximum, maximum);
        if ([element respondsToSelector:setPreferred]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(element, setPreferred, preferred);
        BOOL alert = (style != 0 && isNewest);
        [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK layout %@ mode=%ld/%ld/%ld newest=%d alert=%d activity=%d style=%ld",
         OITIKVCObject(element, @"elementIdentifier"), (long)minimum, (long)preferred, (long)maximum,
         isNewest, alert, !alert, (long)style];
    } @catch (NSException *exception) {
        [sLog logTag:@"ELEMENT" format:@"STACK layout update failed for %@: %@ %@",
         OITIKVCObject(element, @"elementIdentifier"), exception.name, exception.reason];
    }
}

// ---- Element crash recovery ------------------------------------------------------------------
// Written (synchronously, so it survives an immediate crash) when the first OITI element goes live, deleted when the
// last one leaves. Found at launch it means the previous SpringBoard ended while an element was live.
static void OITIWriteElementBreadcrumb(NSString *reason) {
    NSDictionary *crumb = @{ @"time": @([[NSDate date] timeIntervalSince1970]),
                             @"pid": @(getpid()),
                             @"reason": reason ?: @"",
                             @"build": kOITIBuildTag };
    if (![crumb writeToFile:kOITILiveElementPath atomically:YES]) {
        [sLog logTag:@"ELEMENT" format:@"RECOVERY breadcrumb could not be written"];
    }
}

static void OITIClearElementBreadcrumb(void) {
    [[NSFileManager defaultManager] removeItemAtPath:kOITILiveElementPath error:nil];
}

// Called once at launch, before the hooks are installed. A breadcrumb left by a SpringBoard that ended while an OITI
// element was live starts the recovery window, unless that launch was a respring requested from OITI's own settings
// (the previous process was healthy then).
static void OITIEvaluateElementBreadcrumb(void) {
    NSDictionary *crumb = [NSDictionary dictionaryWithContentsOfFile:kOITILiveElementPath];
    if (!crumb) return;
    OITIClearElementBreadcrumb();
    id when = crumb[@"time"];
    NSTimeInterval age = [when isKindOfClass:[NSNumber class]] ? [[NSDate date] timeIntervalSince1970] - [when doubleValue] : -1;
    if (sLaunchWasRequestedRespring) {
        [sLog logTag:@"ELEMENT" format:@"RECOVERY not needed: SpringBoard was restarted from OITI's settings while an element was live (%@)", crumb[@"reason"]];
        return;
    }
    sElementRecoveryUntil = CFAbsoluteTimeGetCurrent() + kOITIElementRecoveryWindow;
    [sLog logTag:@"ELEMENT" format:@"RECOVERY the previous SpringBoard ended while an OITI Island element was live (%@, %.0f s before this launch, build %@): Island notifications and the startup animation stay off for %.0f s and the stock banner is used",
     crumb[@"reason"], age, crumb[@"build"], kOITIElementRecoveryWindow];
}

// True while the recovery window is open. Main thread only.
static BOOL OITIElementRecoveryActive(NSString *reason) {
    if (sElementRecoveryUntil <= 0) return NO;
    CFAbsoluteTime left = sElementRecoveryUntil - CFAbsoluteTimeGetCurrent();
    if (left <= 0) {
        sElementRecoveryUntil = 0;
        [sLog logTag:@"ELEMENT" format:@"RECOVERY window is over: Island elements are allowed again"];
        return NO;
    }
    [sLog logTag:@"ELEMENT" format:@"RECOVERY: %@ is not shown as an Island element (%.0f s left); the stock banner is used", reason, left];
    return YES;
}

// Expire or swipe away one item. If the visible newest item leaves, promote the newest survivor.
static void OITIRemoveNoticeItem(NSDictionary *item, NSString *reason) {
    NSUInteger index = [sIslandNoticeItems indexOfObjectIdenticalTo:item];
    if (index == NSNotFound) return;
    BOOL wasNewest = (index == sIslandNoticeItems.count - 1);
    dispatch_block_t timeout = item[@"timeoutBlock"];
    if (timeout) dispatch_block_cancel(timeout);
    for (id playbackObserver in item[@"playbackObservers"] ?: @[]) {
        [[NSNotificationCenter defaultCenter] removeObserver:playbackObserver];
    }
    [(OITIStartupVideoView *)item[@"startupVideoView"] stopPlayback];
    if (wasNewest && index > 0) {
        OITIScheduleNoticeTimeout((NSMutableDictionary *)sIslandNoticeItems[index - 1]);
        OITISetNoticeLayout(sIslandNoticeItems[index - 1], OITINoticeStyle(), YES);
    }
    OITIDismissNoticeItem(item);
    [sIslandNoticeItems removeObjectAtIndex:index];
    if (item == sStartupHelloItem) sStartupHelloItem = nil;
    if (item == sDownloadItem) OITIDownloadItemRemoved(item, reason);
    OITIRefreshNewestNoticeComposite();
    [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK removed %@ reason=%@ remaining=%lu",
     OITIKVCObject(item[@"element"], @"elementIdentifier"), reason, (unsigned long)sIslandNoticeItems.count];
    if (sIslandNoticeItems.count == 0) {
        OITIRestoreCorners();
        OITIClearElementBreadcrumb();
    }
}

// Give a notice a fresh lifetime when it is demoted from the expanded slot to the compact list.
// The weak capture avoids a retain cycle between the item dictionary and its timeout block.
static void OITIScheduleNoticeTimeout(NSMutableDictionary *item) {
    dispatch_block_t previous = item[@"timeoutBlock"];
    if (previous) dispatch_block_cancel(previous);
    __weak NSMutableDictionary *weakItem = item;
    dispatch_block_t timeout = dispatch_block_create((dispatch_block_flags_t)0, ^{
        NSMutableDictionary *strongItem = weakItem;
        if (strongItem && [sIslandNoticeItems containsObject:strongItem]) {
            OITIRemoveNoticeItem(strongItem, @"timeout");
        }
    });
    item[@"timeoutBlock"] = timeout;
    NSTimeInterval duration = [item[@"timeoutDuration"] respondsToSelector:@selector(doubleValue)]
        ? [item[@"timeoutDuration"] doubleValue] : sIslandNoticeDuration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), timeout);
}

static void OITICancelStartupHello(NSString *reason) {
    NSDictionary *item = sStartupHelloItem;
    if (!item) return;
    [sLog logLevel:1 tag:@"HELLO" format:@"yielding startup card to Island activity (%@)", reason];
    OITIRemoveNoticeItem(item, reason ?: @"interrupted");
}

static BOOL OITIIsBaselineLockElement(id element) {
    NSString *identifier = [OITIKVCObject(element, @"elementIdentifier") description];
    NSString *className = NSStringFromClass([element class]);
    return [identifier rangeOfString:@"lock" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [className rangeOfString:@"LockElement" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// Logs one TRACE line per distinct message per test run, in the order they first happen.
static void OITITraceOnce(NSString *message) {
    @synchronized ([NSNull null]) {
        if (!sTraceSeen) sTraceSeen = [NSMutableSet set];
        if ([sTraceSeen containsObject:message]) return;
        [sTraceSeen addObject:message];
    }
    [sLog logTag:@"ELEMENT" format:@"TRACE %@", message];
}

// ---- OITI's element class ---------------------------------------------------------------------
// A runtime subclass of Apple's SBSystemApertureProvidedContentElement. The newest item is an alert;
// older items become activities so SpringBoard can keep them in compact mode alongside the alert.
static Class OITINoticeElementClass(void) {
    static Class elementClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = NSClassFromString(@"SBSystemApertureProvidedContentElement");
        if (!base) return;
        elementClass = objc_getClass("OITINotificationElement");
        if (elementClass) return;
        Class created = objc_allocateClassPair(base, "OITINotificationElement", 0);
        if (!created) return;
        class_addMethod(created, NSSelectorFromString(@"hasAlertBehavior"),
                        imp_implementationWithBlock(^BOOL(id receiver) { return OITIIsAlertNoticeElement(receiver); }), "B16@0:8");
        class_addMethod(created, NSSelectorFromString(@"hasActivityBehavior"),
                        imp_implementationWithBlock(^BOOL(id receiver) {
                            return OITIIsOurElement(receiver) && !OITIIsAlertNoticeElement(receiver);
                        }), "B16@0:8");
        class_addMethod(created, NSSelectorFromString(@"hasIndicatorBehavior"),
                        imp_implementationWithBlock(^BOOL(id receiver) { return NO; }), "B16@0:8");
        class_addMethod(created, NSSelectorFromString(@"preferredAlertingDuration:"),
                        imp_implementationWithBlock(^double(id receiver, double suggested) {
                            // Apple ends an alert after this long without telling OITI. That suits a notice, which OITI
                            // removes after the same time, but a download lasts as long as the download does.
                            if (OITIItemForElement(receiver)[@"download"]) return kOITIDownloadAlertDuration;
                            return (double)sIslandNoticeDuration;
                        }),
                        "d24@0:8d16");
        objc_registerClassPair(created);
        elementClass = created;
    });
    return elementClass;
}

static NSString *OITIShortText(NSString *text, NSUInteger limit) {
    if (!text.length) return @"";
    NSString *flat = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return flat.length > limit ? [[flat substringToIndex:limit] stringByAppendingString:@"…"] : flat;
}

// Pulls what we need out of an NCNotificationRequest without a header: every access is looked up at run time.
static NSDictionary<NSString *, NSString *> *OITINoticeInfoFromRequest(id request) {
    id content = OITISafeObject(request, @"content");
    NSString *bundleID = OITISafeString(request, @"sectionIdentifier") ?: OITISafeString(request, @"bundleIdentifier") ?: @"";
    NSString *appName = OITISafeString(content, @"header") ?: @"";
    NSString *title = OITISafeString(content, @"title") ?: @"";
    NSString *subtitle = OITISafeString(content, @"subtitle") ?: @"";
    NSString *message = OITISafeString(content, @"message") ?: @"";
    return @{ @"bundleID": bundleID, @"appName": appName, @"title": title, @"subtitle": subtitle, @"message": message };
}

static UIImage *OITIRoundedIcon(UIImage *image, CGFloat side) {
    if (!image) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect bounds = CGRectMake(0, 0, side, side);
        [[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:side * 0.225] addClip];
        [image drawInRect:bounds];
    }];
}

// The two views of the compact element, like the lock element's leading and trailing views: the app icon on the left
// and a short label on the right. Both are sized (frame = what they need) because Apple asks them sizeThatFits.
@interface OITINoticeStackView : UIStackView
@end

@implementation OITINoticeStackView
- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat width = size.width > 0 ? MIN(size.width, 260.0) : 260.0;
    CGSize target = CGSizeMake(width, UILayoutFittingCompressedSize.height);
    CGSize fitted = [self systemLayoutSizeFittingSize:target
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return CGSizeMake(width, ceil(fitted.height));
}
@end

// ---- Download progress element views ----------------------------------------------------------
// Apple's system blue (#007AFF) for the bar, a tint of it for the track, system green when finished. The ends are
// round: the corner radius is always half the bar height.
static UIColor *OITIDownloadBlue(void) { return [UIColor colorWithRed:0.0 green:122.0 / 255.0 blue:1.0 alpha:1.0]; }
static UIColor *OITIDownloadRed(void) { return [UIColor colorWithRed:255.0 / 255.0 green:69.0 / 255.0 blue:58.0 / 255.0 alpha:1.0]; }
static UIColor *OITIDownloadGreen(void) { return [UIColor colorWithRed:52.0 / 255.0 green:199.0 / 255.0 blue:89.0 / 255.0 alpha:1.0]; }

@interface OITIProgressBarView : UIView
@property (nonatomic, readonly) double fraction;
@property (nonatomic, assign) CGFloat barHeight;   // default 6
- (void)setFraction:(double)fraction animated:(BOOL)animated;
- (void)setComplete:(BOOL)complete;
- (void)setCancelled:(BOOL)cancelled;   // red fill; call after setComplete:, which resets the colour
@end

@implementation OITIProgressBarView {
    UIView *_fill;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _barHeight = 6.0;
        self.backgroundColor = [OITIDownloadBlue() colorWithAlphaComponent:0.28];
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        _fill = [[UIView alloc] initWithFrame:CGRectZero];
        _fill.backgroundColor = OITIDownloadBlue();
        _fill.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_fill];
    }
    return self;
}
- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, _barHeight);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = self.bounds.size.height / 2.0;
    self.layer.cornerRadius = radius;
    _fill.layer.cornerRadius = radius;
    _fill.frame = CGRectMake(0, 0, self.bounds.size.width * _fraction, self.bounds.size.height);
}
- (void)setFraction:(double)fraction animated:(BOOL)animated {
    _fraction = isfinite(fraction) ? MAX(0.0, MIN(1.0, fraction)) : 0.0;
    CGRect target = CGRectMake(0, 0, self.bounds.size.width * _fraction, self.bounds.size.height);
    if (animated && self.window) {
        [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveLinear
                         animations:^{ self->_fill.frame = target; } completion:nil];
    } else {
        _fill.frame = target;
    }
}
- (void)setComplete:(BOOL)complete {
    _fill.backgroundColor = complete ? OITIDownloadGreen() : OITIDownloadBlue();
}
- (void)setCancelled:(BOOL)cancelled {
    if (cancelled) _fill.backgroundColor = OITIDownloadRed();
}
@end

// The minimal look, on the WIDE layout. The same body for every download:
//
//          App Name - File Name
//                212 MB
//   9.4 MB/s [████████░░░░░░] 26%
//                800 MB
//
// The bar is in the middle of the row with the speed on its left and the percentage on its right; the downloaded size is
// centered above the bar and the total size centered below it. Everything is laid out from the view's bounds, so it
// follows whatever width the Island gives it. The constants are the knobs for size and spacing.
static const CGFloat kOITIMinimalWidth = 260.0;          // width it asks for
static const CGFloat kOITIMinimalHeight = 56.0;          // height it asks for
static const CGFloat kOITIMinimalSpeedWidth = 62.0;      // speed, left of the bar
static const CGFloat kOITIMinimalPercentWidth = 36.0;    // percentage, right of the bar
static const CGFloat kOITIMinimalGap = 6.0;
static const CGFloat kOITIMinimalBarHeight = 7.0;

@interface OITIMinimalDownloadView : UIView
@property (nonatomic, readonly) OITIProgressBarView *bar;
- (void)setHeader:(NSString *)header downloaded:(NSString *)downloaded total:(NSString *)total speed:(NSString *)speed
          percent:(NSString *)percent fraction:(double)fraction complete:(BOOL)complete;
- (void)playCompletion;    // the text fades out, the bar becomes a green circle and a check is drawn in it
- (void)resetCompletion;   // back to the normal layout (a new download started)
@end

@implementation OITIMinimalDownloadView {
    UILabel *_header;
    UILabel *_top;
    UILabel *_bottom;
    UILabel *_speed;
    UILabel *_percent;
    CAShapeLayer *_check;
    BOOL _completionShown;
}
- (UILabel *)minimalLabelWithSize:(CGFloat)size weight:(UIFontWeight)weight alignment:(NSTextAlignment)alignment {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    label.textAlignment = alignment;
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.75;
    label.text = @" ";
    return label;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, kOITIMinimalWidth, kOITIMinimalHeight)])) {
        _bar = [[OITIProgressBarView alloc] initWithFrame:CGRectZero];
        _bar.barHeight = kOITIMinimalBarHeight;
        _header = [self minimalLabelWithSize:11 weight:UIFontWeightSemibold alignment:NSTextAlignmentCenter];
        _top = [self minimalLabelWithSize:10 weight:UIFontWeightMedium alignment:NSTextAlignmentCenter];
        _bottom = [self minimalLabelWithSize:10 weight:UIFontWeightMedium alignment:NSTextAlignmentCenter];
        _speed = [self minimalLabelWithSize:10 weight:UIFontWeightMedium alignment:NSTextAlignmentRight];
        _percent = [self minimalLabelWithSize:10 weight:UIFontWeightMedium alignment:NSTextAlignmentLeft];
        for (UIView *view in @[_header, _top, _bar, _bottom, _speed, _percent]) [self addSubview:view];
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(kOITIMinimalWidth, kOITIMinimalHeight); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(kOITIMinimalWidth, kOITIMinimalHeight); }
- (CGRect)completionCircleFrame {
    CGFloat diameter = 30.0;
    return CGRectMake((self.bounds.size.width - diameter) / 2.0, (self.bounds.size.height - diameter) / 2.0, diameter, diameter);
}
- (NSArray<UILabel *> *)allLabels {
    return @[_header, _top, _bottom, _speed, _percent];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (_completionShown) {   // the labels are faded out (and scaled, so their frames are left alone); only the circle needs placing
        _bar.frame = [self completionCircleFrame];
        return;
    }
    CGFloat width = self.bounds.size.width;
    CGFloat barX = kOITIMinimalSpeedWidth + kOITIMinimalGap;
    CGFloat barWidth = MAX(40.0, width - barX - kOITIMinimalGap - kOITIMinimalPercentWidth);
    CGFloat rowCenter = 36.0;   // the row with the bar: header 13, gap 2, downloaded 12, gap 2, row 14, gap 1, total 12
    _header.frame = CGRectMake(0, 0, width, 13);
    _top.frame = CGRectMake(barX, 15, barWidth, 12);
    _speed.frame = CGRectMake(0, rowCenter - 7, kOITIMinimalSpeedWidth, 14);
    _bar.frame = CGRectMake(barX, rowCenter - kOITIMinimalBarHeight / 2.0, barWidth, kOITIMinimalBarHeight);
    _percent.frame = CGRectMake(barX + barWidth + kOITIMinimalGap, rowCenter - 7, kOITIMinimalPercentWidth, 14);
    _bottom.frame = CGRectMake(barX, 44, barWidth, 12);
}
- (void)setHeader:(NSString *)header downloaded:(NSString *)downloaded total:(NSString *)total speed:(NSString *)speed
          percent:(NSString *)percent fraction:(double)fraction complete:(BOOL)complete {
    if (![_header.text isEqualToString:header]) _header.text = header;
    if (![_top.text isEqualToString:downloaded]) _top.text = downloaded;
    if (![_bottom.text isEqualToString:total]) _bottom.text = total;
    if (![_speed.text isEqualToString:speed]) _speed.text = speed;
    if (![_percent.text isEqualToString:percent]) _percent.text = percent;
    [_bar setComplete:complete];
    [_bar setFraction:fraction animated:YES];
}
// Completion: all the text fades and shrinks away while the bar contracts into a green circle, then a white check is drawn
// in the circle (a stroke animation). With Reduce Motion on, the end state appears at once.
- (void)playCompletion {
    if (_completionShown) return;
    _completionShown = YES;
    CGRect circle = [self completionCircleFrame];
    if (!_check) {
        _check = [CAShapeLayer layer];
        _check.fillColor = nil;
        _check.strokeColor = UIColor.whiteColor.CGColor;
        _check.lineWidth = 3.0;
        _check.lineCap = kCALineCapRound;
        _check.lineJoin = kCALineJoinRound;
        [self.layer addSublayer:_check];
    }
    CGFloat d = circle.size.width;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(CGRectGetMinX(circle) + d * 0.28, CGRectGetMinY(circle) + d * 0.52)];
    [path addLineToPoint:CGPointMake(CGRectGetMinX(circle) + d * 0.43, CGRectGetMinY(circle) + d * 0.67)];
    [path addLineToPoint:CGPointMake(CGRectGetMinX(circle) + d * 0.72, CGRectGetMinY(circle) + d * 0.35)];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _check.frame = self.bounds;
    _check.path = path.CGPath;
    _check.hidden = NO;
    _check.strokeEnd = reduceMotion ? 1.0 : 0.0;
    [CATransaction commit];
    [_bar.layer removeAllAnimations];
    for (UIView *subview in _bar.subviews) [subview.layer removeAllAnimations];
    if (reduceMotion) {
        for (UILabel *label in [self allLabels]) label.alpha = 0.0;
        _bar.frame = circle;
        [_bar setFraction:1.0 animated:NO];
        return;
    }
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        for (UILabel *label in [self allLabels]) {
            label.alpha = 0.0;
            label.transform = CGAffineTransformMakeScale(0.8, 0.8);
        }
    } completion:nil];
    [UIView animateWithDuration:0.45 delay:0.05 usingSpringWithDamping:0.78 initialSpringVelocity:0.0 options:0 animations:^{
        self->_bar.frame = circle;
    } completion:nil];
    [_bar setFraction:1.0 animated:YES];   // the bar's bounds are already the circle's, so the fill shrinks with it
    CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    draw.fromValue = @0.0;
    draw.toValue = @1.0;
    draw.duration = 0.32;
    draw.beginTime = [_check convertTime:CACurrentMediaTime() fromLayer:nil] + 0.32;
    draw.fillMode = kCAFillModeBackwards;
    draw.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _check.strokeEnd = 1.0;
    [CATransaction commit];
    [_check addAnimation:draw forKey:@"draw"];
}
- (void)resetCompletion {
    if (!_completionShown) return;
    _completionShown = NO;
    [_bar.layer removeAllAnimations];
    for (UIView *subview in _bar.subviews) [subview.layer removeAllAnimations];
    [_check removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _check.hidden = YES;
    _check.strokeEnd = 0.0;
    [CATransaction commit];
    for (UILabel *label in [self allLabels]) {
        label.alpha = 1.0;
        label.transform = CGAffineTransformIdentity;
    }
    [self setNeedsLayout];
}
@end

// The expanded body of the download element: the bar with one line of text under it.
static OITINoticeStackView *OITIBuildDownloadStack(OITIProgressBarView **barOut, UILabel **detailOut) {
    OITIProgressBarView *bar = [[OITIProgressBarView alloc] initWithFrame:CGRectZero];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *detail = [[UILabel alloc] init];
    detail.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    detail.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    detail.numberOfLines = 1;
    detail.lineBreakMode = NSLineBreakByTruncatingTail;
    detail.adjustsFontSizeToFitWidth = YES;
    detail.minimumScaleFactor = 0.8;
    detail.text = @" ";
    OITINoticeStackView *stack = [OITINoticeStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFill;
    stack.spacing = 7;
    [stack addArrangedSubview:bar];
    [stack addArrangedSubview:detail];
    CGSize size = [stack sizeThatFits:CGSizeMake(260, CGFLOAT_MAX)];
    stack.frame = CGRectMake(0, 0, size.width, size.height);
    *barOut = bar;
    *detailOut = detail;
    return stack;
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

static OITIStartupVideoView *OITIBuildStartupVideoView(void) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:kOITIStartupHelloVideoPath]) {
        [sLog logLevel:1 tag:@"HELLO" format:@"video asset missing at %@; retaining the placeholder card", kOITIStartupHelloVideoPath];
        return nil;
    }
    NSURL *url = [NSURL fileURLWithPath:kOITIStartupHelloVideoPath];
    OITIStartupVideoView *view = [[OITIStartupVideoView alloc] initWithURL:url];
    if (view) [sLog logLevel:1 tag:@"HELLO" format:@"created muted, single-play video view duration=%.2fs", (double)view.mediaDuration];
    return view;
}

static void OITIBuildNoticeViews(NSDictionary<NSString *, NSString *> *info, UIView **leadingOut, UIView **trailingOut,
                                 UIView **primaryOut, UIView **secondaryOut, UILabel **secondaryBodyOut) {
    NSString *bundleID = info[@"bundleID"] ?: @"";
    NSString *title = info[@"title"] ?: @"";
    NSString *subtitle = info[@"subtitle"] ?: @"";
    NSString *message = info[@"message"] ?: @"";
    NSString *appName = info[@"appName"] ?: @"";
    if (!appName.length && bundleID.length) appName = [bundleID componentsSeparatedByString:@"."].lastObject ?: @"";

    // Headline and body. No title: the app name becomes the headline, or the message itself if there is no app name either.
    NSString *headline = title.length ? title : (appName.length ? appName : message);
    NSString *body = message;
    if (subtitle.length) body = message.length ? [NSString stringWithFormat:@"%@: %@", subtitle, message] : subtitle;
    if (!title.length && !appName.length) body = @"";   // the message already is the headline

    UIImage *icon = nil;
    if (bundleID.length && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
    }
    UIImage *small = OITIRoundedIcon(icon, 22);
    UIView *leading;
    if (small) {
        UIImageView *iconView = [[UIImageView alloc] initWithImage:small];
        iconView.frame = CGRectMake(0, 0, 22, 22);
        leading = iconView;
    } else {
        UILabel *initial = [[UILabel alloc] init];
        initial.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        initial.textColor = [UIColor whiteColor];
        NSString *name = appName.length ? appName : headline;
        initial.text = name.length ? [name substringToIndex:1] : @"•";
        [initial sizeToFit];
        leading = initial;
    }

    UILabel *trailing = [[UILabel alloc] init];
    trailing.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    trailing.textColor = [UIColor whiteColor];
    trailing.text = OITIShortText(headline, 12);
    [trailing sizeToFit];

    // Expanded layouts (primary / secondary): the headline and the message, like Apple's own expanded alerts.
    UILabel *primary = [[UILabel alloc] init];
    primary.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    primary.textColor = [UIColor whiteColor];
    primary.lineBreakMode = NSLineBreakByTruncatingTail;
    primary.text = headline;
    CGSize primarySize = [primary sizeThatFits:CGSizeMake(260, CGFLOAT_MAX)];
    primary.frame = CGRectMake(0, 0, MIN(260, ceil(primarySize.width)), ceil(primarySize.height));

    NSInteger lines = MAX(1, MIN(4, lround([sOITIPreferences floatForKey:@"IslandNotificationsMessageLines" default:2])));
    UILabel *secondary = [[UILabel alloc] init];
    secondary.font = [UIFont systemFontOfSize:13];
    secondary.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    secondary.numberOfLines = lines;
    secondary.lineBreakMode = NSLineBreakByTruncatingTail;
    secondary.text = body;
    secondary.preferredMaxLayoutWidth = 260;
    OITINoticeStackView *secondaryStack = [OITINoticeStackView new];
    secondaryStack.axis = UILayoutConstraintAxisVertical;
    secondaryStack.alignment = UIStackViewAlignmentFill;
    secondaryStack.distribution = UIStackViewDistributionFill;
    secondaryStack.spacing = 8;
    [secondaryStack addArrangedSubview:secondary];
    CGSize secondarySize = [secondaryStack sizeThatFits:CGSizeMake(260, CGFLOAT_MAX)];
    secondaryStack.frame = CGRectMake(0, 0, secondarySize.width, secondarySize.height);

    *leadingOut = leading;
    *trailingOut = trailing;
    *primaryOut = primary;
    *secondaryOut = secondaryStack;
    if (secondaryBodyOut) *secondaryBodyOut = secondary;
}

static UIView *OITIBuildCompactNoticeCard(NSDictionary<NSString *, NSString *> *info) {
    NSString *bundleID = info[@"bundleID"] ?: @"";
    NSString *appName = info[@"appName"] ?: @"";
    if (!appName.length && bundleID.length) appName = [bundleID componentsSeparatedByString:@"."].lastObject ?: @"";
    NSString *title = info[@"title"] ?: @"";
    NSString *message = info[@"message"] ?: @"";
    NSString *labelText = title.length ? title : (message.length ? message : appName);
    if (appName.length && title.length) labelText = [NSString stringWithFormat:@"%@ · %@", appName, title];

    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 6;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:24].active = YES;

    UIImage *icon = nil;
    if (bundleID.length && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
    }
    UIImage *smallIcon = OITIRoundedIcon(icon, 16);
    if (smallIcon) {
        UIImageView *iconView = [[UIImageView alloc] initWithImage:smallIcon];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [iconView.widthAnchor constraintEqualToConstant:18].active = YES;
        [iconView.heightAnchor constraintEqualToConstant:18].active = YES;
        [row addArrangedSubview:iconView];
    }

    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.numberOfLines = 1;
    label.text = OITIShortText(labelText, 42);
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [row addArrangedSubview:label];
    UIView *card = [UIView new];
    card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.13];
    card.layer.cornerRadius = 10;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:5],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-5],
        [card.heightAnchor constraintEqualToConstant:34],
    ]];
    return card;
}

// Present older notices as visually distinct, spaced compact cards beneath the current expanded notice.
static void OITIRefreshNewestNoticeComposite(void) {
    NSDictionary *item = sIslandNoticeItems.lastObject;
    if (!item || OITINoticeStyle() == 0) return;
    OITINoticeStackView *stack = item[@"secondaryStack"];
    UIView *body = item[@"secondaryBody"];
    if (!stack || !body) return;

    for (UIView *view in [stack.arrangedSubviews copy]) {
        if (view == body) continue;
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSUInteger olderCount = sIslandNoticeItems.count > 0 ? sIslandNoticeItems.count - 1 : 0;
    for (NSUInteger i = 0; i < olderCount; i++) {
        NSDictionary *older = sIslandNoticeItems[i];
        NSDictionary *info = older[@"info"];
        if (info) [stack addArrangedSubview:OITIBuildCompactNoticeCard(info)];
    }

    CGSize size = [stack sizeThatFits:CGSizeMake(260, CGFLOAT_MAX)];
    stack.frame = CGRectMake(stack.frame.origin.x, stack.frame.origin.y, size.width, size.height);
    [stack invalidateIntrinsicContentSize];
    for (UIView *view = stack.superview; view; view = view.superview) [view setNeedsLayout];
    [stack.superview layoutIfNeeded];
    [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK separate-cards newest=%@ compactCards=%lu size=%.1fx%.1f",
     OITIKVCObject(item[@"element"], @"elementIdentifier"), (unsigned long)olderCount,
     (double)size.width, (double)size.height];
}

// ---- Corner radius adjustment (IslandNotificationsCornerExtra) -------------------------------
static NSMutableArray<NSDictionary *> *sCornerAdjusted;   // {view, original} for every layer we changed

static NSString *OITICornerChain(UIView *view) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *up = view.superview;
    for (int i = 0; up && i < 9; i++, up = up.superview) {
        [parts addObject:[NSString stringWithFormat:@"%@(r=%.1f mask=%d curve=%@ size=%@)", NSStringFromClass([up class]),
                          up.layer.cornerRadius, up.layer.masksToBounds, up.layer.cornerCurve,
                          NSStringFromCGSize(up.bounds.size)]];
    }
    return [parts componentsJoinedByString:@" < "];
}

// Adds `extra` points to the corner radius of every rounded ancestor. The first time a layer is touched its original
// radius is remembered, so applying twice does not compound and OITIRestoreCorners puts everything back.
static void OITIApplyCornerExtra(UIView *view, CGFloat extra) {
    if (extra == 0 || !view) return;
    if (!sCornerAdjusted) sCornerAdjusted = [NSMutableArray array];
    for (UIView *up = view.superview; up; up = up.superview) {
        if (up.layer.cornerRadius <= 0.5) continue;
        NSDictionary *existing = nil;
        for (NSDictionary *entry in sCornerAdjusted) {
            if (entry[@"view"] == up) { existing = entry; break; }
        }
        if (!existing) {
            existing = @{ @"view": up, @"original": @(up.layer.cornerRadius) };
            [sCornerAdjusted addObject:existing];
        }
        up.layer.cornerRadius = [existing[@"original"] doubleValue] + extra;
    }
}

static void OITIRestoreCorners(void) {
    for (NSDictionary *entry in sCornerAdjusted) {
        UIView *view = entry[@"view"];
        view.layer.cornerRadius = [entry[@"original"] doubleValue];
    }
    [sCornerAdjusted removeAllObjects];
}

// Where a view ended up: class, frames, visibility, window and the first superviews. For the ELEMENT VIEWS line.
static NSString *OITIViewDiag(UIView *view) {
    if (!view) return @"nil";
    NSMutableArray<NSString *> *chain = [NSMutableArray array];
    UIView *up = view.superview;
    for (int i = 0; up && i < 4; i++, up = up.superview) [chain addObject:NSStringFromClass([up class])];
    CGRect inWindow = view.window ? [view convertRect:view.bounds toView:nil] : CGRectZero;
    return [NSString stringWithFormat:@"%@ frame=%@ inWindow=%@ hidden=%d alpha=%.2f window=%@ chain=%@",
            NSStringFromClass([view class]), NSStringFromCGRect(view.frame), NSStringFromCGRect(inWindow), view.hidden, view.alpha,
            view.window ? NSStringFromClass([view.window class]) : @"nil", [chain componentsJoinedByString:@" < "]];
}

// ---- Stock banner fade (optional, islandNotificationsHideBanner) ----------------------------

static NSArray<UIWindow *> *OITIBannerWindowsNow(void) {
    NSMutableArray<UIWindow *> *result = [NSMutableArray array];
    for (UIView *view in sBannerWindows.allObjects) {
        if ([view isKindOfClass:[UIWindow class]]) [result addObject:(UIWindow *)view];
    }
    if (!result.count && [UIWindow respondsToSelector:@selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:)]) {
        Class bannerClass = NSClassFromString(@"SBBannerWindow");
        for (UIWindow *window in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
            if (bannerClass && [window isKindOfClass:bannerClass]) [result addObject:window];
        }
    }
    return result;
}

static void OITIHideBannerWindows(void) {
    for (UIWindow *window in OITIBannerWindowsNow()) {
        if (!objc_getAssociatedObject(window, kOITIBannerOriginalAlphaKey)) {
            objc_setAssociatedObject(window, kOITIBannerOriginalAlphaKey, @(window.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (window.alpha != 0) window.alpha = 0;
    }
}

static void OITIRestoreBannerWindows(void) {
    for (UIWindow *window in OITIBannerWindowsNow()) {
        NSNumber *original = objc_getAssociatedObject(window, kOITIBannerOriginalAlphaKey);
        if (!original) continue;
        CGFloat value = original.doubleValue;
        window.alpha = value > 0.01 ? value : 1.0;
        objc_setAssociatedObject(window, kOITIBannerOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Keeps the banner window faded until Apple says no banner is presented any more (or a hard cap passes), then puts
// it back exactly as it was. Without a usable presentedBanner getter it simply waits a fixed time.
static void OITIPollBannerHide(void) {
    if (!sBannerHideActive) return;
    CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - sBannerHideStart;
    id presented = sBannerHideCanProbe ? OITISafeObject(sBannerHideDestination, @"presentedBanner") : nil;
    if (presented) sBannerHideSawBanner = YES;

    BOOL done;
    if (sBannerHideCanProbe) {
        done = (sBannerHideSawBanner && !presented && elapsed > 1.0) || (!sBannerHideSawBanner && elapsed > 4.0) || elapsed > 12.0;
    } else {
        done = elapsed > 7.0;
    }
    if (done) {
        OITIRestoreBannerWindows();
        sBannerHideActive = NO;
        [sLog logLevel:1 tag:@"NOTIF" format:@"stock banner window restored after %.1fs (sawBanner=%d probe=%d)",
         elapsed, sBannerHideSawBanner, sBannerHideCanProbe];
        return;
    }
    OITIHideBannerWindows();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OITIPollBannerHide();
    });
}

static void OITIBeginBannerHide(id destination) {
    sBannerHideDestination = destination;
    sBannerHideCanProbe = [destination respondsToSelector:NSSelectorFromString(@"presentedBanner")];
    sBannerHideStart = CFAbsoluteTimeGetCurrent();
    sBannerHideSawBanner = NO;
    OITIHideBannerWindows();
    if (!sBannerHideActive) {
        sBannerHideActive = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            OITIPollBannerHide();
        });
    }
}

// ---- The element ----------------------------------------------------------------------------

// Logs the method list of an object's class once per class (level 1 only; this is research output).
static void OITIProbeObject(id object, NSString *role) {
    if (!object || ![sLog isLoggingAtLevel:1]) return;
    static NSMutableSet<NSString *> *probed;
    if (!probed) probed = [NSMutableSet set];
    NSString *className = NSStringFromClass([object class]);
    if ([probed containsObject:className]) return;
    [probed addObject:className];
    [sLog logTag:@"ELEMENT" format:@"PROBE %@ = %@", role, className];
    OITIDumpMethods([object class], @"-");
    OITIDumpMethods(object_getClass([object class]), @"+");
}

// ---- Tap / swipe on the element ----------------------------------------------------------------
static void OITIOpenApp(NSString *bundleID) {
    if (!bundleID.length) return;
    UIApplication *application = [UIApplication sharedApplication];
    SEL launch = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([application respondsToSelector:launch]) {
        BOOL ok = ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(application, launch, bundleID, NO);
        [sLog logLevel:1 tag:@"ELEMENT" format:@"open app %@ via launchApplicationWithIdentifier: -> %d", bundleID, ok];
        return;
    }
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspace = NSSelectorFromString(@"defaultWorkspace");
    SEL open = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (workspaceClass && [workspaceClass respondsToSelector:defaultWorkspace]) {
        id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultWorkspace);
        if ([workspace respondsToSelector:open]) {
            BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, open, bundleID);
            [sLog logLevel:1 tag:@"ELEMENT" format:@"open app %@ via LSApplicationWorkspace -> %d", bundleID, ok];
            return;
        }
    }
    [sLog logTag:@"ELEMENT" format:@"could not open %@: no launch API found", bundleID];
}

// ---- Tap action ----------------------------------------------------------------------------------
// A tap on the notification element does what tapping the stock banner does (see OITIExecuteStockBannerTap). If that banner is
// gone (for example the element outlived it), the tap uses the notification's default action URL when it has one, and otherwise
// launches the app.
static NSURL *OITIDefaultActionURL(id request) {
    id action = OITIKVCObject(request, @"defaultAction");
    for (NSString *key in @[@"url", @"launchURL", @"targetURL"]) {
        id value = OITIKVCObject(action, key);
        if ([value isKindOfClass:[NSURL class]]) return value;
    }
    return nil;
}

static BOOL OITIOpenURL(NSURL *url) {
    UIApplication *application = [UIApplication sharedApplication];
    SEL open = NSSelectorFromString(@"openURL:options:completionHandler:");
    if (![application respondsToSelector:open]) return NO;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(application, open, url, @{}, nil);
    [sLog logLevel:1 tag:@"ELEMENT" format:@"open url %@ via openURL:options:completionHandler:", url];
    return YES;
}

// The stock banner is still alive (only faded) while OITI's element shows, so a tap can run exactly what a tap on it runs:
// NCNotificationViewController -_executeDefaultAction: (found with a class dump on 16.7.16; the banner's view controllers are
// BNContentViewController > SBNotificationPresentableViewController > NCNotificationShortLookViewController). Apple's own code
// then opens the right conversation, dismisses the banner and clears the notification.
static void OITICollectNotificationViewControllers(UIViewController *controller, Class base, int depth,
                                                   NSMutableArray<UIViewController *> *found) {
    if (!controller || depth > 8 || found.count > 8) return;
    if (base && [controller isKindOfClass:base]) [found addObject:controller];
    for (UIViewController *child in controller.childViewControllers) OITICollectNotificationViewControllers(child, base, depth + 1, found);
    if (controller.presentedViewController) OITICollectNotificationViewControllers(controller.presentedViewController, base, depth + 1, found);
}

static BOOL OITIExecuteStockBannerTap(id request) {
    Class base = NSClassFromString(@"NCNotificationViewController");
    SEL execute = NSSelectorFromString(@"_executeDefaultAction:");
    if (!base) return NO;
    NSMutableArray<UIViewController *> *found = [NSMutableArray array];
    for (UIWindow *window in OITIBannerWindowsNow()) OITICollectNotificationViewControllers(window.rootViewController, base, 0, found);
    UIViewController *target = nil;
    for (UIViewController *controller in found) {
        id candidate = OITIKVCObject(controller, @"notificationRequest");
        if (request && candidate && (candidate == request || [candidate isEqual:request])) { target = controller; break; }
    }
    // With a stack, another notification's banner may be the only one left on screen. Never route an
    // older item's tap to that unrelated banner; only use the sole-banner fallback when no request exists.
    if (!target && !request && found.count == 1) target = found.firstObject;
    if (!target || ![target respondsToSelector:execute]) {
        [sLog logLevel:1 tag:@"ELEMENT" format:@"tap: no matching stock banner (found %lu), using the fallback", (unsigned long)found.count];
        return NO;
    }
    ((void (*)(id, SEL, BOOL))objc_msgSend)(target, execute, YES);
    [sLog logLevel:1 tag:@"ELEMENT" format:@"tap ran -_executeDefaultAction: on %@", NSStringFromClass([target class])];
    return YES;
}

// A tap recognizer that logs where touches land (TOUCH lines), so a tap that never reaches us is visible in the log.
@interface OITINoticeTapRecognizer : UITapGestureRecognizer
@property (nonatomic, copy) NSString *label;
@end

@implementation OITINoticeTapRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    [sLog logLevel:1 tag:@"ELEMENT" format:@"TOUCH began (%@) hit=%@ at %@", self.label, NSStringFromClass([touch.view class]),
     NSStringFromCGPoint([touch locationInView:nil])];
    [super touchesBegan:touches withEvent:event];
}
@end

@interface OITINoticeActions : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) id request;
@property (nonatomic, weak) UIView *host;
@property (nonatomic, assign) BOOL handled;
@property (nonatomic, copy) void (^dismiss)(void);
- (void)handleTap:(UIGestureRecognizer *)recognizer;
- (void)handleSwipe:(UIGestureRecognizer *)recognizer;
@end

@implementation OITINoticeActions
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
// The window-level recognizers only take touches that start inside the notification element.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if (![recognizer.view isKindOfClass:[UIWindow class]]) return YES;
    UIView *host = self.host;
    return host && CGRectContainsPoint(host.bounds, [touch locationInView:host]);
}
- (void)handleTap:(UIGestureRecognizer *)recognizer {
    if (self.handled) return;
    self.handled = YES;
    NSURL *url = OITIDefaultActionURL(self.request);
    [sLog logLevel:1 tag:@"ELEMENT" format:@"TAP on the notification element (%@) seen by %@ url=%@", self.bundleID,
     NSStringFromClass([recognizer.view class]), url];
    if (!OITIExecuteStockBannerTap(self.request)) {   // fallbacks: the default action's URL, then just the app
        if (!(url && OITIOpenURL(url))) OITIOpenApp(self.bundleID);
    }
    // Opening a notification does not remove it from the stack; it remains until timeout or swipe dismissal.
    __weak OITINoticeActions *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        weakSelf.handled = NO;   // window and element recognizers share one tap, but later taps should still work
    });
}
- (void)handleSwipe:(UIGestureRecognizer *)recognizer {
    if (self.handled) return;
    self.handled = YES;
    [sLog logLevel:1 tag:@"ELEMENT" format:@"SWIPE up on the notification element seen by %@", NSStringFromClass([recognizer.view class])];
    if (self.dismiss) self.dismiss();
}
@end

// Tries the invalidation selectors Apple's assertion-like objects usually have. Logs what it found.
static void OITIDismissNoticeItem(NSDictionary *item) {
    if (sIslandNoticeItems.count <= 1) OITIRestoreCorners();
    for (UIGestureRecognizer *recognizer in item[@"recognizers"]) [recognizer.view removeGestureRecognizer:recognizer];
    if ([item isKindOfClass:[NSMutableDictionary class]]) {   // break the item -> actions -> dismiss block -> item cycle
        NSMutableDictionary *mutableItem = (NSMutableDictionary *)item;
        [mutableItem removeObjectForKey:@"actions"];
        [mutableItem removeObjectForKey:@"recognizers"];
    }
    id registration = item[@"registration"];
    id manager = item[@"manager"];
    id element = item[@"element"];
    BOOL done = NO;
    SEL realInvalidate = NSSelectorFromString(@"invalidateWithReason:layoutModeChangeReason:");
    if (registration && [registration respondsToSelector:realInvalidate]) {
        @try {
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(registration, realInvalidate, @"OITI", 0);
            done = YES;
            [sLog logLevel:1 tag:@"ELEMENT" format:@"dismissed element via invalidateWithReason:layoutModeChangeReason:"];
        } @catch (NSException *exception) {
            [sLog logTag:@"ELEMENT" format:@"dismiss via invalidateWithReason:layoutModeChangeReason: threw %@", exception.name];
        }
    }
    for (NSString *name in done ? @[] : @[@"invalidate", @"invalidateWithReason:"]) {
        SEL selector = NSSelectorFromString(name);
        if (registration && [registration respondsToSelector:selector]) {
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                if ([name hasSuffix:@":"]) [registration performSelector:selector withObject:@"OITI"];
                else [registration performSelector:selector];
#pragma clang diagnostic pop
                done = YES;
            } @catch (NSException *exception) {
                [sLog logTag:@"ELEMENT" format:@"dismiss via %@ threw %@", name, exception.name];
            }
            if (done) {
                [sLog logLevel:1 tag:@"ELEMENT" format:@"dismissed element via registration %@", name];
                break;
            }
        }
    }
    if (!done && manager && element) {
        for (NSString *name in @[@"unregisterElement:", @"removeElement:", @"invalidateElement:"]) {
            SEL selector = NSSelectorFromString(name);
            if (![manager respondsToSelector:selector]) continue;
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [manager performSelector:selector withObject:element];
#pragma clang diagnostic pop
                done = YES;
            } @catch (NSException *exception) {
                [sLog logTag:@"ELEMENT" format:@"dismiss via manager %@ threw %@", name, exception.name];
            }
            if (done) {
                [sLog logLevel:1 tag:@"ELEMENT" format:@"dismissed element via manager %@", name];
                break;
            }
        }
    }
    if (!done) {
        [sLog logTag:@"ELEMENT" format:@"could not dismiss the element: registration %@ has no invalidate selector. See PROBE lines.",
         OITIObjectSummary(registration)];
    }
}

// Creates one element from `info`, registers it and schedules its removal. Main thread only.
static BOOL OITIPresentNoticeElement(NSDictionary<NSString *, NSString *> *info, NSString *reason) {
    @synchronized ([NSNull null]) { [sTraceSeen removeAllObjects]; }
    if (OITIElementRecoveryActive(reason)) return NO;
    if (sPoCDisabledAfterFailure) {
        [sLog logTag:@"ELEMENT" format:@"element creation is off until the next respring (the promotion guard caught %d exceptions)", sPoCFailureCount];
        return NO;
    }
    id manager = sRegisteringManager ?: sSeenManager;
    NSInteger registrarVariant = (NSInteger)[sOITIPreferences floatForKey:@"IslandNotificationsPoCRegistrar" default:0];
    id registrar = (registrarVariant == 0 && sSystemApertureController) ? sSystemApertureController : manager;
    if (!registrar) {
        [sLog logTag:@"ELEMENT" format:@"no SAUISystemApertureManager seen yet (%@): lock/unlock once or open the Island, then retry", reason];
        return NO;
    }
    Class elementClass = OITINoticeElementClass();
    Class providerClass = NSClassFromString(@"SBUISystemApertureCustomContentProvider");
    if (!elementClass || !providerClass) {
        [sLog logTag:@"ELEMENT" format:@"missing class: element=%d provider=%d", elementClass != nil, providerClass != nil];
        return NO;
    }
    if (![registrar respondsToSelector:@selector(registerElement:)]) {
        [sLog logTag:@"ELEMENT" format:@"registrar %@ does not respond to registerElement:", OITIObjectSummary(registrar)];
        return NO;
    }

    if (!sIslandNoticeItems) sIslandNoticeItems = [NSMutableArray array];
    BOOL startupHello = [reason isEqualToString:@"startup-hello"];
    BOOL downloadProgress = [reason isEqualToString:@"download-progress"];
    NSInteger style = (startupHello || downloadProgress) ? 2 : OITINoticeStyle();
    if (!sIslandNotificationStackEnabled && sIslandNoticeItems.count) {
        NSArray<NSDictionary *> *previousItems = [sIslandNoticeItems copy];
        for (NSDictionary *previous in previousItems) OITIRemoveNoticeItem(previous, @"stack-disabled-replaced");
        [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK disabled; replacing prior items with newest notification"];
    }
    if (sIslandNoticeItems.count && style != 0) {
        // The previous alert now enters the compact stack; its visible time starts again here.
        OITIScheduleNoticeTimeout((NSMutableDictionary *)sIslandNoticeItems.lastObject);
    }
    for (NSDictionary *existing in sIslandNoticeItems) OITISetNoticeLayout(existing, style, NO);

    NSMutableDictionary *item = nil;
    @try {
        Class containerClass = NSClassFromString(@"SBUISystemApertureContentProvider");
        if (!containerClass) {
            [sLog logTag:@"ELEMENT" format:@"missing class SBUISystemApertureContentProvider"];
            if (sIslandNoticeItems.count && style != 0) OITISetNoticeLayout(sIslandNoticeItems.lastObject, style, YES);
            return NO;
        }
        UIView *leadingView = nil, *trailingView = nil, *primaryView = nil, *secondaryView = nil;
        UILabel *secondaryBody = nil;
        OITIBuildNoticeViews(info, &leadingView, &trailingView, &primaryView, &secondaryView, &secondaryBody);
        OITIProgressBarView *downloadBar = nil;
        UILabel *downloadDetail = nil;
        if (downloadProgress) {
            // The Detailed look: the same icon and headline as a notice; the body is the bar and its text line.
            // (The Minimal look is not an Apple element at all, see the download pill.)
            secondaryView = OITIBuildDownloadStack(&downloadBar, &downloadDetail);
            secondaryBody = nil;
            CGRect headlineFrame = primaryView.frame;
            headlineFrame.size.width = 260;   // the headline text changes (name, "2 downloads"), so keep the width fixed
            primaryView.frame = headlineFrame;
        }
        OITIStartupVideoView *startupVideoView = startupHello ? OITIBuildStartupVideoView() : nil;
        if (startupVideoView) {
            // The normal notification chrome puts an app icon on the left and a short title on
            // the trailing side. A startup animation is the entire card, so leave those slots
            // empty and let the video occupy the expanded content area by itself.
            leadingView = [[UIView alloc] initWithFrame:CGRectZero];
            trailingView = [[UIView alloc] initWithFrame:CGRectZero];
            primaryView = startupVideoView;
            secondaryView = [[UIView alloc] initWithFrame:CGRectZero];
            secondaryBody = nil;
        }
        id leadingProvider = [[providerClass alloc] initWithView:leadingView];
        id trailingProvider = [[providerClass alloc] initWithView:trailingView];
        id primaryProvider = [[providerClass alloc] initWithView:primaryView];
        id secondaryProvider = [[providerClass alloc] initWithView:secondaryView];
        id provider = [[containerClass alloc] init];   // the container real elements use
        [(SBUISystemApertureContentProvider *)provider setLeadingContentViewProvider:leadingProvider];
        [(SBUISystemApertureContentProvider *)provider setTrailingContentViewProvider:trailingProvider];
        [(SBUISystemApertureContentProvider *)provider setPrimaryContentViewProvider:primaryProvider];
        [(SBUISystemApertureContentProvider *)provider setSecondaryContentViewProvider:secondaryProvider];
        NSString *identifier = [NSString stringWithFormat:@"com.wilburt.oiti.notification.%@", [NSUUID UUID].UUIDString];
        OITIElementIdentifierStub *identifierObject = [OITIElementIdentifierStub new];
        identifierObject.value = identifier;
        id element = [[elementClass alloc] initWithIdentifier:identifierObject contentProvider:provider];
        if (!provider || !element) {
            [sLog logTag:@"ELEMENT" format:@"creation failed: provider=%@ element=%@", OITIObjectSummary(provider), OITIObjectSummary(element)];
            if (sIslandNoticeItems.count && style != 0) OITISetNoticeLayout(sIslandNoticeItems.lastObject, style, YES);
            return NO;
        }
        OITIProbeObject(provider, @"provider");
        OITIProbeObject(leadingProvider, @"leadingProvider");
        OITIProbeObject(element, @"element");

        [sLog logTag:@"ELEMENT" format:@"our element before layout values: %@", OITIElementValuesSummary(element)];
        [sLog logTag:@"ELEMENT" format:@"our element parts: %@", OITIElementPartsSummary(element)];
        item = [NSMutableDictionary dictionary];
        item[@"leadingView"] = leadingView; item[@"trailingView"] = trailingView; item[@"leadingProvider"] = leadingProvider;
        item[@"primaryView"] = primaryView; item[@"secondaryView"] = secondaryView;
        item[@"secondaryStack"] = secondaryView; item[@"secondaryBody"] = secondaryBody; item[@"info"] = [info copy];
        item[@"primaryProvider"] = primaryProvider; item[@"secondaryProvider"] = secondaryProvider;
        item[@"trailingProvider"] = trailingProvider; item[@"provider"] = provider; item[@"element"] = element; item[@"manager"] = registrar;
        if (sPendingNoticeRequest) item[@"request"] = sPendingNoticeRequest;
        if (startupHello) {
            item[@"startupHello"] = @YES;
            if (startupVideoView) {
                item[@"startupVideoView"] = startupVideoView;
                NSTimeInterval duration = startupVideoView.mediaDuration;
                item[@"timeoutDuration"] = @(duration > 0 ? MIN(duration + 2.0, 120.0) : 60.0);
            } else {
                item[@"timeoutDuration"] = @(kOITIStartupHelloPrototypeDuration);
            }
        }
        if (downloadProgress) {
            item[@"download"] = @YES;
            item[@"downloadBar"] = downloadBar;
            if (downloadDetail) item[@"downloadDetail"] = downloadDetail;
            item[@"timeoutDuration"] = @(365.0 * 24.0 * 3600.0);   // the download decides when this ends, not the notice timer
            sDownloadItem = item;
            sDownloadShownAt = CFAbsoluteTimeGetCurrent();
        }
        OITISetNoticeLayout(item, style, YES);
        NSUInteger stackLimit = sIslandNotificationStackEnabled ? kOITINoticeStackLimit : 1;
        while (sIslandNoticeItems.count >= stackLimit) {
            NSDictionary *oldest = sIslandNoticeItems.firstObject;
            [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK full (%lu); evicting oldest %@",
             (unsigned long)kOITINoticeStackLimit, OITIKVCObject(oldest[@"element"], @"elementIdentifier")];
            OITIRemoveNoticeItem(oldest, @"capacity");
        }
        [sIslandNoticeItems addObject:item];   // added BEFORE registering so the promotion guard knows an OITI element is live
        if (sIslandNoticeItems.count == 1) OITIWriteElementBreadcrumb(reason);   // also before registering: registration is the risky call
        if (startupHello) sStartupHelloItem = item;
        OITIScheduleNoticeTimeout(item);
        OITIRefreshNewestNoticeComposite();

        sPoCOurRegistrationInFlight = YES;
        id registration = [(SAUISystemApertureManager *)registrar registerElement:element];
        sPoCOurRegistrationInFlight = NO;
        if (registration) item[@"registration"] = registration;
        OITIProbeObject(registration, @"registration");
        [sLog logTag:@"ELEMENT" format:@"registered %@ (%@) registrar=%@ registration=%@ duration=%.1fs", identifier, reason,
         OITIObjectSummary(registrar), OITIObjectSummary(registration), (double)sIslandNoticeDuration];

        if (startupVideoView) {
            __weak NSMutableDictionary *weakItem = item;
            NSMutableArray *observers = [NSMutableArray array];
            for (NSString *notificationName in @[AVPlayerItemDidPlayToEndTimeNotification,
                                                  AVPlayerItemFailedToPlayToEndTimeNotification]) {
                id observer = [[NSNotificationCenter defaultCenter]
                    addObserverForName:notificationName
                    object:startupVideoView.player.currentItem
                    queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *notification) {
                        NSMutableDictionary *strongItem = weakItem;
                        if (!strongItem || ![sIslandNoticeItems containsObject:strongItem]) return;
                        BOOL failed = [notification.name isEqualToString:AVPlayerItemFailedToPlayToEndTimeNotification];
                        [sLog logLevel:1 tag:@"HELLO" format:@"video %@; removing startup element %@",
                         failed ? @"playback failed" : @"reached end", failed ? notification.userInfo : @""];
                        OITIRemoveNoticeItem(strongItem, failed ? @"video-failed" : @"video-finished");
                    }];
                if (observer) [observers addObject:observer];
            }
            item[@"playbackObservers"] = observers;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (![sIslandNoticeItems containsObject:item]) return;
                [startupVideoView startPlayback];
                [sLog logLevel:1 tag:@"HELLO" format:@"video playback started"];
            });
        }

        if ([sLog isLoggingAtLevel:1]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (![sIslandNoticeItems containsObject:item]) return;
                [sLog logTag:@"ELEMENT" format:@"VIEWS element: %@", OITIElementValuesSummary(element)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS parts:   %@", OITIElementPartsSummary(element)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS leading:   %@", OITIViewDiag(leadingView)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS trailing:  %@", OITIViewDiag(trailingView)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS primary:   %@", OITIViewDiag(primaryView)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS secondary: %@", OITIViewDiag(secondaryView)];
                [sLog logTag:@"ELEMENT" format:@"CORNERS leading chain: %@", OITICornerChain(leadingView)];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                OITIRunDump(@"poc-element");
            });
        }
        NSString *noticeBundleID = info[@"bundleID"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (![sIslandNoticeItems containsObject:item]) return;
            UIView *host = nil;
            for (UIView *up = leadingView.superview; up; up = up.superview) {
                if ([NSStringFromClass([up class]) isEqualToString:@"SAUIElementView"]) { host = up; break; }
            }
            if (!host) host = leadingView.superview;
            if (!host) {
                [sLog logTag:@"ELEMENT" format:@"GESTURES: no host view found, tap and swipe unavailable"];
                return;
            }
            OITINoticeActions *actions = [OITINoticeActions new];
            actions.bundleID = noticeBundleID;
            actions.request = item[@"request"];
            actions.host = host;
            actions.dismiss = ^{
                OITIRemoveNoticeItem(item, @"swipe");
            };
            // Recognizers on the element view and on the Island window (the window ones only take touches that start inside the
            // element): some touches may be taken before they reach the element view, and the TOUCH lines show which route works.
            NSMutableArray<UIGestureRecognizer *> *recognizers = [NSMutableArray array];
            NSArray<UIView *> *targets = host.window ? @[host, host.window] : @[host];
            for (UIView *target in targets) {
                OITINoticeTapRecognizer *tap = [[OITINoticeTapRecognizer alloc] initWithTarget:actions action:@selector(handleTap:)];
                tap.label = [target isKindOfClass:[UIWindow class]] ? @"window" : @"element";
                tap.cancelsTouchesInView = NO;
                tap.delegate = actions;
                UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:actions action:@selector(handleSwipe:)];
                swipe.direction = UISwipeGestureRecognizerDirectionUp;
                swipe.cancelsTouchesInView = NO;
                swipe.delegate = actions;
                [target addGestureRecognizer:tap];
                [target addGestureRecognizer:swipe];
                [recognizers addObject:tap];
                [recognizers addObject:swipe];
            }
            item[@"actions"] = actions; item[@"recognizers"] = recognizers;
            [sLog logLevel:1 tag:@"ELEMENT" format:@"GESTURES attached to %@ and %@ (frame %@, interaction %d)", NSStringFromClass([host class]),
             host.window ? NSStringFromClass([host.window class]) : @"no window", NSStringFromCGRect(host.frame), host.userInteractionEnabled];
        });

        CGFloat cornerExtra = [sOITIPreferences floatForKey:@"IslandNotificationsCornerExtra" default:0];
        if (isfinite(cornerExtra) && cornerExtra != 0) {
            cornerExtra = MAX(-20.0, MIN(20.0, cornerExtra));
            for (NSNumber *delay in @[@0.7, @1.3]) {   // after Apple's expansion animation, and once more in case it re-lays out
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (![sIslandNoticeItems containsObject:item]) return;
                    OITIApplyCornerExtra(leadingView, cornerExtra);
                    [sLog logLevel:1 tag:@"ELEMENT" format:@"CORNERS applied %+.1f: %@", (double)cornerExtra, OITICornerChain(leadingView)];
                });
            }
        }
        return YES;
    } @catch (NSException *exception) {
        sPoCOurRegistrationInFlight = NO;
        [sLog logTag:@"ELEMENT" format:@"exception while creating/registering the element: %@ %@", exception.name, exception.reason];
        if ([sIslandNoticeItems containsObject:item]) OITIRemoveNoticeItem(item, @"registration-error");
        else if (sIslandNoticeItems.count && style != 0) OITISetNoticeLayout(sIslandNoticeItems.lastObject, style, YES);
        return NO;
    }
}

// =============================================================================================
// MARK: Download progress (the tracker, the Minimal pill and the Detailed element; the App Store source is below)
// =============================================================================================
// A small tracker that takes bytes from any source and drives one Island element. Everything here runs on the main
// thread. Sources call OITIDownloadUpdate while a download runs and OITIDownloadFinish when it ends.

static NSMutableDictionary<NSString *, NSMutableDictionary *> *sDownloads;   // id -> title, bundleID, downloaded, total, speed, lastBytes, lastTime
static NSTimer *sDownloadTimer;
static BOOL sDownloadCollapsed = NO;            // dismissed or limit reached: stays away until a new download starts
static CFAbsoluteTime sDownloadNextPresentAttempt = 0;
static NSUInteger sDownloadCompleteGeneration = 0;

static NSString *OITIDownloadBytesText(double bytes) {
    return [NSByteCountFormatter stringFromByteCount:(long long)MAX(0.0, bytes) countStyle:NSByteCountFormatterCountStyleFile];
}

// Totals over every tracked download, or nil when none is running. A download is either byte-based (OITIDownloadUpdate) or
// fraction-only (OITIDownloadUpdateFraction, for sources such as the App Store that only know a percentage). When any
// download is fraction-only the snapshot is in fraction mode: `fraction` is the mean over all downloads, sizes and speed
// are not shown, and `eta` is the longest estimate (-1 unless every download is fraction-only and moving).
static NSDictionary *OITIDownloadSnapshot(void) {
    if (!sDownloads.count) return nil;
    double downloaded = 0, total = 0, speed = 0, fractionSum = 0, etaMax = 0;
    BOOL totalKnown = YES, anyFraction = NO, allFraction = YES, allPaused = YES, etaKnown = YES;
    NSString *title = nil, *bundleID = nil, *appName = nil;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (NSDictionary *download in sDownloads.allValues) {
        double itemDownloaded = [download[@"downloaded"] doubleValue];
        double size = [download[@"total"] doubleValue];
        downloaded += itemDownloaded;
        if (size > 0) total += size; else totalKnown = NO;
        speed += [download[@"speed"] doubleValue];
        if ([download[@"fractionOnly"] boolValue]) {
            anyFraction = YES;
            double fraction = [download[@"fraction"] doubleValue];
            fractionSum += fraction;
            double rate = [download[@"fractionRate"] doubleValue];
            BOOL stalled = now - [download[@"fractionChangeTime"] doubleValue] > 20.0;
            if (rate > 0 && fraction < 1.0 && !stalled && ![download[@"paused"] boolValue]) {
                etaMax = MAX(etaMax, (1.0 - fraction) / rate);
            } else {
                etaKnown = NO;
            }
        } else {
            allFraction = NO;
            etaKnown = NO;
            fractionSum += size > 0 ? MIN(1.0, itemDownloaded / size) : 0.0;
        }
        if (![download[@"paused"] boolValue]) allPaused = NO;
        if (!title) { title = download[@"title"]; bundleID = download[@"bundleID"]; appName = download[@"appName"]; }
    }
    return @{ @"count": @(sDownloads.count), @"downloaded": @(downloaded), @"total": @(totalKnown ? total : 0.0),
              @"speed": @(speed), @"title": title ?: @"Download", @"appName": appName ?: @"", @"bundleID": bundleID ?: @"",
              @"fractionMode": @(anyFraction), @"fraction": @(fractionSum / (double)sDownloads.count), @"paused": @(allPaused),
              @"eta": @(allFraction && etaKnown ? etaMax : -1.0) };
}

// "~45 s left", "~7 min left", "~1 h 5 min left"; empty when the estimate is unknown.
static NSString *OITIDownloadETAText(double seconds) {
    if (!isfinite(seconds) || seconds < 0) return @"";
    if (seconds < 60.0) return [NSString stringWithFormat:@"~%d s left", MAX(5, (int)(ceil(seconds / 5.0) * 5.0))];
    int minutes = (int)ceil(seconds / 60.0);
    if (minutes < 60) return [NSString stringWithFormat:@"~%d min left", minutes];
    return [NSString stringWithFormat:@"~%d h %d min left", minutes / 60, minutes % 60];
}

// ---- The Minimal look: OITI's own pill ----------------------------------------------------------
// Apple's layouts cannot hold this design. The compact and wide layouts are two slots either side of the sensor (the
// owner's screenshot of the wide build showed only the icon and the percentage, none of the body), and the expanded
// layout adds the sensor row above its body. So the Minimal look is drawn by OITI: a black capsule in a window of its
// own at the top centre, above the Island's window. Touches outside the pill fall through. Its width, height and
// distance from the top are settings, so the size can be tuned on the phone without a rebuild. Portrait only.
static void OITIDownloadPillSwiped(void);

static UIWindowLevel OITIDownloadPillWindowLevel(void) {
    UIWindowLevel level = UIWindowLevelAlert + 1000.0;
    for (UIView *view in sLiveApertureWindows.allObjects) {
        if ([view isKindOfClass:[UIWindow class]]) level = MAX(level, ((UIWindow *)view).windowLevel + 1.0);
    }
    return level;
}

// SpringBoard's windows belong to a window scene. A window created without one can be "visible" yet never drawn on
// iOS 16, so the pill's window is built in the same scene as the Island's own window (the most reliable match), or in any
// window scene the application knows.
static UIWindowScene *OITIDownloadPillWindowScene(void) {
    for (UIView *view in sLiveApertureWindows.allObjects) {
        UIWindowScene *scene = [view isKindOfClass:[UIWindow class]] ? ((UIWindow *)view).windowScene : nil;
        if (scene) return scene;
    }
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)scene;
    }
    return nil;
}

// ---- Where the Island is -------------------------------------------------------------------------
// The pill covers the Island, so it needs the Island's rectangle on screen: its top, its height (the "sensor row" the pill
// keeps clear at its own top, like the expanded Island) and its width and centre. The Island's own pill view
// (SBSystemApertureContainerView, the rounded black shape) is looked for in the Island's windows and converted to screen
// coordinates, which includes OITI's position and scale transforms. If none is on screen (the Island is idle and not
// drawn on a phone without the hardware) or it looks wrong, the rectangle is computed from the stock idle size (125 x
// 36.667 window units) times the Island Size sliders and the window's scale, and the top comes from a constant.
static const CGFloat kOITIIslandStockWidth = 125.0;
static const CGFloat kOITIIslandStockHeight = 36.667;
static const CGFloat kOITIIslandFallbackTop = 11.0;

static void OITICollectIslandRects(UIView *view, Class containerClass, NSUInteger depth, NSMutableArray<NSValue *> *rects) {
    if (containerClass && [view isKindOfClass:containerClass]) {
        if (!view.hidden && view.alpha > 0.01) {
            CGRect rect = [[UIScreen mainScreen].coordinateSpace convertRect:view.bounds fromCoordinateSpace:view];
            if (rect.size.width > 20.0 && rect.size.height > 10.0) [rects addObject:[NSValue valueWithCGRect:rect]];
        }
        return;   // not inside the pill
    }
    if (depth >= 8) return;
    for (UIView *subview in view.subviews) OITICollectIslandRects(subview, containerClass, depth + 1, rects);
}

// Sets *rectOut to the Island pill in screen points and says where it came from.
static void OITIIslandPillRect(CGRect *rectOut, NSString **sourceOut) {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    Class containerClass = NSClassFromString(@"SBSystemApertureContainerView");
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    CGFloat scaleX = 1.0, scaleY = 1.0;
    BOOL haveScale = NO;
    for (UIView *view in sLiveApertureWindows.allObjects) {
        if (![view isKindOfClass:[UIWindow class]] || view.hidden) continue;
        OITICollectIslandRects(view, containerClass, 0, rects);
        if (!haveScale && view.transform.a > 0.1 && view.transform.d > 0.1) {
            scaleX = view.transform.a;
            scaleY = view.transform.d;
            haveScale = YES;
        }
    }
    CGFloat computedWidth = kOITIIslandStockWidth * sMetricsSensorX * scaleX;
    CGFloat computedHeight = kOITIIslandStockHeight * sMetricsSensorY * scaleY;

    // The topmost candidate (the widest if two start at the same height).
    CGRect best = CGRectNull;
    for (NSValue *value in rects) {
        CGRect rect = value.CGRectValue;
        if (CGRectIsNull(best) || rect.origin.y < best.origin.y - 1.0 ||
            (fabs(rect.origin.y - best.origin.y) <= 1.0 && rect.size.width > best.size.width)) best = rect;
    }
    BOOL plausible = !CGRectIsNull(best) && best.size.width >= 60.0 && best.size.width <= screen.width - 20.0 &&
                     best.origin.y >= -5.0 && best.origin.y <= 80.0 && best.size.height >= 20.0;
    if (plausible) {
        // An expanded Island is far taller than the sensor row; only its top and centre are of use then.
        CGFloat height = best.size.height <= 80.0 ? best.size.height : computedHeight;
        *rectOut = CGRectMake(best.origin.x, best.origin.y, best.size.width, height);
        *sourceOut = [NSString stringWithFormat:@"the Island's pill view (%lu candidate%@)", (unsigned long)rects.count, rects.count == 1 ? @"" : @"s"];
        return;
    }
    *rectOut = CGRectMake((screen.width - computedWidth) / 2.0, kOITIIslandFallbackTop, computedWidth, computedHeight);
    *sourceOut = [NSString stringWithFormat:@"computed from the stock size (%lu candidates, none usable)", (unsigned long)rects.count];
}

@interface OITIDownloadPillController : UIViewController
@end
@implementation OITIDownloadPillController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
@end

@interface OITIDownloadPillWindow : UIWindow
@end
@implementation OITIDownloadPillWindow
// Only the pill takes touches; everything else goes to whatever is underneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

@interface OITIDownloadPill : NSObject
@property (nonatomic, readonly) OITIMinimalDownloadView *content;
@property (nonatomic, readonly) UIWindowLevel level;
- (void)present;
- (void)relayout;
- (void)refreshOrientation;
- (void)dismiss;
@end

@implementation OITIDownloadPill {
    OITIDownloadPillWindow *_window;
    UIView *_pill;
    BOOL _dismissed;
    NSString *_geometryNote;
}
- (CGAffineTransform)collapsedTransform {
    // About a third of the height and half the width, kept at the top edge, like the Island growing from its idle size.
    return CGAffineTransformMake(0.5, 0, 0, 0.35, 0, -_pill.bounds.size.height * 0.325);
}
- (instancetype)init {
    if ((self = [super init])) {
        UIWindowScene *scene = OITIDownloadPillWindowScene();
        _window = scene ? [[OITIDownloadPillWindow alloc] initWithWindowScene:scene]
                        : [[OITIDownloadPillWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _window.backgroundColor = [UIColor clearColor];
        OITIDownloadPillController *controller = [[OITIDownloadPillController alloc] init];
        controller.view.backgroundColor = [UIColor clearColor];
        _window.rootViewController = controller;
        _level = OITIDownloadPillWindowLevel();
        _window.windowLevel = _level;
        _pill = [[UIView alloc] initWithFrame:CGRectZero];
        _pill.backgroundColor = [UIColor blackColor];
        _pill.layer.cornerCurve = kCACornerCurveContinuous;
        _content = [[OITIMinimalDownloadView alloc] initWithFrame:CGRectZero];
        [_pill addSubview:_content];
        [controller.view addSubview:_pill];
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped)];
        swipe.direction = UISwipeGestureRecognizerDirectionUp;
        [_pill addGestureRecognizer:swipe];
        [self relayout];
    }
    return self;
}
- (void)swiped { OITIDownloadPillSwiped(); }
// One line describing why the pill is or is not on screen. Written right after it is shown and again 0.8 s later.
- (void)logState:(NSString *)when {
    CALayer *shown = _pill.layer.presentationLayer;
    [sLog logTag:@"DOWNLOAD" format:@"pill %@: window hidden=%d scene=%@ level=%.0f key=%d pillWindowMatches=%d pill hidden=%d alpha=%.2f onScreenFrame=%@ | %@",
     when, _window.hidden, _window.windowScene ? NSStringFromClass([_window.windowScene class]) : @"none", (double)_window.windowLevel,
     _window.isKeyWindow, _pill.window == _window, _pill.hidden, _pill.alpha, shown ? NSStringFromCGRect(shown.frame) : @"none",
     _geometryNote ?: @"no geometry"];
}
- (void)relayout {
    if (!CGAffineTransformIsIdentity(_pill.transform)) return;   // mid-animation: the next refresh will do it
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGRect island = CGRectZero;
    NSString *source = nil;
    OITIIslandPillRect(&island, &source);

    // The pill starts at the Island's top, is centred on it and wide enough to cover it. Its top row is the Island's own
    // height and stays empty (the sensor row of the expanded Island); the content sits under it.
    CGFloat rowHeight = MAX(24.0, MIN(60.0, island.size.height));
    CGFloat width = MAX(MAX(200.0, sDownloadPillWidth), island.size.width + 32.0);
    width = MIN(width, screen.width - 16.0);
    CGFloat centerX = CGRectGetMidX(island);
    CGFloat x = MAX(8.0, MIN(screen.width - width - 8.0, centerX - width / 2.0));
    CGFloat contentTop = rowHeight + 3.0;
    CGFloat height = contentTop + kOITIMinimalHeight + sDownloadPillBottomPadding;
    _pill.frame = CGRectMake(floor(x), island.origin.y + sDownloadPillNudgeY, width, height);
    CGFloat radius = MIN(height / 2.0, MAX(rowHeight / 2.0 + 6.0, 22.0));
    _pill.layer.cornerRadius = radius;
    CGFloat padding = MAX(16.0, radius * 0.75);
    _content.frame = CGRectMake(padding, contentTop, MAX(100.0, width - 2.0 * padding), kOITIMinimalHeight);
    _geometryNote = [NSString stringWithFormat:@"island=%@ (%@) -> pill=%@", NSStringFromCGRect(island), source, NSStringFromCGRect(_pill.frame)];
}
- (void)refreshOrientation {
    _pill.hidden = UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation);   // portrait only
}
- (void)present {
    _dismissed = NO;
    _window.hidden = NO;
    [_window.rootViewController.view layoutIfNeeded];
    _pill.alpha = 0.0;
    _pill.transform = [self collapsedTransform];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self->_pill.alpha = 1.0; self->_pill.transform = CGAffineTransformIdentity; } completion:nil];
    [self logState:@"shown"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_dismissed) [self logState:@"0.8 s later"];
    });
}
- (void)dismiss {
    _dismissed = YES;
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                     animations:^{ self->_pill.alpha = 0.0; self->_pill.transform = [self collapsedTransform]; }
                     completion:^(BOOL finished) { if (self->_dismissed) self->_window.hidden = YES; }];
}
@end

static OITIDownloadPill *sDownloadPill;   // the Minimal look, while it is on screen

static void OITIDownloadPillPresent(NSDictionary *snapshot) {
    OITIDownloadPill *pill = [[OITIDownloadPill alloc] init];
    sDownloadPill = pill;
    sDownloadShownAt = CFAbsoluteTimeGetCurrent();
    [pill present];
    [sLog logTag:@"DOWNLOAD" format:@"progress pill up for %@ (window level %.0f)", snapshot[@"title"], (double)pill.level];
}

static void OITIDownloadPillDismiss(NSString *reason) {
    OITIDownloadPill *pill = sDownloadPill;
    if (!pill) return;
    sDownloadPill = nil;
    [pill dismiss];
    [sLog logTag:@"DOWNLOAD" format:@"progress pill dismissed (%@)", reason];
}

// A swipe up: gone, and it stays away until the next download starts.
static void OITIDownloadPillSwiped(void) {
    sDownloadCollapsed = YES;
    OITIDownloadPillDismiss(@"swipe");
}

// "App Name - File Name" for one download, "N downloads" for several.
static NSString *OITIDownloadHeaderText(NSDictionary *snapshot) {
    NSUInteger count = [snapshot[@"count"] unsignedIntegerValue];
    if (count > 1) return [NSString stringWithFormat:@"%lu downloads", (unsigned long)count];
    NSString *appName = snapshot[@"appName"];
    NSString *title = snapshot[@"title"];
    return appName.length ? [NSString stringWithFormat:@"%@ - %@", appName, title] : title;
}

// Writes the snapshot into whichever look is showing. complete shows the finished state.
// ending: 0 = running, 1 = completed, 2 = cancelled (a short red "Cancelled" state).
static void OITIDownloadUpdateViews(NSDictionary *snapshot, NSInteger ending) {
    BOOL complete = ending == 1;
    BOOL cancelled = ending == 2;
    NSDictionary *item = sDownloadItem;
    OITIMinimalDownloadView *minimal = sDownloadPill.content;
    if ((!item && !minimal) || !snapshot) return;
    double downloaded = [snapshot[@"downloaded"] doubleValue];
    double total = [snapshot[@"total"] doubleValue];
    double speed = [snapshot[@"speed"] doubleValue];
    BOOL fractionMode = [snapshot[@"fractionMode"] boolValue];
    BOOL paused = [snapshot[@"paused"] boolValue];
    NSString *etaText = (complete || paused) ? @"" : OITIDownloadETAText([snapshot[@"eta"] doubleValue]);
    double fraction = complete ? 1.0 : (fractionMode ? [snapshot[@"fraction"] doubleValue] : (total > 0 ? downloaded / total : 0.0));
    NSString *percent = (fractionMode || total > 0 || complete) ? [NSString stringWithFormat:@"%d%%", (int)floor(fraction * 100.0 + 0.0001)] : @"…";
    NSString *header = OITIDownloadHeaderText(snapshot);

    if (minimal && cancelled) {
        [minimal resetCompletion];
        [minimal setHeader:header downloaded:@"Cancelled" total:@"" speed:@"" percent:percent fraction:fraction complete:NO];
        [minimal.bar setCancelled:YES];
        [sDownloadPill refreshOrientation];
        return;
    }
    if (minimal && fractionMode) {
        // A source that only knows a percentage: no sizes and no speed, a state word above the bar and the estimate below it.
        [minimal setHeader:header
                downloaded:complete ? @"Download complete" : (paused ? @"Paused" : @"Downloading")
                     total:etaText
                     speed:complete ? @"Done" : @""
                   percent:percent fraction:fraction complete:complete];
        if (complete) [minimal playCompletion]; else [minimal resetCompletion];
        [sDownloadPill refreshOrientation];
        return;
    }
    if (minimal) {
        [minimal setHeader:header
                downloaded:OITIDownloadBytesText(complete && total > 0 ? total : downloaded)
                     total:total > 0 ? OITIDownloadBytesText(total) : @"?"
                     speed:complete ? @"Done" : [NSString stringWithFormat:@"%@/s", OITIDownloadBytesText(speed)]
                   percent:percent fraction:fraction complete:complete];
        if (complete) [minimal playCompletion]; else [minimal resetCompletion];
        [sDownloadPill refreshOrientation];
        return;
    }
    UILabel *trailing = (UILabel *)item[@"trailingView"];
    OITIProgressBarView *bar = item[@"downloadBar"];
    UILabel *detail = item[@"downloadDetail"];
    UILabel *headline = (UILabel *)item[@"primaryView"];
    if ([headline isKindOfClass:[UILabel class]] && ![headline.text isEqualToString:header]) headline.text = header;
    NSString *detailText;
    if (cancelled) {
        detailText = @"Download cancelled";
    } else if (complete) {
        detailText = fractionMode ? @"Download complete" : [NSString stringWithFormat:@"Download complete · %@", OITIDownloadBytesText(downloaded)];
    } else if (fractionMode) {
        NSString *state = paused ? @"Paused" : etaText;
        detailText = state.length ? [NSString stringWithFormat:@"%@ · %@", percent, state] : percent;
    } else if (total > 0) {
        detailText = [NSString stringWithFormat:@"%@ of %@ · %@/s", OITIDownloadBytesText(downloaded), OITIDownloadBytesText(total),
                      OITIDownloadBytesText(speed)];
    } else {
        detailText = [NSString stringWithFormat:@"%@ · %@/s", OITIDownloadBytesText(downloaded), OITIDownloadBytesText(speed)];
    }
    if (![detail.text isEqualToString:detailText]) detail.text = detailText;
    [bar setComplete:complete];
    if (cancelled) [bar setCancelled:YES];
    [bar setFraction:fraction animated:YES];
    if ([trailing isKindOfClass:[UILabel class]] && ![trailing.text isEqualToString:percent]) {
        trailing.text = percent;
        [trailing sizeToFit];
    }
}

static void OITIDownloadsEnsureTimer(void);
static void OITIFakeDownloadAdvance(void);
static void OITIAppStoreSourceRefresh(void);

// Presents, updates and ends the element for the current state. Called after every update and from the timer.
static void OITIDownloadsRefresh(void) {
    if (!sDownloadProgressEnabled) {
        if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"feature-disabled");
        OITIDownloadPillDismiss(@"feature-disabled");
        return;
    }
    NSDictionary *snapshot = OITIDownloadSnapshot();
    if (!snapshot) return;   // OITIDownloadFinish handles the end
    sDownloadCompleteGeneration++;   // a pending "complete" removal no longer applies
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

    // Return to idle by size or by time, whichever look is showing.
    if (sDownloadItem || sDownloadPill) {
        double limitBytes = sDownloadIdleAfterMB * 1000.0 * 1000.0;   // decimal MB, like the size text
        BOOL byBytes = limitBytes > 0 && ![snapshot[@"fractionMode"] boolValue] && [snapshot[@"downloaded"] doubleValue] >= limitBytes;   // sizes are unknown in fraction mode
        BOOL byTime = sDownloadIdleAfterSeconds > 0 && now - sDownloadShownAt >= sDownloadIdleAfterSeconds;
        if (byBytes || byTime) {
            [sLog logTag:@"DOWNLOAD" format:@"limit reached (%@): the Island returns to idle, the download carries on",
             byBytes ? [NSString stringWithFormat:@"%@ downloaded", OITIDownloadBytesText([snapshot[@"downloaded"] doubleValue])]
                     : [NSString stringWithFormat:@"%.0f s on screen", (double)(now - sDownloadShownAt)]];
            sDownloadCollapsed = YES;
            if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"download-limit");
            OITIDownloadPillDismiss(@"download-limit");
            return;
        }
    }

    if (sDownloadStyle == 0) {
        // Minimal: OITI's own pill. Nothing of the Apple element is used.
        if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"restyle");
        if (!sDownloadPill && !sDownloadCollapsed && now >= sDownloadNextPresentAttempt) OITIDownloadPillPresent(snapshot);
        OITIDownloadUpdateViews(snapshot, NO);
        return;
    }
    OITIDownloadPillDismiss(@"restyle");

    // Detailed: the Apple element.
    if (sDownloadItem) {
        // The system can end an element on its own (its alert timer) without telling OITI. If the bar was on screen and
        // should still be the one showing but its views have left the window, record that and put it back. At most
        // five times per download, so a system that keeps ending it can never make the bar flicker forever.
        UIView *probe = sDownloadItem[@"downloadBar"];
        if (probe && sIslandNoticeItems.lastObject == sDownloadItem) {
            if (probe.window) {
                sDownloadItem[@"downloadSeenOnScreen"] = @YES;
            } else if ([sDownloadItem[@"downloadSeenOnScreen"] boolValue]) {
                sDownloadDropCount++;
                [sLog logTag:@"DOWNLOAD" format:@"the progress element left the screen after %.0f s but nothing in OITI removed it, so the system ended it (drop %lu of 5)",
                 (double)(now - sDownloadShownAt), (unsigned long)sDownloadDropCount];
                if (sDownloadDropCount >= 5) {
                    sDownloadCollapsed = YES;
                    [sLog logTag:@"DOWNLOAD" format:@"giving up on putting the progress element back for this download"];
                } else {
                    // Wait longer after every drop (1.5, 4.5, 13.5, 30 s): if something else really took the Island over,
                    // such as a call, the bar should not keep pushing back in.
                    sDownloadNextPresentAttempt = now + MIN(30.0, 1.5 * pow(3.0, (double)(sDownloadDropCount - 1)));
                }
                OITIRemoveNoticeItem(sDownloadItem, @"system-dismissed");
                return;
            }
        }
    } else if (!sDownloadCollapsed && now >= sDownloadNextPresentAttempt) {
        NSString *message = [snapshot[@"fractionMode"] boolValue]
            ? [NSString stringWithFormat:@"%d%%", (int)floor([snapshot[@"fraction"] doubleValue] * 100.0 + 0.0001)]
            : [NSString stringWithFormat:@"%@ of %@", OITIDownloadBytesText([snapshot[@"downloaded"] doubleValue]),
               [snapshot[@"total"] doubleValue] > 0 ? OITIDownloadBytesText([snapshot[@"total"] doubleValue]) : @"?"];
        NSDictionary *info = @{ @"bundleID": snapshot[@"bundleID"], @"appName": snapshot[@"appName"], @"title": snapshot[@"title"], @"message": message };
        if (OITIPresentNoticeElement(info, @"download-progress")) {
            [sLog logTag:@"DOWNLOAD" format:@"progress element up for %@", snapshot[@"title"]];
        } else {
            sDownloadNextPresentAttempt = now + 10.0;   // not ready, recovering or failed: try again later, not every tick
        }
    }
    OITIDownloadUpdateViews(snapshot, NO);
}

// Called from OITIRemoveNoticeItem when the download element leaves. Removals we made ourselves are recorded as such;
// anything else (a swipe, a notification replacing it, stack capacity) keeps it away until the next download starts.
static void OITIDownloadItemRemoved(NSDictionary *item, NSString *reason) {
    sDownloadItem = nil;
    NSArray<NSString *> *ours = @[@"download-limit", @"download-complete", @"download-cancelled", @"feature-disabled",
                                  @"restyle", @"system-dismissed"];
    if (![ours containsObject:reason]) {
        sDownloadCollapsed = YES;
        [sLog logTag:@"DOWNLOAD" format:@"progress element removed (%@): it stays away until the next download starts", reason];
    }
}

// Sources call this with the bytes so far. total is 0 when unknown. Speed is smoothed from the byte deltas.
static void OITIDownloadUpdate(NSString *identifier, NSString *appName, NSString *title, NSString *bundleID, double downloaded, double total) {
    if (!identifier.length) return;
    if (!sDownloads) sDownloads = [NSMutableDictionary dictionary];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSMutableDictionary *download = sDownloads[identifier];
    if (!download) {
        download = [NSMutableDictionary dictionary];
        sDownloads[identifier] = download;
        download[@"speed"] = @0.0;
        download[@"lastBytes"] = @(MAX(0.0, downloaded));
        download[@"lastTime"] = @(now);
        sDownloadCollapsed = NO;   // a new download brings the element back
        sDownloadNextPresentAttempt = 0;
        sDownloadDropCount = 0;
        [sLog logTag:@"DOWNLOAD" format:@"started %@ (%@), total %@", identifier, title ?: @"?",
         total > 0 ? OITIDownloadBytesText(total) : @"unknown"];
    }
    download[@"title"] = title.length ? title : @"Download";
    download[@"appName"] = appName ?: @"";
    download[@"bundleID"] = bundleID ?: @"";
    download[@"total"] = @(MAX(0.0, total));
    download[@"downloaded"] = @(MAX(0.0, downloaded));
    double dt = now - [download[@"lastTime"] doubleValue];
    if (dt >= 0.25) {
        double instant = MAX(0.0, downloaded - [download[@"lastBytes"] doubleValue]) / dt;
        double previous = [download[@"speed"] doubleValue];
        download[@"speed"] = @(previous > 0 ? previous * 0.7 + instant * 0.3 : instant);
        download[@"lastBytes"] = @(MAX(0.0, downloaded));
        download[@"lastTime"] = @(now);
    }
    OITIDownloadsEnsureTimer();
    OITIDownloadsRefresh();
}

// Sources that only know a percentage (the App Store) call this instead. fraction is 0 to 1. The estimate of the time
// left comes from how fast the fraction moves (smoothed, unknown while paused or when it has not moved for 20 s).
static void OITIDownloadUpdateFraction(NSString *identifier, NSString *appName, NSString *title, NSString *bundleID, double fraction, BOOL paused) {
    if (!identifier.length) return;
    if (!sDownloads) sDownloads = [NSMutableDictionary dictionary];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double clamped = isfinite(fraction) ? MAX(0.0, MIN(1.0, fraction)) : 0.0;
    NSMutableDictionary *download = sDownloads[identifier];
    if (!download) {
        download = [NSMutableDictionary dictionary];
        sDownloads[identifier] = download;
        download[@"fractionOnly"] = @YES;
        download[@"fractionRate"] = @0.0;
        download[@"fractionLast"] = @(clamped);
        download[@"fractionLastTime"] = @(now);
        download[@"fractionChangeTime"] = @(now);
        sDownloadCollapsed = NO;   // a new download brings the element back
        sDownloadNextPresentAttempt = 0;
        sDownloadDropCount = 0;
        [sLog logTag:@"DOWNLOAD" format:@"started %@ (%@), percentage only (no sizes)", identifier, title ?: @"?"];
    }
    download[@"title"] = title.length ? title : @"Download";
    download[@"appName"] = appName ?: @"";
    download[@"bundleID"] = bundleID ?: @"";
    download[@"fraction"] = @(clamped);
    download[@"paused"] = @(paused);
    double last = [download[@"fractionLast"] doubleValue];
    if (clamped > last + 0.0005) {
        double dt = now - [download[@"fractionLastTime"] doubleValue];
        if (dt >= 0.25) {
            double instant = (clamped - last) / dt;
            double previous = [download[@"fractionRate"] doubleValue];
            download[@"fractionRate"] = @(previous > 0 ? previous * 0.7 + instant * 0.3 : instant);
        }
        download[@"fractionLast"] = @(clamped);
        download[@"fractionLastTime"] = @(now);
        download[@"fractionChangeTime"] = @(now);
    } else if (clamped < last - 0.0005) {   // started over: forget the old rate
        download[@"fractionRate"] = @0.0;
        download[@"fractionLast"] = @(clamped);
        download[@"fractionLastTime"] = @(now);
        download[@"fractionChangeTime"] = @(now);
    }
    OITIDownloadsEnsureTimer();
    OITIDownloadsRefresh();
}

// outcome: 0 = drop quietly (the feature or the source was switched off), 1 = completed (a short "complete" state with the
// check animation), 2 = cancelled (a short red "Cancelled" state). With several downloads only the one that ended is removed.
static void OITIDownloadEnd(NSString *identifier, NSInteger outcome) {
    NSMutableDictionary *download = sDownloads[identifier];
    if (!download) return;
    BOOL completed = outcome == 1;
    double total = [download[@"total"] doubleValue];
    if (completed && total > 0) download[@"downloaded"] = @(total);
    if (completed && [download[@"fractionOnly"] boolValue]) download[@"fraction"] = @1.0;
    NSDictionary *finalSnapshot = OITIDownloadSnapshot();
    [sDownloads removeObjectForKey:identifier];
    [sLog logTag:@"DOWNLOAD" format:@"%@ %@", completed ? @"finished" : (outcome == 2 ? @"cancelled" : @"dropped"), identifier];
    OITIDownloadsEnsureTimer();
    if (sDownloads.count) {
        OITIDownloadsRefresh();
        return;
    }
    if (!sDownloadItem && !sDownloadPill) return;
    if (!completed) {
        if (outcome == 2 && finalSnapshot) {
            OITIDownloadUpdateViews(finalSnapshot, 2);
            NSUInteger cancelGeneration = ++sDownloadCompleteGeneration;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (cancelGeneration == sDownloadCompleteGeneration && !sDownloads.count) {
                    if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"download-cancelled");
                    OITIDownloadPillDismiss(@"download-cancelled");
                }
            });
            return;
        }
        if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"download-cancelled");
        OITIDownloadPillDismiss(@"download-cancelled");
        return;
    }
    OITIDownloadUpdateViews(finalSnapshot, 1);
    NSUInteger generation = ++sDownloadCompleteGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == sDownloadCompleteGeneration && !sDownloads.count) {
            if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"download-complete");
            OITIDownloadPillDismiss(@"download-complete");
        }
    });
}

// A download ended: completed YES shows the "complete" state, NO shows "Cancelled" (the last one only).
static void OITIDownloadFinish(NSString *identifier, BOOL completed) {
    OITIDownloadEnd(identifier, completed ? 1 : 2);
}

// A download stops being tracked without a verdict (the source was switched off): the bar goes at once.
static void OITIDownloadDrop(NSString *identifier) {
    OITIDownloadEnd(identifier, 0);
}

static void OITIDownloadsEnsureTimer(void) {
    BOOL needed = sDownloads.count > 0;
    if (needed && !sDownloadTimer) {
        sDownloadTimer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            OITIFakeDownloadAdvance();
            OITIDownloadsRefresh();
        }];
        [[NSRunLoop mainRunLoop] addTimer:sDownloadTimer forMode:NSRunLoopCommonModes];
    } else if (!needed && sDownloadTimer) {
        [sDownloadTimer invalidate];
        sDownloadTimer = nil;
    }
}

// ---- Test download (started and stopped from Settings > OITI > Download Progress) ---------------
static BOOL sFakeDownloadActive = NO;
static double sFakeDownloadBytes = 0, sFakeDownloadTotal = 0, sFakeDownloadSpeed = 0;
static CFAbsoluteTime sFakeDownloadLastTick = 0;
static NSString * const kOITIFakeDownloadIdentifier = @"oiti.test-download";

// Reports the simulated bytes, or only a whole-percent fraction when DownloadTestFractionOnly is on (to try the
// percentage-only look without a real download).
static void OITIFakeDownloadReport(double bytes) {
    if (sDownloadTestFractionOnly) {
        double fraction = sFakeDownloadTotal > 0 ? floor(bytes / sFakeDownloadTotal * 100.0) / 100.0 : 0.0;
        OITIDownloadUpdateFraction(kOITIFakeDownloadIdentifier, @"App Store", @"Test Download", @"com.apple.AppStore", fraction, NO);
    } else {
        OITIDownloadUpdate(kOITIFakeDownloadIdentifier, @"App Store", @"Test Download", @"com.apple.AppStore", bytes, sFakeDownloadTotal);
    }
}

static void OITIFakeDownloadStart(void) {
    if (sFakeDownloadActive) {
        // Already running: Start brings a bar that was dismissed or timed out back.
        [sLog logTag:@"DOWNLOAD" format:@"test download is already running; showing the bar again"];
        sDownloadCollapsed = NO;
        sDownloadNextPresentAttempt = 0;
        sDownloadDropCount = 0;
        OITIDownloadsRefresh();
        return;
    }
    CGFloat sizeMB = isfinite(sDownloadTestSizeMB) ? MAX(50.0, MIN(5000.0, sDownloadTestSizeMB)) : 800.0;
    sFakeDownloadTotal = sizeMB * 1000.0 * 1000.0;
    sFakeDownloadBytes = 0;
    sFakeDownloadSpeed = 8.0e6 + (double)arc4random_uniform(6000000);
    sFakeDownloadLastTick = CFAbsoluteTimeGetCurrent();
    sFakeDownloadActive = YES;
    [sLog logTag:@"DOWNLOAD" format:@"test download started: %@ (Download Progress is %@)", OITIDownloadBytesText(sFakeDownloadTotal),
     sDownloadProgressEnabled ? @"on" : @"OFF, so nothing will show"];
    OITIFakeDownloadReport(0);
}

// Called from the tracker's timer: moves the simulated bytes along with a speed that drifts between 2 and 28 MB/s.
static void OITIFakeDownloadAdvance(void) {
    if (!sFakeDownloadActive) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double dt = MAX(0.0, MIN(2.0, now - sFakeDownloadLastTick));
    sFakeDownloadLastTick = now;
    double drift = ((double)arc4random_uniform(2001) - 1000.0) / 1000.0 * 1.5e6;
    sFakeDownloadSpeed = MAX(2.0e6, MIN(28.0e6, sFakeDownloadSpeed + drift));
    sFakeDownloadBytes = MIN(sFakeDownloadTotal, sFakeDownloadBytes + sFakeDownloadSpeed * dt);
    if (sFakeDownloadBytes >= sFakeDownloadTotal) {
        sFakeDownloadActive = NO;
        OITIFakeDownloadReport(sFakeDownloadTotal);
        OITIDownloadFinish(kOITIFakeDownloadIdentifier, YES);
        return;
    }
    OITIFakeDownloadReport(sFakeDownloadBytes);
}

static void OITIFakeDownloadStop(void) {
    if (!sFakeDownloadActive) return;
    sFakeDownloadActive = NO;
    OITIDownloadFinish(kOITIFakeDownloadIdentifier, NO);
}

// =============================================================================================
// MARK: App Store source (Download Progress, stage 2)
// =============================================================================================

// Feeds the download tracker from the App Store's placeholders in SpringBoard. Setting: DownloadAppStoreEnabled (default
// off, Settings > OITI > Download Progress > App Store Downloads); it also needs DownloadProgressEnabled, and Apple Mode and
// safe mode switch it off (safe mode: the timer never starts).
//
// What the install dump showed (build -c, iOS 16.7.16, one App Store download; LEARNINGS.md): a download's placeholder
// carries a percentage and no byte counts. Path, all by instance variables: SBApplicationPlaceholderController
// -placeholdersByDisplayID (bundle ID -> SBApplicationPlaceholder) > _placeholderProxy > _queue_progress
// (FBSApplicationPlaceholderProgress) > _percentComplete (double, 0 to 1, -1 = unknown) and _progress (an NSProgress with a
// total of 100). So the tracker gets a fraction (OITIDownloadUpdateFraction), not bytes.
//
// How it works. A timer on the main run loop polls once a second, only while the feature is on. Each poll reads the
// placeholders. A placeholder with a readable fraction of 0 or more becomes (or stays) a tracked download. When a tracked
// placeholder leaves the list, the app is looked up: installed means complete, and if it is not there after a 3 s grace the
// download counts as complete only when it had reached 97 percent, otherwise as cancelled (an update or a TestFlight
// install has not been dumped yet, so those are unconfirmed).
//
// Risk rules (see LEARNINGS.md, "Never call private methods because their names look like getters"): the progress is read
// from instance variables and the public NSProgress API; the only private method calls are the explicitly named
// accessors placeholdersByDisplayID, displayName and isPaused (a declared property that SpringBoard's own icon code calls),
// plus the shared-instance and applicationWithBundleIdentifier: lookups the install dump already uses. Whether a pause shows
// up in isPaused or in the NSProgress is logged (level 1) the first time it changes, so the first real pause tells us.

static BOOL OITISafeBool(id object, NSString *selectorName, BOOL *available);

static NSTimer *sAppStoreTimer;
static NSMutableDictionary<NSString *, NSMutableDictionary *> *sAppStoreTracked;   // bundle ID -> name, fraction, paused, missingSince
static NSMutableSet<NSString *> *sAppStoreWarned;                                  // one-time warnings per session
static const NSTimeInterval kOITIAppStorePollInterval = 1.0;
static const NSTimeInterval kOITIAppStoreFinishGrace = 3.0;

static NSString *OITIAppStoreIdentifier(NSString *bundleID) {
    return [@"appstore:" stringByAppendingString:bundleID];
}

static id OITIAppStoreIvarObject(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable([object class], name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || type[0] != '@') return nil;
    return object_getIvar(object, ivar);
}

static BOOL OITIAppStoreIvarNumber(id object, const char *name, double *value) {
    if (!object) return NO;
    Ivar ivar = class_getInstanceVariable([object class], name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || !type[0]) return NO;
    double number = NAN;
    if (!OITIInstallIvarScalarText(object, ivar, type, &number) || isnan(number)) return NO;
    if (value) *value = number;
    return YES;
}

// Reads one placeholder. Returns NO when the progress object is not where it was on iOS 16.7.16. fraction is -1 while
// the progress is unknown.
static BOOL OITIAppStoreRead(id placeholder, double *fractionOut, BOOL *pausedOut, NSString **detailOut) {
    id proxy = OITIAppStoreIvarObject(placeholder, "_placeholderProxy");
    id progressObject = OITIAppStoreIvarObject(proxy, "_queue_progress");
    if (!progressObject) return NO;
    double fraction = -1.0, phase = -1.0, state = -1.0;
    BOOL haveFraction = OITIAppStoreIvarNumber(progressObject, "_percentComplete", &fraction);
    OITIAppStoreIvarNumber(progressObject, "_installPhase", &phase);
    OITIAppStoreIvarNumber(progressObject, "_installState", &state);
    id nsProgress = OITIAppStoreIvarObject(progressObject, "_progress");
    BOOL progressPaused = NO;
    if ([nsProgress isKindOfClass:[NSProgress class]]) {
        NSProgress *progress = (NSProgress *)nsProgress;
        if (!haveFraction || (fraction < 0 && !progress.indeterminate)) {
            fraction = progress.fractionCompleted;
            haveFraction = YES;
        }
        progressPaused = progress.paused;
    }
    BOOL available = NO;
    BOOL placeholderPaused = OITISafeBool(placeholder, @"isPaused", &available);
    if (fractionOut) *fractionOut = fraction;
    if (pausedOut) *pausedOut = progressPaused || (available && placeholderPaused);
    if (detailOut) {
        *detailOut = [NSString stringWithFormat:@"installPhase=%.0f installState=%.0f nsProgress=%d progressPaused=%d placeholderPaused=%@",
                      phase, state, nsProgress != nil, (int)progressPaused, available ? (placeholderPaused ? @"YES" : @"NO") : @"?"];
    }
    return haveFraction;
}

static NSString *OITIAppStoreDisplayName(id placeholder, NSString *bundleID) {
    id proxy = OITIAppStoreIvarObject(placeholder, "_placeholderProxy");
    for (id candidate in @[placeholder ?: @"", proxy ?: @""]) {
        if ([candidate isKindOfClass:[NSString class]]) continue;
        id value = OITIInstallObjectGetter(candidate, @"displayName");
        if ([value isKindOfClass:[NSString class]] && ((NSString *)value).length) return value;
    }
    return bundleID;
}

static void OITIAppStorePoll(void) {
    if (!sDownloadProgressEnabled || !sDownloadAppStoreEnabled || sSafeModeActive) return;
    if (!sAppStoreTracked) sAppStoreTracked = [NSMutableDictionary dictionary];
    if (!sAppStoreWarned) sAppStoreWarned = [NSMutableSet set];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @try {
        id controller = OITIInstallSharedInstance(NSClassFromString(@"SBApplicationPlaceholderController"), NULL);
        id dictionary = OITIInstallObjectGetter(controller, @"placeholdersByDisplayID");
        BOOL haveList = [dictionary isKindOfClass:[NSDictionary class]];
        if (!haveList && ![sAppStoreWarned containsObject:@"list"]) {
            [sAppStoreWarned addObject:@"list"];
            [sLog logTag:@"DOWNLOAD" format:@"App Store source: the placeholder list is not available (controller %@). The classes may differ on this iOS version; run the install dump (COMMANDS.md section 17).",
             controller ? @"found" : @"missing"];
        }
        NSMutableSet<NSString *> *present = [NSMutableSet set];
        if (haveList) {
            NSDictionary *placeholders = (NSDictionary *)dictionary;
            for (id key in placeholders.allKeys) {
                if (![key isKindOfClass:[NSString class]]) continue;
                NSString *bundleID = key;
                id placeholder = placeholders[bundleID];
                double fraction = -1.0;
                BOOL paused = NO;
                NSString *detail = nil;
                BOOL readable = OITIAppStoreRead(placeholder, &fraction, &paused, &detail);
                NSMutableDictionary *tracked = sAppStoreTracked[bundleID];
                if (!readable) {
                    if (![sAppStoreWarned containsObject:bundleID]) {
                        [sAppStoreWarned addObject:bundleID];
                        [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source: the placeholder for %@ has no readable progress object, skipped", bundleID];
                    }
                    if (tracked) [present addObject:bundleID];   // keep what is shown until it leaves the list
                    continue;
                }
                if (fraction < 0 && !tracked) continue;   // progress unknown and not tracked yet: not downloading (or not started)
                if (fraction < 0) fraction = [tracked[@"fraction"] doubleValue];   // keep the last value while it is unknown
                [present addObject:bundleID];
                if (!tracked) {
                    tracked = [NSMutableDictionary dictionary];
                    sAppStoreTracked[bundleID] = tracked;
                    tracked[@"paused"] = @NO;
                    tracked[@"name"] = OITIAppStoreDisplayName(placeholder, bundleID);
                    [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source: tracking %@ (%@) at %d%% (%@)", bundleID, tracked[@"name"],
                     (int)lround(fraction * 100.0), detail];
                }
                if ([tracked[@"paused"] boolValue] != paused) {
                    tracked[@"paused"] = @(paused);
                    [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source: %@ %@ at %d%% (%@)", bundleID, paused ? @"paused" : @"resumed",
                     (int)lround(fraction * 100.0), detail];
                }
                tracked[@"fraction"] = @(fraction);
                [tracked removeObjectForKey:@"missingSince"];
                OITIDownloadUpdateFraction(OITIAppStoreIdentifier(bundleID), @"App Store", tracked[@"name"], bundleID, fraction, paused);
                OITLOGGER_LOG_RATED(sLog, 2, @"DOWNLOAD", @"appstore-poll", 1, @"App Store source: %@ %.4f paused=%d %@",
                                    bundleID, fraction, (int)paused, detail);
            }
        }
        for (NSString *bundleID in sAppStoreTracked.allKeys) {
            if ([present containsObject:bundleID]) continue;
            NSMutableDictionary *tracked = sAppStoreTracked[bundleID];
            if (!tracked[@"missingSince"]) tracked[@"missingSince"] = @(now);
            id applicationController = OITIInstallSharedInstance(NSClassFromString(@"SBApplicationController"), NULL);
            BOOL installed = OITIInstallApplicationForBundleID(applicationController, bundleID) != nil;
            BOOL waited = now - [tracked[@"missingSince"] doubleValue] >= kOITIAppStoreFinishGrace;
            if (!installed && !waited) continue;   // the app may still be about to appear
            double lastFraction = [tracked[@"fraction"] doubleValue];
            BOOL completed = installed || lastFraction >= 0.97;
            [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source: %@ left the placeholder list at %d%%: %@ (app installed: %@)", bundleID,
             (int)lround(lastFraction * 100.0), completed ? @"complete" : @"cancelled", installed ? @"yes" : @"no"];
            OITIDownloadFinish(OITIAppStoreIdentifier(bundleID), completed);
            [sAppStoreTracked removeObjectForKey:bundleID];
        }
    } @catch (NSException *exception) {
        [sLog logTag:@"DOWNLOAD" format:@"App Store source: exception %@: %@", exception.name, exception.reason];
    }
}

// Starts or stops the poll for the current settings. Idempotent; called after every preferences reload.
static void OITIAppStoreSourceRefresh(void) {
    BOOL wanted = sDownloadProgressEnabled && sDownloadAppStoreEnabled && !sAppleMode && !sSafeModeActive;
    if (wanted && !sAppStoreTimer) {
        sAppStoreTimer = [NSTimer timerWithTimeInterval:kOITIAppStorePollInterval repeats:YES block:^(NSTimer *timer) {
            OITIAppStorePoll();
        }];
        [[NSRunLoop mainRunLoop] addTimer:sAppStoreTimer forMode:NSRunLoopCommonModes];
        [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source on: polling the placeholders every %.0f s", kOITIAppStorePollInterval];
        OITIAppStorePoll();
    } else if (!wanted && sAppStoreTimer) {
        [sAppStoreTimer invalidate];
        sAppStoreTimer = nil;
        for (NSString *bundleID in sAppStoreTracked.allKeys) OITIDownloadDrop(OITIAppStoreIdentifier(bundleID));
        [sAppStoreTracked removeAllObjects];
        [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source off"];
    }
}

// The developer trigger (touch /tmp/OITIPoC.trigger). Independent of the islandNotificationsEnabled setting because
// it never reacts to a notification: it is a manual test of the element mechanism.
void OITIRunPoCElement(NSString *reason) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *info = @{ @"bundleID": @"com.apple.Preferences", @"appName": @"Insula",
                                @"title": @"Island Notification", @"subtitle": @"",
                                @"message": @"Hello from Insula" };
        // /tmp/OITIPoCSample.txt (optional): title, message, bundle id, subtitle, one per line, to try long text or no title.
        NSString *sample = [NSString stringWithContentsOfFile:@"/tmp/OITIPoCSample.txt" encoding:NSUTF8StringEncoding error:nil];
        if (sample.length) {
            NSArray<NSString *> *rows = [sample componentsSeparatedByString:@"\n"];
            NSString *(^row)(NSUInteger) = ^NSString *(NSUInteger i) { return i < rows.count ? rows[i] : @""; };
            NSString *sampleBundle = row(2).length ? row(2) : @"com.apple.MobileSMS";
            info = @{ @"bundleID": sampleBundle, @"appName": @"", @"title": row(0), @"subtitle": row(3), @"message": row(1) };
        }
        OITIPresentNoticeElement(info, reason);
    });
}

// First-stage prototype: verify launch gating and Island handoff with the existing custom-content element.
// The final Hello video and dedicated media view are intentionally not part of this prototype.
static BOOL OITISafeBool(id object, NSString *selectorName, BOOL *available) {
    if (available) *available = NO;
    if (!object || !selectorName.length) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) return NO;
    const char *returnType = signature.methodReturnType;
    if (!returnType || (returnType[0] != 'B' && returnType[0] != 'c')) return NO;
    if (available) *available = YES;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
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

// ---- Haptic ----------------------------------------------------------------------------------
// One short light tap per banner request. Respects the system's own haptics setting (UIKit decides).
static void OITIPlayNotificationHaptic(void) {
    static CFAbsoluteTime lastHaptic = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - lastHaptic < 0.4) return;   // one banner can be posted more than once
    lastHaptic = now;
    dispatch_async(dispatch_get_main_queue(), ^{
        static UIImpactFeedbackGenerator *generator;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (!generator) generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
#pragma clang diagnostic pop
        [generator prepare];
        [generator impactOccurredWithIntensity:0.8];
        [sLog logLevel:1 tag:@"NOTIF" format:@"haptic played"];
    });
}

// A banner request arrived. Always safe: log-only unless the feature is on.
static void OITIHandleBannerRequest(id destination, id request) {
    if ([sOITIPreferences boolForKey:@"NotificationHaptic" default:NO]) OITIPlayNotificationHaptic();
    if (sStartupHelloObservationWindowOpen && islandStartupHelloEnabled) sStartupHelloActivitySeen = YES;
    if (sStartupHelloItem) {
        dispatch_async(dispatch_get_main_queue(), ^{
            OITICancelStartupHello(@"notification");
        });
    }
    if (!islandNotificationsEnabled && !(sLog.enabled && sLog.level >= 1)) return;
    NSDictionary<NSString *, NSString *> *info = OITINoticeInfoFromRequest(request);
    [sLog logLevel:1 tag:@"NOTIF" format:@"banner request %@ bundle=%@ app=%@ title=%@ message=%@ (feature %@)",
     OITIObjectSummary(request), info[@"bundleID"], OITIShortText(info[@"appName"], 30), OITIShortText(info[@"title"], 40),
     OITIShortText(info[@"message"], 60), islandNotificationsEnabled ? @"on" : @"off"];
    if (!islandNotificationsEnabled) return;

    __weak id weakDestination = destination;
    id requestRef = request;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!islandNotificationsEnabled) return;   // the setting may have been turned off before this queued block ran
        sPendingNoticeRequest = requestRef;
        BOOL shown = OITIPresentNoticeElement(info, @"notification");
        sPendingNoticeRequest = nil;
        // Only fade the stock banner when our element really went up, so a failure never swallows a notification.
        if (shown && islandNotificationsHideBanner) OITIBeginBannerHide(weakDestination);
    });
}

// ---- Banner hook, installed at run time ----------------------------------------------------
// The selector that posts a banner differs between iOS versions (the one seen in a 2023 trace is not on 16.7.16), so the
// hook is found by name pattern in the class chain and installed with the runtime, only if the type encoding has one of
// the two shapes this build can forward exactly (void return, one or two object arguments). The replacement always calls
// Apple's original first. Nothing matching = nothing installed, and the candidates are logged for the next build.

static NSString *OITIFirstBannerMethodName(Class cls, const char **encodingOut, int *argsOut) {
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(c, &count);
        NSString *found = nil;
        for (unsigned int i = 0; i < count && !found; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            const char *encoding = method_getTypeEncoding(methods[i]);
            if (!encoding || ![name hasPrefix:@"postNotificationRequest"]) continue;
            if (strcmp(encoding, "v32@0:8@16@24") == 0) { found = name; *argsOut = 2; *encodingOut = encoding; }
            else if (strcmp(encoding, "v24@0:8@16") == 0) { found = name; *argsOut = 1; *encodingOut = encoding; }
        }
        free(methods);
        if (found) return found;
    }
    return nil;
}

// Logs every method in the class chain that looks related to posting or presenting a banner (selector and encoding).
static void OITILogBannerCandidates(Class cls) {
    NSArray<NSString *> *keywords = @[@"post", @"present", @"request", @"banner", @"notification", @"modify", @"add"];
    NSUInteger lines = 0;
    for (Class c = cls; c && c != [NSObject class] && lines < 160; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(c, &count);
        [sLog logTag:@"NOTIF" format:@"CANDIDATES %@: %u method(s)", NSStringFromClass(c), count];
        for (unsigned int i = 0; i < count && lines < 160; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            BOOL related = NO;
            for (NSString *keyword in keywords) {
                if ([name rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) { related = YES; break; }
            }
            if (!related) continue;
            [sLog logTag:@"NOTIF" format:@"  %@ [%s]", name, method_getTypeEncoding(methods[i]) ?: "?"];
            lines++;
        }
        free(methods);
    }
}

// ---- Promotion guard --------------------------------------------------------------------------
// poc2's element made -[SAUISystemApertureManager _reevaluatePromotedElements] throw inside -[NSArray insertObject:atIndex:],
// which took SpringBoard down on the next layout pass. While one of OITI's elements is live, the exception is caught and
// logged (name, reason, first stack symbols), the element is invalidated and creation is switched off until a respring.
// With none of OITI's elements live the exception is rethrown untouched, so Apple's own behavior never changes.
static void OITIInstallPromotionGuard(void) {
    Class managerClass = NSClassFromString(@"SAUISystemApertureManager");
    SEL selector = NSSelectorFromString(@"_reevaluatePromotedElements");
    Method method = managerClass ? class_getInstanceMethod(managerClass, selector) : NULL;
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!encoding || strcmp(encoding, "v16@0:8") != 0) {
        [sLog logTag:@"ELEMENT" format:@"promotion guard NOT installed: method=%d encoding=%s", method != NULL, encoding ?: "(none)"];
        return;
    }
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id receiver) {
        @try {
            ((void (*)(id, SEL))original)(receiver, selector);
        } @catch (NSException *exception) {
            if (!sIslandNoticeItems.count) @throw;
            NSArray *stack = exception.callStackSymbols;
            [sLog logTag:@"ELEMENT" format:@"GUARD caught %@: %@", exception.name, exception.reason];
            for (NSUInteger i = 0; i < MIN(stack.count, (NSUInteger)10); i++) {
                [sLog logTag:@"ELEMENT" format:@"GUARD   %@", stack[i]];
            }
            if (++sPoCFailureCount >= 5) sPoCDisabledAfterFailure = YES;
            id registered = OITIKVCObject(receiver, @"registeredElements");
            if ([registered conformsToProtocol:@protocol(NSFastEnumeration)]) {
                NSUInteger shown = 0;
                for (id element in registered) {
                    if (shown++ >= 12) break;
                    [sLog logTag:@"ELEMENT" format:@"GUARD element %@", OITIElementValuesSummary(element)];
                    [sLog logTag:@"ELEMENT" format:@"GUARD parts   %@", OITIElementPartsSummary(element)];
                }
            }
            NSArray<NSDictionary *> *items = [sIslandNoticeItems copy];
            [sIslandNoticeItems removeAllObjects];
            for (NSDictionary *item in items) OITIDismissNoticeItem(item);
            if (sDownloadItem) OITIDownloadItemRemoved(sDownloadItem, @"promotion-guard");
            OITIClearElementBreadcrumb();   // the exception was caught and the elements dismissed: SpringBoard is fine
        }
    });
    class_replaceMethod(managerClass, selector, replacement, encoding);
    [sLog logTag:@"ELEMENT" format:@"promotion guard installed on -[SAUISystemApertureManager _reevaluatePromotedElements]"];
}

static void OITIInstallIslandNotificationHooks(void) {
    OITIInstallPromotionGuard();
    Class destinationClass = NSClassFromString(@"SBNotificationBannerDestination");
    if (!destinationClass) {
        [sLog logTag:@"NOTIF" format:@"banner hook NOT installed: SBNotificationBannerDestination not found"];
        return;
    }
    const char *encoding = NULL;
    int argCount = 0;
    NSString *name = OITIFirstBannerMethodName(destinationClass, &encoding, &argCount);
    if (!name) {
        [sLog logTag:@"NOTIF" format:@"banner hook NOT installed: no postNotificationRequest* method with a supported shape. Candidates follow."];
        OITILogBannerCandidates(destinationClass);
        return;
    }
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(destinationClass, selector);
    IMP original = method ? method_getImplementation(method) : NULL;
    if (!original) {
        [sLog logTag:@"NOTIF" format:@"banner hook NOT installed: %@ has no implementation", name];
        return;
    }
    IMP replacement;
    if (argCount == 2) {
        replacement = imp_implementationWithBlock(^(id receiver, id request, id other) {
            ((void (*)(id, SEL, id, id))original)(receiver, selector, request, other);
            OITIHandleBannerRequest(receiver, request);
        });
    } else {
        replacement = imp_implementationWithBlock(^(id receiver, id request) {
            ((void (*)(id, SEL, id))original)(receiver, selector, request);
            OITIHandleBannerRequest(receiver, request);
        });
    }
    class_replaceMethod(destinationClass, selector, replacement, encoding);
    [sLog logTag:@"NOTIF" format:@"banner hook installed on -[%@ %@] (encoding %s)", NSStringFromClass(destinationClass), name, encoding];
}

%group OITIResearchHooks

%hook SBSystemApertureController

- (id)initWithWindowScene:(id)scene {
    id result = %orig;
    if (result) sSystemApertureController = result;
    return result;
}

- (id)registerElement:(id)element {
    if (!sSystemApertureController) sSystemApertureController = self;
    id result = %orig;
    BOOL chargingElement = OITIIsChargingSystemElement(element);
    if (sStartupHelloObservationWindowOpen && islandStartupHelloEnabled &&
        !OITIIsOurElement(element) && !OITIIsBaselineLockElement(element) && !chargingElement) {
        sStartupHelloActivitySeen = YES;
        [sLog logLevel:1 tag:@"HELLO" format:@"startup activity observed before prototype presentation: %@ identifier=%@",
         OITIObjectSummary(element), OITIKVCObject(element, @"elementIdentifier")];
    }
    if (sStartupHelloItem && element != sStartupHelloItem[@"element"] && !OITIIsOurElement(element)) {
        [sLog logLevel:1 tag:@"HELLO" format:@"system activity registered during startup playback: %@ identifier=%@",
         OITIObjectSummary(element), OITIKVCObject(element, @"elementIdentifier")];
        if (chargingElement) {
            [sLog logLevel:1 tag:@"HELLO" format:@"charging activity retained until startup playback finishes"];
        } else {
            OITICancelStartupHello(@"system-element-registration");
        }
    }
    return result;
}

%end

%end

%group OITIDiagnosticHooks

%hook SBSystemApertureProvidedContentElement

- (instancetype)initWithIdentifier:(id)identifier contentProvider:(id)contentProvider {
    id result = %orig;
    if ([sLog isLoggingAtLevel:1]) {
        if (identifier && ![identifier isKindOfClass:[NSString class]]) OITIProbeObject(identifier, @"identifier");
        OITIProbeObject(contentProvider, @"contentProvider");
        OITIProbeObject(result, @"element");
    }
    OITLOGGER_LOG_RATED(sLog, 1, @"APERTURE", @"element-init", 8,
        @"ELEMENT init identifier=%@ provider=%@ result=%@",
        OITIObjectSummary(identifier), OITIObjectSummary(contentProvider), OITIObjectSummary(result));
    return result;
}

- (BOOL)respondsToSelector:(SEL)selector {
    BOOL result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element respondsToSelector:%@ -> %d", NSStringFromSelector(selector), result]);
    return result;
}

- (BOOL)conformsToProtocol:(Protocol *)protocol {
    BOOL result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element conformsToProtocol:%s -> %d", protocol_getName(protocol), result]);
    return result;
}

- (BOOL)isKindOfClass:(Class)cls {
    BOOL result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element isKindOfClass:%@ -> %d", NSStringFromClass(cls), result]);
    return result;
}

- (id)viewProvider {
    id result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element viewProvider -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

- (id)element {
    id result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element element -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

- (id)elementHost {
    id result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element elementHost -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

- (id)layoutHost {
    id result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element layoutHost -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

%end

%hook SAUIElementViewController

- (id)initWithElementViewProvider:(id)provider {
    id result = %orig;
    if (sIslandNoticeItems.count && [sLog isLoggingAtLevel:1]) {
        [sLog logTag:@"ELEMENT" format:@"VCINIT provider=%@(%@) -> %@", NSStringFromClass([provider class]),
         OITIKVCObject(provider, @"elementIdentifier"), result ? OITIObjectSummary(result) : @"nil"];
    }
    return result;
}

%end

%hook SBSystemApertureElementAuthority

- (id)elementsOrderedByPromotionFromTemporallyOrderedElements:(id)elements withPreviousOrdering:(id)previous {
    id result = %orig;
    if (sStartupHelloItem && [result isKindOfClass:[NSArray class]]) {
        NSMutableArray *ordered = [result mutableCopy];
        id helloElement = sStartupHelloItem[@"element"];
        NSUInteger helloIndex = [ordered indexOfObjectIdenticalTo:helloElement];
        NSUInteger chargingIndex = NSNotFound;
        for (NSUInteger i = 0; i < ordered.count; i++) {
            if (OITIIsChargingSystemElement(ordered[i])) { chargingIndex = i; break; }
        }
        if (helloIndex != NSNotFound && chargingIndex != NSNotFound && helloIndex > chargingIndex) {
            [ordered removeObjectAtIndex:helloIndex];
            [ordered insertObject:helloElement atIndex:chargingIndex];
            result = [ordered copy];
            [sLog logLevel:1 tag:@"HELLO" format:@"promoted startup animation ahead of charging activity"];
        }
    }
    if (sIslandNoticeItems.count && [sLog isLoggingAtLevel:1]) {
        [sLog logTag:@"ELEMENT" format:@"AUTH in=%@ previous=%@ out=%@", OITIElementIdentifierList(elements),
         OITIElementIdentifierList(previous), OITIElementIdentifierList(result)];
    }
    return result;
}

%end

%hook SAUISystemApertureManager

- (id)registerElement:(id)element {
    id result = %orig;
    sRegisteringManager = self;
    if (!sPoCOurRegistrationInFlight) OITICaptureRealElement(element);
    if ([sLog isLoggingAtLevel:1]) OITIProbeObject(result, @"registration");
    if ([sLog isLoggingAtLevel:1] && sObservedApertureManagers) {
        @synchronized (sObservedApertureManagers) {
            [sObservedApertureManagers addObject:self];
        }
    }
    OITLOGGER_LOG_RATED(sLog, 1, @"APERTURE", @"register-element", 8,
        @"REGISTER manager=%@ element=%@ result=%@",
        OITIObjectSummary(self), OITIObjectSummary(element), OITIObjectSummary(result));
    return result;
}

- (id)_assertionForElementCreatingIfNecessary:(id)element {
    id result = %orig;
    if (OITIIsOurElement(element)) OITITraceOnce([NSString stringWithFormat:@"manager _assertionForElementCreatingIfNecessary -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

- (id)_elementViewControllerForElement:(id)element creatingIfNecessary:(BOOL)creating {
    id result = %orig;
    if (sIslandNoticeItems.count && [sLog isLoggingAtLevel:1]) {
        [sLog logTag:@"ELEMENT" format:@"VCFOR element=%@ creating=%d -> %@", OITIKVCObject(element, @"elementIdentifier"), creating,
         result ? OITIObjectSummary(result) : @"nil"];
    }
    return result;
}

- (id)orderedElementViewControllers {
    // Cheap capture so the hello element does not need a charger or timer to have run first.
    if (!sSeenManager) sSeenManager = self;
    return %orig;
}

%end

%end

%group OITIHooks

%hook SBSystemApertureWindow

- (void)layoutSubviews {
    CGRect before = self.frame;

    if (scaleEnabled) {
        CGFloat appleScale = OITIAppleCanvasScale(self);
        CGAffineTransform wanted = CGAffineTransformMakeScale(appleScale * OITISafeScaleValue(scaleX),
                                                              appleScale * OITISafeScaleValue(scaleY));
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

    // An instance OITI changed earlier must still be visited when the setting is switched off, so it can be restored.
    if (!transEnabled && !lineDisabled && !objc_getAssociatedObject(self, kOITIPassThroughTouchedKey)) return;

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

    // Transparency. A view is OITI's to change when it is untouched (alpha 1.0, as before) or still carries the alpha
    // OITI set earlier (so a new opacity applies live). If something else changed the alpha since, it is left alone.
    UIView *targetSubview = self.subviews[2];
    NSNumber *appliedAlpha = objc_getAssociatedObject(targetSubview, kOITITransparencyAppliedKey);
    BOOL carriesOurAlpha = appliedAlpha && fabs(targetSubview.alpha - appliedAlpha.doubleValue) < 0.001;
    if (transEnabled) {
        BOOL untouched = targetSubview.alpha == 1.0 && targetSubview.userInteractionEnabled == 0;
        if (untouched || carriesOurAlpha) {
            if (fabs(targetSubview.alpha - alpha) > 0.001) {
                targetSubview.alpha = alpha;
                OITLOGGER_LOG_RATED(sLog, 2, @"TOUCHPASS", @"touchpass.trans", 4,
                                    @"transparency applied alpha=%.2f to %@", alpha, NSStringFromClass([targetSubview class]));
            }
            objc_setAssociatedObject(targetSubview, kOITITransparencyAppliedKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (appliedAlpha) {
        if (carriesOurAlpha) targetSubview.alpha = 1.0;
        objc_setAssociatedObject(targetSubview, kOITITransparencyAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Outline.
    UIView *lineView = self.subviews[1];
    BOOL lineIsOurs = objc_getAssociatedObject(lineView, kOITILineHiddenKey) != nil;
    if (lineDisabled) {
        if (lineIsOurs || (lineView.alpha == 1.0 && lineView.userInteractionEnabled == 0)) {
            if (!lineView.hidden) {
                lineView.hidden = YES;
                OITLOGGER_LOG_RATED(sLog, 2, @"TOUCHPASS", @"touchpass.line", 4,
                                    @"line hidden: %@", NSStringFromClass([lineView class]));
            }
            objc_setAssociatedObject(lineView, kOITILineHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (lineIsOurs) {
        lineView.hidden = NO;
        objc_setAssociatedObject(lineView, kOITILineHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    BOOL touched = objc_getAssociatedObject(targetSubview, kOITITransparencyAppliedKey) != nil ||
                   objc_getAssociatedObject(lineView, kOITILineHiddenKey) != nil;
    objc_setAssociatedObject(self, kOITIPassThroughTouchedKey, touched ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

    [sBannerWindows addObject:self];   // always kept (weak): the Island notification path needs the banner window
    if ([sLog isLoggingAtLevel:1]) {
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

// The root input Apple builds the Island from. Returns Apple's value times the Island Size multipliers (both 1.0 by
// default, which is an exact pass-through). The raw value is kept for the dump.
%hook SBUISystemApertureLayoutMetrics

- (CGSize)sensorRegionSize {
    CGSize size = %orig;
    sRawSensorRegionSize = size;
    return OITIApplyMetricsFactor(size, sMetricsSensorX, sMetricsSensorY);
}

%end

%end

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
        %init(OITIHooks);
        %init(OITIResearchHooks);
        if (sLog.enabled && sLog.level >= 1) {
            %init(OITIDiagnosticHooks);
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
