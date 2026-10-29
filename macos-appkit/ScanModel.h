#import <Cocoa/Cocoa.h>

extern NSNotificationName const ScanModelDidChangeNotification;

@interface ScanModel : NSObject

@property(nonatomic, copy, readonly) NSDictionary *report;
@property(nonatomic, copy, readonly) NSDictionary *localMetadata;
@property(nonatomic, copy, readonly) NSDictionary *changes;
@property(nonatomic, copy, readonly) NSString *phase;
@property(nonatomic, readonly) double progress;
@property(nonatomic, copy, readonly) NSString *errorMessage;
@property(nonatomic, copy, readonly) NSString *settingsMessage;
@property(nonatomic, copy, readonly) NSDate *lastScanDate;
@property(nonatomic, copy, readonly) NSArray<NSString *> *approvedRoots;
@property(nonatomic, readonly) BOOL scanning;
@property(nonatomic, readonly) BOOL showingSavedScan;
@property(nonatomic, readonly) BOOL monitoring;
@property(nonatomic, readonly) BOOL launchAtLogin;
@property(nonatomic, readonly) BOOL notificationsEnabled;
@property(nonatomic) BOOL includePaths;
@property(nonatomic) BOOL inspectMCP;
@property(nonatomic) BOOL inspectEditorSettings;
@property(nonatomic) BOOL inspectPathTools;

- (void)scan;
- (void)refreshQuietly;
- (void)setMonitoringEnabled:(BOOL)enabled;
- (void)setLaunchAtLoginEnabled:(BOOL)enabled;
- (void)setNotificationsEnabled:(BOOL)enabled;
- (void)addApprovedRoot:(NSString *)path;
- (void)removeApprovedRoot:(NSString *)path;
- (BOOL)exportReportToURL:(NSURL *)url error:(NSError **)error;
- (NSString *)changeSummary;
- (NSURL *)historyDirectory;
- (void)stop;

@end
