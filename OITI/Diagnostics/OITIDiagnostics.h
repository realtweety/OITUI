// OITIDiagnostics.h -- the Diagnostics module's functions that other files call (v0.3.0 module split, round 1).
//
// Everything in OITI/Diagnostics is read-only, gated behind DiagnosticsLevel (see DIAGNOSTICS.md) and changes nothing
// on screen. This header lists only what is used across files; every other helper is static in its own file.

#import "Shared/OITIShared.h"

// OITIDump.xm
NSString *OITIColorDesc(UIColor *color);
NSString *OITIViewLine(UIView *view);
void OITIDumpMethods(Class cls, NSString *kind);
void OITIRunDump(NSString *reason);

// OITIStatusBarDiagnostic.xm
void OITIRunStatusBarDiagnostic(NSString *reason);

// OITIInstallDump.xm
NSString *OITIInstallIvarScalarText(id object, Ivar ivar, const char *type, double *numberOut);
id OITIInstallObjectGetter(id object, NSString *selectorName);
id OITIInstallSharedInstance(Class cls, NSString **how);
id OITIInstallApplicationForBundleID(id applicationController, NSString *bundleID);
void OITIRunInstallDump(NSString *reason);

// OITIDumpTriggers.xm
void OITIUpdateDumpTrigger(void);
void OITIObserveDumpNotification(void);
void OITIScheduleAutoDump(void);
