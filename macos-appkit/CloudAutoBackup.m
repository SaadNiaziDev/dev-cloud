#import "CloudAutoBackup.h"
#import "CloudAccount.h"
#import "CloudInventory.h"

@implementation CloudAutoBackup {
    CloudAccount *_account;
    NSDictionary *_seen;
    NSDictionary *_pending;
    NSString *_device;
    BOOL _scheduling;
}

- (instancetype)initWithAccount:(CloudAccount *)account {
    if ((self = [super init])) {
        _account = account;
        _device = account.deviceIdentifier;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(queueCleared:) name:CloudAccountUploadQueueClearedNotification object:account];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged:) name:CloudAccountDidChangeNotification object:account];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)completedScan:(NSDictionary *)report {
    if (report == _seen) return;
    _seen = report;
    if (!_account.automaticBackupsEnabled || _account.state != CloudSignedIn) return;
    _pending = report;
    [self enqueueIfReady];
}

- (void)queueCleared:(NSNotification *)notification { _pending = nil; }

- (void)accountChanged:(NSNotification *)notification {
    if (_account.state != CloudSignedIn || !_account.automaticBackupsEnabled || ![_device isEqual:_account.deviceIdentifier]) _pending = nil;
    _device = _account.deviceIdentifier;
    [self enqueueIfReady];
}

- (void)enqueueIfReady {
    if (_scheduling || !_pending || !_account.automaticBackupsEnabled || _account.state != CloudSignedIn || _account.busy) return;
    NSData *body = CloudInventoryData(_pending, NULL, NULL);
    NSString *fingerprint = body ? CloudInventoryFingerprint(body) : nil;
    if (!fingerprint) { _pending = nil; return; }
    if ([fingerprint isEqual:_account.lastBackedUpFingerprint] || [_account hasPendingInventoryFingerprint:fingerprint]) { _pending = nil; return; }
    NSDictionary *report = _pending;
    _scheduling = YES;
    [_account backUpReport:report completion:^(NSUInteger tools, NSError *error) {
        if (!error && self->_pending == report) self->_pending = nil;
        self->_scheduling = NO;
    }];
}
@end
