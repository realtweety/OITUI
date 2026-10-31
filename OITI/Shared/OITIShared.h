// OITIShared.h -- state and helpers that more than one OITI source file uses (v0.3.0 module split).
//
// Round 1 (Diagnostics) starts this header with exactly what the Diagnostics files need. The definitions still live in
// Tweak.xm (their `static` was dropped, nothing else changed) and move into Shared/ in the round that builds the core.
// Each module round adds what that module needs; nothing is added "just in case".
//
// Every OITI source file imports with paths relative to the OITI folder ("Shared/...", "Diagnostics/..."); the Makefile
// puts that folder on the include path (-I.).

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
#import "Shared/OITIApplePrivate.h"

// Build tag, logger and preferences.
extern NSString * const kOITIBuildTag;
extern OITLogger *sLog;
extern OITPreferences *sOITIPreferences;

// State the hooks keep and the dumps read.
extern BOOL sSafeModeActive;
extern BOOL islandEnabled;
extern NSHashTable *sObservedApertureManagers;
extern NSHashTable<UIView *> *sApertureWindows;
extern NSHashTable<UIView *> *sBannerWindows;
extern CGFloat sMetricsSensorX;
extern CGFloat sMetricsSensorY;
extern CGSize sRawSensorRegionSize;

// More state that Tweak.xm still defines (round 2): the Apple Mode switch, the relative scale, the live Island windows,
// the Island notification stack and the download element that the presenter keeps.
extern BOOL sAppleMode;
extern CGFloat scaleX;
extern CGFloat scaleY;
extern NSHashTable<UIView *> *sLiveApertureWindows;
extern NSMutableArray<NSDictionary *> *sIslandNoticeItems;
extern NSMutableDictionary *sDownloadItem;
extern CFAbsoluteTime sDownloadShownAt;
extern NSUInteger sDownloadDropCount;

// The Island appearance and position settings. The preferences reload in Tweak.xm writes them, the hooks read them.
extern CGFloat red;
extern CGFloat green;
extern CGFloat blue;
extern CGFloat alpha;
extern CGFloat xPos;
extern CGFloat yPos;
extern CGFloat xNot;
extern CGFloat yNot;
extern BOOL fixEnabled;
extern BOOL posEnabled;
extern BOOL hideEnabled;
extern BOOL notificationFix;
extern BOOL notEnabled;
extern BOOL colorEnabled;
extern BOOL transEnabled;
extern BOOL scaleEnabled;
extern BOOL lineDisabled;

// Helpers.
NSString *OITIObjectSummary(id object);
const OITIDeviceProfile *OITICurrentProfile(void);
NSDictionary<NSString *, NSNumber *> *OITIPrefSnapshot(void);
NSString *OITIPrefSnapshotString(NSDictionary<NSString *, NSNumber *> *snapshot);

// Defined in Tweak.xm until its module moves: the status bar provider choice. The test element is in IslandNotifications/.
NSString *OITINativeProviderNameForScreen(UIScreen *screen, NSString **source);
NSString *OITILearnedNativeProviderName(void);
void OITIRunPoCElement(NSString *reason);

// The Island notification element machinery (IslandNotifications/). The stack view is declared here because the download views build one.
@interface OITINoticeStackView : UIStackView
@end
void OITIRemoveNoticeItem(NSDictionary *item, NSString *reason);
BOOL OITIPresentNoticeElement(NSDictionary<NSString *, NSString *> *info, NSString *reason);
BOOL OITISafeBool(id object, NSString *selectorName, BOOL *available);

// More of Tweak.xm that the Island notification files use, until their own rounds: the notification and startup settings, the
// breadcrumb state and the Hello startup animation (round 5).

@interface OITIStartupVideoView : UIView
@property (nonatomic, strong, readonly) AVPlayer *player;
- (instancetype)initWithURL:(NSURL *)url;
- (NSTimeInterval)mediaDuration;
- (void)startPlayback;
- (void)stopPlayback;
@end
extern const NSTimeInterval kOITIStartupHelloPrototypeDuration;
extern NSString * const kOITILiveElementPath;
extern const NSTimeInterval kOITIElementRecoveryWindow;
extern CFAbsoluteTime sElementRecoveryUntil;
extern BOOL sLaunchWasRequestedRespring;
extern BOOL islandNotificationsEnabled;
extern BOOL islandNotificationsHideBanner;
extern BOOL sIslandNotificationStackEnabled;
extern BOOL islandStartupHelloEnabled;
extern BOOL sStartupHelloObservationWindowOpen;
extern BOOL sStartupHelloActivitySeen;
extern CGFloat sIslandNoticeDuration;
extern NSMutableDictionary *sStartupHelloItem;
void OITICancelStartupHello(NSString *reason);
OITIStartupVideoView *OITIBuildStartupVideoView(void);
