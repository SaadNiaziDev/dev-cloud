#import "CloudAccount.h"
#import "CloudInventory.h"
#import "CloudUploadQueue.h"
#import <AppKit/AppKit.h>
#import <Security/Security.h>

NSNotificationName const CloudAccountDidChangeNotification = @"CloudAccountDidChangeNotification";
NSNotificationName const CloudAccountUploadQueueClearedNotification = @"CloudAccountUploadQueueClearedNotification";

// Empty unless the build passes -DDEVCLOUD_API_URL='"https://…"'. No address is committed to source.
#ifndef DEVCLOUD_API_URL
#define DEVCLOUD_API_URL ""
#endif

static NSString *const ClientIdentifier = @"devcloud-macos";
static const NSUInteger MaxResponseBytes = 2 * 1024 * 1024;

NSURL *CloudValidatedURL(NSString *value) {
    NSURLComponents *components = value.length ? [NSURLComponents componentsWithString:value] : nil;
    NSString *scheme = components.scheme.lowercaseString, *host = components.host.lowercaseString;
    BOOL loopback = [host isEqual:@"127.0.0.1"] || [host isEqual:@"localhost"];
    if (!host.length || !([scheme isEqual:@"https"] || ([scheme isEqual:@"http"] && loopback))) return nil;
    if (components.user || components.password || components.query || components.fragment || !(components.path.length == 0 || [components.path isEqual:@"/"])) return nil;
    components.path = @"";
    return components.URL;
}

NSURL *CloudBaseURL(void) {
    NSString *value = @"" DEVCLOUD_API_URL;
#ifdef DEVCLOUD_TESTING
    value = NSProcessInfo.processInfo.environment[@"DEVCLOUD_API_URL"] ?: value;
#endif
    return CloudValidatedURL(value);
}

// A field of a decoded JSON object, or nil when the value is not an object.
static id Get(id object, NSString *key) {
    return [object isKindOfClass:NSDictionary.class] ? object[key] : nil;
}

static NSError *CloudError(NSString *message) {
    return [NSError errorWithDomain:@"DevCloudCloud" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL SameOrigin(NSURL *a, NSURL *b) {
    return [a.scheme.lowercaseString isEqual:b.scheme.lowercaseString] && [a.host.lowercaseString isEqual:b.host.lowercaseString] &&
           (a.port ?: @0).integerValue == (b.port ?: @0).integerValue;
}

// The server allows any printable name up to 80 characters.
static NSString *DeviceName(void) {
    NSString *name = NSHost.currentHost.localizedName ?: @"";
    NSMutableCharacterSet *hidden = [NSCharacterSet.controlCharacterSet mutableCopy];
    [hidden formUnionWithCharacterSet:NSCharacterSet.illegalCharacterSet];
    name = [[[name componentsSeparatedByCharactersInSet:hidden] componentsJoinedByString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (name.length > 80) name = [name substringToIndex:[name rangeOfComposedCharacterSequenceAtIndex:80].location];
    return name.length ? name : @"Mac";
}

static NSString *Architecture(void) {
#if defined(__arm64__)
    return @"aarch64";
#else
    return @"x86_64";
#endif
}

@interface CloudAccount () <NSURLSessionTaskDelegate>
@property(nonatomic) CloudState state;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL automaticBackupsEnabled;
@property(nonatomic, copy) NSString *lastBackedUpFingerprint;
@property(nonatomic, copy) NSString *errorMessage;
@property(nonatomic, copy) NSString *email;
@property(nonatomic, copy) NSString *deviceIdentifier;
@property(nonatomic, copy) NSString *userCode;
@property(nonatomic, copy) NSDate *codeExpiry;
@property(nonatomic, copy) NSArray<NSDictionary *> *backups;
@property(nonatomic, copy) NSArray<NSDictionary *> *devices;
@end

@implementation CloudAccount {
    CloudUploadQueue *_uploadQueue;
    NSURL *_baseURL;
    NSString *_service;
    NSURLSession *_session;
    NSString *_token;
    NSString *_deviceCode;
    NSURL *_verificationURL;
    NSTimeInterval _interval;
    NSUInteger _signInGeneration;
}

@synthesize busy = _busy;

- (BOOL)busy { return _busy || _uploadQueue.uploading; }
- (NSUInteger)pendingBackups { return _uploadQueue.count; }
- (NSString *)uploadMessage { return _uploadQueue.message; }

+ (instancetype)shared {
    static CloudAccount *account;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ account = [[CloudAccount alloc] initWithBaseURL:CloudBaseURL() keychainService:@"dev.devcloud.desktop.cloud"]; });
    return account;
}

- (instancetype)initWithBaseURL:(NSURL *)baseURL keychainService:(NSString *)service {
    self = [super init];
    if (self) {
        _baseURL = baseURL;
        _service = service;
        _backups = @[];
        _devices = @[];
        _state = baseURL ? CloudSignedOut : CloudUnavailable;
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
        configuration.HTTPShouldSetCookies = NO;
        configuration.URLCache = nil;
        configuration.URLCredentialStorage = nil;
        configuration.timeoutIntervalForRequest = 20;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:NSOperationQueue.mainQueue];
    }
    return self;
}

- (void)changed {
    [NSNotificationCenter.defaultCenter postNotificationName:CloudAccountDidChangeNotification object:self];
}

#pragma mark Keychain

- (NSDictionary *)keychainQuery {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService: _service,
             (__bridge id)kSecAttrAccount: _baseURL.absoluteString};
}

- (NSDictionary *)storedSession {
    NSMutableDictionary *query = [self.keychainQuery mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || !result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    NSDictionary *stored = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [stored isKindOfClass:NSDictionary.class] && [stored[@"token"] isKindOfClass:NSString.class] && [stored[@"device_id"] isKindOfClass:NSString.class] ? stored : nil;
}

- (BOOL)storeSession {
    if (!_token.length || !self.deviceIdentifier.length || !_baseURL || !_service.length) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"token": _token, @"device_id": self.deviceIdentifier, @"email": self.email ?: @"", @"automatic_backups": @(_automaticBackupsEnabled), @"last_backup_fingerprint": self.lastBackedUpFingerprint ?: @""} options:0 error:nil];
    NSDictionary *values = @{(__bridge id)kSecValueData: data};
    OSStatus update = SecItemUpdate((__bridge CFDictionaryRef)self.keychainQuery, (__bridge CFDictionaryRef)values);
    if (update == errSecSuccess) return YES;
    if (update != errSecItemNotFound) return NO;
    NSMutableDictionary *item = [self.keychainQuery mutableCopy];
    item[(__bridge id)kSecValueData] = data;
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    item[(__bridge id)kSecAttrLabel] = @"DevCloud cloud session";
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}

- (void)forgetSession:(NSString *)message {
    SecItemDelete((__bridge CFDictionaryRef)self.keychainQuery);
    BOOL hadPending = _uploadQueue.count > 0;
    _token = nil;
    NSError *clearError = nil;
    if (_uploadQueue && ![_uploadQueue discard:&clearError]) message = @"Signed out. Pending upload data could not be cleared from this Mac.";
    else if (message && hadPending) message = [message stringByAppendingString:@" Pending uploads on this Mac were cleared."];
    _uploadQueue = nil;
    self.deviceIdentifier = nil;
    self.email = nil;
    self.backups = @[];
    self.devices = @[];
    _automaticBackupsEnabled = NO;
    self.lastBackedUpFingerprint = nil;
    self.busy = NO;
    self.state = _baseURL ? CloudSignedOut : CloudUnavailable;
    self.errorMessage = message;
    [self changed];
}

#pragma mark Requests

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil);
}

- (void)send:(NSString *)method path:(NSString *)path json:(id)json body:(NSData *)body token:(NSString *)token
  completion:(void (^)(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path relativeToURL:_baseURL]];
    request.HTTPMethod = method;
    if (json) body = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    if (body) {
        request.HTTPBody = body;
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    if (token) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (error || !http || data.length > MaxResponseBytes) { completion(0, nil, nil, nil); return; }
        id payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        completion(http.statusCode, payload, data, http);
    }] resume];
}

// Plain-language failure for an API response; 401 also ends the stored session.
- (NSString *)failure:(NSInteger)status payload:(id)payload response:(NSHTTPURLResponse *)response {
    NSString *code = Get(payload, @"error");
    if (status == 0) return @"Can’t reach DevCloud cloud. Check your connection and try again.";
    if (status == 401) { [self forgetSession:@"Your session ended. Sign in again to keep backing up."]; return self.errorMessage; }
    if ([code isEqual:@"rate_limit_exceeded"]) return [NSString stringWithFormat:@"Too many requests. Try again in %@ seconds.", [response valueForHTTPHeaderField:@"Retry-After"] ?: @"a few"];
    if ([code isEqual:@"recent_auth_required"]) return @"Sign out and sign in again, then confirm account deletion again. Signing out clears pending uploads.";
    if ([code isEqual:@"quota_exceeded"]) return @"Backup storage for this account is full. Delete older backups to make room.";
    if ([code isEqual:@"device_quota_exceeded"]) return @"This account already has the most Macs it can hold. Sign out on another Mac first.";
    if (status == 409 || status == 410) return @"The backup didn’t finish. Try again.";
    if (status == 404) return @"That backup no longer exists.";
    return @"DevCloud cloud is unavailable right now. Try again later.";
}

#pragma mark Sign-in

- (void)restore {
    if (!_baseURL || _token || self.state == CloudSigningIn) return;
    NSDictionary *stored = [self storedSession];
    if (!stored) return;
    _token = stored[@"token"];
    self.deviceIdentifier = stored[@"device_id"];
    self.email = [stored[@"email"] length] ? stored[@"email"] : nil;
    _automaticBackupsEnabled = [stored[@"automatic_backups"] isKindOfClass:NSNumber.class] && [stored[@"automatic_backups"] boolValue] && ![NSUserDefaults.standardUserDefaults boolForKey:self.automaticOptOutKey];
    self.lastBackedUpFingerprint = [stored[@"last_backup_fingerprint"] isKindOfClass:NSString.class] ? stored[@"last_backup_fingerprint"] : nil;
    self.state = CloudSignedIn;
    [self restoreUploadQueue];
    [self changed];
    [self refreshBackups];
}

- (void)beginSignIn {
    if (!_baseURL || self.busy || self.state == CloudSignedIn) return;
    NSUInteger generation = ++_signInGeneration;
    self.busy = YES;
    self.errorMessage = nil;
    [self changed];
    [self send:@"POST" path:@"/api/auth/device/code" json:@{@"client_id": ClientIdentifier} body:nil token:nil completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
        if (generation != self->_signInGeneration) return;
        self.busy = NO;
        NSString *deviceCode = Get(payload, @"device_code"), *userCode = Get(payload, @"user_code"), *page = Get(payload, @"verification_uri_complete");
        NSURL *verification = [page isKindOfClass:NSString.class] ? [NSURL URLWithString:page] : nil;
        // The page we open must be on our own API origin, whatever the response says.
        if (status != 200 || ![deviceCode isKindOfClass:NSString.class] || ![userCode isKindOfClass:NSString.class] || userCode.length != 8 || !verification || !SameOrigin(verification, self->_baseURL)) {
            self.errorMessage = status == 200 ? @"DevCloud cloud sent an unexpected sign-in response." : [self failure:status payload:payload response:response];
            [self changed];
            return;
        }
        self->_deviceCode = deviceCode;
        self->_verificationURL = verification;
        self->_interval = MAX(5, [Get(payload, @"interval") doubleValue]);
        self.userCode = [NSString stringWithFormat:@"%@-%@", [userCode substringToIndex:4], [userCode substringFromIndex:4]];
        self.codeExpiry = [NSDate dateWithTimeIntervalSinceNow:MAX(60, MIN(1800, [Get(payload, @"expires_in") doubleValue] ?: 600))];
        self.state = CloudSigningIn;
        [self changed];
        [self openVerificationPage];
        [self schedulePoll:generation];
    }];
}

- (void)openVerificationPage {
    if (self.state != CloudSigningIn || !_verificationURL) return;
#ifdef DEVCLOUD_TESTING
    if (NSProcessInfo.processInfo.environment[@"DEVCLOUD_NO_BROWSER"]) return;
#endif
    [NSWorkspace.sharedWorkspace openURL:_verificationURL];
}

- (void)cancelSignIn {
    if (self.state != CloudSigningIn) return;
    _signInGeneration++;
    [self endSignIn:nil];
}

- (void)endSignIn:(NSString *)message {
    _deviceCode = nil;
    _verificationURL = nil;
    self.userCode = nil;
    self.codeExpiry = nil;
    self.busy = NO;
    self.state = CloudSignedOut;
    self.errorMessage = message;
    [self changed];
}

- (void)schedulePoll:(NSUInteger)generation {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self->_signInGeneration || self.state != CloudSigningIn) return;
        if ([self.codeExpiry timeIntervalSinceNow] <= 0) { [self endSignIn:@"The sign-in code expired. Start again."]; return; }
        NSDictionary *body = @{@"grant_type": @"urn:ietf:params:oauth:grant-type:device_code", @"device_code": self->_deviceCode, @"client_id": ClientIdentifier};
        [self send:@"POST" path:@"/api/auth/device/token" json:body body:nil token:nil completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
            if (generation != self->_signInGeneration || self.state != CloudSigningIn) return;
            NSString *token = Get(payload, @"access_token"), *code = Get(payload, @"error");
            if (status == 200 && [token isKindOfClass:NSString.class] && token.length) {
                self->_deviceCode = nil;
                [self signInWithToken:token];
            } else if (status == 0 || [code isEqual:@"authorization_pending"] || [code isEqual:@"slow_down"]) {
                if ([code isEqual:@"slow_down"]) self->_interval += 5;
                [self schedulePoll:generation];
            } else {
                [self endSignIn:[code isEqual:@"access_denied"] ? @"Sign-in was denied in the browser." :
                                ([code isEqual:@"expired_token"] ? @"The sign-in code expired. Start again." : [self failure:status payload:payload response:response])];
            }
        }];
    });
}

- (void)signInWithToken:(NSString *)token {
    self.busy = YES;
    [self changed];
    NSDictionary *device = @{@"name": DeviceName(), @"platform": @"macos", @"architecture": Architecture()};
    [self send:@"POST" path:@"/v1/devices" json:device body:nil token:token completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
        NSString *identifier = Get(Get(payload, @"device"), @"id");
        if (status != 201 || ![identifier isKindOfClass:NSString.class]) {
            [self endSignIn:status == 401 ? @"Sign-in didn’t complete. Start again." : [self failure:status payload:payload response:response]];
            return;
        }
        self->_automaticBackupsEnabled = NO;
        self.lastBackedUpFingerprint = nil;
        self->_token = token;
        self.deviceIdentifier = identifier;
        [self send:@"GET" path:@"/api/auth/get-session" json:nil body:nil token:token completion:^(NSInteger status, id session, NSData *data, NSHTTPURLResponse *response) {
            NSString *email = Get(Get(session, @"user"), @"email");
            self.email = [email isKindOfClass:NSString.class] ? email : nil;
            self->_verificationURL = nil;
            self.userCode = nil;
            self.codeExpiry = nil;
            self.busy = NO;
            self.state = CloudSignedIn;
            [self restoreUploadQueue];
            self.errorMessage = [self storeSession] ? nil : @"Signed in, but Keychain refused to save the session. You’ll need to sign in again next time.";
            [self changed];
            [self refreshBackups];
        }];
    }];
}

- (void)signOut {
    [self revokeDevice:self.deviceIdentifier completion:^(NSError *error) {}];
}

- (void)revokeDevice:(NSString *)identifier completion:(void (^)(NSError *))completion {
    if (self.state != CloudSignedIn || self.busy) { completion(CloudError(@"Wait for the current operation to finish.")); return; }
    BOOL current = [identifier isEqual:self.deviceIdentifier];
    BOOL known = current;
    for (NSDictionary *device in self.devices) if ([device[@"identifier"] isEqual:identifier]) known = YES;
    if (!known || ![[NSUUID alloc] initWithUUIDString:identifier]) { completion(CloudError(@"Refresh the connected Macs list and try again.")); return; }
    self.busy = YES;
    self.errorMessage = nil;
    [_uploadQueue stop];
    [self changed];
    NSString *token = _token;
    [self send:@"DELETE" path:[@"/v1/devices/" stringByAppendingString:identifier] json:nil body:nil token:token
        completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
        if (token != self->_token) { completion(CloudError(@"The signed-in account changed.")); return; }
        if (current && (status == 204 || status == 401 || status == 404)) { [self forgetSession:nil]; completion(nil); return; }
        self.busy = NO;
        NSError *error = nil;
        if (status != 204 && status != 404) error = CloudError([self failure:status payload:payload response:response]);
        self.errorMessage = error.localizedDescription;
        if (self.state == CloudSignedIn) {
            [self->_uploadQueue start];
            if (!error) [self refreshBackups];
        }
        [self changed];
        completion(error);
    }];
}

- (void)deleteAccountWithConfirmation:(NSString *)confirmation completion:(void (^)(NSError *))completion {
    if (![confirmation isEqual:@"delete my account"]) { completion(CloudError(@"Type delete my account to confirm.")); return; }
    if (self.state != CloudSignedIn || self.busy) { completion(CloudError(@"Sign in and wait for the current operation to finish.")); return; }
    self.busy = YES;
    self.errorMessage = nil;
    [_uploadQueue stop];
    [self changed];
    NSString *token = _token;
    [self send:@"DELETE" path:@"/v1/account" json:@{@"confirmation": confirmation} body:nil token:token
        completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
        if (token != self->_token) { completion(CloudError(@"The signed-in account changed.")); return; }
        if (status == 202 && [Get(payload, @"status") isEqual:@"deletion_queued"]) { [self forgetSession:nil]; completion(nil); return; }
        self.busy = NO;
        NSString *message = status == 0 || status == 202 ? @"Couldn’t confirm account deletion. Refresh before trying again." : [self failure:status payload:payload response:response];
        self.errorMessage = message;
        if (self.state == CloudSignedIn) [self->_uploadQueue start];
        [self changed];
        completion(CloudError(message));
    }];
}

#pragma mark Backups

- (void)refreshBackups {
    if (self.state != CloudSignedIn) return;
    NSString *token = _token;
    [self send:@"GET" path:@"/v1/devices" json:nil body:nil token:token completion:^(NSInteger status, id devices, NSData *data, NSHTTPURLResponse *response) {
        if (token != self->_token) return;
        if (status != 200) { self.errorMessage = [self failure:status payload:devices response:response]; [self changed]; return; }
        NSMutableDictionary *names = [NSMutableDictionary dictionary];
        NSMutableArray *connected = [NSMutableArray array];
        NSArray *list = Get(devices, @"devices");
        for (NSDictionary *device in [list isKindOfClass:NSArray.class] ? list : nil) {
            NSString *identifier = Get(device, @"id"), *name = Get(device, @"name");
            if (![identifier isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:identifier] || ![name isKindOfClass:NSString.class]) continue;
            names[identifier] = name;
            [connected addObject:@{@"identifier": identifier, @"name": name, @"this_mac": @([identifier isEqual:self.deviceIdentifier])}];
        }
        self.devices = connected;
        [self changed];
        [self send:@"GET" path:@"/v1/snapshots" json:nil body:nil token:token completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
            if (token != self->_token) return;
            if (status != 200) { self.errorMessage = [self failure:status payload:payload response:response]; [self changed]; return; }
            NSISO8601DateFormatter *dates = [NSISO8601DateFormatter new];
            dates.formatOptions |= NSISO8601DateFormatWithFractionalSeconds;
            NSMutableArray *backups = [NSMutableArray array];
            NSArray *rows = Get(payload, @"snapshots");
            for (NSDictionary *row in [rows isKindOfClass:NSArray.class] ? rows : nil) {
                if (![row isKindOfClass:NSDictionary.class] || ![row[@"id"] isKindOfClass:NSString.class] || ![row[@"sha256"] isKindOfClass:NSString.class]) continue;
                NSString *device = row[@"device_id"];
                [backups addObject:@{
                    @"identifier": row[@"id"], @"sha256": row[@"sha256"], @"byte_count": [row[@"byte_count"] isKindOfClass:NSNumber.class] ? row[@"byte_count"] : @0,
                    @"created": ([row[@"created_at"] isKindOfClass:NSString.class] ? [dates dateFromString:row[@"created_at"]] : nil) ?: NSDate.distantPast,
                    @"device_name": [names[device] isKindOfClass:NSString.class] ? names[device] : @"A removed Mac",
                    @"this_mac": @([device isEqual:self.deviceIdentifier]),
                }];
            }
            self.backups = backups;
            [self changed];
        }];
    }];
}

- (NSURL *)uploadQueueDirectory {
    NSString *partition = SHA256Hex([[_service stringByAppendingString:_baseURL.absoluteString] dataUsingEncoding:NSUTF8StringEncoding]);
    return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
        URLByAppendingPathComponent:[@"DevCloud/CloudUploads/" stringByAppendingString:partition] isDirectory:YES];
}

- (void)restoreUploadQueue {
    [_uploadQueue stop];
    _uploadQueue = nil;
    NSURL *root = [self uploadQueueDirectory];
    NSString *owner = SHA256Hex([[_token stringByAppendingString:self.deviceIdentifier] dataUsingEncoding:NSUTF8StringEncoding]);
    __weak CloudAccount *weakSelf = self;
    _uploadQueue = [[CloudUploadQueue alloc] initWithDirectory:root owner:owner transport:^(NSString *method, NSString *path, id json, NSData *body, CloudUploadReply reply) {
        CloudAccount *self = weakSelf;
        if (!self || self.state != CloudSignedIn) return;
        NSString *token = self->_token;
        [self send:method path:path json:json body:body token:token completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
            if (token != self->_token) return;
            if (status == 401) [self forgetSession:@"Your session ended. Sign in again to keep backing up."];
            reply(status, payload, response);
        }];
    }];
    _uploadQueue.changed = ^{ [weakSelf changed]; };
    _uploadQueue.committed = ^(NSData *body) {
        CloudAccount *self = weakSelf;
        if (!self || self.state != CloudSignedIn) return;
        self.lastBackedUpFingerprint = CloudInventoryFingerprint(body);
        self.errorMessage = [self storeSession] ? nil : @"Backup saved, but its change marker could not be saved in Keychain.";
        [self refreshBackups];
    };
    [_uploadQueue start];
}

- (NSString *)automaticOptOutKey {
    NSString *scope = [_service stringByAppendingString:_baseURL.absoluteString];
    return [@"CloudAutomaticOptOut." stringByAppendingString:SHA256Hex([scope dataUsingEncoding:NSUTF8StringEncoding])];
}

- (void)setAutomaticBackupsEnabled:(BOOL)enabled {
    if (self.state != CloudSignedIn || self.busy || enabled == _automaticBackupsEnabled) return;
    if (!enabled) [NSUserDefaults.standardUserDefaults setBool:YES forKey:self.automaticOptOutKey];
    _automaticBackupsEnabled = enabled;
    if (![self storeSession]) {
        _automaticBackupsEnabled = NO;
        self.errorMessage = @"Keychain could not save the automatic-backup preference.";
    } else {
        if (enabled) [NSUserDefaults.standardUserDefaults removeObjectForKey:self.automaticOptOutKey];
        self.errorMessage = nil;
    }
    [self changed];
}

- (BOOL)hasPendingInventoryFingerprint:(NSString *)fingerprint { return [_uploadQueue containsFingerprint:fingerprint]; }

- (void)backUpReport:(NSDictionary *)report completion:(void (^)(NSUInteger, NSError *))completion {
    if (self.state != CloudSignedIn || self.busy) { completion(0, CloudError(@"Sign in and wait for the current operation to finish.")); return; }
    NSUInteger dropped = 0;
    NSError *error = nil;
    NSData *body = CloudInventoryData(report, &dropped, &error);
    if (!body || ![_uploadQueue enqueue:body device:self.deviceIdentifier error:&error]) { completion(0, error); return; }
    completion([report[@"resources"] count] - dropped, nil);
}

- (void)retryPendingBackups { if (!self.busy) [_uploadQueue retry]; }
- (void)discardPendingBackups {
    if (self.busy) return;
    [NSNotificationCenter.defaultCenter postNotificationName:CloudAccountUploadQueueClearedNotification object:self];
    NSError *error = nil;
    if (![_uploadQueue discard:&error]) self.errorMessage = error.localizedDescription;
    [self changed];
}

- (void)downloadBackup:(NSString *)identifier completion:(void (^)(NSData *, NSError *))completion {
    NSString *expected = nil;
    for (NSDictionary *backup in self.backups) if ([backup[@"identifier"] isEqual:identifier]) expected = backup[@"sha256"];
    if (self.state != CloudSignedIn || !expected) { completion(nil, CloudError(@"That backup no longer exists.")); return; }
    NSString *path = [NSString stringWithFormat:@"/v1/snapshots/%@/body", identifier];
    [self send:@"GET" path:path json:nil body:nil token:_token completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
        if (status != 200) { completion(nil, CloudError([self failure:status payload:payload response:response])); return; }
        NSString *actual = SHA256Hex(data ?: [NSData data]);
        if (![actual isEqual:expected] || ![[response valueForHTTPHeaderField:@"X-Content-SHA256"] isEqual:expected]) {
            completion(nil, CloudError(@"The downloaded backup didn’t match its checksum, so it was discarded."));
            return;
        }
        completion(data, nil);
    }];
}

- (void)deleteBackup:(NSString *)identifier completion:(void (^)(NSError *))completion {
    if (self.state != CloudSignedIn) return;
    NSString *path = [@"/v1/snapshots/" stringByAppendingString:identifier];
    [self send:@"DELETE" path:path json:nil body:nil token:_token completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
        NSError *error = status == 204 || status == 404 ? nil : CloudError([self failure:status payload:payload response:response]);
        if (!error) {
            self.lastBackedUpFingerprint = nil;
            [self storeSession];
        }
        [self refreshBackups];
        completion(error);
    }];
}

@end
