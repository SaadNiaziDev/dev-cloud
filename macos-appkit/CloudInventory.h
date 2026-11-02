#import <Foundation/Foundation.h>

// Largest upload body the cloud accepts.
extern const NSUInteger CloudInventoryMaxBytes;

// The allowlisted cloud form of a schema v1 report: host platform, architecture and
// OS version, plus each tool's canonical ID, version and provider. Paths, warnings,
// evidence, display names and installation IDs never leave the Mac. Unsupported
// providers and versions become null; IDs that could carry other text are dropped.
// Compact, key-sorted JSON, or nil with `error` when the report itself is unusable.
NSData *CloudInventoryData(NSDictionary *report, NSUInteger *dropped, NSError **error);
NSString *SHA256Hex(NSData *data);

// Change detection excludes scan time and resource ordering, using only the cloud allowlist.
NSString *CloudInventoryFingerprint(NSData *body);
