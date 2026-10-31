// OITIDownloadProgress.h -- what other files use of the download progress module (v0.3.0 module split, round 2).
//
// The module is OITIDownloadViews.xm (bar and views), OITIDownloadTracker.xm (tracker, Minimal pill, test download) and
// OITIAppStoreSource.xm (App Store source). The class declarations below moved here unchanged from the files that
// implement them, because the notification presenter in Tweak.xm and the pill use them too.

#import "Shared/OITIShared.h"

// The settings (defined in OITIDownloadTracker.xm, written by the preferences reload in Tweak.xm).
extern BOOL sDownloadProgressEnabled;
extern BOOL sDownloadAppStoreEnabled;
extern BOOL sDownloadTestFractionOnly;
extern CGFloat sDownloadIdleAfterMB;
extern CGFloat sDownloadIdleAfterSeconds;
extern CGFloat sDownloadTestSizeMB;
extern NSInteger sDownloadStyle;
extern CGFloat sDownloadPillWidth;
extern CGFloat sDownloadPillBottomPadding;
extern CGFloat sDownloadPillNudgeY;

// Views.
@interface OITIProgressBarView : UIView
@property (nonatomic, readonly) double fraction;
@property (nonatomic, assign) CGFloat barHeight;   // default 6
- (void)setFraction:(double)fraction animated:(BOOL)animated;
- (void)setComplete:(BOOL)complete;
- (void)setCancelled:(BOOL)cancelled;   // red fill; call after setComplete:, which resets the colour
@end

static const CGFloat kOITIMinimalHeight = 56.0;          // height it asks for

@interface OITIMinimalDownloadView : UIView
@property (nonatomic, readonly) OITIProgressBarView *bar;
- (void)setHeader:(NSString *)header downloaded:(NSString *)downloaded total:(NSString *)total speed:(NSString *)speed
          percent:(NSString *)percent fraction:(double)fraction complete:(BOOL)complete;
- (void)playCompletion;    // the text fades out, the bar becomes a green circle and a check is drawn in it
- (void)resetCompletion;   // back to the normal layout (a new download started)
@end

@interface OITIDownloadPill : NSObject
@property (nonatomic, readonly) OITIMinimalDownloadView *content;
@property (nonatomic, readonly) UIWindowLevel level;
- (void)present;
- (void)relayout;
- (void)refreshOrientation;
- (void)dismiss;
@end

extern OITIDownloadPill *sDownloadPill;   // the Minimal look, while it is on screen

// OITIDownloadViews.xm
OITINoticeStackView *OITIBuildDownloadStack(OITIProgressBarView **barOut, UILabel **detailOut);

// OITIDownloadTracker.xm
void OITIDownloadsRefresh(void);
void OITIDownloadPillDismiss(NSString *reason);
void OITIDownloadItemRemoved(NSDictionary *item, NSString *reason);
void OITIDownloadUpdateFraction(NSString *identifier, NSString *appName, NSString *title, NSString *bundleID, double fraction, BOOL paused);
void OITIDownloadFinish(NSString *identifier, BOOL completed);
void OITIDownloadDrop(NSString *identifier);
void OITIFakeDownloadStart(void);
void OITIFakeDownloadStop(void);

// OITIAppStoreSource.xm
void OITIAppStoreSourceRefresh(void);
