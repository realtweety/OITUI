#pragma once
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT void OITLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
FOUNDATION_EXPORT void OITLogSetEnabled(BOOL enabled);
FOUNDATION_EXPORT BOOL OITLogIsEnabled(void);
