// OITIIslandNotifications.h -- what the Island notification files share (v0.3.0 module split, round 4).
//
// The module is OITINoticePresenter.xm, OITINoticeSupport.xm, OITINoticeElement.xm, OITINoticeViews.xm, OITIBannerHide.xm,
// OITINoticeActions.xm and OITINotificationHooks.xm. Everything below is declared here because more than one of them (or
// Tweak.xm) uses it; every other helper is static in its own file. The declarations are copies of the definitions.

#import "Shared/OITIShared.h"

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
- (void)handleTap:(UIGestureRecognizer *)recognizer;
- (void)handleSwipe:(UIGestureRecognizer *)recognizer;
@end

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
id OITISafeObject(id object, NSString *selectorName);
NSString *OITISafeString(id object, NSString *selectorName);
id OITIKVCObject(id object, NSString *key);
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
void OITIRefreshNewestNoticeComposite(void);
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
