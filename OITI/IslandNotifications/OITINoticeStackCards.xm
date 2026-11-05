// OITINoticeStackCards.xm -- the stack's older notifications, drawn by OITI as cards below the Island
// (v0.3.0 polish, batch 5; tested on the phone by the owner from build OITI-exp-2026-11-03-c).
//
// The newest notice is an Apple element in whatever Style the owner chose. The older notices of the stack (the stack holds four)
// are drawn here, as compact capsules in a window of OITI's own placed under the Island's card:
//
//     [app icon]        Title: message in the middle        [how long ago]
//
// Each card has its own tap and its own swipe up, so a tap opens that notice only. Every notice is still a registered element with
// its own timeout and promotion; only where the older ones are drawn and what a tap on them does lives here. (Until build
// OITI-exp-2026-11-03-d the older notices could also be drawn as compact cards inside the newest element's card, selected by a
// Stack Look setting; the owner preferred these cards, so that look and its setting were removed.)
//
// The window follows the Minimal download pill's design (own window in the Island's scene, above the Island's window, touches
// outside the cards fall through). The cards are placed from the on-screen rectangle of the Island's container view and wait until it
// has stood still for a moment; when no plausible rectangle is found they stay hidden (nothing is guessed). Level 2 logs the
// candidate rectangles (tag STACKCARDS).
//
// Launch path: nothing here runs at launch. The first call comes from OITIPresentNoticeElement after a notice exists.

#import "Shared/OITIShared.h"
#import "IslandNotifications/OITIIslandNotifications.h"
#import "Diagnostics/OITIDiagnostics.h"

static const CGFloat kOITICardHeight = 36.0;
static const CGFloat kOITICardGap = 5.0;            // between cards
static const CGFloat kOITICardIslandGap = 8.0;      // between the Island's card and the first card
static const CGFloat kOITICardMinWidth = 240.0;
static const NSUInteger kOITICardMax = 3;           // the stack holds four notices: the newest plus three older ones
static const CFTimeInterval kOITICardStableAfter = 0.15;   // the Island's rectangle must stand still this long

// ---- One card ------------------------------------------------------------------------------------------

@interface OITINoticeCardView : UIView
@property (nonatomic, strong) OITINoticeActions *actions;   // the gesture recognizers' target (they hold it weakly)
@property (nonatomic, assign) CFAbsoluteTime postedAt;
@property (nonatomic, strong) UILabel *timeLabel;
- (instancetype)initWithItem:(NSDictionary *)item;
- (void)refreshTimeText;
@end

@implementation OITINoticeCardView {
    UIImageView *_icon;
    UILabel *_initial;
    UILabel *_message;
}

static NSString *OITICardMessageText(NSDictionary *info) {
    NSString *title = info[@"title"] ?: @"";
    NSString *subtitle = info[@"subtitle"] ?: @"";
    NSString *message = info[@"message"] ?: @"";
    NSString *appName = info[@"appName"] ?: @"";
    if (!appName.length && [info[@"bundleID"] length]) appName = [(NSString *)info[@"bundleID"] componentsSeparatedByString:@"."].lastObject ?: @"";
    NSString *body = message;
    if (subtitle.length) body = message.length ? [NSString stringWithFormat:@"%@: %@", subtitle, message] : subtitle;
    if (title.length) return body.length ? [NSString stringWithFormat:@"%@: %@", title, body] : title;
    if (body.length) return body;
    return appName;
}

- (instancetype)initWithItem:(NSDictionary *)item {
    if ((self = [super initWithFrame:CGRectMake(0, 0, kOITICardMinWidth, kOITICardHeight)])) {
        NSDictionary *info = item[@"info"];
        NSString *bundleID = info[@"bundleID"] ?: @"";
        self.backgroundColor = [UIColor blackColor];
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.cornerRadius = kOITICardHeight / 2.0;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
        self.postedAt = [item[@"postedAt"] doubleValue];

        UIImage *icon = nil;
        if (bundleID.length && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
            icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
        }
        if (icon) {
            _icon = [[UIImageView alloc] initWithImage:icon];
            _icon.layer.cornerCurve = kCACornerCurveContinuous;
            _icon.layer.cornerRadius = 5.0;
            _icon.layer.masksToBounds = YES;
            [self addSubview:_icon];
        } else {
            _initial = [[UILabel alloc] init];
            _initial.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
            _initial.textColor = [UIColor whiteColor];
            _initial.textAlignment = NSTextAlignmentCenter;
            NSString *name = [info[@"appName"] length] ? info[@"appName"] : OITICardMessageText(info);
            _initial.text = name.length ? [name substringToIndex:1] : @"•";
            [self addSubview:_initial];
        }

        _message = [[UILabel alloc] init];
        _message.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        _message.textColor = [UIColor colorWithWhite:1.0 alpha:0.95];
        _message.textAlignment = NSTextAlignmentCenter;
        _message.numberOfLines = 1;
        _message.lineBreakMode = NSLineBreakByTruncatingTail;
        _message.text = OITICardMessageText(info);
        [self addSubview:_message];

        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        _timeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:_timeLabel];
        [self refreshTimeText];
    }
    return self;
}

- (void)refreshTimeText {
    NSString *text = @"";
    if (self.postedAt > 0) {
        double seconds = MAX(0.0, CFAbsoluteTimeGetCurrent() - self.postedAt);
        if (seconds < 60.0) text = @"now";
        else if (seconds < 3600.0) text = [NSString stringWithFormat:@"%dm", (int)(seconds / 60.0)];
        else text = [NSString stringWithFormat:@"%dh", (int)(seconds / 3600.0)];
    }
    if (![_timeLabel.text isEqualToString:text]) {
        _timeLabel.text = text;
        [self setNeedsLayout];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat iconSide = 22.0, margin = 12.0;
    CGRect iconFrame = CGRectMake(margin, (height - iconSide) / 2.0, iconSide, iconSide);
    _icon.frame = iconFrame;
    _initial.frame = iconFrame;
    CGSize timeSize = [_timeLabel sizeThatFits:CGSizeMake(80, height)];
    CGFloat timeWidth = _timeLabel.text.length ? ceil(timeSize.width) : 0.0;
    _timeLabel.frame = CGRectMake(width - margin - timeWidth, (height - ceil(timeSize.height)) / 2.0, timeWidth, ceil(timeSize.height));
    // The message is centred in the space between the icon and the time, and the two sides use the same inset, so it is
    // centred on the card even when the time is short.
    CGFloat side = MAX(CGRectGetMaxX(iconFrame), timeWidth + margin) + 8.0;
    _message.frame = CGRectMake(side, 0, MAX(20.0, width - 2.0 * side), height);
}
@end

// ---- The window -----------------------------------------------------------------------------------------

@interface OITINoticeCardsController : UIViewController
@end
@implementation OITINoticeCardsController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
@end

@interface OITINoticeCardsWindow : UIWindow
@end
@implementation OITINoticeCardsWindow
// Only the cards take touches; everything else goes to whatever is underneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

static OITINoticeCardsWindow *sCardsWindow;
static NSMutableArray<OITINoticeCardView *> *sCardViews;
static NSTimer *sCardsTimer;
static BOOL sCardsShown;                  // the cards are faded in
static CGRect sCardsLastRect;             // the Island rectangle seen on the last tick
static CFTimeInterval sCardsStableSince;
static CFAbsoluteTime sCardsLastSecond;   // when the time labels were last refreshed
static NSString *sCardsLastCandidates;    // for the level 2 probe log (log on change only)
static NSInteger sCardsLastDecisionCode = -1;   // log a decision only when it changes (the tick runs ~30 times a second)

static UIWindowScene *OITICardsWindowScene(void) {
    for (UIView *view in sLiveApertureWindows.allObjects) {
        UIWindowScene *scene = [view isKindOfClass:[UIWindow class]] ? ((UIWindow *)view).windowScene : nil;
        if (scene) return scene;
    }
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)scene;
    }
    return nil;
}

static UIWindowLevel OITICardsWindowLevel(void) {
    UIWindowLevel level = UIWindowLevelAlert + 1000.0;
    for (UIView *view in sLiveApertureWindows.allObjects) {
        if ([view isKindOfClass:[UIWindow class]]) level = MAX(level, ((UIWindow *)view).windowLevel + 1.0);
    }
    return level;
}

// ---- Where the Island's card is ---------------------------------------------------------------------------
// The Island's own rounded black view (SBSystemApertureContainerView) in screen coordinates; the conversion includes OITI's
// position and scale transforms. All candidates are collected (and logged at level 2: this is the probe of this round); the
// one that reaches lowest on screen wins, because the cards go under the expanded card.
static void OITICardsCollectContainers(UIView *view, Class containerClass, NSUInteger depth, NSMutableArray<NSValue *> *rects) {
    if (containerClass && [view isKindOfClass:containerClass]) {
        if (!view.hidden && view.alpha > 0.01) {
            CGRect rect = [[UIScreen mainScreen].coordinateSpace convertRect:view.bounds fromCoordinateSpace:view];
            if (rect.size.width > 20.0 && rect.size.height > 10.0) [rects addObject:[NSValue valueWithCGRect:rect]];
        }
        return;
    }
    if (depth >= 8) return;
    for (UIView *subview in view.subviews) OITICardsCollectContainers(subview, containerClass, depth + 1, rects);
}

static BOOL OITICardsIslandRect(CGRect *rectOut) {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    Class containerClass = NSClassFromString(@"SBSystemApertureContainerView");
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    for (UIView *view in sLiveApertureWindows.allObjects) {
        if (![view isKindOfClass:[UIWindow class]] || view.hidden) continue;
        OITICardsCollectContainers(view, containerClass, 0, rects);
    }
    CGRect best = CGRectNull;
    for (NSValue *value in rects) {
        CGRect rect = value.CGRectValue;
        BOOL plausible = rect.size.width >= 60.0 && rect.size.width <= screen.width - 8.0 &&
                         rect.origin.y >= -5.0 && rect.origin.y <= 80.0 && rect.size.height >= 20.0 && rect.size.height <= 420.0;
        if (!plausible) continue;
        if (CGRectIsNull(best) || CGRectGetMaxY(rect) > CGRectGetMaxY(best)) best = rect;
    }
    if ([sLog isLoggingAtLevel:2]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (NSValue *value in rects) [parts addObject:NSStringFromCGRect(value.CGRectValue)];
        NSString *summary = [NSString stringWithFormat:@"containers=[%@] chosen=%@", [parts componentsJoinedByString:@" "],
                             CGRectIsNull(best) ? @"none" : NSStringFromCGRect(best)];
        if (![summary isEqualToString:sCardsLastCandidates]) {
            sCardsLastCandidates = summary;
            [sLog logLevel:2 tag:@"STACKCARDS" format:@"island rectangle probe: %@", summary];
        }
    }
    if (CGRectIsNull(best)) return NO;
    *rectOut = best;
    return YES;
}

// ---- Which notices become cards -----------------------------------------------------------------------------
// The older items of the stack that are notifications (a running Detailed download and the Hello are not drawn as cards in
// round 1). Most recent first, at most kOITICardMax.
static NSArray<NSDictionary *> *OITICardsOlderItems(void) {
    if (sAppleMode || !sIslandNotificationStackEnabled) return @[];
    if (sIslandNoticeItems.count < 2) return @[];
    NSMutableArray<NSDictionary *> *older = [NSMutableArray array];
    for (NSInteger i = (NSInteger)sIslandNoticeItems.count - 2; i >= 0 && older.count < kOITICardMax; i--) {
        NSDictionary *item = sIslandNoticeItems[(NSUInteger)i];
        if (item[@"download"] || item[@"startupHello"] || !item[@"info"]) continue;
        [older addObject:item];
    }
    return older;
}

static BOOL OITICardsNewestIsOnScreen(void) {
    NSDictionary *newest = sIslandNoticeItems.lastObject;
    for (NSString *key in @[@"leadingView", @"trailingView", @"primaryView"]) {
        UIView *view = newest[key];
        if ([view isKindOfClass:[UIView class]] && view.window) return YES;
    }
    return NO;
}

// `text` is only evaluated when the decision changed and level 1 logging is on.
static void OITICardsDecision(NSInteger code, NSString *(^text)(void)) {
    if (code == sCardsLastDecisionCode) return;
    sCardsLastDecisionCode = code;
    if ([sLog isLoggingAtLevel:1]) [sLog logLevel:1 tag:@"STACKCARDS" format:@"%@", text()];
}

static void OITICardsSetShown(BOOL shown) {
    if (sCardsShown == shown) return;
    sCardsShown = shown;
    UIView *root = sCardsWindow.rootViewController.view;
    [UIView animateWithDuration:shown ? 0.22 : 0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{ root.alpha = shown ? 1.0 : 0.0; } completion:nil];
}

static void OITICardsStopTimer(void) {
    [sCardsTimer invalidate];
    sCardsTimer = nil;
}

static void OITICardsTearDown(NSString *why) {
    OITICardsStopTimer();
    if (!sCardsWindow && !sCardViews.count) return;
    for (UIView *card in sCardViews) [card removeFromSuperview];
    [sCardViews removeAllObjects];
    sCardsShown = NO;
    sCardsWindow.rootViewController.view.alpha = 0.0;
    sCardsWindow.hidden = YES;
    sCardsLastRect = CGRectZero;
    OITICardsDecision(0, ^NSString *{ return [NSString stringWithFormat:@"cards removed (%@)", why]; });
}

// One tick: where the cards go and whether they show. Cheap; runs ~30 times a second only while cards exist.
static void OITICardsTick(void) {
    if (!sCardsWindow || !sCardViews.count) { OITICardsStopTimer(); return; }
    CGRect island = CGRectZero;
    BOOL haveIsland = OITICardsIslandRect(&island);
    BOOL onScreen = OITICardsNewestIsOnScreen();
    BOOL landscape = UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation);
    CFTimeInterval now = CACurrentMediaTime();
    if (haveIsland) {
        CGRect last = sCardsLastRect;
        BOOL moved = fabs(island.origin.x - last.origin.x) > 0.75 || fabs(island.origin.y - last.origin.y) > 0.75 ||
                     fabs(island.size.width - last.size.width) > 0.75 || fabs(island.size.height - last.size.height) > 0.75;
        if (moved) {
            sCardsStableSince = now;
            sCardsLastRect = island;
            [sLog logLevel:2 tag:@"STACKCARDS" format:@"island rectangle changed to %@ (was %@)", NSStringFromCGRect(island), NSStringFromCGRect(last)];
        }
    }
    BOOL stable = haveIsland && now - sCardsStableSince >= kOITICardStableAfter;
    BOOL wanted = haveIsland && onScreen && stable && !landscape;
    if (!wanted) {
        OITICardsDecision(100 + haveIsland + 2 * onScreen + 4 * stable + 8 * landscape, ^NSString *{
            return [NSString stringWithFormat:@"cards hidden: island rectangle %@, newest on screen=%d, stable=%d, landscape=%d",
                    haveIsland ? @"found" : @"NOT found", onScreen, stable, landscape];
        });
        OITICardsSetShown(NO);
        return;
    }

    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat width = MIN(screen.width - 24.0, MAX(kOITICardMinWidth, island.size.width - 20.0));
    CGFloat x = MAX(12.0, MIN(screen.width - width - 12.0, CGRectGetMidX(island) - width / 2.0));
    CGFloat y = CGRectGetMaxY(island) + kOITICardIslandGap;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < sCardViews.count; i++) {
        sCardViews[i].frame = CGRectMake(floor(x), floor(y + (CGFloat)i * (kOITICardHeight + kOITICardGap)), width, kOITICardHeight);
    }
    [CATransaction commit];
    OITICardsDecision(1000 + (NSInteger)sCardViews.count, ^NSString *{
        return [NSString stringWithFormat:@"cards shown: %lu under island %@", (unsigned long)sCardViews.count, NSStringFromCGRect(island)];
    });
    OITICardsSetShown(YES);

    CFAbsoluteTime seconds = floor(CFAbsoluteTimeGetCurrent());
    if (seconds != sCardsLastSecond) {
        sCardsLastSecond = seconds;
        for (OITINoticeCardView *card in sCardViews) [card refreshTimeText];
    }
}

static void OITICardsEnsureWindow(void) {
    if (sCardsWindow) {
        sCardsWindow.windowLevel = OITICardsWindowLevel();   // the Island's windows can change level
        return;
    }
    UIWindowScene *scene = OITICardsWindowScene();
    sCardsWindow = scene ? [[OITINoticeCardsWindow alloc] initWithWindowScene:scene]
                         : [[OITINoticeCardsWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    sCardsWindow.backgroundColor = [UIColor clearColor];
    OITINoticeCardsController *controller = [[OITINoticeCardsController alloc] init];
    controller.view.backgroundColor = [UIColor clearColor];
    controller.view.alpha = 0.0;
    sCardsWindow.rootViewController = controller;
    sCardsWindow.windowLevel = OITICardsWindowLevel();
    sCardsShown = NO;
    [sLog logLevel:1 tag:@"STACKCARDS" format:@"window created: scene=%@ level=%.0f", scene ? NSStringFromClass([scene class]) : @"none", (double)sCardsWindow.windowLevel];
}

// Builds the card for one older notice, with its own tap and swipe (aimed at that notice only).
static OITINoticeCardView *OITICardsBuildCard(NSDictionary *item) {
    OITINoticeCardView *card = [[OITINoticeCardView alloc] initWithItem:item];
    NSDictionary *info = item[@"info"];
    OITINoticeActions *actions = [OITINoticeActions new];
    actions.bundleID = info[@"bundleID"];
    actions.request = item[@"request"];
    actions.host = card;
    // The removal rebuilds the cards (this card and its actions object go away), so it runs after the recognizer's callback returns.
    actions.dismiss = ^{ dispatch_async(dispatch_get_main_queue(), ^{ OITIRemoveNoticeItem(item, @"swipe"); }); };
    actions.tapDismiss = ^{ OITIRemoveNoticeItem(item, @"tap"); };
    card.actions = actions;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:actions action:@selector(handleTap:)];
    [card addGestureRecognizer:tap];
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:actions action:@selector(handleSwipe:)];
    swipe.direction = UISwipeGestureRecognizerDirectionUp;
    [card addGestureRecognizer:swipe];
    return card;
}

// Called whenever the stack changes: rebuilds the cards from the stack, or removes them.
void OITIStackCardsRefresh(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ OITIStackCardsRefresh(); });
        return;
    }
    NSArray<NSDictionary *> *older = OITICardsOlderItems();
    if (!older.count) {
        OITICardsTearDown(@"no older notice");
        return;
    }
    OITICardsEnsureWindow();
    if (!sCardViews) sCardViews = [NSMutableArray array];
    UIView *root = sCardsWindow.rootViewController.view;
    for (UIView *card in sCardViews) [card removeFromSuperview];
    [sCardViews removeAllObjects];
    for (NSDictionary *item in older) {
        OITINoticeCardView *card = OITICardsBuildCard(item);
        [root addSubview:card];
        [sCardViews addObject:card];
    }
    sCardsWindow.hidden = NO;
    sCardsLastSecond = 0;
    sCardsLastDecisionCode = -1;
    [sLog logLevel:1 tag:@"STACKCARDS" format:@"refresh: %lu older notice%@ as cards (stack of %lu)", (unsigned long)older.count,
     older.count == 1 ? @"" : @"s", (unsigned long)sIslandNoticeItems.count];
    if (!sCardsTimer) {
        sCardsTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer *timer) { OITICardsTick(); }];
        [[NSRunLoop mainRunLoop] addTimer:sCardsTimer forMode:NSRunLoopCommonModes];
    }
    OITICardsTick();
}
