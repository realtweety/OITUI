// OITIStatusBar.h -- what other OITI files use of the StatusBar module (v0.3.0 module split, round 6).
//
// The module is OITIStatusBarProvider.xm. Everything below is declared here because Tweak.xm (the %ctor) or the Diagnostics
// files use it; every other helper is static in the module file. The declarations are copies of the definitions.

#import "Shared/OITIShared.h"

NSString *OITINativeProviderNameForScreen(UIScreen *screen, NSString **source);
NSString *OITILearnedNativeProviderName(void);

// State the %ctor in Tweak.xm sets up before the hooks install.
extern BOOL sIslandEnabledAtLaunch;
extern NSMutableSet<NSString *> *sLoggedProviderChoices;
extern NSHashTable *sLoggedStatusBars;

void OITIInstallStatusBarHooks(void);   // initialises the OITIStatusBarHooks group
