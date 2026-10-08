// OITI -- Dynamic Island positioning/appearance module for OITUI (fork of VisibleIsland by ethxnn88).
//
// Step 1 cleanup (behavior-preserving except where marked "FIX"):
//  * The six copy-pasted per-device if/else chains are replaced by one table (OITIDeviceProfiles.h), shared
//    with the prefs bundle. A script verified that all six chains agreed for every device before removal.
//  * -layoutSubviews on SBSystemApertureWindow runs %orig exactly once (it used to run twice).
//  * Hooks that replaced Apple's didMoveToWindow now call %orig.
//  * Prefs defaults now match the intended globals.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <math.h>
#import <OITCore/OITCore.h>
#import "OITIDeviceProfiles.h"

static CGFloat red = 0.0;
static CGFloat green = 0.0;
static CGFloat blue = 0.0;
static CGFloat alpha = 1.0;

static CGFloat scale = 1.0;

static CGFloat xPos = 0;
static CGFloat yPos = 20.5;
static CGFloat xNot = 0.0;
static CGFloat yNot = 40;

static BOOL fixEnabled;
static BOOL islandEnabled __attribute__((unused));   // read by the prefs UI; reserved for the Step 2 startup self-check
static BOOL posEnabled;
static BOOL hideEnabled;
static BOOL notificationFix;
static BOOL notEnabled;
static BOOL colorEnabled;
static BOOL transEnabled;
static BOOL scaleEnabled;
static BOOL lineDisabled;

static const void *kOITIAppliedScaleKey = &kOITIAppliedScaleKey;
static const void *kOITIHiddenByUsKey = &kOITIHiddenByUsKey;
static const void *kOITIColorAppliedKey = &kOITIColorAppliedKey;

@interface SBSystemApertureWindow : UIView
@end

@interface _SBSystemApertureMagiciansCurtainView : UIView
@end

@interface SBBannerWindow : UIView
@end

@interface _SBGainMapView : UIView
@end

@interface _SBSystemApertureContainerViewContentView : UIView
@end

@interface SBFTouchPassThroughView : UIView
@end

static CGFloat OITISafeScaleValue(CGFloat value) {
    if (!isfinite(value)) return 1.0;
    if (value < 0.05) return 1.0;
    if (value > 3.0) return 3.0;
    return value;
}

// Resolved once. NULL means "this device has no built-in offsets" (for example an iPhone 8 / 8 Plus).
static const OITIDeviceProfile *OITICurrentProfile(void) {
    static const OITIDeviceProfile *profile;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        profile = OITIProfileForModel([OITDeviceInfo machineIdentifier]);
    });
    return profile;
}

// Moves the Island window to the built-in (fixEnabled) or custom (posEnabled) position.
// The built-in table wins when both are on, as before. FIX: on a device with no table entry, "fixEnabled" used to
// do nothing at all even if custom position was also on; now the custom position applies.
static void OITIApplyIslandPosition(UIView *window) {
    CGFloat s = scaleEnabled ? OITISafeScaleValue(scale) : 1.0;   // FIX: the divisor used the raw, unclamped scale
    CGRect frame = window.frame;
    const OITIDeviceProfile *profile = fixEnabled ? OITICurrentProfile() : NULL;

    if (profile) {
        frame.origin.y = profile->islandY / s;
    } else if (posEnabled) {
        frame.origin.y = yPos / s;
        // Original behavior: with scaling on, only override x when it is set; without scaling, always set it.
        if (!scaleEnabled || xPos > 0) frame.origin.x = xPos / s;
    } else {
        return;
    }

    if (!CGRectEqualToRect(frame, window.frame)) window.frame = frame;
}

%hook SBSystemApertureWindow

- (void)layoutSubviews {
    if (scaleEnabled) {
        CGFloat s = OITISafeScaleValue(scale);
        CGAffineTransform wanted = CGAffineTransformMakeScale(s, s);
        if (!CGAffineTransformEqualToTransform(self.transform, wanted)) self.transform = wanted;
        objc_setAssociatedObject(self, kOITIAppliedScaleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (objc_getAssociatedObject(self, kOITIAppliedScaleKey)) {
        // FIX: turning scaling off used to leave the old transform in place until a respring.
        self.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(self, kOITIAppliedScaleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    %orig;
    OITIApplyIslandPosition(self);
}

%end

%hook _SBSystemApertureMagiciansCurtainView

- (void)didMoveToWindow {
    %orig;   // FIX: was missing
    BOOL shouldHide = fixEnabled || posEnabled || scaleEnabled;
    if (shouldHide) {
        if (!self.hidden) self.hidden = YES;
        objc_setAssociatedObject(self, kOITIHiddenByUsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (objc_getAssociatedObject(self, kOITIHiddenByUsKey)) {
        // FIX: only undo our own hiding, instead of force-unhiding a view Apple may have hidden itself.
        self.hidden = NO;
        objc_setAssociatedObject(self, kOITIHiddenByUsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

%hook _SBGainMapView

- (void)didMoveToWindow {
    %orig;   // FIX: was missing
    if (hideEnabled && self.superview) {
        [self removeFromSuperview];
    }
}

%end

%hook _SBSystemApertureContainerViewContentView

- (void)layoutSubviews {
    UIColor *backgroundColor = [self backgroundColor];
    BOOL ours = objc_getAssociatedObject(self, kOITIColorAppliedKey) != nil;

    if (colorEnabled) {
        // Only touch the color when nothing set one, or when the color is the one we applied earlier
        // (so changing the color in prefs now takes effect without a respring).
        if (!backgroundColor || ours) {
            UIColor *customColor = [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
            if (!backgroundColor || ![backgroundColor isEqual:customColor]) {
                [self setBackgroundColor:customColor];
            }
            objc_setAssociatedObject(self, kOITIColorAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (ours) {
        [self setBackgroundColor:nil];
        objc_setAssociatedObject(self, kOITIColorAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
}

%end

%hook SBFTouchPassThroughView

- (void)layoutSubviews {
    %orig;

    if (!transEnabled && !lineDisabled) return;

    // SBFTouchPassThroughView is used pervasively throughout SpringBoard (Dock, folders, notification banners,
    // home screen icons, etc.), and the subviews.count == 4 heuristic below is NOT specific enough on its own.
    // Scoping to instances actually inside SBSystemApertureWindow avoids matching unrelated views.
    // KNOWN FRAGILE: the index-based subview picks may change between iOS versions.
    static Class apertureWindowClass;
    if (!apertureWindowClass) apertureWindowClass = NSClassFromString(@"SBSystemApertureWindow");
    if (!apertureWindowClass || !OITViewHasAncestorOfClass(self, apertureWindowClass)) return;

    if (self.subviews.count != 4) return;

    if (transEnabled) {
        UIView *targetSubview = self.subviews[2];
        if (targetSubview.alpha == 1.0 && targetSubview.userInteractionEnabled == 0) {
            targetSubview.alpha = alpha;
        }
    }
    if (lineDisabled) {
        UIView *lineView = self.subviews[1];
        if (lineView.alpha == 1.0 && lineView.userInteractionEnabled == 0) {
            lineView.hidden = YES;
        }
    }
}

%end

// Notification banner window position. Returns YES and fills `out` when an override applies.
//  - notificationFix: use the device's built-in banner position. Devices with no table entry are left untouched
//    (FIX: -setFrame: used to be swallowed entirely on such devices, so banners never got a frame at all).
//  - notEnabled: custom origin (xNot, yNot). FIX: devices with no table entry now keep the system's size instead of
//    being ignored.
static BOOL OITIBannerFrame(CGRect incoming, CGRect *out) {
    const OITIDeviceProfile *profile = OITICurrentProfile();
    if (notificationFix) {
        if (!profile) return NO;
        *out = CGRectMake(0, profile->bannerY, profile->bannerWidth, profile->bannerHeight);
        return YES;
    }
    if (notEnabled) {
        CGSize size = profile ? CGSizeMake(profile->bannerWidth, profile->bannerHeight) : incoming.size;
        *out = CGRectMake(xNot, yNot, size.width, size.height);
        return YES;
    }
    return NO;
}

%hook SBBannerWindow

- (CGRect)frame {
    CGRect original = %orig;
    CGRect overridden;
    return OITIBannerFrame(original, &overridden) ? overridden : original;
}

- (void)setFrame:(CGRect)frame {
    CGRect overridden;
    %orig(OITIBannerFrame(frame, &overridden) ? overridden : frame);
}

%end

static OITPreferences *sOITIPreferences;

static void preferencesChanged(void) {
    if (!sOITIPreferences) {
        sOITIPreferences = [OITPreferences preferencesWithDomain:@"com.wilburt.oiti.prefs"];
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

    // FIX: these defaults used to be 0.0 while the globals above say 20.5 / 40 / 1.0, so enabling a feature without
    // touching its slider gave a transparent color, Island at y = 0, or banner at y = 0.
    xPos = [sOITIPreferences floatForKey:@"xPos" default:0.0];
    yPos = [sOITIPreferences floatForKey:@"yPos" default:20.5];
    xNot = [sOITIPreferences floatForKey:@"xNot" default:0.0];
    yNot = [sOITIPreferences floatForKey:@"yNot" default:40.0];
    red = [sOITIPreferences floatForKey:@"red" default:0.0];
    green = [sOITIPreferences floatForKey:@"green" default:0.0];
    blue = [sOITIPreferences floatForKey:@"blue" default:0.0];
    alpha = [sOITIPreferences floatForKey:@"alpha" default:1.0];
    scale = [sOITIPreferences floatForKey:@"scale" default:1.0];
}

%ctor {
    preferencesChanged();

    OITObserveDarwinNotification(@"com.wilburt.oiti/PrefsChanged", ^{
        preferencesChanged();
    });
}
