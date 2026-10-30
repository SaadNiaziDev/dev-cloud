#import <Foundation/Foundation.h>

@interface SnapshotComparison : NSObject
+ (NSDictionary *)fromInventory:(NSDictionary *)before toInventory:(NSDictionary *)after;
@end
