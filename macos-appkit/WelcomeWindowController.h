#import <Cocoa/Cocoa.h>

@interface WelcomeWindowController : NSWindowController
- (instancetype)initWithCloudAvailable:(BOOL)available completion:(void (^)(BOOL signIn))completion;
@end
