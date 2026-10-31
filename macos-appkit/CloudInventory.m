#import "CloudInventory.h"
#import <CommonCrypto/CommonDigest.h>

const NSUInteger CloudInventoryMaxBytes = 1024 * 1024;

// Mirrors the server's upload format; the server rejects anything else.
static BOOL Matches(id value, NSString *pattern, NSUInteger maxLength) {
    if (![value isKindOfClass:NSString.class] || [value length] == 0 || [value length] > maxLength) return NO;
    return [value rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

static id Version(id value) {
    return Matches(value, @"^[A-Za-z0-9][A-Za-z0-9 .+_!()-]*$", 80) ? value : NSNull.null;
}

static NSError *Failure(NSString *message) {
    return [NSError errorWithDomain:@"DevCloudCloud" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSData *CloudInventoryData(NSDictionary *report, NSUInteger *dropped, NSError **error) {
    static NSSet *providers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        providers = [NSSet setWithArray:@[@"homebrew", @"homebrew_formula", @"homebrew_cask", @"macos_system", @"xcode", @"nvm", @"pyenv",
                                          @"volta", @"fnm", @"rustup", @"npm", @"pip", @"cargo", @"vscode", @"cursor"]];
    });
    if (dropped) *dropped = 0;
    NSDictionary *host = [report[@"host"] isKindOfClass:NSDictionary.class] ? report[@"host"] : nil;
    NSNumber *observed = [report[@"observed_at_unix_seconds"] isKindOfClass:NSNumber.class] ? report[@"observed_at_unix_seconds"] : nil;
    NSArray *resources = [report[@"resources"] isKindOfClass:NSArray.class] ? report[@"resources"] : nil;
    if (![report[@"schema_version"] isEqual:@1] || !host || !observed || observed.longLongValue < 0 || !resources) {
        if (error) *error = Failure(@"The scan is incomplete. Scan again before backing up.");
        return nil;
    }
    if (![host[@"platform"] isEqual:@"macos"] || !([host[@"architecture"] isEqual:@"aarch64"] || [host[@"architecture"] isEqual:@"x86_64"])) {
        if (error) *error = Failure(@"Only scans of this Mac can be backed up.");
        return nil;
    }
    NSMutableArray *tools = [NSMutableArray array];
    for (NSDictionary *resource in resources) {
        if (![resource isKindOfClass:NSDictionary.class] || !Matches(resource[@"canonical_tool_id"], @"^[a-z0-9][a-z0-9._@:-]*$", 120) || tools.count == 5000) {
            if (dropped) (*dropped)++;
            continue;
        }
        NSString *provider = resource[@"installation_provider"];
        [tools addObject:@{
            @"canonical_tool_id": resource[@"canonical_tool_id"],
            @"version": Version(resource[@"version"]),
            @"installation_provider": [provider isKindOfClass:NSString.class] && [providers containsObject:provider] ? provider : NSNull.null,
        }];
    }
    NSDictionary *inventory = @{
        @"schema_version": @1,
        @"observed_at_unix_seconds": @(observed.longLongValue),
        @"host": @{@"platform": @"macos", @"architecture": host[@"architecture"], @"os_version": Version(host[@"os_version"])},
        @"resources": tools,
    };
    // Every string is ASCII without `/`, so this matches the server's compact re-encoding byte for byte.
    NSData *data = [NSJSONSerialization dataWithJSONObject:inventory options:NSJSONWritingSortedKeys error:error];
    if (data.length > CloudInventoryMaxBytes) {
        if (error) *error = Failure(@"This inventory is larger than a backup allows.");
        return nil;
    }
    return data;
}

NSString *SHA256Hex(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}
