#import <OITCore/OITLog.h>
#import <os/log.h>

static BOOL sOITLogEnabled = NO;

void OITLogSetEnabled(BOOL enabled) {
    sOITLogEnabled = enabled;
}

BOOL OITLogIsEnabled(void) {
    return sOITLogEnabled;
}

void OITLog(NSString *format, ...) {
    if (!sOITLogEnabled) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    os_log(OS_LOG_DEFAULT, "[OITCore] %{public}@", message);
}
