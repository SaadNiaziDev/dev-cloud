#import <Foundation/Foundation.h>
#import "SnapshotStore.h"
#import "SnapshotComparison.h"
#import <sys/stat.h>
#import <unistd.h>

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "%s\n", message.UTF8String); exit(1); }
}

static NSDictionary *Tool(NSString *identifier, NSString *instance, NSString *version) {
    return @{@"canonical_tool_id": identifier, @"display_name": identifier, @"kind": @"tool",
             @"installation_instance_id": instance, @"version": version, @"installation_provider": @"fixture"};
}

static NSDictionary *Compare(NSArray *before, NSArray *after) {
    return [SnapshotComparison fromInventory:@{@"resources": before} toInventory:@{@"resources": after}];
}

static void CheckComparisons(void) {
    NSDictionary *git = Tool(@"git", @"git-1", @"2.0"), *node = Tool(@"node", @"node-1", @"22");
    NSDictionary *same = Compare(@[git, node], @[node, git]);
    Check([same[@"added"] count] == 0 && [same[@"removed"] count] == 0 && [same[@"changed"] count] == 0, @"Order must not change comparisons");
    NSDictionary *delta = Compare(@[git], @[node]);
    Check([delta[@"added"] isEqual:@[node]] && [delta[@"removed"] isEqual:@[git]], @"Added and removed tools must preserve direction");
    NSDictionary *upgrade = Compare(@[git], @[Tool(@"git", @"git-2", @"2.1")]);
    Check([upgrade[@"changed"] count] == 1 && [upgrade[@"added"] count] == 0 && [upgrade[@"removed"] count] == 0, @"Unique package upgrades must pair across instance IDs");
    Check([upgrade[@"changed"][0][@"fields"] isEqual:@[@"version"]], @"Changed fields must be reported");
    NSDictionary *multiple = Compare(@[node, Tool(@"node", @"node-2", @"24")], @[Tool(@"node", @"node-3", @"25")]);
    Check([multiple[@"changed"] count] == 0 && [multiple[@"added"] count] == 1 && [multiple[@"removed"] count] == 2, @"Ambiguous installations must not be paired");
    NSDictionary *matched = Compare(@[node, Tool(@"node", @"node-2", @"24")], @[node, Tool(@"node", @"node-3", @"25")]);
    Check([matched[@"changed"] count] == 0 && [matched[@"added"] count] == 1 && [matched[@"removed"] count] == 1, @"A surviving installation must not make the remaining upgrade unambiguous");
    NSMutableDictionary *changed = [git mutableCopy];
    changed[@"installation_path"] = @"/fixture/git";
    changed[@"path_status"] = @"first_on_path";
    NSDictionary *paths = Compare(@[git], @[changed]);
    Check([paths[@"changed"][0][@"fields"] isEqual:@[@"installation_path", @"path_status"]], @"Path and priority changes must be reported");
    changed = [git mutableCopy];
    changed[@"installation_provider"] = @"other";
    NSDictionary *provider = Compare(@[git], @[changed]);
    Check([provider[@"changed"] count] == 0 && [provider[@"added"] count] == 1 && [provider[@"removed"] count] == 1, @"Different providers must remain separate");
    changed = [git mutableCopy];
    changed[@"evidence"] = @[@"Different discovery evidence"];
    Check([Compare(@[git], @[changed])[@"changed"] count] == 0, @"Evidence alone must not count as an inventory change");
    Check([Compare(@[], @[])[@"changed"] count] == 0, @"Empty inventories must compare safely");
}

int main(void) {
    @autoreleasepool {
        CheckComparisons();
        NSFileManager *files = NSFileManager.defaultManager;
        NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        NSURL *directory = [root URLByAppendingPathComponent:@"Snapshots"];
        SnapshotStore *store = [[SnapshotStore alloc] initWithDirectory:directory];
        Check([store snapshotsWithError:nil].count == 0, @"Missing store should be empty");
        NSDictionary *report = @{@"schema_version": @1, @"observed_at_unix_seconds": @123,
            @"host": @{@"platform": @"macos", @"architecture": @"aarch64"}, @"warnings": @[],
            @"resources": @[@{@"canonical_tool_id": @"git", @"display_name": @"Git", @"kind": @"tool",
                @"installation_instance_id": @"git-1", @"discovery_adapter": @"fixture", @"version": @"2.0"}]};
        Check([store captureReport:report error:nil], @"Capture failed");
        NSArray *snapshots = [store snapshotsWithError:nil];
        Check(snapshots.count == 1 && ![snapshots[0][@"damaged"] boolValue], @"Saved snapshot must validate");
        NSString *identifier = snapshots[0][@"identifier"];
        NSData *original = [store exportSnapshot:identifier error:nil];
        NSDictionary *exported = [NSJSONSerialization JSONObjectWithData:original options:0 error:nil];
        Check([exported[@"inventory"] isEqual:report], @"Export must preserve the captured inventory");
        NSURL *external = [root URLByAppendingPathComponent:@"external.json"];
        [original writeToURL:external atomically:YES];
        Check([[store inspectFileAtURL:external error:nil][@"inventory"] isEqual:report], @"External snapshot inspection must preserve inventory");
        Check([store snapshotsWithError:nil].count == 1, @"Inspection must not import into the store");
        Check([[NSData dataWithContentsOfURL:external] isEqual:original], @"Inspection must not modify the source file");
        Check(![store inspectFileAtURL:[NSURL URLWithString:@"https://example.invalid/snapshot.json"] error:nil], @"Remote URLs must be refused");
        Check(![store inspectFileAtURL:root error:nil], @"Directories must be refused");
        NSURL *externalLink = [root URLByAppendingPathComponent:@"linked.json"];
        Check(symlink(external.fileSystemRepresentation, externalLink.fileSystemRepresentation) == 0, @"External symlink fixture failed");
        Check(![store inspectFileAtURL:externalLink error:nil], @"External symlinks must be refused");
        NSMutableDictionary *invalid = [exported mutableCopy];
        invalid[@"captured_at_unix_seconds"] = @(-1);
        [[NSJSONSerialization dataWithJSONObject:invalid options:0 error:nil] writeToURL:external atomically:YES];
        Check(![store inspectFileAtURL:external error:nil], @"Negative capture dates must be refused");
        invalid[@"captured_at_unix_seconds"] = @YES;
        [[NSJSONSerialization dataWithJSONObject:invalid options:0 error:nil] writeToURL:external atomically:YES];
        Check(![store inspectFileAtURL:external error:nil], @"Boolean capture dates must be refused");
        invalid = [exported mutableCopy];
        invalid[@"snapshot_version"] = @YES;
        [[NSJSONSerialization dataWithJSONObject:invalid options:0 error:nil] writeToURL:external atomically:YES];
        Check(![store inspectFileAtURL:external error:nil], @"Boolean versions must be refused");
        NSFileHandle *oversized = [NSFileHandle fileHandleForWritingAtPath:external.path];
        [oversized truncateFileAtOffset:16 * 1024 * 1024 + 1];
        [oversized closeFile];
        Check(![store inspectFileAtURL:external error:nil], @"Oversized files must be refused");
        NSMutableDictionary *invalidReport = [report mutableCopy];
        invalidReport[@"observed_at_unix_seconds"] = @1.5;
        Check(![store captureReport:invalidReport error:nil], @"Fractional scan dates must be refused");
        NSMutableDictionary *invalidResource = [report[@"resources"][0] mutableCopy];
        invalidResource[@"installation_provider"] = @[@"invalid"];
        invalidReport = [report mutableCopy];
        invalidReport[@"resources"] = @[invalidResource];
        Check(![store captureReport:invalidReport error:nil], @"Non-string providers must be refused before comparison");
        struct stat metadata;
        Check(stat(directory.fileSystemRepresentation, &metadata) == 0 && (metadata.st_mode & 0777) == 0700, @"Store must be private");
        NSURL *saved = [directory URLByAppendingPathComponent:identifier];
        Check(stat(saved.fileSystemRepresentation, &metadata) == 0 && (metadata.st_mode & 0777) == 0600, @"Snapshot must be private");
        Check([store captureReport:report error:nil], @"Repeated capture failed");
        Check([store snapshotsWithError:nil].count == 2, @"Repeated captures must remain separate");
        Check([[store exportSnapshot:identifier error:nil] isEqual:original], @"Capture must not overwrite older snapshots");
        SnapshotStore *reopened = [[SnapshotStore alloc] initWithDirectory:directory];
        Check([[reopened exportSnapshot:identifier error:nil] isEqual:original], @"Snapshot must survive reopening");
        NSDictionary *sameSnapshot = [reopened compareSnapshot:identifier toSnapshot:identifier error:nil];
        Check(sameSnapshot && [sameSnapshot[@"changed"] count] == 0, @"Stored snapshots must compare through integrity verification");
        Check(![store exportSnapshot:@"../outside.json" error:nil], @"Traversal must be refused");
        NSMutableDictionary *partial = [report mutableCopy];
        partial[@"warnings"] = @[@"Unable to read Homebrew inventory"];
        Check(![store captureReport:partial error:nil], @"Incomplete inventory must be refused");
        Check(![store captureReport:@{} error:nil], @"Malformed inventory must be refused");
        NSMutableDictionary *tampered = [exported mutableCopy];
        NSMutableDictionary *inventory = [report mutableCopy];
        inventory[@"observed_at_unix_seconds"] = @456;
        tampered[@"inventory"] = inventory;
        [[NSJSONSerialization dataWithJSONObject:tampered options:0 error:nil] writeToURL:saved atomically:YES];
        Check(![store exportSnapshot:identifier error:nil], @"Tampered inventory must fail integrity verification");
        Check(![store compareSnapshot:identifier toSnapshot:identifier error:nil], @"Comparison must refuse tampered snapshots");
        Check([[store snapshotsWithError:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"damaged == YES"]].count == 1, @"Damage must remain visible");
        [original writeToURL:saved atomically:YES];
        tampered = [exported mutableCopy];
        tampered[@"snapshot_version"] = @2;
        [[NSJSONSerialization dataWithJSONObject:tampered options:0 error:nil] writeToURL:saved atomically:YES];
        Check(![store exportSnapshot:identifier error:nil], @"Unknown format versions must be refused");
        [@"not json" writeToURL:saved atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Check(![store exportSnapshot:identifier error:nil], @"Invalid JSON must be refused");
        NSURL *outside = [root URLByAppendingPathComponent:@"outside.json"];
        [original writeToURL:outside atomically:YES];
        [files removeItemAtURL:saved error:nil];
        Check(symlink(outside.fileSystemRepresentation, saved.fileSystemRepresentation) == 0, @"Symlink fixture failed");
        Check(![store exportSnapshot:identifier error:nil], @"Symlinked snapshot must be refused");
        Check([[NSData dataWithContentsOfURL:outside] isEqual:original], @"Outside file must stay untouched");
        NSURL *link = [root URLByAppendingPathComponent:@"LinkedStore"];
        Check(symlink(directory.fileSystemRepresentation, link.fileSystemRepresentation) == 0, @"Directory symlink fixture failed");
        SnapshotStore *linked = [[SnapshotStore alloc] initWithDirectory:link];
        Check(![linked snapshotsWithError:nil] && ![linked captureReport:report error:nil], @"Symlinked store must be refused");
        [files setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:directory.path error:nil];
        Check(![store captureReport:report error:nil], @"Public store must be refused without changing its permissions");
        Check(stat(directory.fileSystemRepresentation, &metadata) == 0 && (metadata.st_mode & 0777) == 0755, @"Capture must not chmod existing directories");
        [files removeItemAtURL:root error:nil];
        puts("Snapshot capture, comparison, export, corruption and filesystem safety passed");
    }
    return 0;
}
