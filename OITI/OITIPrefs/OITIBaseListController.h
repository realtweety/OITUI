#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Foundation/Foundation.h>

// Shared behavior for every OITI settings page: loads its specifier plist, adds the Respring button and
// confirmation alert, and provides savePos. Subclasses only override -oiti_plistName.
@interface OITIBaseListController : PSListController

// Name of the specifier plist to load ("Root", "Color", "Scale", "Notifications").
- (NSString *)oiti_plistName;

@end
