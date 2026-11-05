#import <Foundation/Foundation.h>

// A Brewfile for setting up another Mac from a scan, snapshot or cloud backup.
// DevCloud never runs it. Returns nil when the inventory is invalid.
NSString *SetupBrewfile(NSDictionary *inventory, NSUInteger *entries, NSError **error);
