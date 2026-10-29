#import <Cocoa/Cocoa.h>
#import "ScanModel.h"

// The menu bar dropdown: monitoring switch, scan status, recent warnings, and
// commands. Commands are sent to `target`: openMainWindow:, scanNow:,
// exportReport:, openSettings:, and quit:.
@interface StatusMenu : NSObject

- (instancetype)initWithModel:(ScanModel *)model statusItem:(NSStatusItem *)item target:(id)target;
@property(nonatomic, strong, readonly) NSPanel *panel;
- (void)toggle;
- (void)show;
- (void)close;

@end
