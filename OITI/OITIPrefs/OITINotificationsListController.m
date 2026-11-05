#import "OITINotificationsListController.h"

@implementation OITINotificationsListController

- (NSString *)oiti_plistName {
    return @"Notifications";
}

// Fix Notification Positioning reads the same device-table entry as Fix Island Position, so it gets the same notice.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    if ([[specifier propertyForKey:@"key"] isEqualToString:@"notificationFix"] && [value boolValue]) {
        [OITIBaseListController oitiCheckDeviceFixSupportForKey:@"notificationFix"];
    }
}

@end
