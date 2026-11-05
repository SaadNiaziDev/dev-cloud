#import <Cocoa/Cocoa.h>

@class CloudAccount;

// The only window shown until the account is signed in. DevCloud does not scan,
// monitor or show inventory without a signed-in account.
@interface SignInWindowController : NSWindowController
- (instancetype)initWithAccount:(CloudAccount *)account;
@end
