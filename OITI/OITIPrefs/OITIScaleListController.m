#import "OITIScaleListController.h"
#import <OITCore/OITCore.h>
#import <math.h>

static NSString * const kOITIScalePrefsDomain = @"com.wilburt.oiti.prefs";
static NSString * const kOITIScalePrefsChangedNotification = @"com.wilburt.oiti/PrefsChanged";

// Slider range in Scale.plist. A migrated value is kept inside it so the slider can show it.
static const CGFloat kOITIScaleSliderMin = 0.5;
static const CGFloat kOITIScaleSliderMax = 2.0;

@implementation OITIScaleListController

- (NSString *)oiti_plistName {
    return @"Scale";
}

// The single "scale" setting was replaced by separate width (scaleX) and height (scaleY) sliders. The first time
// this page loads, carry an existing single scale over to both, so the sliders start where the Island already is
// instead of showing 1.0 while the Island is scaled. The tweak also falls back to the old value when scaleX/scaleY
// are not set, so nothing changes visually if this page is never opened.
+ (void)oiti_migrateLegacyScaleIfNeeded {
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIScalePrefsDomain];
    BOOL haveX = [prefs objectForKey:@"scaleX" default:nil] != nil;
    BOOL haveY = [prefs objectForKey:@"scaleY" default:nil] != nil;
    if (haveX && haveY) return;

    CGFloat legacy = [prefs floatForKey:@"scale" default:1.0];
    if (!isfinite(legacy)) legacy = 1.0;
    legacy = MAX(kOITIScaleSliderMin, MIN(kOITIScaleSliderMax, legacy));

    if (!haveX) [prefs setObject:@(legacy) forKey:@"scaleX"];
    if (!haveY) [prefs setObject:@(legacy) forKey:@"scaleY"];
    [prefs synchronize];
    OITPostDarwinNotification(kOITIScalePrefsChangedNotification);
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        // Runs before the sliders read their values.
        [OITIScaleListController oiti_migrateLegacyScaleIfNeeded];
    }
    return [super specifiers];
}

- (void)resetScale {
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIScalePrefsDomain];
    [prefs setObject:@1.0 forKey:@"scaleX"];
    [prefs setObject:@1.0 forKey:@"scaleY"];
    [prefs synchronize];
    OITPostDarwinNotification(kOITIScalePrefsChangedNotification);
    [self reloadSpecifiers];
}

@end
