#import <Cocoa/Cocoa.h>
#import "ScanModel.h"

typedef NS_ENUM(NSInteger, Page) { PageOverview, PageTools, PageWorkspaces, PageConfigurations, PageActivity, PageSnapshots, PageSettings };

typedef NS_ENUM(NSInteger, ToolGroup) { ToolGroupRuntimes, ToolGroupManagers, ToolGroupEditors, ToolGroupOther, ToolGroupPackages, ToolGroupExtensions };

NSString *StringValue(id value, NSString *fallback);
NSString *ProviderName(NSString *provider);
NSString *KindName(NSString *kind);
// The installer, or how discovery found it when no installer is recorded.
NSString *ResourceProviderName(NSDictionary *resource);
// 3 when the version and its installer were read, 2 for the version alone, 1 otherwise.
NSInteger ResourceConfidence(NSDictionary *resource);

// Every installation of one tool, with the one that resolves first on PATH as primary.
@interface ToolEntry : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *category;
@property(nonatomic) ToolGroup group;
@property(nonatomic, copy) NSArray<NSDictionary *> *installations;
@property(nonatomic, copy) NSArray<NSString *> *warnings;
@property(nonatomic, readonly) NSDictionary *primary;
@property(nonatomic, readonly) BOOL detected;
- (BOOL)matches:(NSString *)query;
@end

@interface AttentionItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *detail;
@property(nonatomic) Page page;
@property(nonatomic, copy) NSString *toolIdentifier;
@end

typedef NS_ENUM(NSInteger, ActivityKind) { ActivityChange, ActivityScan, ActivityWarning, ActivityInfo };

@interface ActivityEvent : NSObject
@property(nonatomic, copy) NSDate *date;
@property(nonatomic) ActivityKind kind;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *detail;
@end

@interface Inventory : NSObject
// Rebuilt only when the model's report or local metadata changes.
+ (instancetype)inventoryForModel:(ScanModel *)model;
@property(nonatomic, copy, readonly) NSArray<ToolEntry *> *tools;
@property(nonatomic, copy, readonly) NSArray<ToolEntry *> *missing;
@property(nonatomic, copy, readonly) NSArray<AttentionItem *> *attention;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *workspaces;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *mcpServers;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *editorSettings;
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *pathTools;
@property(nonatomic, readonly) NSUInteger developerToolCount;
- (ToolEntry *)toolWithIdentifier:(NSString *)identifier;
@end

// Scans and changes, newest first, rebuilt from the saved history snapshots.
NSArray<ActivityEvent *> *LoadActivity(NSURL *historyDirectory, NSDictionary *report, NSDate *lastScan);
