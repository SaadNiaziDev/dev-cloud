#import <Cocoa/Cocoa.h>
#import "Inventory.h"
#import "ScanModel.h"
#import "Theme.h"

// Title, subtitle, symbol, and sidebar group for each page, in sidebar order.
NSArray<NSDictionary *> *PageCatalog(void);

// What approving a workspace folder lets the scanner read, and what it never reads.
NSArray<NSString *> *WorkspaceReadScope(void);
NSArray<NSString *> *WorkspaceNeverRead(void);

@protocol PageHost <NSObject>
@property(nonatomic, strong, readonly) ScanModel *model;
- (void)showPage:(Page)page;
- (void)showTool:(NSString *)identifier;
- (void)scanNow:(id)sender;
- (void)exportReport:(id)sender;
- (void)approveWorkspace:(id)sender;
- (void)toast:(NSString *)title detail:(NSString *)detail;
@end

// Asks where to save a Brewfile for another Mac, then writes it. Never runs it.
void SaveSetupFile(NSWindow *window, id<PageHost> host, NSDictionary *inventory);

@interface PageView : NSView
- (instancetype)initWithHost:(id<PageHost>)host;
@property(nonatomic, weak, readonly) id<PageHost> host;
@property(nonatomic, readonly) ScanModel *model;
@property(nonatomic, readonly) Inventory *inventory;
// Called on every model change; rebuilds only when `signature` differs from the last build.
- (void)reload;
- (NSString *)signature;
- (void)rebuild;
@end

@interface OverviewPage : PageView
@end

@interface ToolsPage : PageView
- (void)selectTool:(NSString *)identifier;
- (void)focusSearch;
@end

@interface WorkspacesPage : PageView
@end

@interface ConfigurationsPage : PageView
@end

@interface ActivityPage : PageView
@end

@interface SnapshotsPage : PageView
@end

@interface SetupPage : PageView
@end

@interface BackupPage : PageView
@end

@interface SettingsPage : PageView
@end
