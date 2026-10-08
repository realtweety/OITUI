#import <Foundation/Foundation.h>
#import "OITIRootListController.h"
#import "../OITIDeviceProfiles.h"
#import <OITCore/OITCore.h>
#import <UIKit/UIKit.h>

static NSString * const kOITIGestaltPlistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static NSString * const kOITIGestaltCacheExtraKey = @"CacheExtra";
static NSString * const kOITIGestaltNestedKey = @"oPeik/9e8lQWMszEjbPzng";
static NSString * const kOITIGestaltLeafKey = @"ArtworkDeviceSubType";
static NSString * const kOITIGestaltPrefsDomain = @"com.wilburt.oiti.prefs";

// Plain, fixed-path breadcrumb -- deliberately NOT going through CFPreferences.
// The uninstall-time helper (which runs as root, not mobile) reads this file
// directly instead of trying to resolve OITI's real preferences domain, since
// that domain's on-disk representation is not guaranteed to be a flat file we
// can locate, and CFPreferences' "current user" would resolve incorrectly
// from a root-owned process anyway.
static NSString * const kOITIGestaltBackupBreadcrumbPath = @"/var/mobile/Library/Preferences/OITIGestaltBackup.plist";

@implementation OITIRootListController

- (NSString *)oiti_plistName {
    return @"Root";
}

// MARK: - MobileGestalt hardware-identity spoof (backup-safe)

+ (void)oiti_writeBackupBreadcrumb {
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIGestaltPrefsDomain];
    BOOL captured = [prefs boolForKey:@"MobileGestaltBackupCaptured" default:NO];
    if (!captured) return;

    NSMutableDictionary *breadcrumb = [NSMutableDictionary dictionary];
    breadcrumb[@"BackupCaptured"] = @YES;
    BOOL wasPresent = [prefs boolForKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent" default:NO];
    breadcrumb[@"OriginalValuePresent"] = @(wasPresent);
    if (wasPresent) {
        id originalValue = [prefs objectForKey:@"MobileGestaltOriginalArtworkDeviceSubType" default:nil];
        if (originalValue) {
            breadcrumb[@"OriginalValue"] = originalValue;
        }
    }
    [breadcrumb writeToFile:kOITIGestaltBackupBreadcrumbPath atomically:YES];
}

+ (void)oiti_backupOriginalArtworkDeviceSubTypeIfNeeded {
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIGestaltPrefsDomain];
    if ([prefs boolForKey:@"MobileGestaltBackupCaptured" default:NO]) {
        return; // Already captured once, ever -- never re-capture a possibly-spoofed value.
    }

    NSDictionary *plistDictionary = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
    NSDictionary *cacheExtraDictionary = plistDictionary[kOITIGestaltCacheExtraKey];
    NSDictionary *nestedDictionary = cacheExtraDictionary[kOITIGestaltNestedKey];
    id existingValue = nestedDictionary[kOITIGestaltLeafKey];

    if ([existingValue isKindOfClass:[NSNumber class]]) {
        [prefs setObject:@YES forKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent"];
        [prefs setObject:existingValue forKey:@"MobileGestaltOriginalArtworkDeviceSubType"];
    } else {
        [prefs setObject:@NO forKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent"];
    }
    [prefs setObject:@YES forKey:@"MobileGestaltBackupCaptured"];
    [prefs synchronize];

    [self oiti_writeBackupBreadcrumb];
}

+ (void)oiti_writeArtworkDeviceSubTypeValue:(NSNumber *)value {
    NSMutableDictionary *plistDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
    if (!plistDictionary) {
        return;
    }

    NSMutableDictionary *cacheExtraDictionary = [plistDictionary[kOITIGestaltCacheExtraKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *nestedDictionary = [cacheExtraDictionary[kOITIGestaltNestedKey] mutableCopy] ?: [NSMutableDictionary dictionary];

    if (value) {
        nestedDictionary[kOITIGestaltLeafKey] = value;
    } else {
        [nestedDictionary removeObjectForKey:kOITIGestaltLeafKey];
    }

    cacheExtraDictionary[kOITIGestaltNestedKey] = nestedDictionary;
    plistDictionary[kOITIGestaltCacheExtraKey] = cacheExtraDictionary;

    [plistDictionary writeToFile:kOITIGestaltPlistPath atomically:YES];
}

+ (void)enableIslandHardwareIdentitySpoof {
    [self oiti_backupOriginalArtworkDeviceSubTypeIfNeeded];
    [self oiti_writeArtworkDeviceSubTypeValue:@(2556)];
}

+ (void)restoreOriginalHardwareIdentity {
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIGestaltPrefsDomain];
    if (![prefs boolForKey:@"MobileGestaltBackupCaptured" default:NO]) {
        return; // Feature was never enabled -- nothing was ever captured, nothing to restore.
    }

    BOOL wasPresent = [prefs boolForKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent" default:NO];
    if (wasPresent) {
        NSNumber *originalValue = [prefs objectForKey:@"MobileGestaltOriginalArtworkDeviceSubType" default:nil];
        [self oiti_writeArtworkDeviceSubTypeValue:originalValue];
    } else {
        [self oiti_writeArtworkDeviceSubTypeValue:nil];
    }

    [self oiti_writeBackupBreadcrumb];
}

+ (void)showFixNoticeWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction *action) {
                                                     }];

    [alert addAction:okAction];

    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow) break;
    }
    [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)sourceCode {
    NSURL *url = [NSURL URLWithString:@"https://github.com/ethxnn88/visibleisland"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)twitter {
    NSURL *url = [NSURL URLWithString:@"https://twitter.com/ethxnn88"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == [tableView numberOfSections] - 1) {
        UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 50)];
        footerLabel.textAlignment = NSTextAlignmentCenter;
        footerLabel.textColor = [UIColor grayColor];
        footerLabel.font = [UIFont systemFontOfSize:14.0];
        footerLabel.text = @"OITI v0.1.0";
        return footerLabel;
    } else {
        return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == [tableView numberOfSections] - 1) {
        return 50;
    } else if (section == [tableView numberOfSections] - 5) {
        return 45;
    }
    return 0;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    if ([[specifier propertyForKey:@"key"] isEqualToString:@"islandEnabled"]) {
        BOOL switchValue = [value boolValue];
        if (switchValue) {
			[OITIRootListController enableIslandHardwareIdentitySpoof];
        } else {
			[OITIRootListController restoreOriginalHardwareIdentity];
        }
    } else if ([[specifier propertyForKey:@"key"] isEqualToString:@"fixEnabled"]) {
        BOOL switchValue = [value boolValue];
        if (switchValue) {
            // One shared table (OITIDeviceProfiles.h) decides what "supported" means, so this can never
            // disagree with the offsets the tweak actually uses.
            const OITIDeviceProfile *profile = OITIProfileForModel([OITDeviceInfo machineIdentifier]);
            if (!profile) {
                [OITIRootListController showFixNoticeWithTitle:@"No built-in offsets"
                                                       message:@"OITI has no built-in offsets for this device, so this option will have no effect. Turn it off and use the custom position and banner offsets instead."];
            } else if (!profile->verified) {
                [OITIRootListController showFixNoticeWithTitle:@"Estimated offsets"
                                                       message:@"The built-in offsets for this device are estimates and may not be pixel-perfect. If something looks off, turn this option off and use custom offsets."];
            }
        }
    }
}
@end
