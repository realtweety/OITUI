// OITIDump.xm -- the on-demand state dump (OITI diagnostics, read-only).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 1, Diagnostics): the dump helpers (colors, view
// lines, window trees, Apple's Island classes, queried classes, layout metrics, environment) and OITIRunDump, which
// writes one numbered dump to the log. Everything here runs only when DiagnosticsLevel >= 1 and a trigger asks for
// it (see OITIDumpTriggers.xm); it changes nothing on screen. Reference: DIAGNOSTICS.md.

#import "Shared/OITIShared.h"
#import "Diagnostics/OITIDiagnostics.h"

static NSString * const kOITIClassQueryPath = @"/tmp/OITIClassQuery.txt";

static const NSUInteger kOITIDumpMaxLines = 800;
static const NSUInteger kOITIDumpMaxDepth = 16;
static const NSUInteger kOITIClassListMaxLines = 800;
static const NSUInteger kOITIClassQueryMethodCap = 250;

static NSUInteger sDumpCount = 0;

// =============================================================================================
// MARK: Dump helpers
// =============================================================================================

NSString *OITIColorDesc(UIColor *color) {
    if (!color) return @"nil";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [NSString stringWithFormat:@"rgba(%.2f,%.2f,%.2f,%.2f)", r, g, b, a];
    }
    return [NSString stringWithFormat:@"%@", color];
}

static NSString *OITITextOfView(UIView *view) {
    if (![view respondsToSelector:@selector(text)]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id value = [view performSelector:@selector(text)];
#pragma clang diagnostic pop
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

NSString *OITIViewLine(UIView *view) {
    NSMutableString *line = [NSMutableString stringWithFormat:@"%@@%p frame=%@ bounds=%@ alpha=%.2f subviews=%lu",
                             NSStringFromClass([view class]), view, NSStringFromCGRect(view.frame),
                             NSStringFromCGRect(view.bounds), view.alpha, (unsigned long)view.subviews.count];
    if (view.hidden) [line appendString:@" HIDDEN"];
    if (!CGAffineTransformIsIdentity(view.transform)) {
        [line appendFormat:@" transform=%@", NSStringFromCGAffineTransform(view.transform)];
    }
    if (!view.userInteractionEnabled) [line appendString:@" noInteraction"];
    if (view.clipsToBounds) [line appendString:@" clips"];
    if (view.layer.cornerRadius > 0) [line appendFormat:@" cornerRadius=%.1f", view.layer.cornerRadius];
    if (view.backgroundColor) [line appendFormat:@" bg=%@", OITIColorDesc(view.backgroundColor)];
    if (![view.layer isMemberOfClass:[CALayer class]]) {
        [line appendFormat:@" layer=%@", NSStringFromClass([view.layer class])];
    }
    NSString *text = OITITextOfView(view);
    if (text.length) [line appendFormat:@" text=\"%@\"", text];
    UIResponder *next = view.nextResponder;
    if ([next isKindOfClass:[UIViewController class]]) {
        [line appendFormat:@" vc=%@@%p", NSStringFromClass([next class]), next];
    }
    return line;
}

static void OITIDumpViewTree(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (!view) return;
    if (*budget == 0) return;
    (*budget)--;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    [sLog logTag:@"DUMP" format:@"TREE %@%@", indent, OITIViewLine(view)];
    if (depth >= kOITIDumpMaxDepth) {
        if (view.subviews.count) {
            [sLog logTag:@"DUMP" format:@"TREE %@  ...(%lu subview(s) not shown, depth limit)",
             indent, (unsigned long)view.subviews.count];
        }
        return;
    }
    for (UIView *subview in view.subviews) {
        OITIDumpViewTree(subview, depth + 1, budget);
    }
}

static void OITIDumpViewControllerTree(UIViewController *controller, NSUInteger depth, NSString *relation) {
    if (!controller || depth > 8) return;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    [sLog logTag:@"DUMP" format:@"VC %@%@%@@%p view=%@", indent, relation,
     NSStringFromClass([controller class]), controller,
     controller.isViewLoaded ? NSStringFromClass([controller.view class]) : @"(not loaded)"];
    for (UIViewController *child in controller.childViewControllers) {
        OITIDumpViewControllerTree(child, depth + 1, @"child ");
    }
    if (controller.presentedViewController) {
        OITIDumpViewControllerTree(controller.presentedViewController, depth + 1, @"presented ");
    }
}

static void OITIDumpTrackedWindow(UIView *view, NSString *label) {
    [sLog logTag:@"DUMP" format:@"WINDOW %@ %@", label, OITIViewLine(view)];
    if ([view isKindOfClass:[UIWindow class]]) {
        UIWindow *window = (UIWindow *)view;
        [sLog logTag:@"DUMP" format:@"WINDOW %@ level=%.1f key=%d scene=%@ rootVC=%@", label,
         window.windowLevel, window.isKeyWindow,
         window.windowScene ? NSStringFromClass([window.windowScene class]) : @"nil",
         window.rootViewController ? NSStringFromClass([window.rootViewController class]) : @"nil"];
        OITIDumpViewControllerTree(window.rootViewController, 0, @"root ");
    }
    NSUInteger budget = kOITIDumpMaxLines;
    OITIDumpViewTree(view, 0, &budget);
    if (budget == 0) {
        [sLog logTag:@"DUMP" format:@"TREE (output truncated at %lu lines)", (unsigned long)kOITIDumpMaxLines];
    }
}

static void OITIDumpEnvironment(void) {
    UIScreen *screen = [UIScreen mainScreen];
    const OITIDeviceProfile *profile = OITICurrentProfile();
    [sLog logTag:@"DUMP" format:@"ENV build=%@ machine=%@ os=%@ screen=%@ scale=%.1f",
     kOITIBuildTag, [OITDeviceInfo machineIdentifier],
     [NSProcessInfo processInfo].operatingSystemVersionString,
     NSStringFromCGRect(screen.bounds), screen.scale];
    if (profile) {
        [sLog logTag:@"DUMP" format:@"ENV profile islandY=%.2f bannerY=%.2f bannerSize=%.1fx%.1f verified=%d",
         (double)profile->islandY, (double)profile->bannerY, (double)profile->bannerWidth,
         (double)profile->bannerHeight, (int)profile->verified];
    } else {
        [sLog logTag:@"DUMP" format:@"ENV profile=none (no built-in offsets for this device)"];
    }
    [sLog logTag:@"DUMP" format:@"ENV isFullScreenDevice=%d hasDynamicIsland=%d safeMode=%d",
     [OITDeviceInfo isFullScreenDevice], [OITDeviceInfo hasDynamicIsland], sSafeModeActive];
    [sLog logTag:@"DUMP" format:@"PREFS %@", OITIPrefSnapshotString(OITIPrefSnapshot())];
}

static void OITIDumpWindowsOverview(void) {
    NSUInteger index = 0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            BOOL tracked = [sApertureWindows containsObject:window] || [sBannerWindows containsObject:window];
            [sLog logTag:@"DUMP" format:@"WINDOWS #%lu %@@%p level=%.1f hidden=%d frame=%@ tracked=%d",
             (unsigned long)index++, NSStringFromClass([window class]), window, window.windowLevel,
             window.hidden, NSStringFromCGRect(window.frame), tracked];
        }
    }
    if (index == 0) {
        [sLog logTag:@"DUMP" format:@"WINDOWS none visible through connectedScenes (SpringBoard windows are often not listed there)"];
    }
}

// Apple's Island classes: every loaded class whose name contains "aperture", with the image that owns it.
static void OITIDumpApertureClasses(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (!name || !strcasestr(name, "aperture")) continue;
        const char *image = class_getImageName(classes[i]);
        const char *slash = image ? strrchr(image, '/') : NULL;
        Class super = class_getSuperclass(classes[i]);
        [lines addObject:[NSString stringWithFormat:@"%s : %s  image=%s", name,
                          super ? class_getName(super) : "(root)", slash ? slash + 1 : (image ?: "?")]];
    }
    free(classes);
    [lines sortUsingSelector:@selector(compare:)];
    [sLog logTag:@"DUMP" format:@"CLASSES %lu loaded class(es) with \"aperture\" in the name", (unsigned long)lines.count];
    NSUInteger shown = 0;
    for (NSString *line in lines) {
        if (shown++ >= kOITIClassListMaxLines) {
            [sLog logTag:@"DUMP" format:@"CLASSES (truncated at %lu)", (unsigned long)kOITIClassListMaxLines];
            break;
        }
        [sLog logTag:@"DUMP" format:@"CLASSES %@", line];
    }

    // Research the interfaces before installing any hooks against them. Protocol names and method
    // encodings vary by OS build, so this read-only dump gives us the device's actual ABI first.
    unsigned int protocolCount = 0;
    Protocol * __unsafe_unretained *protocols = objc_copyProtocolList(&protocolCount);
    NSMutableArray<NSString *> *apertureProtocols = [NSMutableArray array];
    for (unsigned int i = 0; i < protocolCount; i++) {
        const char *name = protocol_getName(protocols[i]);
        if (name && strcasestr(name, "aperture")) [apertureProtocols addObject:@(name)];
    }
    free(protocols);
    [apertureProtocols sortUsingSelector:@selector(compare:)];
    [sLog logTag:@"DUMP" format:@"PROTOCOLS %lu loaded protocol(s) with \"aperture\" in the name",
     (unsigned long)apertureProtocols.count];
    for (NSString *name in apertureProtocols) {
        [sLog logTag:@"DUMP" format:@"PROTOCOL %@", name];
    }

    // Report only the relevant method type encodings; this is enough to safely declare diagnostic
    // hooks on this iOS build without flooding the log with every method on every aperture class.
    NSDictionary<NSString *, NSArray<NSString *> *> *researchSelectors = @{
        @"SBSystemApertureProvidedContentElement": @[@"initWithIdentifier:contentProvider:"],
        @"SAUISystemApertureManager": @[@"registerElement:", @"registeredElements", @"orderedElementViewControllers"],
        @"SBSystemAperturePresentableManager": @[@"registerElement:", @"invalidateElement:"],
        @"SBUISystemApertureCustomContentProvider": @[@"initWithView:", @"providedView", @"contentColor"],
        @"SBChargingSystemApertureElementProvider": @[@"powerElementWithBatteryCapacity:"],
        @"SBSystemApertureElementAuthority": @[@"elementsOrderedByPromotionFromTemporallyOrderedElements:withPreviousOrdering:"],
    };
    for (NSString *className in researchSelectors) {
        Class cls = NSClassFromString(className);
        if (!cls) {
            [sLog logTag:@"DUMP" format:@"RESEARCH class %@ not found", className];
            continue;
        }
        for (NSString *selectorName in researchSelectors[className]) {
            SEL selector = NSSelectorFromString(selectorName);
            Method method = class_getInstanceMethod(cls, selector);
            if (!method) method = class_getClassMethod(cls, selector);
            [sLog logTag:@"DUMP" format:@"RESEARCH %@ %@ encoding=%s",
             className, selectorName, method ? method_getTypeEncoding(method) : "(method not found)"];
        }
    }
}

void OITIDumpMethods(Class cls, NSString *kind) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    [sLog logTag:@"CLASSQ" format:@"  %@ methods: %u", kind, count];
    for (unsigned int i = 0; i < count && i < kOITIClassQueryMethodCap; i++) {
        const char *types = method_getTypeEncoding(methods[i]);
        [sLog logTag:@"CLASSQ" format:@"    %@ %s  [%s]", kind, sel_getName(method_getName(methods[i])), types ?: "?"];
    }
    if (count > kOITIClassQueryMethodCap) {
        [sLog logTag:@"CLASSQ" format:@"    (%u more %@ method(s) not shown)", count - (unsigned int)kOITIClassQueryMethodCap, kind];
    }
    free(methods);
}

// Describes every class named in /tmp/OITIClassQuery.txt: superclass chain, protocols, ivars and methods.
static void OITIDumpQueriedClasses(void) {
    NSString *contents = [NSString stringWithContentsOfFile:kOITIClassQueryPath encoding:NSUTF8StringEncoding error:nil];
    if (!contents.length) {
        [sLog logTag:@"CLASSQ" format:@"no class query (%@ missing or empty)", kOITIClassQueryPath];
        return;
    }
    for (NSString *rawLine in [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *name = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!name.length || [name hasPrefix:@"#"]) continue;
        Class cls = NSClassFromString(name);
        if (!cls) {
            [sLog logTag:@"CLASSQ" format:@"%@ -- class not found in this process", name];
            continue;
        }
        NSMutableArray<NSString *> *chain = [NSMutableArray array];
        for (Class c = cls; c; c = class_getSuperclass(c)) [chain addObject:NSStringFromClass(c)];
        const char *image = class_getImageName(cls);
        [sLog logTag:@"CLASSQ" format:@"%@  chain=%@  image=%s", name, [chain componentsJoinedByString:@" > "], image ?: "?"];

        unsigned int protocolCount = 0;
        Protocol * __unsafe_unretained *protocols = class_copyProtocolList(cls, &protocolCount);
        NSMutableArray<NSString *> *protocolNames = [NSMutableArray array];
        for (unsigned int i = 0; i < protocolCount; i++) [protocolNames addObject:@(protocol_getName(protocols[i]))];
        free(protocols);
        [sLog logTag:@"CLASSQ" format:@"  protocols: %@", protocolNames.count ? [protocolNames componentsJoinedByString:@", "] : @"(none)"];

        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        [sLog logTag:@"CLASSQ" format:@"  ivars: %u", ivarCount];
        for (unsigned int i = 0; i < ivarCount && i < 60; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            [sLog logTag:@"CLASSQ" format:@"    %s  [%s]", ivar_getName(ivars[i]) ?: "?", type ?: "?"];
        }
        free(ivars);

        OITIDumpMethods(cls, @"-");
        OITIDumpMethods(object_getClass(cls), @"+");
    }
}

// Formats the return value of a no-argument getter, for the METRICS dump. Returns nil for unsupported types.
static NSString *OITIFormatGetterResult(const void *buffer, const char *type) {
    if (!strcmp(type, "d")) return [NSString stringWithFormat:@"%.3f", *(const double *)buffer];
    if (!strcmp(type, "f")) return [NSString stringWithFormat:@"%.3f", *(const float *)buffer];
    if (!strcmp(type, "B")) return *(const BOOL *)buffer ? @"YES" : @"NO";
    if (!strcmp(type, "q")) return [NSString stringWithFormat:@"%lld", *(const long long *)buffer];
    if (!strcmp(type, "Q")) return [NSString stringWithFormat:@"%llu", *(const unsigned long long *)buffer];
    if (!strcmp(type, "{CGSize=dd}")) {
        const CGSize *v = (const CGSize *)buffer;
        return [NSString stringWithFormat:@"%.3f x %.3f", v->width, v->height];
    }
    if (!strcmp(type, "{CGPoint=dd}")) {
        const CGPoint *v = (const CGPoint *)buffer;
        return [NSString stringWithFormat:@"(%.3f, %.3f)", v->x, v->y];
    }
    if (!strcmp(type, "{CGRect={CGPoint=dd}{CGSize=dd}}")) {
        const CGRect *v = (const CGRect *)buffer;
        return [NSString stringWithFormat:@"origin (%.3f, %.3f) size %.3f x %.3f",
                v->origin.x, v->origin.y, v->size.width, v->size.height];
    }
    if (!strcmp(type, "{NSDirectionalEdgeInsets=dddd}")) {
        const NSDirectionalEdgeInsets *v = (const NSDirectionalEdgeInsets *)buffer;
        return [NSString stringWithFormat:@"top %.3f leading %.3f bottom %.3f trailing %.3f",
                v->top, v->leading, v->bottom, v->trailing];
    }
    return nil;
}

// Calls every no-argument getter that `source` declares (numbers, sizes, rects and insets only) on `target` and logs
// the result. Read-only: these are plain computed values.
static void OITIDumpNoArgGetters(id target, Class source, NSString *prefix) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(source, &count);
    for (unsigned int i = 0; i < count; i++) {
        SEL selector = method_getName(methods[i]);
        const char *name = sel_getName(selector);
        if (!name || strchr(name, ':') || name[0] == '.' || !strcmp(name, "hash")) continue;

        char *returnType = method_copyReturnType(methods[i]);
        NSMethodSignature *signature = [target methodSignatureForSelector:selector];
        if (!returnType || !signature || signature.numberOfArguments != 2) {
            free(returnType);
            continue;
        }
        NSString *text = nil;
        @try {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.target = target;
            invocation.selector = selector;
            [invocation invoke];
            NSUInteger length = signature.methodReturnLength;
            if (length > 0 && length <= 64) {
                char buffer[64];
                memset(buffer, 0, sizeof(buffer));
                [invocation getReturnValue:buffer];
                text = OITIFormatGetterResult(buffer, returnType);
            }
        } @catch (NSException *exception) {
            text = [NSString stringWithFormat:@"(threw %@)", exception.name];
        }
        if (text) {
            [sLog logTag:@"DUMP" format:@"METRICS %@ %s = %@  [%s]", prefix, name, text, returnType];
        }
        free(returnType);
    }
    free(methods);
}

// What Apple sizes the Island from. The "effective" values below include any multiplier set by the Metrics* prefs;
// the "raw" lines show what Apple's own getters returned.
static void OITIDumpLayoutMetrics(void) {
    Class cls = NSClassFromString(@"SBUISystemApertureLayoutMetrics");
    if (!cls) {
        [sLog logTag:@"DUMP" format:@"METRICS class SBUISystemApertureLayoutMetrics not found"];
        return;
    }
    id shared = nil;
    if ([cls respondsToSelector:@selector(sharedInstanceForEmbeddedDisplay)]) {
        shared = [cls sharedInstanceForEmbeddedDisplay];
    }
    [sLog logTag:@"DUMP" format:@"METRICS shared instance=%@", shared ? [NSString stringWithFormat:@"%@@%p", NSStringFromClass([shared class]), shared] : @"nil"];
    [sLog logTag:@"DUMP" format:@"METRICS multiplier sensorRegionSize=%.3f x %.3f", sMetricsSensorX, sMetricsSensorY];
    [sLog logTag:@"DUMP" format:@"METRICS raw (what Apple returned to the hook; 0 x 0 = not called yet) sensorRegionSize=%.3f x %.3f",
     sRawSensorRegionSize.width, sRawSensorRegionSize.height];
    OITIDumpNoArgGetters(cls, object_getClass(cls), @"class");
    if (shared) OITIDumpNoArgGetters(shared, cls, @"effective");
}


void OITIRunDump(NSString *reason) {
    if (!sLog.enabled) return;
    NSUInteger index = ++sDumpCount;
    [sLog logTag:@"DUMP" format:@"=== BEGIN #%lu reason=%@ ===", (unsigned long)index, reason];
    OITIDumpEnvironment();
    OITIRunStatusBarDiagnostic(reason);
    OITIDumpLayoutMetrics();
    OITIDumpWindowsOverview();

    NSArray *apertureManagers;
    @synchronized (sObservedApertureManagers) {
        apertureManagers = sObservedApertureManagers.allObjects;
    }
    [sLog logTag:@"DUMP" format:@"APERTURE-MANAGERS %lu observed", (unsigned long)apertureManagers.count];
    for (id manager in apertureManagers) {
        [sLog logTag:@"DUMP" format:@"APERTURE-MANAGER %@", OITIObjectSummary(manager)];
    }

    NSArray<UIView *> *apertureWindows = sApertureWindows.allObjects;
    NSArray<UIView *> *bannerWindows = sBannerWindows.allObjects;
    if (!apertureWindows.count) {
        [sLog logTag:@"DUMP" format:@"WINDOW no SBSystemApertureWindow seen yet (hooks not installed, safe mode, or the Island has not laid out)"];
    }
    for (UIView *window in apertureWindows) OITIDumpTrackedWindow(window, @"SBSystemApertureWindow");
    for (UIView *window in bannerWindows) OITIDumpTrackedWindow(window, @"SBBannerWindow");

    OITIDumpApertureClasses();
    OITIDumpQueriedClasses();
    [sLog logTag:@"DUMP" format:@"=== END #%lu ===", (unsigned long)index];
}
