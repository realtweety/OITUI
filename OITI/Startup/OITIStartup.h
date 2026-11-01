// OITIStartup.h -- what other OITI files use of the Startup module (v0.3.0 module split, round 5).
//
// The module is OITIStartupHello.xm. Everything below is declared here because the Island notification files (the presenter
// and the hooks) or Tweak.xm use it; every other helper is static in OITIStartupHello.xm. The declarations are copies of the
// definitions. The setting islandStartupHelloEnabled is defined in Shared/OITIState.xm (the preferences reload writes it).

#import "Shared/OITIShared.h"

@interface OITIStartupVideoView : UIView
@property (nonatomic, strong, readonly) AVPlayer *player;
- (instancetype)initWithURL:(NSURL *)url;
- (NSTimeInterval)mediaDuration;
- (void)startPlayback;
- (void)stopPlayback;
@end

extern const NSTimeInterval kOITIStartupHelloPrototypeDuration;
extern BOOL islandStartupHelloEnabled;   // defined in Shared/OITIState.xm
extern BOOL sStartupHelloObservationWindowOpen;
extern BOOL sStartupHelloActivitySeen;
extern NSMutableDictionary *sStartupHelloItem;
void OITICancelStartupHello(NSString *reason);
OITIStartupVideoView *OITIBuildStartupVideoView(void);
void OITIRunStartupHello(void);
