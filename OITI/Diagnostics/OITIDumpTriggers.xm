// OITIDumpTriggers.xm -- what starts a dump (OITI diagnostics).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 1, Diagnostics): the trigger-file poll (one timer, only
// while DiagnosticsLevel >= 1), the Darwin notification observers and the one-shot automatic dump. Touching
// /tmp/OITIDump.trigger, /tmp/OITIPoC.trigger or /tmp/OITIInstallDump.trigger, or posting the matching
// notification, runs the dump, the hello element test or the install dump. Reference: DIAGNOSTICS.md, "Triggers".

#import "Shared/OITIShared.h"
#import "Diagnostics/OITIDiagnostics.h"

static NSString * const kOITIDumpNotification = @"com.wilburt.oiti/Dump";
static NSString * const kOITIDumpTriggerPath = @"/tmp/OITIDump.trigger";
static NSString * const kOITIPoCTriggerPath = @"/tmp/OITIPoC.trigger";
static NSString * const kOITIInstallDumpNotification = @"com.wilburt.oiti/InstallDump";
static NSString * const kOITIInstallDumpTriggerPath = @"/tmp/OITIInstallDump.trigger";
static int64_t sLastInstallTriggerMtimeNs = 0;

static BOOL sAutoDumpScheduled = NO;
static dispatch_source_t sDumpTriggerTimer;
static int64_t sLastTriggerMtimeNs = 0;

static int64_t OITIFileMtimeNs(NSString *path) {
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) return 0;
    return (int64_t)st.st_mtimespec.tv_sec * 1000000000ll + (int64_t)st.st_mtimespec.tv_nsec;
}

static int64_t OITITriggerFileMtimeNs(void) {
    return OITIFileMtimeNs(kOITIDumpTriggerPath);
}

static int64_t sLastPoCTriggerMtimeNs = 0;

// Polls the trigger file once a second, but only while diagnostics are on (DiagnosticsLevel >= 1), so a normal
// install runs no timer at all. Detects by modification time, never deletes (/tmp is sticky).
void OITIUpdateDumpTrigger(void) {
    BOOL wanted = sLog.enabled && sLog.level >= 1;
    if (wanted && !sDumpTriggerTimer) {
        sLastTriggerMtimeNs = OITITriggerFileMtimeNs();
        sLastPoCTriggerMtimeNs = OITIFileMtimeNs(kOITIPoCTriggerPath);
        sLastInstallTriggerMtimeNs = OITIFileMtimeNs(kOITIInstallDumpTriggerPath);
        sDumpTriggerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(sDumpTriggerTimer,
                                  dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                                  NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(sDumpTriggerTimer, ^{
            if (!sLog.enabled || sLog.level < 1) return;
            int64_t mtime = OITITriggerFileMtimeNs();
            if (mtime != 0 && mtime != sLastTriggerMtimeNs) {
                sLastTriggerMtimeNs = mtime;
                OITIRunDump(@"trigger-file");
            }
            int64_t pocMtime = OITIFileMtimeNs(kOITIPoCTriggerPath);
            if (pocMtime != 0 && pocMtime != sLastPoCTriggerMtimeNs) {
                sLastPoCTriggerMtimeNs = pocMtime;
                OITIRunPoCElement(@"trigger-file");
            }
            int64_t installMtime = OITIFileMtimeNs(kOITIInstallDumpTriggerPath);
            if (installMtime != 0 && installMtime != sLastInstallTriggerMtimeNs) {
                sLastInstallTriggerMtimeNs = installMtime;
                OITIRunInstallDump(@"trigger-file");
            }
        });
        dispatch_resume(sDumpTriggerTimer);
        [sLog logLevel:1 tag:@"DUMP" format:@"trigger polling started (touch %@ for a dump, %@ for the hello element, %@ for the install dump)", kOITIDumpTriggerPath, kOITIPoCTriggerPath, kOITIInstallDumpTriggerPath];
    } else if (!wanted && sDumpTriggerTimer) {
        dispatch_source_cancel(sDumpTriggerTimer);
        sDumpTriggerTimer = nil;
    }
}

// The Darwin notification is passive (no timer), so it is registered once at launch.
void OITIObserveDumpNotification(void) {
    OITObserveDarwinNotification(kOITIInstallDumpNotification, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            OITIRunInstallDump(@"darwin-notification");
        });
    });
    OITObserveDarwinNotification(kOITIDumpNotification, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sLog.enabled && sLog.level >= 1) {
                OITIRunDump(@"darwin-notification");
            } else {
                [sLog logTag:@"DUMP" format:@"dump request ignored: DiagnosticsLevel is 0 (set it to 1 or 2 and respring)"];
            }
        });
    });
}

// One baseline dump a few seconds after the Island first lays out.
void OITIScheduleAutoDump(void) {
    if (sAutoDumpScheduled) return;
    sAutoDumpScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (sLog.enabled && sLog.level >= 1) OITIRunDump(@"auto-baseline");
    });
}
