#import <Foundation/Foundation.h>

static NSString * const kOITIGestaltBackupBreadcrumbPath = @"/var/mobile/Library/Preferences/OITIGestaltBackup.plist";
static NSString * const kOITIGestaltPlistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static NSString * const kOITIGestaltCacheExtraKey = @"CacheExtra";
static NSString * const kOITIGestaltNestedKey = @"oPeik/9e8lQWMszEjbPzng";
static NSString * const kOITIGestaltLeafKey = @"ArtworkDeviceSubType";

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSDictionary *breadcrumb = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltBackupBreadcrumbPath];
        if (![breadcrumb[@"BackupCaptured"] boolValue]) {
            // Nothing was ever spoofed by OITI -- nothing to restore.
            return 0;
        }

        NSMutableDictionary *plistDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
        if (!plistDictionary) {
            return 0;
        }

        NSMutableDictionary *cacheExtraDictionary = [plistDictionary[kOITIGestaltCacheExtraKey] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSMutableDictionary *nestedDictionary = [cacheExtraDictionary[kOITIGestaltNestedKey] mutableCopy] ?: [NSMutableDictionary dictionary];

        BOOL wasPresent = [breadcrumb[@"OriginalValuePresent"] boolValue];
        if (wasPresent && breadcrumb[@"OriginalValue"]) {
            nestedDictionary[kOITIGestaltLeafKey] = breadcrumb[@"OriginalValue"];
        } else {
            [nestedDictionary removeObjectForKey:kOITIGestaltLeafKey];
        }

        cacheExtraDictionary[kOITIGestaltNestedKey] = nestedDictionary;
        plistDictionary[kOITIGestaltCacheExtraKey] = cacheExtraDictionary;

        [plistDictionary writeToFile:kOITIGestaltPlistPath atomically:YES];
        return 0;
    }
}
