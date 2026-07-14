#import <Foundation/Foundation.h>
#import "OITIRootListController.h"
#import <OITCore/OITCore.h>
#import <UIKit/UIKit.h>

@implementation OITIRootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}

	return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIBarButtonItem *respring = [[UIBarButtonItem alloc] initWithTitle:@"Respring" style:UIBarButtonItemStylePlain target:self action:@selector(respringAsk:)];
    self.navigationItem.rightBarButtonItem = respring;
}

- (void)respringAsk:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Respring"
                         message:@"You are about to respring."
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"Cancel"
                  style:UIAlertActionStyleCancel
                handler:nil];

    UIAlertAction *yes = [UIAlertAction
        actionWithTitle:@"Respring"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    [self respring];
                }];

    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respring {
    OITRequestRespring();
}

+ (void)set2556 {
    NSString *plistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";

    NSMutableDictionary *plistDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];

    if (!plistDictionary) {
        return;
    }

    NSMutableDictionary *cacheExtraDictionary = plistDictionary[@"CacheExtra"];
    if (!cacheExtraDictionary) {
        cacheExtraDictionary = [NSMutableDictionary dictionary];
        plistDictionary[@"CacheExtra"] = cacheExtraDictionary;
    }

    NSMutableDictionary *nestedDictionary = cacheExtraDictionary[@"oPeik/9e8lQWMszEjbPzng"];
    if (!nestedDictionary) {
        nestedDictionary = [NSMutableDictionary dictionary];
        cacheExtraDictionary[@"oPeik/9e8lQWMszEjbPzng"] = nestedDictionary;
    }

    [nestedDictionary setValue:@(2556) forKey:@"ArtworkDeviceSubType"];

    [plistDictionary writeToFile:plistPath atomically:YES];
}

+ (void)set0000 {
    NSString *plistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";

    NSMutableDictionary *plistDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];

    if (!plistDictionary) {
        return;
    }

    NSMutableDictionary *cacheExtraDictionary = plistDictionary[@"CacheExtra"];
    if (!cacheExtraDictionary) {
        cacheExtraDictionary = [NSMutableDictionary dictionary];
        plistDictionary[@"CacheExtra"] = cacheExtraDictionary;
    }

    NSMutableDictionary *nestedDictionary = cacheExtraDictionary[@"oPeik/9e8lQWMszEjbPzng"];
    if (!nestedDictionary) {
        nestedDictionary = [NSMutableDictionary dictionary];
        cacheExtraDictionary[@"oPeik/9e8lQWMszEjbPzng"] = nestedDictionary;
    }

    [nestedDictionary setValue:@(0000) forKey:@"ArtworkDeviceSubType"];

    [plistDictionary writeToFile:plistPath atomically:YES];
}

+ (void)fixUnsupported {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Device not supported"
                                                                   message:@"This device is not officially supported by OITI, meaning there are no 'perfect' offsets found for your device as of now. You can enable this option and use the built-in estimated offsets, or disable it and use custom offsets."
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

- (void)savePos {
    [self.view endEditing:YES];
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
    } if (section == [tableView numberOfSections] - 5) {
        return 45;
    } else {
        return 0;
    }
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    if ([[specifier propertyForKey:@"key"] isEqualToString:@"islandEnabled"]) {
        BOOL switchValue = [value boolValue];
        if (switchValue) {
			[OITIRootListController set2556];
        } else {
			[OITIRootListController set0000];
        }
    } else if ([[specifier propertyForKey:@"key"] isEqualToString:@"fixEnabled"]) {
        BOOL switchValue = [value boolValue];
        if (switchValue) {
            NSString *deviceModel = [OITDeviceInfo machineIdentifier];
            NSArray *supportedModels = @[@"iPhone10,3", @"iPhone10,6", @"iPhone11,2", @"iPhone12,3", @"iPhone11,6", @"iPhone12,5", @"iPhone11,8", @"iPhone12,1", @"iPhone14,2", @"iPhone14,5", @"iPhone14,7", @"iPhone14,3", @"iPhone14,4"];
            if ([supportedModels containsObject:deviceModel]) {
            } else {
                [OITIRootListController fixUnsupported];
            }
        }
    }
}
@end
