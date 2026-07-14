#pragma once
#import <Foundation/Foundation.h>

@interface OITDeviceInfo : NSObject

+ (NSString *)machineIdentifier;
+ (BOOL)isFullScreenDevice;
+ (BOOL)hasDynamicIsland;
+ (BOOL)isAtLeastOperatingSystemVersion:(NSOperatingSystemVersion)version;

@end
