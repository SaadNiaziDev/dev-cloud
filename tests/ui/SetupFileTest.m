#import <Foundation/Foundation.h>
#import "SetupFile.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL %s\n", message.UTF8String); exit(1); }
}

static NSDictionary *Tool(NSString *identifier, id version, id provider) {
    return @{@"canonical_tool_id": identifier, @"version": version ?: NSNull.null, @"installation_provider": provider ?: NSNull.null};
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSDictionary *host = @{@"platform": @"macos", @"architecture": @"aarch64", @"os_version": @"15.1"};
        NSArray *resources = @[
            Tool(@"git", @"2.47.0", @"homebrew_formula"), Tool(@"git", @"2.39.5", @"macos_system"),
            Tool(@"nodejs", @"23.1.0", @"homebrew_formula"), Tool(@"nodejs", @"22.11.0", @"nvm"),
            Tool(@"python", @"3.12.7", @"homebrew_formula"), Tool(@"python", @"3.11.9", @"pyenv"),
            Tool(@"openjdk@17", @"17.0.13", @"homebrew_formula"), Tool(@"brew", @"4.4.0", nil), Tool(@"npm", @"10.9.0", @"homebrew_formula"),
            Tool(@"iterm2", @"3.5.10", @"homebrew_cask"), Tool(@"vscode", @"1.95.0", nil), Tool(@"cursor", @"0.42.0", nil),
            Tool(@"vscode-extension:esbenp.prettier-vscode", @"11.0.0", @"vscode"),
            Tool(@"cursor-extension:anthropic.claude-code", @"2.0.0", @"cursor"),
        ];
        NSDictionary *report = @{@"schema_version": @1, @"observed_at_unix_seconds": @1730851200, @"host": host, @"resources": resources};
        NSUInteger entries = 0;
        NSString *file = SetupBrewfile(report, &entries, nil);
        Check(file != nil, @"A valid inventory produces a setup file");
        for (NSString *line in @[@"brew \"git\"", @"brew \"node\"", @"brew \"python@3.12\"", @"brew \"openjdk@17\"", @"cask \"iterm2\"",
                                 @"cask \"visual-studio-code\"", @"cask \"cursor\"", @"vscode \"esbenp.prettier-vscode\"",
                                 @"# nvm install 22.11.0", @"# pyenv install 3.11.9", @"# cursor --install-extension anthropic.claude-code",
                                 @"#   xcode-select --install", @"macOS 15.1 (aarch64), 2024-11-06"]) {
            Check([file containsString:[line stringByAppendingString:@"\n"]] || [file containsString:line], [@"Setup file contains " stringByAppendingString:line]);
        }
        Check(![file containsString:@"brew \"brew\""] && ![file containsString:@"brew \"npm\""], @"Tools bundled with Homebrew or Node are skipped");
        Check(entries == 11, [NSString stringWithFormat:@"Entries are counted once each (got %lu)", (unsigned long)entries]);
        Check([file componentsSeparatedByString:@"brew \"git\""].count == 2, @"Duplicate installations produce one line");

        NSDictionary *current = @{@"schema_version": @1, @"observed_at_unix_seconds": @2, @"host": host,
                                  @"resources": @[Tool(@"git", @"2.48.0", @"homebrew_formula"), Tool(@"iterm2", @"3.5.11", @"homebrew_cask")]};
        NSArray *items = SetupItems(report, current, nil);
        NSDictionary *byLine = [NSDictionary dictionaryWithObjects:items forKeys:[items valueForKey:@"line"]];
        Check(items.count == entries, @"Items match the setup file's entries");
        Check([byLine[@"brew \"git\""][@"installed"] boolValue] && [byLine[@"cask \"iterm2\""][@"installed"] boolValue], @"Tools on this Mac are marked installed, whatever their version");
        Check(![byLine[@"brew \"node\""][@"installed"] boolValue], @"Missing tools are not marked installed");
        Check([[items.firstObject objectForKey:@"kind"] isEqual:@"brew"] && [[items.lastObject objectForKey:@"kind"] isEqual:@"cursor"], @"Items keep Brewfile order");
        NSString *install = SetupInstallFile(items);
        Check([install containsString:@"vscode \"esbenp.prettier-vscode\""] && ![install containsString:@"nvm"] && ![install containsString:@"cursor --install"], @"Install files hold only Homebrew lines");

        NSArray *hostile = @[Tool(@"evil/tap", @"1", @"homebrew_formula"), Tool(@"x\"; system(\"id\")", @"1", @"homebrew_formula"),
                             Tool(@"nodejs", @"1; curl x | sh", @"nvm"), Tool(@"vscode-extension:bad\"ext", @"1", @"vscode")];
        NSDictionary *bad = @{@"schema_version": @1, @"observed_at_unix_seconds": @1, @"host": host, @"resources": hostile};
        NSString *safe = SetupBrewfile(bad, &entries, nil);
        Check(safe && entries == 0, @"Untrusted names and versions never become setup lines");
        Check(![safe containsString:@"evil"] && ![safe containsString:@"system("] && ![safe containsString:@"curl"], @"Hostile values are not copied");

        NSError *error = nil;
        Check(!SetupBrewfile(@{@"schema_version": @2}, NULL, &error) && error, @"Invalid inventories are refused");

        if (argc > 1) {
            // Optional: render a real scan, e.g. `devcloud-agent scan --format json > scan.json`.
            NSDictionary *scan = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
            NSString *real = SetupBrewfile(scan, &entries, &error);
            Check(real != nil, @"A real scan produces a setup file");
            printf("%s", real.UTF8String);
        }
        printf("Setup file checks passed\n");
    }
    return 0;
}
