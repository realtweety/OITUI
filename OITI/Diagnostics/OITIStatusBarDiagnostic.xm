// OITIStatusBarDiagnostic.xm -- the read-only status bar provider report (OITI diagnostics).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 1, Diagnostics). It runs once at boot (also in
// safe mode) and on every dump. The two provider-name helpers it calls live with the status bar provider choice in
// Tweak.xm and are declared in Shared/OITIShared.h. Reference: DIAGNOSTICS.md, "Status bar".

#import "Shared/OITIShared.h"
#import "Diagnostics/OITIDiagnostics.h"

// =============================================================================================
// MARK: Status bar provider diagnostic (read-only)
// =============================================================================================

// Why this exists: with the Island spoof on, some notch iPhones (reported on iPhone XR, 11 and 13 mini) show a red
// status bar titled "rdar:45025538". That bar looks like UIKit's placeholder when no usable status bar visual
// provider is chosen for the screen. This function only READS (level 1). It prints the screen geometry, every provider
// class that exists on the device, any UIStatusBarVisualProviderClassName override in com.apple.UIKit and the Status Bar
// Layout setting. The class UIKit actually chose is logged by the CHOICE and LIVE lines further down.


void OITIRunStatusBarDiagnostic(NSString *reason) {
    if (!sLog.enabled || sLog.level < 1) return;
    @try {
        UIScreen *screen = [UIScreen mainScreen];
        NSString *machine = [OITDeviceInfo machineIdentifier];
        const OITIDeviceProfile *profile = OITICurrentProfile();

        [sLog logTag:@"STATUSBAR" format:@"BEGIN reason=%@ build=%@ machine=%@ os=%@ islandEnabled=%d safeMode=%d",
         reason, kOITIBuildTag, machine, [NSProcessInfo processInfo].operatingSystemVersionString,
         islandEnabled, sSafeModeActive];
        [sLog logTag:@"STATUSBAR" format:@"SCREEN bounds=%@ nativeBounds=%@ scale=%.3f nativeScale=%.3f",
         NSStringFromCGRect(screen.bounds), NSStringFromCGRect(screen.nativeBounds),
         (double)screen.scale, (double)screen.nativeScale];
        if (profile) {
            [sLog logTag:@"STATUSBAR" format:@"TABLE %s (%s) bannerSize=%.0fx%.0f islandY=%.1f verified=%d",
             profile->name, profile->model, (double)profile->bannerWidth, (double)profile->bannerHeight,
             (double)profile->islandY, (int)profile->verified];
        } else {
            [sLog logTag:@"STATUSBAR" format:@"TABLE no entry for %@", machine];
        }

        NSString *nativeSource = nil;
        NSString *nativeName = profile ? OITINativeProviderNameForScreen(screen, &nativeSource) : nil;
        [sLog logTag:@"STATUSBAR" format:@"NATIVE provider auto would use=%@ (from %@) | learned record=%@",
         nativeName ?: @"(none: device not in the table)", nativeSource ?: @"-", OITILearnedNativeProviderName() ?: @"(none)"];

        id overrideValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("UIStatusBarVisualProviderClassName"),
                                                                  CFSTR("com.apple.UIKit")));
        [sLog logTag:@"STATUSBAR" format:@"OVERRIDE UIStatusBarVisualProviderClassName (com.apple.UIKit) = %@",
         overrideValue ?: @"(not set)"];
        [sLog logTag:@"STATUSBAR" format:@"LAYOUT Status Bar Layout setting=%@ (auto, off, or a provider class name)",
         [sOITIPreferences stringForKey:@"StatusBarLayout" default:@"auto"]];

        // Every loaded class named _UIStatusBar*Provider*, with its superclass. Covers both the
        // _UIStatusBarVisualProvider_* family and names like _UIStatusBarProvider_DynamicSplit.
        unsigned int count = 0;
        Class *classes = objc_copyClassList(&count);
        NSMutableArray<NSString *> *found = [NSMutableArray array];
        for (unsigned int i = 0; i < count; i++) {
            const char *name = class_getName(classes[i]);
            if (!name || strncmp(name, "_UIStatusBar", 12) != 0 || !strstr(name, "Provider")) continue;
            Class super = class_getSuperclass(classes[i]);
            [found addObject:[NSString stringWithFormat:@"%s : %s", name, super ? class_getName(super) : "(root)"]];
        }
        free(classes);
        [found sortUsingSelector:@selector(compare:)];
        [sLog logTag:@"STATUSBAR" format:@"PROVIDERS %lu loaded class(es) match _UIStatusBar*Provider*",
         (unsigned long)found.count];
        NSUInteger shown = 0;
        for (NSString *entry in found) {
            if (shown++ >= 60) {
                [sLog logTag:@"STATUSBAR" format:@"PROVIDER (list truncated at 60)"];
                break;
            }
            [sLog logTag:@"STATUSBAR" format:@"PROVIDER %@", entry];
        }
        [sLog logTag:@"STATUSBAR" format:@"END reason=%@", reason];
    } @catch (NSException *exception) {
        [sLog logTag:@"STATUSBAR" format:@"ERROR exception %@: %@", exception.name, exception.reason];
    }
}
