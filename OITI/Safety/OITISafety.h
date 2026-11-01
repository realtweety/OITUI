// OITISafety.h -- what other OITI files use of the Safety module (v0.3.0 module split, round 7).
//
// The module is OITISafety.xm: the respring-loop guard and the startup self-check. Declared here because the %ctor in
// Tweak.xm, the preferences reload and the status bar code use them; the declarations are copies of the definitions.

#import "Shared/OITIShared.h"

// The state files the guard reads and the %ctor's ClearSafeMode observer removes.
extern NSString * const kOITIBootLogPath;
extern NSString * const kOITISafeModePath;

// Guard settings (prefs keys listed in the header comment of Tweak.xm); the preferences reload writes them.
extern BOOL sGuardEnabled;
extern NSInteger sGuardMaxLaunches;
extern NSInteger sGuardWindowSeconds;
extern NSInteger sGuardStableSeconds;
extern BOOL sGuardRestoreGestalt;

BOOL OITIEvaluateLoopGuard(void);        // YES = safe mode (hooks are not installed)
void OITIRunStartupSelfCheck(void);
BOOL OITIMachineHasNativeIsland(NSString *machine);
