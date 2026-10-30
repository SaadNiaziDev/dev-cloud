#import "SnapshotStore.h"
#import "SnapshotComparison.h"
#import <CommonCrypto/CommonDigest.h>
#import <fcntl.h>
#import <dirent.h>
#import <sys/stat.h>
#import <unistd.h>

static const NSUInteger SnapshotLimit = 16 * 1024 * 1024;

static void SnapshotError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"DevCloudSnapshots" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *Digest(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) [result appendFormat:@"%02x", bytes[i]];
    return result;
}

static BOOL ValidInventory(id report) {
    if (![report isKindOfClass:NSDictionary.class]) return NO;
    if (![report[@"schema_version"] isEqual:@1] || ![report[@"host"] isKindOfClass:NSDictionary.class] ||
        ![report[@"observed_at_unix_seconds"] isKindOfClass:NSNumber.class] ||
        ![report[@"resources"] isKindOfClass:NSArray.class] || ![report[@"warnings"] isKindOfClass:NSArray.class]) return NO;
    for (id resource in report[@"resources"]) {
        if (![resource isKindOfClass:NSDictionary.class]) return NO;
        for (NSString *key in @[@"canonical_tool_id", @"display_name", @"kind", @"installation_instance_id", @"discovery_adapter"]) {
            if (![resource[key] isKindOfClass:NSString.class]) return NO;
        }
    }
    for (id warning in report[@"warnings"]) if (![warning isKindOfClass:NSString.class]) return NO;
    return YES;
}

@implementation SnapshotStore {
    NSURL *_directory;
}

- (instancetype)initWithDirectory:(NSURL *)directory {
    self = [super init];
    if (self) _directory = directory;
    return self;
}

- (BOOL)captureReport:(NSDictionary *)report error:(NSError **)error {
    if (!ValidInventory(report)) { SnapshotError(error, @"A valid inventory scan is required."); return NO; }
    for (NSString *warning in report[@"warnings"]) {
        if (([warning hasPrefix:@"Unable to read "] && [warning containsString:@" inventory"]) || [warning hasSuffix:@" inventory exceeded its entry limit"]) {
            SnapshotError(error, @"The inventory is incomplete. Scan again before saving a snapshot.");
            return NO;
        }
    }
    NSData *inventory = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:error];
    if (!inventory || inventory.length > SnapshotLimit) { SnapshotError(error, @"The inventory exceeds the snapshot size limit."); return NO; }
    NSDictionary *snapshot = @{@"snapshot_version": @1, @"captured_at_unix_seconds": @((long long)NSDate.date.timeIntervalSince1970),
                               @"inventory": report, @"inventory_sha256": Digest(inventory)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingSortedKeys error:error];
    if (!data || data.length > SnapshotLimit) { SnapshotError(error, @"The snapshot exceeds the size limit."); return NO; }
    if (![NSFileManager.defaultManager createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:error]) return NO;
    int directory = [self openDirectory:error];
    if (directory < 0) return NO;
    NSString *name = [NSUUID.UUID.UUIDString stringByAppendingString:@".json"];
    NSString *temporary = [name stringByAppendingString:@".tmp"];
    int file = openat(directory, temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    BOOL success = file >= 0;
    NSUInteger offset = 0;
    while (success && offset < data.length) {
        ssize_t written = write(file, (const char *)data.bytes + offset, data.length - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) success = NO;
        else offset += (NSUInteger)written;
    }
    if (success) success = fsync(file) == 0;
    if (file >= 0) close(file);
    // Publish only complete files, without ever replacing an existing snapshot.
    if (success) success = linkat(directory, temporary.fileSystemRepresentation, directory, name.fileSystemRepresentation, 0) == 0;
    unlinkat(directory, temporary.fileSystemRepresentation, 0);
    if (success) success = fsync(directory) == 0;
    close(directory);
    if (!success) SnapshotError(error, @"The snapshot could not be saved.");
    return success;
}

- (NSArray<NSDictionary *> *)snapshotsWithError:(NSError **)error {
    struct stat metadata;
    if (lstat(_directory.fileSystemRepresentation, &metadata) < 0 && errno == ENOENT) return @[];
    int directory = [self openDirectory:error];
    if (directory < 0) return nil;
    // Enumerate the opened directory so a renamed or replaced path cannot redirect reads.
    DIR *entries = fdopendir(dup(directory));
    if (!entries) { close(directory); SnapshotError(error, @"Snapshots could not be listed."); return nil; }
    NSMutableArray *snapshots = [NSMutableArray array];
    struct dirent *entry;
    while ((entry = readdir(entries))) {
        NSString *name = [NSString stringWithUTF8String:entry->d_name];
        if (![name.pathExtension isEqual:@"json"]) continue;
        NSData *data = [self read:name directory:directory error:nil];
        NSDictionary *snapshot = data ? [self validate:data error:nil] : nil;
        NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary:snapshot ?: @{}];
        row[@"identifier"] = name;
        row[@"damaged"] = @(!snapshot);
        [snapshots addObject:row];
    }
    closedir(entries);
    close(directory);
    [snapshots sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"captured_at_unix_seconds"] ?: @0 compare:a[@"captured_at_unix_seconds"] ?: @0];
    }];
    return snapshots;
}

- (NSData *)exportSnapshot:(NSString *)identifier error:(NSError **)error {
    if (![identifier isEqual:identifier.lastPathComponent] || ![identifier.pathExtension isEqual:@"json"]) {
        SnapshotError(error, @"Invalid snapshot identifier."); return nil;
    }
    int directory = [self openDirectory:error];
    if (directory < 0) return nil;
    NSData *data = [self read:identifier directory:directory error:error];
    close(directory);
    return data && [self validate:data error:error] ? data : nil;
}

- (NSDictionary *)compareSnapshot:(NSString *)before toSnapshot:(NSString *)after error:(NSError **)error {
    NSData *oldData = [self exportSnapshot:before error:error];
    if (!oldData) return nil;
    NSData *newData = [self exportSnapshot:after error:error];
    if (!newData) return nil;
    NSDictionary *oldSnapshot = [NSJSONSerialization JSONObjectWithData:oldData options:0 error:error];
    NSDictionary *newSnapshot = [NSJSONSerialization JSONObjectWithData:newData options:0 error:error];
    return [SnapshotComparison fromInventory:oldSnapshot[@"inventory"] toInventory:newSnapshot[@"inventory"]];
}

- (int)openDirectory:(NSError **)error {
    int directory = open(_directory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat metadata;
    if (directory < 0 || fstat(directory, &metadata) < 0 || metadata.st_uid != getuid() || (metadata.st_mode & 0077)) {
        if (directory >= 0) close(directory);
        SnapshotError(error, @"The snapshot folder must be private and owned by you, without a symlink.");
        return -1;
    }
    return directory;
}

- (NSData *)read:(NSString *)name directory:(int)directory error:(NSError **)error {
    int file = openat(directory, name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    struct stat metadata;
    if (file < 0 || fstat(file, &metadata) < 0 || !S_ISREG(metadata.st_mode) || metadata.st_size < 0 || metadata.st_size > (off_t)SnapshotLimit) {
        if (file >= 0) close(file);
        SnapshotError(error, @"The snapshot is unreadable or exceeds the size limit."); return nil;
    }
    NSMutableData *data = [NSMutableData data];
    char buffer[8192];
    ssize_t count;
    while ((count = read(file, buffer, sizeof(buffer))) != 0) {
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 || data.length + (NSUInteger)count > SnapshotLimit) {
            close(file); SnapshotError(error, @"The snapshot could not be read."); return nil;
        }
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    close(file);
    return data;
}

- (NSDictionary *)validate:(NSData *)data error:(NSError **)error {
    id snapshot = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![snapshot isKindOfClass:NSDictionary.class] || ![snapshot[@"snapshot_version"] isEqual:@1] ||
        ![snapshot[@"captured_at_unix_seconds"] isKindOfClass:NSNumber.class] || !ValidInventory(snapshot[@"inventory"])) {
        SnapshotError(error, @"Unsupported or damaged snapshot."); return nil;
    }
    NSData *inventory = [NSJSONSerialization dataWithJSONObject:snapshot[@"inventory"] options:NSJSONWritingSortedKeys error:nil];
    if (![snapshot[@"inventory_sha256"] isEqual:Digest(inventory)]) {
        SnapshotError(error, @"The snapshot failed its integrity check."); return nil;
    }
    return snapshot;
}
@end
