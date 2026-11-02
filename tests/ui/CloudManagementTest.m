#import <AppKit/AppKit.h>
#import "CloudAccount.h"

@interface CloudAccount (ManagementFixture)
- (BOOL)storeSession;
- (NSString *)automaticOptOutKey;
- (NSURL *)uploadQueueDirectory;
- (void)forgetSession:(NSString *)message;
- (void)send:(NSString *)method path:(NSString *)path json:(id)json body:(NSData *)body token:(NSString *)token
    completion:(void (^)(NSInteger, id, NSData *, NSHTTPURLResponse *))completion;
@end

@interface ManagementFixture : CloudAccount
@property(nonatomic) NSInteger deletionStatus;
@property(nonatomic) BOOL malformedAck;
@property(nonatomic) BOOL failSave;
@property(nonatomic, strong) NSDictionary *savedSession;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *requests;
@property(nonatomic, strong) NSArray<NSDictionary *> *connected;
@property(nonatomic, strong) NSURL *root;
@end

@implementation ManagementFixture
- (instancetype)init {
    self = [super initWithBaseURL:CloudValidatedURL(@"https://api.example.invalid") keychainService:[@"dev.devcloud.management.test." stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (self) {
        _deletionStatus = 202;
        _requests = [NSMutableArray array];
        _root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        _connected = @[
            @{@"id": @"6117ab34-e18d-4caa-8bba-d3160307914f", @"name": @"This fixture Mac"},
            @{@"id": @"5df50ac3-bfaf-4407-9826-9ab5b77ddd46", @"name": @"Lost fixture Mac"},
        ];
    }
    return self;
}
- (BOOL)storeSession { return !self.failSave; }
- (NSDictionary *)storedSession { return self.savedSession; }
- (NSURL *)uploadQueueDirectory { return _root; }
- (void)send:(NSString *)method path:(NSString *)path json:(id)json body:(NSData *)body token:(NSString *)token
    completion:(void (^)(NSInteger, id, NSData *, NSHTTPURLResponse *))completion {
    [_requests addObject:@{@"method": method, @"path": path, @"json": json ?: NSNull.null}];
    if ([method isEqual:@"POST"] && [path isEqual:@"/v1/devices"]) completion(201, @{@"device": _connected.firstObject}, nil, nil);
    else if ([path isEqual:@"/api/auth/get-session"]) completion(200, @{@"user": @{@"email": @"fixture@example.invalid"}}, nil, nil);
    else if ([method isEqual:@"GET"] && [path isEqual:@"/v1/devices"]) completion(200, @{@"devices": _connected}, nil, nil);
    else if ([path isEqual:@"/v1/snapshots"]) completion(200, @{@"snapshots": @[]}, nil, nil);
    else if ([path hasPrefix:@"/v1/devices/"]) {
        NSString *identifier = path.lastPathComponent;
        _connected = [_connected filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) { return ![item[@"id"] isEqual:identifier]; }]];
        completion(204, nil, nil, nil);
    } else if ([path isEqual:@"/v1/account"]) {
        id payload = _deletionStatus == 403 ? @{@"error": @"recent_auth_required"} : @{@"status": _malformedAck ? @"unexpected" : @"deletion_queued"};
        completion(_deletionStatus, payload, nil, nil);
    } else completion(0, nil, nil, nil);
}
- (NSUInteger)deletions {
    NSUInteger count = 0;
    for (NSDictionary *request in _requests) if ([request[@"path"] isEqual:@"/v1/account"]) count++;
    return count;
}
- (void)clean {
    [self forgetSession:nil];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:self.automaticOptOutKey];
    [NSFileManager.defaultManager removeItemAtURL:_root error:nil];
}
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL %s\n", message.UTF8String); exit(1); }
}
static void Pump(void) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:.1];
    while (until.timeIntervalSinceNow > 0) { @autoreleasepool { [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:until]; } }
}

int main(void) {
    @autoreleasepool {
        CloudAccount *incomplete = [[CloudAccount alloc] initWithBaseURL:CloudValidatedURL(@"https://api.example.invalid") keychainService:@"dev.devcloud.missing-session.test"];
        [incomplete setValue:@(CloudSignedIn) forKey:@"state"];
        @try {
            [incomplete setAutomaticBackupsEnabled:YES];
            Check(!incomplete.automaticBackupsEnabled && incomplete.errorMessage.length, @"Missing session fails closed when enabling automatic backup");
        } @catch (NSException *exception) {
            Check(NO, @"Missing session must not crash automatic-backup settings");
        }
        ManagementFixture *account = [ManagementFixture new];
        [account signInWithToken:@"fixture-session"];
        Check(account.state == CloudSignedIn && account.devices.count == 2, @"Connected Macs load from the account");
        Check([account.devices[0][@"this_mac"] boolValue], @"The current Mac is identified");
        account.failSave = YES;
        [account setAutomaticBackupsEnabled:YES];
        Check(!account.automaticBackupsEnabled && [account.errorMessage containsString:@"Keychain"], @"Consent is not enabled when it cannot be saved");
        account.failSave = NO;
        [account setAutomaticBackupsEnabled:YES];
        Check(account.automaticBackupsEnabled, @"Explicit consent can be saved");
        account.failSave = YES;
        [account setAutomaticBackupsEnabled:NO];
        Check(!account.automaticBackupsEnabled, @"Opt-out takes effect even when Keychain saving fails");
        account.savedSession = @{@"token": @"fixture-session", @"device_id": account.deviceIdentifier,
            @"email": account.email, @"automatic_backups": @YES};
        [account forgetSession:nil];
        [account restore];
        Check(account.state == CloudSignedIn && !account.automaticBackupsEnabled, @"An older saved consent cannot override a local opt-out after restart");
        account.failSave = NO;
        __block NSError *failure = nil;
        NSUInteger requests = account.requests.count;
        [account revokeDevice:NSUUID.UUID.UUIDString completion:^(NSError *error) { failure = error; }];
        Check(failure && account.requests.count == requests, @"Unknown devices are rejected without a request");
        [account revokeDevice:account.devices[1][@"identifier"] completion:^(NSError *error) { failure = error; }];
        Check(!failure && account.devices.count == 1 && account.state == CloudSignedIn, @"Removing a lost Mac keeps this Mac signed in");

        NSDictionary *report = @{@"schema_version": @1, @"observed_at_unix_seconds": @1,
            @"host": @{@"platform": @"macos", @"architecture": @"aarch64", @"os_version": @"14"}, @"resources": @[]};
        [account backUpReport:report completion:^(NSUInteger count, NSError *error) { failure = error; }];
        Pump();
        Check(!failure && account.pendingBackups == 1 && !account.busy, @"An offline intent is staged");
        [account deleteAccountWithConfirmation:@"yes" completion:^(NSError *error) { failure = error; }];
        Check(failure && account.deletions == 0, @"Typed confirmation is enforced before making a request");
        account.deletionStatus = 403;
        [account deleteAccountWithConfirmation:@"delete my account" completion:^(NSError *error) { failure = error; }];
        Check(failure && [failure.localizedDescription containsString:@"Sign out and sign in again"], @"Recent sign-in failure explains recovery");
        Check(account.state == CloudSignedIn && account.pendingBackups == 1 && !account.busy, @"Rejected deletion preserves the account and queue");
        account.deletionStatus = 0;
        [account deleteAccountWithConfirmation:@"delete my account" completion:^(NSError *error) { failure = error; }];
        Check(failure && account.state == CloudSignedIn && account.pendingBackups == 1, @"An uncertain deletion does not claim success");
        account.deletionStatus = 202; account.malformedAck = YES;
        [account deleteAccountWithConfirmation:@"delete my account" completion:^(NSError *error) { failure = error; }];
        Check(failure && account.state == CloudSignedIn, @"An unexpected acknowledgement fails closed");
        account.malformedAck = NO;
        [account deleteAccountWithConfirmation:@"delete my account" completion:^(NSError *error) { failure = error; }];
        Check(!failure && account.state == CloudSignedOut && account.pendingBackups == 0 && account.devices.count == 0, @"Confirmed deletion clears local credentials, queue and account views");
        NSDictionary *last = account.requests.lastObject;
        Check([last[@"method"] isEqual:@"DELETE"] && [last[@"json"] isEqual:@{@"confirmation": @"delete my account"}], @"Only the confirmation is sent, with no caller-selected account ID");
        NSUInteger deletions = account.deletions;
        Pump();
        Check(account.deletions == deletions, @"Deletion never retries automatically");
        [account clean];

        ManagementFixture *signedOut = [ManagementFixture new];
        [signedOut signInWithToken:@"another-fixture-session"];
        [signedOut signOut];
        Check(signedOut.state == CloudSignedOut && signedOut.devices.count == 0, @"Current-device revocation still signs out");
        [signedOut clean];
        printf("Cloud account management checks passed\n");
    }
    return 0;
}
