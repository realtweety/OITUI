#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <OITCore/OITCore.h>

static NSString * const kOITSPrefsDomain = @"com.wilburt.oits.prefs";
static NSString * const kOITSPrefsChangedNotification = @"com.wilburt.oits/PrefsChanged";
static const CGFloat kOITSCenterToleranceInPoints = 2.0;
static const CGFloat kOITSDriftToleranceInPoints = 0.5;
static const NSUInteger kOITSDiscoveryIntervalTicks = 10;
static const NSUInteger kOITSMaxTraverseDepth = 40;
static const NSTimeInterval kOITSStartupDelaySeconds = 3.0;

static OITPreferences *sOITSPreferences;
static BOOL sClockRepositionEnabled = NO;
static CGFloat sClockLeadingOffset = 16.0;
static NSHashTable<UIView *> *sTrackedClockViews;
static Class sStatusBarStringViewClass;
static BOOL sSpringBoardIsReadyForWindowAccess = NO;

static CGFloat OITSClampedLeadingOffsetForWidth(CGFloat viewWidth) {
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    CGFloat maxX = MAX(0.0, screenWidth - viewWidth);
    return MAX(0.0, MIN(sClockLeadingOffset, maxX));
}

static void OITSFindCenteredStringViews(UIView *view, CGFloat screenCenterX, NSUInteger depth) {
    if (!view || depth > kOITSMaxTraverseDepth) return;
    if (sStatusBarStringViewClass && [view isKindOfClass:sStatusBarStringViewClass]) {
        if (![sTrackedClockViews containsObject:view]) {
            CGFloat centerX = CGRectGetMidX(view.frame);
            if (fabs(centerX - screenCenterX) <= kOITSCenterToleranceInPoints) {
                [sTrackedClockViews addObject:view];
            }
        }
    }
    for (UIView *subview in view.subviews) {
        OITSFindCenteredStringViews(subview, screenCenterX, depth + 1);
    }
}

static void OITSDiscoverClockViews(void) {
    if (!UIApplication.sharedApplication) return;
    if (!sTrackedClockViews) sTrackedClockViews = [NSHashTable weakObjectsHashTable];
    if (!sStatusBarStringViewClass) sStatusBarStringViewClass = NSClassFromString(@"_UIStatusBarStringView");

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
        OITSFindCenteredStringViews(window, screenCenterX, 0);
    }
}

@interface OITSClockPositionEnforcer : NSObject
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSUInteger tickCounter;
@end

@implementation OITSClockPositionEnforcer

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

- (void)correctTrackedViews {
    // If ANY tracked view has been torn out of the hierarchy (window ==
    // nil), that instance is permanently gone -- no property we set can
    // bring it back. Drop it immediately and re-scan right now, rather
    // than waiting up to kOITSDiscoveryIntervalTicks for the next
    // scheduled scan to find whatever replaced it. This is the fix for a
    // real, confirmed bug: iOS can tear down and recreate the status bar's
    // string view (not just reposition the existing one) when other
    // status bar content changes, leaving our old reference dangling
    // indefinitely with nothing telling us to look for the new instance.
    BOOL anyViewWasRemoved = NO;
    NSMutableArray<UIView *> *deadViews = [NSMutableArray array];
    for (UIView *view in sTrackedClockViews) {
        if (!view.window) {
            [deadViews addObject:view];
            anyViewWasRemoved = YES;
        }
    }
    for (UIView *deadView in deadViews) {
        [sTrackedClockViews removeObject:deadView];
    }
    if (anyViewWasRemoved) {
        OITSDiscoverClockViews();
    }

    for (UIView *view in sTrackedClockViews) {
        if (!view.window) continue;
        CGRect currentFrame = view.frame;
        CGFloat clampedOffset = OITSClampedLeadingOffsetForWidth(currentFrame.size.width);
        if (fabs(currentFrame.origin.x - clampedOffset) > kOITSDriftToleranceInPoints) {
            currentFrame.origin.x = clampedOffset;
            view.frame = currentFrame;
        }
    }
}

- (void)tick:(__unused CADisplayLink *)link {
    if (!sClockRepositionEnabled || !sSpringBoardIsReadyForWindowAccess) return;
    self.tickCounter++;
    if (self.tickCounter == 1 || self.tickCounter % kOITSDiscoveryIntervalTicks == 0) {
        OITSDiscoverClockViews();
    }
    [self correctTrackedViews];
}

@end

static OITSClockPositionEnforcer *sClockEnforcer;

static void OITSUpdateEnforcerState(void) {
    if (!sSpringBoardIsReadyForWindowAccess) return;
    if (!sClockEnforcer) sClockEnforcer = [OITSClockPositionEnforcer new];
    if (sClockRepositionEnabled) {
        [sClockEnforcer start];
    } else {
        [sClockEnforcer stop];
    }
}

static void OITSReloadPreferences(void) {
    if (!sOITSPreferences) {
        sOITSPreferences = [OITPreferences preferencesWithDomain:kOITSPrefsDomain];
    } else {
        [sOITSPreferences reload];
    }
    sClockRepositionEnabled = [sOITSPreferences boolForKey:@"ClockRepositionEnabled" default:NO];
    sClockLeadingOffset = [sOITSPreferences floatForKey:@"ClockLeadingOffset" default:16.0];
    OITSUpdateEnforcerState();
}

@interface _UIStatusBarStringView : UIView
@end

@interface _UIStatusBarForegroundView : UIView
@end

%hook _UIStatusBarForegroundView

- (void)layoutSubviews {
    %orig;
    if (!sSpringBoardIsReadyForWindowAccess) return;
    CGFloat screenCenterX = UIScreen.mainScreen.bounds.size.width * 0.5;
    if (!sStatusBarStringViewClass) sStatusBarStringViewClass = NSClassFromString(@"_UIStatusBarStringView");
    OITSFindCenteredStringViews(self, screenCenterX, 0);
    [sClockEnforcer correctTrackedViews];
}

%end

%hook _UIStatusBarStringView

- (void)setFrame:(CGRect)frame {
    if (sClockRepositionEnabled && sSpringBoardIsReadyForWindowAccess) {
        CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
        CGFloat screenCenterX = screenWidth * 0.5;
        CGFloat incomingCenterX = CGRectGetMidX(frame);

        if (fabs(incomingCenterX - screenCenterX) <= kOITSCenterToleranceInPoints) {
            if (!sTrackedClockViews) sTrackedClockViews = [NSHashTable weakObjectsHashTable];
            [sTrackedClockViews addObject:self];
            frame.origin.x = OITSClampedLeadingOffsetForWidth(frame.size.width);
        }
    }
    %orig(frame);
}

%end

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

    OITSReloadPreferences();

    OITObserveDarwinNotification(kOITSPrefsChangedNotification, ^{
        OITSReloadPreferences();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOITSStartupDelaySeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        sSpringBoardIsReadyForWindowAccess = YES;
        OITSUpdateEnforcerState();
    });
}
