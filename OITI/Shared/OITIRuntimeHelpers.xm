// OITIRuntimeHelpers.xm -- exception-safe readers for private runtime objects (v0.3.0 module split, round 8).
//
// Moved unchanged from the modules that first needed them, so the dependencies point at Shared/ instead of sideways:
//  * from IslandNotifications/OITINoticeSupport.xm: OITISafeObject, OITISafeString, OITIKVCObject and OITISafeBool (the getters
//    used by the notification files, the Hello startup code and the App Store source);
//  * from Diagnostics/OITIInstallDump.xm: OITIInstallIvarScalarText, OITIInstallObjectGetter, OITIInstallSharedInstance and
//    OITIInstallApplicationForBundleID (the instance-variable and getter helpers the App Store download source also calls).
// All are declared in Shared/OITIShared.h. The names are unchanged. A stale two-line comment about the first-stage prototype
// that stood above OITISafeBool was dropped.

#import "Shared/OITIShared.h"

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

id OITIKVCObject(id object, NSString *key) {
    if (!object) return nil;
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}

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

// Reads a scalar instance variable by offset. Returns nil for types it does not handle.
NSString *OITIInstallIvarScalarText(id object, Ivar ivar, const char *type, double *numberOut) {
    const uint8_t *base = (const uint8_t *)(__bridge const void *)object;
    const void *location = base + ivar_getOffset(ivar);
    double number = NAN;
    NSString *text = nil;
    switch (type[0]) {
        case 'B': { bool v; memcpy(&v, location, sizeof v); number = v ? 1 : 0; text = v ? @"YES" : @"NO"; break; }
        case 'c': { signed char v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%d", (int)v]; break; }
        case 'C': { unsigned char v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%u", (unsigned)v]; break; }
        case 'i': { int v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%d", v]; break; }
        case 'I': { unsigned int v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%u", v]; break; }
        case 's': { short v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%d", (int)v]; break; }
        case 'S': { unsigned short v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%u", (unsigned)v]; break; }
        case 'l': { int32_t v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%d", (int)v]; break; }
        case 'L': { uint32_t v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%u", (unsigned)v]; break; }
        case 'q': { long long v; memcpy(&v, location, sizeof v); number = (double)v; text = [NSString stringWithFormat:@"%lld", v]; break; }
        case 'Q': { unsigned long long v; memcpy(&v, location, sizeof v); number = (double)v; text = [NSString stringWithFormat:@"%llu", v]; break; }
        case 'f': { float v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%.4f", (double)v]; break; }
        case 'd': { double v; memcpy(&v, location, sizeof v); number = v; text = [NSString stringWithFormat:@"%.4f", v]; break; }
        default: return nil;
    }
    if (numberOut) *numberOut = number;
    return text;
}

id OITIInstallObjectGetter(id object, NSString *selectorName) {
    if (!object) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    Method method = class_getInstanceMethod([object class], selector);
    if (!method) return nil;
    char *type = method_copyReturnType(method);
    BOOL isObject = type && type[0] == '@' && type[1] != '?';
    free(type);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!isObject || !signature || signature.numberOfArguments != 2) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (NSException *exception) {
        return nil;
    }
}

id OITIInstallSharedInstance(Class cls, NSString **how) {
    if (!cls) return nil;
    for (NSString *name in @[@"sharedInstanceIfExists", @"sharedInstance", @"sharedController", @"sharedManager"]) {
        SEL selector = NSSelectorFromString(name);
        if (![cls respondsToSelector:selector]) continue;
        id instance = nil;
        @try {
            instance = ((id (*)(Class, SEL))objc_msgSend)(cls, selector);
        } @catch (NSException *exception) {
            instance = nil;
        }
        if (instance) {
            if (how) *how = name;
            return instance;
        }
    }
    return nil;
}

id OITIInstallApplicationForBundleID(id applicationController, NSString *bundleID) {
    SEL selector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (!applicationController || ![applicationController respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL, id))objc_msgSend)(applicationController, selector, bundleID);
    } @catch (NSException *exception) {
        return nil;
    }
}
