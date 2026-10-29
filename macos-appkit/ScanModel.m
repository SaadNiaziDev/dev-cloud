#import "ScanModel.h"
#import <CoreServices/CoreServices.h>
#import <ServiceManagement/ServiceManagement.h>
#import <UserNotifications/UserNotifications.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

NSNotificationName const ScanModelDidChangeNotification = @"ScanModelDidChangeNotification";

static NSString * const MonitoringKey = @"continuity.monitoring";
static NSString * const NotificationsKey = @"continuity.notifications";
static NSString * const IncludePathsKey = @"continuity.includePaths";
static NSString * const InspectMCPKey = @"continuity.inspectMCP";
static NSString * const InspectEditorKey = @"continuity.inspectEditorSettings";
static NSString * const InspectPathToolsKey = @"continuity.inspectPathTools";
static NSString * const ApprovedRootsKey = @"continuity.approvedRoots";
static const NSUInteger MaxHistoryBytes = 16 * 1024 * 1024;
static const NSUInteger MaxScanOutputBytes = 64 * 1024 * 1024;

@interface ScanModel ()
@property(nonatomic, copy, readwrite) NSDictionary *report;
@property(nonatomic, copy, readwrite) NSDictionary *localMetadata;
@property(nonatomic, copy, readwrite) NSDictionary *changes;
@property(nonatomic, copy, readwrite) NSString *phase;
@property(nonatomic, readwrite) double progress;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *completedPhases;
@property(nonatomic, copy, readwrite) NSString *errorMessage;
@property(nonatomic, copy, readwrite) NSString *settingsMessage;
@property(nonatomic, copy, readwrite) NSDate *lastScanDate;
@property(nonatomic, copy, readwrite) NSArray<NSString *> *approvedRoots;
@property(nonatomic, readwrite) BOOL scanning;
@property(nonatomic, readwrite) BOOL showingSavedScan;
@property(nonatomic, readwrite) BOOL monitoring;
@property(nonatomic, readwrite) BOOL launchAtLogin;
@property(nonatomic, readwrite) BOOL notificationsEnabled;
@property(nonatomic, strong) NSTask *activeTask;
@property(nonatomic, strong) NSPipe *outputPipe;
@property(nonatomic, strong) NSPipe *progressPipe;
@property(nonatomic, strong) NSMutableData *outputData;
@property(nonatomic, strong) NSMutableData *progressData;
@property(nonatomic) FSEventStreamRef eventStream;
@property(nonatomic, strong) NSTimer *reconcileTimer;
@property(nonatomic) NSUInteger debounceToken;
@property(nonatomic) BOOL rescanRequested;
@property(nonatomic) BOOL monitorRescanRequested;
@property(nonatomic) BOOL outputTooLarge;
- (void)scheduleFileEventScan;
@end

// Reports come from the helper and from files on disk, so every collection is
// type-checked before the UI indexes into it.
static NSArray<NSDictionary *> *DictionaryArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    return [value filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, id bindings) {
        return [item isKindOfClass:NSDictionary.class];
    }]];
}

static NSDictionary *ValidReport(id value) {
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"resources"] isKindOfClass:NSArray.class]) return nil;
    NSMutableDictionary *report = [value mutableCopy];
    report[@"resources"] = DictionaryArray(value[@"resources"]);
    NSArray *warnings = [value[@"warnings"] isKindOfClass:NSArray.class] ? value[@"warnings"] : @[];
    report[@"warnings"] = [warnings filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self isKindOfClass: %@", NSString.class]];
    if (![value[@"host"] isKindOfClass:NSDictionary.class]) report[@"host"] = @{};
    if (![value[@"observed_at_unix_seconds"] isKindOfClass:NSNumber.class]) report[@"observed_at_unix_seconds"] = @0;
    return report;
}

static NSDictionary *ValidChanges(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"added", @"removed", @"updated"]) changes[key] = DictionaryArray(value[key]);
    if ([value[@"previous_observed_at_unix_seconds"] isKindOfClass:NSNumber.class]) changes[@"previous_observed_at_unix_seconds"] = value[@"previous_observed_at_unix_seconds"];
    return [changes[@"added"] count] + [changes[@"removed"] count] + [changes[@"updated"] count] ? changes : nil;
}

static NSDictionary *ValidLocal(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *local = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"mcp_servers", @"editor_settings", @"unknown_path_tools"]) local[key] = DictionaryArray(value[key]);
    NSMutableArray *workspaces = [NSMutableArray array];
    for (NSDictionary *workspace in DictionaryArray(value[@"workspaces"])) {
        NSMutableDictionary *entry = [workspace mutableCopy];
        if (![entry[@"linked_worktree_count"] isKindOfClass:NSNumber.class]) entry[@"linked_worktree_count"] = @0;
        [workspaces addObject:entry];
    }
    local[@"workspaces"] = workspaces;
    return local;
}

NSData *ReadHistoryFile(NSURL *url) {
    int fd = open(url.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return nil;
    struct stat metadata;
    if (fstat(fd, &metadata) != 0 || !S_ISREG(metadata.st_mode) || metadata.st_size < 0 || (unsigned long long)metadata.st_size > MaxHistoryBytes) {
        close(fd);
        return nil;
    }
    NSFileHandle *file = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
    NSData *data = [file readDataOfLength:MaxHistoryBytes + 1];
    [file closeFile];
    return data.length <= MaxHistoryBytes ? data : nil;
}

static void ContinuityFileEvent(ConstFSEventStreamRef stream, void *info, size_t count, void *paths, const FSEventStreamEventFlags flags[], const FSEventStreamEventId identifiers[]) {
    ScanModel *model = (__bridge ScanModel *)info;
    dispatch_async(dispatch_get_main_queue(), ^{ [model scheduleFileEventScan]; });
}

@implementation ScanModel

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _monitoring = [defaults boolForKey:MonitoringKey];
        _notificationsEnabled = [defaults boolForKey:NotificationsKey];
        _includePaths = [defaults boolForKey:IncludePathsKey];
        _inspectMCP = [defaults boolForKey:InspectMCPKey];
        _inspectEditorSettings = [defaults boolForKey:InspectEditorKey];
        _inspectPathTools = [defaults boolForKey:InspectPathToolsKey];
        _approvedRoots = [self existingDirectories:[defaults stringArrayForKey:ApprovedRootsKey] ?: @[]];
        _phase = @"Ready to scan";
        _completedPhases = @[];
        _launchAtLogin = SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
        [self loadSavedScan];
        if (_monitoring) [self startMonitoring];
    }
    return self;
}

- (NSArray<NSString *> *)existingDirectories:(NSArray<NSString *> *)paths {
    NSMutableArray *existing = [NSMutableArray array];
    for (NSString *path in paths) {
        BOOL directory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && directory) [existing addObject:path];
    }
    return existing;
}

- (NSURL *)historyDirectory {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [[support URLByAppendingPathComponent:@"Continuity"] URLByAppendingPathComponent:@"History"];
}

- (void)loadSavedScan {
    NSData *data = ReadHistoryFile([self.historyDirectory URLByAppendingPathComponent:@"latest.json"]);
    NSDictionary *report = data ? ValidReport([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]) : nil;
    if (!report) return;
    _report = report;
    _showingSavedScan = YES;
    NSData *changeData = ReadHistoryFile([self.historyDirectory URLByAppendingPathComponent:@"changes.json"]);
    _changes = changeData ? ValidChanges([NSJSONSerialization JSONObjectWithData:changeData options:0 error:nil]) : nil;
    _lastScanDate = [NSDate dateWithTimeIntervalSince1970:[report[@"observed_at_unix_seconds"] doubleValue]];
}

#pragma mark - Options

- (void)setIncludePaths:(BOOL)value { [self setOption:&_includePaths value:value key:IncludePathsKey]; }
- (void)setInspectMCP:(BOOL)value { [self setOption:&_inspectMCP value:value key:InspectMCPKey]; }
- (void)setInspectEditorSettings:(BOOL)value { [self setOption:&_inspectEditorSettings value:value key:InspectEditorKey]; }
- (void)setInspectPathTools:(BOOL)value { [self setOption:&_inspectPathTools value:value key:InspectPathToolsKey]; }

- (void)setOption:(BOOL *)storage value:(BOOL)value key:(NSString *)key {
    if (*storage == value) return;
    *storage = value;
    [NSUserDefaults.standardUserDefaults setBool:value forKey:key];
    [self requestScan];
}

#pragma mark - Scanning

- (void)scan { [self beginScan:NO]; }
- (void)refreshQuietly { [self beginScan:YES]; }

// Option changes during a scan would otherwise be lost; run once more afterwards.
- (void)requestScan {
    if (self.scanning) self.rescanRequested = YES;
    else [self scan];
}

// A manual scan clears the view and shows each phase; a monitoring scan runs
// quietly and replaces results only when it finishes.
- (void)beginScan:(BOOL)fromMonitor {
    if (self.scanning) return;
    if (!fromMonitor) {
        self.report = nil;
        self.localMetadata = nil;
    }
    self.errorMessage = nil;
    self.phase = @"Preparing local scan";
    self.completedPhases = @[];
    self.progress = 0;
    self.scanning = YES;
    self.outputTooLarge = NO;
    self.outputData = [NSMutableData data];
    self.progressData = [NSMutableData data];
    [self notify];

    NSTask *task = [NSTask new];
    task.executableURL = [self scannerURL];
    task.arguments = [self scannerArguments];
    NSPipe *output = [NSPipe pipe];
    NSPipe *progress = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = progress;
    self.activeTask = task;
    self.outputPipe = output;
    self.progressPipe = progress;

    __weak ScanModel *weakSelf = self;
    __weak NSTask *weakTask = task;
    output.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *chunk = handle.availableData;
        if (chunk.length == 0) { handle.readabilityHandler = nil; return; }
        ScanModel *strongSelf = weakSelf;
        BOOL tooLarge = NO;
        @synchronized (strongSelf.outputData) {
            tooLarge = chunk.length > MaxScanOutputBytes - strongSelf.outputData.length;
            if (!tooLarge) [strongSelf.outputData appendData:chunk];
        }
        if (tooLarge) dispatch_async(dispatch_get_main_queue(), ^{
            ScanModel *model = weakSelf;
            NSTask *running = weakTask;
            if (model.activeTask == running && running.isRunning && !model.outputTooLarge) {
                model.outputTooLarge = YES;
                [running terminate];
            }
        });
    };
    progress.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *chunk = handle.availableData;
        if (chunk.length == 0) { handle.readabilityHandler = nil; return; }
        ScanModel *strongSelf = weakSelf;
        @synchronized (strongSelf.progressData) {
            [strongSelf.progressData appendData:chunk];
            [strongSelf consumeProgressLines];
        }
    };
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf finishTask:finished fromMonitor:fromMonitor];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.activeTask = nil;
        self.scanning = NO;
        self.errorMessage = @"The scanner inside Continuity couldn’t start. Reinstall the app, then try again.";
        self.phase = @"Scan failed";
        [self notify];
    }
}

// Release builds run only the helper sealed inside the signed bundle; overrides
// exist for test builds, so the environment or launch folder cannot swap it.
- (NSURL *)scannerURL {
#ifdef CONTINUITY_TESTING
    NSString *override = NSProcessInfo.processInfo.environment[@"CONTINUITY_AGENT_PATH"];
    if (override.length) return [NSURL fileURLWithPath:override];
#endif
    return [[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Contents/Helpers"] URLByAppendingPathComponent:@"continuity-agent"];
}

- (NSArray<NSString *> *)scannerArguments {
    NSMutableArray *arguments = [@[@"scan", @"--format", @"json", @"--progress", @"--local", @"--history-dir", self.historyDirectory.path] mutableCopy];
    if (self.includePaths) [arguments addObject:@"--include-paths"];
    if (self.inspectMCP) [arguments addObject:@"--inspect-mcp"];
    if (self.inspectEditorSettings) [arguments addObject:@"--inspect-editor-settings"];
    if (self.inspectPathTools) [arguments addObject:@"--inspect-path-tools"];
    for (NSString *root in self.approvedRoots) [arguments addObjectsFromArray:@[@"--approved-root", root]];
    return arguments;
}

- (void)consumeProgressLines {
    const uint8_t newline = '\n';
    while (true) {
        const void *found = memchr(self.progressData.bytes, newline, self.progressData.length);
        if (!found) break;
        NSUInteger length = (const uint8_t *)found - (const uint8_t *)self.progressData.bytes;
        NSData *lineData = [self.progressData subdataWithRange:NSMakeRange(0, length)];
        [self.progressData replaceBytesInRange:NSMakeRange(0, length + 1) withBytes:NULL length:0];
        NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{ [self applyProgressLine:line]; });
    }
}

- (void)applyProgressLine:(NSString *)line {
    if (![line hasPrefix:@"CONTINUITY_PROGRESS|"]) return;
    NSArray<NSString *> *fields = [line componentsSeparatedByString:@"|"];
    if (fields.count < 4) return;
    NSInteger completed = fields[1].integerValue;
    NSInteger total = fields[2].integerValue;
    if (self.phase.length && ![self.phase isEqual:fields[3]] && ![self.completedPhases containsObject:self.phase]) {
        self.completedPhases = [self.completedPhases arrayByAddingObject:self.phase];
    }
    self.phase = fields[3];
    if (total > 0) self.progress = (double)completed / (double)total;
    [self notify];
}

- (void)finishTask:(NSTask *)task fromMonitor:(BOOL)fromMonitor {
    NSFileHandle *outputHandle = self.outputPipe.fileHandleForReading;
    NSFileHandle *progressHandle = self.progressPipe.fileHandleForReading;
    outputHandle.readabilityHandler = nil;
    progressHandle.readabilityHandler = nil;
    NSData *outputTail = outputHandle.readDataToEndOfFile;
    @synchronized (self.outputData) {
        if (outputTail.length > MaxScanOutputBytes - self.outputData.length) self.outputTooLarge = YES;
        else [self.outputData appendData:outputTail];
    }

    NSDictionary *envelope = nil;
    if (task.terminationStatus == 0) {
        id value = [NSJSONSerialization JSONObjectWithData:self.outputData options:0 error:nil];
        if ([value isKindOfClass:NSDictionary.class]) envelope = value;
    }
    NSDictionary *report = ValidReport(envelope[@"report"]);
    if (self.outputTooLarge) {
        self.errorMessage = @"The scan returned too much data. Reduce the scan scope and try again.";
        self.phase = @"Scan failed";
    } else if (report) {
        self.report = report;
        self.localMetadata = ValidLocal(envelope[@"local"]);
        NSDictionary *changes = ValidChanges(envelope[@"changes"]);
        BOOL changed = changes != nil;
        // The last detected changes stay visible until newer ones replace them.
        if (changed) self.changes = changes;
        self.showingSavedScan = NO;
        self.lastScanDate = [NSDate dateWithTimeIntervalSince1970:[report[@"observed_at_unix_seconds"] doubleValue]];
        if (self.phase.length && ![self.completedPhases containsObject:self.phase]) self.completedPhases = [self.completedPhases arrayByAddingObject:self.phase];
        self.phase = @"Scan complete";
        self.progress = 1;
        if ([envelope[@"history_error"] boolValue]) self.errorMessage = @"Scan history could not be saved. Review scan notes and try again.";
        if (fromMonitor && changed && self.notificationsEnabled) [self sendNotification];
    } else {
        self.errorMessage = task.terminationStatus == 0
            ? @"The scanner returned an unreadable report."
            : @"The scan could not be completed.";
        self.phase = @"Scan failed";
    }
    self.scanning = NO;
    self.activeTask = nil;
    self.outputPipe = nil;
    self.progressPipe = nil;
    [self notify];
    if (self.rescanRequested) {
        self.rescanRequested = NO;
        self.monitorRescanRequested = NO;
        [self scan];
    } else if (self.monitorRescanRequested && self.monitoring) {
        self.monitorRescanRequested = NO;
        [self beginScan:YES];
    }
}

- (NSString *)changeSummary {
    if (!self.changes) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"added", @"updated", @"removed"]) {
        NSUInteger count = [self.changes[key] count];
        if (count) [parts addObject:[NSString stringWithFormat:@"%lu %@", (unsigned long)count, key]];
    }
    return parts.count ? [parts componentsJoinedByString:@" · "] : nil;
}

- (BOOL)exportReportToURL:(NSURL *)url workspaces:(BOOL)workspaces configurations:(BOOL)configurations error:(NSError **)error {
    if (!self.report) return NO;
    id object = self.report;
    if (workspaces || configurations) {
        NSMutableDictionary *local = [NSMutableDictionary dictionary];
        if (workspaces) local[@"workspaces"] = self.localMetadata[@"workspaces"] ?: @[];
        if (configurations) {
            for (NSString *key in @[@"mcp_servers", @"editor_settings", @"unknown_path_tools"]) local[key] = self.localMetadata[key] ?: @[];
        }
        object = @{@"report": self.report, @"local": local};
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    return data && [data writeToURL:url options:NSDataWritingAtomic error:error];
}

#pragma mark - Monitoring

- (void)setMonitoringEnabled:(BOOL)enabled {
    if (_monitoring == enabled) return;
    self.monitoring = enabled;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:MonitoringKey];
    if (enabled) [self startMonitoring]; else [self stopMonitoring];
    [self notify];
    if (enabled) [self requestMonitoringScan];
}

- (void)startMonitoring {
    [self refreshEventStream];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(workspaceDidWake:) name:NSWorkspaceDidWakeNotification object:nil];
    if (!self.reconcileTimer) {
        __weak ScanModel *weakSelf = self;
        self.reconcileTimer = [NSTimer scheduledTimerWithTimeInterval:300 repeats:YES block:^(NSTimer *timer) {
            ScanModel *strongSelf = weakSelf;
            if (strongSelf.monitoring) {
                [strongSelf refreshEventStream];
                [strongSelf requestMonitoringScan];
            }
        }];
        self.reconcileTimer.tolerance = 30;
    }
}

- (void)stopMonitoring {
    [self.reconcileTimer invalidate];
    self.reconcileTimer = nil;
    self.monitorRescanRequested = NO;
    self.debounceToken++;
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self name:NSWorkspaceDidWakeNotification object:nil];
    [self releaseEventStream];
}

- (void)workspaceDidWake:(NSNotification *)notification {
    if (!self.monitoring) return;
    [self refreshEventStream];
    [self requestMonitoringScan];
}

- (void)requestMonitoringScan {
    if (!self.monitoring) return;
    if (self.scanning) self.monitorRescanRequested = YES;
    else [self beginScan:YES];
}

- (void)releaseEventStream {
    if (!self.eventStream) return;
    FSEventStreamStop(self.eventStream);
    FSEventStreamInvalidate(self.eventStream);
    FSEventStreamRelease(self.eventStream);
    self.eventStream = NULL;
}

- (NSArray<NSString *> *)watchLocations {
    NSString *home = NSFileManager.defaultManager.homeDirectoryForCurrentUser.path;
    NSMutableArray *paths = [@[@"/opt/homebrew/Cellar", @"/opt/homebrew/Caskroom", @"/opt/homebrew/opt", @"/usr/local/Cellar", @"/usr/local/Caskroom", @"/usr/local/opt", @"/Applications"] mutableCopy];
    for (NSString *relative in @[@"Applications", @".nvm", @".pyenv/versions", @".volta/tools", @".local/share/mise", @".asdf/installs", @".sdkman/candidates", @".rustup/toolchains", @".cargo/bin", @".bun/bin", @"go/bin", @".vscode/extensions", @".cursor/extensions", @"Library/Application Support/Code/User", @"Library/Application Support/Cursor/User"]) {
        [paths addObject:[home stringByAppendingPathComponent:relative]];
    }
    [paths addObjectsFromArray:self.approvedRoots];
    NSString *pathEnvironment = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"";
    [paths addObjectsFromArray:[pathEnvironment componentsSeparatedByString:@":"]];
    NSMutableOrderedSet *existing = [NSMutableOrderedSet orderedSet];
    for (NSString *path in paths) {
        BOOL isDirectory = NO;
        if ([path hasPrefix:@"/"] && [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) [existing addObject:path];
    }
    return existing.array;
}

- (void)refreshEventStream {
    if (!self.monitoring) return;
    [self releaseEventStream];
    NSArray *locations = [self watchLocations];
    FSEventStreamContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    FSEventStreamCreateFlags flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer;
    self.eventStream = FSEventStreamCreate(NULL, ContinuityFileEvent, &context, (__bridge CFArrayRef)locations, kFSEventStreamEventIdSinceNow, 1.0, flags);
    if (self.eventStream) {
        FSEventStreamSetDispatchQueue(self.eventStream, dispatch_get_main_queue());
        if (FSEventStreamStart(self.eventStream)) return;
        [self releaseEventStream];
    }
    self.settingsMessage = @"Live monitoring is unavailable. Periodic scans are still enabled.";
    [self notify];
}

- (void)scheduleFileEventScan {
    if (!self.monitoring) return;
    NSUInteger token = ++self.debounceToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.monitoring && token == self.debounceToken) [self requestMonitoringScan];
    });
}

#pragma mark - System integration

- (void)setLaunchAtLoginEnabled:(BOOL)enabled {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL success = enabled ? [service registerAndReturnError:&error] : [service unregisterAndReturnError:&error];
    self.launchAtLogin = success ? enabled : service.status == SMAppServiceStatusEnabled;
    self.settingsMessage = success
        ? (enabled ? @"Continuity will open when you sign in." : @"Continuity will no longer open at login.")
        : [NSString stringWithFormat:@"Login item could not be changed: %@", error.localizedDescription ?: @"System approval is required."];
    [self notify];
}

- (void)setNotificationsEnabled:(BOOL)enabled {
    if (!enabled) {
        _notificationsEnabled = NO;
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:NotificationsKey];
        [self notify];
        return;
    }
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_notificationsEnabled = granted;
            [NSUserDefaults.standardUserDefaults setBool:granted forKey:NotificationsKey];
            self.settingsMessage = granted ? @"Change notifications are enabled." : @"Allow notifications in System Settings to use change alerts.";
            [self notify];
        });
    }];
}

- (void)sendNotification {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = @"Development setup changed";
    content.body = [NSString stringWithFormat:@"%@. Open Continuity to review.", self.changeSummary];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:NSUUID.UUID.UUIDString content:content trigger:nil];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:nil];
}

#pragma mark - Approved folders

- (void)addApprovedRoot:(NSString *)path {
    if ([self.approvedRoots containsObject:path]) return;
    [self updateApprovedRoots:[self.approvedRoots arrayByAddingObject:path]];
}

- (void)removeApprovedRoot:(NSString *)path {
    NSMutableArray *roots = [self.approvedRoots mutableCopy];
    [roots removeObject:path];
    [self updateApprovedRoots:roots];
}

- (void)updateApprovedRoots:(NSArray<NSString *> *)roots {
    self.approvedRoots = roots;
    [NSUserDefaults.standardUserDefaults setObject:roots forKey:ApprovedRootsKey];
    [self refreshEventStream];
    [self requestScan];
}

- (void)stop {
    [self stopMonitoring];
    [self.activeTask terminate];
}

- (void)notify {
    [NSNotificationCenter.defaultCenter postNotificationName:ScanModelDidChangeNotification object:self];
}

- (void)dealloc {
    [self stopMonitoring];
}

@end
