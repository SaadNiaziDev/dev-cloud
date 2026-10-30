#import <Foundation/Foundation.h>

@interface SnapshotStore : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory;
- (NSArray<NSDictionary *> *)snapshotsWithError:(NSError **)error;
- (BOOL)captureReport:(NSDictionary *)report error:(NSError **)error;
- (NSData *)exportSnapshot:(NSString *)identifier error:(NSError **)error;
- (NSDictionary *)compareSnapshot:(NSString *)before toSnapshot:(NSString *)after error:(NSError **)error;
@end
