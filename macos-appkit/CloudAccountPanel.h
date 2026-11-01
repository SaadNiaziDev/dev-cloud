#import <AppKit/AppKit.h>
@class CloudAccount;

@interface CloudAccountPanel : NSStackView
- (instancetype)initWithAccount:(CloudAccount *)account notice:(void (^)(NSString *title, NSString *detail))notice;
@end
