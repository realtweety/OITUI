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
//                  than one file uses). The definitions of that shared state are in Shared/OITIState.xm,
//                  the preferences reload is Shared/OITIPreferences.xm.
//   DownloadProgress/  the download tracker, the Minimal pill, the progress views and the App Store source (done, round 2).
//   IslandSize/        the Island's position, size, scale and appearance hooks (done, round 3).
//   IslandNotifications/  Island notifications: the presenter, element, views, banner hide, actions and hooks (done, round 4).
//   Startup/       the Hello startup animation: video view, readiness checks, cooldown, runner (done, round 5).
//   StatusBar/     the status bar provider choice and the OITIStatusBarHooks group (done, round 6).
//   Safety/        the respring-loop guard (safe mode) and the startup self-check of the MobileGestalt spoof (done, round 7).
//   This file keeps the documentation above, the build tag and the %ctor that installs everything. Imports are relative to the
//   OITI folder.

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
#import "Startup/OITIStartup.h"
#import "StatusBar/OITIStatusBar.h"
#import "Safety/OITISafety.h"


extern NSString * const kOITIBuildTag = @"OITI-exp-2026-10-26-a";
static NSString * const kOITIPrefsChangedNotification = @"com.wilburt.oiti/PrefsChanged";
static NSString * const kOITIClearSafeModeNotification = @"com.wilburt.oiti/ClearSafeMode";
static NSString * const kOITITestDownloadStartNotification = @"com.wilburt.oiti/TestDownloadStart";
static NSString * const kOITITestDownloadStopNotification = @"com.wilburt.oiti/TestDownloadStop";
static NSString * const kOITILogPath = @"/tmp/OITIDebug.log";

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
        OITIInstallStatusBarHooks();
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
