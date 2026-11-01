// OITIApplePrivate.h -- declarations of Apple's private classes that OITI talks to (v0.3.0 module split, round 1).
//
// Moved from the top of Tweak.xm unchanged. These only tell the compiler which selectors exist; every real use goes
// through NSClassFromString or a Logos hook, because a direct class reference would not link.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface SBSystemApertureWindow : UIView
@end

@interface SBSystemApertureProvidedContentElement : NSObject
- (instancetype)initWithIdentifier:(id)identifier contentProvider:(id)contentProvider;
@end

@interface SAUISystemApertureManager : NSObject
- (id)registerElement:(id)element;
@end

// Private classes used by Island Notifications. They are declared only so the compiler knows the
// selectors; every use goes through NSClassFromString at run time (a direct class reference would not link).
@interface SBUISystemApertureCustomContentProvider : NSObject
- (instancetype)initWithView:(UIView *)view;
@end

@interface SBUISystemApertureContentProvider : NSObject
- (void)setLeadingContentViewProvider:(id)provider;
- (void)setTrailingContentViewProvider:(id)provider;
- (void)setMinimalContentViewProvider:(id)provider;
- (void)setPrimaryContentViewProvider:(id)provider;
- (void)setSecondaryContentViewProvider:(id)provider;
@end

@interface SBSystemApertureController : NSObject
- (id)registerElement:(id)element;
@end

@interface SBSystemApertureElementAuthority : NSObject
@end

@interface SBNotificationBannerDestination : NSObject
- (id)presentedBanner;
@end

@interface UIImage (OITIPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface UIWindow (OITIPrivate)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)includeInternal onlyVisibleWindows:(BOOL)onlyVisible;
@end

@interface _SBSystemApertureMagiciansCurtainView : UIView
@end

@interface SBBannerWindow : UIView
@end

@interface _SBGainMapView : UIView
@end

@interface _SBSystemApertureContainerViewContentView : UIView
@end

@interface SBFTouchPassThroughView : UIView
@end

// Apple's layout-metrics object for the Island (SpringBoardUIServices). Its getters are computed, with no stored
// state, which is what makes overriding them possible.
@interface SBUISystemApertureLayoutMetrics : NSObject
+ (instancetype)sharedInstanceForEmbeddedDisplay;
@end
