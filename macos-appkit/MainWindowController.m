#import "MainWindowController.h"
#import "BrandMark.h"

static NSToolbarItemIdentifier const StatusItem = @"status";
static NSToolbarItemIdentifier const ActionsItem = @"actions";

@interface FilledView : NSView
@property(nonatomic, strong) NSColor *fill;
@end
@implementation FilledView
- (void)drawRect:(NSRect)rect {
    [self.fill setFill];
    NSRectFill(rect);
}
@end

#pragma mark - Sidebar

@interface SidebarItem : PressableView
@property(nonatomic, strong) NSTextField *count;
@end
// ⌘1–⌘6 navigate, so sidebar rows never take focus from page content.
@implementation SidebarItem
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)canBecomeKeyView { return NO; }
@end

@interface SidebarView : FilledView
@property(nonatomic, copy) void (^onSelect)(Page page);
@property(nonatomic, strong) NSMutableArray<SidebarItem *> *items;
@property(nonatomic, strong) NSTextField *machineDetail;
@property(nonatomic, strong) NSStackView *monitorRow;
- (void)updatePage:(Page)page counts:(NSDictionary<NSNumber *, NSNumber *> *)counts host:(NSDictionary *)host monitoring:(BOOL)monitoring;
@end

@implementation SidebarView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.fill = ThemeSidebarColor();
    self.items = [NSMutableArray array];
    NSStackView *nav = VStack(1, @[]);
    __block NSString *group = nil;
    [PageCatalog() enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger index, BOOL *stop) {
        if (![entry[@"group"] isEqual:group]) {
            group = entry[@"group"];
            if (index > 0) [nav setCustomSpacing:18 afterView:nav.arrangedSubviews.lastObject];
            if (group.length) {
                NSStackView *header = VStack(0, @[Label(group, 11, NSFontWeightSemibold, ThemeFaintColor())]);
                header.edgeInsets = NSEdgeInsetsMake(0, 10, 4, 10);
                FillWidth(header, nav);
            }
        }
        SidebarItem *item = [self itemFor:entry index:index];
        FillWidth(item, nav);
        [self.items addObject:item];
    }];

    NSView *machine = [self machineCard];
    [self addSubview:nav];
    [self addSubview:machine];
    [NSLayoutConstraint activateConstraints:@[
        [nav.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [nav.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [nav.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:6],
        [machine.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [machine.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [machine.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        [machine.topAnchor constraintGreaterThanOrEqualToAnchor:nav.bottomAnchor constant:12],
    ]];
    return self;
}

- (SidebarItem *)itemFor:(NSDictionary *)entry index:(NSUInteger)index {
    SidebarItem *item = [SidebarItem new];
    item.cornerRadius = 6;
    NSImageView *icon = SymbolView(entry[@"symbol"], 13, NSFontWeightRegular, NSColor.systemBlueColor);
    [icon.widthAnchor constraintEqualToConstant:18].active = YES;
    item.count = Label(@"", 11.5, NSFontWeightRegular, ThemeFaintColor());
    item.count.font = [NSFont monospacedDigitSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    NSStackView *row = HStack(9, @[icon, Label(entry[@"title"], 13, NSFontWeightRegular, ThemeTextColor()), Spacer(), item.count]);
    for (NSView *view in row.arrangedSubviews) view.accessibilityElement = NO;
    Pin(row, item, NSEdgeInsetsMake(0, 10, 0, 10));
    [item.heightAnchor constraintEqualToConstant:28].active = YES;
    __weak SidebarView *weakSelf = self;
    item.onPress = ^{ if (weakSelf.onSelect) weakSelf.onSelect((Page)index); };
    item.accessibilityLabel = entry[@"title"];
    return item;
}

- (NSView *)machineCard {
    NSImageView *laptop = SymbolView(@"laptopcomputer", 14, NSFontWeightRegular, ThemeSubColor());
    NSTextField *name = Label(NSHost.currentHost.localizedName ?: @"This Mac", 12.5, NSFontWeightMedium, ThemeTextColor());
    self.machineDetail = Label(@"", 11, NSFontWeightRegular, ThemeFaintColor());
    NSStackView *top = HStack(10, @[laptop, VStack(1, @[name, self.machineDetail])]);
    self.monitorRow = HStack(8, @[]);
    NSStackView *stack = VStack(10, @[]);
    FillWidth(top, stack);
    FillWidth(Hairline(), stack);
    FillWidth(self.monitorRow, stack);
    PanelView *card = PaddedPanel(stack, 12);
    card.cornerRadius = 9;
    return card;
}

- (void)updatePage:(Page)page counts:(NSDictionary<NSNumber *, NSNumber *> *)counts host:(NSDictionary *)host monitoring:(BOOL)monitoring {
    [self.items enumerateObjectsUsingBlock:^(SidebarItem *item, NSUInteger index, BOOL *stop) {
        item.selected = (Page)index == page;
        NSNumber *count = counts[@(index)];
        item.count.stringValue = count ? count.stringValue : @"";
        NSString *title = PageCatalog()[index][@"title"];
        item.accessibilityLabel = count ? [NSString stringWithFormat:@"%@, %@", title, count] : title;
        item.accessibilitySelected = item.selected;
    }];
    NSString *chip = [host[@"architecture"] isEqual:@"aarch64"] ? @"Apple silicon" : ([host[@"architecture"] length] ? @"Intel" : nil);
    NSString *os = StringValue(host[@"os_version"], nil);
    self.machineDetail.stringValue = os ? [NSString stringWithFormat:@"macOS %@ · %@", os, chip] : @"Not scanned yet";
    for (NSView *view in self.monitorRow.arrangedSubviews) { [self.monitorRow removeArrangedSubview:view]; [view removeFromSuperview]; }
    [self.monitorRow addArrangedSubview:[StatusDot dotWithTone:monitoring ? ToneGreen : ToneAmber]];
    [self.monitorRow addArrangedSubview:Label(monitoring ? @"Monitoring locally" : @"Monitoring paused", 11, NSFontWeightRegular, ThemeSubColor())];
}

@end

#pragma mark - Toast

@interface ToastView : PanelView
@property(nonatomic) NSUInteger generation;
@end
@implementation ToastView
@end

#pragma mark - Window controller

@interface MainWindowController () <NSToolbarDelegate>
@property(nonatomic, strong, readwrite) ScanModel *model;
@property(nonatomic, readwrite) Page currentPage;
@property(nonatomic, strong) SidebarView *sidebar;
@property(nonatomic, strong) NSView *content;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, PageView *> *pages;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) ProgressBar *statusProgress;
@property(nonatomic, strong) NSToolbarItemGroup *actions;
@property(nonatomic, strong) ToastView *toastView;
@property(nonatomic, strong) NSTimer *clock;
@property(nonatomic, strong) NSDictionary<NSString *, NSSwitch *> *exportOptions;
@property(nonatomic) BOOL wasScanning;
@end

@implementation MainWindowController

- (instancetype)initWithModel:(ScanModel *)model {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 760)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (!self) return nil;
    _model = model;
    _pages = [NSMutableDictionary dictionary];
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    window.backgroundColor = ThemeWindowColor();
    [self buildContent];
    [self installToolbar];
    [window setContentSize:NSMakeSize(1180, 760)];
    window.minSize = NSMakeSize(1040, 620);
    [window center];
    window.frameAutosaveName = @"DevCloudMainWindow";
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(modelChanged:) name:ScanModelDidChangeNotification object:model];
    __weak MainWindowController *weakSelf = self;
    // Keeps "2 min ago" labels current.
    _clock = [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
    _clock.tolerance = 5;
    [self showPage:PageOverview];
    return self;
}

- (void)dealloc {
    [_clock invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)buildContent {
    NSSplitViewController *split = [NSSplitViewController new];
    NSViewController *sidebarController = [NSViewController new];
    self.sidebar = [SidebarView new];
    __weak MainWindowController *weakSelf = self;
    self.sidebar.onSelect = ^(Page page) { [weakSelf showPage:page]; };
    sidebarController.view = self.sidebar;
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarController];
    sidebarItem.minimumThickness = 228;
    sidebarItem.maximumThickness = 228;
    sidebarItem.canCollapse = YES;
    [split addSplitViewItem:sidebarItem];

    NSViewController *detailController = [NSViewController new];
    FilledView *detail = [FilledView new];
    detail.fill = ThemeWindowColor();
    detailController.view = detail;
    self.content = [NSView new];
    self.content.translatesAutoresizingMaskIntoConstraints = NO;
    [detail addSubview:self.content];
    [NSLayoutConstraint activateConstraints:@[
        [self.content.topAnchor constraintEqualToAnchor:detail.safeAreaLayoutGuide.topAnchor],
        [self.content.leadingAnchor constraintEqualToAnchor:detail.leadingAnchor],
        [self.content.trailingAnchor constraintEqualToAnchor:detail.trailingAnchor],
        [self.content.bottomAnchor constraintEqualToAnchor:detail.bottomAnchor],
        [detail.widthAnchor constraintGreaterThanOrEqualToConstant:780],
        [detail.heightAnchor constraintGreaterThanOrEqualToConstant:520],
    ]];
    [split addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:detailController]];
    self.window.contentViewController = split;
}

#pragma mark Toolbar

- (void)installToolbar {
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"DevCloudToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    self.window.toolbar = toolbar;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarSidebarTrackingSeparatorItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, StatusItem, ActionsItem];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return [self toolbarDefaultItemIdentifiers:toolbar]; }

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    if ([identifier isEqual:StatusItem]) {
        self.statusLabel = Label(@"", 11.5, NSFontWeightRegular, ThemeFaintColor());
        [self.statusLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        self.statusProgress = [ProgressBar barWithHeight:4];
        [self.statusProgress.widthAnchor constraintEqualToConstant:84].active = YES;
        NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
        item.view = HStack(10, @[self.statusLabel, self.statusProgress]);
        item.label = @"Scan status";
        item.bordered = NO;
        return item;
    }
    if ([identifier isEqual:ActionsItem]) {
        NSArray *images = @[[NSImage imageWithSystemSymbolName:@"square.and.arrow.up" accessibilityDescription:@"Export JSON"],
                            [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"Scan Now"]];
        self.actions = [NSToolbarItemGroup groupWithItemIdentifier:identifier images:images selectionMode:NSToolbarItemGroupSelectionModeMomentary
                                                            labels:@[@"Export JSON…", @"Scan Now"] target:self action:@selector(toolbarAction:)];
        self.actions.subitems[0].toolTip = @"Export JSON… (⌘E)";
        self.actions.subitems[1].toolTip = @"Scan now (⌘R)";
        self.actions.autovalidates = NO;
        return self.actions;
    }
    return nil;
}

- (void)toolbarAction:(NSToolbarItemGroup *)group {
    if (group.selectedIndex == 0) [self exportReport:group];
    else [self scanNow:group];
}

#pragma mark Pages

- (PageView *)pageFor:(Page)page {
    PageView *view = self.pages[@(page)];
    if (view) return view;
    NSArray<Class> *classes = @[OverviewPage.class, ToolsPage.class, WorkspacesPage.class, ConfigurationsPage.class, ActivityPage.class, SettingsPage.class];
    view = [[classes[(NSUInteger)page] alloc] initWithHost:self];
    self.pages[@(page)] = view;
    return view;
}

- (void)showPage:(Page)page {
    PageView *view = [self pageFor:page];
    if (view.superview != self.content) {
        for (NSView *subview in [self.content.subviews copy]) if (subview != self.toastView) [subview removeFromSuperview];
        [self.content addSubview:view positioned:NSWindowBelow relativeTo:self.toastView];
        Pin(view, self.content, NSEdgeInsetsZero);
    }
    self.currentPage = page;
    NSDictionary *entry = PageCatalog()[(NSUInteger)page];
    self.window.title = entry[@"title"];
    self.window.subtitle = entry[@"subtitle"];
    [self refresh];
}

- (void)showTool:(NSString *)identifier {
    [self showPage:PageTools];
    [(ToolsPage *)[self pageFor:PageTools] selectTool:identifier];
}

- (void)focusSearch {
    [self showWindow:nil];
    [self showPage:PageTools];
    [(ToolsPage *)[self pageFor:PageTools] focusSearch];
}

#pragma mark Refresh

- (void)modelChanged:(NSNotification *)notification {
    BOOL finished = self.wasScanning && !self.model.scanning;
    self.wasScanning = self.model.scanning;
    [self refresh];
    if (finished && self.model.report && !self.model.errorMessage) {
        Inventory *inventory = [Inventory inventoryForModel:self.model];
        NSString *changes = self.model.changeSummary;
        [self toast:@"Scan complete" detail:[NSString stringWithFormat:@"Read-only · %lu tools · %lu %@%@", (unsigned long)inventory.developerToolCount,
                                             (unsigned long)inventory.attention.count, inventory.attention.count == 1 ? @"warning" : @"warnings", changes ? [@" · " stringByAppendingString:changes] : @""]];
    }
}

- (void)refresh {
    ScanModel *model = self.model;
    Inventory *inventory = [Inventory inventoryForModel:model];
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    if (model.report) {
        counts[@(PageTools)] = @(inventory.developerToolCount);
        counts[@(PageWorkspaces)] = @(model.approvedRoots.count);
        counts[@(PageConfigurations)] = @(inventory.mcpServers.count + inventory.editorSettings.count);
    }
    [self.sidebar updatePage:self.currentPage counts:counts host:model.report[@"host"] monitoring:model.monitoring];

    if (model.scanning) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@…", model.phase ?: @"Scanning"];
        self.statusLabel.textColor = ThemeSubColor();
        self.statusProgress.value = model.progress > 0 ? model.progress : MIN(0.9, 0.12 + model.completedPhases.count * 0.16);
    } else {
        self.statusLabel.stringValue = model.errorMessage ? @"Last scan failed" : (model.report ? [NSString stringWithFormat:@"Scanned %@", RelativeDate(model.lastScanDate)] : @"Not scanned yet");
        self.statusLabel.textColor = model.errorMessage ? NSColor.systemOrangeColor : ThemeFaintColor();
    }
    self.statusProgress.hidden = !model.scanning;
    self.actions.subitems[0].enabled = model.report != nil;
    self.actions.subitems[1].enabled = !model.scanning;
    [self.pages[@(self.currentPage)] reload];
}

#pragma mark Actions

- (void)scanNow:(id)sender { [self.model scan]; }

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(exportReport:)) return self.model.report != nil;
    if (item.action == @selector(scanNow:)) return !self.model.scanning;
    return YES;
}

- (void)toast:(NSString *)title detail:(NSString *)detail {
    [self.toastView removeFromSuperview];
    ToastView *toast = [ToastView new];
    toast.cornerRadius = 12;
    toast.fill = [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        BOOL dark = [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua];
        return dark ? [NSColor colorWithSRGBRed:40 / 255.0 green:40 / 255.0 blue:42 / 255.0 alpha:0.97] : [NSColor colorWithWhite:1 alpha:0.98];
    }];
    toast.border = [ThemeTextColor() colorWithAlphaComponent:0.12];
    toast.wantsLayer = YES;
    toast.layer.shadowColor = NSColor.blackColor.CGColor;
    toast.layer.shadowOpacity = 0.35;
    toast.layer.shadowRadius = 14;
    toast.layer.shadowOffset = CGSizeMake(0, -6);
    NSStackView *text = VStack(2, @[Label(title, 13, NSFontWeightMedium, ThemeTextColor())]);
    if (detail.length) [text addArrangedSubview:Label(detail, 12, NSFontWeightRegular, ThemeSubColor())];
    NSStackView *row = HStack(10, @[SymbolView(@"checkmark.circle.fill", 15, NSFontWeightMedium, NSColor.systemGreenColor), text]);
    row.alignment = NSLayoutAttributeTop;
    Pin(row, toast, NSEdgeInsetsMake(12, 14, 12, 16));
    [self.content addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor constant:-18],
        [toast.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor constant:-18],
        [toast.widthAnchor constraintLessThanOrEqualToConstant:380],
    ]];
    toast.accessibilityElement = YES;
    toast.accessibilityRole = NSAccessibilityStaticTextRole;
    toast.accessibilityLabel = detail.length ? [NSString stringWithFormat:@"%@. %@", title, detail] : title;
    NSAccessibilityPostNotificationWithUserInfo(NSApp.mainWindow ?: self.window, NSAccessibilityAnnouncementRequestedNotification,
                                               @{NSAccessibilityAnnouncementKey: toast.accessibilityLabel, NSAccessibilityPriorityKey: @(NSAccessibilityPriorityMedium)});
    self.toastView = toast;
    // Enters and leaves through the same edge, so it reads as one object.
    [toast layoutSubtreeIfNeeded];
    AnimateIn(@[toast], 16, 0);
    __weak MainWindowController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf.toastView != toast) return;
        AnimateOut(toast, 8, ^{ if (weakSelf.toastView == toast) { [toast removeFromSuperview]; weakSelf.toastView = nil; } });
    });
}

#pragma mark Sheets

- (NSWindow *)sheetWithBody:(NSView *)body buttons:(NSArray<NSButton *> *)buttons width:(CGFloat)width {
    NSPanel *sheet = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, 200) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskDocModalWindow backing:NSBackingStoreBuffered defer:YES];
    NSStackView *bar = HStack(8, @[Spacer()]);
    for (NSButton *button in buttons) [bar addArrangedSubview:button];
    bar.edgeInsets = NSEdgeInsetsMake(14, 24, 14, 24);
    NSStackView *stack = VStack(0, @[]);
    NSStackView *padded = VStack(0, @[body]);
    padded.edgeInsets = NSEdgeInsetsMake(24, 24, 22, 24);
    FillWidth(body, padded);
    FillWidth(padded, stack);
    FillWidth(Hairline(), stack);
    FillWidth(bar, stack);
    NSView *root = [NSView new];
    Pin(stack, root, NSEdgeInsetsZero);
    [root.widthAnchor constraintEqualToConstant:width].active = YES;
    // Wrapping labels need a laid-out width before the fitting height is right.
    root.frame = NSMakeRect(0, 0, width, 1000);
    [root layoutSubtreeIfNeeded];
    sheet.contentView = root;
    [sheet setContentSize:root.fittingSize];
    return sheet;
}

- (NSView *)sheetHeader:(NSString *)symbol tint:(NSColor *)tint title:(NSString *)title message:(NSView *)message {
    PanelView *tile = [PanelView new];
    tile.border = nil;
    tile.fill = tint ? [tint colorWithAlphaComponent:0.14] : ToneFillColor(ToneNeutral);
    NSImageView *icon = SymbolView(symbol, 18, NSFontWeightRegular, tint ?: ThemeTextColor());
    [tile addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [tile.widthAnchor constraintEqualToConstant:40], [tile.heightAnchor constraintEqualToConstant:40],
        [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor], [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
    ]];
    NSStackView *text = VStack(4, @[Label(title, 15, NSFontWeightSemibold, ThemeTextColor())]);
    FillWidth(message, text);
    NSStackView *row = HStack(14, @[tile, text]);
    row.alignment = NSLayoutAttributeTop;
    return row;
}

- (NSButton *)cancelButton {
    NSButton *cancel = PushButton(@"Cancel", NO, self, @selector(cancelSheet:));
    cancel.keyEquivalent = @"\e";
    return cancel;
}

- (void)cancelSheet:(id)sender { [self.window endSheet:self.window.attachedSheet returnCode:NSModalResponseCancel]; }
- (void)confirmSheet:(id)sender { [self.window endSheet:self.window.attachedSheet returnCode:NSModalResponseOK]; }

- (void)exportReport:(id)sender {
    if (!self.model.report || self.window.attachedSheet) return;
    [self showWindow:nil];
    NSSwitch *tools = Switch(YES, NSControlSizeSmall, nil, nil);
    tools.enabled = NO;
    Inventory *inventory = [Inventory inventoryForModel:self.model];
    NSSwitch *workspaces = Switch(inventory.workspaces.count > 0, NSControlSizeSmall, nil, nil);
    NSSwitch *configurations = Switch(inventory.mcpServers.count + inventory.editorSettings.count + inventory.pathTools.count > 0, NSControlSizeSmall, nil, nil);
    self.exportOptions = @{@"workspaces": workspaces, @"configurations": configurations};
    NSMutableArray *rows = [NSMutableArray array];
    for (NSArray *option in @[@[@"Tools and installations", tools, @" · required"], @[@"Workspace metadata", workspaces, @""], @[@"Configuration metadata", configurations, @""]]) {
        NSSwitch *toggle = option[1];
        toggle.accessibilityLabel = option[0];
        NSStackView *label = HStack(0, @[Label(option[0], 12.5, NSFontWeightRegular, ThemeTextColor()), Label(option[2], 12.5, NSFontWeightRegular, ThemeFaintColor())]);
        NSView *cell = [NSView new];
        cell.translatesAutoresizingMaskIntoConstraints = NO;
        Pin(HStack(12, @[label, Spacer(), toggle]), cell, NSEdgeInsetsMake(9, 14, 9, 14));
        [rows addObject:cell];
    }
    NSDictionary *host = self.model.report[@"host"];
    NSArray *resources = self.model.report[@"resources"];
    NSDictionary *first = resources.firstObject;
    NSString *preview = [NSString stringWithFormat:@"{\n  \"schema_version\": %@,\n  \"host\": { \"platform\": \"%@\",\n            \"architecture\": \"%@\" },\n  \"resources\": [ { \"canonical_tool_id\": \"%@\",\n      \"version\": \"%@\" }, … %lu more ]\n}",
                         self.model.report[@"schema_version"] ?: @1, StringValue(host[@"platform"], @"macos"), StringValue(host[@"architecture"], @"—"),
                         StringValue(first[@"canonical_tool_id"], @"—"), StringValue(first[@"version"], @"—"), (unsigned long)MAX(1u, resources.count) - 1];
    PanelView *well = [PanelView new];
    well.fill = ThemeWellColor();
    well.border = nil;
    well.cornerRadius = 8;
    NSTextField *code = WrappingLabel(preview, 10.5, ThemeSubColor());
    code.font = ThemeMono(10.5);
    code.accessibilityLabel = @"Export preview";
    Pin(code, well, NSEdgeInsetsMake(10, 12, 10, 12));

    NSStackView *body = VStack(16, @[]);
    FillWidth([self sheetHeader:@"curlybraces" tint:nil title:@"Export inventory as JSON" message:WrappingLabel(@"A snapshot of what the latest scan discovered. This is a report, not a backup.", 12.5, ThemeSubColor())], body);
    FillWidth(ListPanel(rows), body);
    FillWidth(well, body);
    FillWidth(WrappingLabel(self.model.includePaths ? @"Installation paths are included. Review the file before sharing it." : @"Installation paths are left out. Package names and versions can still be personal.", 11, ThemeFaintColor()), body);
    [body setCustomSpacing:8 afterView:well];

    NSWindow *sheet = [self sheetWithBody:body buttons:@[[self cancelButton], PushButton(@"Save…", YES, self, @selector(confirmSheet:))] width:460];
    [self.window beginSheet:sheet completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) dispatch_async(dispatch_get_main_queue(), ^{ [self saveExport]; });
    }];
}

- (void)saveExport {
    BOOL workspaces = self.exportOptions[@"workspaces"].state == NSControlStateValueOn;
    BOOL configurations = self.exportOptions[@"configurations"].state == NSControlStateValueOn;
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd";
    panel.nameFieldStringValue = [NSString stringWithFormat:@"devcloud-report-%@.json", [formatter stringFromDate:self.model.lastScanDate ?: NSDate.date]];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil;
        if ([self.model exportReportToURL:panel.URL workspaces:workspaces configurations:configurations error:&error]) {
            [self toast:[NSString stringWithFormat:@"Exported %@", panel.URL.lastPathComponent] detail:@"Saved on this Mac only."];
        } else {
            [[NSAlert alertWithError:error ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]] beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }];
}

- (void)approveWorkspace:(id)sender {
    if (self.window.attachedSheet) return;
    [self showWindow:nil];
    NSView *read = [self scopeBox:@"Will read" items:WorkspaceReadScope() symbol:@"checkmark" tint:NSColor.systemGreenColor];
    NSView *never = [self scopeBox:@"Never reads" items:WorkspaceNeverRead() symbol:@"xmark" tint:ThemeFaintColor()];
    NSStackView *columns = HStack(12, @[read, never]);
    columns.alignment = NSLayoutAttributeTop;
    columns.distribution = NSStackViewDistributionFillEqually;
    NSStackView *body = VStack(20, @[]);
    FillWidth([self sheetHeader:@"folder.badge.plus" tint:NSColor.systemBlueColor title:@"Add a workspace"
                        message:WrappingLabel(@"Choose a project folder in Finder. DevCloud only reads metadata from folders you explicitly approve.", 12.5, ThemeSubColor())], body);
    FillWidth(columns, body);
    NSWindow *sheet = [self sheetWithBody:body buttons:@[[self cancelButton], PushButton(@"Choose Folder…", YES, self, @selector(confirmSheet:))] width:480];
    [self.window beginSheet:sheet completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) dispatch_async(dispatch_get_main_queue(), ^{ [self chooseWorkspaceFolders]; });
    }];
}

- (NSView *)scopeBox:(NSString *)title items:(NSArray<NSString *> *)items symbol:(NSString *)symbol tint:(NSColor *)tint {
    NSStackView *stack = VStack(7, @[Label(title, 11, NSFontWeightSemibold, ThemeTextColor())]);
    for (NSString *item in items) {
        NSImageView *icon = SymbolView(symbol, 9, NSFontWeightBold, tint);
        [icon.widthAnchor constraintEqualToConstant:12].active = YES;
        NSStackView *line = HStack(7, @[icon, WrappingLabel(item, 11.5, ThemeSubColor())]);
        line.alignment = NSLayoutAttributeFirstBaseline;
        FillWidth(line, stack);
    }
    PanelView *box = PaddedPanel(stack, 12);
    box.border = nil;
    box.cornerRadius = 8;
    return box;
}

- (void)chooseWorkspaceFolders {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.message = @"Choose Git workspaces. DevCloud reads only branch and worktree metadata.";
    panel.prompt = @"Approve Workspace";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSMutableArray *added = [NSMutableArray array];
        for (NSURL *url in panel.URLs) {
            NSString *path = url.standardizedURL.path;
            if ([self.model.approvedRoots containsObject:path]) continue;
            [self.model addApprovedRoot:path];
            [added addObject:[path stringByAbbreviatingWithTildeInPath]];
        }
        [self showPage:PageWorkspaces];
        [self toast:added.count ? @"Workspace approved" : @"Already approved" detail:added.count ? [NSString stringWithFormat:@"%@ · metadata only", [added componentsJoinedByString:@", "]] : @"Those folders were already on the list."];
    }];
}

@end
