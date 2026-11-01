// OITIState.xm -- the state OITI's modules share (v0.3.0 module split, round 7).
//
// Moved from Tweak.xm unchanged: the recovery state and the MobileGestalt location, the logger and preferences objects, every
// setting the preferences reload writes and the hooks read, the weak window tables, OITIObjectSummary, OITICurrentProfile
// and the preferences snapshot helpers. All are declared in Shared/OITIShared.h (they lost their `static` when each module was
// cut out).

#import "Shared/OITIShared.h"
#import "DownloadProgress/OITIDownloadProgress.h"   // the preferences snapshot reads the download settings

// Exists while one of OITI's Island elements is live (see ELEMENT CRASH RECOVERY above).
NSString * const kOITILiveElementPath = @"/var/mobile/Library/Preferences/OITILiveElement.plist";
const NSTimeInterval kOITIElementRecoveryWindow = 120.0;
CFAbsoluteTime sElementRecoveryUntil = 0;     // while in the future, no Island element is created
BOOL sLaunchWasRequestedRespring = NO;        // this launch followed a respring asked for in OITI's settings
NSString * const kOITIGestaltPlistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
NSString * const kOITIGestaltCacheExtraKey = @"CacheExtra";
NSString * const kOITIGestaltNestedKey = @"oPeik/9e8lQWMszEjbPzng";
NSString * const kOITIGestaltLeafKey = @"ArtworkDeviceSubType";


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
CGFloat sIslandNoticeDuration = 4.0;   // seconds, key IslandNotificationsDuration, clamped 1 - 15



// Shared state: declared in Shared/OITIShared.h.
OITLogger *sLog;
// Weak references: the research hooks observe Apple's manager but must not keep it alive.
NSHashTable *sObservedApertureManagers;
OITPreferences *sOITIPreferences;
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




// Resolved once. NULL means "this device has no built-in offsets" (for example an iPhone 8 / 8 Plus).
const OITIDeviceProfile *OITICurrentProfile(void) {
    static const OITIDeviceProfile *profile;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        profile = OITIProfileForModel([OITDeviceInfo machineIdentifier]);
    });
    return profile;
}


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
