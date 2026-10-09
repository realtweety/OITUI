#import <Foundation/Foundation.h>
#import "OITIRootListController.h"
#import "../OITIDeviceProfiles.h"
#import <OITCore/OITCore.h>
#import <UIKit/UIKit.h>

static NSString * const kOITIPrefsBuildTag = @"OITIPrefs-step2-2026-10-08-b";
static NSString * const kOITIPrefsLogPath = @"/tmp/OITIPrefsDebug.log";

static NSString * const kOITIGestaltPlistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static NSString * const kOITIGestaltCacheExtraKey = @"CacheExtra";
static NSString * const kOITIGestaltNestedKey = @"oPeik/9e8lQWMszEjbPzng";
static NSString * const kOITIGestaltLeafKey = @"ArtworkDeviceSubType";
static NSString * const kOITIGestaltPrefsDomain = @"com.wilburt.oiti.prefs";

// The value OITI writes to make iOS build the Dynamic Island.
static const NSInteger kOITISpoofedArtworkDeviceSubType = 2556;

// Plain, fixed-path breadcrumb -- deliberately NOT going through CFPreferences.
// The uninstall-time helper (which runs as root, not mobile) reads this file
// directly instead of trying to resolve OITI's real preferences domain, since
// that domain's on-disk representation is not guaranteed to be a flat file we
// can locate, and CFPreferences' "current user" would resolve incorrectly
// from a root-owned process anyway.
static NSString * const kOITIGestaltBackupBreadcrumbPath = @"/var/mobile/Library/Preferences/OITIGestaltBackup.plist";

// Prefs-side log, separate from the tweak's /tmp/OITIDebug.log because this code runs in the Settings process.
static OITLogger *OITIPrefsLog(void) {
    static OITLogger *log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = [OITLogger loggerWithName:@"oitiprefs" path:kOITIPrefsLogPath];
        log.ignoredImageNames = @[@"OITCore.dylib"];
        [log logSessionStartWithBuildTag:kOITIPrefsBuildTag];
    });
    return log;
}

// 2556 is the spoof value. iOS 16 only ever runs on one model that natively reports it (iPhone 14 Pro,
// iPhone15,2). On anything else, a stored "original" of 2556 is the spoof itself, captured by mistake.
// Keep in sync with OITIMachineHasNativeIsland in the tweak's Tweak.xm.
static BOOL OITIMachineHasNativeIsland(NSString *machine) {
    return [machine isEqualToString:@"iPhone15,2"];
}

@implementation OITIRootListController

- (NSString *)oiti_plistName {
    return @"Root";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Opening the settings page repairs a backup that was captured while the spoof was already active.
    [OITIRootListController oiti_repairSuspectBackupIfNeeded];
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
    // Informational (the restore helper ignores it): the "original" was not trustworthy when it was captured,
    // so it is recorded as absent. Restoring then removes the key and lets iOS compute the real value.
    if ([prefs boolForKey:@"MobileGestaltBackupSuspect" default:NO]) {
        breadcrumb[@"CaptureSuspect"] = @YES;
    }
    BOOL ok = [breadcrumb writeToFile:kOITIGestaltBackupBreadcrumbPath atomically:YES];
    [OITIPrefsLog() logTag:@"GESTALT" format:@"breadcrumb written ok=%d present=%d original=%@ suspect=%d",
     ok, wasPresent, breadcrumb[@"OriginalValue"] ?: @"(none)", [breadcrumb[@"CaptureSuspect"] boolValue]];
}

// A backup captured while the 2556 spoof was already active recorded 2556 as the "original". On hardware that
// does not natively report 2556 that can never be right: restoring it would write the spoof back, so turning
// the feature off (or uninstalling) would leave the Island active. Record the original as absent instead, so a
// restore removes the key. This changes only OITI's own backup data, never the MobileGestalt cache.
+ (void)oiti_repairSuspectBackupIfNeeded {
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIGestaltPrefsDomain];
    if (![prefs boolForKey:@"MobileGestaltBackupCaptured" default:NO]) return;
    if ([prefs boolForKey:@"MobileGestaltBackupSuspect" default:NO]) return;

    BOOL present = [prefs boolForKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent" default:NO];
    id original = [prefs objectForKey:@"MobileGestaltOriginalArtworkDeviceSubType" default:nil];
    NSString *machine = [OITDeviceInfo machineIdentifier];
    if (!present || ![original isKindOfClass:[NSNumber class]] ||
        [original integerValue] != kOITISpoofedArtworkDeviceSubType) {
        return;
    }
    if (OITIMachineHasNativeIsland(machine)) return;

    [OITIPrefsLog() logTag:@"GESTALT" format:@"REPAIR backup recorded original=%@ on %@ (not Island hardware): recording the original as absent instead",
     original, machine];
    [prefs setObject:@NO forKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent"];
    [prefs removeObjectForKey:@"MobileGestaltOriginalArtworkDeviceSubType"];
    [prefs setObject:@YES forKey:@"MobileGestaltBackupSuspect"];
    [prefs synchronize];
    [self oiti_writeBackupBreadcrumb];
}

+ (void)oiti_backupOriginalArtworkDeviceSubTypeIfNeeded {
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIGestaltPrefsDomain];
    if ([prefs boolForKey:@"MobileGestaltBackupCaptured" default:NO]) {
        // Already captured once, ever -- never re-capture a possibly-spoofed value. But an earlier capture may
        // itself have been taken from a spoofed cache, so repair that case.
        [self oiti_repairSuspectBackupIfNeeded];
        return;
    }

    NSDictionary *plistDictionary = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
    if (!plistDictionary) {
        // Do not capture "absent" just because the cache could not be read.
        [OITIPrefsLog() logTag:@"GESTALT" format:@"backup NOT captured: MobileGestalt cache not readable at %@", kOITIGestaltPlistPath];
        return;
    }
    NSDictionary *cacheExtraDictionary = plistDictionary[kOITIGestaltCacheExtraKey];
    NSDictionary *nestedDictionary = cacheExtraDictionary[kOITIGestaltNestedKey];
    id existingValue = nestedDictionary[kOITIGestaltLeafKey];
    NSString *machine = [OITDeviceInfo machineIdentifier];

    BOOL suspect = NO;
    if ([existingValue isKindOfClass:[NSNumber class]]) {
        if ([existingValue integerValue] == kOITISpoofedArtworkDeviceSubType && !OITIMachineHasNativeIsland(machine)) {
            // The spoof is already in the cache (left over from an earlier run). That is not this device's real
            // value, so do not record it as the original.
            suspect = YES;
            [prefs setObject:@NO forKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent"];
            [OITIPrefsLog() logTag:@"GESTALT" format:@"capture: cache already holds %@ on %@ (not Island hardware): recording the original as absent",
             existingValue, machine];
        } else {
            [prefs setObject:@YES forKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent"];
            [prefs setObject:existingValue forKey:@"MobileGestaltOriginalArtworkDeviceSubType"];
            [OITIPrefsLog() logTag:@"GESTALT" format:@"capture: original=%@ on %@", existingValue, machine];
        }
    } else {
        [prefs setObject:@NO forKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent"];
        [OITIPrefsLog() logTag:@"GESTALT" format:@"capture: cache has no %@ value on %@ (original recorded as absent)",
         kOITIGestaltLeafKey, machine];
    }
    if (suspect) {
        [prefs setObject:@YES forKey:@"MobileGestaltBackupSuspect"];
    }
    [prefs setObject:@YES forKey:@"MobileGestaltBackupCaptured"];
    [prefs synchronize];

    [self oiti_writeBackupBreadcrumb];
}

+ (void)oiti_writeArtworkDeviceSubTypeValue:(NSNumber *)value {
    NSMutableDictionary *plistDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
    if (!plistDictionary) {
        [OITIPrefsLog() logTag:@"GESTALT" format:@"write %@ skipped: cache not readable", (id)value ?: (id)@"(remove key)"];
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

    BOOL ok = [plistDictionary writeToFile:kOITIGestaltPlistPath atomically:YES];
    [OITIPrefsLog() logTag:@"GESTALT" format:@"cache %@ %@ ok=%d",
     value ? @"set to" : @"key removed:", (id)value ?: (id)kOITIGestaltLeafKey, ok];
}

+ (void)enableIslandHardwareIdentitySpoof {
    [OITIPrefsLog() logTag:@"GESTALT" format:@"islandEnabled ON requested"];
    [self oiti_backupOriginalArtworkDeviceSubTypeIfNeeded];
    [self oiti_writeArtworkDeviceSubTypeValue:@(kOITISpoofedArtworkDeviceSubType)];
}

+ (void)restoreOriginalHardwareIdentity {
    [OITIPrefsLog() logTag:@"GESTALT" format:@"islandEnabled OFF requested"];
    OITPreferences *prefs = [OITPreferences preferencesWithDomain:kOITIGestaltPrefsDomain];
    if (![prefs boolForKey:@"MobileGestaltBackupCaptured" default:NO]) {
        [OITIPrefsLog() logTag:@"GESTALT" format:@"restore skipped: nothing was ever captured"];
        return; // Feature was never enabled -- nothing was ever captured, nothing to restore.
    }

    // Make sure a poisoned backup cannot make this restore a no-op.
    [self oiti_repairSuspectBackupIfNeeded];
    prefs = [OITPreferences preferencesWithDomain:kOITIGestaltPrefsDomain];

    BOOL wasPresent = [prefs boolForKey:@"MobileGestaltOriginalArtworkDeviceSubTypePresent" default:NO];
    if (wasPresent) {
        NSNumber *originalValue = [prefs objectForKey:@"MobileGestaltOriginalArtworkDeviceSubType" default:nil];
        [OITIPrefsLog() logTag:@"GESTALT" format:@"restoring original value %@", (id)originalValue ?: (id)@"(nil)"];
        [self oiti_writeArtworkDeviceSubTypeValue:originalValue];
    } else {
        [OITIPrefsLog() logTag:@"GESTALT" format:@"original was absent: removing the key"];
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
