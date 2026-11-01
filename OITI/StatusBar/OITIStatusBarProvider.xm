// OITIStatusBarProvider.xm -- the status bar provider choice (OITI Settings > Status Bar Layout).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 6, StatusBar): the provider decision (off, auto or a named
// class), the learned native provider record, the native-provider table lookups, the live status bar log and the
// OITIStatusBarHooks Logos group (+[_UIStatusBarVisualProvider_iOS visualProviderSubclassForScreen:visualProviderInfo:] and
// -[_UIStatusBar _prepareVisualProviderIfNeeded]).
//
// A Logos group can only be initialised in the file that defines it, so OITIInstallStatusBarHooks at the end of this file does
// the %init and the %ctor in Tweak.xm calls it where it used to say %init(OITIStatusBarHooks).

#import "Shared/OITIShared.h"
#import "StatusBar/OITIStatusBar.h"
#import "Safety/OITISafety.h"

// With the Island spoof on, some notch iPhones get UIKit's placeholder provider (_UIStatusBarVisualProvider_Fallback,
// the red "rdar:45025538" bar). UIKit picks the provider in +visualProviderSubclassForScreen:visualProviderInfo:.
// This hook always calls %orig and logs the answer. What it does with it depends on the Status Bar Layout setting
// (key StatusBarLayout in com.wilburt.oiti.prefs, a picker on the OITI settings page, default "auto"):
//   "off"   never changes UIKit's answer.
//   "auto"  while the Island is on and the device is a notch iPhone in the table, return its native Split provider
//           when UIKit chose nothing (nil, what a 13 mini returns under the spoof) or Fallback, or (for the 828 and 1080
//           pixel screens, the widths reported to show the red bar) when UIKit chose anything else. Other devices, and any device UIKit already
//           handles, are left alone.
//   <class> a _UIStatusBarVisualProvider_* class name: return that class while the Island is on (for trying layouts).
// A wrong class can crash SpringBoard, which the respring-loop guard turns into safe mode (hooks off) after 5 launches.
// The provider is chosen when a status bar is built, so a changed setting needs a respring.
//
// The native provider "auto" returns comes from, in order: the record this phone wrote about itself (below), the
// table of models read from real logs, and a guess by native pixel width. The record is written the first time a
// launch with the Island off builds a status bar (unproven on a notch iPhone: the 8 Plus runs it inert).

@interface _UIStatusBarVisualProvider_iOS : NSObject
@end

@interface _UIStatusBar : UIView
- (Class)_visualProviderClass;
- (NSString *)_visualProviderClassName;
- (id)visualProviderInfo;
- (id)targetScreen;
@end

static NSString * const kOITIProviderPrefix = @"_UIStatusBarVisualProvider_";
static NSString * const kOITIFallbackProviderName = @"_UIStatusBarVisualProvider_Fallback";
static NSString * const kOITIStatusBarLayoutKey = @"StatusBarLayout";
static NSString * const kOITIStatusBarLayoutAuto = @"auto";
static NSString * const kOITIStatusBarLayoutOff = @"off";
NSMutableSet<NSString *> *sLoggedProviderChoices;
NSHashTable *sLoggedStatusBars;
static NSUInteger sLiveStatusBarLogCount = 0;

// The provider UIKit chose natively on this phone (Island off), written by OITIMaybeLearnNativeProvider and read back
// by "auto". Flat plist next to the other OITI state files. Not removed on uninstall.
static NSString * const kOITINativeProviderPath = @"/var/mobile/Library/Preferences/OITINativeProvider.plist";
BOOL sIslandEnabledAtLaunch = NO;          // set in %ctor from the first preferences load
static BOOL sNativeProviderLearnAttempted = NO;   // one attempt per launch
static BOOL sLearnedNativeProviderLoaded = NO;
static NSString *sLearnedNativeProvider = nil;

static NSInteger OITINativePixelWidth(UIScreen *screen) {
    CGSize pixels = screen.nativeBounds.size;
    return (NSInteger)llround(MIN(pixels.width, pixels.height));
}

// The record this phone wrote about itself, or nil. Read once per launch and kept. It is only trusted for the same
// machine identifier (a restored backup from another phone is ignored) and only if it names a real provider class
// name (never Fallback).
NSString *OITILearnedNativeProviderName(void) {
    @synchronized (kOITINativeProviderPath) {
        if (!sLearnedNativeProviderLoaded) {
            sLearnedNativeProviderLoaded = YES;
            NSDictionary *record = [NSDictionary dictionaryWithContentsOfFile:kOITINativeProviderPath];
            id name = record[@"provider"];
            id machine = record[@"machine"];
            if ([name isKindOfClass:[NSString class]] && [machine isKindOfClass:[NSString class]] &&
                [machine isEqualToString:[OITDeviceInfo machineIdentifier]] &&
                [name hasPrefix:kOITIProviderPrefix] && ![name isEqualToString:kOITIFallbackProviderName]) {
                sLearnedNativeProvider = name;
            }
        }
        return sLearnedNativeProvider;
    }
}

// The provider UIKit uses natively (Island off) for a device. Order: the record this phone wrote (learned), then a
// model read from that device's own log ("CHOICE UIKit chose ..." with islandEnabled=0; table), then a guess by
// native pixel width using the names in the STATUSBAR PROVIDER dump (width guess, an estimate until someone reports a
// log). *source says which one answered, nil when none did.
NSString *OITINativeProviderNameForScreen(UIScreen *screen, NSString **source) {
    NSString *name = nil;
    NSString *from = nil;
    NSString *learned = OITILearnedNativeProviderName();
    if (learned) {
        name = learned;
        from = @"learned record";
    } else if ([[OITDeviceInfo machineIdentifier] isEqualToString:@"iPhone14,4"]) {
        name = @"_UIStatusBarVisualProvider_Split1080_Wide";   // iPhone 13 mini
        from = @"table";
    } else {
        switch (OITINativePixelWidth(screen)) {
            case 828:  name = @"_UIStatusBarVisualProvider_Split828"; break;
            case 1080: name = @"_UIStatusBarVisualProvider_Split1080"; break;
            case 1125: name = @"_UIStatusBarVisualProvider_Split1125"; break;
            case 1170: name = @"_UIStatusBarVisualProvider_Split1170"; break;
            case 1242: name = @"_UIStatusBarVisualProvider_Split1242"; break;
            case 1284: name = @"_UIStatusBarVisualProvider_Split1284"; break;
            default: break;
        }
        if (name) from = @"width guess";
    }
    if (source) *source = from;
    return name;
}

// Only classes named _UIStatusBarVisualProvider_* are accepted, so a typo cannot return an unrelated class.
static Class OITIProviderClassNamed(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || ![name hasPrefix:kOITIProviderPrefix]) return Nil;
    return NSClassFromString(name);
}

static NSString *OITIStatusBarLayoutSetting(void) {
    NSString *layout = [sOITIPreferences stringForKey:kOITIStatusBarLayoutKey default:kOITIStatusBarLayoutAuto];
    return layout.length ? layout : kOITIStatusBarLayoutAuto;
}

// Writes the provider UIKit chose natively on this phone, so "auto" does not depend on a table built from other
// people's logs. It only runs when UIKit's answer is certainly native: the Island was off when SpringBoard started
// (the MobileGestalt value is read once per process, so a phone that started with the spoof stays spoofed until the
// next respring) and is still off, the phone is a notch iPhone in the table, and UIKit chose a real provider (not
// nil, not Fallback). The file checks run off the main thread: the cache must not hold the spoofed value and no
// UIStatusBarVisualProviderClassName override may be set, since either would make UIKit's answer not native.
// One attempt per launch, and nothing is rewritten when the record already says the same.
static void OITIMaybeLearnNativeProvider(Class chosen, UIScreen *screen) {
    if (sNativeProviderLearnAttempted) return;
    if (islandEnabled || sIslandEnabledAtLaunch) return;
    if (screen != [UIScreen mainScreen]) return;
    sNativeProviderLearnAttempted = YES;
    if (!OITICurrentProfile()) {
        [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: %@ is not in the device table, so there is no status bar fix to feed and nothing is recorded",
         [OITDeviceInfo machineIdentifier]];
        return;
    }

    NSString *name = chosen ? NSStringFromClass(chosen) : nil;
    NSString *machine = [OITDeviceInfo machineIdentifier];
    NSString *bounds = NSStringFromCGRect(screen.nativeBounds);
    if (!name || ![name hasPrefix:kOITIProviderPrefix] || [name isEqualToString:kOITIFallbackProviderName]) {
        [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: UIKit chose %@ with the Island off, which is not a usable native provider", name ?: @"nil"];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @try {
            id overrideValue = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("UIStatusBarVisualProviderClassName"),
                                                                      CFSTR("com.apple.UIKit")));
            if (overrideValue) {
                [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: UIStatusBarVisualProviderClassName override is set (%@), so UIKit's answer may not be native", overrideValue];
                return;
            }
            NSDictionary *cache = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
            if (!cache) {
                [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: the MobileGestalt cache is not readable, cannot confirm the spoof is absent"];
                return;
            }
            id extra = cache[kOITIGestaltCacheExtraKey];
            id nested = [extra isKindOfClass:[NSDictionary class]] ? extra[kOITIGestaltNestedKey] : nil;
            id subtype = [nested isKindOfClass:[NSDictionary class]] ? nested[kOITIGestaltLeafKey] : nil;
            if ([subtype isKindOfClass:[NSNumber class]] && [subtype integerValue] == 2556 && !OITIMachineHasNativeIsland(machine)) {
                [sLog logTag:@"STATUSBAR" format:@"LEARN skipped: the cache holds the spoofed ArtworkDeviceSubType 2556, so UIKit's answer is not native"];
                return;
            }

            NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kOITINativeProviderPath];
            if ([existing[@"machine"] isEqual:machine] && [existing[@"provider"] isEqual:name]) {
                [sLog logTag:@"STATUSBAR" format:@"LEARN record already holds %@ for %@", name, machine];
                return;
            }
            NSDictionary *record = @{
                @"machine": machine ?: @"",
                @"provider": name,
                @"nativeBounds": bounds ?: @"",
                @"os": [NSProcessInfo processInfo].operatingSystemVersionString ?: @"",
                @"build": kOITIBuildTag,
                @"time": @([[NSDate date] timeIntervalSince1970]),
            };
            BOOL written = [record writeToFile:kOITINativeProviderPath atomically:YES];
            [sLog logTag:@"STATUSBAR" format:@"LEARN %@: native provider for %@ is %@ (nativeBounds=%@, previous record=%@)",
             written ? @"recorded" : @"WRITE FAILED", machine, name, bounds, existing[@"provider"] ?: @"(none)"];
            if (written) {
                @synchronized (kOITINativeProviderPath) {
                    sLearnedNativeProvider = name;
                    sLearnedNativeProviderLoaded = YES;
                }
            }
        } @catch (NSException *exception) {
            [sLog logTag:@"STATUSBAR" format:@"LEARN ERROR exception %@: %@", exception.name, exception.reason];
        }
    });
}

static Class OITIStatusBarProviderDecision(Class chosen, id screenArgument, id info) {
    Class result = chosen;
    @try {
        UIScreen *screen = [screenArgument isKindOfClass:[UIScreen class]] ? (UIScreen *)screenArgument : [UIScreen mainScreen];
        OITIMaybeLearnNativeProvider(chosen, screen);
        NSString *layout = OITIStatusBarLayoutSetting();
        NSString *chosenName = chosen ? NSStringFromClass(chosen) : @"nil";
        NSInteger width = OITINativePixelWidth(screen);
        Class replacement = Nil;
        NSString *decision = nil;
        NSString *nativeSource = nil;

        if (!islandEnabled) {
            decision = @"idle: Island is off";
        } else if ([layout isEqualToString:kOITIStatusBarLayoutOff]) {
            decision = @"idle: Status Bar Layout is Off";
        } else if ([layout isEqualToString:kOITIStatusBarLayoutAuto]) {
            NSString *nativeName = OITICurrentProfile() ? OITINativeProviderNameForScreen(screen, &nativeSource) : nil;
            Class native = nativeName ? OITIProviderClassNamed(nativeName) : Nil;
            if (!native) {
                decision = @"auto idle: no native provider known for this device";
            } else if (chosen == native) {
                decision = @"auto idle: UIKit already chose the native provider";
            } else if (!chosen || [chosenName isEqualToString:kOITIFallbackProviderName]) {
                replacement = native;
                decision = @"auto replaced UIKit's empty or Fallback choice with the native provider";
            } else if (width == 828 || width == 1080) {
                replacement = native;
                decision = @"auto replaced UIKit's choice on a width reported to show the red bar";
            } else {
                decision = @"auto idle: UIKit chose a real provider";
            }
        } else {
            Class forced = OITIProviderClassNamed(layout);
            if (forced) {
                replacement = forced;
                decision = @"forced the selected layout";
            } else {
                decision = @"selected layout is not a loaded _UIStatusBarVisualProvider_* class, ignored";
            }
        }

        if (nativeSource) decision = [decision stringByAppendingFormat:@" [native provider from %@]", nativeSource];
        if (replacement) result = replacement;

        NSString *replacementName = replacement ? NSStringFromClass(replacement) : @"-";
        NSString *signature = [NSString stringWithFormat:@"%@|%@|%d|%@|%@", chosenName, replacementName,
                               islandEnabled, layout, NSStringFromCGRect(screen.nativeBounds)];
        BOOL firstTime = NO;
        if (sLoggedProviderChoices) {
            @synchronized (sLoggedProviderChoices) {
                if (sLoggedProviderChoices.count < 16 && ![sLoggedProviderChoices containsObject:signature]) {
                    [sLoggedProviderChoices addObject:signature];
                    firstTime = YES;
                }
            }
        }
        if (firstTime) {
            NSString *infoText = info ? [[info description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] : @"nil";
            if (infoText.length > 300) infoText = [infoText substringToIndex:300];
            [sLog logTag:@"STATUSBAR" format:@"CHOICE UIKit chose %@ | screen nativeBounds=%@ scale=%.2f | islandEnabled=%d layout=%@ | %@ -> returning %@ | info=%@",
             chosenName, NSStringFromCGRect(screen.nativeBounds), (double)screen.scale, islandEnabled, layout,
             decision, result ? NSStringFromClass(result) : @"nil", infoText];
        }
    } @catch (NSException *exception) {
        [sLog logTag:@"STATUSBAR" format:@"CHOICE ERROR exception %@: %@ (returning UIKit's own answer)",
         exception.name, exception.reason];
        result = chosen;
    }
    return result;
}

// One line per live _UIStatusBar (the persistent one, the app switcher's and the cover sheet's): the provider class it
// actually ended up with, which can differ from the CHOICE line if something else sets the class name.
static void OITILogLiveStatusBar(_UIStatusBar *bar) {
    if (!sLog.enabled || sLog.level < 1 || !sLoggedStatusBars) return;
    @try {
        @synchronized (sLoggedStatusBars) {
            if (sLiveStatusBarLogCount >= 24 || [sLoggedStatusBars containsObject:bar]) return;
            [sLoggedStatusBars addObject:bar];
            sLiveStatusBarLogCount++;
        }
        Class providerClass = [bar _visualProviderClass];
        NSString *className = [bar respondsToSelector:@selector(_visualProviderClassName)] ? [bar _visualProviderClassName] : nil;
        id target = [bar targetScreen];
        [sLog logTag:@"STATUSBAR" format:@"LIVE %p provider=%@ className=%@ target=%@ window=%@ alpha=%.2f hidden=%d",
         (__bridge void *)bar, providerClass ? NSStringFromClass(providerClass) : @"nil", className ?: @"(none)",
         [target isKindOfClass:[UIScreen class]] ? NSStringFromCGRect([(UIScreen *)target bounds]) : @"nil",
         bar.window ? NSStringFromClass([bar.window class]) : @"nil", (double)bar.alpha, bar.hidden];
    } @catch (NSException *exception) {
        [sLog logTag:@"STATUSBAR" format:@"LIVE ERROR exception %@: %@", exception.name, exception.reason];
    }
}

// Status bar provider choice. A separate group so it installs and fails independently of the Island hooks. It is
// installed under the same safe-mode rule, so safe mode turns it off too.
%group OITIStatusBarHooks

%hook _UIStatusBarVisualProvider_iOS

+ (Class)visualProviderSubclassForScreen:(id)screen visualProviderInfo:(id)info {
    Class chosen = %orig;
    return OITIStatusBarProviderDecision(chosen, screen, info);
}

%end

%hook _UIStatusBar

- (void)_prepareVisualProviderIfNeeded {
    %orig;
    OITILogLiveStatusBar(self);
}

%end

%end

void OITIInstallStatusBarHooks(void) {
    %init(OITIStatusBarHooks);
}
