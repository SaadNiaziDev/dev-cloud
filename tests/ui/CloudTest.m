#import <AppKit/AppKit.h>
#import "CloudAccount.h"
#import "CloudInventory.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL %s\n", message.UTF8String); exit(1); }
}

static BOOL Wait(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [limit timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return done();
}

static NSDictionary *Report(NSArray *resources) {
    return @{@"schema_version": @1, @"observed_at_unix_seconds": @1793404800, @"warnings": @[@"/Users/private/.zshrc unreadable"],
             @"host": @{@"platform": @"macos", @"architecture": @"aarch64", @"os_version": @"26.6.2", @"home": @"/Users/private"}, @"resources": resources};
}

static void CheckURLs(void) {
    Check([CloudValidatedURL(@"https://api.example.invalid/").absoluteString isEqual:@"https://api.example.invalid"], @"HTTPS origins are accepted and normalised");
    Check(CloudValidatedURL(@"http://127.0.0.1:8787") != nil, @"HTTP is allowed to this Mac");
    for (NSString *bad in @[@"", @"http://api.example.invalid", @"https://user:pass@api.example.invalid", @"https://api.example.invalid/v1",
                             @"https://api.example.invalid?x=1", @"ftp://127.0.0.1", @"http://127.0.0.1.example.invalid"]) {
        Check(CloudValidatedURL(bad) == nil, [@"Rejected origin accepted: " stringByAppendingString:bad]);
    }
}

static void CheckInventory(void) {
    NSArray *resources = @[
        @{@"canonical_tool_id": @"nodejs", @"display_name": @"Node.js", @"version": @"24.0.0", @"installation_provider": @"nvm",
          @"installation_path": @"/Users/private/.nvm/versions/node/v24.0.0/bin/node", @"installation_instance_id": @"local-1", @"evidence": @[@"path"]},
        @{@"canonical_tool_id": @"vscode-extension:ms-python.python", @"version": @"2026.10.0", @"installation_provider": @"vscode"},
        @{@"canonical_tool_id": @"openssl@3", @"version": @"3.6.0", @"installation_provider": @"homebrew_formula"},
        @{@"canonical_tool_id": @"git", @"version": [NSNull null], @"installation_provider": @"macos_system"},
        @{@"canonical_tool_id": @"tool", @"version": @"1.0/../../etc", @"installation_provider": @"windows_registry"},
        @{@"canonical_tool_id": @"/Users/private/bin/secret", @"version": @"1"},
        @{@"canonical_tool_id": @"Uppercase", @"version": @"1"},
        @"not a resource",
    ];
    NSUInteger dropped = 0;
    NSError *error = nil;
    NSData *data = CloudInventoryData(Report(resources), &dropped, &error);
    Check(data != nil && dropped == 3, @"Valid tools map and unsafe IDs are dropped");
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *expected = @"{\"host\":{\"architecture\":\"aarch64\",\"os_version\":\"26.6.2\",\"platform\":\"macos\"},\"observed_at_unix_seconds\":1793404800,"
        "\"resources\":[{\"canonical_tool_id\":\"nodejs\",\"installation_provider\":\"nvm\",\"version\":\"24.0.0\"},"
        "{\"canonical_tool_id\":\"vscode-extension:ms-python.python\",\"installation_provider\":\"vscode\",\"version\":\"2026.10.0\"},"
        "{\"canonical_tool_id\":\"openssl@3\",\"installation_provider\":\"homebrew_formula\",\"version\":\"3.6.0\"},"
        "{\"canonical_tool_id\":\"git\",\"installation_provider\":\"macos_system\",\"version\":null},"
        "{\"canonical_tool_id\":\"tool\",\"installation_provider\":null,\"version\":null}],\"schema_version\":1}";
    Check([text isEqual:expected], [@"Unexpected cloud inventory: " stringByAppendingString:text ?: @"(nil)"]);
    Check([text rangeOfString:@"/"].location == NSNotFound && [text rangeOfString:@"private"].location == NSNotFound, @"No paths or private text in the upload");
    Check([SHA256Hex([@"abc" dataUsingEncoding:NSUTF8StringEncoding]) isEqual:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"], @"SHA-256 matches the standard vector");

    NSMutableDictionary *other = [Report(@[]) mutableCopy];
    other[@"host"] = @{@"platform": @"windows", @"architecture": @"x86_64"};
    Check(CloudInventoryData(other, NULL, &error) == nil && error, @"Non-macOS scans are refused");
    Check(CloudInventoryData(@{@"schema_version": @2}, NULL, &error) == nil, @"Unknown schema versions are refused");
    NSMutableArray *many = [NSMutableArray array];
    for (int i = 0; i < 6000; i++) [many addObject:@{@"canonical_tool_id": [NSString stringWithFormat:@"tool-%d", i], @"version": @"1.0.0"}];
    CloudInventoryData(Report(many), &dropped, &error);
    Check(dropped == 1000, @"Resource lists are capped at 5000");
}

// Round trip against a running local server. Sign-in uses the real device-code flow
// when DEVCLOUD_TEST_APPROVE names a command that approves a code; otherwise a token.
static void CheckServer(NSString *base, NSString *token, NSString *approve) {
    CloudAccount *account = [[CloudAccount alloc] initWithBaseURL:CloudValidatedURL(base) keychainService:@"dev.devcloud.desktop.cloud.test"];
    Check(account.state == CloudSignedOut, @"Local server origin is accepted");
    if (approve.length) {
        [account beginSignIn];
        Check(Wait(10, ^{ return (BOOL)(account.state == CloudSigningIn); }), [@"Sign-in code was not issued: " stringByAppendingString:account.errorMessage ?: @""]);
        NSString *code = [account.userCode stringByReplacingOccurrencesOfString:@"-" withString:@""];
        NSTask *task = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/bin/sh"] arguments:@[@"-c", [approve stringByAppendingFormat:@" %@", code]] error:nil terminationHandler:nil];
        [task waitUntilExit];
        Check(task.terminationStatus == 0, @"Approval command failed");
    } else {
        [account signInWithToken:token];
    }
    Check(Wait(30, ^{ return (BOOL)(account.state == CloudSignedIn && !account.busy); }), [@"Sign-in did not finish: " stringByAppendingString:account.errorMessage ?: @""]);
    Check(account.deviceIdentifier.length > 0, @"This Mac was registered");

    NSData *json = [NSData dataWithContentsOfFile:NSProcessInfo.processInfo.environment[@"DEVCLOUD_TEST_REPORT"]];
    NSDictionary *fixture = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    NSDictionary *report = fixture[@"report"] ?: fixture;
    Check(report != nil, @"Fixture report loads");
    __block NSError *failure = nil;
    __block BOOL finished = NO;
    [account backUpReport:report completion:^(NSUInteger tools, NSError *error) { failure = error; finished = YES; }];
    Check(Wait(20, ^{ return finished; }) && !failure, [@"Backup failed: " stringByAppendingString:failure.localizedDescription ?: @"timeout"]);
    // The account may hold backups from earlier runs, but this Mac was just registered.
    __block NSDictionary *backup = nil;
    Check(Wait(10, ^{
        for (NSDictionary *row in account.backups) if ([row[@"this_mac"] boolValue]) backup = row;
        return (BOOL)(backup != nil);
    }), @"Backup is listed and attributed to this Mac");

    __block NSData *downloaded = nil;
    finished = NO;
    [account downloadBackup:backup[@"identifier"] completion:^(NSData *data, NSError *error) { downloaded = data; failure = error; finished = YES; }];
    Check(Wait(20, ^{ return finished; }) && [downloaded isEqual:CloudInventoryData(report, NULL, NULL)], @"Downloaded backup matches what was uploaded");

    finished = NO;
    [account deleteBackup:backup[@"identifier"] completion:^(NSError *error) { failure = error; finished = YES; }];
    Check(Wait(20, ^{ return finished; }) && !failure, @"Backup deletes");
    Check(Wait(10, ^{ return (BOOL)![[account.backups valueForKey:@"identifier"] containsObject:backup[@"identifier"]]; }), @"Deleted backup leaves the list");

    [account signOut];
    Check(Wait(20, ^{ return (BOOL)(account.state == CloudSignedOut); }), @"Sign-out finishes");
    CloudAccount *reopened = [[CloudAccount alloc] initWithBaseURL:CloudValidatedURL(base) keychainService:@"dev.devcloud.desktop.cloud.test"];
    [reopened restore];
    Check(reopened.state == CloudSignedOut, @"Sign-out removes the Keychain session");
    if (token.length && !approve.length) {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/v1/devices" relativeToURL:CloudValidatedURL(base)]];
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        __block NSInteger status = 0;
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) { status = ((NSHTTPURLResponse *)r).statusCode; }] resume];
        Check(Wait(10, ^{ return (BOOL)(status != 0); }) && status == 401, @"Signed-out session is revoked on the server");
    }
}

int main(void) {
    @autoreleasepool {
        CheckURLs();
        CheckInventory();
        NSDictionary *env = NSProcessInfo.processInfo.environment;
        if (env[@"DEVCLOUD_TEST_API_URL"]) {
            CheckServer(env[@"DEVCLOUD_TEST_API_URL"], env[@"DEVCLOUD_TEST_TOKEN"], env[@"DEVCLOUD_TEST_APPROVE"]);
            printf("Cloud checks passed, including the local server round trip\n");
        } else {
            printf("Cloud checks passed (set DEVCLOUD_TEST_API_URL for the server round trip)\n");
        }
    }
    return 0;
}
