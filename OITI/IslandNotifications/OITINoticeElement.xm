// OITINoticeElement.xm -- recognising and laying out the elements OITI creates (OITI Island notifications).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 4, IslandNotifications).
// Which Island element is ours, which is the newest notice or an alert, the style, the layout of an element, and the element class.

#import "Shared/OITIShared.h"
#import "IslandNotifications/OITIIslandNotifications.h"

BOOL OITIIsOurElement(id element) {
    if (!element || !sIslandNoticeItems.count) return NO;
    for (NSDictionary *item in sIslandNoticeItems) {
        if (item[@"element"] == element) return YES;
    }
    return NO;
}

// The item (notice, Hello or download) an element belongs to, or nil.
static NSDictionary *OITIItemForElement(id element) {
    if (!element) return nil;
    for (NSDictionary *item in sIslandNoticeItems) {
        if (item[@"element"] == element) return item;
    }
    return nil;
}

// The charging activity is an ordinary system aperture element. Let Hello play ahead of it,
// then allow SpringBoard to promote charging after Hello is removed. Other system activities
// (especially calls) keep the normal immediate-yield behavior.
BOOL OITIIsChargingSystemElement(id element) {
    id identifier = OITIKVCObject(element, @"elementIdentifier");
    return [identifier isKindOfClass:[NSString class]] &&
           [identifier isEqualToString:@"SBChargingSystemApertureElementProvider"];
}

// SpringBoard only promotes one alert at a time. Keep the newest notice in the alert lane and let
// older notices participate as compact activities so the aperture can present them alongside it.
static BOOL OITIIsNewestNoticeElement(id element) {
    return element && sIslandNoticeItems.count && sIslandNoticeItems.lastObject[@"element"] == element;
}

static BOOL OITIIsAlertNoticeElement(id element) {
    if (OITIItemForElement(element)[@"download"]) return OITIIsNewestNoticeElement(element);   // wide or expanded, whatever the notification style is
    return OITINoticeStyle() != 0 && OITIIsNewestNoticeElement(element);
}

NSInteger OITINoticeStyle(void) {
    NSInteger style = (NSInteger)lround([sOITIPreferences floatForKey:@"IslandNotificationsStyle" default:2]);
    return MAX(0, MIN(2, style));   // 0 compact, 1 wide, 2 expanded
}

void OITISetNoticeLayout(NSDictionary *item, NSInteger style, BOOL isNewest) {
    id element = item[@"element"];
    if (!element) return;
    if (item[@"download"]) style = 2;   // the Detailed download look is the expanded layout, whatever the notification style is

    BOOL compact = (style == 0) || !isNewest;
    NSInteger layoutVariant = compact ? 1 : (style == 1 ? 6 : 5);
    NSInteger devVariant = (NSInteger)lround([sOITIPreferences floatForKey:@"IslandNotificationsDevLayout" default:-1]);
    if (isNewest && devVariant >= 0) layoutVariant = devVariant;
    NSInteger minimum = 1, preferred = 1, maximum = 1;
    if (layoutVariant == 2 && sRealLayoutValues) {
        minimum = sRealLayoutValues[@"minimum"].integerValue;
        preferred = sRealLayoutValues[@"preferred"].integerValue;
        maximum = sRealLayoutValues[@"maximum"].integerValue;
    } else if (layoutVariant == 3) {
        preferred = 2; maximum = 3;
    } else if (layoutVariant == 4) {
        minimum = -1; preferred = 2; maximum = 2;
    } else if (layoutVariant == 5) {
        preferred = 3; maximum = 3;
    } else if (layoutVariant == 6) {
        preferred = 2; maximum = 2;
    }
    SEL setPreferred = NSSelectorFromString(@"setPreferredLayoutMode:");
    SEL setMinimum = NSSelectorFromString(@"setMinimumSupportedLayoutMode:");
    SEL setMaximum = NSSelectorFromString(@"setMaximumSupportedLayoutMode:");
    @try {
        if ([element respondsToSelector:setMinimum]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(element, setMinimum, minimum);
        if ([element respondsToSelector:setMaximum]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(element, setMaximum, maximum);
        if ([element respondsToSelector:setPreferred]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(element, setPreferred, preferred);
        BOOL alert = (style != 0 && isNewest);
        [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK layout %@ mode=%ld/%ld/%ld newest=%d alert=%d activity=%d style=%ld",
         OITIKVCObject(element, @"elementIdentifier"), (long)minimum, (long)preferred, (long)maximum,
         isNewest, alert, !alert, (long)style];
    } @catch (NSException *exception) {
        [sLog logTag:@"ELEMENT" format:@"STACK layout update failed for %@: %@ %@",
         OITIKVCObject(element, @"elementIdentifier"), exception.name, exception.reason];
    }
}

BOOL OITIIsBaselineLockElement(id element) {
    NSString *identifier = [OITIKVCObject(element, @"elementIdentifier") description];
    NSString *className = NSStringFromClass([element class]);
    return [identifier rangeOfString:@"lock" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [className rangeOfString:@"LockElement" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// ---- OITI's element class ---------------------------------------------------------------------
// A runtime subclass of Apple's SBSystemApertureProvidedContentElement. The newest item is an alert;
// older items become activities so SpringBoard can keep them in compact mode alongside the alert.
Class OITINoticeElementClass(void) {
    static Class elementClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = NSClassFromString(@"SBSystemApertureProvidedContentElement");
        if (!base) return;
        elementClass = objc_getClass("OITINotificationElement");
        if (elementClass) return;
        Class created = objc_allocateClassPair(base, "OITINotificationElement", 0);
        if (!created) return;
        class_addMethod(created, NSSelectorFromString(@"hasAlertBehavior"),
                        imp_implementationWithBlock(^BOOL(id receiver) { return OITIIsAlertNoticeElement(receiver); }), "B16@0:8");
        class_addMethod(created, NSSelectorFromString(@"hasActivityBehavior"),
                        imp_implementationWithBlock(^BOOL(id receiver) {
                            return OITIIsOurElement(receiver) && !OITIIsAlertNoticeElement(receiver);
                        }), "B16@0:8");
        class_addMethod(created, NSSelectorFromString(@"hasIndicatorBehavior"),
                        imp_implementationWithBlock(^BOOL(id receiver) { return NO; }), "B16@0:8");
        class_addMethod(created, NSSelectorFromString(@"preferredAlertingDuration:"),
                        imp_implementationWithBlock(^double(id receiver, double suggested) {
                            // Apple ends an alert after this long without telling OITI. That suits a notice, which OITI
                            // removes after the same time, but a download lasts as long as the download does.
                            if (OITIItemForElement(receiver)[@"download"]) return kOITIDownloadAlertDuration;
                            return (double)sIslandNoticeDuration;
                        }),
                        "d24@0:8d16");
        objc_registerClassPair(created);
        elementClass = created;
    });
    return elementClass;
}
