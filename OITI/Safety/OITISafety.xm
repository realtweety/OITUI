// OITISafety.xm -- the respring-loop guard and the startup self-check (v0.3.0 module split, round 7).
//
// Moved from Tweak.xm unchanged: the restore helper launcher, OITIEvaluateLoopGuard (safe mode after repeated respring cycles)
// and OITIRunStartupSelfCheck (the MobileGestalt spoof against islandEnabled). The %ctor in Tweak.xm calls both in the same
// order as before. The guard settings and the state-file paths are declared in Safety/OITISafety.h.

#import "Shared/OITIShared.h"
#import "Safety/OITISafety.h"

extern char **environ;

NSString * const kOITIBootLogPath = @"/var/mobile/Library/Preferences/OITIBootLog.plist";
NSString * const kOITISafeModePath = @"/var/mobile/Library/Preferences/OITISafeMode.plist";
// Written by OITI's settings pages just before they ask for a respring (Respring button, Clear Safe Mode). The loop
// guard consumes it: a respring the user asked for is not a crash, so that launch is not counted. Older than
// kOITIRespringIntentMaxAge seconds it is ignored.
static NSString * const kOITIRespringIntentPath = @"/var/mobile/Library/Preferences/OITIRespringIntent.plist";
static const NSTimeInterval kOITIRespringIntentMaxAge = 30.0;
static NSString * const kOITIGestaltBackupBreadcrumbPath = @"/var/mobile/Library/Preferences/OITIGestaltBackup.plist";
static const char * const kOITIRestoreHelperPath = "/var/jb/usr/libexec/OITIRestoreGestalt";

// Diagnostics and safe-mode settings (prefs keys listed in the header comment).
BOOL sGuardEnabled = YES;
NSInteger sGuardMaxLaunches = 5;
NSInteger sGuardWindowSeconds = 120;
NSInteger sGuardStableSeconds = 45;
BOOL sGuardRestoreGestalt = NO;


static void OITIRunRestoreHelper(void) {
    if (access(kOITIRestoreHelperPath, X_OK) != 0) {
        [sLog logTag:@"SAFE" format:@"restore helper not found or not executable at %s", kOITIRestoreHelperPath];
        return;
    }
    pid_t pid = 0;
    char *argv[] = { (char *)kOITIRestoreHelperPath, NULL };
    int rc = posix_spawn(&pid, kOITIRestoreHelperPath, NULL, NULL, argv, environ);
    if (rc != 0) {
        [sLog logTag:@"SAFE" format:@"posix_spawn of restore helper failed rc=%d", rc];
        return;
    }
    [sLog logTag:@"SAFE" format:@"restore helper started pid=%d", pid];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int status = 0;
        waitpid(pid, &status, 0);
        [sLog logTag:@"SAFE" format:@"restore helper exited status=%d", WIFEXITED(status) ? WEXITSTATUS(status) : -1];
    });
}

// ---- The respring-loop guard, in two steps (v0.3.0 polish, batch 2) --------------------------------------------------------
//
// Step 1, OITIGuardBeginLaunch(), runs first thing in the %ctor, right after the log and the guard settings are available and
// BEFORE preferencesChanged() or anything else that could fail. It only records this launch. Before batch 2 the launch was
// recorded in the single evaluation function, which ran after preferencesChanged(): a SpringBoard that died inside
// preferencesChanged() (the v0.3.0 batch 1 bootloop) left no trace, so safe mode could never trip.
//
// Step 2, OITIEvaluateLoopGuard(), counts the launches inside the window and decides. It also runs before preferencesChanged(),
// so when it trips, the %ctor skips preferencesChanged() and installs no hooks: a crash in that code path cannot repeat.
//
// What did not change: the thresholds and settings, what counts as a launch (a respring asked for from OITI's settings does not,
// and a tripped safe mode is left alone until it is cleared), the state files, the stable-launch timer and every log line.
static NSArray<NSNumber *> *sGuardLaunches;       // launches inside the window including this one (set by Step 1)
static NSTimeInterval sGuardLaunchTime;
static BOOL sGuardLaunchCounted;                  // NO for a requested respring, or when Step 1 did not record

void OITIGuardBeginLaunch(void) {
    sGuardLaunches = nil;
    sGuardLaunchCounted = NO;
    if (!sGuardEnabled) return;
    NSDictionary *flag = [NSDictionary dictionaryWithContentsOfFile:kOITISafeModePath];
    if ([flag[@"tripped"] boolValue]) return;   // safe mode stays on: the history and any respring marker are left as they are
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    sGuardLaunchTime = now;

    // A respring requested from OITI's settings pages is not a crash. The marker is consumed either way (a stale
    // one is deleted and ignored), and a fresh one means the previous SpringBoard was healthy enough to be asked
    // to restart, so the launch history is forgotten instead of grown.
    NSDictionary *intent = [NSDictionary dictionaryWithContentsOfFile:kOITIRespringIntentPath];
    if (intent) {
        [[NSFileManager defaultManager] removeItemAtPath:kOITIRespringIntentPath error:nil];
        id intentTime = intent[@"time"];
        NSTimeInterval intentAge = [intentTime isKindOfClass:[NSNumber class]] ? now - [intentTime doubleValue] : -1;
        if (intentAge >= 0 && intentAge < kOITIRespringIntentMaxAge) {
            [@{ @"launches": @[] } writeToFile:kOITIBootLogPath atomically:YES];
            sLaunchWasRequestedRespring = YES;
            [sLog logTag:@"GUARD" format:@"respring requested from OITI settings %.0f s ago: launch not counted, history cleared",
             intentAge];
            return;
        }
        [sLog logTag:@"GUARD" format:@"ignored a stale respring marker (age %.0f s)", intentAge];
    }

    NSDictionary *bootLog = [NSDictionary dictionaryWithContentsOfFile:kOITIBootLogPath];
    NSMutableArray<NSNumber *> *launches = [NSMutableArray array];
    id stored = bootLog[@"launches"];
    if ([stored isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)stored) {
            if (![entry isKindOfClass:[NSNumber class]]) continue;
            NSTimeInterval age = now - [entry doubleValue];
            if (age >= 0 && age < (NSTimeInterval)sGuardWindowSeconds) [launches addObject:entry];
        }
    }
    [launches addObject:@(now)];
    while (launches.count > 16) [launches removeObjectAtIndex:0];
    [@{ @"launches": launches } writeToFile:kOITIBootLogPath atomically:YES];
    sGuardLaunches = launches;
    sGuardLaunchCounted = YES;
}

// Returns YES when OITI must stay in safe mode (hooks not installed) for this launch. Call OITIGuardBeginLaunch() first.
BOOL OITIEvaluateLoopGuard(void) {
    if (!sGuardEnabled) {
        [sLog logTag:@"GUARD" format:@"disabled by SafeModeGuardEnabled"];
        return NO;
    }
    NSDictionary *flag = [NSDictionary dictionaryWithContentsOfFile:kOITISafeModePath];
    if ([flag[@"tripped"] boolValue]) {
        [sLog logTag:@"SAFE" format:@"safe mode still active (tripped at %@, reason: %@). Clear with: rm %@",
         flag[@"time"], flag[@"reason"], kOITISafeModePath];
        return YES;
    }
    if (!sGuardLaunchCounted) return NO;   // a respring asked for in OITI's settings (logged by Step 1)
    NSArray<NSNumber *> *launches = sGuardLaunches ?: @[];
    [sLog logTag:@"GUARD" format:@"SpringBoard launches in the last %ld s: %lu (trip at %ld)",
     (long)sGuardWindowSeconds, (unsigned long)launches.count, (long)sGuardMaxLaunches];
    if ((NSInteger)launches.count >= sGuardMaxLaunches) {
        NSString *reason = [NSString stringWithFormat:@"%lu SpringBoard launches within %ld s",
                            (unsigned long)launches.count, (long)sGuardWindowSeconds];
        [@{ @"tripped": @YES, @"time": @(sGuardLaunchTime), @"reason": reason, @"build": kOITIBuildTag }
            writeToFile:kOITISafeModePath atomically:YES];
        [sLog logTag:@"SAFE" format:@"TRIPPED: %@. OITI hooks will not be installed. Clear with: rm %@",
         reason, kOITISafeModePath];
        if (sGuardRestoreGestalt) {
            [sLog logTag:@"SAFE" format:@"SafeModeRestoreGestalt is on: running the restore helper"];
            OITIRunRestoreHelper();
        } else {
            [sLog logTag:@"SAFE" format:@"SafeModeRestoreGestalt is off: the MobileGestalt spoof was left as is"];
        }
        return YES;
    }
    // A launch that stays up long enough is not part of a loop: forget the history.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)sGuardStableSeconds * (int64_t)NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [@{ @"launches": @[] } writeToFile:kOITIBootLogPath atomically:YES];
        [sLog logTag:@"GUARD" format:@"stable for %ld s: launch history cleared", (long)sGuardStableSeconds];
    });
    return NO;
}

// ---- "Island elements are off" flag (v0.3.0 polish, batch 2) ----------------------------------------------------------------
// When the promotion guard has caught five exceptions it switches element creation off until the next respring
// (sPoCDisabledAfterFailure). That used to be visible only in the log. The tweak now also writes this small file so the Settings
// pages can say so; the next SpringBoard launch deletes it, because a launch turns element creation back on.
NSString * const kOITIElementsOffPath = @"/var/mobile/Library/Preferences/OITIElementsOff.plist";

void OITIMarkElementsOff(int failures, NSString *reason) {
    NSDictionary *flag = @{ @"time": @([[NSDate date] timeIntervalSince1970]), @"failures": @(failures),
                            @"reason": reason ?: @"", @"build": kOITIBuildTag };
    [flag writeToFile:kOITIElementsOffPath atomically:YES];
}

void OITIClearElementsOffFlag(void) {
    [[NSFileManager defaultManager] removeItemAtPath:kOITIElementsOffPath error:nil];
}

// 2556 is the spoofed value. iOS 16 only ever runs on one model that natively reports it (iPhone 14 Pro).
// Keep in sync with OITIMachineHasNativeIsland in OITIRootListController.m.
BOOL OITIMachineHasNativeIsland(NSString *machine) {
    return [machine isEqualToString:@"iPhone15,2"];
}

void OITIRunStartupSelfCheck(void) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltPlistPath];
    if (!plist) {
        [sLog logTag:@"CHECK" format:@"WARN MobileGestalt cache not readable at the expected path; cannot verify the spoof"];
        return;
    }
    id value = ((NSDictionary *)((NSDictionary *)plist[kOITIGestaltCacheExtraKey])[kOITIGestaltNestedKey])[kOITIGestaltLeafKey];
    BOOL isSpoofed = [value isKindOfClass:[NSNumber class]] && [value integerValue] == 2556;

    NSString *machine = [OITDeviceInfo machineIdentifier];
    BOOL nativeIsland = OITIMachineHasNativeIsland(machine);

    NSDictionary *breadcrumb = [NSDictionary dictionaryWithContentsOfFile:kOITIGestaltBackupBreadcrumbPath];
    BOOL haveBreadcrumb = [breadcrumb[@"BackupCaptured"] boolValue];
    BOOL originalPresent = [breadcrumb[@"OriginalValuePresent"] boolValue];
    id originalValue = breadcrumb[@"OriginalValue"];
    BOOL backupSuspect = [breadcrumb[@"CaptureSuspect"] boolValue];
    // The backup says the "original" value was the spoof value, on hardware that is not Island hardware: it was
    // captured while the spoof was already active, so restoring it can never remove the spoof.
    BOOL backupHoldsSpoofValue = haveBreadcrumb && originalPresent &&
        [originalValue isKindOfClass:[NSNumber class]] && [originalValue integerValue] == 2556 && !nativeIsland;

    [sLog logTag:@"CHECK" format:@"ArtworkDeviceSubType in cache=%@ islandEnabled=%d machine=%@ nativeIsland=%d | breadcrumb=%d originalPresent=%d original=%@ captureSuspect=%d",
     value ?: @"(absent)", islandEnabled, machine, nativeIsland, haveBreadcrumb, originalPresent,
     originalValue ?: @"(none)", backupSuspect];

    BOOL warned = NO;
    if (backupHoldsSpoofValue) {
        warned = YES;
        [sLog logTag:@"CHECK" format:@"WARN the restore breadcrumb records 2556 as the ORIGINAL ArtworkDeviceSubType, but 2556 is the spoof value and %@ is not Dynamic Island hardware. The backup was captured while the spoof was already active, so restoring it cannot remove the spoof (this also affects the prerm helper). Open OITI's settings page once: it repairs the backup. Then check the next CHECK line after a respring.", machine];
    }
    if (islandEnabled && !isSpoofed) {
        warned = YES;
        [sLog logTag:@"CHECK" format:@"WARN islandEnabled is ON but the cache does not hold 2556: the Island spoof is not active (iOS update rebuilt the cache, or something restored it)"];
    } else if (!islandEnabled && isSpoofed) {
        warned = YES;
        if (backupHoldsSpoofValue) {
            [sLog logTag:@"CHECK" format:@"WARN islandEnabled is OFF but the cache still holds 2556, and the poisoned backup (above) cannot remove it. Repair the backup first, then turn islandEnabled off again."];
        } else {
            [sLog logTag:@"CHECK" format:@"WARN islandEnabled is OFF but the cache still holds 2556: a stale spoof was left behind (the restore did not run, or did not take effect)"];
        }
    }
    if (islandEnabled && !haveBreadcrumb) {
        warned = YES;
        [sLog logTag:@"CHECK" format:@"WARN islandEnabled is ON but there is no restore breadcrumb: the prerm helper cannot restore the original value"];
    }
    if (backupSuspect && !backupHoldsSpoofValue) {
        [sLog logTag:@"CHECK" format:@"INFO the backup was repaired: the original is recorded as absent, so turning islandEnabled off (or uninstalling) removes the key and lets iOS recompute the real value"];
    }
    if (!warned) {
        [sLog logTag:@"CHECK" format:@"OK spoof state matches islandEnabled"];
    }
}
