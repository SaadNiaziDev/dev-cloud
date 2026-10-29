#import <Cocoa/Cocoa.h>
#import "ScanModel.h"

@interface ScanModel (MonitoringTest)
- (void)scheduleFileEventScan;
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"continuity.monitoring"];
        ScanModel *model = [ScanModel new];
        NSString *logPath = NSProcessInfo.processInfo.environment[@"CONTINUITY_UI_SCAN_LOG"];
        __block id observer = nil;
        observer = [NSNotificationCenter.defaultCenter addObserverForName:ScanModelDidChangeNotification object:model queue:nil usingBlock:^(NSNotification *note) {
            NSString *log = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
            NSUInteger count = [[log componentsSeparatedByString:@"scan\n"] count] - 1;
            if (count >= 2 && !model.scanning) {
                [NSNotificationCenter.defaultCenter removeObserver:observer];
                [model setMonitoringEnabled:NO];
                exit(count == 2 ? 0 : 1);
            }
        }];
        [model setMonitoringEnabled:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{ [model scheduleFileEventScan]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(1); });
        [NSApp run];
    }
    return 1;
}
