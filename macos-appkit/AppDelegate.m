#import "AppDelegate.h"
#import "BrandMark.h"
#import "MainWindowController.h"
#import "ScanModel.h"
#import "SettingsWindowController.h"

@interface AppDelegate () <NSWindowDelegate>
@property(nonatomic, strong) ScanModel *model;
@property(nonatomic, strong) MainWindowController *windowController;
@property(nonatomic, strong) SettingsWindowController *settingsController;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSPopover *popover;
@property(nonatomic, strong) NSTextField *popoverStatus;
@property(nonatomic, strong) NSTextField *popoverDetail;
@property(nonatomic, strong) NSButton *monitorButton;
@property(nonatomic, strong) NSButton *scanButton;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.model = [ScanModel new];
    self.windowController = [[MainWindowController alloc] initWithModel:self.model];
    self.windowController.window.delegate = self;
    [self buildMenuBarItem];
    [self buildApplicationMenu];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshPopover) name:ScanModelDidChangeNotification object:self.model];
    [self openMainWindow:nil];
    [self.model refreshQuietly];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    if (!visible) [self openMainWindow:nil];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification { [self.model stop]; }

// The Dock icon and menus appear only while the main window is open.
- (void)windowWillClose:(NSNotification *)notification {
    NSWindow *closing = notification.object;
    NSWindow *other = closing == self.windowController.window ? self.settingsController.window : self.windowController.window;
    if (!other.isVisible) [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

#pragma mark Menu bar item

- (void)buildMenuBarItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = ContinuityMenuBarImage();
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);
    self.popover = [NSPopover new];
    self.popover.behavior = NSPopoverBehaviorTransient;
    NSViewController *controller = [NSViewController new];
    controller.view = [self popoverView];
    self.popover.contentViewController = controller;
    self.popover.contentSize = controller.view.fittingSize;
}

- (NSView *)popoverView {
    NSView *background = [NSView new];
    NSStackView *stack = [NSStackView new];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *title = [NSTextField labelWithString:@"Continuity"];
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    [stack addArrangedSubview:title];
    self.popoverStatus = [NSTextField labelWithString:@""];
    self.popoverStatus.font = [NSFont systemFontOfSize:12];
    self.popoverStatus.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:self.popoverStatus];
    self.popoverDetail = [NSTextField labelWithString:@""];
    self.popoverDetail.font = [NSFont systemFontOfSize:12];
    self.popoverDetail.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:self.popoverDetail];
    [stack setCustomSpacing:12 afterView:self.popoverDetail];
    [stack addArrangedSubview:[self separator]];
    [stack addArrangedSubview:[self popoverButton:@"Open Continuity" action:@selector(openMainWindow:) symbol:@"macwindow"]];
    self.scanButton = [self popoverButton:@"Scan Now" action:@selector(scanNow:) symbol:@"arrow.clockwise"];
    [stack addArrangedSubview:self.scanButton];
    [stack addArrangedSubview:[self popoverButton:@"Settings…" action:@selector(openSettings:) symbol:@"gearshape"]];
    self.monitorButton = [NSButton checkboxWithTitle:@"Monitor in background" target:self action:@selector(toggleMonitoring:)];
    [stack addArrangedSubview:self.monitorButton];
    [stack addArrangedSubview:[self separator]];
    [stack addArrangedSubview:[self popoverButton:@"Quit Continuity" action:@selector(quit:) symbol:@"power"]];
    [background addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:background.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:background.bottomAnchor constant:-12],
        [stack.widthAnchor constraintEqualToConstant:260],
    ]];
    return background;
}

- (NSBox *)separator {
    NSBox *box = [NSBox new];
    box.boxType = NSBoxSeparator;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [box.widthAnchor constraintEqualToConstant:260].active = YES;
    return box;
}

- (NSButton *)popoverButton:(NSString *)title action:(SEL)action symbol:(NSString *)symbol {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bordered = NO;
    button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    button.imagePosition = NSImageLeading;
    button.imageHugsTitle = YES;
    button.alignment = NSTextAlignmentLeft;
    button.contentTintColor = NSColor.labelColor;
    return button;
}

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover performClose:sender];
        return;
    }
    [self refreshPopover];
    // Activate first: an inactive app's popover can open behind the frontmost window.
    [NSApp activateIgnoringOtherApps:YES];
    [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
    NSWindow *window = self.popover.contentViewController.view.window;
    window.level = NSStatusWindowLevel;
    [window makeKeyAndOrderFront:nil];
}

- (void)refreshPopover {
    if (self.model.scanning) {
        self.popoverStatus.stringValue = self.model.phase ?: @"Scanning";
    } else if (self.model.errorMessage) {
        self.popoverStatus.stringValue = self.model.errorMessage;
    } else {
        NSUInteger count = [self.model.report[@"resources"] count];
        self.popoverStatus.stringValue = self.model.report ? [NSString stringWithFormat:@"%lu items on this Mac", (unsigned long)count] : @"No scan yet";
    }
    NSString *when = self.model.lastScanDate
        ? [NSString stringWithFormat:@"Last scan %@", [NSDateFormatter localizedStringFromDate:self.model.lastScanDate dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]]
        : @"";
    self.popoverDetail.stringValue = self.model.changeSummary ? [NSString stringWithFormat:@"Changes: %@", self.model.changeSummary] : when;
    self.monitorButton.state = self.model.monitoring ? NSControlStateValueOn : NSControlStateValueOff;
    self.scanButton.enabled = !self.model.scanning;
}

#pragma mark Application menu

- (void)buildApplicationMenu {
    NSMenu *main = [NSMenu new];

    NSMenu *app = [self submenu:@"Continuity" in:main];
    [app addItemWithTitle:@"About Continuity" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [app addItem:NSMenuItem.separatorItem];
    [self add:app title:@"Settings…" action:@selector(openSettings:) key:@","];
    [app addItem:NSMenuItem.separatorItem];
    [app addItemWithTitle:@"Hide Continuity" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [app addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [app addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [app addItem:NSMenuItem.separatorItem];
    [self add:app title:@"Quit Continuity" action:@selector(quit:) key:@"q"];

    NSMenu *file = [self submenu:@"File" in:main];
    [self add:file title:@"Scan Now" action:@selector(scanNow:) key:@"r"];
    NSMenuItem *approve = [self add:file title:@"Add Workspace…" action:@selector(approveWorkspace:) key:@"o"];
    approve.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [self add:file title:@"Export Report…" action:@selector(exportReport:) key:@"e"];
    [file addItem:NSMenuItem.separatorItem];
    [file addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];

    NSMenu *edit = [self submenu:@"Edit" in:main];
    [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [edit addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [edit addItem:NSMenuItem.separatorItem];
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [edit addItem:NSMenuItem.separatorItem];
    [self add:edit title:@"Find…" action:@selector(focusSearch:) key:@"f"];

    NSMenu *view = [self submenu:@"View" in:main];
    [MainWindowController.sectionTitles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
        NSString *key = index < 9 ? [NSString stringWithFormat:@"%lu", (unsigned long)index + 1] : (index == 9 ? @"0" : @"");
        NSMenuItem *item = [self add:view title:title action:@selector(showSection:) key:key];
        item.tag = (NSInteger)index;
        if (index == 5) [view addItem:NSMenuItem.separatorItem];
    }];
    [view addItem:NSMenuItem.separatorItem];
    NSMenuItem *sidebar = [view addItemWithTitle:@"Toggle Sidebar" action:@selector(toggleSidebar:) keyEquivalent:@"s"];
    sidebar.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    NSMenuItem *fullScreen = [view addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    fullScreen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;

    NSMenu *window = [self submenu:@"Window" in:main];
    [window addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [window addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [window addItem:NSMenuItem.separatorItem];
    [self add:window title:@"Continuity" action:@selector(openMainWindow:) key:@"0"].keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [window addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    NSApp.windowsMenu = window;

    NSApp.mainMenu = main;
}

- (NSMenu *)submenu:(NSString *)title in:(NSMenu *)main {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
    item.submenu = menu;
    [main addItem:item];
    return menu;
}

- (NSMenuItem *)add:(NSMenu *)menu title:(NSString *)title action:(SEL)action key:(NSString *)key {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    return item;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(scanNow:)) return !self.model.scanning;
    if (item.action == @selector(exportReport:)) return self.model.report != nil;
    return YES;
}

#pragma mark Actions

- (void)openMainWindow:(id)sender {
    [self.popover performClose:sender];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self.windowController showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)openSettings:(id)sender {
    [self.popover performClose:sender];
    if (!self.settingsController) {
        self.settingsController = [[SettingsWindowController alloc] initWithModel:self.model];
        self.settingsController.window.delegate = self;
    }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self.settingsController showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showSection:(NSMenuItem *)sender {
    [self openMainWindow:sender];
    [self.windowController selectSectionAtIndex:(NSUInteger)sender.tag];
}

- (void)focusSearch:(id)sender { [self.windowController focusSearch]; }

- (void)approveWorkspace:(id)sender {
    [self openMainWindow:sender];
    [self.windowController approveWorkspace:sender];
}

- (void)exportReport:(id)sender {
    [self openMainWindow:sender];
    [self.windowController exportReport:sender];
}

- (void)scanNow:(id)sender { [self.model scan]; }
- (void)toggleMonitoring:(NSButton *)sender { [self.model setMonitoringEnabled:sender.state == NSControlStateValueOn]; }
- (void)quit:(id)sender { [NSApp terminate:nil]; }

@end
