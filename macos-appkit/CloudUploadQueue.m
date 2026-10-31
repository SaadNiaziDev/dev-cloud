#import "CloudUploadQueue.h"
#import "CloudUploadStore.h"
#import "CloudInventory.h"

static id Field(id object, NSString *key) { return [object isKindOfClass:NSDictionary.class] ? object[key] : nil; }
static NSError *QueueError(NSString *message) {
    return [NSError errorWithDomain:@"DevCloudCloud" code:3 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation CloudUploadQueue {
    CloudUploadStore *_store;
    NSMutableArray<NSDictionary *> *_jobs;
    CloudUploadTransport _transport;
    BOOL _running;
    NSUInteger _generation;
    BOOL _storageFailed;
    BOOL _reserved;
}
@synthesize uploading = _uploading, message = _message;

- (instancetype)initWithDirectory:(NSURL *)directory owner:(NSString *)owner transport:(CloudUploadTransport)transport {
    if ((self = [super init])) {
        _store = [[CloudUploadStore alloc] initWithDirectory:directory owner:owner];
        NSError *error = nil;
        _jobs = [[_store load:&error] mutableCopy] ?: [NSMutableArray array];
        _storageFailed = error != nil;
        _message = error.localizedDescription;
        _transport = [transport copy];
    }
    return self;
}

- (NSUInteger)count { return _jobs.count; }
- (void)notify { if (self.changed) self.changed(); }

- (BOOL)persist:(NSArray<NSDictionary *> *)jobs error:(NSError **)error {
    if (![_store save:jobs error:error]) return NO;
    _jobs = [jobs mutableCopy];
    return YES;
}

- (BOOL)enqueue:(NSData *)body device:(NSString *)device error:(NSError **)error {
    if (_storageFailed) { if (error) *error = QueueError(_message); return NO; }
    if (!body.length || body.length > CloudInventoryMaxBytes || ![[NSUUID alloc] initWithUUIDString:device]) {
        if (error) *error = QueueError(@"This inventory cannot be queued."); return NO;
    }
    id inventory = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if (![inventory isKindOfClass:NSDictionary.class] || ![CloudInventoryData(inventory, NULL, NULL) isEqual:body]) {
        if (error) *error = QueueError(@"This inventory cannot be queued."); return NO;
    }
    NSString *sha = SHA256Hex(body);
    for (NSDictionary *job in _jobs) if ([job[@"sha"] isEqual:sha]) return YES;
    if (_jobs.count == 5) { if (error) *error = QueueError(@"Five backups are already queued. Finish or clear them before adding another."); return NO; }
    NSMutableArray *jobs = [_jobs mutableCopy];
    [jobs addObject:@{@"key": NSUUID.UUID.UUIDString.lowercaseString, @"body": body, @"device": device, @"sha": sha,
                     @"attempts": @0, @"next": @0, @"blocked": @NO}];
    if (![self persist:jobs error:error]) return NO;
    [self notify];
    [self start];
    return YES;
}

- (void)start {
    _running = YES;
    if (_storageFailed || _uploading || !_jobs.count) return;
    NSDictionary *job = _jobs.firstObject;
    if ([job[@"blocked"] boolValue]) { _message = @"A queued backup needs attention. Retry it or clear the queue."; [self notify]; return; }
    NSUInteger generation = ++_generation;
    NSTimeInterval delay = MAX(0, [job[@"next"] doubleValue] - NSDate.date.timeIntervalSince1970);
    __weak CloudUploadQueue *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MIN(delay, 86400) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CloudUploadQueue *self = weakSelf;
        if (!self || !self->_running || generation != self->_generation) return;
        [self upload:generation];
    });
}

- (void)retry {
    if (_uploading || _storageFailed || !_jobs.count) return;
    NSMutableArray *jobs = [_jobs mutableCopy];
    NSMutableDictionary *first = [jobs[0] mutableCopy];
    first[@"next"] = @0; first[@"blocked"] = @NO; jobs[0] = first;
    NSError *error = nil;
    if (![self persist:jobs error:&error]) { _message = error.localizedDescription; [self notify]; return; }
    [self start];
}

- (void)stop { _running = NO; _generation++; _uploading = NO; }

- (BOOL)discard:(NSError **)error {
    [self stop];
    if (![self persist:@[] error:error]) return NO;
    _storageFailed = NO; _message = nil; [self notify]; return YES;
}

- (void)upload:(NSUInteger)generation {
    _uploading = YES; _message = nil; [self notify];
    NSDictionary *job = _jobs.firstObject;
    _reserved = NO;
    if ([job[@"commit_sent"] boolValue]) {
        NSString *identifier = job[@"upload_id"];
        [self commit:[NSString stringWithFormat:@"/v1/uploads/%@", identifier] identifier:identifier generation:generation];
        return;
    }
    NSDictionary *input = @{@"device_id": job[@"device"], @"schema_version": @1, @"byte_count": @([job[@"body"] length]),
                            @"sha256": job[@"sha"], @"idempotency_key": job[@"key"]};
    _transport(@"POST", @"/v1/uploads", input, nil, ^(NSInteger status, id payload, NSHTTPURLResponse *response) {
        if (![self active:generation]) return;
        id upload = Field(payload, @"upload");
        NSString *identifier = Field(upload, @"id");
        if (status != 201 || ![identifier isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:identifier]) {
            [self failed:status payload:payload response:response]; return;
        }
        self->_reserved = YES;
        NSString *path = [NSString stringWithFormat:@"/v1/uploads/%@", identifier];
        self->_transport(@"PUT", [path stringByAppendingString:@"/body"], nil, job[@"body"], ^(NSInteger status, id payload, NSHTTPURLResponse *response) {
            if (![self active:generation]) return;
            if (status != 204) { [self failed:status payload:payload response:response]; return; }
            [self commit:path identifier:identifier generation:generation];
        });
    });
}

- (BOOL)active:(NSUInteger)generation { return _running && _uploading && generation == _generation; }

- (void)commit:(NSString *)path identifier:(NSString *)identifier generation:(NSUInteger)generation {
    if (![_jobs.firstObject[@"commit_sent"] boolValue]) {
        NSMutableArray *jobs = [_jobs mutableCopy];
        NSMutableDictionary *job = [jobs[0] mutableCopy];
        job[@"commit_sent"] = @YES; job[@"upload_id"] = identifier; jobs[0] = job;
        NSError *error = nil;
        if (![self persist:jobs error:&error]) {
            _uploading = NO; _storageFailed = YES; _message = error.localizedDescription; [self notify]; return;
        }
    }
    _transport(@"POST", [path stringByAppendingString:@"/commit"], nil, nil, ^(NSInteger status, id payload, NSHTTPURLResponse *response) {
        if (![self active:generation]) return;
        NSDictionary *job = self->_jobs.firstObject;
        id snapshot = Field(payload, @"snapshot");
        if (status != 200 || ![Field(snapshot, @"id") isEqual:identifier] || ![Field(snapshot, @"sha256") isEqual:job[@"sha"]] ||
            ![Field(snapshot, @"byte_count") isEqual:@([job[@"body"] length])] || ![Field(snapshot, @"device_id") isEqual:job[@"device"]] || ![Field(snapshot, @"schema_version") isEqual:@1]) {
            [self failed:status payload:payload response:response]; return;
        }
        NSMutableArray *jobs = [self->_jobs mutableCopy]; [jobs removeObjectAtIndex:0];
        NSError *error = nil;
        self->_uploading = NO;
        if (![self persist:jobs error:&error]) { self->_storageFailed = YES; self->_message = error.localizedDescription; [self notify]; return; }
        if (self.committed) self.committed();
        [self notify]; [self start];
    });
}

- (void)failed:(NSInteger)status payload:(id)payload response:(NSHTTPURLResponse *)response {
    _uploading = NO;
    NSMutableDictionary *job = [_jobs.firstObject mutableCopy];
    NSUInteger attempts = MIN(100, [job[@"attempts"] unsignedIntegerValue] + 1);
    BOOL committing = [job[@"commit_sent"] boolValue];
    BOOL expired = status == 410 || (status == 404 && _reserved && !committing);
    BOOL incomplete = status == 409 && [Field(payload, @"error") isEqual:@"upload_incomplete"];
    BOOL transient = status == 0 || status == 408 || status == 425 || status == 429 || status >= 500 || expired ||
        incomplete;
    if ([Field(payload, @"error") isEqual:@"quota_exceeded"]) transient = NO;
    NSTimeInterval delay = MAX(5u << MIN(attempts, 7u), [[response valueForHTTPHeaderField:@"Retry-After"] doubleValue]);
    job[@"attempts"] = @(attempts); job[@"blocked"] = @(!transient);
    job[@"next"] = @(NSDate.date.timeIntervalSince1970 + MIN(delay, 86400));
    if (expired) job[@"key"] = NSUUID.UUID.UUIDString.lowercaseString;
    if (expired || incomplete) { [job removeObjectForKey:@"commit_sent"]; [job removeObjectForKey:@"upload_id"]; }
    // A missing uncertain commit may have been explicitly deleted; never recreate it.
    if (status == 404 && committing) { job[@"blocked"] = @YES; transient = NO; }
    NSMutableArray *jobs = [_jobs mutableCopy]; jobs[0] = job;
    NSError *error = nil;
    if (![self persist:jobs error:&error]) { _storageFailed = YES; _message = error.localizedDescription; }
    else _message = transient ? @"Backup queued. It will retry automatically when DevCloud is open." : @"A queued backup needs attention. Retry it or clear the queue.";
    [self notify];
    if (transient) [self start];
}
@end
