#import "Pages.h"

static NSArray<NSArray<NSString *> *> *ExcludedPatterns(void) {
    return @[
        @[@"Environment files", @"**/.env, .env.*", @"Likely to contain secrets"],
        @[@"SSH private keys", @"~/.ssh/id_*", @"Credentials"],
        @[@"Cloud credentials", @"~/.aws/credentials, ~/.config/gcloud", @"Credentials"],
        @[@"Keychains", @"~/Library/Keychains", @"Credential store"],
        @[@"Shell history", @"~/.zsh_history", @"May contain tokens"],
    ];
}

@implementation ConfigurationsPage {
    PageScrollView *_scroll;
}

- (instancetype)initWithHost:(id<PageHost>)host {
    self = [super initWithHost:host];
    if (self) {
        _scroll = [[PageScrollView alloc] initWithMaxWidth:1000];
        Pin(_scroll, self, NSEdgeInsetsZero);
    }
    return self;
}

- (NSString *)signature {
    ScanModel *model = self.model;
    return [NSString stringWithFormat:@"%p|%d%d%d%d|%d", model.localMetadata, model.inspectMCP, model.inspectEditorSettings, model.inspectPathTools, model.includePaths, model.scanning];
}

- (void)rebuild {
    Inventory *inventory = self.inventory;
    ScanModel *model = self.model;
    NSMutableArray *sections = [NSMutableArray arrayWithObject:[self summary]];
    [sections addObject:SectionWithHeader(SectionHeader(@"Discovery sources", @"Each source stays off until you turn it on. Secret-bearing values are discarded before anything is stored.", nil), [self sourcesPanel])];
    if (model.inspectMCP) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *server in inventory.mcpServers) {
            [rows addObject:[self row:StringValue(server[@"name"], @"Server") detail:[NSString stringWithFormat:@"%@ · %@", StringValue(server[@"config_source"], @"—"), StringValue(server[@"transport"], @"—")]
                                 mono:StringValue(server[@"executable"], @"no executable") pill:[PillView pill:@"Metadata only" tone:ToneNeutral dot:NO]]];
        }
        [sections addObject:[self section:@"MCP servers" caption:@"Names, transport and executable only. Arguments, URLs and environment values are discarded." rows:rows warning:[model.localMetadata[@"mcp_warning"] boolValue] ? @"A configuration file could not be parsed. Its values were not stored." : nil empty:@"Claude Desktop and Cursor list no MCP servers."]];
    }
    if (model.inspectEditorSettings) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *setting in inventory.editorSettings) {
            [rows addObject:[self row:StringValue(setting[@"key"], @"Setting") detail:StringValue(setting[@"application"], @"Editor") mono:StringValue(setting[@"value"], @"—") pill:[PillView pill:@"Allowlisted" tone:ToneBlue dot:NO]]];
        }
        [sections addObject:[self section:@"Editor preferences" caption:@"A short allowlist of VS Code and Cursor settings. Paths and unknown keys are ignored." rows:rows warning:[model.localMetadata[@"editor_warning"] boolValue] ? @"A settings file could not be parsed. Its values were not stored." : nil empty:@"Every tracked preference uses its default."]];
    }
    if (model.inspectPathTools) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *tool in inventory.pathTools) {
            [rows addObject:[self row:StringValue(tool[@"name"], @"Executable") detail:@"Executable on PATH" mono:[NSString stringWithFormat:@"PATH[%@]", tool[@"path_position"] ?: @"?"] pill:nil]];
        }
        [sections addObject:[self section:@"Other PATH executables" caption:@"Names only. Files are never run and full paths are left out." rows:rows warning:nil empty:@"Every command on PATH is a recognised developer tool."]];
    }
    NSMutableArray *excluded = [NSMutableArray array];
    for (NSArray *pattern in ExcludedPatterns()) {
        NSTextField *label = Label(pattern[0], 12.5, NSFontWeightRegular, ThemeTextColor());
        [label.widthAnchor constraintEqualToConstant:150].active = YES;
        NSTextField *glob = MonoLabel(pattern[1], 11, ThemeFaintColor());
        NSStackView *line = HStack(12, @[SymbolView(@"nosign", 11, NSFontWeightRegular, ThemeFaintColor()), label, glob, Spacer(), Label(pattern[2], 11.5, NSFontWeightRegular, ThemeFaintColor())]);
        NSView *cell = [NSView new];
        cell.translatesAutoresizingMaskIntoConstraints = NO;
        Pin(line, cell, NSEdgeInsetsMake(10, 16, 10, 16));
        [excluded addObject:cell];
    }
    [sections addObject:SectionWithHeader(SectionHeader(@"Excluded by default", @"Never read, monitored, or exported in this release", nil), ListPanel(excluded))];
    [_scroll setSections:sections];
}

- (NSView *)summary {
    Inventory *inventory = self.inventory;
    NSArray *tiles = @[
        @[@"point.3.connected.trianglepath.dotted", @(inventory.mcpServers.count), @"MCP servers", @(self.model.inspectMCP)],
        @[@"slider.horizontal.3", @(inventory.editorSettings.count), @"Editor preferences", @(self.model.inspectEditorSettings)],
        @[@"terminal", @(inventory.pathTools.count), @"Other PATH tools", @(self.model.inspectPathTools)],
        @[@"nosign", @(ExcludedPatterns().count), @"Excluded by default", @YES],
    ];
    NSStackView *row = HStack(12, @[]);
    row.distribution = NSStackViewDistributionFillEqually;
    for (NSArray *tile in tiles) {
        BOOL on = [tile[3] boolValue];
        NSTextField *value = Label(on ? [tile[1] stringValue] : @"Off", 18, NSFontWeightSemibold, on ? ThemeTextColor() : ThemeFaintColor());
        value.font = [NSFont monospacedDigitSystemFontOfSize:18 weight:NSFontWeightSemibold];
        NSStackView *content = HStack(12, @[SymbolView(tile[0], 14, NSFontWeightRegular, ThemeFaintColor()), VStack(4, @[value, Label(tile[2], 11.5, NSFontWeightRegular, ThemeFaintColor())])]);
        PanelView *panel = [PanelView new];
        Pin(content, panel, NSEdgeInsetsMake(14, 16, 14, 16));
        [row addArrangedSubview:panel];
    }
    return row;
}

- (NSView *)sourcesPanel {
    ScanModel *model = self.model;
    NSArray *sources = @[
        @[@"mcp", @"MCP servers", @"Claude Desktop and Cursor configuration", @(model.inspectMCP)],
        @[@"editor", @"Editor preferences", @"VS Code and Cursor settings.json, allowlisted keys", @(model.inspectEditorSettings)],
        @[@"pathTools", @"Other PATH executables", @"Names of commands discovery does not recognise", @(model.inspectPathTools)],
        @[@"paths", @"Installation locations", @"Full paths in the inventory and exports; enables Show in Finder", @(model.includePaths)],
    ];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSArray *source in sources) {
        BOOL on = [source[3] boolValue];
        NSSwitch *toggle = Switch(on, NSControlSizeSmall, self, @selector(toggleSource:));
        toggle.identifier = source[0];
        toggle.accessibilityLabel = source[1];
        NSStackView *text = VStack(2, @[Label(source[1], 13, NSFontWeightRegular, ThemeTextColor()), Label(source[2], 11.5, NSFontWeightRegular, ThemeFaintColor())]);
        NSStackView *line = HStack(12, @[text, Spacer(), [PillView pill:on ? @"On" : @"Off" tone:on ? ToneBlue : ToneNeutral dot:NO], toggle]);
        NSView *cell = [NSView new];
        cell.translatesAutoresizingMaskIntoConstraints = NO;
        Pin(line, cell, NSEdgeInsetsMake(11, 16, 11, 16));
        [rows addObject:cell];
    }
    return ListPanel(rows);
}

- (void)toggleSource:(NSSwitch *)sender {
    BOOL on = sender.state == NSControlStateValueOn;
    NSString *key = sender.identifier;
    if ([key isEqual:@"mcp"]) self.model.inspectMCP = on;
    else if ([key isEqual:@"editor"]) self.model.inspectEditorSettings = on;
    else if ([key isEqual:@"pathTools"]) self.model.inspectPathTools = on;
    else if ([key isEqual:@"paths"]) self.model.includePaths = on;
}

- (NSView *)row:(NSString *)title detail:(NSString *)detail mono:(NSString *)mono pill:(NSView *)pill {
    NSStackView *text = VStack(2, @[Label(title, 13, NSFontWeightRegular, ThemeTextColor()), Label(detail, 11.5, NSFontWeightRegular, ThemeFaintColor())]);
    NSTextField *value = MonoLabel(mono, 11.5, ThemeSubColor());
    NSStackView *line = HStack(16, @[text, Spacer(), value]);
    [text.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
    if (pill) [line addArrangedSubview:pill];
    NSView *cell = [NSView new];
    cell.translatesAutoresizingMaskIntoConstraints = NO;
    Pin(line, cell, NSEdgeInsetsMake(10, 16, 10, 16));
    return cell;
}

- (NSView *)section:(NSString *)title caption:(NSString *)caption rows:(NSArray *)rows warning:(NSString *)warning empty:(NSString *)empty {
    NSMutableArray *all = [rows mutableCopy];
    if (warning) {
        NSStackView *line = HStack(9, @[SymbolView(@"exclamationmark.triangle", 11, NSFontWeightSemibold, NSColor.systemOrangeColor), Label(warning, 12, NSFontWeightRegular, NSColor.systemOrangeColor)]);
        NSView *cell = [NSView new];
        cell.translatesAutoresizingMaskIntoConstraints = NO;
        Pin(line, cell, NSEdgeInsetsMake(10, 16, 10, 16));
        [all insertObject:cell atIndex:0];
    }
    if (!all.count) {
        NSView *cell = [NSView new];
        cell.translatesAutoresizingMaskIntoConstraints = NO;
        Pin(Label(self.model.scanning ? @"Reading…" : empty, 12.5, NSFontWeightRegular, ThemeFaintColor()), cell, NSEdgeInsetsMake(12, 16, 12, 16));
        [all addObject:cell];
    }
    NSString *count = rows.count ? [NSString stringWithFormat:@"%lu", (unsigned long)rows.count] : nil;
    return SectionWithHeader(SectionHeader(title, caption, count ? Label(count, 11.5, NSFontWeightRegular, ThemeFaintColor()) : nil), ListPanel(all));
}

@end
