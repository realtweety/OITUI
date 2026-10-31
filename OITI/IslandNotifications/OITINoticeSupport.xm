// OITINoticeSupport.xm -- safe readers and research helpers for Island notifications (OITI).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 4, IslandNotifications).
// Exception-safe getters (OITISafeObject, OITIKVCObject, OITISafeBool), the element description helpers, the once-per-key trace,
// the live-element breadcrumb file and the crash-recovery check, and the element identifier stub class.

#import "Shared/OITIShared.h"
#import "IslandNotifications/OITIIslandNotifications.h"

static NSMutableSet<NSString *> *sStubSelectorsSeen;

@implementation OITIElementIdentifierStub
- (id)elementIdentifier { return self.value; }
- (id)clientIdentifier { return @"com.apple.springboard"; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return self.value ?: @"OITIElementIdentifierStub"; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [super methodSignatureForSelector:selector] ?: [NSMethodSignature signatureWithObjCTypes:"@@:"];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    NSString *name = NSStringFromSelector(invocation.selector);
    @synchronized ([OITIElementIdentifierStub class]) {
        if (!sStubSelectorsSeen) sStubSelectorsSeen = [NSMutableSet set];
        if (![sStubSelectorsSeen containsObject:name]) {
            [sStubSelectorsSeen addObject:name];
            [sLog logTag:@"ELEMENT" format:@"STUB identifier was sent -%@ (answering with %@)", name,
             [name rangeOfString:@"dentifier" options:NSCaseInsensitiveSearch].location != NSNotFound ? @"the string" : @"nil"];
        }
    }
    id result = [name rangeOfString:@"dentifier" options:NSCaseInsensitiveSearch].location != NSNotFound ? self.value : nil;
    [invocation setReturnValue:&result];
}
@end

// Returns an object-valued, no-argument selector's result, or nil if the object does not implement it with that shape.
id OITISafeObject(id object, NSString *selectorName) {
    if (!object || !selectorName.length) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, "@") != 0) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [object performSelector:selector];
#pragma clang diagnostic pop
}

NSString *OITISafeString(id object, NSString *selectorName) {
    id value = OITISafeObject(object, selectorName);
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

static NSNumber *OITIKVCNumber(id object, NSString *key) {
    if (!object) return nil;
    @try {
        id value = [object valueForKey:key];
        return [value isKindOfClass:[NSNumber class]] ? (NSNumber *)value : nil;
    } @catch (NSException *exception) {
        return nil;
    }
}

id OITIKVCObject(id object, NSString *key) {
    if (!object) return nil;
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}

// Which parts an element has (class name or nil). Real elements versus ours: the nil that breaks Apple's code is in here.
NSString *OITIElementPartsSummary(id element) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in @[@"viewProvider", @"elementHost", @"layoutHost", @"leadingView", @"trailingView", @"minimalView",
                            @"primaryView", @"secondaryView", @"actionView", @"element"]) {
        id value = OITIKVCObject(element, key);
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, value ? NSStringFromClass([value class]) : @"nil"]];
    }
    return [parts componentsJoinedByString:@" "];
}

// "[idA, idB]" for an array of elements (their elementIdentifier), for the authority ordering log.
NSString *OITIElementIdentifierList(id elements) {
    if (![elements conformsToProtocol:@protocol(NSFastEnumeration)]) return OITIObjectSummary(elements);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id element in elements) {
        id identifier = OITIKVCObject(element, @"elementIdentifier");
        [names addObject:[NSString stringWithFormat:@"%@", identifier ?: NSStringFromClass([element class])]];
    }
    return [NSString stringWithFormat:@"[%@]", [names componentsJoinedByString:@", "]];
}

// One line describing an element: class, both identifiers, layout modes.
NSString *OITIElementValuesSummary(id element) {
    id elementID = OITIKVCObject(element, @"elementIdentifier");
    id clientID = OITIKVCObject(element, @"clientIdentifier");
    return [NSString stringWithFormat:@"%@ elementIdentifier=%@(%@) clientIdentifier=%@(%@) layoutMode=%@ preferred=%@ min=%@ max=%@",
            NSStringFromClass([element class]), elementID, elementID ? NSStringFromClass([elementID class]) : @"nil",
            clientID, clientID ? NSStringFromClass([clientID class]) : @"nil",
            OITIKVCNumber(element, @"layoutMode"), OITIKVCNumber(element, @"preferredLayoutMode"),
            OITIKVCNumber(element, @"minimumSupportedLayoutMode"), OITIKVCNumber(element, @"maximumSupportedLayoutMode")];
}

// Called after Apple registers one of its own elements: log its values and remember the first set of layout modes.
void OITICaptureRealElement(id element) {
    if (!element) return;
    if ([sLog isLoggingAtLevel:1]) {
        [sLog logTag:@"ELEMENT" format:@"REAL element %@", OITIElementValuesSummary(element)];
        [sLog logTag:@"ELEMENT" format:@"REAL parts   %@: %@", NSStringFromClass([element class]), OITIElementPartsSummary(element)];
    }
    if (sRealLayoutValues) return;
    NSNumber *preferred = OITIKVCNumber(element, @"preferredLayoutMode");
    NSNumber *minimum = OITIKVCNumber(element, @"minimumSupportedLayoutMode");
    NSNumber *maximum = OITIKVCNumber(element, @"maximumSupportedLayoutMode");
    if (preferred && minimum && maximum) {
        sRealLayoutValues = @{ @"preferred": preferred, @"minimum": minimum, @"maximum": maximum };
        [sLog logTag:@"ELEMENT" format:@"remembered real layout values preferred=%@ min=%@ max=%@ from %@", preferred, minimum, maximum,
         NSStringFromClass([element class])];
    }
}

// ---- Trace of what Apple asks OITI's element ------------------------------------------------
NSMutableSet<NSString *> *sTraceSeen;

// ---- Element crash recovery ------------------------------------------------------------------
// Written (synchronously, so it survives an immediate crash) when the first OITI element goes live, deleted when the
// last one leaves. Found at launch it means the previous SpringBoard ended while an element was live.
void OITIWriteElementBreadcrumb(NSString *reason) {
    NSDictionary *crumb = @{ @"time": @([[NSDate date] timeIntervalSince1970]),
                             @"pid": @(getpid()),
                             @"reason": reason ?: @"",
                             @"build": kOITIBuildTag };
    if (![crumb writeToFile:kOITILiveElementPath atomically:YES]) {
        [sLog logTag:@"ELEMENT" format:@"RECOVERY breadcrumb could not be written"];
    }
}

void OITIClearElementBreadcrumb(void) {
    [[NSFileManager defaultManager] removeItemAtPath:kOITILiveElementPath error:nil];
}

// Called once at launch, before the hooks are installed. A breadcrumb left by a SpringBoard that ended while an OITI
// element was live starts the recovery window, unless that launch was a respring requested from OITI's own settings
// (the previous process was healthy then).
void OITIEvaluateElementBreadcrumb(void) {
    NSDictionary *crumb = [NSDictionary dictionaryWithContentsOfFile:kOITILiveElementPath];
    if (!crumb) return;
    OITIClearElementBreadcrumb();
    id when = crumb[@"time"];
    NSTimeInterval age = [when isKindOfClass:[NSNumber class]] ? [[NSDate date] timeIntervalSince1970] - [when doubleValue] : -1;
    if (sLaunchWasRequestedRespring) {
        [sLog logTag:@"ELEMENT" format:@"RECOVERY not needed: SpringBoard was restarted from OITI's settings while an element was live (%@)", crumb[@"reason"]];
        return;
    }
    sElementRecoveryUntil = CFAbsoluteTimeGetCurrent() + kOITIElementRecoveryWindow;
    [sLog logTag:@"ELEMENT" format:@"RECOVERY the previous SpringBoard ended while an OITI Island element was live (%@, %.0f s before this launch, build %@): Island notifications and the startup animation stay off for %.0f s and the stock banner is used",
     crumb[@"reason"], age, crumb[@"build"], kOITIElementRecoveryWindow];
}

// True while the recovery window is open. Main thread only.
BOOL OITIElementRecoveryActive(NSString *reason) {
    if (sElementRecoveryUntil <= 0) return NO;
    CFAbsoluteTime left = sElementRecoveryUntil - CFAbsoluteTimeGetCurrent();
    if (left <= 0) {
        sElementRecoveryUntil = 0;
        [sLog logTag:@"ELEMENT" format:@"RECOVERY window is over: Island elements are allowed again"];
        return NO;
    }
    [sLog logTag:@"ELEMENT" format:@"RECOVERY: %@ is not shown as an Island element (%.0f s left); the stock banner is used", reason, left];
    return YES;
}

// Logs one TRACE line per distinct message per test run, in the order they first happen.
void OITITraceOnce(NSString *message) {
    @synchronized ([NSNull null]) {
        if (!sTraceSeen) sTraceSeen = [NSMutableSet set];
        if ([sTraceSeen containsObject:message]) return;
        [sTraceSeen addObject:message];
    }
    [sLog logTag:@"ELEMENT" format:@"TRACE %@", message];
}

// First-stage prototype: verify launch gating and Island handoff with the existing custom-content element.
// The final Hello video and dedicated media view are intentionally not part of this prototype.
BOOL OITISafeBool(id object, NSString *selectorName, BOOL *available) {
    if (available) *available = NO;
    if (!object || !selectorName.length) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2) return NO;
    const char *returnType = signature.methodReturnType;
    if (!returnType || (returnType[0] != 'B' && returnType[0] != 'c')) return NO;
    if (available) *available = YES;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}
