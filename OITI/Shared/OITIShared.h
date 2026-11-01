// OITIShared.h -- state and helpers that more than one OITI source file uses (v0.3.0 module split).
//
// Round 1 (Diagnostics) started this header with exactly what the Diagnostics files need. The definitions live in
// Shared/OITIState.xm (the build tag is the one exception: it is defined in Tweak.xm). Each module round added what that
// module needs; nothing was added "just in case".
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

// More shared state (defined in Shared/OITIState.xm): the Apple Mode switch, the relative scale, the live Island windows,
// the Island notification stack and the download element that the presenter keeps.
extern BOOL sAppleMode;
extern CGFloat scaleX;
extern CGFloat scaleY;
extern NSHashTable<UIView *> *sLiveApertureWindows;
extern NSMutableArray<NSDictionary *> *sIslandNoticeItems;
extern NSMutableDictionary *sDownloadItem;
extern CFAbsoluteTime sDownloadShownAt;
extern NSUInteger sDownloadDropCount;

// The Island appearance and position settings. The preferences reload (Shared/OITIPreferences.xm) writes them, the hooks read them.
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

// The preferences reload (Shared/OITIPreferences.xm), called by the %ctor.
void preferencesChanged(void);

// Helpers.
NSString *OITIObjectSummary(id object);
const OITIDeviceProfile *OITICurrentProfile(void);
NSDictionary<NSString *, NSNumber *> *OITIPrefSnapshot(void);
NSString *OITIPrefSnapshotString(NSDictionary<NSString *, NSNumber *> *snapshot);

// The test element is in IslandNotifications/ (the status bar provider helpers are declared in StatusBar/OITIStatusBar.h).
void OITIRunPoCElement(NSString *reason);

// The Island notification element machinery (IslandNotifications/). The stack view is declared here because the download views build one.
@interface OITINoticeStackView : UIStackView
@end
void OITIRemoveNoticeItem(NSDictionary *item, NSString *reason);
BOOL OITIPresentNoticeElement(NSDictionary<NSString *, NSString *> *info, NSString *reason);

// Shared/OITIRuntimeHelpers.xm: exception-safe readers for private runtime objects.
id OITISafeObject(id object, NSString *selectorName);
NSString *OITISafeString(id object, NSString *selectorName);
id OITIKVCObject(id object, NSString *key);
BOOL OITISafeBool(id object, NSString *selectorName, BOOL *available);
NSString *OITIInstallIvarScalarText(id object, Ivar ivar, const char *type, double *numberOut);
id OITIInstallObjectGetter(id object, NSString *selectorName);
id OITIInstallSharedInstance(Class cls, NSString **how);
id OITIInstallApplicationForBundleID(id applicationController, NSString *bundleID);

// More shared state that the Island notification files use (defined in Shared/OITIState.xm): the notification settings and the
// breadcrumb state. (The Hello startup animation declarations moved to Startup/OITIStartup.h in round 5.)

extern NSString * const kOITILiveElementPath;
extern const NSTimeInterval kOITIElementRecoveryWindow;
extern CFAbsoluteTime sElementRecoveryUntil;
extern BOOL sLaunchWasRequestedRespring;
extern BOOL islandNotificationsEnabled;
extern BOOL islandNotificationsHideBanner;
extern BOOL sIslandNotificationStackEnabled;
extern CGFloat sIslandNoticeDuration;

// The MobileGestalt cache location and keys (defined in Shared/OITIState.xm). The startup self-check (Safety/) and
// StatusBar/OITIStatusBarProvider.xm both use them; OITIMachineHasNativeIsland is declared in Safety/OITISafety.h.
extern NSString * const kOITIGestaltPlistPath;
extern NSString * const kOITIGestaltCacheExtraKey;
extern NSString * const kOITIGestaltNestedKey;
extern NSString * const kOITIGestaltLeafKey;
