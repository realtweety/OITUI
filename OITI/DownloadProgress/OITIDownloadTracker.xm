// OITIDownloadTracker.xm -- the download tracker, the Minimal pill window and the simulated test download (OITI download progress).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 2, DownloadProgress). The download settings that the
// preferences reload in Tweak.xm writes are defined here (they were file-level statics at the top of Tweak.xm) and declared
// in OITIDownloadProgress.h. The Island element of the Detailed look is created by the notification presenter in Tweak.xm,
// which keeps sDownloadItem, sDownloadShownAt and sDownloadDropCount; the tracker reads and updates them.

#import "Shared/OITIShared.h"
#import "DownloadProgress/OITIDownloadProgress.h"

// The download settings (DownloadProgressEnabled and the keys below), written by the preferences reload in Tweak.xm.
BOOL sDownloadProgressEnabled;          // DownloadProgressEnabled (default NO)
BOOL sDownloadAppStoreEnabled;          // DownloadAppStoreEnabled (default NO): feed the tracker from App Store downloads
BOOL sDownloadTestFractionOnly;         // DownloadTestFractionOnly (default NO, defaults write only): the test download reports a percentage only
CGFloat sDownloadIdleAfterMB = 0;       // DownloadIdleAfterMB: return the Island to idle after this many MB downloaded, 0 = never
CGFloat sDownloadIdleAfterSeconds = 0;  // DownloadIdleAfterSeconds: the same after this long on screen, 0 = never
CGFloat sDownloadTestSizeMB = 800;      // DownloadTestSizeMB: size of the test download
NSInteger sDownloadStyle = 0;           // DownloadProgressStyle: 0 minimal (default), 1 detailed
CGFloat sDownloadPillWidth = 296;         // DownloadPillWidth: the Minimal pill, in points (never narrower than the Island plus a margin)
CGFloat sDownloadPillBottomPadding = 10;  // DownloadPillBottomPadding: space under the content
CGFloat sDownloadPillNudgeY = 0;          // DownloadPillNudgeY: moves the pill up or down from the Island's top

// =============================================================================================
// MARK: Download progress (the tracker, the Minimal pill and the Detailed element; the App Store source is below)
// =============================================================================================
// A small tracker that takes bytes from any source and drives one Island element. Everything here runs on the main
// thread. Sources call OITIDownloadUpdate while a download runs and OITIDownloadFinish when it ends.

static NSMutableDictionary<NSString *, NSMutableDictionary *> *sDownloads;   // id -> title, bundleID, downloaded, total, speed, lastBytes, lastTime
static NSTimer *sDownloadTimer;
static BOOL sDownloadCollapsed = NO;            // dismissed or limit reached: stays away until a new download starts
static CFAbsoluteTime sDownloadNextPresentAttempt = 0;
static NSUInteger sDownloadCompleteGeneration = 0;

static NSString *OITIDownloadBytesText(double bytes) {
    return [NSByteCountFormatter stringFromByteCount:(long long)MAX(0.0, bytes) countStyle:NSByteCountFormatterCountStyleFile];
}

// Totals over every tracked download, or nil when none is running. A download is either byte-based (OITIDownloadUpdate) or
// fraction-only (OITIDownloadUpdateFraction, for sources such as the App Store that only know a percentage). When any
// download is fraction-only the snapshot is in fraction mode: `fraction` is the mean over all downloads, sizes and speed
// are not shown, and `eta` is the longest estimate (-1 unless every download is fraction-only and moving).
static NSDictionary *OITIDownloadSnapshot(void) {
    if (!sDownloads.count) return nil;
    double downloaded = 0, total = 0, speed = 0, fractionSum = 0, etaMax = 0;
    BOOL totalKnown = YES, anyFraction = NO, allFraction = YES, allPaused = YES, etaKnown = YES;
    NSString *title = nil, *bundleID = nil, *appName = nil;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (NSDictionary *download in sDownloads.allValues) {
        double itemDownloaded = [download[@"downloaded"] doubleValue];
        double size = [download[@"total"] doubleValue];
        downloaded += itemDownloaded;
        if (size > 0) total += size; else totalKnown = NO;
        speed += [download[@"speed"] doubleValue];
        if ([download[@"fractionOnly"] boolValue]) {
            anyFraction = YES;
            double fraction = [download[@"fraction"] doubleValue];
            fractionSum += fraction;
            double rate = [download[@"fractionRate"] doubleValue];
            BOOL stalled = now - [download[@"fractionChangeTime"] doubleValue] > 20.0;
            if (rate > 0 && fraction < 1.0 && !stalled && ![download[@"paused"] boolValue]) {
                etaMax = MAX(etaMax, (1.0 - fraction) / rate);
            } else {
                etaKnown = NO;
            }
        } else {
            allFraction = NO;
            etaKnown = NO;
            fractionSum += size > 0 ? MIN(1.0, itemDownloaded / size) : 0.0;
        }
        if (![download[@"paused"] boolValue]) allPaused = NO;
        if (!title) { title = download[@"title"]; bundleID = download[@"bundleID"]; appName = download[@"appName"]; }
    }
    return @{ @"count": @(sDownloads.count), @"downloaded": @(downloaded), @"total": @(totalKnown ? total : 0.0),
              @"speed": @(speed), @"title": title ?: @"Download", @"appName": appName ?: @"", @"bundleID": bundleID ?: @"",
              @"fractionMode": @(anyFraction), @"fraction": @(fractionSum / (double)sDownloads.count), @"paused": @(allPaused),
              @"eta": @(allFraction && etaKnown ? etaMax : -1.0) };
}

// "~45 s left", "~7 min left", "~1 h 5 min left"; empty when the estimate is unknown.
static NSString *OITIDownloadETAText(double seconds) {
    if (!isfinite(seconds) || seconds < 0) return @"";
    if (seconds < 60.0) return [NSString stringWithFormat:@"~%d s left", MAX(5, (int)(ceil(seconds / 5.0) * 5.0))];
    int minutes = (int)ceil(seconds / 60.0);
    if (minutes < 60) return [NSString stringWithFormat:@"~%d min left", minutes];
    return [NSString stringWithFormat:@"~%d h %d min left", minutes / 60, minutes % 60];
}

// ---- The Minimal look: OITI's own pill ----------------------------------------------------------
// Apple's layouts cannot hold this design. The compact and wide layouts are two slots either side of the sensor (the
// owner's screenshot of the wide build showed only the icon and the percentage, none of the body), and the expanded
// layout adds the sensor row above its body. So the Minimal look is drawn by OITI: a black capsule in a window of its
// own at the top centre, above the Island's window. Touches outside the pill fall through. Its width, height and
// distance from the top are settings, so the size can be tuned on the phone without a rebuild. Portrait only.
static void OITIDownloadPillSwiped(void);

static UIWindowLevel OITIDownloadPillWindowLevel(void) {
    UIWindowLevel level = UIWindowLevelAlert + 1000.0;
    for (UIView *view in sLiveApertureWindows.allObjects) {
        if ([view isKindOfClass:[UIWindow class]]) level = MAX(level, ((UIWindow *)view).windowLevel + 1.0);
    }
    return level;
}

// SpringBoard's windows belong to a window scene. A window created without one can be "visible" yet never drawn on
// iOS 16, so the pill's window is built in the same scene as the Island's own window (the most reliable match), or in any
// window scene the application knows.
static UIWindowScene *OITIDownloadPillWindowScene(void) {
    for (UIView *view in sLiveApertureWindows.allObjects) {
        UIWindowScene *scene = [view isKindOfClass:[UIWindow class]] ? ((UIWindow *)view).windowScene : nil;
        if (scene) return scene;
    }
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)scene;
    }
    return nil;
}

// ---- Where the Island is -------------------------------------------------------------------------
// The pill covers the Island, so it needs the Island's rectangle on screen: its top, its height (the "sensor row" the pill
// keeps clear at its own top, like the expanded Island) and its width and centre. The Island's own pill view
// (SBSystemApertureContainerView, the rounded black shape) is looked for in the Island's windows and converted to screen
// coordinates, which includes OITI's position and scale transforms. If none is on screen (the Island is idle and not
// drawn on a phone without the hardware) or it looks wrong, the rectangle is computed from the stock idle size (125 x
// 36.667 window units) times the Island Size sliders and the window's scale, and the top comes from a constant.
static const CGFloat kOITIIslandStockWidth = 125.0;
static const CGFloat kOITIIslandStockHeight = 36.667;
static const CGFloat kOITIIslandFallbackTop = 11.0;

static void OITICollectIslandRects(UIView *view, Class containerClass, NSUInteger depth, NSMutableArray<NSValue *> *rects) {
    if (containerClass && [view isKindOfClass:containerClass]) {
        if (!view.hidden && view.alpha > 0.01) {
            CGRect rect = [[UIScreen mainScreen].coordinateSpace convertRect:view.bounds fromCoordinateSpace:view];
            if (rect.size.width > 20.0 && rect.size.height > 10.0) [rects addObject:[NSValue valueWithCGRect:rect]];
        }
        return;   // not inside the pill
    }
    if (depth >= 8) return;
    for (UIView *subview in view.subviews) OITICollectIslandRects(subview, containerClass, depth + 1, rects);
}

// Sets *rectOut to the Island pill in screen points and says where it came from.
static void OITIIslandPillRect(CGRect *rectOut, NSString **sourceOut) {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    Class containerClass = NSClassFromString(@"SBSystemApertureContainerView");
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    CGFloat scaleX = 1.0, scaleY = 1.0;
    BOOL haveScale = NO;
    for (UIView *view in sLiveApertureWindows.allObjects) {
        if (![view isKindOfClass:[UIWindow class]] || view.hidden) continue;
        OITICollectIslandRects(view, containerClass, 0, rects);
        if (!haveScale && view.transform.a > 0.1 && view.transform.d > 0.1) {
            scaleX = view.transform.a;
            scaleY = view.transform.d;
            haveScale = YES;
        }
    }
    CGFloat computedWidth = kOITIIslandStockWidth * sMetricsSensorX * scaleX;
    CGFloat computedHeight = kOITIIslandStockHeight * sMetricsSensorY * scaleY;

    // The topmost candidate (the widest if two start at the same height).
    CGRect best = CGRectNull;
    for (NSValue *value in rects) {
        CGRect rect = value.CGRectValue;
        if (CGRectIsNull(best) || rect.origin.y < best.origin.y - 1.0 ||
            (fabs(rect.origin.y - best.origin.y) <= 1.0 && rect.size.width > best.size.width)) best = rect;
    }
    BOOL plausible = !CGRectIsNull(best) && best.size.width >= 60.0 && best.size.width <= screen.width - 20.0 &&
                     best.origin.y >= -5.0 && best.origin.y <= 80.0 && best.size.height >= 20.0;
    if (plausible) {
        // An expanded Island is far taller than the sensor row; only its top and centre are of use then.
        CGFloat height = best.size.height <= 80.0 ? best.size.height : computedHeight;
        *rectOut = CGRectMake(best.origin.x, best.origin.y, best.size.width, height);
        *sourceOut = [NSString stringWithFormat:@"the Island's pill view (%lu candidate%@)", (unsigned long)rects.count, rects.count == 1 ? @"" : @"s"];
        return;
    }
    *rectOut = CGRectMake((screen.width - computedWidth) / 2.0, kOITIIslandFallbackTop, computedWidth, computedHeight);
    *sourceOut = [NSString stringWithFormat:@"computed from the stock size (%lu candidates, none usable)", (unsigned long)rects.count];
}

@interface OITIDownloadPillController : UIViewController
@end
@implementation OITIDownloadPillController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
@end

@interface OITIDownloadPillWindow : UIWindow
@end
@implementation OITIDownloadPillWindow
// Only the pill takes touches; everything else goes to whatever is underneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end



@implementation OITIDownloadPill {
    OITIDownloadPillWindow *_window;
    UIView *_pill;
    BOOL _dismissed;
    NSString *_geometryNote;
}
- (CGAffineTransform)collapsedTransform {
    // About a third of the height and half the width, kept at the top edge, like the Island growing from its idle size.
    return CGAffineTransformMake(0.5, 0, 0, 0.35, 0, -_pill.bounds.size.height * 0.325);
}
- (instancetype)init {
    if ((self = [super init])) {
        UIWindowScene *scene = OITIDownloadPillWindowScene();
        _window = scene ? [[OITIDownloadPillWindow alloc] initWithWindowScene:scene]
                        : [[OITIDownloadPillWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _window.backgroundColor = [UIColor clearColor];
        OITIDownloadPillController *controller = [[OITIDownloadPillController alloc] init];
        controller.view.backgroundColor = [UIColor clearColor];
        _window.rootViewController = controller;
        _level = OITIDownloadPillWindowLevel();
        _window.windowLevel = _level;
        _pill = [[UIView alloc] initWithFrame:CGRectZero];
        _pill.backgroundColor = [UIColor blackColor];
        _pill.layer.cornerCurve = kCACornerCurveContinuous;
        _content = [[OITIMinimalDownloadView alloc] initWithFrame:CGRectZero];
        [_pill addSubview:_content];
        [controller.view addSubview:_pill];
        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped)];
        swipe.direction = UISwipeGestureRecognizerDirectionUp;
        [_pill addGestureRecognizer:swipe];
        [self relayout];
    }
    return self;
}
- (void)swiped { OITIDownloadPillSwiped(); }
// One line describing why the pill is or is not on screen. Written right after it is shown and again 0.8 s later.
- (void)logState:(NSString *)when {
    CALayer *shown = _pill.layer.presentationLayer;
    [sLog logTag:@"DOWNLOAD" format:@"pill %@: window hidden=%d scene=%@ level=%.0f key=%d pillWindowMatches=%d pill hidden=%d alpha=%.2f onScreenFrame=%@ | %@",
     when, _window.hidden, _window.windowScene ? NSStringFromClass([_window.windowScene class]) : @"none", (double)_window.windowLevel,
     _window.isKeyWindow, _pill.window == _window, _pill.hidden, _pill.alpha, shown ? NSStringFromCGRect(shown.frame) : @"none",
     _geometryNote ?: @"no geometry"];
}
- (void)relayout {
    if (!CGAffineTransformIsIdentity(_pill.transform)) return;   // mid-animation: the next refresh will do it
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGRect island = CGRectZero;
    NSString *source = nil;
    OITIIslandPillRect(&island, &source);

    // The pill starts at the Island's top, is centred on it and wide enough to cover it. Its top row is the Island's own
    // height and stays empty (the sensor row of the expanded Island); the content sits under it.
    CGFloat rowHeight = MAX(24.0, MIN(60.0, island.size.height));
    CGFloat width = MAX(MAX(200.0, sDownloadPillWidth), island.size.width + 32.0);
    width = MIN(width, screen.width - 16.0);
    CGFloat centerX = CGRectGetMidX(island);
    CGFloat x = MAX(8.0, MIN(screen.width - width - 8.0, centerX - width / 2.0));
    CGFloat contentTop = rowHeight + 3.0;
    CGFloat height = contentTop + kOITIMinimalHeight + sDownloadPillBottomPadding;
    _pill.frame = CGRectMake(floor(x), island.origin.y + sDownloadPillNudgeY, width, height);
    CGFloat radius = MIN(height / 2.0, MAX(rowHeight / 2.0 + 6.0, 22.0));
    _pill.layer.cornerRadius = radius;
    CGFloat padding = MAX(16.0, radius * 0.75);
    _content.frame = CGRectMake(padding, contentTop, MAX(100.0, width - 2.0 * padding), kOITIMinimalHeight);
    _geometryNote = [NSString stringWithFormat:@"island=%@ (%@) -> pill=%@", NSStringFromCGRect(island), source, NSStringFromCGRect(_pill.frame)];
}
- (void)refreshOrientation {
    _pill.hidden = UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation);   // portrait only
}
- (void)present {
    _dismissed = NO;
    _window.hidden = NO;
    [_window.rootViewController.view layoutIfNeeded];
    _pill.alpha = 0.0;
    _pill.transform = [self collapsedTransform];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self->_pill.alpha = 1.0; self->_pill.transform = CGAffineTransformIdentity; } completion:nil];
    [self logState:@"shown"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_dismissed) [self logState:@"0.8 s later"];
    });
}
- (void)dismiss {
    _dismissed = YES;
    [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                     animations:^{ self->_pill.alpha = 0.0; self->_pill.transform = [self collapsedTransform]; }
                     completion:^(BOOL finished) { if (self->_dismissed) self->_window.hidden = YES; }];
}
@end

OITIDownloadPill *sDownloadPill;   // the Minimal look, while it is on screen

static void OITIDownloadPillPresent(NSDictionary *snapshot) {
    OITIDownloadPill *pill = [[OITIDownloadPill alloc] init];
    sDownloadPill = pill;
    sDownloadShownAt = CFAbsoluteTimeGetCurrent();
    [pill present];
    [sLog logTag:@"DOWNLOAD" format:@"progress pill up for %@ (window level %.0f)", snapshot[@"title"], (double)pill.level];
}

void OITIDownloadPillDismiss(NSString *reason) {
    OITIDownloadPill *pill = sDownloadPill;
    if (!pill) return;
    sDownloadPill = nil;
    [pill dismiss];
    [sLog logTag:@"DOWNLOAD" format:@"progress pill dismissed (%@)", reason];
}

// A swipe up: gone, and it stays away until the next download starts.
static void OITIDownloadPillSwiped(void) {
    sDownloadCollapsed = YES;
    OITIDownloadPillDismiss(@"swipe");
}

// "App Name - File Name" for one download, "N downloads" for several.
static NSString *OITIDownloadHeaderText(NSDictionary *snapshot) {
    NSUInteger count = [snapshot[@"count"] unsignedIntegerValue];
    if (count > 1) return [NSString stringWithFormat:@"%lu downloads", (unsigned long)count];
    NSString *appName = snapshot[@"appName"];
    NSString *title = snapshot[@"title"];
    return appName.length ? [NSString stringWithFormat:@"%@ - %@", appName, title] : title;
}

// Writes the snapshot into whichever look is showing. complete shows the finished state.
// ending: 0 = running, 1 = completed, 2 = cancelled (a short red "Cancelled" state).
static void OITIDownloadUpdateViews(NSDictionary *snapshot, NSInteger ending) {
    BOOL complete = ending == 1;
    BOOL cancelled = ending == 2;
    NSDictionary *item = sDownloadItem;
    OITIMinimalDownloadView *minimal = sDownloadPill.content;
    if ((!item && !minimal) || !snapshot) return;
    double downloaded = [snapshot[@"downloaded"] doubleValue];
    double total = [snapshot[@"total"] doubleValue];
    double speed = [snapshot[@"speed"] doubleValue];
    BOOL fractionMode = [snapshot[@"fractionMode"] boolValue];
    BOOL paused = [snapshot[@"paused"] boolValue];
    NSString *etaText = (complete || paused) ? @"" : OITIDownloadETAText([snapshot[@"eta"] doubleValue]);
    double fraction = complete ? 1.0 : (fractionMode ? [snapshot[@"fraction"] doubleValue] : (total > 0 ? downloaded / total : 0.0));
    NSString *percent = (fractionMode || total > 0 || complete) ? [NSString stringWithFormat:@"%d%%", (int)floor(fraction * 100.0 + 0.0001)] : @"…";
    NSString *header = OITIDownloadHeaderText(snapshot);

    if (minimal && cancelled) {
        [minimal resetCompletion];
        [minimal setHeader:header downloaded:@"Cancelled" total:@"" speed:@"" percent:percent fraction:fraction complete:NO];
        [minimal.bar setCancelled:YES];
        [sDownloadPill refreshOrientation];
        return;
    }
    if (minimal && fractionMode) {
        // A source that only knows a percentage: no sizes and no speed, a state word above the bar and the estimate below it.
        [minimal setHeader:header
                downloaded:complete ? @"Download complete" : (paused ? @"Paused" : @"Downloading")
                     total:etaText
                     speed:complete ? @"Done" : @""
                   percent:percent fraction:fraction complete:complete];
        if (complete) [minimal playCompletion]; else [minimal resetCompletion];
        [sDownloadPill refreshOrientation];
        return;
    }
    if (minimal) {
        [minimal setHeader:header
                downloaded:OITIDownloadBytesText(complete && total > 0 ? total : downloaded)
                     total:total > 0 ? OITIDownloadBytesText(total) : @"?"
                     speed:complete ? @"Done" : [NSString stringWithFormat:@"%@/s", OITIDownloadBytesText(speed)]
                   percent:percent fraction:fraction complete:complete];
        if (complete) [minimal playCompletion]; else [minimal resetCompletion];
        [sDownloadPill refreshOrientation];
        return;
    }
    UILabel *trailing = (UILabel *)item[@"trailingView"];
    OITIProgressBarView *bar = item[@"downloadBar"];
    UILabel *detail = item[@"downloadDetail"];
    UILabel *headline = (UILabel *)item[@"primaryView"];
    if ([headline isKindOfClass:[UILabel class]] && ![headline.text isEqualToString:header]) headline.text = header;
    NSString *detailText;
    if (cancelled) {
        detailText = @"Download cancelled";
    } else if (complete) {
        detailText = fractionMode ? @"Download complete" : [NSString stringWithFormat:@"Download complete · %@", OITIDownloadBytesText(downloaded)];
    } else if (fractionMode) {
        NSString *state = paused ? @"Paused" : etaText;
        detailText = state.length ? [NSString stringWithFormat:@"%@ · %@", percent, state] : percent;
    } else if (total > 0) {
        detailText = [NSString stringWithFormat:@"%@ of %@ · %@/s", OITIDownloadBytesText(downloaded), OITIDownloadBytesText(total),
                      OITIDownloadBytesText(speed)];
    } else {
        detailText = [NSString stringWithFormat:@"%@ · %@/s", OITIDownloadBytesText(downloaded), OITIDownloadBytesText(speed)];
    }
    if (![detail.text isEqualToString:detailText]) detail.text = detailText;
    [bar setComplete:complete];
    if (cancelled) [bar setCancelled:YES];
    [bar setFraction:fraction animated:YES];
    if ([trailing isKindOfClass:[UILabel class]] && ![trailing.text isEqualToString:percent]) {
        trailing.text = percent;
        [trailing sizeToFit];
    }
}

static void OITIDownloadsEnsureTimer(void);
static void OITIFakeDownloadAdvance(void);

// Presents, updates and ends the element for the current state. Called after every update and from the timer.
void OITIDownloadsRefresh(void) {
    if (!sDownloadProgressEnabled) {
        if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"feature-disabled");
        OITIDownloadPillDismiss(@"feature-disabled");
        return;
    }
    NSDictionary *snapshot = OITIDownloadSnapshot();
    if (!snapshot) return;   // OITIDownloadFinish handles the end
    sDownloadCompleteGeneration++;   // a pending "complete" removal no longer applies
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();

    // Return to idle by size or by time, whichever look is showing.
    if (sDownloadItem || sDownloadPill) {
        double limitBytes = sDownloadIdleAfterMB * 1000.0 * 1000.0;   // decimal MB, like the size text
        BOOL byBytes = limitBytes > 0 && ![snapshot[@"fractionMode"] boolValue] && [snapshot[@"downloaded"] doubleValue] >= limitBytes;   // sizes are unknown in fraction mode
        BOOL byTime = sDownloadIdleAfterSeconds > 0 && now - sDownloadShownAt >= sDownloadIdleAfterSeconds;
        if (byBytes || byTime) {
            [sLog logTag:@"DOWNLOAD" format:@"limit reached (%@): the Island returns to idle, the download carries on",
             byBytes ? [NSString stringWithFormat:@"%@ downloaded", OITIDownloadBytesText([snapshot[@"downloaded"] doubleValue])]
                     : [NSString stringWithFormat:@"%.0f s on screen", (double)(now - sDownloadShownAt)]];
            sDownloadCollapsed = YES;
            if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"download-limit");
            OITIDownloadPillDismiss(@"download-limit");
            return;
        }
    }

    if (sDownloadStyle == 0) {
        // Minimal: OITI's own pill. Nothing of the Apple element is used.
        if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"restyle");
        if (!sDownloadPill && !sDownloadCollapsed && now >= sDownloadNextPresentAttempt) OITIDownloadPillPresent(snapshot);
        OITIDownloadUpdateViews(snapshot, NO);
        return;
    }
    OITIDownloadPillDismiss(@"restyle");

    // Detailed: the Apple element.
    if (sDownloadItem) {
        // The system can end an element on its own (its alert timer) without telling OITI. If the bar was on screen and
        // should still be the one showing but its views have left the window, record that and put it back. At most
        // five times per download, so a system that keeps ending it can never make the bar flicker forever.
        UIView *probe = sDownloadItem[@"downloadBar"];
        if (probe && sIslandNoticeItems.lastObject == sDownloadItem) {
            if (probe.window) {
                sDownloadItem[@"downloadSeenOnScreen"] = @YES;
            } else if ([sDownloadItem[@"downloadSeenOnScreen"] boolValue]) {
                sDownloadDropCount++;
                [sLog logTag:@"DOWNLOAD" format:@"the progress element left the screen after %.0f s but nothing in OITI removed it, so the system ended it (drop %lu of 5)",
                 (double)(now - sDownloadShownAt), (unsigned long)sDownloadDropCount];
                if (sDownloadDropCount >= 5) {
                    sDownloadCollapsed = YES;
                    [sLog logTag:@"DOWNLOAD" format:@"giving up on putting the progress element back for this download"];
                } else {
                    // Wait longer after every drop (1.5, 4.5, 13.5, 30 s): if something else really took the Island over,
                    // such as a call, the bar should not keep pushing back in.
                    sDownloadNextPresentAttempt = now + MIN(30.0, 1.5 * pow(3.0, (double)(sDownloadDropCount - 1)));
                }
                OITIRemoveNoticeItem(sDownloadItem, @"system-dismissed");
                return;
            }
        }
    } else if (!sDownloadCollapsed && now >= sDownloadNextPresentAttempt) {
        NSString *message = [snapshot[@"fractionMode"] boolValue]
            ? [NSString stringWithFormat:@"%d%%", (int)floor([snapshot[@"fraction"] doubleValue] * 100.0 + 0.0001)]
            : [NSString stringWithFormat:@"%@ of %@", OITIDownloadBytesText([snapshot[@"downloaded"] doubleValue]),
               [snapshot[@"total"] doubleValue] > 0 ? OITIDownloadBytesText([snapshot[@"total"] doubleValue]) : @"?"];
        NSDictionary *info = @{ @"bundleID": snapshot[@"bundleID"], @"appName": snapshot[@"appName"], @"title": snapshot[@"title"], @"message": message };
        if (OITIPresentNoticeElement(info, @"download-progress")) {
            [sLog logTag:@"DOWNLOAD" format:@"progress element up for %@", snapshot[@"title"]];
        } else {
            sDownloadNextPresentAttempt = now + 10.0;   // not ready, recovering or failed: try again later, not every tick
        }
    }
    OITIDownloadUpdateViews(snapshot, NO);
}

// Called from OITIRemoveNoticeItem when the download element leaves. Removals we made ourselves are recorded as such;
// anything else (a swipe, a notification replacing it, stack capacity) keeps it away until the next download starts.
void OITIDownloadItemRemoved(NSDictionary *item, NSString *reason) {
    sDownloadItem = nil;
    NSArray<NSString *> *ours = @[@"download-limit", @"download-complete", @"download-cancelled", @"feature-disabled",
                                  @"restyle", @"system-dismissed"];
    if (![ours containsObject:reason]) {
        sDownloadCollapsed = YES;
        [sLog logTag:@"DOWNLOAD" format:@"progress element removed (%@): it stays away until the next download starts", reason];
    }
}

// Sources call this with the bytes so far. total is 0 when unknown. Speed is smoothed from the byte deltas.
static void OITIDownloadUpdate(NSString *identifier, NSString *appName, NSString *title, NSString *bundleID, double downloaded, double total) {
    if (!identifier.length) return;
    if (!sDownloads) sDownloads = [NSMutableDictionary dictionary];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSMutableDictionary *download = sDownloads[identifier];
    if (!download) {
        download = [NSMutableDictionary dictionary];
        sDownloads[identifier] = download;
        download[@"speed"] = @0.0;
        download[@"lastBytes"] = @(MAX(0.0, downloaded));
        download[@"lastTime"] = @(now);
        sDownloadCollapsed = NO;   // a new download brings the element back
        sDownloadNextPresentAttempt = 0;
        sDownloadDropCount = 0;
        [sLog logTag:@"DOWNLOAD" format:@"started %@ (%@), total %@", identifier, title ?: @"?",
         total > 0 ? OITIDownloadBytesText(total) : @"unknown"];
    }
    download[@"title"] = title.length ? title : @"Download";
    download[@"appName"] = appName ?: @"";
    download[@"bundleID"] = bundleID ?: @"";
    download[@"total"] = @(MAX(0.0, total));
    download[@"downloaded"] = @(MAX(0.0, downloaded));
    double dt = now - [download[@"lastTime"] doubleValue];
    if (dt >= 0.25) {
        double instant = MAX(0.0, downloaded - [download[@"lastBytes"] doubleValue]) / dt;
        double previous = [download[@"speed"] doubleValue];
        download[@"speed"] = @(previous > 0 ? previous * 0.7 + instant * 0.3 : instant);
        download[@"lastBytes"] = @(MAX(0.0, downloaded));
        download[@"lastTime"] = @(now);
    }
    OITIDownloadsEnsureTimer();
    OITIDownloadsRefresh();
}

// Sources that only know a percentage (the App Store) call this instead. fraction is 0 to 1. The estimate of the time
// left comes from how fast the fraction moves (smoothed, unknown while paused or when it has not moved for 20 s).
void OITIDownloadUpdateFraction(NSString *identifier, NSString *appName, NSString *title, NSString *bundleID, double fraction, BOOL paused) {
    if (!identifier.length) return;
    if (!sDownloads) sDownloads = [NSMutableDictionary dictionary];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double clamped = isfinite(fraction) ? MAX(0.0, MIN(1.0, fraction)) : 0.0;
    NSMutableDictionary *download = sDownloads[identifier];
    if (!download) {
        download = [NSMutableDictionary dictionary];
        sDownloads[identifier] = download;
        download[@"fractionOnly"] = @YES;
        download[@"fractionRate"] = @0.0;
        download[@"fractionLast"] = @(clamped);
        download[@"fractionLastTime"] = @(now);
        download[@"fractionChangeTime"] = @(now);
        sDownloadCollapsed = NO;   // a new download brings the element back
        sDownloadNextPresentAttempt = 0;
        sDownloadDropCount = 0;
        [sLog logTag:@"DOWNLOAD" format:@"started %@ (%@), percentage only (no sizes)", identifier, title ?: @"?"];
    }
    download[@"title"] = title.length ? title : @"Download";
    download[@"appName"] = appName ?: @"";
    download[@"bundleID"] = bundleID ?: @"";
    download[@"fraction"] = @(clamped);
    download[@"paused"] = @(paused);
    double last = [download[@"fractionLast"] doubleValue];
    if (clamped > last + 0.0005) {
        double dt = now - [download[@"fractionLastTime"] doubleValue];
        if (dt >= 0.25) {
            double instant = (clamped - last) / dt;
            double previous = [download[@"fractionRate"] doubleValue];
            download[@"fractionRate"] = @(previous > 0 ? previous * 0.7 + instant * 0.3 : instant);
        }
        download[@"fractionLast"] = @(clamped);
        download[@"fractionLastTime"] = @(now);
        download[@"fractionChangeTime"] = @(now);
    } else if (clamped < last - 0.0005) {   // started over: forget the old rate
        download[@"fractionRate"] = @0.0;
        download[@"fractionLast"] = @(clamped);
        download[@"fractionLastTime"] = @(now);
        download[@"fractionChangeTime"] = @(now);
    }
    OITIDownloadsEnsureTimer();
    OITIDownloadsRefresh();
}

// outcome: 0 = drop quietly (the feature or the source was switched off), 1 = completed (a short "complete" state with the
// check animation), 2 = cancelled (a short red "Cancelled" state). With several downloads only the one that ended is removed.
static void OITIDownloadEnd(NSString *identifier, NSInteger outcome) {
    NSMutableDictionary *download = sDownloads[identifier];
    if (!download) return;
    BOOL completed = outcome == 1;
    double total = [download[@"total"] doubleValue];
    if (completed && total > 0) download[@"downloaded"] = @(total);
    if (completed && [download[@"fractionOnly"] boolValue]) download[@"fraction"] = @1.0;
    NSDictionary *finalSnapshot = OITIDownloadSnapshot();
    [sDownloads removeObjectForKey:identifier];
    [sLog logTag:@"DOWNLOAD" format:@"%@ %@", completed ? @"finished" : (outcome == 2 ? @"cancelled" : @"dropped"), identifier];
    OITIDownloadsEnsureTimer();
    if (sDownloads.count) {
        OITIDownloadsRefresh();
        return;
    }
    if (!sDownloadItem && !sDownloadPill) return;
    if (!completed) {
        if (outcome == 2 && finalSnapshot) {
            OITIDownloadUpdateViews(finalSnapshot, 2);
            NSUInteger cancelGeneration = ++sDownloadCompleteGeneration;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (cancelGeneration == sDownloadCompleteGeneration && !sDownloads.count) {
                    if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"download-cancelled");
                    OITIDownloadPillDismiss(@"download-cancelled");
                }
            });
            return;
        }
        if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"download-cancelled");
        OITIDownloadPillDismiss(@"download-cancelled");
        return;
    }
    OITIDownloadUpdateViews(finalSnapshot, 1);
    NSUInteger generation = ++sDownloadCompleteGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == sDownloadCompleteGeneration && !sDownloads.count) {
            if (sDownloadItem) OITIRemoveNoticeItem(sDownloadItem, @"download-complete");
            OITIDownloadPillDismiss(@"download-complete");
        }
    });
}

// A download ended: completed YES shows the "complete" state, NO shows "Cancelled" (the last one only).
void OITIDownloadFinish(NSString *identifier, BOOL completed) {
    OITIDownloadEnd(identifier, completed ? 1 : 2);
}

// A download stops being tracked without a verdict (the source was switched off): the bar goes at once.
void OITIDownloadDrop(NSString *identifier) {
    OITIDownloadEnd(identifier, 0);
}

static void OITIDownloadsEnsureTimer(void) {
    BOOL needed = sDownloads.count > 0;
    if (needed && !sDownloadTimer) {
        sDownloadTimer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            OITIFakeDownloadAdvance();
            OITIDownloadsRefresh();
        }];
        [[NSRunLoop mainRunLoop] addTimer:sDownloadTimer forMode:NSRunLoopCommonModes];
    } else if (!needed && sDownloadTimer) {
        [sDownloadTimer invalidate];
        sDownloadTimer = nil;
    }
}

// ---- Test download (started and stopped from Settings > OITI > Download Progress) ---------------
static BOOL sFakeDownloadActive = NO;
static double sFakeDownloadBytes = 0, sFakeDownloadTotal = 0, sFakeDownloadSpeed = 0;
static CFAbsoluteTime sFakeDownloadLastTick = 0;
static NSString * const kOITIFakeDownloadIdentifier = @"oiti.test-download";

// Reports the simulated bytes, or only a whole-percent fraction when DownloadTestFractionOnly is on (to try the
// percentage-only look without a real download).
static void OITIFakeDownloadReport(double bytes) {
    if (sDownloadTestFractionOnly) {
        double fraction = sFakeDownloadTotal > 0 ? floor(bytes / sFakeDownloadTotal * 100.0) / 100.0 : 0.0;
        OITIDownloadUpdateFraction(kOITIFakeDownloadIdentifier, @"App Store", @"Test Download", @"com.apple.AppStore", fraction, NO);
    } else {
        OITIDownloadUpdate(kOITIFakeDownloadIdentifier, @"App Store", @"Test Download", @"com.apple.AppStore", bytes, sFakeDownloadTotal);
    }
}

void OITIFakeDownloadStart(void) {
    if (sFakeDownloadActive) {
        // Already running: Start brings a bar that was dismissed or timed out back.
        [sLog logTag:@"DOWNLOAD" format:@"test download is already running; showing the bar again"];
        sDownloadCollapsed = NO;
        sDownloadNextPresentAttempt = 0;
        sDownloadDropCount = 0;
        OITIDownloadsRefresh();
        return;
    }
    CGFloat sizeMB = isfinite(sDownloadTestSizeMB) ? MAX(50.0, MIN(5000.0, sDownloadTestSizeMB)) : 800.0;
    sFakeDownloadTotal = sizeMB * 1000.0 * 1000.0;
    sFakeDownloadBytes = 0;
    sFakeDownloadSpeed = 8.0e6 + (double)arc4random_uniform(6000000);
    sFakeDownloadLastTick = CFAbsoluteTimeGetCurrent();
    sFakeDownloadActive = YES;
    [sLog logTag:@"DOWNLOAD" format:@"test download started: %@ (Download Progress is %@)", OITIDownloadBytesText(sFakeDownloadTotal),
     sDownloadProgressEnabled ? @"on" : @"OFF, so nothing will show"];
    OITIFakeDownloadReport(0);
}

// Called from the tracker's timer: moves the simulated bytes along with a speed that drifts between 2 and 28 MB/s.
static void OITIFakeDownloadAdvance(void) {
    if (!sFakeDownloadActive) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double dt = MAX(0.0, MIN(2.0, now - sFakeDownloadLastTick));
    sFakeDownloadLastTick = now;
    double drift = ((double)arc4random_uniform(2001) - 1000.0) / 1000.0 * 1.5e6;
    sFakeDownloadSpeed = MAX(2.0e6, MIN(28.0e6, sFakeDownloadSpeed + drift));
    sFakeDownloadBytes = MIN(sFakeDownloadTotal, sFakeDownloadBytes + sFakeDownloadSpeed * dt);
    if (sFakeDownloadBytes >= sFakeDownloadTotal) {
        sFakeDownloadActive = NO;
        OITIFakeDownloadReport(sFakeDownloadTotal);
        OITIDownloadFinish(kOITIFakeDownloadIdentifier, YES);
        return;
    }
    OITIFakeDownloadReport(sFakeDownloadBytes);
}

void OITIFakeDownloadStop(void) {
    if (!sFakeDownloadActive) return;
    sFakeDownloadActive = NO;
    OITIDownloadFinish(kOITIFakeDownloadIdentifier, NO);
}
