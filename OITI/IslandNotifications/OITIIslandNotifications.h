// OITIIslandNotifications.h -- what the Island notification files share (v0.3.0 module split, round 4).
//
// The module is OITINoticePresenter.xm, OITINoticeSupport.xm, OITINoticeElement.xm, OITINoticeViews.xm, OITIBannerHide.xm,
// OITINoticeActions.xm and OITINotificationHooks.xm. Everything below is declared here because more than one of them (or
// another module) uses it; every other helper is static in its own file. The declarations are copies of the definitions.

#import "Shared/OITIShared.h"
#import "Startup/OITIStartup.h"   // the presenter and the hooks call the Hello startup code (round 5)

// Apple's element code calls -elementIdentifier on the "identifier" argument (a plain NSString crashed with
// "-[__NSCFString elementIdentifier]: unrecognized selector"), so the identifier must be an object. This stub answers
// elementIdentifier with our string and logs every other selector Apple sends it (once each), answering with the string
// for anything identifier-like and nil otherwise. The ELEMENT STUB lines show what Apple really wants from it.
@interface OITIElementIdentifierStub : NSObject <NSCopying>
@property (nonatomic, copy) NSString *value;
@end

// A tap recognizer that logs where touches land (TOUCH lines), so a tap that never reaches us is visible in the log.
@interface OITINoticeTapRecognizer : UITapGestureRecognizer
@property (nonatomic, copy) NSString *label;
@end

@interface OITINoticeActions : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) id request;
@property (nonatomic, weak) UIView *host;
@property (nonatomic, assign) BOOL handled;
@property (nonatomic, copy) void (^dismiss)(void);
@property (nonatomic, copy) void (^tapAction)(void);    // when set, a tap runs this instead of the notification tap path (the Hello opens Insula's settings)
@property (nonatomic, copy) void (^tapDismiss)(void);   // set for a notification notice only (nil for the Hello and a download); used when sIslandNotificationTapDismisses is on
- (void)handleTap:(UIGestureRecognizer *)recognizer;
- (void)handleSwipe:(UIGestureRecognizer *)recognizer;
@end

// OITINoticeStackCards.xm
void OITIStackCardsRefresh(void);   // rebuild or remove the cards of the older notices (the stack below the newest notice)

// OITINoticeActions.xm
void OITIOpenInsulaSettings(void);   // the Hello's tap: Insula's page in Settings (prefs:root=Insula)

// OITINoticePresenter.xm
static const double kOITIDownloadAlertDuration = 86400.0;

// OITINoticePresenter.xm
extern __weak id sRegisteringManager;
extern __weak id sSeenManager;
extern __weak id sSystemApertureController;
extern NSDictionary<NSString *, NSNumber *> *sRealLayoutValues;
extern BOOL sPoCOurRegistrationInFlight;
extern BOOL sPoCDisabledAfterFailure;
extern int sPoCFailureCount;

// OITIBannerHide.xm
extern BOOL sBannerHideActive;

// OITINoticeSupport.xm
extern NSMutableSet<NSString *> *sTraceSeen;

// OITINoticeSupport.xm
NSString *OITIElementPartsSummary(id element);
NSString *OITIElementIdentifierList(id elements);
NSString *OITIElementValuesSummary(id element);
void OITICaptureRealElement(id element);

// OITINoticeElement.xm
BOOL OITIIsOurElement(id element);
BOOL OITIIsChargingSystemElement(id element);
NSInteger OITINoticeStyle(void);
void OITISetNoticeLayout(NSDictionary *item, NSInteger style, BOOL isNewest);

// OITINoticeSupport.xm
void OITIWriteElementBreadcrumb(NSString *reason);
void OITIClearElementBreadcrumb(void);
void OITIEvaluateElementBreadcrumb(void);
BOOL OITIElementRecoveryActive(NSString *reason);

// OITINoticeElement.xm
BOOL OITIIsBaselineLockElement(id element);

// OITINoticeSupport.xm
void OITITraceOnce(NSString *message);

// OITINoticeElement.xm
Class OITINoticeElementClass(void);

// OITINoticeViews.xm
NSString *OITIShortText(NSString *text, NSUInteger limit);
NSDictionary<NSString *, NSString *> *OITINoticeInfoFromRequest(id request);
void OITIBuildNoticeViews(NSDictionary<NSString *, NSString *> *info, UIView **leadingOut, UIView **trailingOut, UIView **primaryOut, UIView **secondaryOut, UILabel **secondaryBodyOut);
NSString *OITICornerChain(UIView *view);
void OITIApplyCornerExtra(UIView *view, CGFloat extra);
void OITIRestoreCorners(void);
NSString *OITIViewDiag(UIView *view);

// OITIBannerHide.xm
NSArray<UIWindow *> *OITIBannerWindowsNow(void);
void OITIRestoreBannerWindows(void);
void OITIBeginBannerHide(id destination);

// OITINoticeActions.xm
void OITIProbeObject(id object, NSString *role);

// OITINoticePresenter.xm
void OITIDismissNoticeItem(NSDictionary *item);
void OITIHandleBannerRequest(id destination, id request);
NSString *OITIFirstBannerMethodName(Class cls, const char **encodingOut, int *argsOut);
void OITILogBannerCandidates(Class cls);

// OITINotificationHooks.xm
void OITIInstallIslandNotificationHooks(void);

// OITINotificationHooks.xm
void OITIInstallResearchHooks(void);
void OITIInstallDiagnosticHooks(void);
