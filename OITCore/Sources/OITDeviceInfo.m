#import "OITDeviceInfo.h"
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>

static NSArray<UIWindow *> *OITAllWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    return windows;
}

@implementation OITDeviceInfo

+ (NSString *)machineIdentifier {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size == 0) return nil;

    char *machine = malloc(size);
    if (!machine) return nil;
    NSString *identifier = nil;
    if (sysctlbyname("hw.machine", machine, &size, NULL, 0) == 0) {
        identifier = [NSString stringWithUTF8String:machine];
    }
    free(machine);
    return identifier;
}

+ (BOOL)isFullScreenDevice {
    for (UIWindow *window in OITAllWindows()) {
        if (window.safeAreaInsets.top > 20.0) return YES;
    }
    CGSize screen = UIScreen.mainScreen.bounds.size;
    return MAX(screen.width, screen.height) >= 812.0;
}

+ (BOOL)hasDynamicIsland {
    for (UIWindow *window in OITAllWindows()) {
        if (window.safeAreaInsets.top >= 51.0) return YES;
    }
    return NO;
}

+ (BOOL)isAtLeastOperatingSystemVersion:(NSOperatingSystemVersion)version {
    return [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:version];
}

@end
