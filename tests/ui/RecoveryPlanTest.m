#import <Foundation/Foundation.h>
#import "CloudInventory.h"
#import "RecoveryPlan.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL %s\n", message.UTF8String); exit(1); }
}

int main(void) {
    @autoreleasepool {
        NSDictionary *host = @{@"platform": @"macos", @"architecture": @"aarch64", @"os_version": @"14"};
        NSDictionary *node = @{@"canonical_tool_id": @"nodejs", @"version": @"24", @"installation_provider": @"nvm"};
        NSDictionary *git = @{@"canonical_tool_id": @"git", @"version": @"2.0", @"installation_provider": @"homebrew"};
        NSDictionary *python = @{@"canonical_tool_id": @"python", @"version": @"3.12", @"installation_provider": @"pyenv"};
        NSDictionary *saved = @{@"schema_version": @1, @"observed_at_unix_seconds": @1, @"host": host, @"resources": @[node, git, python]};
        NSDictionary *oldGit = @{@"canonical_tool_id": @"git", @"version": @"1.0", @"installation_provider": @"homebrew"};
        NSDictionary *current = @{@"schema_version": @1, @"observed_at_unix_seconds": @2, @"host": host, @"resources": @[node, oldGit]};
        NSData *backup = CloudInventoryData(saved, NULL, nil);
        NSArray *plan = RecoveryPlan(backup, current, nil);
        Check(plan.count == 3, @"All saved tools appear in the plan");
        Check([plan[0][@"status"] isEqual:@"Present"], @"Exact tool version and source are present");
        Check([plan[1][@"status"] isEqual:@"Review version or source"], @"Different versions require review");
        Check([plan[2][@"status"] isEqual:@"Manual setup needed"], @"Missing tools require manual setup");
        NSMutableDictionary *invalid = [saved mutableCopy];
        invalid[@"extra"] = @"unexpected";
        NSData *bad = [NSJSONSerialization dataWithJSONObject:invalid options:0 error:nil];
        NSError *error = nil;
        Check(!RecoveryPlan(bad, current, &error) && error, @"Unexpected backup fields are rejected");
        Check(!RecoveryPlan(backup, nil, &error), @"A destination scan is required");
        printf("Recovery plan checks passed\n");
    }
    return 0;
}
