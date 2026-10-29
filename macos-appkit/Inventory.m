#import "Inventory.h"

NSString *StringValue(id value, NSString *fallback) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : fallback;
}

NSString *ProviderName(NSString *provider) {
    if (!StringValue(provider, nil)) return @"Unknown";
    NSDictionary *names = @{
        @"homebrew_formula": @"Homebrew", @"homebrew_cask": @"Homebrew Cask", @"macos_system": @"macOS",
        @"xcode": @"Xcode", @"nvm": @"nvm", @"pyenv": @"pyenv", @"volta": @"Volta", @"fnm": @"fnm",
        @"vscode": @"VS Code", @"cursor": @"Cursor", @"application_bundle": @"Application", @"path": @"PATH",
    };
    return names[provider] ?: provider;
}

NSString *ResourceProviderName(NSDictionary *resource) {
    if (StringValue(resource[@"installation_provider"], nil)) return ProviderName(resource[@"installation_provider"]);
    return StringValue(resource[@"discovery_adapter"], nil) ? ProviderName(resource[@"discovery_adapter"]) : @"Unknown";
}

NSString *KindName(NSString *kind) {
    NSDictionary *names = @{
        @"runtime": @"Runtime", @"tool": @"CLI", @"package_manager": @"Package manager", @"version_manager": @"Version manager",
        @"database": @"Database", @"application": @"Application", @"editor": @"Editor", @"editor_extension": @"Editor extension",
        @"package": @"Package",
    };
    return names[kind] ?: StringValue(kind, @"Unknown");
}

NSInteger ResourceConfidence(NSDictionary *resource) {
    if (!StringValue(resource[@"version"], nil)) return 1;
    return StringValue(resource[@"installation_provider"], nil) ? 3 : 2;
}

static ToolGroup GroupForKind(NSString *kind) {
    if ([kind isEqual:@"runtime"]) return ToolGroupRuntimes;
    if ([kind isEqual:@"package_manager"] || [kind isEqual:@"version_manager"]) return ToolGroupManagers;
    if ([kind isEqual:@"editor"]) return ToolGroupEditors;
    if ([kind isEqual:@"package"]) return ToolGroupPackages;
    if ([kind isEqual:@"editor_extension"]) return ToolGroupExtensions;
    return ToolGroupOther;
}

static BOOL OnPath(NSDictionary *resource) {
    return [resource[@"path_status"] isEqual:@"first_on_path"] || [resource[@"path_status"] isEqual:@"also_on_path"];
}

@implementation ToolEntry

- (NSDictionary *)primary {
    for (NSDictionary *resource in self.installations) if ([resource[@"path_status"] isEqual:@"first_on_path"]) return resource;
    return self.installations.firstObject;
}

- (BOOL)detected { return self.installations.count > 0; }

- (BOOL)matches:(NSString *)query {
    NSMutableArray *fields = [NSMutableArray arrayWithObjects:self.name, self.category, nil];
    for (NSDictionary *resource in self.installations) {
        [fields addObject:ResourceProviderName(resource)];
        [fields addObject:StringValue(resource[@"version"], @"")];
        [fields addObject:StringValue(resource[@"provider_package_id"], @"")];
    }
    for (NSString *field in fields) if ([field rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

@end

@implementation AttentionItem
@end

@implementation ActivityEvent
@end

@interface Inventory ()
@property(nonatomic, copy, readwrite) NSArray<ToolEntry *> *tools;
@property(nonatomic, copy, readwrite) NSArray<ToolEntry *> *missing;
@property(nonatomic, copy, readwrite) NSArray<AttentionItem *> *attention;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary *> *workspaces;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary *> *mcpServers;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary *> *editorSettings;
@property(nonatomic, copy, readwrite) NSArray<NSDictionary *> *pathTools;
@property(nonatomic, readwrite) NSUInteger developerToolCount;
@property(nonatomic, weak) NSDictionary *sourceReport;
@property(nonatomic, weak) NSDictionary *sourceLocal;
@end

@implementation Inventory

+ (instancetype)inventoryForModel:(ScanModel *)model {
    static Inventory *cached;
    if (cached && cached.sourceReport == model.report && cached.sourceLocal == model.localMetadata) return cached;
    cached = [[Inventory alloc] initWithReport:model.report local:model.localMetadata];
    return cached;
}

- (instancetype)initWithReport:(NSDictionary *)report local:(NSDictionary *)local {
    self = [super init];
    if (!self) return nil;
    _sourceReport = report;
    _sourceLocal = local;
    _workspaces = local[@"workspaces"] ?: @[];
    _mcpServers = local[@"mcp_servers"] ?: @[];
    _editorSettings = local[@"editor_settings"] ?: @[];
    _pathTools = local[@"unknown_path_tools"] ?: @[];
    [self buildTools:report[@"resources"] ?: @[]];
    [self buildAttention:report local:local];
    return self;
}

- (void)buildTools:(NSArray<NSDictionary *> *)resources {
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *resource in resources) {
        NSString *key = StringValue(resource[@"canonical_tool_id"], @"unknown");
        if (!groups[key]) groups[key] = [NSMutableArray array];
        [groups[key] addObject:resource];
    }
    NSMutableArray<ToolEntry *> *tools = [NSMutableArray array];
    for (NSString *key in groups) {
        NSArray *members = [groups[key] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSInteger rank = ([b[@"path_status"] isEqual:@"first_on_path"] ? 2 : OnPath(b)) - ([a[@"path_status"] isEqual:@"first_on_path"] ? 2 : OnPath(a));
            return rank > 0 ? NSOrderedDescending : (rank < 0 ? NSOrderedAscending : NSOrderedSame);
        }];
        ToolEntry *tool = [ToolEntry new];
        tool.identifier = key;
        tool.installations = members;
        tool.name = StringValue(tool.primary[@"display_name"], key);
        tool.category = KindName(tool.primary[@"kind"]);
        tool.group = GroupForKind(tool.primary[@"kind"]);
        NSArray *visible = [members filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *r, id b) { return OnPath(r); }]];
        if (visible.count > 1) {
            NSDictionary *first = tool.primary;
            tool.warnings = @[[NSString stringWithFormat:@"%lu installations are on DevCloud’s scan PATH. The %@ %@ resolves first; your shell may differ.",
                (unsigned long)visible.count, ResourceProviderName(first), StringValue(first[@"version"], @"installation")]];
        } else {
            tool.warnings = @[];
        }
        [tools addObject:tool];
    }
    [tools sortUsingComparator:^NSComparisonResult(ToolEntry *a, ToolEntry *b) {
        if (a.group != b.group) return a.group < b.group ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedStandardCompare:b.name];
    }];
    self.tools = tools;
    self.developerToolCount = [tools indexesOfObjectsPassingTest:^BOOL(ToolEntry *t, NSUInteger i, BOOL *s) { return t.group < ToolGroupPackages; }].count;

    // Common tools that discovery looks for, shown as absent rather than silently omitted.
    NSArray *expected = @[@[@"nodejs", @"Node.js", @"runtime"], @[@"python", @"Python", @"runtime"], @[@"go", @"Go", @"runtime"], @[@"rustc", @"Rust", @"runtime"],
                          @[@"bun", @"Bun", @"runtime"], @[@"java", @"Java", @"runtime"], @[@"swift", @"Swift", @"runtime"], @[@"git", @"Git", @"tool"],
                          @[@"docker", @"Docker CLI", @"tool"], @[@"yarn", @"Yarn", @"package_manager"], @[@"pnpm", @"pnpm", @"package_manager"], @[@"uv", @"uv", @"package_manager"]];
    NSMutableSet *present = [NSMutableSet set];
    for (NSString *key in groups) [present addObject:[key componentsSeparatedByString:@"@"].firstObject];
    if ([present containsObject:@"openjdk"]) [present addObject:@"java"];
    if ([present containsObject:@"node"]) [present addObject:@"nodejs"];
    NSMutableArray *missing = [NSMutableArray array];
    for (NSArray *spec in expected) {
        if (!resources.count || [present containsObject:spec[0]]) continue;
        ToolEntry *tool = [ToolEntry new];
        tool.identifier = spec[0];
        tool.name = spec[1];
        tool.category = KindName(spec[2]);
        tool.group = GroupForKind(spec[2]);
        tool.installations = @[];
        tool.warnings = @[];
        [missing addObject:tool];
    }
    self.missing = missing;
}

- (void)buildAttention:(NSDictionary *)report local:(NSDictionary *)local {
    NSMutableArray *items = [NSMutableArray array];
    for (ToolEntry *tool in self.tools) {
        if (!tool.warnings.count) continue;
        AttentionItem *item = [AttentionItem new];
        item.title = [NSString stringWithFormat:@"Multiple %@ installations", tool.name];
        item.detail = tool.warnings.firstObject;
        item.page = PageTools;
        item.toolIdentifier = tool.identifier;
        [items addObject:item];
    }
    void (^add)(NSString *, NSString *, Page) = ^(NSString *title, NSString *detail, Page page) {
        AttentionItem *item = [AttentionItem new];
        item.title = title;
        item.detail = detail;
        item.page = page;
        [items addObject:item];
    };
    for (NSString *warning in report[@"warnings"] ?: @[]) add(@"Scan note", warning, PageActivity);
    for (id warning in local[@"workspace_warnings"] ?: @[]) {
        if ([warning isKindOfClass:NSString.class]) add(@"Workspace not read", warning, PageWorkspaces);
    }
    if ([local[@"mcp_warning"] boolValue]) add(@"MCP configuration unreadable", @"A Claude Desktop or Cursor MCP file could not be parsed. Its values were not stored.", PageConfigurations);
    if ([local[@"editor_warning"] boolValue]) add(@"Editor settings unreadable", @"A VS Code or Cursor settings file could not be parsed. Its values were not stored.", PageConfigurations);
    self.attention = items;
}

- (ToolEntry *)toolWithIdentifier:(NSString *)identifier {
    for (ToolEntry *tool in [self.tools arrayByAddingObjectsFromArray:self.missing]) if ([tool.identifier isEqual:identifier]) return tool;
    return nil;
}

@end

#pragma mark - Activity

static ActivityEvent *Event(NSDate *date, ActivityKind kind, NSString *title, NSString *detail) {
    ActivityEvent *event = [ActivityEvent new];
    event.date = date;
    event.kind = kind;
    event.title = title;
    event.detail = detail;
    return event;
}

static NSString *PackageKey(NSDictionary *r) {
    return [NSString stringWithFormat:@"%@|%@|%@|%@", StringValue(r[@"canonical_tool_id"], @""), StringValue(r[@"installation_provider"], @""), StringValue(r[@"provider_package_id"], @""), StringValue(r[@"kind"], @"")];
}

// Mirrors history.rs: match by instance, then pair a lone new instance with a lone
// vanished one from the same package, since upgrades move installs.
static NSArray<ActivityEvent *> *DiffEvents(NSArray<NSDictionary *> *before, NSArray<NSDictionary *> *after, NSDate *date) {
    NSMutableDictionary<NSString *, NSDictionary *> *old = [NSMutableDictionary dictionary];
    for (NSDictionary *r in before) old[[NSString stringWithFormat:@"%@|%@", r[@"canonical_tool_id"], r[@"installation_instance_id"]]] = r;
    NSMutableArray *events = [NSMutableArray array];
    NSMutableArray *unmatched = [NSMutableArray array];
    void (^updated)(NSDictionary *, NSDictionary *) = ^(NSDictionary *was, NSDictionary *now) {
        NSString *detail = [NSString stringWithFormat:@"%@ · %@ → %@", ResourceProviderName(now), StringValue(was[@"version"], @"unknown"), StringValue(now[@"version"], @"unknown")];
        [events addObject:Event(date, ActivityChange, [NSString stringWithFormat:@"%@ updated", StringValue(now[@"display_name"], @"Tool")], detail)];
    };
    for (NSDictionary *r in after) {
        NSString *key = [NSString stringWithFormat:@"%@|%@", r[@"canonical_tool_id"], r[@"installation_instance_id"]];
        NSDictionary *was = old[key];
        if (!was) { [unmatched addObject:r]; continue; }
        [old removeObjectForKey:key];
        if (![StringValue(was[@"version"], @"") isEqual:StringValue(r[@"version"], @"")] || ![StringValue(was[@"installation_provider"], @"") isEqual:StringValue(r[@"installation_provider"], @"")]) updated(was, r);
    }
    for (NSDictionary *r in unmatched) {
        NSString *package = PackageKey(r);
        NSArray *sameOld = [old.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, id b) { return [PackageKey(old[key]) isEqual:package]; }]];
        NSUInteger sameNew = [unmatched indexesOfObjectsPassingTest:^BOOL(NSDictionary *c, NSUInteger i, BOOL *s) { return [PackageKey(c) isEqual:package]; }].count;
        if (sameOld.count == 1 && sameNew == 1) {
            updated(old[sameOld.firstObject], r);
            [old removeObjectForKey:sameOld.firstObject];
        } else {
            NSString *detail = [NSString stringWithFormat:@"%@ · %@", ResourceProviderName(r), StringValue(r[@"version"], @"version unknown")];
            [events addObject:Event(date, ActivityChange, [NSString stringWithFormat:@"%@ added", StringValue(r[@"display_name"], @"Tool")], detail)];
        }
    }
    for (NSDictionary *r in old.allValues) {
        NSString *detail = [NSString stringWithFormat:@"%@ · %@", ResourceProviderName(r), StringValue(r[@"version"], @"version unknown")];
        [events addObject:Event(date, ActivityChange, [NSString stringWithFormat:@"%@ removed", StringValue(r[@"display_name"], @"Tool")], detail)];
    }
    return events;
}

NSArray<ActivityEvent *> *LoadActivity(NSURL *historyDirectory, NSDictionary *report, NSDate *lastScan) {
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:historyDirectory includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] ?: @[];
    files = [[files filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, id b) {
        return [url.lastPathComponent hasPrefix:@"scan-"] && [url.pathExtension isEqual:@"json"];
    }]] sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent]; }];

    NSMutableArray<ActivityEvent *> *events = [NSMutableArray array];
    NSArray *previous = nil;
    NSDate *newest = nil;
    for (NSURL *file in files) {
        NSData *data = ReadHistoryFile(file);
        NSDictionary *snapshot = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![snapshot isKindOfClass:NSDictionary.class] || ![snapshot[@"resources"] isKindOfClass:NSArray.class]) continue;
        NSArray *resources = [snapshot[@"resources"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self isKindOfClass: %@", NSDictionary.class]];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[snapshot[@"observed_at_unix_seconds"] doubleValue]];
        if (!previous) {
            [events addObject:Event(date, ActivityScan, @"First scan recorded", [NSString stringWithFormat:@"Read-only discovery · %lu items · no files changed", (unsigned long)resources.count])];
        } else {
            NSArray *changes = DiffEvents(previous, resources, date);
            [events addObject:Event(date, ActivityScan, @"Scan found changes", [NSString stringWithFormat:@"%lu %@ · %lu items", (unsigned long)changes.count, changes.count == 1 ? @"change" : @"changes", (unsigned long)resources.count])];
            [events addObjectsFromArray:changes];
        }
        previous = resources;
        newest = date;
    }
    if (report && lastScan && (!newest || [lastScan timeIntervalSinceDate:newest] > 1)) {
        [events addObject:Event(lastScan, ActivityScan, @"Scan completed", [NSString stringWithFormat:@"No changes · %lu items", (unsigned long)[report[@"resources"] count]])];
    }
    for (NSString *warning in report[@"warnings"] ?: @[]) [events addObject:Event(lastScan ?: NSDate.date, ActivityWarning, @"Scan note", warning)];
    return [events sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(ActivityEvent *a, ActivityEvent *b) { return [b.date compare:a.date]; }];
}
