#import <Foundation/Foundation.h>

// Setting up another Mac from a scan, snapshot or cloud backup. Returns nil when the
// inventory is invalid. Backup names reach a line only after strict pattern checks.

// A reviewable Brewfile, with runtime and Cursor steps as comments.
NSString *SetupBrewfile(NSDictionary *inventory, NSUInteger *entries, NSError **error);

// One entry per line, in Brewfile order: kind (brew, cask, vscode, step, cursor), name,
// line, and installed (already present in `current`, which may be nil).
NSArray<NSDictionary *> *SetupItems(NSDictionary *inventory, NSDictionary *current, NSError **error);
BOOL SetupItemInstallable(NSDictionary *item);
// A Brewfile holding only the Homebrew-installable `items`.
NSString *SetupInstallFile(NSArray<NSDictionary *> *items);
