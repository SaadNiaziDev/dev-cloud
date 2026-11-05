#import <AppKit/AppKit.h>
#import "CloudAccount.h"
#import "CloudInventory.h"
#import "CloudAutoBackup.h"
#import "RecoveryPlan.h"

@interface CloudAccount (LiveManagementFixture)
- (BOOL)storeSession;
- (NSURL *)uploadQueueDirectory;
- (void)forgetSession:(NSString *)message;
- (void)send:(NSString *)method path:(NSString *)path json:(id)json body:(NSData *)body token:(NSString *)token completion:(void (^)(NSInteger, id, NSData *, NSHTTPURLResponse *))completion;
@end

@interface LiveManagementAccount : CloudAccount
@property(nonatomic, strong) NSURL *root;
@end
@implementation LiveManagementAccount
- (BOOL)storeSession { return YES; }
- (NSURL *)uploadQueueDirectory {
    if (!_root) _root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    return _root;
}
- (void)clean {
    [self forgetSession:nil];
    if (_root) [NSFileManager.defaultManager removeItemAtURL:_root error:nil];
}
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL %s\n", message.UTF8String); exit(1); }
}
static BOOL Wait(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done() && limit.timeIntervalSinceNow > 0) { @autoreleasepool { [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.02]]; } }
    return done();
}
static LiveManagementAccount *Account(NSURL *base, NSString *token) {
    Check(token.length > 0, @"A fixture session is required");
    LiveManagementAccount *account = [[LiveManagementAccount alloc] initWithBaseURL:base keychainService:[@"dev.devcloud.live-management.test." stringByAppendingString:NSUUID.UUID.UUIDString]];
    [account signInWithToken:token];
    Check(Wait(^BOOL { return account.state == CloudSignedIn && !account.busy; }), @"Fixture Mac enrolls");
    return account;
}

int main(void) {
    @autoreleasepool {
        NSDictionary *env = NSProcessInfo.processInfo.environment;
        NSURL *base = CloudValidatedURL(env[@"DEVCLOUD_TEST_MANAGEMENT_API"]);
        Check([base.scheme isEqual:@"http"] && [base.host isEqual:@"127.0.0.1"], @"Destructive fixture checks require a loopback server");
        LiveManagementAccount *first = Account(base, env[@"DEVCLOUD_TEST_MANAGEMENT_FIRST"]);
        LiveManagementAccount *second = Account(base, env[@"DEVCLOUD_TEST_MANAGEMENT_SECOND"]);
        LiveManagementAccount *other = Account(base, env[@"DEVCLOUD_TEST_MANAGEMENT_OTHER"]);
        [first refreshBackups];
        Check(Wait(^BOOL { return first.devices.count == 2; }), @"Both Macs appear in account management");
        NSDictionary *report = @{@"schema_version": @1, @"observed_at_unix_seconds": @1,
            @"host": @{@"platform": @"macos", @"architecture": @"aarch64", @"os_version": @"14"},
            @"resources": @[@{@"canonical_tool_id": @"nodejs", @"version": @"22", @"installation_provider": @"nvm"}]};
        __block BOOL finished = NO;
        __block NSError *failure = nil;
        [second backUpReport:report completion:^(NSUInteger count, NSError *error) { failure = error; finished = YES; }];
        Check(Wait(^BOOL { return finished && !second.busy && second.pendingBackups == 0; }) && !failure, @"The second Mac commits a fixture backup");
        [first refreshBackups];
        Check(Wait(^BOOL { return first.backups.count == 1; }), @"The first Mac sees the second Mac's backup");
        NSString *backup = first.backups.firstObject[@"identifier"];
        LiveManagementAccount *fresh = Account(base, env[@"DEVCLOUD_TEST_MANAGEMENT_FRESH"]);
        Check(Wait(^BOOL { return fresh.backups.count == 1; }), @"A fresh client finds the cloud backup");
        __block NSData *freshDownload = nil;
        finished = NO;
        [fresh downloadBackup:fresh.backups.firstObject[@"identifier"] completion:^(NSData *data, NSError *error) { freshDownload = data; failure = error; finished = YES; }];
        Check(Wait(^BOOL { return finished; }) && !failure && [freshDownload isEqual:CloudInventoryData(report, NULL, NULL)], @"A fresh client selects and verifies the saved inventory");
        NSDictionary *emptyScan = @{@"schema_version": @1, @"observed_at_unix_seconds": @1, @"host": report[@"host"], @"resources": @[]};
        NSArray *freshPlan = RecoveryPlan(freshDownload, emptyScan, &failure);
        Check(freshPlan.count == 1 && [freshPlan.firstObject[@"status"] isEqual:@"Manual setup needed"] && !failure, @"A fresh client can review the verified inventory against its scan");
        [fresh clean];
        NSString *removed = second.deviceIdentifier;
        finished = NO;
        [first revokeDevice:removed completion:^(NSError *error) { failure = error; finished = YES; }];
        Check(Wait(^BOOL { return finished; }) && !failure, @"Removing another Mac succeeds");
        [second refreshBackups];
        Check(Wait(^BOOL { return second.state == CloudSignedOut; }), @"The revoked Mac's session ends");
        __block NSData *download = nil;
        finished = NO;
        [first downloadBackup:backup completion:^(NSData *data, NSError *error) { download = data; failure = error; finished = YES; }];
        Check(Wait(^BOOL { return finished; }) && !failure && [download isEqual:CloudInventoryData(report, NULL, NULL)], @"A revoked Mac's backup remains recoverable on the other Mac");
        [first setAutomaticBackupsEnabled:YES];
        Check(first.automaticBackupsEnabled, @"Automatic backup requires explicit opt-in");
        CloudAutoBackup *automatic = [[CloudAutoBackup alloc] initWithAccount:first];
        NSMutableDictionary *changed = [report mutableCopy];
        changed[@"observed_at_unix_seconds"] = @2;
        changed[@"resources"] = @[@{@"canonical_tool_id": @"nodejs", @"version": @"24", @"installation_provider": @"nvm"}];
        NSString *fingerprint = CloudInventoryFingerprint(CloudInventoryData(changed, NULL, NULL));
        [automatic completedScan:changed];
        Check(Wait(^BOOL { return [first.lastBackedUpFingerprint isEqual:fingerprint] && first.pendingBackups == 0; }), @"A changed scan commits through the real queue and Worker");
        NSMutableDictionary *unchanged = [changed mutableCopy]; unchanged[@"observed_at_unix_seconds"] = @3;
        [automatic completedScan:unchanged];
        Check(first.pendingBackups == 0, @"A timestamp-only scan does not queue again");
        [first refreshBackups];
        Check(Wait(^BOOL { return first.backups.count == 2; }), @"Only one automatic backup was created");
        __block NSInteger denied = 0;
        [other send:@"GET" path:[NSString stringWithFormat:@"/v1/snapshots/%@/body", backup] json:nil body:nil token:env[@"DEVCLOUD_TEST_MANAGEMENT_OTHER"]
            completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) { denied = status; }];
        Check(Wait(^BOOL { return denied != 0; }) && denied == 404, @"An unrelated account cannot retrieve the backup");
        finished = NO;
        [first deleteAccountWithConfirmation:@"delete my account" completion:^(NSError *error) { failure = error; finished = YES; }];
        Check(Wait(^BOOL { return finished; }) && !failure && first.state == CloudSignedOut && !first.automaticBackupsEnabled, @"Fresh confirmation deletes the account and clears this Mac");
        [other refreshBackups];
        Check(Wait(^BOOL { return other.state == CloudSignedIn && other.devices.count == 1; }), @"The unrelated account remains accessible");
        finished = NO;
        [other deleteAccountWithConfirmation:@"delete my account" completion:^(NSError *error) { failure = error; finished = YES; }];
        BOOL cleaned = Wait(^BOOL { return finished; });
        Check(cleaned && !failure, [NSString stringWithFormat:@"The other fixture account is cleaned up: %@", failure.localizedDescription ?: @"timed out"]);
        [first clean]; [second clean]; [other clean];
        printf("Live cloud account management checks passed\n");
    }
    return 0;
}
