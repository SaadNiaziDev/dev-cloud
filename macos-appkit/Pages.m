#import "Pages.h"

NSArray<NSDictionary *> *PageCatalog(void) {
    static NSArray *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        catalog = @[
            @{@"title": @"Overview", @"subtitle": @"Your development environment at a glance", @"symbol": @"square.grid.2x2", @"group": @"Inventory"},
            @{@"title": @"Tools", @"subtitle": @"Installed tools, versions and providers", @"symbol": @"shippingbox", @"group": @"Inventory"},
            @{@"title": @"Workspaces", @"subtitle": @"Folders you approved for metadata discovery", @"symbol": @"folder", @"group": @"Inventory"},
            @{@"title": @"Configurations", @"subtitle": @"Discoverable configuration metadata", @"symbol": @"doc.badge.gearshape", @"group": @"Inventory"},
            @{@"title": @"Activity", @"subtitle": @"Scans and detected changes", @"symbol": @"waveform.path.ecg", @"group": @"Monitoring"},
            @{@"title": @"Snapshots", @"subtitle": @"Saved inventory on this Mac", @"symbol": @"camera", @"group": @"Monitoring"},
            @{@"title": @"Settings", @"subtitle": @"Monitoring, notifications and export", @"symbol": @"gearshape", @"group": @""},
        ];
    });
    return catalog;
}

@implementation PageView {
    NSString *_builtSignature;
}

- (instancetype)initWithHost:(id<PageHost>)host {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _host = host;
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (ScanModel *)model { return self.host.model; }
- (Inventory *)inventory { return [Inventory inventoryForModel:self.model]; }

- (void)reload {
    NSString *signature = [self signature];
    if (signature && [signature isEqual:_builtSignature]) return;
    _builtSignature = signature;
    [self rebuild];
}

- (NSString *)signature { return nil; }
- (void)rebuild {}

@end
