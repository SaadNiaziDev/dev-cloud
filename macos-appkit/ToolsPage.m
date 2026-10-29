#import "Pages.h"

static NSArray<NSString *> *Filters(void) { return @[@"All", @"Runtimes", @"Managers", @"Editors", @"Packages", @"Extensions", @"Other"]; }

static BOOL InFilter(ToolEntry *tool, NSInteger filter) {
    switch (filter) {
        case 1: return tool.group == ToolGroupRuntimes;
        case 2: return tool.group == ToolGroupManagers;
        case 3: return tool.group == ToolGroupEditors;
        case 4: return tool.group == ToolGroupPackages;
        case 5: return tool.group == ToolGroupExtensions;
        case 6: return tool.group == ToolGroupOther;
        default: return YES;
    }
}

// Rounded blue selection inset from the table edges, as in Finder lists.
@interface ToolRowView : NSTableRowView
@end
@implementation ToolRowView
- (void)drawSelectionInRect:(NSRect)rect {
    [(self.emphasized ? NSColor.systemBlueColor : ThemeSelectionColor()) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 8, 1) xRadius:6 yRadius:6] fill];
}
- (void)drawBackgroundInRect:(NSRect)rect {
    if (self.groupRowStyle) return;
    [super drawBackgroundInRect:rect];
}
@end

// Recolours its labels white on the emphasized selection.
@interface ToolCell : NSTableCellView
@property(nonatomic, strong) NSMutableArray<NSArray *> *tinted;
@end
@implementation ToolCell
- (void)tint:(NSTextField *)label color:(NSColor *)color selected:(CGFloat)alpha {
    if (!self.tinted) self.tinted = [NSMutableArray array];
    [self.tinted addObject:@[label, color, @(alpha)]];
}
- (void)setBackgroundStyle:(NSBackgroundStyle)style {
    [super setBackgroundStyle:style];
    for (NSArray *entry in self.tinted) {
        NSTextField *label = entry[0];
        label.textColor = style == NSBackgroundStyleEmphasized ? [NSColor.whiteColor colorWithAlphaComponent:[entry[2] doubleValue]] : entry[1];
    }
}
@end

@interface ToolsPage () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate>
@end

@implementation ToolsPage {
    NSSegmentedControl *_filter;
    NSSearchField *_search;
    NSTableView *_table;
    NSTextField *_footer;
    NSStackView *_inspector;
    NSArray *_rows;
    NSString *_selectedIdentifier;
    NSUInteger _detectedCount;
    NSUInteger _missingCount;
}

- (instancetype)initWithHost:(id<PageHost>)host {
    self = [super initWithHost:host];
    if (!self) return nil;
    _filter = [NSSegmentedControl segmentedControlWithLabels:Filters() trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(filterChanged:)];
    _filter.selectedSegment = 0;
    _filter.controlSize = NSControlSizeRegular;
    _filter.segmentDistribution = NSSegmentDistributionFit;
    _filter.accessibilityLabel = @"Filter tools";
    _filter.translatesAutoresizingMaskIntoConstraints = NO;
    _search = [NSSearchField new];
    _search.placeholderString = @"Search tools";
    _search.delegate = self;
    _search.translatesAutoresizingMaskIntoConstraints = NO;
    [_search.widthAnchor constraintEqualToConstant:220].active = YES;
    NSStackView *bar = HStack(12, @[_filter, Spacer(), _search]);
    bar.edgeInsets = NSEdgeInsetsMake(12, 20, 12, 20);

    _table = [NSTableView new];
    _table.dataSource = self;
    _table.delegate = self;
    _table.style = NSTableViewStylePlain;
    _table.rowHeight = 42;
    _table.intercellSpacing = NSMakeSize(12, 0);
    _table.backgroundColor = NSColor.clearColor;
    _table.gridStyleMask = NSTableViewGridNone;
    _table.floatsGroupRows = NO;
    _table.allowsEmptySelection = YES;
    _table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    _table.accessibilityLabel = @"Discovered tools";
    for (NSArray *spec in @[@[@"name", @"Name", @240], @[@"version", @"Version", @96], @[@"provider", @"Provider", @120], @[@"confidence", @"Confidence", @100]]) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        column.minWidth = [spec[0] isEqual:@"name"] ? 160 : [spec[2] doubleValue];
        column.resizingMask = [spec[0] isEqual:@"name"] ? NSTableColumnAutoresizingMask : NSTableColumnNoResizing;
        column.headerCell.font = ThemeFont(11, NSFontWeightMedium);
        [_table addTableColumn:column];
    }
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    _table.menu = menu;
    NSScrollView *scroll = [NSScrollView new];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;

    _footer = Label(@"", 11, NSFontWeightRegular, ThemeFaintColor());
    NSView *footerBar = [NSView new];
    footerBar.translatesAutoresizingMaskIntoConstraints = NO;
    Pin(_footer, footerBar, NSEdgeInsetsMake(8, 20, 8, 20));

    NSStackView *list = VStack(0, @[]);
    FillWidth(bar, list);
    FillWidth(Hairline(), list);
    FillWidth(scroll, list);
    FillWidth(Hairline(), list);
    FillWidth(footerBar, list);
    [scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];

    PageScrollView *inspectorScroll = [[PageScrollView alloc] initWithMaxWidth:400 inset:20];
    _inspector = inspectorScroll.column;
    _inspector.spacing = 22;
    NSView *divider = Hairline();
    [divider.widthAnchor constraintEqualToConstant:1].active = YES;

    [self addSubview:list];
    [self addSubview:divider];
    [self addSubview:inspectorScroll];
    [NSLayoutConstraint activateConstraints:@[
        [list.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [list.topAnchor constraintEqualToAnchor:self.topAnchor],
        [list.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [divider.leadingAnchor constraintEqualToAnchor:list.trailingAnchor],
        [divider.topAnchor constraintEqualToAnchor:self.topAnchor],
        [divider.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [inspectorScroll.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor],
        [inspectorScroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [inspectorScroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [inspectorScroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [inspectorScroll.widthAnchor constraintEqualToConstant:330],
    ]];
    return self;
}

- (NSString *)signature {
    return [NSString stringWithFormat:@"%p|%ld|%@|%@", self.model.report, (long)_filter.selectedSegment, _search.stringValue, RelativeDate(self.model.lastScanDate)];
}

- (void)rebuild {
    Inventory *inventory = self.inventory;
    NSString *query = [_search.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    BOOL (^visible)(ToolEntry *) = ^BOOL(ToolEntry *tool) { return InFilter(tool, self->_filter.selectedSegment) && (!query.length || [tool matches:query]); };
    NSMutableArray *rows = [NSMutableArray array];
    for (ToolEntry *tool in inventory.tools) if (visible(tool)) [rows addObject:tool];
    _detectedCount = rows.count;
    NSArray *missing = [inventory.missing filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ToolEntry *t, id b) { return visible(t); }]];
    _missingCount = missing.count;
    if (missing.count) {
        [rows addObject:@"Not detected"];
        [rows addObjectsFromArray:missing];
    }
    _rows = rows;
    [_table reloadData];
    _footer.stringValue = self.model.report ? [NSString stringWithFormat:@"%lu detected · %lu not detected", (unsigned long)_detectedCount, (unsigned long)_missingCount] : @"No scan yet";
    NSUInteger index = [_rows indexOfObjectPassingTest:^BOOL(id row, NSUInteger i, BOOL *s) { return [row isKindOfClass:ToolEntry.class] && [[row identifier] isEqual:self->_selectedIdentifier]; }];
    if (index == NSNotFound) index = [_rows indexOfObjectPassingTest:^BOOL(id row, NSUInteger i, BOOL *s) { return [row isKindOfClass:ToolEntry.class]; }];
    if (index != NSNotFound) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        [_table scrollRowToVisible:(NSInteger)index];
    }
    [self updateInspector];
}

- (void)selectTool:(NSString *)identifier {
    _selectedIdentifier = identifier;
    _search.stringValue = @"";
    _filter.selectedSegment = 0;
    [self reload];
    [self.window makeFirstResponder:_table];
}

- (void)focusSearch { [self.window makeFirstResponder:_search]; }
- (void)filterChanged:(id)sender { [self reload]; }

- (void)controlTextDidChange:(NSNotification *)notification { [self reload]; }

- (ToolEntry *)selectedTool {
    NSInteger row = _table.selectedRow;
    return row >= 0 && [_rows[(NSUInteger)row] isKindOfClass:ToolEntry.class] ? _rows[(NSUInteger)row] : nil;
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)_rows.count; }
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row { return [_rows[(NSUInteger)row] isKindOfClass:NSString.class]; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return ![self tableView:tableView isGroupRow:row]; }
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row { return [self tableView:tableView isGroupRow:row] ? 34 : 42; }
- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row { return [ToolRowView new]; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    id item = _rows[(NSUInteger)row];
    ToolCell *cell = [ToolCell new];
    if ([item isKindOfClass:NSString.class]) {
        NSTextField *label = Label(item, 11, NSFontWeightSemibold, ThemeFaintColor());
        [cell addSubview:label];
        [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:20], [label.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-6]]];
        return cell;
    }
    ToolEntry *tool = item;
    NSDictionary *primary = tool.primary;
    NSString *key = column.identifier;
    NSView *content;
    if ([key isEqual:@"name"]) {
        NSTextField *name = Label(tool.name, 13, NSFontWeightRegular, tool.detected ? ThemeTextColor() : ThemeFaintColor());
        [cell tint:name color:name.textColor selected:1];
        NSStackView *title = HStack(5, @[name]);
        if (tool.warnings.count) [title addArrangedSubview:SymbolView(@"exclamationmark.triangle.fill", 9, NSFontWeightSemibold, NSColor.systemOrangeColor)];
        NSString *detail = tool.installations.count > 1 ? [NSString stringWithFormat:@"%@ · %lu installations", tool.category, (unsigned long)tool.installations.count] : tool.category;
        NSTextField *sub = Label(detail, 11, NSFontWeightRegular, ThemeFaintColor());
        [cell tint:sub color:sub.textColor selected:0.7];
        content = HStack(10, @[[ToolGlyphView glyphForTool:tool.identifier name:tool.name size:26 muted:!tool.detected], VStack(1, @[title, sub])]);
        cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@%@", tool.name, detail, tool.warnings.count ? @", has warnings" : @""];
    } else if ([key isEqual:@"confidence"] && tool.detected) {
        NSInteger level = ResourceConfidence(primary);
        NSTextField *label = Label(ConfidenceName(level), 12, NSFontWeightRegular, ThemeSubColor());
        [cell tint:label color:label.textColor selected:0.85];
        content = HStack(7, @[[ConfidenceMeter meterWithLevel:level showLabel:NO], label]);
    } else {
        NSString *text = [key isEqual:@"version"] ? StringValue(primary[@"version"], @"—") : (tool.detected ? ResourceProviderName(primary) : @"Not detected");
        if ([key isEqual:@"confidence"]) text = @"—";
        NSTextField *label = [key isEqual:@"version"] ? MonoLabel(text, 12, tool.detected ? ThemeSubColor() : ThemeFaintColor()) : Label(text, 12, NSFontWeightRegular, tool.detected ? ThemeSubColor() : ThemeFaintColor());
        [cell tint:label color:label.textColor selected:0.85];
        content = label;
    }
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:[key isEqual:@"name"] ? 14 : 0],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor],
        [content.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    ToolEntry *tool = [self selectedTool];
    if (tool) _selectedIdentifier = tool.identifier;
    [self updateInspector];
}

#pragma mark Inspector

- (void)updateInspector {
    for (NSView *view in _inspector.arrangedSubviews) { [_inspector removeArrangedSubview:view]; [view removeFromSuperview]; }
    ToolEntry *tool = [self selectedTool];
    if (!tool) {
        FillWidth(WrappingLabel(self.model.report ? @"Select a tool to see its installations and evidence." : @"Scan this Mac to list its tools.", 12.5, ThemeFaintColor()), _inspector);
        return;
    }
    NSDictionary *primary = tool.primary;
    PillView *status = !tool.detected ? [PillView pill:@"Not detected" tone:ToneNeutral dot:NO]
        : (tool.warnings.count ? [PillView pill:@"Review" tone:ToneAmber dot:YES] : [PillView pill:@"Detected" tone:ToneGreen dot:YES]);
    NSTextField *name = Label(tool.name, 17, NSFontWeightSemibold, ThemeTextColor());
    name.selectable = YES;
    NSStackView *heading = HStack(14, @[[ToolGlyphView glyphForTool:tool.identifier name:tool.name size:44 muted:!tool.detected],
                                        VStack(5, @[name, HStack(8, @[Label(tool.category, 12, NSFontWeightRegular, ThemeFaintColor()), status])])]);
    FillWidth(heading, _inspector);

    if (!tool.detected) {
        FillWidth([self box:@"circle.slash" text:@"This tool is not installed on this Mac, or it is outside the locations discovery checks. This is not an error." tone:ToneNeutral], _inspector);
        return;
    }

    NSGridView *facts = [NSGridView gridViewWithNumberOfColumns:2 rows:0];
    facts.rowSpacing = 9;
    facts.columnSpacing = 12;
    void (^fact)(NSString *, NSView *) = ^(NSString *label, NSView *value) {
        [facts addRowWithViews:@[Label(label, 12.5, NSFontWeightRegular, ThemeFaintColor()), value]];
    };
    fact(@"Version", MonoLabel(StringValue(primary[@"version"], @"Not recorded"), 12.5, ThemeTextColor()));
    fact(@"Provider", Label(ResourceProviderName(primary), 12.5, NSFontWeightRegular, ThemeTextColor()));
    if (StringValue(primary[@"provider_package_id"], nil)) fact(@"Package", MonoLabel(primary[@"provider_package_id"], 12.5, ThemeTextColor()));
    fact(@"Adapter", MonoLabel(StringValue(primary[@"discovery_adapter"], @"—"), 12.5, ThemeTextColor()));
    fact(@"Confidence", [ConfidenceMeter meterWithLevel:ResourceConfidence(primary) showLabel:YES]);
    fact(@"Observed", Label(RelativeDate(self.model.lastScanDate), 12.5, NSFontWeightRegular, ThemeTextColor()));
    [facts columnAtIndex:0].width = 86;
    FillWidth(facts, _inspector);

    for (NSString *warning in tool.warnings) FillWidth([self box:@"exclamationmark.triangle" text:warning tone:ToneAmber], _inspector);

    NSStackView *installs = VStack(6, @[]);
    for (NSDictionary *resource in tool.installations) FillWidth([self installationCard:resource], installs);
    FillWidth([self titled:[NSString stringWithFormat:@"INSTALLATIONS · %lu", (unsigned long)tool.installations.count] body:installs], _inspector);

    NSMutableOrderedSet *evidence = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *resource in tool.installations) {
        for (id line in resource[@"evidence"] ?: @[]) {
            if ([line isKindOfClass:NSString.class]) [evidence addObject:[NSString stringWithFormat:@"%@ %@ → %@", ResourceProviderName(resource), StringValue(resource[@"version"], @"?"), line]];
        }
    }
    if (evidence.count) {
        PanelView *well = [PanelView new];
        well.fill = ThemeWellColor();
        well.border = nil;
        well.cornerRadius = 8;
        NSTextField *lines = WrappingLabel([evidence.array componentsJoinedByString:@"\n"], 11, ThemeSubColor());
        lines.font = ThemeMono(11);
        lines.selectable = YES;
        Pin(lines, well, NSEdgeInsetsMake(10, 12, 10, 12));
        FillWidth([self titled:@"EVIDENCE" body:well], _inspector);
    }

    NSButton *copy = PushButton(@"Copy Details", NO, self, @selector(copyDetails:));
    NSStackView *footer = VStack(12, @[]);
    FillWidth(Hairline(), footer);
    NSStackView *note = HStack(9, @[SymbolView(@"info.circle", 11, NSFontWeightRegular, ThemeFaintColor()), WrappingLabel(@"Restore support is planned for a later release. Nothing about this tool is backed up today.", 11.5, ThemeFaintColor())]);
    note.alignment = NSLayoutAttributeFirstBaseline;
    FillWidth(note, footer);
    [footer addArrangedSubview:copy];
    FillWidth(footer, _inspector);
}

- (NSView *)titled:(NSString *)title body:(NSView *)body {
    NSStackView *stack = VStack(8, @[Label(title, 11, NSFontWeightSemibold, ThemeFaintColor())]);
    FillWidth(body, stack);
    return stack;
}

- (NSView *)box:(NSString *)symbol text:(NSString *)text tone:(Tone)tone {
    PanelView *box = [PanelView new];
    box.cornerRadius = 8;
    box.fill = tone == ToneNeutral ? ThemePanelColor() : [ToneColor(tone) colorWithAlphaComponent:0.07];
    box.border = tone == ToneNeutral ? nil : [ToneColor(tone) colorWithAlphaComponent:0.2];
    NSStackView *row = HStack(9, @[SymbolView(symbol, 11, NSFontWeightSemibold, tone == ToneNeutral ? ThemeFaintColor() : ToneColor(tone)), WrappingLabel(text, 12, tone == ToneNeutral ? ThemeSubColor() : ThemeTextColor())]);
    row.alignment = NSLayoutAttributeFirstBaseline;
    Pin(row, box, NSEdgeInsetsMake(10, 12, 10, 12));
    return box;
}

- (NSView *)installationCard:(NSDictionary *)resource {
    PanelView *card = [PanelView new];
    card.cornerRadius = 8;
    NSString *provider = ResourceProviderName(resource);
    NSView *badge = [resource[@"path_status"] isEqual:@"first_on_path"] ? [PillView pill:@"On PATH first" tone:ToneBlue dot:NO]
        : Label([resource[@"path_status"] isEqual:@"also_on_path"] ? @"Later on PATH" : @"Not on PATH", 11, NSFontWeightRegular, ThemeFaintColor());
    NSStackView *stack = VStack(6, @[]);
    FillWidth(HStack(8, @[MonoLabel(StringValue(resource[@"version"], @"version unknown"), 12.5, ThemeTextColor()), Spacer(), badge]), stack);
    NSString *path = StringValue(resource[@"installation_path"], nil);
    if (path) {
        NSTextField *location = MonoLabel([path stringByAbbreviatingWithTildeInPath], 11, ThemeFaintColor());
        location.toolTip = path;
        FillWidth(location, stack);
    }
    FillWidth(HStack(8, @[Label(provider, 11.5, NSFontWeightRegular, ThemeSubColor()), Spacer(), [ConfidenceMeter meterWithLevel:ResourceConfidence(resource) showLabel:YES]]), stack);
    Pin(stack, card, NSEdgeInsetsMake(10, 12, 10, 12));
    return card;
}

#pragma mark Copy and reveal

- (ToolEntry *)actionTool {
    NSInteger row = _table.clickedRow >= 0 ? _table.clickedRow : _table.selectedRow;
    return row >= 0 && [_rows[(NSUInteger)row] isKindOfClass:ToolEntry.class] ? _rows[(NSUInteger)row] : nil;
}

- (void)copyString:(NSString *)string {
    if (!string.length) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:string forType:NSPasteboardTypeString];
}

- (void)copyDetails:(id)sender {
    ToolEntry *tool = [self actionTool];
    if (!tool) return;
    NSMutableArray *lines = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@ (%@)", tool.name, tool.category]];
    for (NSDictionary *resource in tool.installations) {
        NSString *path = StringValue(resource[@"installation_path"], nil);
        [lines addObject:[NSString stringWithFormat:@"- %@ · %@%@", StringValue(resource[@"version"], @"version unknown"), ResourceProviderName(resource), path ? [@" · " stringByAppendingString:path] : @""]];
    }
    [self copyString:[lines componentsJoinedByString:@"\n"]];
    [self.host toast:@"Copied details" detail:tool.name];
}

- (void)copy:(id)sender { [self copyDetails:sender]; }
- (void)copyName:(id)sender { [self copyString:[self actionTool].name]; }
- (void)copyVersion:(id)sender { [self copyString:StringValue([self actionTool].primary[@"version"], nil)]; }

- (void)revealInFinder:(id)sender {
    NSMutableArray *urls = [NSMutableArray array];
    for (NSDictionary *resource in [self actionTool].installations) {
        NSString *path = StringValue(resource[@"installation_path"], nil);
        if (path) [urls addObject:[NSURL fileURLWithPath:path]];
    }
    if (urls.count) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:urls];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    ToolEntry *tool = [self actionTool];
    if (!tool.detected) return;
    [menu addItemWithTitle:@"Copy Name" action:@selector(copyName:) keyEquivalent:@""].target = self;
    if (StringValue(tool.primary[@"version"], nil)) [menu addItemWithTitle:@"Copy Version" action:@selector(copyVersion:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"Copy Details" action:@selector(copyDetails:) keyEquivalent:@""].target = self;
    if (StringValue(tool.primary[@"installation_path"], nil)) {
        [menu addItem:NSMenuItem.separatorItem];
        [menu addItemWithTitle:@"Show in Finder" action:@selector(revealInFinder:) keyEquivalent:@""].target = self;
    }
}

@end
