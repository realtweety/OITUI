#import <Foundation/Foundation.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                            CFSTR("com.wilburt.oitinspector/Dump"),
                                            NULL, NULL, YES);
        NSLog(@"[OITDumpTrigger] Dump notification posted.");
    }
    return 0;
}
