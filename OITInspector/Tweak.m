#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <OITCore/OITCore.h>

static NSString * const kOITInspectorDirectory = @"/var/mobile/Documents/OITInspector";
static NSString * const kOITInspectorDumpNotification = @"com.wilburt.oitinspector/Dump";
static const NSUInteger kOITInspectorMaxDepth = 64;

static NSArray<NSString *> *OITInspectorClassNameFilters(void) {
    return @[@"StatusBar", @"Clock", @"TimeLabel", @"Island", @"Aperture",
              @"Battery", @"Wifi", @"WiFi", @"Cell", @"Signal", @"Carrier",
              @"Call", @"Recording", @"Hotspot", @"Tethering", @"Mic",
              @"Microphone", @"Pill", @"Indicator"];
}

static void OITInspectorEnsureDirectoryExists(void) {
    [[NSFileManager defaultManager] createDirectoryAtPath:kOITInspectorDirectory
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:nil];
}

// Some system windows (UIStatusBarWindow among them) predate UIScene and are
// never attached to a UIWindowScene, so scene-only enumeration silently misses
// them. UIApplication.windows is deprecated but still catches non-scene
// windows. This is intentionally read-only diagnostic code, never shipped
// anywhere, so silencing the deprecation warning here is fine.
static NSArray<UIWindow *> *OITInspectorAllWindows(void) {
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop

    return windows.array;
}

static void OITInspectorAppendLayerDump(CALayer *layer, NSUInteger depth, NSMutableString *output) {
    if (!layer || depth > kOITInspectorMaxDepth) return;
    NSString *indent = [@"" stringByPaddingToLength:(depth * 2) withString:@" " startingAtIndex:0];
    CGRect frame = layer.frame;
    [output appendFormat:@"%@[layer] %@  frame=(%.1f, %.1f, %.1f, %.1f)  hidden=%d  opacity=%.2f\n",
        indent,
        NSStringFromClass([layer class]),
        frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
        layer.hidden,
        layer.opacity];
    for (CALayer *sublayer in layer.sublayers) {
        OITInspectorAppendLayerDump(sublayer, depth + 1, output);
    }
}

static void OITInspectorAppendViewDump(UIView *view, NSUInteger depth, NSMutableString *output) {
    if (!view || depth > kOITInspectorMaxDepth) return;
    NSString *indent = [@"" stringByPaddingToLength:(depth * 2) withString:@" " startingAtIndex:0];
    CGRect frame = view.frame;
    NSString *className = NSStringFromClass([view class]);
    NSString *bgDescription = view.backgroundColor ? [NSString stringWithFormat:@"  bg=%@", view.backgroundColor] : @"";
    [output appendFormat:@"%@%@  frame=(%.1f, %.1f, %.1f, %.1f)  hidden=%d  alpha=%.2f%@\n",
        indent,
        className,
        frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
        view.hidden,
        view.alpha,
        bgDescription];

    if ([className rangeOfString:@"StatusBar" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        OITInspectorAppendLayerDump(view.layer, depth + 1, output);
    }

    for (UIView *subview in view.subviews) {
        OITInspectorAppendViewDump(subview, depth + 1, output);
    }
}

static void OITInspectorDumpWindows(void) {
    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"OITInspector window dump -- %@\n\n", [NSDate date]];

    NSInteger windowIndex = 0;
    for (UIWindow *window in OITInspectorAllWindows()) {
        [output appendFormat:@"== Window %ld: %@  level=%.1f  frame=%@ ==\n",
            (long)windowIndex,
            NSStringFromClass([window class]),
            window.windowLevel,
            NSStringFromCGRect(window.frame)];
        OITInspectorAppendViewDump(window, 1, output);
        [output appendString:@"\n"];
        windowIndex++;
    }

    NSString *path = [kOITInspectorDirectory stringByAppendingPathComponent:@"Latest-Windows.txt"];
    NSError *error = nil;
    BOOL wrote = [output writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    OITLog(@"window dump wrote=%d path=%@ error=%@", wrote, path, error.localizedDescription ?: @"none");
}

static void OITInspectorDumpMatchingClasses(void) {
    NSArray<NSString *> *filters = OITInspectorClassNameFilters();
    NSMutableArray<NSString *> *matches = [NSMutableArray array];

    unsigned int count = 0;
    Class *classList = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        const char *rawName = class_getName(classList[i]);
        if (!rawName) continue;
        NSString *className = [NSString stringWithUTF8String:rawName];
        for (NSString *filter in filters) {
            if ([className rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [matches addObject:className];
                break;
            }
        }
    }
    free(classList);

    [matches sortUsingSelector:@selector(caseInsensitiveCompare:)];

    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"OITInspector class scan -- %@\n", [NSDate date]];
    [output appendFormat:@"Filters: %@\n\n", [filters componentsJoinedByString:@", "]];
    for (NSString *className in matches) {
        [output appendFormat:@"%@\n", className];
    }

    NSString *path = [kOITInspectorDirectory stringByAppendingPathComponent:@"Latest-Classes.txt"];
    NSError *error = nil;
    BOOL wrote = [output writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    OITLog(@"class scan wrote=%d matches=%lu path=%@ error=%@", wrote, (unsigned long)matches.count, path, error.localizedDescription ?: @"none");
}

static void OITInspectorRunFullDump(void) {
    OITInspectorEnsureDirectoryExists();
    OITInspectorDumpWindows();
    OITInspectorDumpMatchingClasses();
}

__attribute__((constructor))
static void OITInspectorInit(void) {
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if (![bundleID isEqualToString:@"com.apple.springboard"]) return;

    OITLogSetEnabled(YES);
    OITLog(@"OITInspector loaded");

    OITObserveDarwinNotification(kOITInspectorDumpNotification, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            OITLog(@"dump triggered via notification");
            OITInspectorRunFullDump();
        });
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OITLog(@"running automatic launch-time dump");
        OITInspectorRunFullDump();
    });
}
