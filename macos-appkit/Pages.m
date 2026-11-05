#import "Pages.h"
#import "SetupFile.h"

void SaveSetupFile(NSWindow *window, id<PageHost> host, NSDictionary *inventory) {
    NSError *error = nil;
    NSUInteger entries = 0;
    NSString *text = SetupBrewfile(inventory, &entries, &error);
    if (!text) { [host toast:@"Couldn’t create setup file" detail:error.localizedDescription]; return; }
    if (!entries) { [host toast:@"Nothing to set up" detail:@"No Homebrew tools, apps or extensions were found"]; return; }
    NSSavePanel *panel = NSSavePanel.savePanel;
    panel.nameFieldStringValue = @"Brewfile";
    panel.message = @"Copy this file to the new Mac, review it, then run `brew bundle --file Brewfile`. DevCloud never runs it.";
    [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSError *writeError = nil;
        if ([text writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&writeError])
            [host toast:@"Setup file saved" detail:[NSString stringWithFormat:@"%@ · %lu entries", panel.URL.lastPathComponent, (unsigned long)entries]];
        else [host toast:@"Couldn’t save setup file" detail:writeError.localizedDescription];
    }];
}

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
            @{@"title": @"Backup", @"subtitle": @"Inventory backups in your DevCloud account", @"symbol": @"icloud.and.arrow.up", @"group": @"Monitoring"},
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
