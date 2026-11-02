#import <Foundation/Foundation.h>
#import "CloudUploadQueue.h"
#import "CloudInventory.h"

static void Check(BOOL ok, NSString *message) { if (!ok) { fprintf(stderr, "FAIL %s\n", message.UTF8String); exit(1); } }
static BOOL Wait(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!done() && limit.timeIntervalSinceNow > 0) { @autoreleasepool { [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]]; } }
    return done();
}
static NSData *Inventory(NSUInteger index) {
    return CloudInventoryData(@{@"schema_version": @1, @"observed_at_unix_seconds": @(index), @"host": @{@"platform": @"macos", @"architecture": @"aarch64", @"os_version": @"14.0"}, @"resources": @[]}, NULL, NULL);
}

int main(void) {
    @autoreleasepool {
        NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        NSString *device = NSUUID.UUID.UUIDString.lowercaseString, *identifier = NSUUID.UUID.UUIDString.lowercaseString;
        NSData *body = Inventory(1);
        __block NSUInteger reserves = 0, puts = 0, commits = 0, acknowledged = 0;
        __block NSString *firstKey;
        __block NSDictionary *metadata;
        CloudUploadTransport transport = ^(NSString *method, NSString *path, id json, NSData *bytes, CloudUploadReply reply) {
            if ([path isEqual:@"/v1/uploads"]) {
                reserves++;
                if (!firstKey) firstKey = json[@"idempotency_key"];
                Check([firstKey isEqual:json[@"idempotency_key"]], @"A lost response preserves the retry key");
                metadata = @{@"id": identifier, @"sha256": json[@"sha256"], @"device_id": json[@"device_id"], @"byte_count": json[@"byte_count"], @"schema_version": @1};
                reply(201, @{@"upload": @{@"id": identifier, @"state": commits ? @"committed" : @"pending"}}, nil);
            } else if ([method isEqual:@"PUT"]) { puts++; Check([bytes isEqual:body], @"Upload uses the staged bytes"); reply(204, nil, nil); }
            else { commits++; reply(commits == 1 ? 0 : 200, @{@"snapshot": metadata}, nil); }
        };
        __block CloudUploadQueue *queue = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-a" transport:transport];
        queue.committed = ^(NSData *acknowledgedBody) { acknowledged++; };
        Check([queue enqueue:body device:device error:nil], @"Inventory is saved before sending");
        Check(Wait(^BOOL(void) { return commits == 1 && !queue.uploading; }), @"An uncertain commit stays queued");
        Check(queue.count == 1 && acknowledged == 0, @"Unacknowledged data is never marked complete");
        [queue stop]; queue = nil;
        queue = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-a" transport:transport];
        queue.committed = ^(NSData *acknowledgedBody) { acknowledged++; };
        Check(queue.count == 1, [@"Restart restores pending bytes: " stringByAppendingString:queue.message ?: @"no message"]);
        [queue retry];
        Check(Wait(^BOOL(void) { return queue.count == 0; }), @"Retry reconciles an already committed upload");
        Check(reserves == 1 && puts == 1 && acknowledged == 1, @"Retry produces one backup without uploading again");
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:[root.path stringByAppendingPathComponent:@"queue.plist"] error:nil];
        Check([attributes[NSFilePosixPermissions] unsignedIntegerValue] == 0600, @"Queue file is owner-only");

        CloudUploadQueue *second = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-a" transport:transport];
        Check(second.message != nil && ![second enqueue:body device:device error:nil], @"Concurrent app instances cannot overwrite the queue");
        second = nil;
        NSURL *crashFile = [root URLByAppendingPathComponent:[@"queue-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        [@"interrupted write" writeToURL:crashFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        __block NSUInteger calls = 0;
        CloudUploadReply __block delayed;
        [queue stop]; queue = nil;
        queue = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-a" transport:^(NSString *m, NSString *p, id j, NSData *b, CloudUploadReply r) { calls++; delayed = [r copy]; }];
        Check(![NSFileManager.defaultManager fileExistsAtPath:crashFile.path], @"Interrupted atomic writes are reclaimed on restart");
        Check([queue enqueue:body device:device error:nil], @"A second intent queues");
        Check(Wait(^BOOL(void) { return calls == 1; }), @"An upload starts");
        Check([queue discard:nil], @"Discard invalidates in-flight work");
        delayed(201, @{@"upload": @{@"id": identifier, @"state": @"pending"}}, nil);
        Check(queue.count == 0 && calls == 1, @"Late callbacks cannot resume a signed-out queue");
        delayed = nil;

        __block NSUInteger limitedCalls = 0;
        [queue stop]; queue = nil;
        queue = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-a" transport:^(NSString *m, NSString *p, id j, NSData *b, CloudUploadReply r) {
            limitedCalls++;
            NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://api.example.invalid"] statusCode:429 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Retry-After": @"120"}];
            r(429, @{@"error": @"rate_limit_exceeded"}, response);
        }];
        Check([queue enqueue:body device:device error:nil], @"A throttled backup queues");
        Check(Wait(^BOOL(void) { return limitedCalls == 1 && !queue.uploading; }), @"Rate limit pauses the queue");
        NSDictionary *disk = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"queue.plist"]] options:0 format:NULL error:nil];
        Check([disk[@"jobs"][0][@"next"] doubleValue] > NSDate.date.timeIntervalSince1970 + 100, @"Retry-After persists across restarts");
        [queue stop]; queue = nil;
        queue = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-b" transport:transport];
        Check(queue.count == 0, @"A different session cannot inherit queued uploads");

        for (NSUInteger i = 1; i <= 5; i++) Check([queue enqueue:Inventory(i) device:device error:nil], @"Queue accepts five bounded intents");
        [queue stop];
        Check([queue enqueue:Inventory(1) device:device error:nil] && queue.count == 5, @"Identical pending inventory is deduplicated");
        [queue stop];
        Check(![queue enqueue:Inventory(6) device:device error:nil], @"The queue cannot grow unbounded");
        Check(![queue enqueue:[@"{}" dataUsingEncoding:NSUTF8StringEncoding] device:device error:nil], @"Malformed inventory never reaches the network");
        [queue discard:nil]; queue = nil;

        __block NSUInteger expiredCalls = 0;
        __block NSString *expiredKey;
        queue = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-b" transport:^(NSString *m, NSString *p, id j, NSData *b, CloudUploadReply r) {
            expiredCalls++;
            if (expiredCalls == 1) { expiredKey = j[@"idempotency_key"]; r(410, @{@"error": @"upload_expired"}, nil); }
            else {
                Check(![expiredKey isEqual:j[@"idempotency_key"]], @"An expired reservation gets a new durable key");
                r(400, @{@"error": @"invalid_upload"}, nil);
            }
        }];
        Check([queue enqueue:body device:device error:nil], @"Expired intent queues");
        Check(Wait(^BOOL(void) { return expiredCalls == 1 && !queue.uploading; }), @"Expiry pauses before retrying");
        [queue retry];
        Check(Wait(^BOOL(void) { return expiredCalls == 2 && !queue.uploading; }), @"Expiry can be retried");
        [queue discard:nil]; queue = nil;

        __block NSUInteger missingReserves = 0, missingCommits = 0;
        queue = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-b" transport:^(NSString *m, NSString *p, id j, NSData *b, CloudUploadReply r) {
            if ([p isEqual:@"/v1/uploads"]) { missingReserves++; r(201, @{@"upload": @{@"id": identifier, @"state": @"pending"}}, nil); }
            else if ([m isEqual:@"PUT"]) r(204, nil, nil);
            else { missingCommits++; r(missingCommits == 1 ? 0 : 404, @{@"error": @"not_found"}, nil); }
        }];
        [queue enqueue:body device:device error:nil];
        Check(Wait(^BOOL(void) { return missingCommits == 1 && !queue.uploading; }), @"Commit uncertainty stays durable");
        [queue retry];
        Check(Wait(^BOOL(void) { return missingCommits == 2 && !queue.uploading; }), @"Retry checks the original commit");
        Check(missingReserves == 1 && queue.count == 1, @"A deleted uncertain backup cannot be recreated by retry");
        [queue discard:nil]; queue = nil;

        queue = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-b" transport:^(NSString *m, NSString *p, id j, NSData *b, CloudUploadReply r) {
            if ([p isEqual:@"/v1/uploads"]) r(201, @{@"upload": @{@"id": identifier, @"state": @"committed"}}, nil);
            else if ([m isEqual:@"PUT"]) r(204, nil, nil);
            else r(200, @{@"snapshot": @{@"id": identifier, @"sha256": @"wrong", @"byte_count": @(body.length), @"device_id": device, @"schema_version": @1}}, nil);
        }];
        queue.committed = ^(NSData *acknowledgedBody) { acknowledged++; };
        [queue enqueue:body device:device error:nil];
        Check(Wait(^BOOL(void) { return queue.message != nil && !queue.uploading; }), @"Mismatched commit acknowledgement fails closed");
        Check(queue.count == 1 && acknowledged == 1, @"HTTP 200 alone cannot mark an inventory as backed up");
        [queue discard:nil]; queue = nil;

        NSURL *outside = [root URLByAppendingPathComponent:@"sentinel"];
        [@"unchanged" writeToURL:outside atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager removeItemAtURL:[root URLByAppendingPathComponent:@"queue.plist"] error:nil];
        [NSFileManager.defaultManager createSymbolicLinkAtURL:[root URLByAppendingPathComponent:@"queue.plist"] withDestinationURL:outside error:nil];
        [queue stop]; queue = nil;
        queue = [[CloudUploadQueue alloc] initWithDirectory:root owner:@"session-b" transport:transport];
        Check(queue.message != nil && ![queue enqueue:body device:device error:nil], @"Symlinked queue data fails closed");
        Check([queue discard:nil], @"Corrupt queue can be cleared without following the link");
        Check([[NSString stringWithContentsOfURL:outside encoding:NSUTF8StringEncoding error:nil] isEqual:@"unchanged"], @"No external file is changed");
        [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        printf("Cloud queue checks passed\n");
    }
    return 0;
}
