#import <Foundation/Foundation.h>

extern NSNotificationName const CloudAccountDidChangeNotification;
extern NSNotificationName const CloudAccountUploadQueueClearedNotification;

typedef NS_ENUM(NSInteger, CloudState) { CloudUnavailable, CloudSignedOut, CloudSigningIn, CloudSignedIn };

// The API origin compiled into this build, or nil when the build has none. Only
// HTTPS, or HTTP to this Mac for local development, is accepted.
NSURL *CloudBaseURL(void);
NSURL *CloudValidatedURL(NSString *value);

// One DevCloud cloud account on this Mac. The session token lives only in Keychain
// and is sent only to the API origin; redirects are refused. Callbacks and change
// notifications arrive on the main thread.
@interface CloudAccount : NSObject
+ (instancetype)shared;
- (instancetype)initWithBaseURL:(NSURL *)baseURL keychainService:(NSString *)service;

@property(nonatomic, readonly) CloudState state;
@property(nonatomic, readonly) BOOL busy;
@property(nonatomic, readonly) NSUInteger pendingBackups;
@property(nonatomic, readonly) BOOL automaticBackupsEnabled;
@property(nonatomic, copy, readonly) NSString *lastBackedUpFingerprint;
- (void)setAutomaticBackupsEnabled:(BOOL)enabled;
- (BOOL)hasPendingInventoryFingerprint:(NSString *)fingerprint;
@property(nonatomic, copy, readonly) NSString *uploadMessage;
@property(nonatomic, copy, readonly) NSString *errorMessage;
@property(nonatomic, copy, readonly) NSString *email;
@property(nonatomic, copy, readonly) NSString *deviceIdentifier;
// Sign-in code to show while waiting, formatted `ABCD-EFGH`, and when it expires.
@property(nonatomic, copy, readonly) NSString *userCode;
@property(nonatomic, copy, readonly) NSDate *codeExpiry;
// Connected Macs: identifier, name, this_mac.
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *devices;
// Newest first: identifier, created (NSDate), byte_count, sha256, device_name, this_mac.
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *backups;

// Loads a stored session and checks it is still valid.
- (void)restore;
- (void)beginSignIn;
- (void)openVerificationPage;
- (void)cancelSignIn;
// Finishes sign-in with a session token: registers this Mac, then keeps the session in Keychain.
- (void)signInWithToken:(NSString *)token;
// Removes this Mac from the account, which ends its session. Backups stay.
- (void)signOut;
- (void)signOutLocally;
- (void)refreshBackups;
- (void)revokeDevice:(NSString *)identifier completion:(void (^)(NSError *error))completion;
- (void)deleteAccountWithConfirmation:(NSString *)confirmation completion:(void (^)(NSError *error))completion;
// Completion acknowledges a durable local queue entry; remote backups appear only after commit.
- (void)backUpReport:(NSDictionary *)report completion:(void (^)(NSUInteger tools, NSError *error))completion;
- (void)retryPendingBackups;
- (void)discardPendingBackups;
// Downloaded bytes are checked against the recorded SHA-256 before they are returned.
- (void)downloadBackup:(NSString *)identifier completion:(void (^)(NSData *data, NSError *error))completion;
- (void)deleteBackup:(NSString *)identifier completion:(void (^)(NSError *error))completion;
@end
