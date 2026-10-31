#import "CloudAccount.h"
#import "CloudInventory.h"
#import <AppKit/AppKit.h>
#import <Security/Security.h>

NSNotificationName const CloudAccountDidChangeNotification = @"CloudAccountDidChangeNotification";

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
@property(nonatomic, copy) NSString *errorMessage;
@property(nonatomic, copy) NSString *email;
@property(nonatomic, copy) NSString *deviceIdentifier;
@property(nonatomic, copy) NSString *userCode;
@property(nonatomic, copy) NSDate *codeExpiry;
@property(nonatomic, copy) NSArray<NSDictionary *> *backups;
@end

@implementation CloudAccount {
    NSURL *_baseURL;
    NSString *_service;
    NSURLSession *_session;
    NSString *_token;
    NSString *_deviceCode;
    NSURL *_verificationURL;
    NSTimeInterval _interval;
    NSUInteger _signInGeneration;
}

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
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"token": _token, @"device_id": self.deviceIdentifier, @"email": self.email ?: @""} options:0 error:nil];
    SecItemDelete((__bridge CFDictionaryRef)self.keychainQuery);
    NSMutableDictionary *item = [self.keychainQuery mutableCopy];
    item[(__bridge id)kSecValueData] = data;
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    item[(__bridge id)kSecAttrLabel] = @"DevCloud cloud session";
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}

- (void)forgetSession:(NSString *)message {
    SecItemDelete((__bridge CFDictionaryRef)self.keychainQuery);
    _token = nil;
    self.deviceIdentifier = nil;
    self.email = nil;
    self.backups = @[];
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
    self.state = CloudSignedIn;
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
            self.errorMessage = [self storeSession] ? nil : @"Signed in, but Keychain refused to save the session. You’ll need to sign in again next time.";
            [self changed];
            [self refreshBackups];
        }];
    }];
}

- (void)signOut {
    if (self.state != CloudSignedIn || self.busy) return;
    self.busy = YES;
    self.errorMessage = nil;
    [self changed];
    NSString *path = [@"/v1/devices/" stringByAppendingString:self.deviceIdentifier];
    [self send:@"DELETE" path:path json:nil body:nil token:_token completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
        // 401/404: the session or device is already gone, which is the goal.
        if (status == 204 || status == 401 || status == 404) { [self forgetSession:nil]; return; }
        self.busy = NO;
        self.errorMessage = [self failure:status payload:payload response:response];
        [self changed];
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
        NSArray *list = Get(devices, @"devices");
        for (NSDictionary *device in [list isKindOfClass:NSArray.class] ? list : nil) {
            if ([device isKindOfClass:NSDictionary.class] && [device[@"id"] isKindOfClass:NSString.class]) names[device[@"id"]] = device[@"name"];
        }
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

- (void)backUpReport:(NSDictionary *)report completion:(void (^)(NSUInteger, NSError *))completion {
    if (self.state != CloudSignedIn || self.busy) return;
    NSUInteger dropped = 0;
    NSError *error = nil;
    NSData *body = CloudInventoryData(report, &dropped, &error);
    if (!body) { completion(0, error); return; }
    NSUInteger tools = [report[@"resources"] count] - dropped;
    NSString *sha = SHA256Hex(body), *token = _token;
    self.busy = YES;
    self.errorMessage = nil;
    [self changed];
    void (^fail)(NSInteger, id, NSHTTPURLResponse *) = ^(NSInteger status, id payload, NSHTTPURLResponse *response) {
        if (token != self->_token) return;
        self.busy = NO;
        NSString *message = [self failure:status payload:payload response:response];
        self.errorMessage = message;
        [self changed];
        completion(0, CloudError(message));
    };
    NSDictionary *reservation = @{@"device_id": self.deviceIdentifier, @"schema_version": @1, @"byte_count": @(body.length), @"sha256": sha,
                                  @"idempotency_key": NSUUID.UUID.UUIDString.lowercaseString};
    [self send:@"POST" path:@"/v1/uploads" json:reservation body:nil token:token completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
        NSString *upload = Get(Get(payload, @"upload"), @"id");
        if (status != 201 || ![upload isKindOfClass:NSString.class]) { fail(status, payload, response); return; }
        NSString *path = [NSString stringWithFormat:@"/v1/uploads/%@", upload];
        [self send:@"PUT" path:[path stringByAppendingString:@"/body"] json:nil body:body token:token completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
            if (status != 204) { fail(status, payload, response); return; }
            [self send:@"POST" path:[path stringByAppendingString:@"/commit"] json:nil body:nil token:token completion:^(NSInteger status, id payload, NSData *data, NSHTTPURLResponse *response) {
                if (status != 200) { fail(status, payload, response); return; }
                self.busy = NO;
                [self changed];
                [self refreshBackups];
                completion(tools, nil);
            }];
        }];
    }];
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
        [self refreshBackups];
        completion(error);
    }];
}

@end
