#import "OITNotifications.h"

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
    // Darwin notification center does not retain the "observer" pointer, so the
    // block must be kept alive independently. We never remove these -- matching
    // how every other Darwin observer in this ecosystem is registered once in
    // %ctor and expected to live for the process's lifetime.
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
                                        NULL, NULL, YES);
}

void OITRequestRespring(void) {
    OITPostDarwinNotification(@"com.oitui.respring");
}
