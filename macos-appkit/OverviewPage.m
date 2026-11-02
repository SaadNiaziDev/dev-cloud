#import "Pages.h"
#import "BrandMark.h"

@implementation OverviewPage {
    PageScrollView *_scroll;
    BOOL _hadReport;
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
    return [NSString stringWithFormat:@"%d|%@|%lu|%p|%p|%p|%d|%@|%@", model.scanning, model.phase, (unsigned long)model.completedPhases.count, model.report, model.localMetadata,
            model.changes, model.monitoring, RelativeDate(model.lastScanDate), model.errorMessage];
}

- (void)rebuild {
    NSMutableArray *sections = [NSMutableArray array];
    if (self.model.scanning) [sections addObject:[self progressPanel]];
    else if (!self.model.report) [sections addObject:[self welcomePanel]];
    else [sections addObject:[self statusPanel]];
    if (self.model.report) {
        [sections addObject:[self statsPanel]];
        [sections addObject:SectionWithHeader(SectionHeader(@"Scope", @"What this release discovers, what it watches, and what it does not do yet", nil), [self scopePanel])];
        [sections addObject:[self bottomRow]];
    }
    [_scroll setSections:sections];
    // Results replacing the progress panel arrive in a short cascade instead of all at once.
    if (self.model.report && !_hadReport && self.window) AnimateIn(sections, 8, 0.05);
    _hadReport = self.model.report != nil;
}

#pragma mark Status

- (NSView *)progressPanel {
    NSArray *phases = [self.model.completedPhases filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT (self IN %@)", @[@"Preparing local scan", @"Scan complete"]]];
    NSStackView *heading = VStack(2, @[Label(@"Scanning your environment", 15, NSFontWeightSemibold, ThemeTextColor()),
                                       Label(@"Read-only · results appear as each phase finishes", 12, NSFontWeightRegular, ThemeSubColor())]);
    NSTextField *count = MonoLabel([NSString stringWithFormat:@"%lu done", (unsigned long)phases.count], 12, ThemeFaintColor());
    NSStackView *top = HStack(12, @[heading, Spacer(), count]);
    ProgressBar *bar = [ProgressBar barWithHeight:4];
    bar.value = self.model.progress > 0 ? self.model.progress : MIN(0.9, 0.12 + phases.count * 0.16);

    NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:2 rows:0];
    grid.rowSpacing = 8;
    grid.columnSpacing = 32;
    NSMutableArray *cells = [NSMutableArray array];
    for (NSString *phase in phases) [cells addObject:[self phaseRow:phase done:YES]];
    if (![phases containsObject:self.model.phase] && ![self.model.phase isEqual:@"Scan complete"]) [cells addObject:[self phaseRow:self.model.phase ?: @"Preparing local scan" done:NO]];
    for (NSUInteger i = 0; i < cells.count; i += 2) [grid addRowWithViews:@[cells[i], i + 1 < cells.count ? cells[i + 1] : [NSGridCell emptyContentView]]];

    NSStackView *stack = VStack(16, @[]);
    FillWidth(top, stack);
    FillWidth(bar, stack);
    [stack addArrangedSubview:grid];
    return PaddedPanel(stack, 24);
}

- (NSView *)phaseRow:(NSString *)phase done:(BOOL)done {
    NSView *icon;
    if (done) {
        icon = SymbolView(@"checkmark", 11, NSFontWeightBold, NSColor.systemGreenColor);
    } else {
        NSProgressIndicator *spinner = [NSProgressIndicator new];
        spinner.style = NSProgressIndicatorStyleSpinning;
        spinner.controlSize = NSControlSizeSmall;
        spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [spinner startAnimation:nil];
        icon = spinner;
    }
    [NSLayoutConstraint activateConstraints:@[[icon.widthAnchor constraintEqualToConstant:14], [icon.heightAnchor constraintEqualToConstant:14]]];
    return HStack(9, @[icon, Label(phase, 12.5, NSFontWeightRegular, ThemeTextColor())]);
}

- (NSView *)welcomePanel {
    BOOL failed = self.model.errorMessage != nil;
    NSImageView *icon = [NSImageView imageViewWithImage:DevCloudAppIconImage(64)];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.accessibilityElement = NO;
    NSTextField *title = Label(failed ? @"The scan didn’t finish" : @"Take inventory of this Mac", 17, NSFontWeightSemibold, ThemeTextColor());
    NSTextField *message = WrappingLabel(failed ? self.model.errorMessage : @"DevCloud finds runtimes, package managers, editors and their versions by reading folder and file metadata. It never runs what it finds, and nothing leaves this Mac.", 12.5, ThemeSubColor());
    message.alignment = NSTextAlignmentCenter;
    [message.widthAnchor constraintLessThanOrEqualToConstant:420].active = YES;
    NSButton *scan = PushButton(failed ? @"Try Again" : @"Scan This Mac", YES, self.host, @selector(scanNow:));
    NSStackView *stack = VStack(10, @[icon, title, message, scan, Label(@"or press ⌘R", 11, NSFontWeightRegular, ThemeFaintColor())]);
    stack.alignment = NSLayoutAttributeCenterX;
    [stack setCustomSpacing:16 afterView:message];
    stack.edgeInsets = NSEdgeInsetsMake(36, 0, 36, 0);
    return PaddedPanel(stack, 24);
}

- (NSView *)statusPanel {
    NSView *badge = [self circleSymbol:@"checkmark.shield" tone:ToneGreen];
    NSString *when = self.model.showingSavedScan ? [NSString stringWithFormat:@"saved scan from %@", RelativeDate(self.model.lastScanDate)] : RelativeDate(self.model.lastScanDate);
    NSTextField *detail = Label([NSString stringWithFormat:@"Inspected without modifying installed tools or configurations · %@", when], 12.5, NSFontWeightRegular, ThemeSubColor());
    NSStackView *text = VStack(3, @[Label(@"Read-only scan complete", 15, NSFontWeightSemibold, ThemeTextColor()), detail]);
    NSView *divider = [self verticalHairline];
    BOOL on = self.model.monitoring;
    NSStackView *monitor = HStack(10, @[Label(@"Local monitoring", 12, NSFontWeightRegular, ThemeSubColor()), [PillView pill:on ? @"On" : @"Paused" tone:on ? ToneGreen : ToneAmber dot:YES]]);
    NSStackView *row = HStack(16, @[badge, text, divider, monitor]);
    [text setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [divider.heightAnchor constraintEqualToConstant:28].active = YES;
    if (self.model.errorMessage) {
        NSStackView *stack = VStack(14, @[]);
        FillWidth(row, stack);
        FillWidth([self notice:self.model.errorMessage], stack);
        return PaddedPanel(stack, 24);
    }
    return PaddedPanel(row, 24);
}

- (NSView *)notice:(NSString *)text {
    PanelView *box = [PanelView new];
    box.cornerRadius = 8;
    box.fill = [NSColor.systemOrangeColor colorWithAlphaComponent:0.08];
    box.border = [NSColor.systemOrangeColor colorWithAlphaComponent:0.2];
    NSStackView *row = HStack(9, @[SymbolView(@"exclamationmark.triangle", 12, NSFontWeightSemibold, NSColor.systemOrangeColor), WrappingLabel(text, 12, ThemeTextColor())]);
    row.alignment = NSLayoutAttributeFirstBaseline;
    Pin(row, box, NSEdgeInsetsMake(10, 12, 10, 12));
    return box;
}

- (NSView *)circleSymbol:(NSString *)symbol tone:(Tone)tone {
    PanelView *circle = [PanelView new];
    circle.cornerRadius = 20;
    circle.fill = ToneFillColor(tone);
    circle.border = nil;
    NSImageView *image = SymbolView(symbol, 18, NSFontWeightMedium, ToneColor(tone));
    [circle addSubview:image];
    [NSLayoutConstraint activateConstraints:@[
        [circle.widthAnchor constraintEqualToConstant:40], [circle.heightAnchor constraintEqualToConstant:40],
        [image.centerXAnchor constraintEqualToAnchor:circle.centerXAnchor], [image.centerYAnchor constraintEqualToAnchor:circle.centerYAnchor],
    ]];
    return circle;
}

- (NSView *)verticalHairline {
    NSView *line = Hairline();
    [line.widthAnchor constraintEqualToConstant:1].active = YES;
    return line;
}

#pragma mark Stats

- (NSUInteger)attentionCount {
    return self.inventory.attention.count + (self.model.monitoring ? 0 : 1);
}

- (NSView *)statsPanel {
    Inventory *inventory = self.inventory;
    NSArray *stats = @[
        @[@(inventory.developerToolCount), @"Tools discovered", @(PageTools), @NO],
        @[@(inventory.workspaces.count), @"Workspaces", @(PageWorkspaces), @NO],
        @[@(inventory.mcpServers.count + inventory.editorSettings.count), @"Configuration items", @(PageConfigurations), @NO],
        @[@([self attentionCount]), @"Warnings", @(PageActivity), @YES],
    ];
    PanelView *panel = [PanelView new];
    NSStackView *row = HStack(0, @[]);
    row.distribution = NSStackViewDistributionFill;
    row.alignment = NSLayoutAttributeTop;
    NSView *first = nil;
    for (NSArray *stat in stats) {
        if (first) {
            NSView *line = [self verticalHairline];
            [row addArrangedSubview:line];
            [line.heightAnchor constraintEqualToAnchor:row.heightAnchor].active = YES;
        }
        PressableView *cell = [PressableView new];
        BOOL warn = [stat[3] boolValue] && [stat[0] unsignedIntegerValue] > 0;
        NSTextField *value = Label([stat[0] stringValue], 28, NSFontWeightSemibold, warn ? NSColor.systemOrangeColor : ThemeTextColor());
        value.font = [NSFont monospacedDigitSystemFontOfSize:28 weight:NSFontWeightSemibold];
        NSStackView *text = VStack(8, @[value, HStack(4, @[Label(stat[1], 12, NSFontWeightRegular, ThemeSubColor()), SymbolView(@"chevron.right", 9, NSFontWeightSemibold, ThemeFaintColor())])]);
        for (NSView *view in text.arrangedSubviews) view.accessibilityElement = NO;
        Pin(text, cell, NSEdgeInsetsMake(16, 20, 16, 12));
        __weak OverviewPage *weakSelf = self;
        Page page = [stat[2] integerValue];
        cell.onPress = ^{ [weakSelf.host showPage:page]; };
        cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", stat[1], stat[0]];
        [row addArrangedSubview:cell];
        if (first) [cell.widthAnchor constraintEqualToAnchor:first.widthAnchor].active = YES;
        else first = cell;
    }
    Pin(row, panel, NSEdgeInsetsZero);
    return panel;
}

#pragma mark Scope

- (NSView *)scopePanel {
    BOOL on = self.model.monitoring;
    NSUInteger roots = self.model.approvedRoots.count;
    NSArray *columns = @[
        @[@"Discovered", @"Read-only, on every scan", @(ToneGreen), @"checkmark",
          @[@"Tools, versions and providers", @"Multiple installations per tool", @"Packages and editor extensions", @"Git branch and worktree metadata"]],
        @[@"Monitoring", on ? @"Approved paths only" : @"Paused", @(on ? ToneBlue : ToneNeutral), @"eye",
          @[@"Runtime, package and editor folders", [NSString stringWithFormat:@"%lu approved %@", (unsigned long)roots, roots == 1 ? @"workspace" : @"workspaces"], @"Rescan every 5 minutes", @"Rescan on startup and after wake"]],
        @[@"Not backed up yet", @"Later releases", @(ToneNeutral), @"circle",
          @[@"Snapshots of configuration files", @"Encrypted cloud sync", @"Restore to a replacement Mac", @"File contents and secrets"]],
    ];
    PanelView *panel = [PanelView new];
    NSStackView *row = HStack(0, @[]);
    row.alignment = NSLayoutAttributeTop;
    NSView *first = nil;
    for (NSArray *column in columns) {
        if (first) {
            NSView *line = [self verticalHairline];
            [row addArrangedSubview:line];
            [line.heightAnchor constraintEqualToAnchor:row.heightAnchor].active = YES;
        }
        Tone tone = [column[2] integerValue];
        BOOL muted = tone == ToneNeutral;
        NSTextField *title = Label(column[0], 13, NSFontWeightSemibold, muted ? ThemeSubColor() : ThemeTextColor());
        NSTextField *caption = Label(column[1], 11, NSFontWeightRegular, ThemeFaintColor());
        [caption setContentCompressionResistancePriority:280 forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *header = HStack(8, @[title, Spacer(), caption]);
        header.alignment = NSLayoutAttributeFirstBaseline;
        NSStackView *stack = VStack(10, @[]);
        FillWidth(header, stack);
        [stack setCustomSpacing:14 afterView:header];
        for (NSString *item in column[4]) {
            NSImageView *icon = SymbolView(column[3], 10, muted ? NSFontWeightRegular : NSFontWeightBold, muted ? ThemeFaintColor() : ToneColor(tone));
            [icon.widthAnchor constraintEqualToConstant:14].active = YES;
            NSStackView *line = HStack(9, @[icon, WrappingLabel(item, 12.5, muted ? ThemeFaintColor() : ThemeSubColor())]);
            line.alignment = NSLayoutAttributeFirstBaseline;
            FillWidth(line, stack);
        }
        NSView *cell = [NSView new];
        cell.translatesAutoresizingMaskIntoConstraints = NO;
        Pin(stack, cell, NSEdgeInsetsMake(20, 20, 20, 20));
        [row addArrangedSubview:cell];
        if (first) [cell.widthAnchor constraintEqualToAnchor:first.widthAnchor].active = YES;
        else first = cell;
    }
    Pin(row, panel, NSEdgeInsetsZero);
    return panel;
}

#pragma mark Lists

- (NSView *)bottomRow {
    NSButton *all = LinkButton(@"View all ›", self, @selector(viewAllTools:));
    NSView *tools = SectionWithHeader(SectionHeader(@"Developer tools", nil, all), [self toolsPanel]);
    NSView *attention = SectionWithHeader(SectionHeader(@"Needs attention", nil, nil), [self attentionPanel]);
    NSStackView *row = HStack(28, @[tools, attention]);
    row.alignment = NSLayoutAttributeTop;
    [tools.widthAnchor constraintEqualToAnchor:attention.widthAnchor multiplier:1.5].active = YES;
    return row;
}

- (void)viewAllTools:(id)sender { [self.host showPage:PageTools]; }

// Tools that changed in the last scan come first, then those with the most installs.
- (NSArray<ToolEntry *> *)featuredTools {
    NSMutableOrderedSet *changed = [NSMutableOrderedSet orderedSet];
    for (NSString *key in @[@"updated", @"added"]) for (NSDictionary *change in self.model.changes[key] ?: @[]) [changed addObject:StringValue(change[@"canonical_tool_id"], @"")];
    NSArray *tools = [self.inventory.tools filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ToolEntry *t, id b) { return t.group < ToolGroupPackages; }]];
    return [[tools sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(ToolEntry *a, ToolEntry *b) {
        BOOL ca = [changed containsObject:a.identifier], cb = [changed containsObject:b.identifier];
        if (ca != cb) return ca ? NSOrderedAscending : NSOrderedDescending;
        if (a.installations.count != b.installations.count) return a.installations.count > b.installations.count ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }] subarrayWithRange:NSMakeRange(0, MIN(5u, tools.count))];
}

- (NSView *)toolsPanel {
    NSMutableArray *rows = [NSMutableArray array];
    for (ToolEntry *tool in [self featuredTools]) {
        NSDictionary *primary = tool.primary;
        NSString *detail = ResourceProviderName(primary);
        if (tool.installations.count > 1) detail = [detail stringByAppendingFormat:@" · %lu installations", (unsigned long)tool.installations.count];
        NSStackView *text = VStack(1, @[Label(tool.name, 13, NSFontWeightRegular, ThemeTextColor()), Label(detail, 11.5, NSFontWeightRegular, ThemeFaintColor())]);
        NSTextField *version = MonoLabel(StringValue(primary[@"version"], @"—"), 12, ThemeSubColor());
        [version setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *line = HStack(12, @[[ToolGlyphView glyphForTool:tool.identifier name:tool.name size:26 muted:NO], text, Spacer(), version]);
        PressableView *row = [PressableView new];
        Pin(line, row, NSEdgeInsetsMake(9, 16, 9, 16));
        NSString *identifier = tool.identifier;
        __weak OverviewPage *weakSelf = self;
        row.onPress = ^{ [weakSelf.host showTool:identifier]; };
        row.accessibilityLabel = [NSString stringWithFormat:@"%@ %@, %@", tool.name, version.stringValue, detail];
        [rows addObject:row];
    }
    if (!rows.count) [rows addObject:[self quietRow:@"No developer tools found in the last scan."]];
    return ListPanel(rows);
}

- (NSView *)attentionPanel {
    NSMutableArray *items = [self.inventory.attention mutableCopy];
    if (!self.model.monitoring) {
        AttentionItem *item = [AttentionItem new];
        item.title = @"Monitoring is off";
        item.detail = @"Turn it on to catch installs and upgrades as they happen.";
        item.page = PageSettings;
        [items addObject:item];
    }
    NSMutableArray *rows = [NSMutableArray array];
    for (AttentionItem *item in [items subarrayWithRange:NSMakeRange(0, MIN(5u, items.count))]) {
        NSImageView *icon = SymbolView(@"exclamationmark.triangle", 11, NSFontWeightSemibold, NSColor.systemOrangeColor);
        NSTextField *detail = WrappingLabel(item.detail, 11.5, ThemeFaintColor());
        detail.maximumNumberOfLines = 3;
        NSStackView *text = VStack(2, @[Label(item.title, 13, NSFontWeightRegular, ThemeTextColor()), detail]);
        NSStackView *line = HStack(10, @[icon, text, SymbolView(@"chevron.right", 10, NSFontWeightSemibold, ThemeFaintColor())]);
        line.alignment = NSLayoutAttributeTop;
        [detail.widthAnchor constraintEqualToAnchor:text.widthAnchor].active = YES;
        PressableView *row = [PressableView new];
        Pin(line, row, NSEdgeInsetsMake(11, 16, 11, 14));
        __weak OverviewPage *weakSelf = self;
        row.onPress = ^{
            if (item.toolIdentifier) [weakSelf.host showTool:item.toolIdentifier];
            else [weakSelf.host showPage:item.page];
        };
        row.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", item.title, item.detail];
        [rows addObject:row];
    }
    if (!rows.count) [rows addObject:[self quietRow:@"Nothing needs attention."]];
    return ListPanel(rows);
}

- (NSView *)quietRow:(NSString *)text {
    NSView *row = [NSView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    Pin(HStack(9, @[SymbolView(@"checkmark.circle", 12, NSFontWeightMedium, NSColor.systemGreenColor), Label(text, 12.5, NSFontWeightRegular, ThemeSubColor())]), row, NSEdgeInsetsMake(12, 16, 12, 16));
    return row;
}

@end
