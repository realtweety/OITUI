#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------------------------
// Legacy API (unchanged): os_log wrapper with a global on/off switch.
// ---------------------------------------------------------------------------------------------
FOUNDATION_EXPORT void OITLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
FOUNDATION_EXPORT void OITLogSetEnabled(BOOL enabled);
FOUNDATION_EXPORT BOOL OITLogIsEnabled(void);

// ---------------------------------------------------------------------------------------------
// OITLogger: flat-file diagnostic logger extracted from the OITS diagnostic build.
//
//  * Asynchronous: lines are formatted on the caller's thread and written on a private serial queue.
//  * Open/append/close per line, so deleting the file while running just starts a fresh one.
//  * Rotates to "<path>.1" when the file exceeds maxFileBytes.
//  * Bounded: if the writer falls far behind, new lines are dropped and counted, never queued without limit.
//  * Per-key rate limiting (counts what it drops) and per-key stack-trace budgets.
//  * Line format: "MM-dd HH:mm:ss.SSS +seconds-since-logger-created #seq M|B tNNN [TAG] message"
//
// Typical use (one logger per tweak, created once in %ctor):
//
//     static OITLogger *sLog;
//     sLog = [OITLogger loggerWithName:@"oiti" path:@"/tmp/OITIDebug.log"];
//     sLog.level = 1;
//     sLog.ignoredImageNames = @[@"OITI.dylib", @"OITCore.dylib"];
//     [sLog logSessionStartWithBuildTag:@"OITI-2026-10-08-a"];
//     OITLOGGER_LOG(sLog, 1, @"PREF", @"reloaded scale=%.2f", scale);
//     OITLOGGER_LOG_RATED(sLog, 2, @"LAYOUT", @"layout", 10, @"frame=%@", NSStringFromCGRect(f));
//
// Levels: 0 = only what you log unconditionally with -logTag:format:, 1 = events and state changes,
// 2 = every hooked call (use the rated macro). A line logged at level N appears when logger.level >= N.
// ---------------------------------------------------------------------------------------------
@interface OITLogger : NSObject

// `name` labels the writer queue. `path` is the log file; the rotated copy is "<path>.1".
+ (instancetype)loggerWithName:(NSString *)name path:(NSString *)path;

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *path;

@property (atomic) BOOL enabled;                       // default YES. NO silences everything, including level-less lines.
@property (atomic) NSInteger level;                    // default 0 (quiet); raise it from a preference
@property (atomic) unsigned long long maxFileBytes;    // default 6 MB
@property (atomic) NSUInteger tick;                    // shown as tNNN; set it from your display-link tick if you have one
@property (atomic, copy, nullable) NSArray<NSString *> *ignoredImageNames;  // dylib file names left out of third-party=[...]

// YES when the logger is enabled and level >= `level`. Check this before building expensive arguments.
- (BOOL)isLoggingAtLevel:(NSInteger)level;

// Logs whenever the logger is enabled, regardless of level.
- (void)logTag:(NSString *)tag format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

// Logs only when logger.level >= level.
- (void)logLevel:(NSInteger)level tag:(NSString *)tag format:(NSString *)format, ... NS_FORMAT_FUNCTION(3,4);

// Rate limit: returns YES if a line for `key` may be emitted now (at most `perSecond` per second).
// When lines were dropped since the last allowed one, a "(N 'key' line(s) dropped by rate limit)" line is
// written first. Only the first 31 characters of `key` are significant.
- (BOOL)allowTag:(NSString *)tag rateKey:(NSString *)key perSecond:(NSUInteger)perSecond;

// Logs the current call stack, at most `budget` times per `budgetKey` over the logger's lifetime (so one
// repetitive event cannot use up the budget for rarer ones). The first line lists tweak dylibs found on the
// stack ("third-party=[...]") so you can see who made a call; the following lines are the frames.
- (void)logStackWithTag:(NSString *)tag budgetKey:(NSString *)budgetKey budget:(NSUInteger)budget note:(nullable NSString *)note;

// Writes "START build=... pid=... proc=... os=... machine=..." under tag SESSION. More than one START in a
// file means the process restarted.
- (void)logSessionStartWithBuildTag:(NSString *)buildTag;

// State-change logging: stores `signature` on `object` and returns YES only when it differs from the last one
// stored for this logger. Compare a compact signature per view and log only when this returns YES.
- (BOOL)noteSignature:(NSString *)signature forObject:(id)object;

// Blocks until everything queued so far is written. Never call it from inside a logging path.
- (void)flush;

@end

// Level-checked logging. Arguments are not evaluated when the level is filtered out.
// NOTE: macro parameters end in "_" so they can never match a selector keyword in the body (a parameter named
// "tag" would also replace the "tag:" part of -logLevel:tag:format:).
#define OITLOGGER_LOG(logger_, level_, tag_, ...) \
    do { \
        OITLogger *_oitLogger = (logger_); \
        if ([_oitLogger isLoggingAtLevel:(level_)]) { \
            [_oitLogger logLevel:(level_) tag:(tag_) format:__VA_ARGS__]; \
        } \
    } while (0)

// Level-checked and rate-limited. Arguments are not evaluated when the line is filtered or rate limited.
#define OITLOGGER_LOG_RATED(logger_, level_, tag_, key_, perSecond_, ...) \
    do { \
        OITLogger *_oitLogger = (logger_); \
        if ([_oitLogger isLoggingAtLevel:(level_)] && \
            [_oitLogger allowTag:(tag_) rateKey:(key_) perSecond:(perSecond_)]) { \
            [_oitLogger logLevel:(level_) tag:(tag_) format:__VA_ARGS__]; \
        } \
    } while (0)

NS_ASSUME_NONNULL_END
