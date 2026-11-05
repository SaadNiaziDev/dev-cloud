#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SetupItemState) { SetupItemWaiting, SetupItemInstalling, SetupItemDone, SetupItemFailed };

// Runs `brew bundle install` for items the user approved, from a Brewfile DevCloud writes
// itself. Homebrew is used only from its standard install locations. Nothing runs
// without `start`, and only one run at a time. Callbacks arrive on the main thread.
@interface SetupInstaller : NSObject
// Homebrew's executable, or nil when Homebrew isn't installed.
+ (NSURL *)homebrew;
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) BOOL finished;
@property(nonatomic, readonly) BOOL succeeded;
@property(nonatomic, copy, readonly) NSString *lastLine;
@property(nonatomic, readonly) NSUInteger completed;
@property(nonatomic, readonly) NSUInteger total;
@property(nonatomic, copy) void (^onChange)(void);
- (SetupItemState)stateFor:(NSString *)name;
- (BOOL)start:(NSError **)error;
- (void)cancel;
// The run's full output, newest last.
- (NSString *)log;
@end
