#pragma once
#import <Foundation/Foundation.h>

typedef void (^OITDarwinNotificationHandler)(void);

FOUNDATION_EXPORT void OITObserveDarwinNotification(NSString *name, OITDarwinNotificationHandler handler);
FOUNDATION_EXPORT void OITPostDarwinNotification(NSString *name);
FOUNDATION_EXPORT void OITRequestRespring(void);
