// OITINoticeActions.xm -- what a tap or swipe on a notification element does (OITI Island notifications).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 4, IslandNotifications).
// Opening the app or URL, running the stock banner's own tap, the gesture recognizers and the actions object.

#import "Shared/OITIShared.h"
#import "IslandNotifications/OITIIslandNotifications.h"
#import "Diagnostics/OITIDiagnostics.h"

// ---- The element ----------------------------------------------------------------------------

// Logs the method list of an object's class once per class (level 1 only; this is research output).
void OITIProbeObject(id object, NSString *role) {
    if (!object || ![sLog isLoggingAtLevel:1]) return;
    static NSMutableSet<NSString *> *probed;
    if (!probed) probed = [NSMutableSet set];
    NSString *className = NSStringFromClass([object class]);
    if ([probed containsObject:className]) return;
    [probed addObject:className];
    [sLog logTag:@"ELEMENT" format:@"PROBE %@ = %@", role, className];
    OITIDumpMethods([object class], @"-");
    OITIDumpMethods(object_getClass([object class]), @"+");
}

// ---- Tap / swipe on the element ----------------------------------------------------------------
static void OITIOpenApp(NSString *bundleID) {
    if (!bundleID.length) return;
    UIApplication *application = [UIApplication sharedApplication];
    SEL launch = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([application respondsToSelector:launch]) {
        BOOL ok = ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(application, launch, bundleID, NO);
        [sLog logLevel:1 tag:@"ELEMENT" format:@"open app %@ via launchApplicationWithIdentifier: -> %d", bundleID, ok];
        return;
    }
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspace = NSSelectorFromString(@"defaultWorkspace");
    SEL open = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (workspaceClass && [workspaceClass respondsToSelector:defaultWorkspace]) {
        id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultWorkspace);
        if ([workspace respondsToSelector:open]) {
            BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, open, bundleID);
            [sLog logLevel:1 tag:@"ELEMENT" format:@"open app %@ via LSApplicationWorkspace -> %d", bundleID, ok];
            return;
        }
    }
    [sLog logTag:@"ELEMENT" format:@"could not open %@: no launch API found", bundleID];
}

// ---- Tap action ----------------------------------------------------------------------------------
// A tap on the notification element does what tapping the stock banner does (see OITIExecuteStockBannerTap). If that banner is
// gone (for example the element outlived it), the tap uses the notification's default action URL when it has one, and otherwise
// launches the app.
static NSURL *OITIDefaultActionURL(id request) {
    id action = OITIKVCObject(request, @"defaultAction");
    for (NSString *key in @[@"url", @"launchURL", @"targetURL"]) {
        id value = OITIKVCObject(action, key);
        if ([value isKindOfClass:[NSURL class]]) return value;
    }
    return nil;
}

static BOOL OITIOpenURL(NSURL *url) {
    UIApplication *application = [UIApplication sharedApplication];
    SEL open = NSSelectorFromString(@"openURL:options:completionHandler:");
    if (![application respondsToSelector:open]) return NO;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(application, open, url, @{}, nil);
    [sLog logLevel:1 tag:@"ELEMENT" format:@"open url %@ via openURL:options:completionHandler:", url];
    return YES;
}

// The stock banner is still alive (only faded) while OITI's element shows, so a tap can run exactly what a tap on it runs:
// NCNotificationViewController -_executeDefaultAction: (found with a class dump on 16.7.16; the banner's view controllers are
// BNContentViewController > SBNotificationPresentableViewController > NCNotificationShortLookViewController). Apple's own code
// then opens the right conversation, dismisses the banner and clears the notification.
static void OITICollectNotificationViewControllers(UIViewController *controller, Class base, int depth,
                                                   NSMutableArray<UIViewController *> *found) {
    if (!controller || depth > 8 || found.count > 8) return;
    if (base && [controller isKindOfClass:base]) [found addObject:controller];
    for (UIViewController *child in controller.childViewControllers) OITICollectNotificationViewControllers(child, base, depth + 1, found);
    if (controller.presentedViewController) OITICollectNotificationViewControllers(controller.presentedViewController, base, depth + 1, found);
}

static BOOL OITIExecuteStockBannerTap(id request) {
    Class base = NSClassFromString(@"NCNotificationViewController");
    SEL execute = NSSelectorFromString(@"_executeDefaultAction:");
    if (!base) return NO;
    NSMutableArray<UIViewController *> *found = [NSMutableArray array];
    for (UIWindow *window in OITIBannerWindowsNow()) OITICollectNotificationViewControllers(window.rootViewController, base, 0, found);
    UIViewController *target = nil;
    for (UIViewController *controller in found) {
        id candidate = OITIKVCObject(controller, @"notificationRequest");
        if (request && candidate && (candidate == request || [candidate isEqual:request])) { target = controller; break; }
    }
    // With a stack, another notification's banner may be the only one left on screen. Never route an
    // older item's tap to that unrelated banner; only use the sole-banner fallback when no request exists.
    if (!target && !request && found.count == 1) target = found.firstObject;
    if (!target || ![target respondsToSelector:execute]) {
        [sLog logLevel:1 tag:@"ELEMENT" format:@"tap: no matching stock banner (found %lu), using the fallback", (unsigned long)found.count];
        return NO;
    }
    ((void (*)(id, SEL, BOOL))objc_msgSend)(target, execute, YES);
    [sLog logLevel:1 tag:@"ELEMENT" format:@"tap ran -_executeDefaultAction: on %@", NSStringFromClass([target class])];
    return YES;
}

@implementation OITINoticeTapRecognizer
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    [sLog logLevel:1 tag:@"ELEMENT" format:@"TOUCH began (%@) hit=%@ at %@", self.label, NSStringFromClass([touch.view class]),
     NSStringFromCGPoint([touch locationInView:nil])];
    [super touchesBegan:touches withEvent:event];
}
@end

@implementation OITINoticeActions
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
// The window-level recognizers only take touches that start inside the notification element.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if (![recognizer.view isKindOfClass:[UIWindow class]]) return YES;
    UIView *host = self.host;
    return host && CGRectContainsPoint(host.bounds, [touch locationInView:host]);
}
- (void)handleTap:(UIGestureRecognizer *)recognizer {
    if (self.handled) return;
    self.handled = YES;
    NSURL *url = OITIDefaultActionURL(self.request);
    [sLog logLevel:1 tag:@"ELEMENT" format:@"TAP on the notification element (%@) seen by %@ url=%@", self.bundleID,
     NSStringFromClass([recognizer.view class]), url];
    if (!OITIExecuteStockBannerTap(self.request)) {   // fallbacks: the default action's URL, then just the app
        if (!(url && OITIOpenURL(url))) OITIOpenApp(self.bundleID);
    }
    // Opening a notification does not remove it from the stack; it remains until timeout or swipe dismissal.
    __weak OITINoticeActions *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        weakSelf.handled = NO;   // window and element recognizers share one tap, but later taps should still work
    });
}
- (void)handleSwipe:(UIGestureRecognizer *)recognizer {
    if (self.handled) return;
    self.handled = YES;
    [sLog logLevel:1 tag:@"ELEMENT" format:@"SWIPE up on the notification element seen by %@", NSStringFromClass([recognizer.view class])];
    if (self.dismiss) self.dismiss();
}
@end
