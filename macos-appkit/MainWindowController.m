#import "MainWindowController.h"
#import "EmptyStateView.h"
#import "CardViews.h"
#import "ToolIcons.h"

static NSToolbarItemIdentifier const ScanItem = @"scan";
static NSToolbarItemIdentifier const ApproveItem = @"approve-folder";
static NSToolbarItemIdentifier const ExportItem = @"export";
static NSToolbarItemIdentifier const SearchItem = @"search";

#pragma mark - Inventory node

@interface InventoryNode : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *toolIdentifier;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *values;
@property(nonatomic, copy) NSDictionary *resource;
@property(nonatomic, copy) NSArray<InventoryNode *> *children;
@property(nonatomic, copy) NSArray<NSArray<NSString *> *> *details;
@property(nonatomic, copy) NSString *symbol;
@property(nonatomic, strong) NSColor *tint;
@end

@implementation InventoryNode
- (NSString *)valueForColumn:(NSString *)column {
    return [column isEqual:@"name"] ? self.title : (self.values[column] ?: @"");
}
- (BOOL)matches:(NSString *)query {
    if ([self.title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    for (NSString *value in self.values.allValues) {
        if ([value rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}
@end

// The disclosure triangle has no name of its own; give VoiceOver one.
@interface InventoryOutlineView : NSOutlineView
@end
@implementation InventoryOutlineView
- (NSView *)makeViewWithIdentifier:(NSUserInterfaceItemIdentifier)identifier owner:(id)owner {
    NSView *view = [super makeViewWithIdentifier:identifier owner:owner];
    if ([identifier isEqual:NSOutlineViewDisclosureButtonKey]) view.accessibilityLabel = @"Show installations";
    return view;
}
@end

@interface HeroView : NSView
@end
@implementation HeroView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) self.translatesAutoresizingMaskIntoConstraints = NO;
    return self;
}
- (void)drawRect:(NSRect)rect {
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:16 yRadius:16];
    [NSColor.controlBackgroundColor setFill];
    [shape fill];
    [NSColor.separatorColor setStroke];
    shape.lineWidth = 1;
    [shape stroke];
}
@end

@interface ResponsiveGridLayout : NSCollectionViewFlowLayout
@end
@implementation ResponsiveGridLayout
- (BOOL)shouldInvalidateLayoutForBoundsChange:(NSRect)newBounds { return YES; }
@end

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - Presentation helpers

static NSString *ProviderName(NSString *provider) {
    if (![provider isKindOfClass:NSString.class] || provider.length == 0) return @"Unknown";
    NSDictionary *names = @{
        @"homebrew_formula": @"Homebrew",
        @"homebrew_cask": @"Homebrew Cask",
        @"macos_system": @"macOS",
        @"xcode": @"Xcode",
        @"nvm": @"nvm",
        @"pyenv": @"pyenv",
        @"volta": @"Volta",
        @"fnm": @"fnm",
        @"vscode": @"VS Code",
        @"cursor": @"Cursor",
        @"application_bundle": @"Application",
        @"path": @"PATH"
    };
    return names[provider] ?: provider;
}

static NSString *KindName(NSString *kind) {
    NSDictionary *names = @{
        @"runtime": @"Runtime",
        @"tool": @"Tool",
        @"package_manager": @"Package manager",
        @"version_manager": @"Version manager",
        @"database": @"Database",
        @"application": @"Application",
        @"editor": @"Editor",
        @"editor_extension": @"Editor extension",
        @"package": @"Package"
    };
    return names[kind] ?: kind ?: @"Unknown";
}

static NSString *StringValue(id value, NSString *fallback) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : fallback;
}

static BOOL IsDeveloperTool(NSDictionary *resource) {
    NSString *kind = resource[@"kind"];
    return ![kind isEqual:@"package"] && ![kind isEqual:@"editor_extension"];
}

static NSString *PathStatusName(NSDictionary *resource) {
    NSString *status = resource[@"path_status"];
    if ([status isEqual:@"first_on_path"]) return @"First";
    if ([status isEqual:@"also_on_path"]) return @"Later";
    return @"";
}

static NSString *RelativeDate(NSDate *date) {
    if (!date) return @"never";
    NSRelativeDateTimeFormatter *formatter = [NSRelativeDateTimeFormatter new];
    formatter.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleFull;
    if (fabs(date.timeIntervalSinceNow) < 60) return @"just now";
    return [formatter localizedStringForDate:date relativeToDate:NSDate.date];
}

#pragma mark - Window controller

@interface MainWindowController () <NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout>
@property(nonatomic, strong) ScanModel *model;
@property(nonatomic, copy) NSArray<NSDictionary *> *sidebarEntries;
@property(nonatomic, strong) NSTableView *sidebarTable;
@property(nonatomic, strong) NSOutlineView *outline;
@property(nonatomic, strong) NSScrollView *outlineScroll;
@property(nonatomic, strong) NSCollectionView *grid;
@property(nonatomic, strong) NSScrollView *gridScroll;
@property(nonatomic, strong) NSView *listContainer;
@property(nonatomic, strong) NSScrollView *overviewScroll;
@property(nonatomic, strong) NSStackView *overviewStack;
@property(nonatomic, strong) EmptyStateView *emptyView;
@property(nonatomic, strong) NSView *banner;
@property(nonatomic, strong) NSLayoutConstraint *bannerHeight;
@property(nonatomic, strong) NSProgressIndicator *bannerProgress;
@property(nonatomic, strong) NSTextField *bannerLabel;
@property(nonatomic, strong) NSStackView *inspectorStack;
@property(nonatomic, strong) NSTextField *footerLabel;
@property(nonatomic, strong) NSSearchField *searchField;
@property(nonatomic, copy) NSArray<InventoryNode *> *nodes;
@property(nonatomic, copy) NSString *section;
@property(nonatomic, copy) NSString *renderedSignature;
@end

@implementation MainWindowController

+ (NSArray<NSString *> *)sectionTitles {
    return @[@"Overview", @"Changes", @"Developer Tools", @"Packages", @"Editor Extensions", @"All Installations", @"Workspaces", @"MCP Servers", @"Editor Settings", @"Other PATH Tools"];
}

- (instancetype)initWithModel:(ScanModel *)model {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1180, 760)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        _model = model;
        _section = @"Overview";
        _nodes = @[];
        window.toolbarStyle = NSWindowToolbarStyleUnified;
        window.titleVisibility = NSWindowTitleVisible;
        [self buildSidebarEntries];
        [self buildContent];
        [self installToolbar];
        [window center];
        window.frameAutosaveName = @"ContinuityMainWindow";
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(modelChanged:) name:ScanModelDidChangeNotification object:model];
        [self selectSectionAtIndex:0];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)buildSidebarEntries {
    NSArray *symbols = @[@"square.grid.2x2", @"clock.arrow.circlepath", @"hammer", @"shippingbox", @"puzzlepiece.extension", @"square.stack.3d.up", @"folder", @"point.3.connected.trianglepath.dotted", @"slider.horizontal.3", @"terminal"];
    NSArray *titles = MainWindowController.sectionTitles;
    NSMutableArray *entries = [NSMutableArray array];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
        if (index == 0) [entries addObject:@{@"header": @"Inventory"}];
        if (index == 6) [entries addObject:@{@"header": @"Local Context"}];
        [entries addObject:@{@"title": title, @"symbol": symbols[index], @"index": @(index)}];
    }];
    self.sidebarEntries = entries;
}

#pragma mark Layout

- (void)buildContent {
    NSSplitViewController *split = [NSSplitViewController new];

    NSViewController *sidebarController = [NSViewController new];
    NSScrollView *sidebarScroll = [NSScrollView new];
    sidebarScroll.drawsBackground = NO;
    sidebarScroll.hasVerticalScroller = YES;
    sidebarScroll.autohidesScrollers = YES;
    self.sidebarTable = [NSTableView new];
    self.sidebarTable.style = NSTableViewStyleSourceList;
    self.sidebarTable.headerView = nil;
    self.sidebarTable.dataSource = self;
    self.sidebarTable.delegate = self;
    self.sidebarTable.rowHeight = 28;
    self.sidebarTable.floatsGroupRows = NO;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"sidebar"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [self.sidebarTable addTableColumn:column];
    self.sidebarTable.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    sidebarScroll.documentView = self.sidebarTable;
    sidebarController.view = sidebarScroll;
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarController];
    sidebarItem.minimumThickness = 200;
    sidebarItem.maximumThickness = 280;
    sidebarItem.canCollapse = YES;
    [split addSplitViewItem:sidebarItem];

    NSViewController *detailController = [NSViewController new];
    NSView *detail = [NSView new];
    detailController.view = detail;
    [self buildDetail:detail];
    NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:detailController];
    detailItem.minimumThickness = 620;
    [split addSplitViewItem:detailItem];
    split.splitView.autosaveName = @"ContinuitySidebar";

    [NSLayoutConstraint activateConstraints:@[
        [detail.widthAnchor constraintGreaterThanOrEqualToConstant:620],
        [detail.heightAnchor constraintGreaterThanOrEqualToConstant:480],
    ]];
    self.window.contentViewController = split;
    [self.window setContentSize:NSMakeSize(1180, 760)];
    self.window.minSize = NSMakeSize(900, 560);
}

- (void)buildDetail:(NSView *)detail {
    self.banner = [self buildBanner];
    [detail addSubview:self.banner];

    self.overviewScroll = [NSScrollView new];
    self.overviewScroll.hasVerticalScroller = YES;
    self.overviewScroll.autohidesScrollers = YES;
    self.overviewScroll.drawsBackground = NO;
    self.overviewScroll.translatesAutoresizingMaskIntoConstraints = NO;
    FlippedView *document = [FlippedView new];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    self.overviewStack = [self verticalStack:22];
    [document addSubview:self.overviewStack];
    self.overviewScroll.documentView = document;
    [detail addSubview:self.overviewScroll];

    self.listContainer = [self buildList];
    [detail addSubview:self.listContainer];

    self.emptyView = [self buildEmptyView];
    [detail addSubview:self.emptyView];

    self.footerLabel = [self label:@"" size:11 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [detail addSubview:self.footerLabel];

    NSLayoutGuide *safe = detail.safeAreaLayoutGuide;
    self.bannerHeight = [self.banner.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.banner.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.banner.leadingAnchor constraintEqualToAnchor:detail.leadingAnchor],
        [self.banner.trailingAnchor constraintEqualToAnchor:detail.trailingAnchor],
        self.bannerHeight,
        [self.footerLabel.leadingAnchor constraintEqualToAnchor:detail.leadingAnchor constant:16],
        [self.footerLabel.trailingAnchor constraintLessThanOrEqualToAnchor:detail.trailingAnchor constant:-16],
        [self.footerLabel.bottomAnchor constraintEqualToAnchor:detail.bottomAnchor constant:-8],
        [document.leadingAnchor constraintEqualToAnchor:self.overviewScroll.contentView.leadingAnchor],
        [document.trailingAnchor constraintEqualToAnchor:self.overviewScroll.contentView.trailingAnchor],
        [document.topAnchor constraintEqualToAnchor:self.overviewScroll.contentView.topAnchor],
        [self.overviewStack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:28],
        [self.overviewStack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-28],
        [self.overviewStack.topAnchor constraintEqualToAnchor:document.topAnchor constant:20],
        [self.overviewStack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-24],
    ]];
    for (NSView *view in @[self.overviewScroll, self.listContainer, self.emptyView]) {
        [NSLayoutConstraint activateConstraints:@[
            [view.topAnchor constraintEqualToAnchor:self.banner.bottomAnchor],
            [view.leadingAnchor constraintEqualToAnchor:detail.leadingAnchor],
            [view.trailingAnchor constraintEqualToAnchor:detail.trailingAnchor],
            [view.bottomAnchor constraintEqualToAnchor:self.footerLabel.topAnchor constant:-6],
        ]];
    }
}

- (NSView *)buildBanner {
    NSView *banner = [NSView new];
    banner.translatesAutoresizingMaskIntoConstraints = NO;
    banner.wantsLayer = YES;
    banner.clipsToBounds = YES;
    self.bannerProgress = [NSProgressIndicator new];
    self.bannerProgress.style = NSProgressIndicatorStyleBar;
    self.bannerProgress.controlSize = NSControlSizeSmall;
    self.bannerProgress.minValue = 0;
    self.bannerProgress.maxValue = 1;
    self.bannerProgress.translatesAutoresizingMaskIntoConstraints = NO;
    self.bannerLabel = [self label:@"" size:12 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    [banner addSubview:self.bannerProgress];
    [banner addSubview:self.bannerLabel];
    NSBox *separator = [NSBox new];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [banner addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
        [self.bannerLabel.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor constant:16],
        [self.bannerLabel.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
        [self.bannerProgress.leadingAnchor constraintEqualToAnchor:self.bannerLabel.trailingAnchor constant:12],
        [self.bannerProgress.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor constant:-16],
        [self.bannerProgress.centerYAnchor constraintEqualToAnchor:banner.centerYAnchor],
        [self.bannerProgress.widthAnchor constraintGreaterThanOrEqualToConstant:120],
        [separator.leadingAnchor constraintEqualToAnchor:banner.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:banner.trailingAnchor],
        [separator.bottomAnchor constraintEqualToAnchor:banner.bottomAnchor],
    ]];
    [self.bannerLabel setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return banner;
}

- (NSView *)buildList {
    NSView *container = [NSView new];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    self.outline = [InventoryOutlineView new];
    self.outline.dataSource = self;
    self.outline.delegate = self;
    self.outline.style = NSTableViewStyleInset;
    self.outline.usesAlternatingRowBackgroundColors = YES;
    self.outline.allowsColumnReordering = NO;
    self.outline.rowHeight = 24;
    self.outline.autosaveExpandedItems = NO;
    self.outline.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    self.outline.target = self;
    self.outline.doubleAction = @selector(toggleExpansion:);
    NSMenu *menu = [NSMenu new];
    menu.delegate = self;
    self.outline.menu = menu;

    self.outlineScroll = [NSScrollView new];
    self.outlineScroll.hasVerticalScroller = YES;
    self.outlineScroll.autohidesScrollers = YES;
    self.outlineScroll.drawsBackground = NO;
    self.outlineScroll.documentView = self.outline;
    self.outlineScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.outlineScroll];

    NSCollectionViewFlowLayout *layout = [ResponsiveGridLayout new];
    layout.itemSize = NSMakeSize(228, 150);
    layout.minimumInteritemSpacing = 14;
    layout.minimumLineSpacing = 14;
    layout.sectionInset = NSEdgeInsetsMake(18, 18, 18, 18);
    self.grid = [NSCollectionView new];
    self.grid.collectionViewLayout = layout;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.selectable = YES;
    self.grid.backgroundColors = @[NSColor.clearColor];
    [self.grid registerClass:ToolCardItem.class forItemWithIdentifier:@"tool"];
    self.grid.menu = menu;
    self.gridScroll = [NSScrollView new];
    self.gridScroll.hasVerticalScroller = YES;
    self.gridScroll.autohidesScrollers = YES;
    self.gridScroll.drawsBackground = NO;
    self.gridScroll.documentView = self.grid;
    self.gridScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:self.gridScroll];

    NSBox *divider = [NSBox new];
    divider.boxType = NSBoxSeparator;
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:divider];

    NSScrollView *inspectorScroll = [NSScrollView new];
    inspectorScroll.hasVerticalScroller = YES;
    inspectorScroll.autohidesScrollers = YES;
    inspectorScroll.drawsBackground = NO;
    inspectorScroll.translatesAutoresizingMaskIntoConstraints = NO;
    FlippedView *inspectorDocument = [FlippedView new];
    inspectorDocument.translatesAutoresizingMaskIntoConstraints = NO;
    self.inspectorStack = [self verticalStack:12];
    [inspectorDocument addSubview:self.inspectorStack];
    inspectorScroll.documentView = inspectorDocument;
    [container addSubview:inspectorScroll];

    [NSLayoutConstraint activateConstraints:@[
        [self.outlineScroll.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.outlineScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.outlineScroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [divider.leadingAnchor constraintEqualToAnchor:self.outlineScroll.trailingAnchor],
        [self.gridScroll.topAnchor constraintEqualToAnchor:container.topAnchor],
        [self.gridScroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [self.gridScroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [self.gridScroll.trailingAnchor constraintEqualToAnchor:divider.leadingAnchor],
        [divider.topAnchor constraintEqualToAnchor:container.topAnchor],
        [divider.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [divider.widthAnchor constraintEqualToConstant:1],
        [inspectorScroll.leadingAnchor constraintEqualToAnchor:divider.trailingAnchor],
        [inspectorScroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [inspectorScroll.topAnchor constraintEqualToAnchor:container.topAnchor],
        [inspectorScroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [inspectorScroll.widthAnchor constraintEqualToConstant:270],
        [inspectorDocument.leadingAnchor constraintEqualToAnchor:inspectorScroll.contentView.leadingAnchor],
        [inspectorDocument.trailingAnchor constraintEqualToAnchor:inspectorScroll.contentView.trailingAnchor],
        [inspectorDocument.topAnchor constraintEqualToAnchor:inspectorScroll.contentView.topAnchor],
        [self.inspectorStack.leadingAnchor constraintEqualToAnchor:inspectorDocument.leadingAnchor constant:18],
        [self.inspectorStack.trailingAnchor constraintEqualToAnchor:inspectorDocument.trailingAnchor constant:-18],
        [self.inspectorStack.topAnchor constraintEqualToAnchor:inspectorDocument.topAnchor constant:16],
        [self.inspectorStack.bottomAnchor constraintEqualToAnchor:inspectorDocument.bottomAnchor constant:-16],
    ]];
    return container;
}

- (EmptyStateView *)buildEmptyView {
    EmptyStateView *view = [EmptyStateView new];
    __weak MainWindowController *weakSelf = self;
    view.onAction = ^{ [weakSelf emptyActionClicked:nil]; };
    return view;
}

#pragma mark Toolbar

- (void)installToolbar {
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"ContinuityToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.allowsUserCustomization = NO;
    self.window.toolbar = toolbar;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[NSToolbarToggleSidebarItemIdentifier, NSToolbarSidebarTrackingSeparatorItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, ApproveItem, ExportItem, ScanItem, SearchItem];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    if ([identifier isEqual:SearchItem]) {
        NSSearchToolbarItem *item = [[NSSearchToolbarItem alloc] initWithItemIdentifier:identifier];
        item.searchField.placeholderString = @"Filter";
        item.searchField.delegate = self;
        item.preferredWidthForSearchField = 220;
        self.searchField = item.searchField;
        return item;
    }
    NSArray *spec = @{
        ScanItem: @[@"Scan Now", @"arrow.clockwise", NSStringFromSelector(@selector(scanNow:)), @"Scan this Mac (⌘R)"],
        ApproveItem: @[@"Add Workspace", @"folder.badge.plus", NSStringFromSelector(@selector(approveWorkspace:)), @"Approve a Git workspace folder"],
        ExportItem: @[@"Export", @"square.and.arrow.up", NSStringFromSelector(@selector(exportReport:)), @"Export the report as JSON (⌘E)"],
    }[identifier];
    if (!spec) return nil;
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = spec[0];
    item.paletteLabel = spec[0];
    item.toolTip = spec[3];
    item.image = [NSImage imageWithSystemSymbolName:spec[1] accessibilityDescription:spec[0]];
    item.target = self;
    item.action = NSSelectorFromString(spec[2]);
    item.bordered = YES;
    return item;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    if ([item.itemIdentifier isEqual:ScanItem]) return !self.model.scanning;
    if ([item.itemIdentifier isEqual:ExportItem]) return self.model.report != nil;
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(exportReport:)) return self.model.report != nil;
    if (item.action == @selector(scanNow:)) return !self.model.scanning;
    return YES;
}

#pragma mark Actions

- (void)scanNow:(id)sender { [self.model scan]; }

- (void)focusSearch {
    [self showWindow:nil];
    if (self.searchField) [self.window makeFirstResponder:self.searchField];
}

- (void)approveWorkspace:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.message = @"Choose Git workspaces. Continuity reads only branch and worktree metadata.";
    panel.prompt = @"Add Workspace";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        for (NSURL *url in panel.URLs) [self.model addApprovedRoot:url.standardizedURL.path];
        [self selectSectionAtIndex:6];
    }];
}

- (void)exportReport:(id)sender {
    if (!self.model.report) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd";
    panel.nameFieldStringValue = [NSString stringWithFormat:@"continuity-report-%@.json", [formatter stringFromDate:self.model.lastScanDate ?: NSDate.date]];
    panel.message = @"Review before sharing: package names and versions can reveal personal information.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil;
        if (![self.model exportReportToURL:panel.URL error:&error]) {
            [[NSAlert alertWithError:error ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]] beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }];
}

- (void)emptyActionClicked:(NSButton *)sender {
    // Mirrors the precedence in showEmpty: so the button does what it says.
    NSString *section = self.section;
    if (!self.model.report) [self.model scan];
    else if (self.searchField.stringValue.length) { self.searchField.stringValue = @""; [self refresh]; }
    else if ([section isEqual:@"MCP Servers"]) self.model.inspectMCP = YES;
    else if ([section isEqual:@"Editor Settings"]) self.model.inspectEditorSettings = YES;
    else if ([section isEqual:@"Other PATH Tools"]) self.model.inspectPathTools = YES;
    else if ([section isEqual:@"Workspaces"]) [self approveWorkspace:sender];
    else if ([section isEqual:@"Changes"]) [self.model setMonitoringEnabled:YES];
    else [self.model scan];
}

- (void)toggleExpansion:(id)sender {
    id item = [self.outline itemAtRow:self.outline.clickedRow];
    if (![self.outline isExpandable:item]) return;
    if ([self.outline isItemExpanded:item]) [self.outline collapseItem:item];
    else [self.outline expandItem:item];
}

#pragma mark Section selection

- (void)selectSectionAtIndex:(NSUInteger)index {
    NSArray *titles = MainWindowController.sectionTitles;
    if (index >= titles.count) return;
    [self.sidebarEntries enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger row, BOOL *stop) {
        if ([entry[@"index"] unsignedIntegerValue] == index && entry[@"title"]) {
            [self.sidebarTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            *stop = YES;
        }
    }];
    [self showSection:titles[index]];
}

- (void)showSection:(NSString *)section {
    if (![self.section isEqual:section]) {
        self.section = section;
        self.searchField.stringValue = @"";
        self.renderedSignature = nil;
    }
    [self configureColumns];
    [self refresh];
}

- (void)modelChanged:(NSNotification *)notification {
    [self refresh];
}

#pragma mark Refresh

- (void)refresh {
    BOOL scanning = self.model.scanning;
    self.bannerHeight.constant = scanning ? 34 : 0;
    self.bannerLabel.stringValue = self.model.phase ?: @"";
    if (scanning && self.model.progress > 0 && self.model.progress < 1) {
        self.bannerProgress.indeterminate = NO;
        self.bannerProgress.doubleValue = self.model.progress;
    } else {
        self.bannerProgress.indeterminate = YES;
    }
    if (scanning) [self.bannerProgress startAnimation:nil]; else [self.bannerProgress stopAnimation:nil];
    [self.sidebarTable reloadData];
    [self.window.toolbar validateVisibleItems];
    [self updateFooter];

    // Rebuilding on every progress tick would reset scrolling and selection.
    NSString *signature = [NSString stringWithFormat:@"%@|%p|%p|%p|%d|%d|%d|%d|%lu|%@|%@|%d", self.section, self.model.report, self.model.localMetadata, self.model.changes, self.model.inspectMCP, self.model.inspectEditorSettings, self.model.inspectPathTools, scanning && !self.model.report, (unsigned long)self.model.approvedRoots.count, self.searchField.stringValue, self.model.report ? @"" : (self.model.phase ?: @""), self.model.monitoring];
    if ([signature isEqual:self.renderedSignature]) return;
    self.renderedSignature = signature;
    [self reloadSection];
}

- (void)reloadSection {
    self.window.title = self.section;
    BOOL waiting = !self.model.report;
    if ([self.section isEqual:@"Overview"]) {
        self.listContainer.hidden = YES;
        if (waiting) {
            [self showEmpty:YES];
        } else {
            [self showEmpty:NO];
            self.overviewScroll.hidden = NO;
            [self rebuildOverview];
        }
        self.window.subtitle = [self hostSummary];
        return;
    }
    self.overviewScroll.hidden = YES;
    NSIndexSet *previousSelection = self.outline.selectedRowIndexes;
    self.nodes = waiting ? @[] : [self filteredNodes:[self nodesForSection]];
    [self sortNodes];
    BOOL gridMode = [self isGridSection];
    self.gridScroll.hidden = !gridMode;
    self.outlineScroll.hidden = gridMode;
    [self.grid reloadData];
    [self.outline reloadData];
    if (self.searchField.stringValue.length) [self.outline expandItem:nil expandChildren:YES];
    if (previousSelection.count && previousSelection.firstIndex < (NSUInteger)self.outline.numberOfRows) {
        [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:previousSelection.firstIndex] byExtendingSelection:NO];
    }
    NSUInteger total = 0;
    for (InventoryNode *node in self.nodes) total += node.children.count ?: 1;
    BOOL empty = self.nodes.count == 0;
    NSString *subtitle = [NSString stringWithFormat:@"%lu %@", (unsigned long)total, total == 1 ? @"item" : @"items"];
    NSNumber *since = self.model.changes[@"previous_observed_at_unix_seconds"];
    if ([self.section isEqual:@"Changes"] && [since isKindOfClass:NSNumber.class]) {
        NSString *date = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:since.doubleValue] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
        subtitle = [NSString stringWithFormat:@"%@ · compared with scan from %@", subtitle, date];
    }
    if ([self.section isEqual:@"Developer Tools"]) subtitle = [NSString stringWithFormat:@"%lu tools · %lu installations", (unsigned long)self.nodes.count, (unsigned long)total];
    self.window.subtitle = waiting || empty ? @"" : subtitle;
    self.listContainer.hidden = empty;
    [self showEmpty:empty];
    [self updateInspector];
}

- (void)showEmpty:(BOOL)show {
    self.emptyView.hidden = !show;
    if (!show) return;
    NSString *section = self.section;
    NSString *query = self.searchField.stringValue;
    NSString *symbol = @"tray";
    NSColor *tint = NSColor.systemGrayColor;
    NSString *title = @"Nothing here yet";
    NSString *message = @"";
    NSString *action = nil;
    NSString *hint = nil;
    BOOL busy = NO;
    if (!self.model.report && self.model.scanning) {
        symbol = nil;
        tint = NSColor.systemBlueColor;
        title = @"Taking inventory of this Mac";
        message = [NSString stringWithFormat:@"%@. Continuity reads folder and file names only and never runs what it finds.", self.model.phase ?: @"Scanning"];
        busy = YES;
    } else if (!self.model.report) {
        symbol = self.model.errorMessage ? @"exclamationmark.triangle.fill" : nil;
        tint = self.model.errorMessage ? NSColor.systemOrangeColor : NSColor.systemBlueColor;
        title = self.model.errorMessage ? @"The scan didn’t finish" : @"Welcome to Continuity";
        message = self.model.errorMessage ?: @"See every runtime, package manager, and editor extension on this Mac, and what changed since last time. Everything stays on this Mac.";
        action = self.model.errorMessage ? @"Try Again" : @"Scan This Mac";
        hint = @"or press ⌘R";
    } else if (query.length) {
        symbol = @"magnifyingglass";
        tint = NSColor.systemGrayColor;
        title = @"No matches";
        message = [NSString stringWithFormat:@"Nothing in %@ matches “%@”. Try a tool name, version, or installer such as Homebrew.", section, query];
        action = @"Clear Filter";
        hint = @"or press Esc in the filter field";
    } else if ([section isEqual:@"Changes"]) {
        symbol = @"checkmark.seal.fill";
        tint = NSColor.systemGreenColor;
        title = @"Your setup is steady";
        message = [NSString stringWithFormat:@"Nothing has been added, removed, or updated since Continuity started tracking. Last scan %@.", RelativeDate(self.model.lastScanDate)];
        if (!self.model.monitoring) {
            message = [message stringByAppendingString:@" Turn on monitoring to catch changes as they happen."];
            action = @"Turn On Monitoring";
        }
    } else if ([section isEqual:@"Workspaces"]) {
        symbol = @"folder.fill.badge.plus";
        tint = NSColor.systemOrangeColor;
        BOOL hasRoots = self.model.approvedRoots.count > 0;
        title = hasRoots ? @"No Git repositories found" : @"Add your first workspace";
        message = hasRoots
            ? @"The folders you added don’t contain a Git repository at the top level. Add a project folder directly."
            : @"Choose project folders to track their current branch and worktrees. Continuity never reads source files or remote URLs.";
        action = @"Add Workspace…";
        hint = @"or press ⇧⌘O";
    } else if ([section isEqual:@"MCP Servers"]) {
        symbol = @"point.3.connected.trianglepath.dotted";
        tint = NSColor.systemPurpleColor;
        if (self.model.inspectMCP) {
            title = @"No MCP servers configured";
            message = @"Claude Desktop and Cursor configurations were checked; neither lists a server.";
        } else {
            title = @"See your MCP servers";
            message = @"Lists servers configured in Claude Desktop and Cursor. Only names, transport, and executable names are kept; arguments, URLs, and secrets are discarded.";
            action = @"Turn On MCP Inspection";
        }
    } else if ([section isEqual:@"Editor Settings"]) {
        symbol = @"slider.horizontal.3";
        tint = NSColor.systemPinkColor;
        if (self.model.inspectEditorSettings) {
            title = @"No tracked preferences found";
            message = @"VS Code and Cursor use their defaults for every preference Continuity tracks.";
        } else {
            title = @"Keep your editor preferences in view";
            message = @"Reads a short allowlist of VS Code and Cursor settings, such as tab size and theme. Paths and unknown keys are ignored.";
            action = @"Turn On Editor Settings";
        }
    } else if ([section isEqual:@"Other PATH Tools"]) {
        symbol = @"terminal.fill";
        tint = NSColor.systemTealColor;
        if (self.model.inspectPathTools) {
            title = @"No other executables";
            message = @"Every command on your PATH is already a recognized developer tool.";
        } else {
            title = @"Find the tools Continuity doesn’t know";
            message = @"Lists names of other executables on your PATH. Files are never run and full paths are left out.";
            action = @"Turn On PATH Tools";
        }
    } else if ([section isEqual:@"Packages"]) {
        symbol = @"shippingbox.fill";
        tint = NSColor.systemOrangeColor;
        title = @"No packages found";
        message = @"Homebrew formulae and casks appear here once they’re installed.";
    } else if ([section isEqual:@"Editor Extensions"]) {
        symbol = @"puzzlepiece.extension.fill";
        tint = NSColor.systemPurpleColor;
        title = @"No editor extensions";
        message = @"Extensions installed in VS Code or Cursor appear here.";
    } else {
        symbol = @"hammer.fill";
        tint = NSColor.systemBlueColor;
        title = @"No developer tools found";
        message = @"Runtimes, package managers, and command-line tools appear here after a scan.";
        action = @"Scan Now";
    }
    [self.emptyView showSymbol:symbol tint:tint title:title message:message action:action hint:hint busy:busy];
}

- (NSString *)hostSummary {
    NSDictionary *host = self.model.report[@"host"];
    if (!host) return @"";
    return [NSString stringWithFormat:@"macOS %@ · %@", StringValue(host[@"os_version"], @"—"), StringValue(host[@"architecture"], @"—")];
}

- (void)updateFooter {
    NSMutableArray *parts = [NSMutableArray array];
    if (self.model.errorMessage) {
        self.footerLabel.textColor = NSColor.systemRedColor;
        self.footerLabel.stringValue = self.model.errorMessage;
        return;
    }
    self.footerLabel.textColor = NSColor.secondaryLabelColor;
    if (self.model.report) {
        [parts addObject:[NSString stringWithFormat:@"%lu items", (unsigned long)[self.model.report[@"resources"] count]]];
        [parts addObject:[NSString stringWithFormat:@"%@ %@", self.model.showingSavedScan ? @"Saved scan from" : @"Scanned", RelativeDate(self.model.lastScanDate)]];
    }
    [parts addObject:self.model.monitoring ? @"Monitoring on" : @"Monitoring off"];
    [parts addObject:@"Stays on this Mac"];
    self.footerLabel.stringValue = [parts componentsJoinedByString:@"  ·  "];
}

#pragma mark Building nodes

- (NSArray<NSDictionary *> *)resources {
    NSArray *resources = self.model.report[@"resources"];
    return [resources isKindOfClass:NSArray.class] ? resources : @[];
}

- (NSArray<InventoryNode *> *)nodesForSection {
    NSString *section = self.section;
    NSArray *resources = [self resources];
    if ([section isEqual:@"Developer Tools"]) {
        return [self groupedNodes:[resources filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *r, id b) { return IsDeveloperTool(r); }]]];
    }
    if ([section isEqual:@"Packages"]) {
        return [self resourceNodes:[resources filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind == 'package'"]]];
    }
    if ([section isEqual:@"Editor Extensions"]) {
        return [self resourceNodes:[resources filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind == 'editor_extension'"]]];
    }
    if ([section isEqual:@"All Installations"]) return [self resourceNodes:resources];
    if ([section isEqual:@"Changes"]) return [self changeNodes];
    return [self localNodes];
}

- (InventoryNode *)nodeForResource:(NSDictionary *)resource {
    InventoryNode *node = [InventoryNode new];
    node.title = StringValue(resource[@"display_name"], @"Unknown");
    node.toolIdentifier = StringValue(resource[@"canonical_tool_id"], @"");
    node.resource = resource;
    node.values = @{
        @"version": StringValue(resource[@"version"], @"—"),
        @"kind": KindName(resource[@"kind"]),
        @"source": ProviderName(resource[@"installation_provider"]),
        @"package": StringValue(resource[@"provider_package_id"], @""),
        @"path": PathStatusName(resource),
    };
    NSMutableArray *details = [NSMutableArray array];
    [details addObject:@[@"Version", StringValue(resource[@"version"], @"Unknown")]];
    [details addObject:@[@"Type", KindName(resource[@"kind"])]];
    [details addObject:@[@"Installed by", ProviderName(resource[@"installation_provider"])]];
    if (StringValue(resource[@"provider_package_id"], nil)) [details addObject:@[@"Package", resource[@"provider_package_id"]]];
    if (PathStatusName(resource).length) [details addObject:@[@"On scan PATH", [PathStatusName(resource) isEqual:@"First"] ? @"First match in Continuity’s PATH; your shell may use a different PATH." : @"A later match in Continuity’s PATH."]];
    if (StringValue(resource[@"installation_path"], nil)) [details addObject:@[@"Location", resource[@"installation_path"]]];
    NSArray *evidence = resource[@"evidence"];
    if ([evidence isKindOfClass:NSArray.class] && evidence.count) [details addObject:@[@"Evidence", [evidence componentsJoinedByString:@"\n"]]];
    [details addObject:@[@"Identifier", [NSString stringWithFormat:@"%@\n%@", StringValue(resource[@"canonical_tool_id"], @""), StringValue(resource[@"installation_instance_id"], @"")]]];
    node.details = details;
    return node;
}

- (NSArray<InventoryNode *> *)resourceNodes:(NSArray<NSDictionary *> *)resources {
    NSMutableArray *nodes = [NSMutableArray array];
    for (NSDictionary *resource in resources) [nodes addObject:[self nodeForResource:resource]];
    return nodes;
}

// One row per tool, with each installation underneath when there are several.
- (NSArray<InventoryNode *> *)groupedNodes:(NSArray<NSDictionary *> *)resources {
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
    NSMutableArray *order = [NSMutableArray array];
    for (NSDictionary *resource in resources) {
        NSString *key = StringValue(resource[@"canonical_tool_id"], @"unknown");
        if (!groups[key]) { groups[key] = [NSMutableArray array]; [order addObject:key]; }
        [groups[key] addObject:resource];
    }
    NSMutableArray *nodes = [NSMutableArray array];
    for (NSString *key in order) {
        NSArray *members = groups[key];
        if (members.count == 1) { [nodes addObject:[self nodeForResource:members.firstObject]]; continue; }
        NSDictionary *active = nil;
        for (NSDictionary *resource in members) if ([resource[@"path_status"] isEqual:@"first_on_path"]) active = resource;
        NSDictionary *representative = active ?: members.firstObject;
        InventoryNode *node = [InventoryNode new];
        node.title = StringValue(representative[@"display_name"], key);
        node.toolIdentifier = key;
        NSMutableArray *children = [NSMutableArray array];
        for (NSDictionary *resource in members) {
            InventoryNode *child = [self nodeForResource:resource];
            child.title = StringValue(resource[@"provider_package_id"], ProviderName(resource[@"installation_provider"]));
            [children addObject:child];
        }
        node.children = children;
        NSMutableOrderedSet *sources = [NSMutableOrderedSet orderedSet];
        for (NSDictionary *resource in members) [sources addObject:ProviderName(resource[@"installation_provider"])];
        node.values = @{
            @"version": active ? StringValue(active[@"version"], @"—") : [NSString stringWithFormat:@"%lu installs", (unsigned long)members.count],
            @"kind": KindName(representative[@"kind"]),
            @"source": [sources.array componentsJoinedByString:@", "],
            @"path": active ? @"First" : @"",
        };
        NSMutableArray *details = [NSMutableArray array];
        [details addObject:@[@"Installations", [NSString stringWithFormat:@"%lu", (unsigned long)members.count]]];
        if (active) [details addObject:@[@"First on scan PATH", [NSString stringWithFormat:@"%@ from %@", StringValue(active[@"version"], @"Unknown version"), ProviderName(active[@"installation_provider"])]]];
        NSMutableArray *lines = [NSMutableArray array];
        for (NSDictionary *resource in members) [lines addObject:[NSString stringWithFormat:@"%@ · %@", StringValue(resource[@"version"], @"unknown"), ProviderName(resource[@"installation_provider"])]];
        [details addObject:@[@"Versions", [lines componentsJoinedByString:@"\n"]]];
        node.details = details;
        [nodes addObject:node];
    }
    return nodes;
}

- (NSArray<InventoryNode *> *)changeNodes {
    NSDictionary *changes = self.model.changes;
    if (!changes) return @[];
    NSMutableArray *nodes = [NSMutableArray array];
    NSDictionary *styles = @{
        @"added": @[@"Added", @"plus.circle.fill", NSColor.systemGreenColor],
        @"updated": @[@"Updated", @"arrow.up.circle.fill", NSColor.systemBlueColor],
        @"removed": @[@"Removed", @"minus.circle.fill", NSColor.systemRedColor],
    };
    for (NSString *key in @[@"added", @"updated", @"removed"]) {
        for (NSDictionary *change in changes[key] ?: @[]) {
            NSArray *style = styles[key];
            InventoryNode *node = [InventoryNode new];
            node.title = StringValue(change[@"display_name"], @"Unknown");
            node.toolIdentifier = StringValue(change[@"canonical_tool_id"], @"");
            node.symbol = style[1];
            node.tint = style[2];
            NSString *version = StringValue(change[@"version"], @"—");
            NSString *previous = StringValue(change[@"previous_version"], nil);
            node.values = @{
                @"change": style[0],
                @"version": previous ? [NSString stringWithFormat:@"%@ → %@", previous, version] : version,
                @"kind": KindName(change[@"kind"]),
                @"source": ProviderName(change[@"installation_provider"]),
            };
            node.details = @[@[@"Change", style[0]], @[@"Version", node.values[@"version"]], @[@"Type", node.values[@"kind"]], @[@"Installed by", node.values[@"source"]]];
            [nodes addObject:node];
        }
    }
    return nodes;
}

- (NSArray<InventoryNode *> *)localNodes {
    NSDictionary *local = self.model.localMetadata ?: @{};
    NSMutableArray *nodes = [NSMutableArray array];
    NSString *section = self.section;
    if ([section isEqual:@"Workspaces"]) {
        for (NSDictionary *workspace in local[@"workspaces"] ?: @[]) {
            InventoryNode *node = [InventoryNode new];
            node.title = StringValue(workspace[@"name"], @"Git repository");
            NSString *worktrees = [NSString stringWithFormat:@"%lu", [workspace[@"linked_worktree_count"] unsignedLongValue]];
            node.values = @{@"branch": StringValue(workspace[@"branch"], @"Detached or unavailable"), @"worktrees": worktrees};
            NSMutableArray *details = [@[@[@"Branch", node.values[@"branch"]], @[@"Linked worktrees", worktrees]] mutableCopy];
            if (StringValue(workspace[@"path"], nil)) [details addObject:@[@"Location", workspace[@"path"]]];
            node.details = details;
            [nodes addObject:node];
        }
    } else if ([section isEqual:@"MCP Servers"]) {
        for (NSDictionary *server in local[@"mcp_servers"] ?: @[]) {
            InventoryNode *node = [InventoryNode new];
            node.title = StringValue(server[@"name"], @"Server");
            node.values = @{@"transport": StringValue(server[@"transport"], @"—"), @"source": StringValue(server[@"config_source"], @"—"), @"executable": StringValue(server[@"executable"], @"—")};
            node.details = @[@[@"Transport", node.values[@"transport"]], @[@"Configured in", node.values[@"source"]], @[@"Executable", node.values[@"executable"]]];
            [nodes addObject:node];
        }
    } else if ([section isEqual:@"Editor Settings"]) {
        for (NSDictionary *setting in local[@"editor_settings"] ?: @[]) {
            InventoryNode *node = [InventoryNode new];
            node.title = StringValue(setting[@"key"], @"Setting");
            node.values = @{@"application": StringValue(setting[@"application"], @"—"), @"value": StringValue(setting[@"value"], @"—")};
            node.details = @[@[@"Editor", node.values[@"application"]], @[@"Value", node.values[@"value"]]];
            [nodes addObject:node];
        }
    } else if ([section isEqual:@"Other PATH Tools"]) {
        for (NSDictionary *tool in local[@"unknown_path_tools"] ?: @[]) {
            InventoryNode *node = [InventoryNode new];
            node.title = StringValue(tool[@"name"], @"Executable");
            NSString *position = [NSString stringWithFormat:@"%@", tool[@"path_position"] ?: @"—"];
            node.values = @{@"position": position};
            node.details = @[@[@"PATH entry", position]];
            [nodes addObject:node];
        }
    }
    return nodes;
}

- (NSArray<InventoryNode *> *)filteredNodes:(NSArray<InventoryNode *> *)nodes {
    NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!query.length) return nodes;
    NSMutableArray *filtered = [NSMutableArray array];
    for (InventoryNode *node in nodes) {
        if ([node matches:query]) { [filtered addObject:node]; continue; }
        NSArray *children = [node.children filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(InventoryNode *child, id b) { return [child matches:query]; }]];
        if (children.count) {
            InventoryNode *copy = [InventoryNode new];
            copy.title = node.title; copy.values = node.values; copy.details = node.details; copy.children = children;
            [filtered addObject:copy];
        }
    }
    return filtered;
}

- (void)sortNodes {
    NSSortDescriptor *descriptor = self.outline.sortDescriptors.firstObject;
    NSString *key = descriptor.key ?: @"name";
    BOOL ascending = descriptor ? descriptor.ascending : YES;
    NSComparator compare = ^NSComparisonResult(InventoryNode *a, InventoryNode *b) {
        NSComparisonResult result = [[a valueForColumn:key] localizedStandardCompare:[b valueForColumn:key]];
        if (result == NSOrderedSame) result = [a.title localizedStandardCompare:b.title];
        return ascending ? result : -result;
    };
    if ([self.section isEqual:@"Changes"] && !descriptor) return;
    NSMutableArray *sorted = [NSMutableArray array];
    for (InventoryNode *node in [self.nodes sortedArrayUsingComparator:compare]) {
        if (node.children.count) node.children = [node.children sortedArrayUsingComparator:compare];
        [sorted addObject:node];
    }
    self.nodes = sorted;
}

#pragma mark Columns

- (NSArray<NSArray *> *)columnSpecs {
    NSString *section = self.section;
    if ([section isEqual:@"Changes"]) return @[@[@"change", @"Change", @90], @[@"name", @"Name", @240], @[@"version", @"Version", @180], @[@"kind", @"Type", @120], @[@"source", @"Installed by", @130]];
    if ([section isEqual:@"Developer Tools"]) return @[@[@"name", @"Name", @200], @[@"version", @"Version", @110], @[@"kind", @"Type", @120], @[@"source", @"Installed by", @150], @[@"path", @"PATH", @70]];
    if ([section isEqual:@"Packages"]) return @[@[@"name", @"Name", @260], @[@"version", @"Version", @140], @[@"source", @"Installed by", @150]];
    if ([section isEqual:@"Editor Extensions"]) return @[@[@"name", @"Extension", @300], @[@"version", @"Version", @120], @[@"source", @"Editor", @120]];
    if ([section isEqual:@"All Installations"]) return @[@[@"name", @"Name", @200], @[@"version", @"Version", @110], @[@"kind", @"Type", @120], @[@"source", @"Installed by", @140], @[@"path", @"PATH", @70]];
    if ([section isEqual:@"Workspaces"]) return @[@[@"name", @"Repository", @260], @[@"branch", @"Branch", @220], @[@"worktrees", @"Worktrees", @90]];
    if ([section isEqual:@"MCP Servers"]) return @[@[@"name", @"Server", @200], @[@"transport", @"Transport", @110], @[@"source", @"Configured in", @150], @[@"executable", @"Executable", @150]];
    if ([section isEqual:@"Editor Settings"]) return @[@[@"name", @"Setting", @240], @[@"value", @"Value", @200], @[@"application", @"Editor", @120]];
    if ([section isEqual:@"Other PATH Tools"]) return @[@[@"name", @"Executable", @280], @[@"position", @"PATH entry", @100]];
    return @[];
}

// The outline column cannot be removed, so it is reused for the name column.
- (void)configureColumns {
    NSTableColumn *nameColumn = self.outline.outlineTableColumn;
    for (NSTableColumn *column in [self.outline.tableColumns copy]) {
        if (column != nameColumn) [self.outline removeTableColumn:column];
    }
    if (!nameColumn) {
        nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        [self.outline addTableColumn:nameColumn];
        self.outline.outlineTableColumn = nameColumn;
    }
    NSInteger nameIndex = 0;
    NSArray<NSArray *> *specs = [self columnSpecs];
    for (NSUInteger index = 0; index < specs.count; index++) {
        NSArray *spec = specs[index];
        BOOL isName = [spec[0] isEqual:@"name"];
        NSTableColumn *column = isName ? nameColumn : [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        column.minWidth = MIN(column.width, 90);
        column.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:spec[0] ascending:YES];
        if (isName) nameIndex = (NSInteger)index;
        else [self.outline addTableColumn:column];
    }
    if (nameIndex > 0) [self.outline moveColumn:0 toColumn:nameIndex];
    [self.outline sizeToFit];
    self.outline.sortDescriptors = @[];
}

#pragma mark Overview

- (void)rebuildOverview {
    for (NSView *view in self.overviewStack.arrangedSubviews) { [self.overviewStack removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSArray *resources = [self resources];
    [self addFullWidth:[self heroCard:resources]];
    [self addFullWidth:[self attentionCard:resources]];
    [self addFullWidth:[self runtimesCard:resources]];
    [self addFullWidth:[self changesCard]];
    NSTextField *privacy = [self wrappingLabel:@"Continuity reads selected local metadata and never runs discovered tools. Scan history stays on this Mac." size:12 color:NSColor.secondaryLabelColor];
    [self addFullWidth:privacy];
}

- (void)addFullWidth:(NSView *)view {
    [self.overviewStack addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:self.overviewStack.widthAnchor].active = YES;
}

- (NSView *)heroCard:(NSArray<NSDictionary *> *)resources {
    NSUInteger packages = 0, extensions = 0;
    NSMutableSet *tools = [NSMutableSet set];
    for (NSDictionary *resource in resources) {
        if ([resource[@"kind"] isEqual:@"editor_extension"]) extensions++;
        else if ([resource[@"kind"] isEqual:@"package"]) packages++;
        else [tools addObject:StringValue(resource[@"canonical_tool_id"], @"")];
    }
    HeroView *hero = [HeroView new];
    NSDictionary *host = self.model.report[@"host"];
    NSString *chip = [StringValue(host[@"architecture"], @"") isEqual:@"aarch64"] ? @"Apple silicon" : @"Intel";
    NSTextField *title = [self label:@"Your development setup" size:16 weight:NSFontWeightSemibold color:NSColor.labelColor];
    NSTextField *subtitle = [self label:[NSString stringWithFormat:@"macOS %@ · %@ · checked %@", StringValue(host[@"os_version"], @"—"), chip, RelativeDate(self.model.lastScanDate)] size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    NSStackView *heading = [self verticalStack:4];
    [heading addArrangedSubview:title];
    [heading addArrangedSubview:subtitle];

    NSUInteger changeCount = [self.model.changes[@"added"] count] + [self.model.changes[@"updated"] count] + [self.model.changes[@"removed"] count];
    NSStackView *stats = [NSStackView new];
    stats.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stats.distribution = NSStackViewDistributionFillEqually;
    stats.spacing = 10;
    [stats addArrangedSubview:[self heroStat:tools.count label:@"Developer tools" section:2]];
    [stats addArrangedSubview:[self heroStat:packages label:@"Packages" section:3]];
    [stats addArrangedSubview:[self heroStat:extensions label:@"Extensions" section:4]];
    [stats addArrangedSubview:[self heroStat:changeCount label:@"Recent changes" section:1]];

    NSStackView *stack = [self verticalStack:12];
    [stack addArrangedSubview:heading];
    [stack addArrangedSubview:stats];
    [hero addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:hero.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-14],
        [stats.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];
    return hero;
}

- (NSView *)heroStat:(NSUInteger)value label:(NSString *)label section:(NSUInteger)section {
    CardView *card = [CardView new];
    card.fill = NSColor.windowBackgroundColor;
    card.cornerRadius = 12;
    card.interactive = YES;
    __weak MainWindowController *weakSelf = self;
    card.onPress = ^{ [weakSelf selectSectionAtIndex:section]; };
    card.accessibilityElement = YES;
    card.accessibilityRole = NSAccessibilityButtonRole;
    card.accessibilityLabel = [NSString stringWithFormat:@"%@, %lu", label, (unsigned long)value];
    card.toolTip = [NSString stringWithFormat:@"Show %@", label];
    NSTextField *number = [self label:[NSString stringWithFormat:@"%lu", (unsigned long)value] size:18 weight:NSFontWeightSemibold color:NSColor.labelColor];
    number.font = [NSFont monospacedDigitSystemFontOfSize:18 weight:NSFontWeightSemibold];
    NSTextField *caption = [self label:label size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    [caption setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *stack = [self verticalStack:0];
    [stack addArrangedSubview:number];
    [stack addArrangedSubview:caption];
    for (NSView *view in @[number, caption]) view.accessibilityElement = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
    ]];
    return card;
}

// Plain-language observations about the setup, each leading somewhere useful.
- (NSArray<NSDictionary *> *)insights:(NSArray<NSDictionary *> *)resources {
    NSMutableArray *insights = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
    NSMutableArray *shadowed = [NSMutableArray array];
    NSMutableOrderedSet *unknown = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *resource in resources) {
        if (!IsDeveloperTool(resource)) continue;
        NSString *key = StringValue(resource[@"canonical_tool_id"], @"");
        if (!groups[key]) groups[key] = [NSMutableArray array];
        [groups[key] addObject:resource];
        if ([resource[@"path_status"] isEqual:@"also_on_path"]) [shadowed addObject:StringValue(resource[@"display_name"], key)];
        if (!StringValue(resource[@"version"], nil)) [unknown addObject:StringValue(resource[@"display_name"], key)];
    }
    NSArray *crowded = [groups.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [@([groups[b] count]) compare:@([groups[a] count])];
    }];
    for (NSString *key in crowded) {
        NSArray *members = groups[key];
        if (members.count < 3 || insights.count >= 2) continue;
        NSDictionary *active = [members filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"path_status == 'first_on_path'"]].firstObject;
        NSString *name = StringValue(members.firstObject[@"display_name"], key);
        [insights addObject:@{@"symbol": @"square.stack.3d.up.fill", @"tint": NSColor.systemOrangeColor,
            @"title": [NSString stringWithFormat:@"%lu %@ installations", (unsigned long)members.count, name],
            @"detail": active ? [NSString stringWithFormat:@"%@ is first on Continuity’s scan PATH. Your shell or version manager may choose another.", StringValue(active[@"version"], @"One installation")] : @"None is first on Continuity’s scan PATH. Other installations may still be usable.",
            @"section": @2}];
    }
    if (shadowed.count) {
        NSOrderedSet *names = [NSOrderedSet orderedSetWithArray:shadowed];
        [insights addObject:@{@"symbol": @"eye.slash.fill", @"tint": NSColor.systemYellowColor,
            @"title": [NSString stringWithFormat:@"%lu later on scan PATH", (unsigned long)shadowed.count],
            @"detail": [NSString stringWithFormat:@"%@ also %@ on Continuity’s scan PATH. Shell PATH settings can differ.", [[names.array subarrayWithRange:NSMakeRange(0, MIN(3u, names.count))] componentsJoinedByString:@", "], shadowed.count == 1 ? @"appears" : @"appear"],
            @"section": @2}];
    }
    if (unknown.count) {
        [insights addObject:@{@"symbol": @"questionmark.circle.fill", @"tint": NSColor.systemGrayColor,
            @"title": [NSString stringWithFormat:@"%lu without a recorded version", (unsigned long)unknown.count],
            @"detail": [NSString stringWithFormat:@"%@. System shims and some installers don’t record versions, and Continuity never runs tools to ask.", [[unknown.array subarrayWithRange:NSMakeRange(0, MIN(3u, unknown.count))] componentsJoinedByString:@", "]],
            @"section": @5}];
    }
    NSArray *warnings = self.model.report[@"warnings"];
    if (warnings.count) {
        [insights addObject:@{@"symbol": @"exclamationmark.triangle.fill", @"tint": NSColor.systemOrangeColor,
            @"title": [NSString stringWithFormat:@"%lu scan %@", (unsigned long)warnings.count, warnings.count == 1 ? @"note" : @"notes"],
            @"detail": [[warnings subarrayWithRange:NSMakeRange(0, MIN(2u, warnings.count))] componentsJoinedByString:@" · "],
            @"section": @5}];
    }
    if (!self.model.monitoring) {
        [insights addObject:@{@"symbol": @"bell.badge.fill", @"tint": NSColor.systemBlueColor,
            @"title": @"Monitoring is off",
            @"detail": @"Turn it on to catch installs and upgrades as they happen.",
            @"action": @"monitor"}];
    }
    return insights;
}

- (NSView *)attentionCard:(NSArray<NSDictionary *> *)resources {
    NSArray *insights = [self insights:resources];
    CardView *card = [CardView new];
    NSStackView *stack = [self verticalStack:12];
    NSTextField *title = [self label:insights.count ? @"Things to review" : @"No scan notes" size:15 weight:NSFontWeightSemibold color:NSColor.labelColor];
    [stack addArrangedSubview:title];
    if (!insights.count) {
        [self addRow:[self wrappingLabel:@"No additional observations from this scan." size:12 color:NSColor.secondaryLabelColor] to:stack];
    }
    NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:2 rows:0];
    grid.columnSpacing = 16;
    grid.rowSpacing = 12;
    NSMutableArray *cells = [NSMutableArray array];
    for (NSDictionary *insight in insights) [cells addObject:[self insightRow:insight]];
    for (NSUInteger i = 0; i < cells.count; i += 2) {
        [grid addRowWithViews:@[cells[i], i + 1 < cells.count ? cells[i + 1] : [NSGridCell emptyContentView]]];
    }
    if (cells.count) {
        [stack addArrangedSubview:grid];
        [grid.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        [grid columnAtIndex:0].xPlacement = NSGridCellPlacementFill;
        [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    }
    [self embedCard:stack in:card];
    return card;
}

- (NSView *)insightRow:(NSDictionary *)insight {
    CardView *row = [CardView new];
    row.cornerRadius = 10;
    row.fill = [insight[@"tint"] colorWithAlphaComponent:0.08];
    row.interactive = YES;
    __weak MainWindowController *weakSelf = self;
    NSNumber *section = insight[@"section"];
    BOOL monitor = [insight[@"action"] isEqual:@"monitor"];
    row.onPress = ^{
        if (monitor) [weakSelf.model setMonitoringEnabled:YES];
        else [weakSelf selectSectionAtIndex:section.unsignedIntegerValue];
    };
    row.accessibilityElement = YES;
    row.accessibilityRole = NSAccessibilityButtonRole;
    row.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", insight[@"title"], insight[@"detail"]];
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:insight[@"symbol"] accessibilityDescription:nil]];
    icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:16 weight:NSFontWeightSemibold];
    icon.contentTintColor = insight[@"tint"];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *title = [self label:insight[@"title"] size:13 weight:NSFontWeightSemibold color:NSColor.labelColor];
    NSTextField *detail = [self wrappingLabel:insight[@"detail"] size:11 color:NSColor.secondaryLabelColor];
    NSStackView *text = [self verticalStack:2];
    [text addArrangedSubview:title];
    [text addArrangedSubview:detail];
    for (NSView *view in @[icon, title, detail]) view.accessibilityElement = NO;
    [row addSubview:icon];
    [row addSubview:text];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:12],
        [icon.topAnchor constraintEqualToAnchor:row.topAnchor constant:12],
        [icon.widthAnchor constraintEqualToConstant:20],
        [text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [text.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [text.topAnchor constraintEqualToAnchor:row.topAnchor constant:11],
        [text.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-11],
        [detail.widthAnchor constraintEqualToAnchor:text.widthAnchor],
    ]];
    return row;
}

- (NSView *)runtimesCard:(NSArray<NSDictionary *> *)resources {
    NSMutableDictionary<NSString *, NSMutableArray *> *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *resource in resources) {
        if (![resource[@"kind"] isEqual:@"runtime"] && ![resource[@"kind"] isEqual:@"package_manager"]) continue;
        NSString *key = StringValue(resource[@"canonical_tool_id"], @"");
        if (!groups[key]) groups[key] = [NSMutableArray array];
        [groups[key] addObject:resource];
    }
    NSArray *keys = [groups.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult byCount = [@([groups[b] count]) compare:@([groups[a] count])];
        return byCount != NSOrderedSame ? byCount : [a compare:b];
    }];
    CardView *card = [CardView new];
    NSStackView *stack = [self verticalStack:10];
    [self addRow:[self cardHeader:@"Runtimes and managers" section:2] to:stack];
    for (NSString *key in [keys subarrayWithRange:NSMakeRange(0, MIN(6u, keys.count))]) {
        NSArray *members = groups[key];
        NSDictionary *active = [members filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"path_status == 'first_on_path'"]].firstObject;
        NSDictionary *shown = active ?: members.firstObject;
        NSString *detail = members.count > 1 ? [NSString stringWithFormat:@"%@ · %lu installs", ProviderName(shown[@"installation_provider"]), (unsigned long)members.count] : ProviderName(shown[@"installation_provider"]);
        NSView *row = [self toolRow:StringValue(shown[@"display_name"], key) identifier:key detail:detail value:StringValue(shown[@"version"], @"—")];
        [stack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    if (!keys.count) [self addRow:[self wrappingLabel:@"No runtimes found." size:12 color:NSColor.secondaryLabelColor] to:stack];
    [self embedCard:stack in:card];
    return card;
}

- (NSView *)changesCard {
    CardView *card = [CardView new];
    NSStackView *stack = [self verticalStack:10];
    [self addRow:[self cardHeader:@"Recent changes" section:1] to:stack];
    NSDictionary *styles = @{@"added": @[@"Added", NSColor.systemGreenColor], @"updated": @[@"Updated", NSColor.systemBlueColor], @"removed": @[@"Removed", NSColor.systemRedColor]};
    NSUInteger shown = 0;
    for (NSString *key in @[@"updated", @"added", @"removed"]) {
        for (NSDictionary *change in self.model.changes[key] ?: @[]) {
            if (shown++ >= 6) break;
            NSString *version = StringValue(change[@"version"], @"");
            NSString *previous = StringValue(change[@"previous_version"], nil);
            NSView *row = [self timelineRow:[NSString stringWithFormat:@"%@ %@", styles[key][0], StringValue(change[@"display_name"], @"")]
                                     detail:previous ? [NSString stringWithFormat:@"%@ → %@", previous, version] : version
                                       tint:styles[key][1]];
            [stack addArrangedSubview:row];
            [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        }
    }
    if (!shown) [self addRow:[self wrappingLabel:@"Nothing has changed since Continuity started tracking. Changes appear here after the next scan finds one." size:12 color:NSColor.secondaryLabelColor] to:stack];
    [self embedCard:stack in:card];
    return card;
}

- (NSView *)cardHeader:(NSString *)title section:(NSUInteger)section {
    NSTextField *label = [self label:title size:15 weight:NSFontWeightSemibold color:NSColor.labelColor];
    NSButton *more = [NSButton buttonWithTitle:@"See All" target:self action:@selector(seeAll:)];
    more.bordered = NO;
    more.tag = (NSInteger)section;
    more.contentTintColor = NSColor.controlAccentColor;
    more.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    more.accessibilityLabel = [NSString stringWithFormat:@"See all %@", title.lowercaseString];
    [label setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [more setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row = [NSStackView stackViewWithViews:@[label, more]];
    return row;
}

- (void)addRow:(NSView *)row to:(NSStackView *)stack {
    [stack addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

- (void)seeAll:(NSButton *)sender { [self selectSectionAtIndex:(NSUInteger)sender.tag]; }

- (NSView *)toolRow:(NSString *)name identifier:(NSString *)identifier detail:(NSString *)detail value:(NSString *)value {
    NSView *row = [NSView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    AvatarView *avatar = [AvatarView new];
    avatar.toolIdentifier = identifier;
    avatar.name = name;
    NSTextField *title = [self label:name size:13 weight:NSFontWeightMedium color:NSColor.labelColor];
    NSTextField *subtitle = [self label:detail size:11 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    NSTextField *version = [self label:value size:13 weight:NSFontWeightSemibold color:NSColor.labelColor];
    version.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightSemibold];
    [version setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    for (NSTextField *label in @[title, subtitle]) [label setContentCompressionResistancePriority:500 forOrientation:NSLayoutConstraintOrientationHorizontal];
    for (NSView *view in @[avatar, title, subtitle, version]) [row addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [avatar.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [avatar.topAnchor constraintEqualToAnchor:row.topAnchor],
        [avatar.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [avatar.widthAnchor constraintEqualToConstant:30],
        [avatar.heightAnchor constraintEqualToConstant:30],
        [title.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:10],
        [title.topAnchor constraintEqualToAnchor:row.topAnchor constant:-1],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:version.leadingAnchor constant:-8],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:1],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:version.leadingAnchor constant:-8],
        [version.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [version.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    row.accessibilityElement = YES;
    row.accessibilityRole = NSAccessibilityStaticTextRole;
    row.accessibilityLabel = [NSString stringWithFormat:@"%@ %@, %@", name, value, detail];
    for (NSView *view in @[title, subtitle, version]) view.accessibilityElement = NO;
    return row;
}

- (NSView *)timelineRow:(NSString *)title detail:(NSString *)detail tint:(NSColor *)tint {
    NSView *row = [NSView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *dot = [NSView new];
    dot.wantsLayer = YES;
    dot.layer.cornerRadius = 4;
    dot.layer.backgroundColor = tint.CGColor;
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *label = [self label:title size:13 weight:NSFontWeightMedium color:NSColor.labelColor];
    NSTextField *value = [self label:detail size:12 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    value.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    [label setContentCompressionResistancePriority:500 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [value setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    for (NSView *view in @[dot, label, value]) [row addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [dot.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:4],
        [dot.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [dot.widthAnchor constraintEqualToConstant:8],
        [dot.heightAnchor constraintEqualToConstant:8],
        [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:12],
        [label.topAnchor constraintEqualToAnchor:row.topAnchor constant:6],
        [label.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-6],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:value.leadingAnchor constant:-8],
        [value.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [value.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

- (void)embedCard:(NSView *)content in:(CardView *)card {
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18],
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
    ]];
}

#pragma mark Inspector

- (BOOL)isGridSection { return [self.section isEqual:@"Developer Tools"]; }

- (InventoryNode *)selectedNode {
    if ([self isGridSection]) {
        NSIndexPath *path = self.grid.selectionIndexPaths.anyObject;
        return path && (NSUInteger)path.item < self.nodes.count ? self.nodes[(NSUInteger)path.item] : nil;
    }
    NSInteger row = self.outline.selectedRow;
    return row >= 0 ? [self.outline itemAtRow:row] : nil;
}

- (void)updateInspector {
    for (NSView *view in self.inspectorStack.arrangedSubviews) { [self.inspectorStack removeArrangedSubview:view]; [view removeFromSuperview]; }
    InventoryNode *node = [self selectedNode];
    if (!node) {
        NSTextField *hint = [self wrappingLabel:@"Select an item to see its details." size:12 color:NSColor.tertiaryLabelColor];
        [self.inspectorStack addArrangedSubview:hint];
        return;
    }
    NSTextField *title = [self wrappingLabel:StringValue(node.resource[@"display_name"], node.title) size:17 color:NSColor.labelColor];
    title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    title.selectable = YES;
    NSView *heading = title;
    if (node.toolIdentifier.length) {
        AvatarView *avatar = [AvatarView new];
        avatar.toolIdentifier = node.toolIdentifier;
        avatar.name = StringValue(node.resource[@"display_name"], node.title);
        [avatar.widthAnchor constraintEqualToConstant:36].active = YES;
        [avatar.heightAnchor constraintEqualToConstant:36].active = YES;
        NSStackView *row = [NSStackView stackViewWithViews:@[avatar, title]];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.spacing = 10;
        heading = row;
    }
    [self.inspectorStack addArrangedSubview:heading];
    [heading.widthAnchor constraintEqualToAnchor:self.inspectorStack.widthAnchor].active = YES;
    [self.inspectorStack setCustomSpacing:16 afterView:heading];
    for (NSArray<NSString *> *detail in node.details) {
        NSTextField *label = [self label:detail[0].uppercaseString size:10 weight:NSFontWeightSemibold color:NSColor.tertiaryLabelColor];
        NSTextField *value = [self wrappingLabel:detail[1] size:12 color:NSColor.labelColor];
        value.selectable = YES;
        NSStackView *pair = [self verticalStack:3];
        [pair addArrangedSubview:label];
        [pair addArrangedSubview:value];
        [self.inspectorStack addArrangedSubview:pair];
    }
    NSButton *copy = [NSButton buttonWithTitle:@"Copy Details" target:self action:@selector(copyDetails:)];
    NSMutableArray *buttons = [NSMutableArray arrayWithObject:copy];
    if (StringValue(node.resource[@"installation_path"], nil)) {
        [buttons addObject:[NSButton buttonWithTitle:@"Show in Finder" target:self action:@selector(revealInFinder:)]];
    }
    NSStackView *actions = [NSStackView stackViewWithViews:buttons];
    actions.spacing = 8;
    [actions setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.inspectorStack setCustomSpacing:18 afterView:self.inspectorStack.arrangedSubviews.lastObject];
    [self.inspectorStack addArrangedSubview:actions];
}

- (InventoryNode *)actionNode {
    if ([self isGridSection]) return [self selectedNode];
    NSInteger clicked = self.outline.clickedRow;
    return clicked >= 0 ? [self.outline itemAtRow:clicked] : [self selectedNode];
}

- (void)copyDetails:(id)sender {
    InventoryNode *node = [self actionNode];
    if (!node) return;
    NSMutableArray *lines = [NSMutableArray arrayWithObject:node.title];
    for (NSArray<NSString *> *detail in node.details) [lines addObject:[NSString stringWithFormat:@"%@: %@", detail[0], [detail[1] stringByReplacingOccurrencesOfString:@"\n" withString:@", "]]];
    [self copyString:[lines componentsJoinedByString:@"\n"]];
}

- (void)copyName:(id)sender { [self copyString:[self actionNode].title]; }
- (void)copyVersion:(id)sender { [self copyString:[self actionNode].values[@"version"]]; }

- (void)copy:(id)sender {
    if ([self selectedNode]) [self copyDetails:sender];
}

- (void)copyString:(NSString *)string {
    if (!string.length) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:string forType:NSPasteboardTypeString];
}

- (void)revealInFinder:(id)sender {
    NSString *path = StringValue([self actionNode].resource[@"installation_path"], nil);
    if (path) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    InventoryNode *node = [self actionNode];
    if (!node) return;
    [menu addItemWithTitle:@"Copy Name" action:@selector(copyName:) keyEquivalent:@""].target = self;
    if (node.values[@"version"].length) [menu addItemWithTitle:@"Copy Version" action:@selector(copyVersion:) keyEquivalent:@""].target = self;
    [menu addItemWithTitle:@"Copy Details" action:@selector(copyDetails:) keyEquivalent:@""].target = self;
    if (StringValue(node.resource[@"installation_path"], nil)) {
        [menu addItem:NSMenuItem.separatorItem];
        [menu addItemWithTitle:@"Show in Finder" action:@selector(revealInFinder:) keyEquivalent:@""].target = self;
    }
}

#pragma mark Sidebar table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.sidebarEntries.count;
}

- (NSUInteger)badgeForSection:(NSString *)section {
    if (!self.model.report) return 0;
    NSArray *resources = [self resources];
    NSDictionary *local = self.model.localMetadata;
    if ([section isEqual:@"Changes"]) return [self.model.changes[@"added"] count] + [self.model.changes[@"updated"] count] + [self.model.changes[@"removed"] count];
    if ([section isEqual:@"Developer Tools"]) {
        NSMutableSet *ids = [NSMutableSet set];
        for (NSDictionary *r in resources) if (IsDeveloperTool(r)) [ids addObject:StringValue(r[@"canonical_tool_id"], @"")];
        return ids.count;
    }
    if ([section isEqual:@"Packages"]) return [[resources filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind == 'package'"]] count];
    if ([section isEqual:@"Editor Extensions"]) return [[resources filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind == 'editor_extension'"]] count];
    if ([section isEqual:@"All Installations"]) return resources.count;
    if ([section isEqual:@"Workspaces"]) return [local[@"workspaces"] count];
    if ([section isEqual:@"MCP Servers"]) return [local[@"mcp_servers"] count];
    if ([section isEqual:@"Editor Settings"]) return [local[@"editor_settings"] count];
    if ([section isEqual:@"Other PATH Tools"]) return [local[@"unknown_path_tools"] count];
    return 0;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *entry = self.sidebarEntries[(NSUInteger)row];
    if (entry[@"header"]) {
        NSTableCellView *cell = [NSTableCellView new];
        NSTextField *label = [self label:entry[@"header"] size:11 weight:NSFontWeightSemibold color:NSColor.secondaryLabelColor];
        [cell addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:6],
            [label.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-3],
        ]];
        return cell;
    }
    NSTableCellView *cell = [NSTableCellView new];
    NSImageView *image = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:entry[@"symbol"] accessibilityDescription:entry[@"title"]]];
    image.translatesAutoresizingMaskIntoConstraints = NO;
    image.contentTintColor = NSColor.controlAccentColor;
    NSTextField *label = [self label:entry[@"title"] size:13 weight:NSFontWeightRegular color:NSColor.labelColor];
    cell.imageView = image;
    cell.textField = label;
    [cell addSubview:image];
    [cell addSubview:label];
    NSMutableArray *constraints = [@[
        [image.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
        [image.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        [image.widthAnchor constraintEqualToConstant:18],
        [label.leadingAnchor constraintEqualToAnchor:image.trailingAnchor constant:8],
        [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ] mutableCopy];
    NSUInteger badge = [self badgeForSection:entry[@"title"]];
    cell.accessibilityLabel = badge ? [NSString stringWithFormat:@"%@, %lu", entry[@"title"], (unsigned long)badge] : entry[@"title"];
    image.accessibilityElement = NO;
    if (badge) {
        NSTextField *count = [self label:[NSString stringWithFormat:@"%lu", (unsigned long)badge] size:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
        count.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
        count.accessibilityElement = NO;
        [cell addSubview:count];
        [constraints addObjectsFromArray:@[
            [count.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
            [count.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:count.leadingAnchor constant:-6],
        ]];
    } else {
        [constraints addObject:[label.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-8]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return cell;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return self.sidebarEntries[(NSUInteger)row][@"header"] ? (row == 0 ? 26 : 34) : 28;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return self.sidebarEntries[(NSUInteger)row][@"header"] == nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.sidebarTable.selectedRow;
    if (row < 0) return;
    NSDictionary *entry = self.sidebarEntries[(NSUInteger)row];
    if (entry[@"title"]) [self showSection:entry[@"title"]];
}

#pragma mark Outline

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(InventoryNode *)item {
    return (NSInteger)(item ? item.children.count : self.nodes.count);
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(InventoryNode *)item {
    return item ? item.children[(NSUInteger)index] : self.nodes[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(InventoryNode *)item {
    return item.children.count > 0;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)column item:(InventoryNode *)item {
    NSString *key = column.identifier;
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:key owner:self];
    if (!cell) {
        cell = [NSTableCellView new];
        cell.identifier = key;
        NSTextField *label = [self label:@"" size:12 weight:NSFontWeightRegular color:NSColor.labelColor];
        cell.textField = label;
        [cell addSubview:label];
        NSImageView *image = [NSImageView new];
        image.translatesAutoresizingMaskIntoConstraints = NO;
        image.imageScaling = NSImageScaleProportionallyUpOrDown;
        image.wantsLayer = YES;
        image.accessibilityElement = NO;
        cell.imageView = image;
        [cell addSubview:image];
        [NSLayoutConstraint activateConstraints:@[
            [image.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [image.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [image.widthAnchor constraintEqualToConstant:16],
            [image.heightAnchor constraintEqualToConstant:16],
            [label.leadingAnchor constraintEqualToAnchor:image.trailingAnchor constant:4],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-2],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    NSString *text = [item valueForColumn:key];
    cell.textField.stringValue = text.length ? text : @"—";
    cell.textField.accessibilityLabel = text.length && ![text isEqual:@"—"] ? nil : @"None";
    BOOL primary = [key isEqual:@"name"];
    cell.textField.font = [NSFont systemFontOfSize:12 weight:primary && item.children.count ? NSFontWeightSemibold : (primary ? NSFontWeightMedium : NSFontWeightRegular)];
    cell.textField.textColor = primary ? NSColor.labelColor : NSColor.secondaryLabelColor;
    if ([key isEqual:@"path"] && [text isEqual:@"First"]) cell.textField.textColor = NSColor.systemGreenColor;
    NSImage *image = nil;
    cell.imageView.contentTintColor = nil;
    if (primary) image = ToolIconForIdentifier(item.toolIdentifier);
    if ([key isEqual:@"change"] && item.symbol) {
        image = [NSImage imageWithSystemSymbolName:item.symbol accessibilityDescription:text];
        cell.imageView.contentTintColor = item.tint;
        cell.textField.textColor = item.tint;
    }
    cell.imageView.image = image;
    cell.imageView.hidden = image == nil;
    cell.imageView.layer.backgroundColor = primary && image ? NSColor.whiteColor.CGColor : NSColor.clearColor.CGColor;
    cell.imageView.layer.cornerRadius = primary && image ? 3 : 0;
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    [self updateInspector];
}

- (void)outlineView:(NSOutlineView *)outlineView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors {
    [self sortNodes];
    [outlineView reloadData];
    [self updateInspector];
}

#pragma mark Tool grid

- (NSInteger)collectionView:(NSCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self isGridSection] ? (NSInteger)self.nodes.count : 0;
}

- (NSSize)collectionView:(NSCollectionView *)collectionView layout:(NSCollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat available = MAX(228, collectionView.enclosingScrollView.contentView.bounds.size.width - 36);
    NSUInteger columns = MAX(1, (NSUInteger)((available + 14) / 242));
    return NSMakeSize((available - (columns - 1) * 14) / columns, 150);
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
    ToolCardItem *item = [collectionView makeItemWithIdentifier:@"tool" forIndexPath:indexPath];
    InventoryNode *node = self.nodes[(NSUInteger)indexPath.item];
    NSArray<InventoryNode *> *installs = node.children.count ? node.children : @[node];
    InventoryNode *active = nil;
    for (InventoryNode *install in installs) if ([install.values[@"path"] isEqual:@"First"]) active = install;
    InventoryNode *shown = active ?: installs.firstObject;
    NSMutableArray *others = [NSMutableArray array];
    for (InventoryNode *install in installs) {
        NSString *version = install.values[@"version"];
        if (install != shown && version.length && ![version isEqual:@"—"]) [others addObject:version];
    }
    NSString *version = shown.values[@"version"];
    [item configureWithName:node.title
                 identifier:node.toolIdentifier ?: @""
                       kind:node.values[@"kind"] ?: @""
                    version:[version isEqual:@"—"] ? @"" : version
                     source:shown.values[@"source"] ?: @""
              otherVersions:others
                     active:active != nil];
    __weak MainWindowController *weakSelf = self;
    __weak NSCollectionView *weakCollection = collectionView;
    ((CardView *)item.view).onPress = ^{
        [weakCollection selectItemsAtIndexPaths:[NSSet setWithObject:indexPath] scrollPosition:NSCollectionViewScrollPositionCenteredVertically];
        [weakSelf updateInspector];
    };
    return item;
}

- (void)collectionView:(NSCollectionView *)collectionView didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths { [self updateInspector]; }
- (void)collectionView:(NSCollectionView *)collectionView didDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)indexPaths { [self updateInspector]; }

#pragma mark Search

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object != self.searchField) return;
    // Overview has nothing to filter, so searching there searches everything.
    NSString *query = self.searchField.stringValue;
    if ([self.section isEqual:@"Overview"] && query.length) {
        [self selectSectionAtIndex:5];
        self.searchField.stringValue = query;
    }
    [self refresh];
}

#pragma mark Factories

- (NSStackView *)verticalStack:(CGFloat)spacing {
    NSStackView *stack = [NSStackView new];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSTextField *)wrappingLabel:(NSString *)text size:(CGFloat)size color:(NSColor *)color {
    NSTextField *label = [NSTextField wrappingLabelWithString:text ?: @""];
    label.font = [NSFont systemFontOfSize:size];
    label.textColor = color;
    label.selectable = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

@end
