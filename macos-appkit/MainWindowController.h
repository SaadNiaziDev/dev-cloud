#import <Cocoa/Cocoa.h>
#import "ScanModel.h"

@interface MainWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSToolbarDelegate, NSSearchFieldDelegate, NSMenuDelegate>

- (instancetype)initWithModel:(ScanModel *)model;
- (void)selectSectionAtIndex:(NSUInteger)index;
- (void)focusSearch;
- (void)exportReport:(id)sender;
- (void)approveWorkspace:(id)sender;

+ (NSArray<NSString *> *)sectionTitles;

@end
