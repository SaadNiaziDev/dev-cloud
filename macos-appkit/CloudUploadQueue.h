#import <Foundation/Foundation.h>

typedef void (^CloudUploadReply)(NSInteger status, id payload, NSHTTPURLResponse *response);
typedef void (^CloudUploadTransport)(NSString *method, NSString *path, id json, NSData *body, CloudUploadReply reply);

@interface CloudUploadQueue : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory owner:(NSString *)owner transport:(CloudUploadTransport)transport;
@property(nonatomic, readonly) NSUInteger count;
@property(nonatomic, readonly) BOOL uploading;
@property(nonatomic, copy, readonly) NSString *message;
@property(nonatomic, copy) void (^changed)(void);
@property(nonatomic, copy) void (^committed)(void);
- (BOOL)enqueue:(NSData *)body device:(NSString *)device error:(NSError **)error;
- (void)start;
- (void)retry;
- (void)stop;
- (BOOL)discard:(NSError **)error;
@end
