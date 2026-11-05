#import "SetupInstaller.h"
#import "SetupFile.h"

static NSError *Failure(NSString *message) {
    return [NSError errorWithDomain:@"DevCloudSetup" code:2 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation SetupInstaller {
    NSArray<NSDictionary *> *_items;
    NSMutableDictionary<NSString *, NSNumber *> *_states;
    NSMutableArray<NSString *> *_lines;
    NSMutableString *_partial;
    BOOL _summarised;
    NSTask *_task;
    NSURL *_directory;
    BOOL _cancelled;
}

+ (NSURL *)homebrew {
#ifdef DEVCLOUD_TESTING
    NSString *override = NSProcessInfo.processInfo.environment[@"DEVCLOUD_BREW_PATH"];
    if (override) return [NSFileManager.defaultManager isExecutableFileAtPath:override] ? [NSURL fileURLWithPath:override] : nil;
#endif
    for (NSString *path in @[@"/opt/homebrew/bin/brew", @"/usr/local/bin/brew"]) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) return [NSURL fileURLWithPath:path];
    }
    return nil;
}

- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items {
    if ((self = [super init])) {
        NSMutableArray *installable = [NSMutableArray array];
        _states = [NSMutableDictionary dictionary];
        for (NSDictionary *item in items) {
            if (!SetupItemInstallable(item)) continue;
            [installable addObject:item];
            _states[item[@"name"]] = @(SetupItemWaiting);
        }
        _items = installable;
        _lines = [NSMutableArray array];
        _partial = [NSMutableString string];
    }
    return self;
}

- (NSUInteger)total { return _items.count; }

- (NSUInteger)completed {
    NSUInteger count = 0;
    for (NSNumber *state in _states.allValues) if (state.integerValue == SetupItemDone || state.integerValue == SetupItemFailed) count++;
    return count;
}

- (SetupItemState)stateFor:(NSString *)name { return (SetupItemState)_states[name].integerValue; }
- (NSString *)log { return [_lines componentsJoinedByString:@"\n"]; }

- (BOOL)start:(NSError **)error {
    if (_task || _finished) { if (error) *error = Failure(@"This install has already run."); return NO; }
    if (!_items.count) { if (error) *error = Failure(@"Nothing is selected to install."); return NO; }
    NSURL *brew = SetupInstaller.homebrew;
    if (!brew) { if (error) *error = Failure(@"Install Homebrew from brew.sh, then try again."); return NO; }

    // A private folder holding only the Brewfile built from the approved items.
    NSFileManager *files = NSFileManager.defaultManager;
    _directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[@"DevCloud-Setup-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSURL *brewfile = [_directory URLByAppendingPathComponent:@"Brewfile"];
    if (![files createDirectoryAtURL:_directory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0700} error:error] ||
        ![SetupInstallFile(_items) writeToURL:brewfile atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        [self cleanUp];
        return NO;
    }

    NSTask *task = [NSTask new];
    task.executableURL = brew;
    task.arguments = @[@"bundle", @"install", @"--no-upgrade", [@"--file=" stringByAppendingString:brewfile.path]];
    NSDictionary *environment = NSProcessInfo.processInfo.environment;
    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:@{
        @"PATH": [NSString stringWithFormat:@"%@:/usr/bin:/bin:/usr/sbin:/sbin", brew.URLByDeletingLastPathComponent.path],
        @"HOME": NSHomeDirectory(), @"LANG": @"en_US.UTF-8", @"TERM": @"dumb",
        @"HOMEBREW_NO_ENV_HINTS": @"1", @"HOMEBREW_NO_COLOR": @"1", @"NONINTERACTIVE": @"1",
    }];
    if (environment[@"USER"]) env[@"USER"] = environment[@"USER"];
    task.environment = env;
    task.currentDirectoryURL = _directory;
    // No input: a step that wants a password fails instead of waiting forever.
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    __weak SetupInstaller *weakSelf = self;
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = handle.availableData;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf receive:data]; });
    };
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            pipe.fileHandleForReading.readabilityHandler = nil;
            [weakSelf receive:[pipe.fileHandleForReading readDataToEndOfFile]];
            [weakSelf finishWithStatus:finished.terminationStatus];
        });
    };
    if (![task launchAndReturnError:error]) { [self cleanUp]; return NO; }
    _task = task;
    _running = YES;
    [self changed];
    return YES;
}

- (void)cancel {
    if (!_running) return;
    _cancelled = YES;
    [_task interrupt];
}

- (void)receive:(NSData *)data {
    if (!data.length) return;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    [_partial appendString:text];
    NSArray *parts = [_partial componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    [_partial setString:parts.lastObject];
    for (NSUInteger i = 0; i + 1 < parts.count; i++) [self line:parts[i]];
    [self changed];
}

// `brew bundle` prints "Using <name>" and "Installing <name>" for every entry first,
// installs them in one batch, then "Installing <name> has failed!" for each failure and a
// summary line. Older versions interleave the same lines with each install.
- (void)line:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!trimmed.length) return;
    [_lines addObject:trimmed];
    if (_lines.count > 2000) [_lines removeObjectsInRange:NSMakeRange(0, 500)];
    _lastLine = trimmed;
    if ([trimmed containsString:@"`brew bundle` complete!"] || [trimmed containsString:@"`brew bundle` failed!"]) { _summarised = YES; return; }
    NSRange failed = [trimmed rangeOfString:@"(Installing|Upgrading) (\\S+) has failed!" options:NSRegularExpressionSearch];
    if (failed.location != NSNotFound) {
        NSArray *words = [[trimmed substringWithRange:failed] componentsSeparatedByString:@" "];
        if (_states[words[1]]) _states[words[1]] = @(SetupItemFailed);
        return;
    }
    NSArray *words = [trimmed componentsSeparatedByString:@" "];
    if (words.count != 2 || !_states[words[1]]) return;
    if ([words[0] isEqual:@"Using"]) _states[words[1]] = @(SetupItemDone);
    else if ([words[0] isEqual:@"Installing"] || [words[0] isEqual:@"Upgrading"]) _states[words[1]] = @(SetupItemInstalling);
}

- (void)finishWithStatus:(int)status {
    if (!_running) return;
    if (_partial.length) { [self line:_partial]; [_partial setString:@""]; }
    // Only Homebrew's own summary confirms entries it didn't report as failed.
    BOOL confirmed = !_cancelled && (status == 0 || _summarised);
    for (NSString *name in _states.allKeys) {
        SetupItemState state = (SetupItemState)_states[name].integerValue;
        if (state == SetupItemWaiting || state == SetupItemInstalling) _states[name] = @(confirmed ? SetupItemDone : SetupItemFailed);
    }
    _running = NO;
    _finished = YES;
    _succeeded = status == 0 && !_cancelled;
    if (_cancelled) _lastLine = @"Install stopped.";
    _task = nil;
    [self cleanUp];
    [self changed];
}

- (void)cleanUp {
    if (_directory) [NSFileManager.defaultManager removeItemAtURL:_directory error:nil];
    _directory = nil;
}

- (void)changed { if (self.onChange) self.onChange(); }

- (void)dealloc {
    [_task terminate];
    [self cleanUp];
}
@end
