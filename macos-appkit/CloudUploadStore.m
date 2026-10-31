#import "CloudUploadStore.h"
#import "CloudInventory.h"
#import <fcntl.h>
#import <dirent.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <unistd.h>

static NSError *StorageError(void) {
    return [NSError errorWithDomain:@"DevCloudCloud" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Queued backups could not be read or saved. Clear the queue and try again."}];
}

@implementation CloudUploadStore {
    NSURL *_directory;
    NSString *_owner;
    int _lock;
}

- (instancetype)initWithDirectory:(NSURL *)directory owner:(NSString *)owner {
    if ((self = [super init])) { _directory = directory; _owner = [owner copy]; _lock = -1; }
    return self;
}

- (void)dealloc { if (_lock >= 0) close(_lock); }

- (int)openDirectory {
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files fileExistsAtPath:_directory.path] &&
        ![files createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil]) return -1;
    int fd = open(_directory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat info;
    if (fd < 0) return -1;
    if (fstat(fd, &info) != 0 || info.st_uid != geteuid() || (info.st_mode & 0077) != 0) { close(fd); return -1; }
    if (_lock < 0) {
        int lock = openat(fd, ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
        struct stat lockInfo;
        if (lock < 0 || fstat(lock, &lockInfo) != 0 || !S_ISREG(lockInfo.st_mode) || lockInfo.st_uid != geteuid() ||
            (lockInfo.st_mode & 0077) != 0 || flock(lock, LOCK_EX | LOCK_NB) != 0) {
            if (lock >= 0) close(lock);
            close(fd); return -1;
        }
        _lock = lock;
    }
    return fd;
}

- (NSArray<NSDictionary *> *)load:(NSError **)error {
    int directory = [self openDirectory];
    if (directory < 0) { if (error) *error = StorageError(); return nil; }
    // Exclusive ownership makes crash-file cleanup safe even with two app builds open.
    DIR *entries = fdopendir(dup(directory));
    if (entries) {
        struct dirent *entry;
        while ((entry = readdir(entries))) {
            NSString *name = [NSString stringWithUTF8String:entry->d_name];
            if ([name hasPrefix:@"queue-"] && [[NSUUID alloc] initWithUUIDString:[name substringFromIndex:6]]) unlinkat(directory, entry->d_name, 0);
        }
        closedir(entries);
    }
    int fd = openat(directory, "queue.plist", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    int failure = errno;
    close(directory);
    if (fd < 0 && failure == ENOENT) return @[];
    struct stat info;
    if (fd < 0 || fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_uid != geteuid() ||
        (info.st_mode & 0077) != 0 || info.st_size <= 0 || info.st_size > 6 * 1024 * 1024) {
        if (fd >= 0) close(fd);
        if (error) *error = StorageError();
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t count = read(fd, (char *)data.mutableBytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (NSUInteger)count;
    }
    close(fd);
    id envelope = offset == data.length ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil] : nil;
    if (![envelope isKindOfClass:NSDictionary.class] || ![envelope[@"version"] isEqual:@1] ||
        ![envelope[@"owner"] isKindOfClass:NSString.class] || ![envelope[@"jobs"] isKindOfClass:NSArray.class] || [envelope[@"jobs"] count] > 5) {
        if (error) *error = StorageError(); return nil;
    }
    if (![envelope[@"owner"] isEqual:_owner]) return [self save:@[] error:error] ? @[] : nil;
    for (id job in envelope[@"jobs"]) {
        if (![self validJob:job]) { if (error) *error = StorageError(); return nil; }
    }
    return envelope[@"jobs"];
}

- (BOOL)validJob:(id)job {
    if (![job isKindOfClass:NSDictionary.class]) return NO;
    NSData *body = job[@"body"];
    if (![body isKindOfClass:NSData.class] || !body.length || body.length > CloudInventoryMaxBytes ||
        ![job[@"key"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:job[@"key"]] ||
        ![job[@"device"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:job[@"device"]] ||
        ![job[@"sha"] isKindOfClass:NSString.class] || ![SHA256Hex(body) isEqual:job[@"sha"]]) return NO;
    for (NSString *key in @[@"attempts", @"next", @"blocked"]) if (![job[key] isKindOfClass:NSNumber.class]) return NO;
    if (job[@"commit_sent"] && (![job[@"commit_sent"] isKindOfClass:NSNumber.class] ||
        ![job[@"upload_id"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:job[@"upload_id"]])) return NO;
    double next = [job[@"next"] doubleValue];
    if (!isfinite(next) || next < 0 || [job[@"attempts"] unsignedIntegerValue] > 100) return NO;
    id report = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    return [report isKindOfClass:NSDictionary.class] && [CloudInventoryData(report, NULL, NULL) isEqual:body];
}

- (BOOL)save:(NSArray<NSDictionary *> *)jobs error:(NSError **)error {
    if (jobs.count > 5) { if (error) *error = StorageError(); return NO; }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"version": @1, @"owner": _owner, @"jobs": jobs}
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    int directory = data ? [self openDirectory] : -1;
    if (directory < 0) { if (error) *error = StorageError(); return NO; }
    NSString *temporary = [@"queue-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int fd = openat(directory, temporary.UTF8String, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    NSUInteger offset = 0;
    while (fd >= 0 && offset < data.length) {
        ssize_t count = write(fd, (const char *)data.bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (NSUInteger)count;
    }
    BOOL saved = fd >= 0 && offset == data.length && fsync(fd) == 0;
    if (fd >= 0) close(fd);
    if (saved) saved = renameat(directory, temporary.UTF8String, directory, "queue.plist") == 0;
    if (saved) saved = fsync(directory) == 0;
    if (!saved) unlinkat(directory, temporary.UTF8String, 0);
    close(directory);
    if (!saved && error) *error = StorageError();
    return saved;
}
@end
