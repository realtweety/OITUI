// OITIBannerHide.xm -- fades out the stock banner while an Island notice shows (OITI Island notifications, optional).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 4, IslandNotifications).
// The banner windows lookup, the hide and restore, and the polling that decides when it is safe.

#import "Shared/OITIShared.h"
#import "IslandNotifications/OITIIslandNotifications.h"

static const void *kOITIBannerOriginalAlphaKey = &kOITIBannerOriginalAlphaKey;

BOOL sBannerHideActive = NO;

static BOOL sBannerHideSawBanner = NO;

static BOOL sBannerHideCanProbe = NO;

static CFAbsoluteTime sBannerHideStart = 0;

static __weak id sBannerHideDestination;

// ---- Stock banner fade (optional, islandNotificationsHideBanner) ----------------------------

NSArray<UIWindow *> *OITIBannerWindowsNow(void) {
    NSMutableArray<UIWindow *> *result = [NSMutableArray array];
    for (UIView *view in sBannerWindows.allObjects) {
        if ([view isKindOfClass:[UIWindow class]]) [result addObject:(UIWindow *)view];
    }
    if (!result.count && [UIWindow respondsToSelector:@selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:)]) {
        Class bannerClass = NSClassFromString(@"SBBannerWindow");
        for (UIWindow *window in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
            if (bannerClass && [window isKindOfClass:bannerClass]) [result addObject:window];
        }
    }
    return result;
}

static void OITIHideBannerWindows(void) {
    for (UIWindow *window in OITIBannerWindowsNow()) {
        if (!objc_getAssociatedObject(window, kOITIBannerOriginalAlphaKey)) {
            objc_setAssociatedObject(window, kOITIBannerOriginalAlphaKey, @(window.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (window.alpha != 0) window.alpha = 0;
    }
}

void OITIRestoreBannerWindows(void) {
    for (UIWindow *window in OITIBannerWindowsNow()) {
        NSNumber *original = objc_getAssociatedObject(window, kOITIBannerOriginalAlphaKey);
        if (!original) continue;
        CGFloat value = original.doubleValue;
        window.alpha = value > 0.01 ? value : 1.0;
        objc_setAssociatedObject(window, kOITIBannerOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// Keeps the banner window faded until Apple says no banner is presented any more (or a hard cap passes), then puts
// it back exactly as it was. Without a usable presentedBanner getter it simply waits a fixed time.
static void OITIPollBannerHide(void) {
    if (!sBannerHideActive) return;
    CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - sBannerHideStart;
    id presented = sBannerHideCanProbe ? OITISafeObject(sBannerHideDestination, @"presentedBanner") : nil;
    if (presented) sBannerHideSawBanner = YES;

    BOOL done;
    if (sBannerHideCanProbe) {
        done = (sBannerHideSawBanner && !presented && elapsed > 1.0) || (!sBannerHideSawBanner && elapsed > 4.0) || elapsed > 12.0;
    } else {
        done = elapsed > 7.0;
    }
    if (done) {
        OITIRestoreBannerWindows();
        sBannerHideActive = NO;
        [sLog logLevel:1 tag:@"NOTIF" format:@"stock banner window restored after %.1fs (sawBanner=%d probe=%d)",
         elapsed, sBannerHideSawBanner, sBannerHideCanProbe];
        return;
    }
    OITIHideBannerWindows();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OITIPollBannerHide();
    });
}

void OITIBeginBannerHide(id destination) {
    sBannerHideDestination = destination;
    sBannerHideCanProbe = [destination respondsToSelector:NSSelectorFromString(@"presentedBanner")];
    sBannerHideStart = CFAbsoluteTimeGetCurrent();
    sBannerHideSawBanner = NO;
    OITIHideBannerWindows();
    if (!sBannerHideActive) {
        sBannerHideActive = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            OITIPollBannerHide();
        });
    }
}
