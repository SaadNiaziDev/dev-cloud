#import "SettingsWindowController.h"

@interface SettingsWindowController () <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong) ScanModel *model;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *toggles;
@property(nonatomic, strong) NSTextField *message;
@property(nonatomic, strong) NSTableView *folders;
@property(nonatomic, strong) NSSegmentedControl *folderButtons;
@end

@implementation SettingsWindowController

- (instancetype)initWithModel:(ScanModel *)model {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 360)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing:NSBackingStoreBuffered defer:YES];
    self = [super initWithWindow:window];
    if (self) {
        _model = model;
        _toggles = [NSMutableDictionary dictionary];
        window.toolbarStyle = NSWindowToolbarStylePreference;
        NSTabViewController *tabs = [NSTabViewController new];
        tabs.tabStyle = NSTabViewControllerTabStyleToolbar;
        [tabs addTabViewItem:[self tab:@"General" symbol:@"gearshape" view:[self generalView]]];
        [tabs addTabViewItem:[self tab:@"Discovery" symbol:@"magnifyingglass" view:[self discoveryView]]];
        [tabs addTabViewItem:[self tab:@"Workspaces" symbol:@"folder" view:[self workspacesView]]];
        window.contentViewController = tabs;
        [window center];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:ScanModelDidChangeNotification object:model];
        [self refresh];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSTabViewItem *)tab:(NSString *)title symbol:(NSString *)symbol view:(NSView *)view {
    NSViewController *controller = [NSViewController new];
    controller.view = view;
    controller.preferredContentSize = view.fittingSize;
    NSTabViewItem *item = [NSTabViewItem tabViewItemWithViewController:controller];
    item.label = title;
    item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    return item;
}

#pragma mark Panes

- (NSView *)generalView {
    self.message = [self note:@""];
    return [self pane:@[
        [self toggle:@"monitoring" title:@"Monitor this Mac in the background" note:@"Watches package, runtime, and editor folders and rescans every five minutes. Closing the window keeps Continuity in the menu bar."],
        [self toggle:@"login" title:@"Open Continuity at login" note:nil],
        [self toggle:@"notifications" title:@"Notify me when tools change" note:@"Sent only after a background scan finds changes."],
        self.message,
    ]];
}

- (NSView *)discoveryView {
    return [self pane:@[
        [self toggle:@"paths" title:@"Show installation locations" note:@"Adds full paths to the inventory and enables Show in Finder. Exports will include them."],
        [self toggle:@"mcp" title:@"Inspect MCP server configuration" note:@"Keeps server names, transport, and executable names. Arguments, URLs, and secrets are discarded."],
        [self toggle:@"editor" title:@"Inspect editor preferences" note:@"Reads an allowlist of VS Code and Cursor settings. Paths and unknown keys are ignored."],
        [self toggle:@"pathTools" title:@"List other PATH executables" note:@"Names only. Files are never run."],
    ]];
}

- (NSView *)workspacesView {
    NSTextField *intro = [self note:@"Continuity reads the current branch and linked worktree names in these folders. It never reads source files or remote URLs."];
    self.folders = [NSTableView new];
    self.folders.headerView = nil;
    self.folders.dataSource = self;
    self.folders.delegate = self;
    self.folders.rowHeight = 22;
    self.folders.style = NSTableViewStyleFullWidth;
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"folder"];
    [self.folders addTableColumn:column];
    NSScrollView *scroll = [NSScrollView new];
    scroll.documentView = self.folders;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.folderButtons = [NSSegmentedControl segmentedControlWithImages:@[
        [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:@"Add Workspace"],
        [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Remove Workspace"]
    ] trackingMode:NSSegmentSwitchTrackingMomentary target:self action:@selector(folderButtonClicked:)];
    self.folderButtons.segmentStyle = NSSegmentStyleSmallSquare;
    NSView *pane = [self pane:@[intro, scroll, self.folderButtons]];
    NSStackView *stack = pane.subviews.firstObject;
    [stack setCustomSpacing:0 afterView:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.heightAnchor constraintEqualToConstant:170],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];
    return pane;
}

- (NSView *)pane:(NSArray<NSView *> *)views {
    NSView *pane = [NSView new];
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [pane addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor constant:-28],
        [stack.topAnchor constraintEqualToAnchor:pane.topAnchor constant:22],
        [stack.bottomAnchor constraintEqualToAnchor:pane.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToConstant:460],
    ]];
    return pane;
}

- (NSView *)toggle:(NSString *)key title:(NSString *)title note:(NSString *)note {
    NSButton *button = [NSButton checkboxWithTitle:title target:self action:@selector(toggleChanged:)];
    button.identifier = key;
    self.toggles[key] = button;
    if (!note) return button;
    NSTextField *detail = [self note:note];
    NSStackView *stack = [NSStackView stackViewWithViews:@[button, detail]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 3;
    stack.edgeInsets = NSEdgeInsetsMake(0, 0, 0, 0);
    [detail.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:20].active = YES;
    return stack;
}

- (NSTextField *)note:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = NSColor.secondaryLabelColor;
    label.selectable = NO;
    [label.widthAnchor constraintLessThanOrEqualToConstant:440].active = YES;
    return label;
}

#pragma mark Actions

- (void)toggleChanged:(NSButton *)sender {
    BOOL on = sender.state == NSControlStateValueOn;
    NSString *key = sender.identifier;
    if ([key isEqual:@"monitoring"]) [self.model setMonitoringEnabled:on];
    else if ([key isEqual:@"login"]) [self.model setLaunchAtLoginEnabled:on];
    else if ([key isEqual:@"notifications"]) [self.model setNotificationsEnabled:on];
    else if ([key isEqual:@"paths"]) self.model.includePaths = on;
    else if ([key isEqual:@"mcp"]) self.model.inspectMCP = on;
    else if ([key isEqual:@"editor"]) self.model.inspectEditorSettings = on;
    else if ([key isEqual:@"pathTools"]) self.model.inspectPathTools = on;
}

- (void)folderButtonClicked:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.prompt = @"Add Workspace";
        panel.canChooseFiles = NO;
        panel.canChooseDirectories = YES;
        panel.allowsMultipleSelection = YES;
        [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
            if (response != NSModalResponseOK) return;
            for (NSURL *url in panel.URLs) [self.model addApprovedRoot:url.standardizedURL.path];
        }];
    } else {
        NSInteger row = self.folders.selectedRow;
        if (row >= 0 && row < (NSInteger)self.model.approvedRoots.count) [self.model removeApprovedRoot:self.model.approvedRoots[(NSUInteger)row]];
    }
}

- (void)refresh {
    NSDictionary *values = @{
        @"monitoring": @(self.model.monitoring),
        @"login": @(self.model.launchAtLogin),
        @"notifications": @(self.model.notificationsEnabled),
        @"paths": @(self.model.includePaths),
        @"mcp": @(self.model.inspectMCP),
        @"editor": @(self.model.inspectEditorSettings),
        @"pathTools": @(self.model.inspectPathTools),
    };
    for (NSString *key in self.toggles) self.toggles[key].state = [values[key] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.message.stringValue = self.model.settingsMessage ?: @"";
    [self.folders reloadData];
    [self.folderButtons setEnabled:self.folders.selectedRow >= 0 forSegment:1];
}

#pragma mark Folder table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.model.approvedRoots.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSString *path = self.model.approvedRoots[(NSUInteger)row];
    NSTableCellView *cell = [NSTableCellView new];
    NSImageView *icon = [NSImageView imageViewWithImage:[NSWorkspace.sharedWorkspace iconForFile:path]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *label = [NSTextField labelWithString:[path stringByAbbreviatingWithTildeInPath]];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:icon];
    [cell addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
        [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:16],
        [icon.heightAnchor constraintEqualToConstant:16],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:6],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-4],
        [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
    ]];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self.folderButtons setEnabled:self.folders.selectedRow >= 0 forSegment:1];
}

@end
