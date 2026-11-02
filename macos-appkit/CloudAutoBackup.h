#import <Foundation/Foundation.h>
@class CloudAccount;

@interface CloudAutoBackup : NSObject
- (instancetype)initWithAccount:(CloudAccount *)account;
// Call only for successful, freshly completed scans, never loaded history.
- (void)completedScan:(NSDictionary *)report;
@end
