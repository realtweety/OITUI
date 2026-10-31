// OITIIslandSize.h -- what other files use of the IslandSize module (v0.3.0 module split, round 3).

#import "Shared/OITIShared.h"

// OITIIslandHooks.xm
CGFloat OITIClampMetricsFactor(CGFloat value);   // keeps an Island size multiplier in a safe range
void OITIInstallIslandSizeHooks(void);            // initialises the OITIHooks group
