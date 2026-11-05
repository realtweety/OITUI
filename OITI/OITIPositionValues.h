// OITIPositionValues.h -- strict parsing and finite/limited values for the typed position settings. FOUNDATION ONLY.
//
// This header is imported by Shared/OITIPreferences.xm, which holds preferencesChanged(), which the %ctor calls while SpringBoard
// is still loading its libraries. Nothing here may touch UIKit (no UIScreen, UIDevice, UIApplication): in v0.3.0 batch 1 a
// [UIScreen mainScreen] call on that path made SpringBoard hang at the Apple logo (a bootloop). The screen-dependent part lives in
// OITIPositionLimits.h, which only hooks, layout code and the Settings bundle import. tools/check_ctor_path.py enforces this.
//
// Parsing is strict on purpose: the old path used -doubleValue, which turned "abc" and "" into 0 (an empty Y field moved the
// Island to y = 0) and accepted "nan", "inf" and "1e30". Those can reach a window frame, and a NaN frame raises inside UIKit
// in SpringBoard.
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdlib.h>

// The most any position value may reach when it is loaded: larger than any iPhone screen in points (the largest is about 932),
// small enough that dividing by the smallest allowed scale stays a sane number. The tighter, per-device limit of one screen is
// applied where the value is used (OITIPositionLimits.h), where UIKit is safe to call.
static const double kOITIPositionCeiling = 1000.0;

// A position typed in Settings: optional leading sign, digits and at most one decimal separator ("." or ","). No exponent,
// no "nan" or "inf", no hex, at most 12 characters. Returns NO for anything else, including empty text.
static inline BOOL OITIParsePositionText(NSString *text, double *valueOut) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length || trimmed.length > 12) return NO;
    NSString *normalized = [trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."];
    NSUInteger digits = 0, dots = 0;
    for (NSUInteger i = 0; i < normalized.length; i++) {
        unichar c = [normalized characterAtIndex:i];
        if (c >= '0' && c <= '9') digits++;
        else if (c == '.') dots++;
        else if ((c == '-' || c == '+') && i == 0) continue;
        else return NO;
    }
    if (digits == 0 || dots > 1) return NO;
    double value = strtod(normalized.UTF8String, NULL);
    if (!isfinite(value)) return NO;
    if (valueOut) *valueOut = value;
    return YES;
}

// Finite and inside +-limit, or the fallback (the setting's default) when the value is not finite. Pure arithmetic.
static inline double OITISanitizedPosition(double value, double fallback, double limit) {
    if (!isfinite(value)) return fallback;
    return MAX(-limit, MIN(limit, value));
}
