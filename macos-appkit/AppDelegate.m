#import "AppDelegate.h"
#import "BrandMark.h"
#import "MainWindowController.h"
#import "ScanModel.h"
#import "StatusMenu.h"
#import "CloudAutoBackup.h"
#import "CloudAccount.h"
#import "SignInWindowController.h"

@interface AppDelegate () <NSWindowDelegate>
@property(nonatomic, strong) ScanModel *model;
@property(nonatomic, strong) MainWindowController *windowController;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) StatusMenu *statusMenu;
@property(nonatomic, strong) CloudAutoBackup *automaticBackup;
@property(nonatomic, strong) SignInWindowController *signIn;
@property(nonatomic) BOOL gateDisabled;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildApplicationMenu];
#ifdef DEVCLOUD_TESTING
    // The UI harness renders pages against fixtures without a cloud session.
    self.gateDisabled = NSProcessInfo.processInfo.environment[@"DEVCLOUD_UI_OUT"] != nil;
#endif
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged:) name:CloudAccountDidChangeNotification object:CloudAccount.shared];
    [CloudAccount.shared restore];
    if (self.gateDisabled || CloudAccount.shared.state == CloudSignedIn) [self unlock:NO];
    else [self lock];
}

- (BOOL)unlocked { return self.model != nil; }

// Nothing scans, monitors or shows inventory until the account is signed in.
- (void)accountChanged:(NSNotification *)notification {
    if (self.gateDisabled) return;
    BOOL signedIn = CloudAccount.shared.state == CloudSignedIn;
    if (signedIn && !self.unlocked) [self unlock:YES];
    else if (!signedIn && self.unlocked && CloudAccount.shared.state != CloudSigningIn) [self lock];
}

- (void)unlock:(BOOL)interactive {
    [self.signIn close];
    self.signIn = nil;
    self.model = [ScanModel new];
    self.automaticBackup = [[CloudAutoBackup alloc] initWithAccount:CloudAccount.shared];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(completedInventoryScan:) name:ScanModelDidChangeNotification object:self.model];
    self.windowController = [[MainWindowController alloc] initWithModel:self.model];
    self.windowController.window.delegate = self;
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusMenu = [[StatusMenu alloc] initWithModel:self.model statusItem:self.statusItem target:self];
    // A fresh sign-in is usually a new Mac: start where its backup can be installed.
    if (interactive) [self.windowController showPage:PageSetup];
    [self openMainWindow:nil];
    [self.model refreshQuietly];
}

- (void)lock {
    [NSNotificationCenter.defaultCenter removeObserver:self name:ScanModelDidChangeNotification object:nil];
    [self.statusMenu close];
    [self.model stop];
    if (self.statusItem) [NSStatusBar.systemStatusBar removeStatusItem:self.statusItem];
    self.windowController.window.delegate = nil;
    [self.windowController close];
    self.statusMenu = nil;
    self.statusItem = nil;
    self.windowController = nil;
    self.automaticBackup = nil;
    self.model = nil;
    if (!self.signIn) {
        self.signIn = [[SignInWindowController alloc] initWithAccount:CloudAccount.shared];
        self.signIn.window.delegate = self;
    }
    [self openMainWindow:nil];
}

- (void)completedInventoryScan:(NSNotification *)notification {
    if (!self.model.scanning && !self.model.showingSavedScan && !self.model.errorMessage && [self.model.phase isEqual:@"Scan complete"]) {
        [self.automaticBackup completedScan:self.model.report];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    if (!visible) [self openMainWindow:nil];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification { [self.model stop]; }

// The Dock icon and menus appear only while the main window is open.
- (void)windowWillClose:(NSNotification *)notification {
    // Closing the sign-in window quits: there is nothing to run in the background.
    if (!self.unlocked && notification.object == self.signIn.window) { [NSApp terminate:nil]; return; }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

#pragma mark Application menu

- (void)buildApplicationMenu {
    NSMenu *main = [NSMenu new];

    NSMenu *app = [self submenu:@"DevCloud" in:main];
    [app addItemWithTitle:@"About DevCloud" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [app addItem:NSMenuItem.separatorItem];
    [self add:app title:@"Settings…" action:@selector(openSettings:) key:@","];
    [app addItem:NSMenuItem.separatorItem];
    [app addItemWithTitle:@"Hide DevCloud" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [app addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [app addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [app addItem:NSMenuItem.separatorItem];
    [self add:app title:@"Quit DevCloud" action:@selector(quit:) key:@"q"];

    NSMenu *file = [self submenu:@"File" in:main];
    [self add:file title:@"Scan Now" action:@selector(scanNow:) key:@"r"];
    NSMenuItem *approve = [self add:file title:@"Add Workspace…" action:@selector(approveWorkspace:) key:@"o"];
    approve.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [self add:file title:@"Export JSON…" action:@selector(exportReport:) key:@"e"];
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
    [self add:edit title:@"Find Tools…" action:@selector(focusSearch:) key:@"f"];

    NSMenu *view = [self submenu:@"View" in:main];
    [PageCatalog() enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger index, BOOL *stop) {
        NSMenuItem *item = [self add:view title:entry[@"title"] action:@selector(showSection:) key:[NSString stringWithFormat:@"%lu", (unsigned long)index + 1]];
        item.tag = (NSInteger)index;
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
    [self add:window title:@"DevCloud" action:@selector(openMainWindow:) key:@"0"].keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
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
    if (!self.unlocked && item.action != @selector(quit:)) return NO;
    if (item.action == @selector(scanNow:)) return !self.model.scanning;
    if (item.action == @selector(exportReport:)) return self.model.report != nil;
    if (item.action == @selector(showSection:)) item.state = self.windowController.window.isVisible && self.windowController.currentPage == item.tag ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}

#pragma mark Actions

- (void)openMainWindow:(id)sender {
    [self.statusMenu close];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    if (!self.unlocked) [self.signIn showWindow:nil];
    else [self.windowController showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)openSettings:(id)sender { [self showPage:PageSettings sender:sender]; }
- (void)showSection:(NSMenuItem *)sender { [self showPage:(Page)sender.tag sender:sender]; }

- (void)showPage:(Page)page sender:(id)sender {
    [self openMainWindow:sender];
    if (!self.unlocked) return;
    [self.windowController showPage:page];
}

- (void)focusSearch:(id)sender {
    [self openMainWindow:sender];
    [self.windowController focusSearch];
}

- (void)approveWorkspace:(id)sender {
    [self openMainWindow:sender];
    [self.windowController approveWorkspace:sender];
}

- (void)exportReport:(id)sender {
    [self openMainWindow:sender];
    [self.windowController exportReport:sender];
}

- (void)scanNow:(id)sender {
    [self.statusMenu close];
    [self.model scan];
}

// Quitting stops monitoring, so offer to close the window instead.
- (void)quit:(id)sender {
    [self.statusMenu close];
    if (!self.model.monitoring) { [NSApp terminate:nil]; return; }
    NSAlert *alert = [NSAlert new];
    alert.icon = DevCloudAppIconImage(64);
    alert.messageText = @"Quit DevCloud?";
    alert.informativeText = @"Background monitoring will stop until you open the app again. To keep monitoring, close the window instead.";
    [alert addButtonWithTitle:@"Close Window Only"];
    [alert addButtonWithTitle:@"Quit and Stop Monitoring"];
    [alert addButtonWithTitle:@"Cancel"].keyEquivalent = @"\e";
    [NSApp activateIgnoringOtherApps:YES];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) [self.windowController.window performClose:nil];
    else if (response == NSAlertSecondButtonReturn) [NSApp terminate:nil];
}

@end
