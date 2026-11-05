#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Foundation/Foundation.h>

// Shared behavior for every OITI settings page: loads its specifier plist, adds the Respring button and
// confirmation alert, and provides savePos: (the Save buttons). Subclasses only override -oiti_plistName.
@interface OITIBaseListController : PSListController

// Name of the specifier plist to load ("Root", "Color", "Scale", "Notifications").
- (NSString *)oiti_plistName;
- (void)oitiRefreshSettingsPage;

// Shared by the pages that have a "Fix ..." switch (Root, Notifications).
+ (void)oitiCheckDeviceFixSupportForKey:(NSString *)key;
+ (void)showFixNoticeWithTitle:(NSString *)title message:(NSString *)message;

@end
