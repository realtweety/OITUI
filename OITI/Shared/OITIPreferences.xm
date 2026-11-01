// OITIPreferences.xm -- the preferences reload (v0.3.0 module split, round 7).
//
// Moved from Tweak.xm unchanged: preferencesChanged reads every OITI setting from com.wilburt.oiti.prefs into the variables
// declared in Shared/OITIShared.h and the modules' headers, logs what changed and asks the modules to refresh. The %ctor in
// Tweak.xm calls it at launch and on the PrefsChanged Darwin notification, so it lost its `static`.

#import "Shared/OITIShared.h"
#import "Safety/OITISafety.h"
#import "Diagnostics/OITIDiagnostics.h"
#import "DownloadProgress/OITIDownloadProgress.h"
#import "IslandSize/OITIIslandSize.h"
#import "IslandNotifications/OITIIslandNotifications.h"
#import "Startup/OITIStartup.h"
#import "StatusBar/OITIStatusBar.h"

static NSString * const kOITIPrefsDomain = @"com.wilburt.oiti.prefs";
static NSDictionary<NSString *, NSNumber *> *sLastPrefSnapshot;

void preferencesChanged(void) {
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
