// OITIAppStoreSource.xm -- feeds the download tracker from the App Store's placeholders in SpringBoard (OITI download progress, stage 2).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 2, DownloadProgress). It reads progress through the
// instance-variable helpers of the install dump (Diagnostics/OITIInstallDump.xm) and calls OITISafeBool, which still lives
// in Tweak.xm; both are declared in the shared headers.

#import "Shared/OITIShared.h"
#import "DownloadProgress/OITIDownloadProgress.h"

#import "Diagnostics/OITIDiagnostics.h"

// =============================================================================================
// MARK: App Store source (Download Progress, stage 2)
// =============================================================================================

// Feeds the download tracker from the App Store's placeholders in SpringBoard. Setting: DownloadAppStoreEnabled (default
// off, Settings > OITI > Download Progress > App Store Downloads); it also needs DownloadProgressEnabled, and Apple Mode and
// safe mode switch it off (safe mode: the timer never starts).
//
// What the install dump showed (build -c, iOS 16.7.16, one App Store download; LEARNINGS.md): a download's placeholder
// carries a percentage and no byte counts. Path, all by instance variables: SBApplicationPlaceholderController
// -placeholdersByDisplayID (bundle ID -> SBApplicationPlaceholder) > _placeholderProxy > _queue_progress
// (FBSApplicationPlaceholderProgress) > _percentComplete (double, 0 to 1, -1 = unknown) and _progress (an NSProgress with a
// total of 100). So the tracker gets a fraction (OITIDownloadUpdateFraction), not bytes.
//
// How it works. A timer on the main run loop polls once a second, only while the feature is on. Each poll reads the
// placeholders. A placeholder with a readable fraction of 0 or more becomes (or stays) a tracked download. When a tracked
// placeholder leaves the list, the app is looked up: installed means complete, and if it is not there after a 3 s grace the
// download counts as complete only when it had reached 97 percent, otherwise as cancelled (an update or a TestFlight
// install has not been dumped yet, so those are unconfirmed).
//
// Risk rules (see LEARNINGS.md, "Never call private methods because their names look like getters"): the progress is read
// from instance variables and the public NSProgress API; the only private method calls are the explicitly named
// accessors placeholdersByDisplayID, displayName and isPaused (a declared property that SpringBoard's own icon code calls),
// plus the shared-instance and applicationWithBundleIdentifier: lookups the install dump already uses. Whether a pause shows
// up in isPaused or in the NSProgress is logged (level 1) the first time it changes, so the first real pause tells us.


static NSTimer *sAppStoreTimer;
static NSMutableDictionary<NSString *, NSMutableDictionary *> *sAppStoreTracked;   // bundle ID -> name, fraction, paused, missingSince
static NSMutableSet<NSString *> *sAppStoreWarned;                                  // one-time warnings per session
static const NSTimeInterval kOITIAppStorePollInterval = 1.0;
static const NSTimeInterval kOITIAppStoreFinishGrace = 3.0;

static NSString *OITIAppStoreIdentifier(NSString *bundleID) {
    return [@"appstore:" stringByAppendingString:bundleID];
}

static id OITIAppStoreIvarObject(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable([object class], name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || type[0] != '@') return nil;
    return object_getIvar(object, ivar);
}

static BOOL OITIAppStoreIvarNumber(id object, const char *name, double *value) {
    if (!object) return NO;
    Ivar ivar = class_getInstanceVariable([object class], name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || !type[0]) return NO;
    double number = NAN;
    if (!OITIInstallIvarScalarText(object, ivar, type, &number) || isnan(number)) return NO;
    if (value) *value = number;
    return YES;
}

// Reads one placeholder. Returns NO when the progress object is not where it was on iOS 16.7.16. fraction is -1 while
// the progress is unknown.
static BOOL OITIAppStoreRead(id placeholder, double *fractionOut, BOOL *pausedOut, NSString **detailOut) {
    id proxy = OITIAppStoreIvarObject(placeholder, "_placeholderProxy");
    id progressObject = OITIAppStoreIvarObject(proxy, "_queue_progress");
    if (!progressObject) return NO;
    double fraction = -1.0, phase = -1.0, state = -1.0;
    BOOL haveFraction = OITIAppStoreIvarNumber(progressObject, "_percentComplete", &fraction);
    OITIAppStoreIvarNumber(progressObject, "_installPhase", &phase);
    OITIAppStoreIvarNumber(progressObject, "_installState", &state);
    id nsProgress = OITIAppStoreIvarObject(progressObject, "_progress");
    BOOL progressPaused = NO;
    if ([nsProgress isKindOfClass:[NSProgress class]]) {
        NSProgress *progress = (NSProgress *)nsProgress;
        if (!haveFraction || (fraction < 0 && !progress.indeterminate)) {
            fraction = progress.fractionCompleted;
            haveFraction = YES;
        }
        progressPaused = progress.paused;
    }
    BOOL available = NO;
    BOOL placeholderPaused = OITISafeBool(placeholder, @"isPaused", &available);
    if (fractionOut) *fractionOut = fraction;
    if (pausedOut) *pausedOut = progressPaused || (available && placeholderPaused);
    if (detailOut) {
        *detailOut = [NSString stringWithFormat:@"installPhase=%.0f installState=%.0f nsProgress=%d progressPaused=%d placeholderPaused=%@",
                      phase, state, nsProgress != nil, (int)progressPaused, available ? (placeholderPaused ? @"YES" : @"NO") : @"?"];
    }
    return haveFraction;
}

static NSString *OITIAppStoreDisplayName(id placeholder, NSString *bundleID) {
    id proxy = OITIAppStoreIvarObject(placeholder, "_placeholderProxy");
    for (id candidate in @[placeholder ?: @"", proxy ?: @""]) {
        if ([candidate isKindOfClass:[NSString class]]) continue;
        id value = OITIInstallObjectGetter(candidate, @"displayName");
        if ([value isKindOfClass:[NSString class]] && ((NSString *)value).length) return value;
    }
    return bundleID;
}

static void OITIAppStorePoll(void) {
    if (!sDownloadProgressEnabled || !sDownloadAppStoreEnabled || sSafeModeActive) return;
    if (!sAppStoreTracked) sAppStoreTracked = [NSMutableDictionary dictionary];
    if (!sAppStoreWarned) sAppStoreWarned = [NSMutableSet set];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @try {
        id controller = OITIInstallSharedInstance(NSClassFromString(@"SBApplicationPlaceholderController"), NULL);
        id dictionary = OITIInstallObjectGetter(controller, @"placeholdersByDisplayID");
        BOOL haveList = [dictionary isKindOfClass:[NSDictionary class]];
        if (!haveList && ![sAppStoreWarned containsObject:@"list"]) {
            [sAppStoreWarned addObject:@"list"];
            [sLog logTag:@"DOWNLOAD" format:@"App Store source: the placeholder list is not available (controller %@). The classes may differ on this iOS version; run the install dump (COMMANDS.md section 17).",
             controller ? @"found" : @"missing"];
        }
        NSMutableSet<NSString *> *present = [NSMutableSet set];
        if (haveList) {
            NSDictionary *placeholders = (NSDictionary *)dictionary;
            for (id key in placeholders.allKeys) {
                if (![key isKindOfClass:[NSString class]]) continue;
                NSString *bundleID = key;
                id placeholder = placeholders[bundleID];
                double fraction = -1.0;
                BOOL paused = NO;
                NSString *detail = nil;
                BOOL readable = OITIAppStoreRead(placeholder, &fraction, &paused, &detail);
                NSMutableDictionary *tracked = sAppStoreTracked[bundleID];
                if (!readable) {
                    if (![sAppStoreWarned containsObject:bundleID]) {
                        [sAppStoreWarned addObject:bundleID];
                        [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source: the placeholder for %@ has no readable progress object, skipped", bundleID];
                    }
                    if (tracked) [present addObject:bundleID];   // keep what is shown until it leaves the list
                    continue;
                }
                if (fraction < 0 && !tracked) continue;   // progress unknown and not tracked yet: not downloading (or not started)
                if (fraction < 0) fraction = [tracked[@"fraction"] doubleValue];   // keep the last value while it is unknown
                [present addObject:bundleID];
                if (!tracked) {
                    tracked = [NSMutableDictionary dictionary];
                    sAppStoreTracked[bundleID] = tracked;
                    tracked[@"paused"] = @NO;
                    tracked[@"name"] = OITIAppStoreDisplayName(placeholder, bundleID);
                    [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source: tracking %@ (%@) at %d%% (%@)", bundleID, tracked[@"name"],
                     (int)lround(fraction * 100.0), detail];
                }
                if ([tracked[@"paused"] boolValue] != paused) {
                    tracked[@"paused"] = @(paused);
                    [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source: %@ %@ at %d%% (%@)", bundleID, paused ? @"paused" : @"resumed",
                     (int)lround(fraction * 100.0), detail];
                }
                tracked[@"fraction"] = @(fraction);
                [tracked removeObjectForKey:@"missingSince"];
                OITIDownloadUpdateFraction(OITIAppStoreIdentifier(bundleID), @"App Store", tracked[@"name"], bundleID, fraction, paused);
                OITLOGGER_LOG_RATED(sLog, 2, @"DOWNLOAD", @"appstore-poll", 1, @"App Store source: %@ %.4f paused=%d %@",
                                    bundleID, fraction, (int)paused, detail);
            }
        }
        for (NSString *bundleID in sAppStoreTracked.allKeys) {
            if ([present containsObject:bundleID]) continue;
            NSMutableDictionary *tracked = sAppStoreTracked[bundleID];
            if (!tracked[@"missingSince"]) tracked[@"missingSince"] = @(now);
            id applicationController = OITIInstallSharedInstance(NSClassFromString(@"SBApplicationController"), NULL);
            BOOL installed = OITIInstallApplicationForBundleID(applicationController, bundleID) != nil;
            BOOL waited = now - [tracked[@"missingSince"] doubleValue] >= kOITIAppStoreFinishGrace;
            if (!installed && !waited) continue;   // the app may still be about to appear
            double lastFraction = [tracked[@"fraction"] doubleValue];
            BOOL completed = installed || lastFraction >= 0.97;
            [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source: %@ left the placeholder list at %d%%: %@ (app installed: %@)", bundleID,
             (int)lround(lastFraction * 100.0), completed ? @"complete" : @"cancelled", installed ? @"yes" : @"no"];
            OITIDownloadFinish(OITIAppStoreIdentifier(bundleID), completed);
            [sAppStoreTracked removeObjectForKey:bundleID];
        }
    } @catch (NSException *exception) {
        [sLog logTag:@"DOWNLOAD" format:@"App Store source: exception %@: %@", exception.name, exception.reason];
    }
}

// Starts or stops the poll for the current settings. Idempotent; called after every preferences reload.
void OITIAppStoreSourceRefresh(void) {
    BOOL wanted = sDownloadProgressEnabled && sDownloadAppStoreEnabled && !sAppleMode && !sSafeModeActive;
    if (wanted && !sAppStoreTimer) {
        sAppStoreTimer = [NSTimer timerWithTimeInterval:kOITIAppStorePollInterval repeats:YES block:^(NSTimer *timer) {
            OITIAppStorePoll();
        }];
        [[NSRunLoop mainRunLoop] addTimer:sAppStoreTimer forMode:NSRunLoopCommonModes];
        [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source on: polling the placeholders every %.0f s", kOITIAppStorePollInterval];
        OITIAppStorePoll();
    } else if (!wanted && sAppStoreTimer) {
        [sAppStoreTimer invalidate];
        sAppStoreTimer = nil;
        for (NSString *bundleID in sAppStoreTracked.allKeys) OITIDownloadDrop(OITIAppStoreIdentifier(bundleID));
        [sAppStoreTracked removeAllObjects];
        [sLog logLevel:1 tag:@"DOWNLOAD" format:@"App Store source off"];
    }
}
