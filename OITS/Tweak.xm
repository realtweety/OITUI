#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/runtime.h>
#import <OITCore/OITCore.h>

static NSString * const kOITSPrefsDomain = @"com.wilburt.oits.prefs";
static NSString * const kOITSPrefsChangedNotification = @"com.wilburt.oits/PrefsChanged";
static const CGFloat kOITSCenterToleranceInPoints = 2.0;
static const CGFloat kOITSDriftToleranceInPoints = 0.5;
static const NSUInteger kOITSDiscoveryIntervalTicks = 10;
static const NSUInteger kOITSMaxTraverseDepth = 40;
static const NSTimeInterval kOITSStartupDelaySeconds = 3.0;
static const NSUInteger kOITSMaxRemovalEventLogs = 60;
static const NSUInteger kOITSMaxSuppressionLogs = 60;

static OITPreferences *sOITSPreferences;
static BOOL sSpringBoardIsReadyForWindowAccess = NO;
static NSUInteger sRemovalEventLogCount = 0;
static NSUInteger sSuppressionLogCount = 0;

static BOOL sClockRepositionEnabled = NO;
static BOOL sPreviousClockEnabled = NO;
static CGFloat sClockLeadingOffset = 16.0;
static NSHashTable<UIView *> *sTrackedClockViews;
static Class sStatusBarStringViewClass;
static const void *kOITSClockNaturalXKey = &kOITSClockNaturalXKey;

static BOOL sBatteryRepositionEnabled = NO;
static BOOL sPreviousBatteryEnabled = NO;
static CGFloat sBatteryLeadingOffset = 384.0;
static NSHashTable<UIView *> *sTrackedBatteryViews;
static Class sStaticBatteryViewClass;
static const void *kOITSBatteryNaturalXKey = &kOITSBatteryNaturalXKey;

static BOOL sWifiRepositionEnabled = NO;
static BOOL sPreviousWifiEnabled = NO;
static CGFloat sWifiLeadingOffset = 76.0;
static NSHashTable<UIView *> *sTrackedWifiViews;
static Class sStatusBarWifiSignalViewClass;
static const void *kOITSWifiNaturalXKey = &kOITSWifiNaturalXKey;

static BOOL sCellularRepositionEnabled = NO;
static BOOL sPreviousCellularEnabled = NO;
static CGFloat sCellularLeadingOffset = 6.0;
static NSHashTable<UIView *> *sTrackedCellularViews;
static const void *kOITSCellularNaturalXKey = &kOITSCellularNaturalXKey;

static BOOL sCarrierTextRepositionEnabled = NO;
static BOOL sPreviousCarrierTextEnabled = NO;
static CGFloat sCarrierTextLeadingOffset = 28.0;
static NSHashTable<UIView *> *sTrackedCarrierTextViews;
static const void *kOITSCarrierTextNaturalXKey = &kOITSCarrierTextNaturalXKey;

static BOOL sNetworkTypeRepositionEnabled = NO;
static BOOL sPreviousNetworkTypeEnabled = NO;
static CGFloat sNetworkTypeLeadingOffset = 100.0;
static NSHashTable<UIView *> *sTrackedNetworkTypeViews;
static const void *kOITSNetworkTypeNaturalXKey = &kOITSNetworkTypeNaturalXKey;

static void OITSDebugLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = @"/tmp/OITSDebug.log";
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
    } @catch (__unused NSException *exception) {}
    [handle closeFile];
}

static CGFloat OITSClampedOffsetForWidth(CGFloat desiredOffset, CGFloat viewWidth) {
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    CGFloat maxX = MAX(0.0, screenWidth - viewWidth);
    return MAX(0.0, MIN(desiredOffset, maxX));
}

static void OITSReapplyTransform(UIView *view, const void *naturalXKey, CGFloat desiredOffset) {
    NSNumber *naturalX = objc_getAssociatedObject(view, naturalXKey);
    if (!naturalX) return;
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    CGFloat clampedOffset = OITSClampedOffsetForWidth(desiredOffset, view.bounds.size.width);
    CGFloat delta = clampedOffset - naturalX.doubleValue;
    if (!isfinite(delta) || fabs(delta) > screenWidth) {
        OITSDebugLog(@"REFUSED bad delta=%.1f naturalX=%.1f desiredOffset=%.1f", delta, naturalX.doubleValue, desiredOffset);
        return;
    }
    CGFloat currentTx = view.transform.tx;
    if (fabs(currentTx - delta) > kOITSDriftToleranceInPoints) {
        view.transform = CGAffineTransformMakeTranslation(delta, 0);
    }
}

static void OITSResetAndForgetTrackedViews(NSHashTable<UIView *> *trackedSet, const void *naturalXKey, NSString *label) {
    if (!trackedSet) return;
    NSUInteger resetCount = 0;
    for (UIView *view in trackedSet) {
        if (!CGAffineTransformIsIdentity(view.transform)) {
            view.transform = CGAffineTransformIdentity;
            resetCount++;
        }
        objc_setAssociatedObject(view, naturalXKey, nil, OBJC_ASSOCIATION_RETAIN);
    }
    [trackedSet removeAllObjects];
    OITSDebugLog(@"Reset-on-disable: %@ -- reset %lu transform(s), forgot all tracking", label, (unsigned long)resetCount);
}

static void OITSFindCenteredStringViews(UIView *view, CGFloat screenCenterX, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    if (sStatusBarStringViewClass && [view isKindOfClass:sStatusBarStringViewClass]) {
        if (![sTrackedClockViews containsObject:view]) {
            NSNumber *naturalX = objc_getAssociatedObject(view, kOITSClockNaturalXKey);
            if (naturalX) {
                [sTrackedClockViews addObject:view];
            } else if (CGAffineTransformIsIdentity(view.transform)) {
                CGFloat centerX = CGRectGetMidX(view.frame);
                if (fabs(centerX - screenCenterX) <= kOITSCenterToleranceInPoints) {
                    objc_setAssociatedObject(view, kOITSClockNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
                    [sTrackedClockViews addObject:view];
                }
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindCenteredStringViews(subview, screenCenterX, depth + 1);
    }
}

static void OITSFindBatteryViews(UIView *view, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    if (sStaticBatteryViewClass && [view isKindOfClass:sStaticBatteryViewClass]) {
        if (![sTrackedBatteryViews containsObject:view]) {
            NSNumber *naturalX = objc_getAssociatedObject(view, kOITSBatteryNaturalXKey);
            if (naturalX) {
                [sTrackedBatteryViews addObject:view];
            } else if (CGAffineTransformIsIdentity(view.transform)) {
                objc_setAssociatedObject(view, kOITSBatteryNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
                [sTrackedBatteryViews addObject:view];
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindBatteryViews(subview, depth + 1);
    }
}

static void OITSFindWifiViews(UIView *view, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    if (sStatusBarWifiSignalViewClass && [view isKindOfClass:sStatusBarWifiSignalViewClass]) {
        if (![sTrackedWifiViews containsObject:view]) {
            NSNumber *naturalX = objc_getAssociatedObject(view, kOITSWifiNaturalXKey);
            if (naturalX) {
                [sTrackedWifiViews addObject:view];
            } else if (CGAffineTransformIsIdentity(view.transform)) {
                objc_setAssociatedObject(view, kOITSWifiNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
                [sTrackedWifiViews addObject:view];
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindWifiViews(subview, depth + 1);
    }
}

static BOOL OITSClassNameLooksLikeCellularSignalView(UIView *view) {
    NSString *className = NSStringFromClass([view class]);
    return [className containsString:@"Cellular"] && [className hasSuffix:@"SignalView"];
}

static void OITSFindCellularViews(UIView *view, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    if (OITSClassNameLooksLikeCellularSignalView(view)) {
        if (![sTrackedCellularViews containsObject:view]) {
            NSNumber *naturalX = objc_getAssociatedObject(view, kOITSCellularNaturalXKey);
            if (naturalX) {
                [sTrackedCellularViews addObject:view];
            } else if (CGAffineTransformIsIdentity(view.transform)) {
                objc_setAssociatedObject(view, kOITSCellularNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
                [sTrackedCellularViews addObject:view];
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindCellularViews(subview, depth + 1);
    }
}

static void OITSClassifyCarrierAndNetworkChildren(UIView *foregroundView, CGFloat screenCenterX) {
    NSMutableArray<UIView *> *leftoverStringViews = [NSMutableArray array];
    for (UIView *subview in foregroundView.subviews) {
        if (!sStatusBarStringViewClass || ![subview isKindOfClass:sStatusBarStringViewClass]) continue;
        if ([sTrackedCarrierTextViews containsObject:subview] || [sTrackedNetworkTypeViews containsObject:subview]) continue;
        if ([sTrackedClockViews containsObject:subview]) continue;
        CGFloat centerX = CGRectGetMidX(subview.frame);
        if (fabs(centerX - screenCenterX) <= kOITSCenterToleranceInPoints) continue;
        if (!CGAffineTransformIsIdentity(subview.transform)) continue;
        [leftoverStringViews addObject:subview];
    }
    if (leftoverStringViews.count == 0) return;

    [leftoverStringViews sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = CGRectGetMinX(a.frame);
        CGFloat bx = CGRectGetMinX(b.frame);
        if (ax < bx) return NSOrderedAscending;
        if (ax > bx) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    if (leftoverStringViews.count > 0 && sCarrierTextRepositionEnabled) {
        UIView *view = leftoverStringViews[0];
        objc_setAssociatedObject(view, kOITSCarrierTextNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
        [sTrackedCarrierTextViews addObject:view];
    }
    if (leftoverStringViews.count > 1 && sNetworkTypeRepositionEnabled) {
        UIView *view = leftoverStringViews[1];
        objc_setAssociatedObject(view, kOITSNetworkTypeNaturalXKey, @(view.frame.origin.x), OBJC_ASSOCIATION_RETAIN);
        [sTrackedNetworkTypeViews addObject:view];
    }
}

static void OITSWalkForForegroundViews(UIView *view, CGFloat screenCenterX, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    static Class foregroundViewClass;
    if (!foregroundViewClass) foregroundViewClass = NSClassFromString(@"_UIStatusBarForegroundView");
    if (foregroundViewClass && [view isKindOfClass:foregroundViewClass]) {
        OITSClassifyCarrierAndNetworkChildren(view, screenCenterX);
    }
    for (UIView *subview in view.subviews) {
        OITSWalkForForegroundViews(subview, screenCenterX, depth + 1);
    }
}

static void OITSDiscoverAllTargets(void) {
    if (!UIApplication.sharedApplication) return;
    if (!sTrackedClockViews) sTrackedClockViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedBatteryViews) sTrackedBatteryViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedWifiViews) sTrackedWifiViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedCellularViews) sTrackedCellularViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedCarrierTextViews) sTrackedCarrierTextViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedNetworkTypeViews) sTrackedNetworkTypeViews = [NSHashTable weakObjectsHashTable];
    if (!sStatusBarStringViewClass) sStatusBarStringViewClass = NSClassFromString(@"_UIStatusBarStringView");
    if (!sStaticBatteryViewClass) sStaticBatteryViewClass = NSClassFromString(@"_UIStaticBatteryView");
    if (!sStatusBarWifiSignalViewClass) sStatusBarWifiSignalViewClass = NSClassFromString(@"_UIStatusBarWifiSignalView");

    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop

    CGFloat screenCenterX = UIScreen.mainScreen.bounds.size.width * 0.5;
    for (UIWindow *window in windows) {
        if (sClockRepositionEnabled) OITSFindCenteredStringViews(window, screenCenterX, 0);
        if (sBatteryRepositionEnabled) OITSFindBatteryViews(window, 0);
        if (sWifiRepositionEnabled) OITSFindWifiViews(window, 0);
        if (sCellularRepositionEnabled) OITSFindCellularViews(window, 0);
        if (sCarrierTextRepositionEnabled || sNetworkTypeRepositionEnabled) {
            OITSWalkForForegroundViews(window, screenCenterX, 0);
        }
    }
}

@interface OITSPositionEnforcer : NSObject
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSUInteger tickCounter;
@end

@implementation OITSPositionEnforcer

- (void)start {
    if (self.displayLink) return;
    if (!sSpringBoardIsReadyForWindowAccess) return;
    self.tickCounter = 0;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (BOOL)cleanDeadViewsFromSet:(NSHashTable<UIView *> *)trackedSet label:(NSString *)label {
    if (!trackedSet) return NO;
    BOOL anyRemoved = NO;
    NSMutableArray<UIView *> *dead = [NSMutableArray array];
    for (UIView *view in trackedSet) {
        if (!view.window) {
            [dead addObject:view];
            anyRemoved = YES;
        }
    }
    for (UIView *deadView in dead) {
        [trackedSet removeObject:deadView];
    }
    if (anyRemoved && sRemovalEventLogCount < kOITSMaxRemovalEventLogs) {
        sRemovalEventLogCount++;
        OITSDebugLog(@"[event #%lu] tick=%lu: removed %lu dead %@ view(s)",
                    (unsigned long)sRemovalEventLogCount, (unsigned long)self.tickCounter,
                    (unsigned long)dead.count, label);
    }
    return anyRemoved;
}

- (void)correctAllTrackedViews {
    BOOL anyRemoved = NO;
    if (sClockRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedClockViews label:@"clock"];
    if (sBatteryRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedBatteryViews label:@"battery"];
    if (sWifiRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedWifiViews label:@"wifi"];
    if (sCellularRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedCellularViews label:@"cellular"];
    if (sCarrierTextRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedCarrierTextViews label:@"carrierText"];
    if (sNetworkTypeRepositionEnabled) anyRemoved |= [self cleanDeadViewsFromSet:sTrackedNetworkTypeViews label:@"networkType"];

    if (anyRemoved) {
        OITSDiscoverAllTargets();
        if (sRemovalEventLogCount <= kOITSMaxRemovalEventLogs) {
            OITSDebugLog(@"after rediscovery: tracking %lu clock, %lu battery, %lu wifi, %lu cellular, %lu carrier, %lu network",
                        (unsigned long)sTrackedClockViews.count, (unsigned long)sTrackedBatteryViews.count,
                        (unsigned long)sTrackedWifiViews.count, (unsigned long)sTrackedCellularViews.count,
                        (unsigned long)sTrackedCarrierTextViews.count, (unsigned long)sTrackedNetworkTypeViews.count);
        }
    }

    if (sClockRepositionEnabled) {
        for (UIView *view in sTrackedClockViews) {
            if (!view.window) continue;
            OITSReapplyTransform(view, kOITSClockNaturalXKey, sClockLeadingOffset);
        }
    }
    if (sBatteryRepositionEnabled) {
        for (UIView *view in sTrackedBatteryViews) {
            if (!view.window) continue;
            OITSReapplyTransform(view, kOITSBatteryNaturalXKey, sBatteryLeadingOffset);
        }
    }
    if (sWifiRepositionEnabled) {
        for (UIView *view in sTrackedWifiViews) {
            if (!view.window) continue;
            OITSReapplyTransform(view, kOITSWifiNaturalXKey, sWifiLeadingOffset);
        }
    }
    if (sCellularRepositionEnabled) {
        for (UIView *view in sTrackedCellularViews) {
            if (!view.window) continue;
            OITSReapplyTransform(view, kOITSCellularNaturalXKey, sCellularLeadingOffset);
        }
    }
    if (sCarrierTextRepositionEnabled) {
        for (UIView *view in sTrackedCarrierTextViews) {
            if (!view.window) continue;
            OITSReapplyTransform(view, kOITSCarrierTextNaturalXKey, sCarrierTextLeadingOffset);
        }
    }
    if (sNetworkTypeRepositionEnabled) {
        for (UIView *view in sTrackedNetworkTypeViews) {
            if (!view.window) continue;
            OITSReapplyTransform(view, kOITSNetworkTypeNaturalXKey, sNetworkTypeLeadingOffset);
        }
    }
}

- (void)tick:(__unused CADisplayLink *)link {
    if (!sSpringBoardIsReadyForWindowAccess) return;
    if (!sClockRepositionEnabled && !sBatteryRepositionEnabled && !sWifiRepositionEnabled &&
        !sCellularRepositionEnabled && !sCarrierTextRepositionEnabled && !sNetworkTypeRepositionEnabled) return;
    self.tickCounter++;
    if (self.tickCounter == 1 || self.tickCounter % kOITSDiscoveryIntervalTicks == 0) {
        OITSDiscoverAllTargets();
    }
    [self correctAllTrackedViews];
}

@end

static OITSPositionEnforcer *sPositionEnforcer;

static void OITSUpdateEnforcerState(void) {
    if (!sSpringBoardIsReadyForWindowAccess) return;
    if (!sPositionEnforcer) sPositionEnforcer = [OITSPositionEnforcer new];
    if (sClockRepositionEnabled || sBatteryRepositionEnabled || sWifiRepositionEnabled ||
        sCellularRepositionEnabled || sCarrierTextRepositionEnabled || sNetworkTypeRepositionEnabled) {
        [sPositionEnforcer start];
    } else {
        [sPositionEnforcer stop];
    }
}

static void OITSReloadPreferences(void) {
    if (!sOITSPreferences) {
        sOITSPreferences = [OITPreferences preferencesWithDomain:kOITSPrefsDomain];
    } else {
        [sOITSPreferences reload];
    }

    BOOL newClockEnabled = [sOITSPreferences boolForKey:@"ClockRepositionEnabled" default:NO];
    BOOL newBatteryEnabled = [sOITSPreferences boolForKey:@"BatteryRepositionEnabled" default:NO];
    BOOL newWifiEnabled = [sOITSPreferences boolForKey:@"WifiSignalRepositionEnabled" default:NO];
    BOOL newCellularEnabled = [sOITSPreferences boolForKey:@"CellularSignalRepositionEnabled" default:NO];
    BOOL newCarrierTextEnabled = [sOITSPreferences boolForKey:@"CarrierTextRepositionEnabled" default:NO];
    BOOL newNetworkTypeEnabled = [sOITSPreferences boolForKey:@"NetworkTypeRepositionEnabled" default:NO];

    if (sPreviousClockEnabled && !newClockEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedClockViews, kOITSClockNaturalXKey, @"clock");
    }
    if (sPreviousBatteryEnabled && !newBatteryEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedBatteryViews, kOITSBatteryNaturalXKey, @"battery");
    }
    if (sPreviousWifiEnabled && !newWifiEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedWifiViews, kOITSWifiNaturalXKey, @"wifi");
    }
    if (sPreviousCellularEnabled && !newCellularEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedCellularViews, kOITSCellularNaturalXKey, @"cellular");
    }
    if (sPreviousCarrierTextEnabled && !newCarrierTextEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedCarrierTextViews, kOITSCarrierTextNaturalXKey, @"carrierText");
    }
    if (sPreviousNetworkTypeEnabled && !newNetworkTypeEnabled) {
        OITSResetAndForgetTrackedViews(sTrackedNetworkTypeViews, kOITSNetworkTypeNaturalXKey, @"networkType");
    }

    sClockRepositionEnabled = newClockEnabled;
    sBatteryRepositionEnabled = newBatteryEnabled;
    sWifiRepositionEnabled = newWifiEnabled;
    sCellularRepositionEnabled = newCellularEnabled;
    sCarrierTextRepositionEnabled = newCarrierTextEnabled;
    sNetworkTypeRepositionEnabled = newNetworkTypeEnabled;
    sPreviousClockEnabled = newClockEnabled;
    sPreviousBatteryEnabled = newBatteryEnabled;
    sPreviousWifiEnabled = newWifiEnabled;
    sPreviousCellularEnabled = newCellularEnabled;
    sPreviousCarrierTextEnabled = newCarrierTextEnabled;
    sPreviousNetworkTypeEnabled = newNetworkTypeEnabled;
    sClockLeadingOffset = [sOITSPreferences floatForKey:@"ClockLeadingOffset" default:16.0];
    sBatteryLeadingOffset = [sOITSPreferences floatForKey:@"BatteryLeadingOffset" default:384.0];
    sWifiLeadingOffset = [sOITSPreferences floatForKey:@"WifiSignalLeadingOffset" default:76.0];
    sCellularLeadingOffset = [sOITSPreferences floatForKey:@"CellularSignalLeadingOffset" default:6.0];
    sCarrierTextLeadingOffset = [sOITSPreferences floatForKey:@"CarrierTextLeadingOffset" default:28.0];
    sNetworkTypeLeadingOffset = [sOITSPreferences floatForKey:@"NetworkTypeLeadingOffset" default:100.0];
    OITSUpdateEnforcerState();
}

@interface _UIStatusBarStringView : UIView
@property (nonatomic, assign) BOOL showsAlternateText;
@property (nonatomic, copy) NSString *alternateText;
- (BOOL)wantsCrossfade;
@end

@interface _UIStatusBarForegroundView : UIView
@end

@interface _UIStaticBatteryView : UIView
@end

@interface _UIStatusBarWifiSignalView : UIView
@property (nonatomic, assign) BOOL needsCycleAnimationUpdate;
@end

@interface _UIStatusBarCellularSignalView : UIView
@end

%hook _UIStatusBarForegroundView

- (void)layoutSubviews {
    %orig;
    if (!sSpringBoardIsReadyForWindowAccess) return;
    if (!sClockRepositionEnabled && !sBatteryRepositionEnabled && !sWifiRepositionEnabled &&
        !sCellularRepositionEnabled && !sCarrierTextRepositionEnabled && !sNetworkTypeRepositionEnabled) return;
    if (!sStatusBarStringViewClass) sStatusBarStringViewClass = NSClassFromString(@"_UIStatusBarStringView");
    if (!sStaticBatteryViewClass) sStaticBatteryViewClass = NSClassFromString(@"_UIStaticBatteryView");
    if (!sStatusBarWifiSignalViewClass) sStatusBarWifiSignalViewClass = NSClassFromString(@"_UIStatusBarWifiSignalView");
    if (!sTrackedClockViews) sTrackedClockViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedBatteryViews) sTrackedBatteryViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedWifiViews) sTrackedWifiViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedCellularViews) sTrackedCellularViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedCarrierTextViews) sTrackedCarrierTextViews = [NSHashTable weakObjectsHashTable];
    if (!sTrackedNetworkTypeViews) sTrackedNetworkTypeViews = [NSHashTable weakObjectsHashTable];
    CGFloat screenCenterX = UIScreen.mainScreen.bounds.size.width * 0.5;
    if (sClockRepositionEnabled) OITSFindCenteredStringViews(self, screenCenterX, 0);
    if (sBatteryRepositionEnabled) OITSFindBatteryViews(self, 0);
    if (sWifiRepositionEnabled) OITSFindWifiViews(self, 0);
    if (sCellularRepositionEnabled) OITSFindCellularViews(self, 0);
    if (sCarrierTextRepositionEnabled || sNetworkTypeRepositionEnabled) {
        OITSClassifyCarrierAndNetworkChildren(self, screenCenterX);
    }
}

%end

%hook _UIStatusBarStringView

- (void)setFrame:(CGRect)frame {
    if (!sClockRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    if (!CGAffineTransformIsIdentity(self.transform)) {
        self.transform = CGAffineTransformIdentity;
    }
    %orig(frame);

    CGFloat screenCenterX = UIScreen.mainScreen.bounds.size.width * 0.5;
    CGFloat incomingCenterX = CGRectGetMidX(frame);
    if (fabs(incomingCenterX - screenCenterX) <= kOITSCenterToleranceInPoints) {
        if (!sTrackedClockViews) sTrackedClockViews = [NSHashTable weakObjectsHashTable];
        [sTrackedClockViews addObject:self];
        objc_setAssociatedObject(self, kOITSClockNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
    }
}

- (void)_updateAlternateTextTimer {
    if (sClockRepositionEnabled && sSpringBoardIsReadyForWindowAccess && sTrackedClockViews && [sTrackedClockViews containsObject:self]) {
        if (sSuppressionLogCount < kOITSMaxSuppressionLogs) {
            sSuppressionLogCount++;
            OITSDebugLog(@"[suppress #%lu] blocked _updateAlternateTextTimer on tracked clock view", (unsigned long)sSuppressionLogCount);
        }
        return;
    }
    %orig;
}

%end

%hook _UIStaticBatteryView

- (void)setFrame:(CGRect)frame {
    if (!sBatteryRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    if (!CGAffineTransformIsIdentity(self.transform)) {
        self.transform = CGAffineTransformIdentity;
    }
    %orig(frame);

    if (!sTrackedBatteryViews) sTrackedBatteryViews = [NSHashTable weakObjectsHashTable];
    [sTrackedBatteryViews addObject:self];
    objc_setAssociatedObject(self, kOITSBatteryNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
}

%end

%hook _UIStatusBarWifiSignalView

- (void)setFrame:(CGRect)frame {
    if (!sWifiRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    if (!CGAffineTransformIsIdentity(self.transform)) {
        self.transform = CGAffineTransformIdentity;
    }
    %orig(frame);

    if (!sTrackedWifiViews) sTrackedWifiViews = [NSHashTable weakObjectsHashTable];
    [sTrackedWifiViews addObject:self];
    objc_setAssociatedObject(self, kOITSWifiNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
}

- (void)_updateCycleAnimationNow {
    if (sWifiRepositionEnabled && sSpringBoardIsReadyForWindowAccess && sTrackedWifiViews && [sTrackedWifiViews containsObject:self]) {
        if (sSuppressionLogCount < kOITSMaxSuppressionLogs) {
            sSuppressionLogCount++;
            OITSDebugLog(@"[suppress #%lu] blocked _updateCycleAnimationNow on tracked wifi view", (unsigned long)sSuppressionLogCount);
        }
        return;
    }
    %orig;
}

%end

%hook _UIStatusBarCellularSignalView

- (void)setFrame:(CGRect)frame {
    if (!sCellularRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) {
        %orig(frame);
        return;
    }
    if (!CGAffineTransformIsIdentity(self.transform)) {
        self.transform = CGAffineTransformIdentity;
    }
    %orig(frame);

    if (!sTrackedCellularViews) sTrackedCellularViews = [NSHashTable weakObjectsHashTable];
    [sTrackedCellularViews addObject:self];
    objc_setAssociatedObject(self, kOITSCellularNaturalXKey, @(frame.origin.x), OBJC_ASSOCIATION_RETAIN);
}

%end

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

    OITSDebugLog(@"=== ctor (restored known-good: clock/battery/wifi/cellular/carrier/network) ===");
    OITSReloadPreferences();

    OITObserveDarwinNotification(kOITSPrefsChangedNotification, ^{
        OITSReloadPreferences();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOITSStartupDelaySeconds * NSEC_PER_SEC)),
                  dispatch_get_main_queue(), ^{
        OITSDebugLog(@"=== startup delay elapsed ===");
        sSpringBoardIsReadyForWindowAccess = YES;
        OITSUpdateEnforcerState();
    });
}
