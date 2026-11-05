// OITIPositionLimits.h -- the per-device limit for the typed position settings: one screen. USES UIKit.
//
// Not for the launch path. OITIPositionLimit() calls +[UIScreen mainScreen]; calling that from %ctor or preferencesChanged() made
// SpringBoard hang at the Apple logo (v0.3.0 batch 1). Import this only from code that runs after SpringBoard is up: the layout
// and banner hooks in IslandSize/OITIIslandHooks.xm, and the Settings bundle (a different process). The launch path imports
// OITIPositionValues.h instead; tools/check_ctor_path.py fails the check if a UIKit call reaches it.
//
// Why one screen: the Island window (SBSystemApertureWindow) and the banner window (SBBannerWindow) are both full-screen canvases
// (the device table's banner size is the screen size in points: 375 x 812 ... 428 x 926), and the built-in offsets are small
// (Island Y 19.5 to 26 pt, banner Y 33 to 42 pt). A window moved by more than its own size is already entirely off screen, so
// a larger value adds nothing useful. |X| is limited to the screen width and |Y| to the screen height, in portrait points: the
// short side for X and the long side for Y, so a rotated UIScreen.bounds cannot change the answer.
#import <UIKit/UIKit.h>
#import "OITIPositionValues.h"

static inline CGFloat OITIPositionLimit(BOOL horizontal) {
    CGSize size = [UIScreen mainScreen].bounds.size;
    CGFloat limit = horizontal ? MIN(size.width, size.height) : MAX(size.width, size.height);
    return limit >= 100.0 ? limit : (CGFloat)kOITIPositionCeiling;   // an unreadable screen size must not turn into a zero limit
}

// A stored position value (already finite and inside kOITIPositionCeiling) limited to one screen, at the point of use.
static inline CGFloat OITIClampedPositionForUse(CGFloat value, BOOL horizontal) {
    return (CGFloat)OITISanitizedPosition(value, 0.0, OITIPositionLimit(horizontal));
}
