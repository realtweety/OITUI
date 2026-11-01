// OITIStartupHello.xm -- the Hello startup animation (OITI Settings > Startup Animation).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 5, Startup): the muted single-play video view, the
// cooldown and readiness checks (unlocked, SpringBoard on the Home Screen, no other Island activity) and the runner that
// asks the notification presenter for the startup element. The setting itself (islandStartupHelloEnabled) is still defined
// in Tweak.xm; the presenter and the hooks in IslandNotifications/ reach this file through Startup/OITIStartup.h.
// OITIRunStartupHello lost its `static` so the %ctor in Tweak.xm can call it.

#import "Shared/OITIShared.h"
#import "Startup/OITIStartup.h"
#import "IslandNotifications/OITIIslandNotifications.h"

static NSString * const kOITIStartupHelloLastPlayedKey = @"IslandStartupHelloLastPlayedAt";
static NSString * const kOITIStartupHelloVideoPath = @"/var/jb/Library/Application Support/OITI/StartupHello.mp4";
static const NSTimeInterval kOITIStartupHelloCooldown = 300.0;
const NSTimeInterval kOITIStartupHelloPrototypeDuration = 8.0;

BOOL sStartupHelloObservationWindowOpen;
BOOL sStartupHelloActivitySeen;
static BOOL sStartupHelloReadinessLogged;
static int sStartupHelloPolls;   // once-a-second readiness checks so far; the check gives up after 180 (3 minutes)

NSMutableDictionary *sStartupHelloItem;


void OITICancelStartupHello(NSString *reason) {
    NSDictionary *item = sStartupHelloItem;
    if (!item) return;
    [sLog logLevel:1 tag:@"HELLO" format:@"yielding startup card to Island activity (%@)", reason];
    OITIRemoveNoticeItem(item, reason ?: @"interrupted");
}


@implementation OITIStartupVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }

- (instancetype)initWithURL:(NSURL *)url {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    _player = [AVPlayer playerWithPlayerItem:item];
    _player.muted = YES;
    AVPlayerLayer *playerLayer = (AVPlayerLayer *)self.layer;
    playerLayer.player = _player;
    // Keep the familiar 16:9 Island content frame; the video is pre-cropped with safe margins
    // so aspect-fill enlarges the word without cutting off either end.
    playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.backgroundColor = UIColor.blackColor;
    self.layer.cornerRadius = 24.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.isAccessibilityElement = NO;
    return self;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(260.0, 146.0); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(260.0, 146.0); }
- (NSTimeInterval)mediaDuration {
    NSTimeInterval duration = CMTimeGetSeconds(self.player.currentItem.duration);
    return isfinite(duration) && duration > 0 ? duration : 0;
}
- (void)startPlayback { [self.player seekToTime:kCMTimeZero]; [self.player play]; }
- (void)stopPlayback {
    [self.player pause];
    [self.player replaceCurrentItemWithPlayerItem:nil];
}
@end

OITIStartupVideoView *OITIBuildStartupVideoView(void) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:kOITIStartupHelloVideoPath]) {
        [sLog logLevel:1 tag:@"HELLO" format:@"video asset missing at %@; retaining the placeholder card", kOITIStartupHelloVideoPath];
        return nil;
    }
    NSURL *url = [NSURL fileURLWithPath:kOITIStartupHelloVideoPath];
    OITIStartupVideoView *view = [[OITIStartupVideoView alloc] initWithURL:url];
    if (view) [sLog logLevel:1 tag:@"HELLO" format:@"created muted, single-play video view duration=%.2fs", (double)view.mediaDuration];
    return view;
}


static BOOL OITIStartupHelloIsAtUnlockedHomeScreen(BOOL *stateAvailable) {
    if (stateAvailable) *stateAvailable = NO;
    Class lockClass = NSClassFromString(@"SBLockScreenManager");
    id lockManager = OITISafeObject(lockClass, @"sharedInstance");
    BOOL lockStateAvailable = NO;
    BOOL locked = OITISafeBool(lockManager, @"isUILocked", &lockStateAvailable);

    Class workspaceClass = NSClassFromString(@"SBMainWorkspace");
    id workspace = OITISafeObject(workspaceClass, @"sharedInstance");
    BOOL homeStateAvailable = NO;
    BOOL springBoardFrontmost = OITISafeBool(workspace, @"isSpringBoardActive", &homeStateAvailable);

    BOOL unlocked = lockStateAvailable && !locked && UIApplication.sharedApplication.protectedDataAvailable;
    BOOL atHome = homeStateAvailable && springBoardFrontmost;
    if (stateAvailable) *stateAvailable = lockStateAvailable && homeStateAvailable;
    return unlocked && atHome;
}

static BOOL OITIStartupHelloHasActiveSystemElement(void) {
    id manager = sRegisteringManager ?: sSeenManager;
    id elements = OITISafeObject(manager, @"registeredElements");
    if (![elements conformsToProtocol:@protocol(NSFastEnumeration)]) return NO;
    for (id element in elements) {
        if (!OITIIsOurElement(element) && !OITIIsBaselineLockElement(element) &&
            !OITIIsChargingSystemElement(element)) return YES;
    }
    return NO;
}

void OITIRunStartupHello(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!islandStartupHelloEnabled) { sStartupHelloObservationWindowOpen = NO; return; }
        if (!islandEnabled) {
            sStartupHelloObservationWindowOpen = NO;
            [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype skipped because the Dynamic Island is disabled"];
            return;
        }
        BOOL stateAvailable = NO;
        if (!OITIStartupHelloIsAtUnlockedHomeScreen(&stateAvailable)) {
            sStartupHelloObservationWindowOpen = NO;
            if (!stateAvailable) {
                if (!sStartupHelloReadinessLogged) {
                    [sLog logLevel:1 tag:@"HELLO" format:@"waiting for unlock/Home Screen state (SpringBoard state selectors unavailable or not ready)"];
                    sStartupHelloReadinessLogged = YES;
                }
            } else if (sStartupHelloReadinessLogged) {
                [sLog logLevel:1 tag:@"HELLO" format:@"waiting until unlocked on the Home Screen"];
                sStartupHelloReadinessLogged = NO;
            }
            if (++sStartupHelloPolls > 180) {
                [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype gave up waiting for an unlocked Home Screen after %d checks", sStartupHelloPolls - 1];
                return;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ OITIRunStartupHello(); });
            return;
        }
        sStartupHelloReadinessLogged = NO;
        sStartupHelloObservationWindowOpen = YES;
        if (sStartupHelloActivitySeen || OITIStartupHelloHasActiveSystemElement()) {
            sStartupHelloObservationWindowOpen = NO;
            [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype skipped because Island activity is already present"];
            return;
        }
        if (sStartupHelloItem || sIslandNoticeItems.count) {
            sStartupHelloObservationWindowOpen = NO;
            [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype skipped because an OITI Island item is already active"];
            return;
        }
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        NSTimeInterval last = [sOITIPreferences floatForKey:kOITIStartupHelloLastPlayedKey default:0];
        if (last > 0 && now >= last && now - last < kOITIStartupHelloCooldown) {
            sStartupHelloObservationWindowOpen = NO;
            [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype suppressed by five-minute cooldown (%.0f seconds remain)",
             kOITIStartupHelloCooldown - (now - last)];
            return;
        }
        // Persist only after the Island element was registered, so a failed presentation does not consume the cooldown.
        NSDictionary *info = @{ @"bundleID": @"com.apple.Preferences", @"appName": @"Insula",
                                @"title": @"Hello", @"subtitle": @"", @"message": @"Startup animation prototype" };
        BOOL shown = OITIPresentNoticeElement(info, @"startup-hello");
        sStartupHelloObservationWindowOpen = NO;
        if (shown) {
            [sOITIPreferences setObject:@(now) forKey:kOITIStartupHelloLastPlayedKey];
            [sOITIPreferences synchronize];
        }
        [sLog logLevel:1 tag:@"HELLO" format:@"startup prototype %@", shown ? @"presented" : @"could not be presented"];
    });
}
