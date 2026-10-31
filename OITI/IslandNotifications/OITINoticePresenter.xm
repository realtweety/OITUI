// OITINoticePresenter.xm -- puts a notification on the Island and takes it off again (OITI Island notifications).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 4, IslandNotifications).
// The presenter: the request-to-element path (OITIPresentNoticeElement), the notice stack and its timeouts, the Island element for a
// download, the developer test element, the haptic, and the run-time banner hook's request handling. State that the hooks and the
// other files share is declared in OITIIslandNotifications.h.

#import "Shared/OITIShared.h"
#import "IslandNotifications/OITIIslandNotifications.h"
#import "Diagnostics/OITIDiagnostics.h"
#import "DownloadProgress/OITIDownloadProgress.h"

// Apple's SAUISystemApertureManager instances. sRegisteringManager is the one that last registered an element (the
// manager for the Island content scene); sSeenManager is the first one that answered orderedElementViewControllers.
// Weak: we must not keep Apple's objects alive.
__weak id sRegisteringManager;

__weak id sSeenManager;

__weak id sSystemApertureController;   // SBSystemApertureController: the registrar real providers use

// Strong references to the elements we registered (element, provider, registration, view), so ARC does not release
// them while the Island still shows them.
NSMutableArray<NSDictionary *> *sIslandNoticeItems;

static id sPendingNoticeRequest;   // the NCNotificationRequest being presented, kept with its element for the tap action

NSMutableDictionary *sDownloadItem;   // the Island element showing download progress, or nil

CFAbsoluteTime sDownloadShownAt = 0;  // when it went up, for the time limit

NSUInteger sDownloadDropCount = 0;    // times the system ended the element on its own during this download

static const NSUInteger kOITINoticeStackLimit = 4;   // one expanded plus three compact, or four compact

// Layout-mode numbers copied from the first real (Apple) element that registers, so our element can use values Apple
// itself uses instead of guessed enum numbers. Keys: preferred, minimum, maximum.
NSDictionary<NSString *, NSNumber *> *sRealLayoutValues;

BOOL sPoCOurRegistrationInFlight = NO;

BOOL sPoCDisabledAfterFailure = NO;   // set after 5 guard catches; cleared only by a respring

int sPoCFailureCount = 0;

// Existing items remain registered while their preferred mode changes. Registering or invalidating an item
// causes Apple's authority to reevaluate the ordering and choose the new preferred layout.
static void OITIScheduleNoticeTimeout(NSMutableDictionary *item);

// Expire or swipe away one item. If the visible newest item leaves, promote the newest survivor.
void OITIRemoveNoticeItem(NSDictionary *item, NSString *reason) {
    NSUInteger index = [sIslandNoticeItems indexOfObjectIdenticalTo:item];
    if (index == NSNotFound) return;
    BOOL wasNewest = (index == sIslandNoticeItems.count - 1);
    dispatch_block_t timeout = item[@"timeoutBlock"];
    if (timeout) dispatch_block_cancel(timeout);
    for (id playbackObserver in item[@"playbackObservers"] ?: @[]) {
        [[NSNotificationCenter defaultCenter] removeObserver:playbackObserver];
    }
    [(OITIStartupVideoView *)item[@"startupVideoView"] stopPlayback];
    if (wasNewest && index > 0) {
        OITIScheduleNoticeTimeout((NSMutableDictionary *)sIslandNoticeItems[index - 1]);
        OITISetNoticeLayout(sIslandNoticeItems[index - 1], OITINoticeStyle(), YES);
    }
    OITIDismissNoticeItem(item);
    [sIslandNoticeItems removeObjectAtIndex:index];
    if (item == sStartupHelloItem) sStartupHelloItem = nil;
    if (item == sDownloadItem) OITIDownloadItemRemoved(item, reason);
    OITIRefreshNewestNoticeComposite();
    [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK removed %@ reason=%@ remaining=%lu",
     OITIKVCObject(item[@"element"], @"elementIdentifier"), reason, (unsigned long)sIslandNoticeItems.count];
    if (sIslandNoticeItems.count == 0) {
        OITIRestoreCorners();
        OITIClearElementBreadcrumb();
    }
}

// Give a notice a fresh lifetime when it is demoted from the expanded slot to the compact list.
// The weak capture avoids a retain cycle between the item dictionary and its timeout block.
static void OITIScheduleNoticeTimeout(NSMutableDictionary *item) {
    dispatch_block_t previous = item[@"timeoutBlock"];
    if (previous) dispatch_block_cancel(previous);
    __weak NSMutableDictionary *weakItem = item;
    dispatch_block_t timeout = dispatch_block_create((dispatch_block_flags_t)0, ^{
        NSMutableDictionary *strongItem = weakItem;
        if (strongItem && [sIslandNoticeItems containsObject:strongItem]) {
            OITIRemoveNoticeItem(strongItem, @"timeout");
        }
    });
    item[@"timeoutBlock"] = timeout;
    NSTimeInterval duration = [item[@"timeoutDuration"] respondsToSelector:@selector(doubleValue)]
        ? [item[@"timeoutDuration"] doubleValue] : sIslandNoticeDuration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), timeout);
}

// Tries the invalidation selectors Apple's assertion-like objects usually have. Logs what it found.
void OITIDismissNoticeItem(NSDictionary *item) {
    if (sIslandNoticeItems.count <= 1) OITIRestoreCorners();
    for (UIGestureRecognizer *recognizer in item[@"recognizers"]) [recognizer.view removeGestureRecognizer:recognizer];
    if ([item isKindOfClass:[NSMutableDictionary class]]) {   // break the item -> actions -> dismiss block -> item cycle
        NSMutableDictionary *mutableItem = (NSMutableDictionary *)item;
        [mutableItem removeObjectForKey:@"actions"];
        [mutableItem removeObjectForKey:@"recognizers"];
    }
    id registration = item[@"registration"];
    id manager = item[@"manager"];
    id element = item[@"element"];
    BOOL done = NO;
    SEL realInvalidate = NSSelectorFromString(@"invalidateWithReason:layoutModeChangeReason:");
    if (registration && [registration respondsToSelector:realInvalidate]) {
        @try {
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(registration, realInvalidate, @"OITI", 0);
            done = YES;
            [sLog logLevel:1 tag:@"ELEMENT" format:@"dismissed element via invalidateWithReason:layoutModeChangeReason:"];
        } @catch (NSException *exception) {
            [sLog logTag:@"ELEMENT" format:@"dismiss via invalidateWithReason:layoutModeChangeReason: threw %@", exception.name];
        }
    }
    for (NSString *name in done ? @[] : @[@"invalidate", @"invalidateWithReason:"]) {
        SEL selector = NSSelectorFromString(name);
        if (registration && [registration respondsToSelector:selector]) {
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                if ([name hasSuffix:@":"]) [registration performSelector:selector withObject:@"OITI"];
                else [registration performSelector:selector];
#pragma clang diagnostic pop
                done = YES;
            } @catch (NSException *exception) {
                [sLog logTag:@"ELEMENT" format:@"dismiss via %@ threw %@", name, exception.name];
            }
            if (done) {
                [sLog logLevel:1 tag:@"ELEMENT" format:@"dismissed element via registration %@", name];
                break;
            }
        }
    }
    if (!done && manager && element) {
        for (NSString *name in @[@"unregisterElement:", @"removeElement:", @"invalidateElement:"]) {
            SEL selector = NSSelectorFromString(name);
            if (![manager respondsToSelector:selector]) continue;
            @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [manager performSelector:selector withObject:element];
#pragma clang diagnostic pop
                done = YES;
            } @catch (NSException *exception) {
                [sLog logTag:@"ELEMENT" format:@"dismiss via manager %@ threw %@", name, exception.name];
            }
            if (done) {
                [sLog logLevel:1 tag:@"ELEMENT" format:@"dismissed element via manager %@", name];
                break;
            }
        }
    }
    if (!done) {
        [sLog logTag:@"ELEMENT" format:@"could not dismiss the element: registration %@ has no invalidate selector. See PROBE lines.",
         OITIObjectSummary(registration)];
    }
}

// Creates one element from `info`, registers it and schedules its removal. Main thread only.
BOOL OITIPresentNoticeElement(NSDictionary<NSString *, NSString *> *info, NSString *reason) {
    @synchronized ([NSNull null]) { [sTraceSeen removeAllObjects]; }
    if (OITIElementRecoveryActive(reason)) return NO;
    if (sPoCDisabledAfterFailure) {
        [sLog logTag:@"ELEMENT" format:@"element creation is off until the next respring (the promotion guard caught %d exceptions)", sPoCFailureCount];
        return NO;
    }
    id manager = sRegisteringManager ?: sSeenManager;
    NSInteger registrarVariant = (NSInteger)[sOITIPreferences floatForKey:@"IslandNotificationsPoCRegistrar" default:0];
    id registrar = (registrarVariant == 0 && sSystemApertureController) ? sSystemApertureController : manager;
    if (!registrar) {
        [sLog logTag:@"ELEMENT" format:@"no SAUISystemApertureManager seen yet (%@): lock/unlock once or open the Island, then retry", reason];
        return NO;
    }
    Class elementClass = OITINoticeElementClass();
    Class providerClass = NSClassFromString(@"SBUISystemApertureCustomContentProvider");
    if (!elementClass || !providerClass) {
        [sLog logTag:@"ELEMENT" format:@"missing class: element=%d provider=%d", elementClass != nil, providerClass != nil];
        return NO;
    }
    if (![registrar respondsToSelector:@selector(registerElement:)]) {
        [sLog logTag:@"ELEMENT" format:@"registrar %@ does not respond to registerElement:", OITIObjectSummary(registrar)];
        return NO;
    }

    if (!sIslandNoticeItems) sIslandNoticeItems = [NSMutableArray array];
    BOOL startupHello = [reason isEqualToString:@"startup-hello"];
    BOOL downloadProgress = [reason isEqualToString:@"download-progress"];
    NSInteger style = (startupHello || downloadProgress) ? 2 : OITINoticeStyle();
    if (!sIslandNotificationStackEnabled && sIslandNoticeItems.count) {
        NSArray<NSDictionary *> *previousItems = [sIslandNoticeItems copy];
        for (NSDictionary *previous in previousItems) OITIRemoveNoticeItem(previous, @"stack-disabled-replaced");
        [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK disabled; replacing prior items with newest notification"];
    }
    if (sIslandNoticeItems.count && style != 0) {
        // The previous alert now enters the compact stack; its visible time starts again here.
        OITIScheduleNoticeTimeout((NSMutableDictionary *)sIslandNoticeItems.lastObject);
    }
    for (NSDictionary *existing in sIslandNoticeItems) OITISetNoticeLayout(existing, style, NO);

    NSMutableDictionary *item = nil;
    @try {
        Class containerClass = NSClassFromString(@"SBUISystemApertureContentProvider");
        if (!containerClass) {
            [sLog logTag:@"ELEMENT" format:@"missing class SBUISystemApertureContentProvider"];
            if (sIslandNoticeItems.count && style != 0) OITISetNoticeLayout(sIslandNoticeItems.lastObject, style, YES);
            return NO;
        }
        UIView *leadingView = nil, *trailingView = nil, *primaryView = nil, *secondaryView = nil;
        UILabel *secondaryBody = nil;
        OITIBuildNoticeViews(info, &leadingView, &trailingView, &primaryView, &secondaryView, &secondaryBody);
        OITIProgressBarView *downloadBar = nil;
        UILabel *downloadDetail = nil;
        if (downloadProgress) {
            // The Detailed look: the same icon and headline as a notice; the body is the bar and its text line.
            // (The Minimal look is not an Apple element at all, see the download pill.)
            secondaryView = OITIBuildDownloadStack(&downloadBar, &downloadDetail);
            secondaryBody = nil;
            CGRect headlineFrame = primaryView.frame;
            headlineFrame.size.width = 260;   // the headline text changes (name, "2 downloads"), so keep the width fixed
            primaryView.frame = headlineFrame;
        }
        OITIStartupVideoView *startupVideoView = startupHello ? OITIBuildStartupVideoView() : nil;
        if (startupVideoView) {
            // The normal notification chrome puts an app icon on the left and a short title on
            // the trailing side. A startup animation is the entire card, so leave those slots
            // empty and let the video occupy the expanded content area by itself.
            leadingView = [[UIView alloc] initWithFrame:CGRectZero];
            trailingView = [[UIView alloc] initWithFrame:CGRectZero];
            primaryView = startupVideoView;
            secondaryView = [[UIView alloc] initWithFrame:CGRectZero];
            secondaryBody = nil;
        }
        id leadingProvider = [[providerClass alloc] initWithView:leadingView];
        id trailingProvider = [[providerClass alloc] initWithView:trailingView];
        id primaryProvider = [[providerClass alloc] initWithView:primaryView];
        id secondaryProvider = [[providerClass alloc] initWithView:secondaryView];
        id provider = [[containerClass alloc] init];   // the container real elements use
        [(SBUISystemApertureContentProvider *)provider setLeadingContentViewProvider:leadingProvider];
        [(SBUISystemApertureContentProvider *)provider setTrailingContentViewProvider:trailingProvider];
        [(SBUISystemApertureContentProvider *)provider setPrimaryContentViewProvider:primaryProvider];
        [(SBUISystemApertureContentProvider *)provider setSecondaryContentViewProvider:secondaryProvider];
        NSString *identifier = [NSString stringWithFormat:@"com.wilburt.oiti.notification.%@", [NSUUID UUID].UUIDString];
        OITIElementIdentifierStub *identifierObject = [OITIElementIdentifierStub new];
        identifierObject.value = identifier;
        id element = [[elementClass alloc] initWithIdentifier:identifierObject contentProvider:provider];
        if (!provider || !element) {
            [sLog logTag:@"ELEMENT" format:@"creation failed: provider=%@ element=%@", OITIObjectSummary(provider), OITIObjectSummary(element)];
            if (sIslandNoticeItems.count && style != 0) OITISetNoticeLayout(sIslandNoticeItems.lastObject, style, YES);
            return NO;
        }
        OITIProbeObject(provider, @"provider");
        OITIProbeObject(leadingProvider, @"leadingProvider");
        OITIProbeObject(element, @"element");

        [sLog logTag:@"ELEMENT" format:@"our element before layout values: %@", OITIElementValuesSummary(element)];
        [sLog logTag:@"ELEMENT" format:@"our element parts: %@", OITIElementPartsSummary(element)];
        item = [NSMutableDictionary dictionary];
        item[@"leadingView"] = leadingView; item[@"trailingView"] = trailingView; item[@"leadingProvider"] = leadingProvider;
        item[@"primaryView"] = primaryView; item[@"secondaryView"] = secondaryView;
        item[@"secondaryStack"] = secondaryView; item[@"secondaryBody"] = secondaryBody; item[@"info"] = [info copy];
        item[@"primaryProvider"] = primaryProvider; item[@"secondaryProvider"] = secondaryProvider;
        item[@"trailingProvider"] = trailingProvider; item[@"provider"] = provider; item[@"element"] = element; item[@"manager"] = registrar;
        if (sPendingNoticeRequest) item[@"request"] = sPendingNoticeRequest;
        if (startupHello) {
            item[@"startupHello"] = @YES;
            if (startupVideoView) {
                item[@"startupVideoView"] = startupVideoView;
                NSTimeInterval duration = startupVideoView.mediaDuration;
                item[@"timeoutDuration"] = @(duration > 0 ? MIN(duration + 2.0, 120.0) : 60.0);
            } else {
                item[@"timeoutDuration"] = @(kOITIStartupHelloPrototypeDuration);
            }
        }
        if (downloadProgress) {
            item[@"download"] = @YES;
            item[@"downloadBar"] = downloadBar;
            if (downloadDetail) item[@"downloadDetail"] = downloadDetail;
            item[@"timeoutDuration"] = @(365.0 * 24.0 * 3600.0);   // the download decides when this ends, not the notice timer
            sDownloadItem = item;
            sDownloadShownAt = CFAbsoluteTimeGetCurrent();
        }
        OITISetNoticeLayout(item, style, YES);
        NSUInteger stackLimit = sIslandNotificationStackEnabled ? kOITINoticeStackLimit : 1;
        while (sIslandNoticeItems.count >= stackLimit) {
            NSDictionary *oldest = sIslandNoticeItems.firstObject;
            [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK full (%lu); evicting oldest %@",
             (unsigned long)kOITINoticeStackLimit, OITIKVCObject(oldest[@"element"], @"elementIdentifier")];
            OITIRemoveNoticeItem(oldest, @"capacity");
        }
        [sIslandNoticeItems addObject:item];   // added BEFORE registering so the promotion guard knows an OITI element is live
        if (sIslandNoticeItems.count == 1) OITIWriteElementBreadcrumb(reason);   // also before registering: registration is the risky call
        if (startupHello) sStartupHelloItem = item;
        OITIScheduleNoticeTimeout(item);
        OITIRefreshNewestNoticeComposite();

        sPoCOurRegistrationInFlight = YES;
        id registration = [(SAUISystemApertureManager *)registrar registerElement:element];
        sPoCOurRegistrationInFlight = NO;
        if (registration) item[@"registration"] = registration;
        OITIProbeObject(registration, @"registration");
        [sLog logTag:@"ELEMENT" format:@"registered %@ (%@) registrar=%@ registration=%@ duration=%.1fs", identifier, reason,
         OITIObjectSummary(registrar), OITIObjectSummary(registration), (double)sIslandNoticeDuration];

        if (startupVideoView) {
            __weak NSMutableDictionary *weakItem = item;
            NSMutableArray *observers = [NSMutableArray array];
            for (NSString *notificationName in @[AVPlayerItemDidPlayToEndTimeNotification,
                                                  AVPlayerItemFailedToPlayToEndTimeNotification]) {
                id observer = [[NSNotificationCenter defaultCenter]
                    addObserverForName:notificationName
                    object:startupVideoView.player.currentItem
                    queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *notification) {
                        NSMutableDictionary *strongItem = weakItem;
                        if (!strongItem || ![sIslandNoticeItems containsObject:strongItem]) return;
                        BOOL failed = [notification.name isEqualToString:AVPlayerItemFailedToPlayToEndTimeNotification];
                        [sLog logLevel:1 tag:@"HELLO" format:@"video %@; removing startup element %@",
                         failed ? @"playback failed" : @"reached end", failed ? notification.userInfo : @""];
                        OITIRemoveNoticeItem(strongItem, failed ? @"video-failed" : @"video-finished");
                    }];
                if (observer) [observers addObject:observer];
            }
            item[@"playbackObservers"] = observers;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (![sIslandNoticeItems containsObject:item]) return;
                [startupVideoView startPlayback];
                [sLog logLevel:1 tag:@"HELLO" format:@"video playback started"];
            });
        }

        if ([sLog isLoggingAtLevel:1]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (![sIslandNoticeItems containsObject:item]) return;
                [sLog logTag:@"ELEMENT" format:@"VIEWS element: %@", OITIElementValuesSummary(element)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS parts:   %@", OITIElementPartsSummary(element)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS leading:   %@", OITIViewDiag(leadingView)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS trailing:  %@", OITIViewDiag(trailingView)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS primary:   %@", OITIViewDiag(primaryView)];
                [sLog logTag:@"ELEMENT" format:@"VIEWS secondary: %@", OITIViewDiag(secondaryView)];
                [sLog logTag:@"ELEMENT" format:@"CORNERS leading chain: %@", OITICornerChain(leadingView)];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                OITIRunDump(@"poc-element");
            });
        }
        NSString *noticeBundleID = info[@"bundleID"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (![sIslandNoticeItems containsObject:item]) return;
            UIView *host = nil;
            for (UIView *up = leadingView.superview; up; up = up.superview) {
                if ([NSStringFromClass([up class]) isEqualToString:@"SAUIElementView"]) { host = up; break; }
            }
            if (!host) host = leadingView.superview;
            if (!host) {
                [sLog logTag:@"ELEMENT" format:@"GESTURES: no host view found, tap and swipe unavailable"];
                return;
            }
            OITINoticeActions *actions = [OITINoticeActions new];
            actions.bundleID = noticeBundleID;
            actions.request = item[@"request"];
            actions.host = host;
            actions.dismiss = ^{
                OITIRemoveNoticeItem(item, @"swipe");
            };
            // Recognizers on the element view and on the Island window (the window ones only take touches that start inside the
            // element): some touches may be taken before they reach the element view, and the TOUCH lines show which route works.
            NSMutableArray<UIGestureRecognizer *> *recognizers = [NSMutableArray array];
            NSArray<UIView *> *targets = host.window ? @[host, host.window] : @[host];
            for (UIView *target in targets) {
                OITINoticeTapRecognizer *tap = [[OITINoticeTapRecognizer alloc] initWithTarget:actions action:@selector(handleTap:)];
                tap.label = [target isKindOfClass:[UIWindow class]] ? @"window" : @"element";
                tap.cancelsTouchesInView = NO;
                tap.delegate = actions;
                UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:actions action:@selector(handleSwipe:)];
                swipe.direction = UISwipeGestureRecognizerDirectionUp;
                swipe.cancelsTouchesInView = NO;
                swipe.delegate = actions;
                [target addGestureRecognizer:tap];
                [target addGestureRecognizer:swipe];
                [recognizers addObject:tap];
                [recognizers addObject:swipe];
            }
            item[@"actions"] = actions; item[@"recognizers"] = recognizers;
            [sLog logLevel:1 tag:@"ELEMENT" format:@"GESTURES attached to %@ and %@ (frame %@, interaction %d)", NSStringFromClass([host class]),
             host.window ? NSStringFromClass([host.window class]) : @"no window", NSStringFromCGRect(host.frame), host.userInteractionEnabled];
        });

        CGFloat cornerExtra = [sOITIPreferences floatForKey:@"IslandNotificationsCornerExtra" default:0];
        if (isfinite(cornerExtra) && cornerExtra != 0) {
            cornerExtra = MAX(-20.0, MIN(20.0, cornerExtra));
            for (NSNumber *delay in @[@0.7, @1.3]) {   // after Apple's expansion animation, and once more in case it re-lays out
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (![sIslandNoticeItems containsObject:item]) return;
                    OITIApplyCornerExtra(leadingView, cornerExtra);
                    [sLog logLevel:1 tag:@"ELEMENT" format:@"CORNERS applied %+.1f: %@", (double)cornerExtra, OITICornerChain(leadingView)];
                });
            }
        }
        return YES;
    } @catch (NSException *exception) {
        sPoCOurRegistrationInFlight = NO;
        [sLog logTag:@"ELEMENT" format:@"exception while creating/registering the element: %@ %@", exception.name, exception.reason];
        if ([sIslandNoticeItems containsObject:item]) OITIRemoveNoticeItem(item, @"registration-error");
        else if (sIslandNoticeItems.count && style != 0) OITISetNoticeLayout(sIslandNoticeItems.lastObject, style, YES);
        return NO;
    }
}

// The developer trigger (touch /tmp/OITIPoC.trigger). Independent of the islandNotificationsEnabled setting because
// it never reacts to a notification: it is a manual test of the element mechanism.
void OITIRunPoCElement(NSString *reason) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *info = @{ @"bundleID": @"com.apple.Preferences", @"appName": @"Insula",
                                @"title": @"Island Notification", @"subtitle": @"",
                                @"message": @"Hello from Insula" };
        // /tmp/OITIPoCSample.txt (optional): title, message, bundle id, subtitle, one per line, to try long text or no title.
        NSString *sample = [NSString stringWithContentsOfFile:@"/tmp/OITIPoCSample.txt" encoding:NSUTF8StringEncoding error:nil];
        if (sample.length) {
            NSArray<NSString *> *rows = [sample componentsSeparatedByString:@"\n"];
            NSString *(^row)(NSUInteger) = ^NSString *(NSUInteger i) { return i < rows.count ? rows[i] : @""; };
            NSString *sampleBundle = row(2).length ? row(2) : @"com.apple.MobileSMS";
            info = @{ @"bundleID": sampleBundle, @"appName": @"", @"title": row(0), @"subtitle": row(3), @"message": row(1) };
        }
        OITIPresentNoticeElement(info, reason);
    });
}

// ---- Haptic ----------------------------------------------------------------------------------
// One short light tap per banner request. Respects the system's own haptics setting (UIKit decides).
static void OITIPlayNotificationHaptic(void) {
    static CFAbsoluteTime lastHaptic = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - lastHaptic < 0.4) return;   // one banner can be posted more than once
    lastHaptic = now;
    dispatch_async(dispatch_get_main_queue(), ^{
        static UIImpactFeedbackGenerator *generator;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (!generator) generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
#pragma clang diagnostic pop
        [generator prepare];
        [generator impactOccurredWithIntensity:0.8];
        [sLog logLevel:1 tag:@"NOTIF" format:@"haptic played"];
    });
}

// A banner request arrived. Always safe: log-only unless the feature is on.
void OITIHandleBannerRequest(id destination, id request) {
    if ([sOITIPreferences boolForKey:@"NotificationHaptic" default:NO]) OITIPlayNotificationHaptic();
    if (sStartupHelloObservationWindowOpen && islandStartupHelloEnabled) sStartupHelloActivitySeen = YES;
    if (sStartupHelloItem) {
        dispatch_async(dispatch_get_main_queue(), ^{
            OITICancelStartupHello(@"notification");
        });
    }
    if (!islandNotificationsEnabled && !(sLog.enabled && sLog.level >= 1)) return;
    NSDictionary<NSString *, NSString *> *info = OITINoticeInfoFromRequest(request);
    [sLog logLevel:1 tag:@"NOTIF" format:@"banner request %@ bundle=%@ app=%@ title=%@ message=%@ (feature %@)",
     OITIObjectSummary(request), info[@"bundleID"], OITIShortText(info[@"appName"], 30), OITIShortText(info[@"title"], 40),
     OITIShortText(info[@"message"], 60), islandNotificationsEnabled ? @"on" : @"off"];
    if (!islandNotificationsEnabled) return;

    __weak id weakDestination = destination;
    id requestRef = request;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!islandNotificationsEnabled) return;   // the setting may have been turned off before this queued block ran
        sPendingNoticeRequest = requestRef;
        BOOL shown = OITIPresentNoticeElement(info, @"notification");
        sPendingNoticeRequest = nil;
        // Only fade the stock banner when our element really went up, so a failure never swallows a notification.
        if (shown && islandNotificationsHideBanner) OITIBeginBannerHide(weakDestination);
    });
}

// ---- Banner hook, installed at run time ----------------------------------------------------
// The selector that posts a banner differs between iOS versions (the one seen in a 2023 trace is not on 16.7.16), so the
// hook is found by name pattern in the class chain and installed with the runtime, only if the type encoding has one of
// the two shapes this build can forward exactly (void return, one or two object arguments). The replacement always calls
// Apple's original first. Nothing matching = nothing installed, and the candidates are logged for the next build.

NSString *OITIFirstBannerMethodName(Class cls, const char **encodingOut, int *argsOut) {
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(c, &count);
        NSString *found = nil;
        for (unsigned int i = 0; i < count && !found; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            const char *encoding = method_getTypeEncoding(methods[i]);
            if (!encoding || ![name hasPrefix:@"postNotificationRequest"]) continue;
            if (strcmp(encoding, "v32@0:8@16@24") == 0) { found = name; *argsOut = 2; *encodingOut = encoding; }
            else if (strcmp(encoding, "v24@0:8@16") == 0) { found = name; *argsOut = 1; *encodingOut = encoding; }
        }
        free(methods);
        if (found) return found;
    }
    return nil;
}

// Logs every method in the class chain that looks related to posting or presenting a banner (selector and encoding).
void OITILogBannerCandidates(Class cls) {
    NSArray<NSString *> *keywords = @[@"post", @"present", @"request", @"banner", @"notification", @"modify", @"add"];
    NSUInteger lines = 0;
    for (Class c = cls; c && c != [NSObject class] && lines < 160; c = class_getSuperclass(c)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(c, &count);
        [sLog logTag:@"NOTIF" format:@"CANDIDATES %@: %u method(s)", NSStringFromClass(c), count];
        for (unsigned int i = 0; i < count && lines < 160; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            BOOL related = NO;
            for (NSString *keyword in keywords) {
                if ([name rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) { related = YES; break; }
            }
            if (!related) continue;
            [sLog logTag:@"NOTIF" format:@"  %@ [%s]", name, method_getTypeEncoding(methods[i]) ?: "?"];
            lines++;
        }
        free(methods);
    }
}
