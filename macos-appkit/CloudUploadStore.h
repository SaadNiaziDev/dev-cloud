#import <Foundation/Foundation.h>

@interface CloudUploadStore : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory owner:(NSString *)owner;
- (NSArray<NSDictionary *> *)load:(NSError **)error;
- (BOOL)save:(NSArray<NSDictionary *> *)jobs error:(NSError **)error;
@end
