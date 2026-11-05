// Drives SetupInstaller against a fake `brew`. Real Homebrew is never run.
#import <Foundation/Foundation.h>
#import "SetupFile.h"
#import "SetupInstaller.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL %s\n", message.UTF8String); exit(1); }
}

static NSString *FakeBrew(NSString *directory, NSString *body) {
    NSString *path = [directory stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@"-brew"]];
    [[@"#!/bin/sh\n" stringByAppendingString:body] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:path error:nil];
    return path;
}

static void Wait(SetupInstaller *installer) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:15];
    while (!installer.finished && [limit timeIntervalSinceNow] > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check(installer.finished, @"The install finishes");
}

int main(void) {
    @autoreleasepool {
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"devcloud-installer-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *record = [directory stringByAppendingPathComponent:@"record"];
        NSArray *items = @[@{@"kind": @"brew", @"name": @"git", @"line": @"brew \"git\""},
                           @{@"kind": @"brew", @"name": @"node", @"line": @"brew \"node\""},
                           @{@"kind": @"cask", @"name": @"iterm2", @"line": @"cask \"iterm2\""},
                           @{@"kind": @"vscode", @"name": @"esbenp.prettier-vscode", @"line": @"vscode \"esbenp.prettier-vscode\""},
                           @{@"kind": @"step", @"name": @"nvm install 22", @"line": @"# nvm install 22"}];

        // Batch-style output with one failure.
        NSString *batch = [NSString stringWithFormat:
            @"echo \"$@\" > '%@'\nfile=\"${4#--file=}\"\ncat \"$file\" >> '%@'\nls -ld \"$(dirname \"$file\")\" >> '%@'\n"
            @"echo 'Using git'\necho 'Installing node'\necho 'Installing iterm2'\necho 'Installing esbenp.prettier-vscode'\n"
            @"echo '==> Downloading node'\necho 'Error: Installing iterm2 has failed!' >&2\n"
            @"echo 'Error: `brew bundle` failed! 1 Brewfile dependency failed to install' >&2\nexit 1\n", record, record, record];
        setenv("DEVCLOUD_BREW_PATH", FakeBrew(directory, batch).UTF8String, 1);
        SetupInstaller *installer = [[SetupInstaller alloc] initWithItems:items];
        Check(installer.total == 4, @"Manual steps are never sent to Homebrew");
        NSError *error = nil;
        Check([installer start:&error], [@"The install starts: " stringByAppendingString:error.localizedDescription ?: @""]);
        Check(![installer start:&error], @"A second run is refused");
        Wait(installer);
        NSString *seen = [NSString stringWithContentsOfFile:record encoding:NSUTF8StringEncoding error:nil];
        Check([seen hasPrefix:@"bundle install --no-upgrade --file="], @"Homebrew receives a fixed command");
        Check([seen containsString:@"brew \"node\"\ncask \"iterm2\"\nvscode \"esbenp.prettier-vscode\""] && ![seen containsString:@"nvm"], @"The Brewfile holds only approved Homebrew items");
        Check([seen containsString:@"drwx------"], @"The Brewfile folder is private");
        Check([installer stateFor:@"git"] == SetupItemDone && [installer stateFor:@"node"] == SetupItemDone, @"Confirmed entries are done");
        Check([installer stateFor:@"iterm2"] == SetupItemFailed, @"Reported failures are failed");
        Check(!installer.succeeded && installer.completed == 4, @"A failed run is reported");
        NSString *folder = [[seen componentsSeparatedByString:@"--file="].lastObject stringByDeletingLastPathComponent];
        Check(![NSFileManager.defaultManager fileExistsAtPath:folder], @"The temporary Brewfile is removed");

        // Exiting without Homebrew's summary confirms nothing.
        setenv("DEVCLOUD_BREW_PATH", FakeBrew(directory, @"echo 'Installing node'\nexit 1\n").UTF8String, 1);
        installer = [[SetupInstaller alloc] initWithItems:items];
        Check([installer start:nil], @"Second install starts");
        Wait(installer);
        Check([installer stateFor:@"node"] == SetupItemFailed && [installer stateFor:@"git"] == SetupItemFailed, @"Unconfirmed entries are not reported as installed");

        // Cancelling stops the run.
        setenv("DEVCLOUD_BREW_PATH", FakeBrew(directory, @"echo 'Installing node'\nsleep 30\n").UTF8String, 1);
        installer = [[SetupInstaller alloc] initWithItems:items];
        Check([installer start:nil], @"Third install starts");
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        [installer cancel];
        Wait(installer);
        Check(!installer.succeeded && [installer stateFor:@"node"] == SetupItemFailed, @"A cancelled install confirms nothing");

        setenv("DEVCLOUD_BREW_PATH", [directory stringByAppendingPathComponent:@"missing"].UTF8String, 1);
        Check(!SetupInstaller.homebrew, @"Missing Homebrew is detected");
        installer = [[SetupInstaller alloc] initWithItems:items];
        Check(![installer start:&error] && [error.localizedDescription containsString:@"brew.sh"], @"Without Homebrew nothing starts");

        [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
        printf("Setup installer checks passed\n");
    }
    return 0;
}
