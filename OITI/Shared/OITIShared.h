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

// Helpers.
NSString *OITIObjectSummary(id object);
const OITIDeviceProfile *OITICurrentProfile(void);
NSDictionary<NSString *, NSNumber *> *OITIPrefSnapshot(void);
NSString *OITIPrefSnapshotString(NSDictionary<NSString *, NSNumber *> *snapshot);

// Defined in Tweak.xm until their modules move: the status bar provider choice and the Island Notifications test element.
NSString *OITINativeProviderNameForScreen(UIScreen *screen, NSString **source);
NSString *OITILearnedNativeProviderName(void);
void OITIRunPoCElement(NSString *reason);
