#import "OITIDownloadsListController.h"
#import <OITCore/OITCore.h>

static NSString * const kOITITestDownloadStartNotification = @"com.wilburt.oiti/TestDownloadStart";
static NSString * const kOITITestDownloadStopNotification = @"com.wilburt.oiti/TestDownloadStop";

@implementation OITIDownloadsListController

- (NSString *)oiti_plistName {
    return @"Downloads";
}

// SpringBoard listens for these (OITI/Tweak.xm). The test download only shows while Download Progress is on.
- (void)startTestDownload {
    OITPostDarwinNotification(kOITITestDownloadStartNotification);
}

- (void)stopTestDownload {
    OITPostDarwinNotification(kOITITestDownloadStopNotification);
}

@end
