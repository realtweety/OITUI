// OITINotificationHooks.xm -- the hooks of Island notifications (OITI).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 4, IslandNotifications).
// The OITIResearchHooks and OITIDiagnosticHooks Logos groups, the run-time banner hook and the promotion guard. A Logos group can
// only be initialised in the file that defines it, so OITIInstallResearchHooks and OITIInstallDiagnosticHooks at the end do the %init;
// the %ctor in Tweak.xm calls them where it used to say %init(...).

#import "Shared/OITIShared.h"
#import "IslandNotifications/OITIIslandNotifications.h"
#import "DownloadProgress/OITIDownloadProgress.h"

// ---- Promotion guard --------------------------------------------------------------------------
// poc2's element made -[SAUISystemApertureManager _reevaluatePromotedElements] throw inside -[NSArray insertObject:atIndex:],
// which took SpringBoard down on the next layout pass. While one of OITI's elements is live, the exception is caught and
// logged (name, reason, first stack symbols), the element is invalidated and creation is switched off until a respring.
// With none of OITI's elements live the exception is rethrown untouched, so Apple's own behavior never changes.
static void OITIInstallPromotionGuard(void) {
    Class managerClass = NSClassFromString(@"SAUISystemApertureManager");
    SEL selector = NSSelectorFromString(@"_reevaluatePromotedElements");
    Method method = managerClass ? class_getInstanceMethod(managerClass, selector) : NULL;
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    if (!encoding || strcmp(encoding, "v16@0:8") != 0) {
        [sLog logTag:@"ELEMENT" format:@"promotion guard NOT installed: method=%d encoding=%s", method != NULL, encoding ?: "(none)"];
        return;
    }
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id receiver) {
        @try {
            ((void (*)(id, SEL))original)(receiver, selector);
        } @catch (NSException *exception) {
            if (!sIslandNoticeItems.count) @throw;
            NSArray *stack = exception.callStackSymbols;
            [sLog logTag:@"ELEMENT" format:@"GUARD caught %@: %@", exception.name, exception.reason];
            for (NSUInteger i = 0; i < MIN(stack.count, (NSUInteger)10); i++) {
                [sLog logTag:@"ELEMENT" format:@"GUARD   %@", stack[i]];
            }
            if (++sPoCFailureCount >= 5) sPoCDisabledAfterFailure = YES;
            id registered = OITIKVCObject(receiver, @"registeredElements");
            if ([registered conformsToProtocol:@protocol(NSFastEnumeration)]) {
                NSUInteger shown = 0;
                for (id element in registered) {
                    if (shown++ >= 12) break;
                    [sLog logTag:@"ELEMENT" format:@"GUARD element %@", OITIElementValuesSummary(element)];
                    [sLog logTag:@"ELEMENT" format:@"GUARD parts   %@", OITIElementPartsSummary(element)];
                }
            }
            NSArray<NSDictionary *> *items = [sIslandNoticeItems copy];
            [sIslandNoticeItems removeAllObjects];
            for (NSDictionary *item in items) OITIDismissNoticeItem(item);
            if (sDownloadItem) OITIDownloadItemRemoved(sDownloadItem, @"promotion-guard");
            OITIClearElementBreadcrumb();   // the exception was caught and the elements dismissed: SpringBoard is fine
        }
    });
    class_replaceMethod(managerClass, selector, replacement, encoding);
    [sLog logTag:@"ELEMENT" format:@"promotion guard installed on -[SAUISystemApertureManager _reevaluatePromotedElements]"];
}

void OITIInstallIslandNotificationHooks(void) {
    OITIInstallPromotionGuard();
    Class destinationClass = NSClassFromString(@"SBNotificationBannerDestination");
    if (!destinationClass) {
        [sLog logTag:@"NOTIF" format:@"banner hook NOT installed: SBNotificationBannerDestination not found"];
        return;
    }
    const char *encoding = NULL;
    int argCount = 0;
    NSString *name = OITIFirstBannerMethodName(destinationClass, &encoding, &argCount);
    if (!name) {
        [sLog logTag:@"NOTIF" format:@"banner hook NOT installed: no postNotificationRequest* method with a supported shape. Candidates follow."];
        OITILogBannerCandidates(destinationClass);
        return;
    }
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(destinationClass, selector);
    IMP original = method ? method_getImplementation(method) : NULL;
    if (!original) {
        [sLog logTag:@"NOTIF" format:@"banner hook NOT installed: %@ has no implementation", name];
        return;
    }
    IMP replacement;
    if (argCount == 2) {
        replacement = imp_implementationWithBlock(^(id receiver, id request, id other) {
            ((void (*)(id, SEL, id, id))original)(receiver, selector, request, other);
            OITIHandleBannerRequest(receiver, request);
        });
    } else {
        replacement = imp_implementationWithBlock(^(id receiver, id request) {
            ((void (*)(id, SEL, id))original)(receiver, selector, request);
            OITIHandleBannerRequest(receiver, request);
        });
    }
    class_replaceMethod(destinationClass, selector, replacement, encoding);
    [sLog logTag:@"NOTIF" format:@"banner hook installed on -[%@ %@] (encoding %s)", NSStringFromClass(destinationClass), name, encoding];
}

%group OITIResearchHooks

%hook SBSystemApertureController

- (id)initWithWindowScene:(id)scene {
    id result = %orig;
    if (result) sSystemApertureController = result;
    return result;
}

- (id)registerElement:(id)element {
    if (!sSystemApertureController) sSystemApertureController = self;
    id result = %orig;
    BOOL chargingElement = OITIIsChargingSystemElement(element);
    if (sStartupHelloObservationWindowOpen && islandStartupHelloEnabled &&
        !OITIIsOurElement(element) && !OITIIsBaselineLockElement(element) && !chargingElement) {
        sStartupHelloActivitySeen = YES;
        [sLog logLevel:1 tag:@"HELLO" format:@"startup activity observed before prototype presentation: %@ identifier=%@",
         OITIObjectSummary(element), OITIKVCObject(element, @"elementIdentifier")];
    }
    if (sStartupHelloItem && element != sStartupHelloItem[@"element"] && !OITIIsOurElement(element)) {
        [sLog logLevel:1 tag:@"HELLO" format:@"system activity registered during startup playback: %@ identifier=%@",
         OITIObjectSummary(element), OITIKVCObject(element, @"elementIdentifier")];
        if (chargingElement) {
            [sLog logLevel:1 tag:@"HELLO" format:@"charging activity retained until startup playback finishes"];
        } else {
            OITICancelStartupHello(@"system-element-registration");
        }
    }
    return result;
}

%end

%end

%group OITIDiagnosticHooks

%hook SBSystemApertureProvidedContentElement

- (instancetype)initWithIdentifier:(id)identifier contentProvider:(id)contentProvider {
    id result = %orig;
    if ([sLog isLoggingAtLevel:1]) {
        if (identifier && ![identifier isKindOfClass:[NSString class]]) OITIProbeObject(identifier, @"identifier");
        OITIProbeObject(contentProvider, @"contentProvider");
        OITIProbeObject(result, @"element");
    }
    OITLOGGER_LOG_RATED(sLog, 1, @"APERTURE", @"element-init", 8,
        @"ELEMENT init identifier=%@ provider=%@ result=%@",
        OITIObjectSummary(identifier), OITIObjectSummary(contentProvider), OITIObjectSummary(result));
    return result;
}

- (BOOL)respondsToSelector:(SEL)selector {
    BOOL result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element respondsToSelector:%@ -> %d", NSStringFromSelector(selector), result]);
    return result;
}

- (BOOL)conformsToProtocol:(Protocol *)protocol {
    BOOL result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element conformsToProtocol:%s -> %d", protocol_getName(protocol), result]);
    return result;
}

- (BOOL)isKindOfClass:(Class)cls {
    BOOL result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element isKindOfClass:%@ -> %d", NSStringFromClass(cls), result]);
    return result;
}

- (id)viewProvider {
    id result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element viewProvider -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

- (id)element {
    id result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element element -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

- (id)elementHost {
    id result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element elementHost -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

- (id)layoutHost {
    id result = %orig;
    if (OITIIsOurElement(self)) OITITraceOnce([NSString stringWithFormat:@"element layoutHost -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

%end

%hook SAUIElementViewController

- (id)initWithElementViewProvider:(id)provider {
    id result = %orig;
    if (sIslandNoticeItems.count && [sLog isLoggingAtLevel:1]) {
        [sLog logTag:@"ELEMENT" format:@"VCINIT provider=%@(%@) -> %@", NSStringFromClass([provider class]),
         OITIKVCObject(provider, @"elementIdentifier"), result ? OITIObjectSummary(result) : @"nil"];
    }
    return result;
}

%end

%hook SBSystemApertureElementAuthority

- (id)elementsOrderedByPromotionFromTemporallyOrderedElements:(id)elements withPreviousOrdering:(id)previous {
    id result = %orig;
    if (sStartupHelloItem && [result isKindOfClass:[NSArray class]]) {
        NSMutableArray *ordered = [result mutableCopy];
        id helloElement = sStartupHelloItem[@"element"];
        NSUInteger helloIndex = [ordered indexOfObjectIdenticalTo:helloElement];
        NSUInteger chargingIndex = NSNotFound;
        for (NSUInteger i = 0; i < ordered.count; i++) {
            if (OITIIsChargingSystemElement(ordered[i])) { chargingIndex = i; break; }
        }
        if (helloIndex != NSNotFound && chargingIndex != NSNotFound && helloIndex > chargingIndex) {
            [ordered removeObjectAtIndex:helloIndex];
            [ordered insertObject:helloElement atIndex:chargingIndex];
            result = [ordered copy];
            [sLog logLevel:1 tag:@"HELLO" format:@"promoted startup animation ahead of charging activity"];
        }
    }
    if (sIslandNoticeItems.count && [sLog isLoggingAtLevel:1]) {
        [sLog logTag:@"ELEMENT" format:@"AUTH in=%@ previous=%@ out=%@", OITIElementIdentifierList(elements),
         OITIElementIdentifierList(previous), OITIElementIdentifierList(result)];
    }
    return result;
}

%end

%hook SAUISystemApertureManager

- (id)registerElement:(id)element {
    id result = %orig;
    sRegisteringManager = self;
    if (!sPoCOurRegistrationInFlight) OITICaptureRealElement(element);
    if ([sLog isLoggingAtLevel:1]) OITIProbeObject(result, @"registration");
    if ([sLog isLoggingAtLevel:1] && sObservedApertureManagers) {
        @synchronized (sObservedApertureManagers) {
            [sObservedApertureManagers addObject:self];
        }
    }
    OITLOGGER_LOG_RATED(sLog, 1, @"APERTURE", @"register-element", 8,
        @"REGISTER manager=%@ element=%@ result=%@",
        OITIObjectSummary(self), OITIObjectSummary(element), OITIObjectSummary(result));
    return result;
}

- (id)_assertionForElementCreatingIfNecessary:(id)element {
    id result = %orig;
    if (OITIIsOurElement(element)) OITITraceOnce([NSString stringWithFormat:@"manager _assertionForElementCreatingIfNecessary -> %@", result ? NSStringFromClass([result class]) : @"nil"]);
    return result;
}

- (id)_elementViewControllerForElement:(id)element creatingIfNecessary:(BOOL)creating {
    id result = %orig;
    if (sIslandNoticeItems.count && [sLog isLoggingAtLevel:1]) {
        [sLog logTag:@"ELEMENT" format:@"VCFOR element=%@ creating=%d -> %@", OITIKVCObject(element, @"elementIdentifier"), creating,
         result ? OITIObjectSummary(result) : @"nil"];
    }
    return result;
}

- (id)orderedElementViewControllers {
    // Cheap capture so the hello element does not need a charger or timer to have run first.
    if (!sSeenManager) sSeenManager = self;
    return %orig;
}

%end

%end

void OITIInstallResearchHooks(void) {
    %init(OITIResearchHooks);
}

void OITIInstallDiagnosticHooks(void) {
    %init(OITIDiagnosticHooks);
}
