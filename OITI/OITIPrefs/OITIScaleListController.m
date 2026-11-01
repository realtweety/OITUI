#import "OITIScaleListController.h"
#import <OITCore/OITCore.h>

static NSString * const kOITIScalePrefsDomain = @"com.wilburt.oiti.prefs";
static NSString * const kOITIScalePrefsChangedNotification = @"com.wilburt.oiti/PrefsChanged";

@implementation OITIScaleListController

- (NSString *)oiti_plistName {
    return @"Scale";
}

// Puts the Island Size sliders back to Apple's own size. Applies immediately.
- (void)resetIslandSize {
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIScalePrefsDomain];
    [prefs setObject:@1.0 forKey:@"MetricsSensorWidthScale"];
    [prefs setObject:@1.0 forKey:@"MetricsSensorHeightScale"];
    [prefs synchronize];
    OITPostDarwinNotification(kOITIScalePrefsChangedNotification);
    [self oitiRefreshSettingsPage];
}

- (void)resetScale {
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIScalePrefsDomain];
    [prefs setObject:@1.0 forKey:@"RelativeScaleX"];
    [prefs setObject:@1.0 forKey:@"RelativeScaleY"];
    [prefs synchronize];
    OITPostDarwinNotification(kOITIScalePrefsChangedNotification);
    [self oitiRefreshSettingsPage];
}

@end
