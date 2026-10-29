#import <Cocoa/Cocoa.h>
#import "Pages.h"

@interface MainWindowController : NSWindowController <PageHost>

- (instancetype)initWithModel:(ScanModel *)model;
@property(nonatomic, readonly) Page currentPage;
- (void)focusSearch;

@end
