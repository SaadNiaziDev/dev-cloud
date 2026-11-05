#import <Foundation/Foundation.h>

NSArray<NSDictionary *> *RecoveryPlan(NSData *backup, NSDictionary *current, NSError **error);
NSString *RecoveryPlanDescription(NSArray<NSDictionary *> *plan);
