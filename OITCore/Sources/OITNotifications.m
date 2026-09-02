#import "OITNotifications.h"
#import <objc/message.h>

static NSMutableArray<OITDarwinNotificationHandler> *sOITObservedHandlers;

static void OITDarwinNotificationCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    OITDarwinNotificationHandler handler = (__bridge OITDarwinNotificationHandler)observer;
    if (handler) handler();
}

void OITObserveDarwinNotification(NSString *name, OITDarwinNotificationHandler handler) {
    if (!name.length || !handler) return;

    if (!sOITObservedHandlers) {
        sOITObservedHandlers = [NSMutableArray array];
    }

    OITDarwinNotificationHandler retainedHandler = [handler copy];
    [sOITObservedHandlers addObject:retainedHandler];

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)retainedHandler,
                                    OITDarwinNotificationCallback,
                                    (__bridge CFStringRef)name,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

void OITPostDarwinNotification(NSString *name) {
    if (!name.length) return;

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name,
                                         NULL,
                                         NULL,
                                         YES);
}

void OITRequestRespring(void) {
    OITPostDarwinNotification(@"com.oitui.respring");
}

__attribute__((constructor))
static void OITNotificationsInit(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

    OITObserveDarwinNotification(@"com.oitui.respring", ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            Class serviceClass = NSClassFromString(@"FBSystemService");
            if (!serviceClass) return;

            id service = ((id (*)(id, SEL))objc_msgSend)(
                serviceClass,
                @selector(sharedInstance)
            );

            SEL relaunchSelector = @selector(exitAndRelaunch:);
            if ([service respondsToSelector:relaunchSelector]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(
                    service,
                    relaunchSelector,
                    YES
                );
            }
        });
    });
}
