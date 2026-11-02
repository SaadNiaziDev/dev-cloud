#import <Foundation/Foundation.h>
#import "CloudAccount.h"
#import "CloudAutoBackup.h"
#import "CloudInventory.h"

@interface AutoFixture : CloudAccount
@property(nonatomic) BOOL optedIn;
@property(nonatomic) BOOL occupied;
@property(nonatomic) BOOL signedIn;
@property(nonatomic) NSUInteger capacity;
@property(nonatomic, copy) NSString *fixtureDevice;
@property(nonatomic, copy) NSString *committedFingerprint;
@property(nonatomic, strong) NSMutableArray *queued;
@property(nonatomic, strong) NSMutableSet *pending;
@end
@implementation AutoFixture
- (instancetype)init {
    if ((self = [super initWithBaseURL:nil keychainService:@"dev.devcloud.auto.fixture"])) {
        _capacity = 5; _signedIn = YES; _fixtureDevice = NSUUID.UUID.UUIDString;
        _queued = [NSMutableArray array]; _pending = [NSMutableSet set];
    }
    return self;
}
- (CloudState)state { return _signedIn ? CloudSignedIn : CloudSignedOut; }
- (BOOL)busy { return _occupied; }
- (BOOL)automaticBackupsEnabled { return _optedIn; }
- (NSString *)deviceIdentifier { return _fixtureDevice; }
- (NSString *)lastBackedUpFingerprint { return _committedFingerprint; }
- (BOOL)hasPendingInventoryFingerprint:(NSString *)fingerprint { return [_pending containsObject:fingerprint]; }
- (void)changed { [NSNotificationCenter.defaultCenter postNotificationName:CloudAccountDidChangeNotification object:self]; }
- (void)setAutomaticBackupsEnabled:(BOOL)enabled { _optedIn = enabled; [self changed]; }
- (void)backUpReport:(NSDictionary *)report completion:(void (^)(NSUInteger, NSError *))completion {
    if (!_capacity) { completion(0, [NSError errorWithDomain:@"fixture" code:1 userInfo:nil]); return; }
    [_queued addObject:report];
    [_pending addObject:CloudInventoryFingerprint(CloudInventoryData(report, NULL, NULL))];
    [self changed];
    completion(1, nil);
}
@end

static void Check(BOOL condition, NSString *message) { if (!condition) { fprintf(stderr, "FAIL %s\n", message.UTF8String); exit(1); } }
static NSDictionary *Report(NSUInteger stamp, NSString *version, BOOL reversed) {
    NSArray *tools = @[@{@"canonical_tool_id": @"nodejs", @"version": version, @"installation_provider": @"nvm"},
                       @{@"canonical_tool_id": @"git", @"version": @"2.4", @"installation_provider": @"macos_system"}];
    return @{@"schema_version": @1, @"observed_at_unix_seconds": @(stamp),
             @"host": @{@"platform": @"macos", @"architecture": @"aarch64", @"os_version": @"14"},
             @"resources": reversed ? tools.reverseObjectEnumerator.allObjects : tools};
}
int main(void) {
    @autoreleasepool {
        AutoFixture *account = [AutoFixture new];
        CloudAutoBackup *automatic = [[CloudAutoBackup alloc] initWithAccount:account];
        NSDictionary *old = Report(1, @"1", NO);
        [automatic completedScan:old];
        Check(account.queued.count == 0, @"No automatic upload without consent");
        [account setAutomaticBackupsEnabled:YES];
        [automatic completedScan:old];
        Check(account.queued.count == 0, @"Enabling does not upload a previously observed scan");
        NSDictionary *first = Report(2, @"1", NO);
        [automatic completedScan:first];
        Check(account.queued.count == 1, @"The first fresh scan queues after opt-in");
        [automatic completedScan:Report(3, @"1", YES)];
        Check(account.queued.count == 1, @"Time and resource ordering do not duplicate a pending backup");
        account.committedFingerprint = CloudInventoryFingerprint(CloudInventoryData(first, NULL, NULL));
        [account.pending removeAllObjects]; [account changed];
        NSMutableDictionary *private = [Report(4, @"1", NO) mutableCopy];
        private[@"warnings"] = @[@"/Users/private/workspace"];
        private[@"local"] = @{@"config": @"not uploaded"};
        [automatic completedScan:private];
        Check(account.queued.count == 1, @"Already committed inventory ignores private metadata changes");
        [automatic completedScan:Report(5, @"2", NO)];
        Check(account.queued.count == 2, @"A version change queues a new backup");
        account.occupied = YES;
        [automatic completedScan:Report(6, @"3", NO)];
        NSDictionary *latest = Report(7, @"4", NO);
        [automatic completedScan:latest];
        Check(account.queued.count == 2, @"Busy uploads defer automatic scheduling");
        account.occupied = NO; [account changed];
        Check(account.queued.count == 3 && account.queued.lastObject == latest, @"Only the latest waiting scan queues when idle");
        account.occupied = YES;
        [automatic completedScan:Report(8, @"5", NO)];
        [account setAutomaticBackupsEnabled:NO];
        account.occupied = NO; [account changed];
        Check(account.queued.count == 3, @"Opt-out clears unscheduled work");
        [account setAutomaticBackupsEnabled:YES];
        account.capacity = 0;
        latest = Report(9, @"6", NO);
        [automatic completedScan:latest];
        Check(account.queued.count == 3, @"A full queue does not claim acceptance");
        account.capacity = 5; [account changed];
        Check(account.queued.count == 4 && account.queued.lastObject == latest, @"Waiting inventory is retried when capacity returns");
        account.capacity = 0;
        [automatic completedScan:Report(10, @"7", NO)];
        [NSNotificationCenter.defaultCenter postNotificationName:CloudAccountUploadQueueClearedNotification object:account];
        account.capacity = 5; [account changed];
        Check(account.queued.count == 4, @"Manual queue clearing also drops waiting automatic intents");
        account.occupied = YES;
        [automatic completedScan:Report(10, @"7", NO)];
        account.signedIn = NO; [account changed];
        account.fixtureDevice = NSUUID.UUID.UUIDString; account.optedIn = NO;
        account.signedIn = YES; account.occupied = NO; [account changed];
        [automatic completedScan:Report(11, @"8", NO)];
        Check(account.queued.count == 4, @"A new session cannot inherit consent or pending work");
        printf("Automatic cloud backup checks passed\n");
    }
    return 0;
}
