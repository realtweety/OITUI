#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#import <sys/sysctl.h>

static NSString * const kOITIGestaltBackupBreadcrumbPath = @"/var/mobile/Library/Preferences/OITIGestaltBackup.plist";
static NSString * const kOITIGestaltPlistPath = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist";
static NSString * const kOITIGestaltCacheExtraKey = @"CacheExtra";
static NSString * const kOITIGestaltNestedKey = @"oPeik/9e8lQWMszEjbPzng";
static NSString * const kOITIGestaltLeafKey = @"ArtworkDeviceSubType";
static NSInteger const kOITISpoofedArtworkDeviceSubType = 2556;

static NSString *OITIMachineIdentifier(void) {
    size_t size = 0;
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0 || size == 0) return nil;
    char *machine = calloc(size, sizeof(char));
    if (!machine) return nil;
    NSString *identifier = nil;
    if (sysctlbyname("hw.machine", machine, &size, NULL, 0) == 0) {
        identifier = [NSString stringWithUTF8String:machine];
    }
    free(machine);
    return identifier;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSDictionary *breadcrumb = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltBackupBreadcrumbPath];
        if (![breadcrumb[@"BackupCaptured"] boolValue]) {
            fprintf(stderr, "OITIRestoreGestalt: no usable backup breadcrumb; leaving MobileGestalt unchanged\n");
            return 0;
        }

        NSMutableDictionary *plistDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
        if (!plistDictionary) {
            fprintf(stderr, "OITIRestoreGestalt: could not read MobileGestalt cache at %s\n", [kOITIGestaltPlistPath UTF8String]);
            return 1;
        }

        NSMutableDictionary *cacheExtraDictionary = [plistDictionary[kOITIGestaltCacheExtraKey] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSMutableDictionary *nestedDictionary = [cacheExtraDictionary[kOITIGestaltNestedKey] mutableCopy] ?: [NSMutableDictionary dictionary];

        BOOL wasPresent = [breadcrumb[@"OriginalValuePresent"] boolValue];
        id originalValue = breadcrumb[@"OriginalValue"];
        NSString *machine = OITIMachineIdentifier();
        BOOL poisonedSpoofBackup = wasPresent && [originalValue respondsToSelector:@selector(integerValue)] &&
            [originalValue integerValue] == kOITISpoofedArtworkDeviceSubType &&
            ![machine isEqualToString:@"iPhone15,2"];
        if (poisonedSpoofBackup) {
            // Older builds could save OITI's 2556 spoof as the "original". On supported iOS 16
            // hardware only iPhone15,2 natively reports 2556; elsewhere remove it and let iOS recompute.
            fprintf(stderr, "OITIRestoreGestalt: treating saved 2556 as a stale spoof on %s; removing the key\n",
                    machine ? [machine UTF8String] : "unknown hardware");
            [nestedDictionary removeObjectForKey:kOITIGestaltLeafKey];
        } else if (wasPresent && originalValue) {
            nestedDictionary[kOITIGestaltLeafKey] = originalValue;
        } else {
            [nestedDictionary removeObjectForKey:kOITIGestaltLeafKey];
        }

        cacheExtraDictionary[kOITIGestaltNestedKey] = nestedDictionary;
        plistDictionary[kOITIGestaltCacheExtraKey] = cacheExtraDictionary;

        if (![plistDictionary writeToFile:kOITIGestaltPlistPath atomically:YES]) {
            fprintf(stderr, "OITIRestoreGestalt: failed to write restored MobileGestalt cache\n");
            return 1;
        }
        return 0;
    }
}
