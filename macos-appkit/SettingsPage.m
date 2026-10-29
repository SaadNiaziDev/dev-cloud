#import "Pages.h"
#import "BrandMark.h"
#import <UserNotifications/UserNotifications.h>

@implementation SettingsPage {
    PageScrollView *_scroll;
    NSString *_permission;
}

- (instancetype)initWithHost:(id<PageHost>)host {
    self = [super initWithHost:host];
    if (self) {
        _scroll = [[PageScrollView alloc] initWithMaxWidth:640];
        Pin(_scroll, self, NSEdgeInsetsZero);
        _permission = @"Checking";
    }
    return self;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) [self refreshPermission];
}

- (void)refreshPermission {
    // The notification center requires an app bundle; unbundled test builds have none.
    if (!NSBundle.mainBundle.bundleIdentifier) return;
    __weak SettingsPage *weakSelf = self;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        NSString *status = @{@(UNAuthorizationStatusAuthorized): @"Allowed", @(UNAuthorizationStatusProvisional): @"Allowed", @(UNAuthorizationStatusDenied): @"Denied"}[@(settings.authorizationStatus)] ?: @"Not requested";
        dispatch_async(dispatch_get_main_queue(), ^{
            SettingsPage *page = weakSelf;
            if (!page || [page->_permission isEqual:status]) return;
            page->_permission = status;
            [page reload];
        });
    }];
}

- (NSString *)signature {
    ScanModel *model = self.model;
    return [NSString stringWithFormat:@"%d%d%d%d|%@|%@", model.monitoring, model.launchAtLogin, model.notificationsEnabled, model.includePaths, model.settingsMessage, _permission];
}

- (void)rebuild {
    ScanModel *model = self.model;
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"development build";
    NSImageView *icon = [NSImageView imageViewWithImage:DevCloudAppIconImage(44)];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.accessibilityElement = NO;
    NSStackView *about = HStack(16, @[icon, VStack(2, @[Label(@"DevCloud", 14, NSFontWeightSemibold, ThemeTextColor()),
                                                         Label([NSString stringWithFormat:@"Version %@ · Local, read-only release", version], 11.5, NSFontWeightRegular, ThemeFaintColor())]),
                                      Spacer(), [PillView pill:@"No account" tone:ToneNeutral dot:NO]]);

    NSString *footer = model.settingsMessage ?: @"Closing the window keeps monitoring running in the menu bar. Quitting the app stops it.";
    Tone permissionTone = [_permission isEqual:@"Allowed"] ? ToneGreen : ([_permission isEqual:@"Denied"] ? ToneRed : ToneNeutral);
    NSButton *openSettings = PushButton(@"Open…", NO, self, @selector(openNotificationSettings:));
    openSettings.accessibilityLabel = @"Open notification settings";
    [_scroll setSections:@[
        PaddedPanel(about, 16),
        [self group:@"General" footer:nil rows:@[
            [self row:@"Launch at login" hint:@"Opens quietly in the menu bar" control:[self toggle:@"login" on:model.launchAtLogin]],
        ]],
        [self group:@"Monitoring" footer:footer rows:@[
            [self row:@"Background monitoring" hint:@"Watches runtime, package and editor folders; rescans every 5 minutes and after wake" control:[self toggle:@"monitoring" on:model.monitoring]],
        ]],
        [self group:@"Notifications" footer:nil rows:@[
            [self row:@"Notification permission" hint:@"Managed in System Settings" control:HStack(12, @[[PillView pill:_permission tone:permissionTone dot:permissionTone != ToneNeutral], openSettings])],
            [self row:@"Tool changes" hint:@"Sent after a background scan finds changes" control:[self toggle:@"notifications" on:model.notificationsEnabled]],
        ]],
        [self group:@"Privacy & Export" footer:@"Secrets, private keys and .env files are never read. Exports never leave this Mac unless you move them." rows:@[
            [self row:@"Include installation locations" hint:@"Adds full paths to the inventory and exports" control:[self toggle:@"paths" on:model.includePaths]],
            [self row:@"Export inventory" hint:@"Schema v1 JSON" control:PushButton(@"Export JSON…", NO, self.host, @selector(exportReport:))],
        ]],
    ]];
}

- (NSSwitch *)toggle:(NSString *)key on:(BOOL)on {
    NSSwitch *toggle = Switch(on, NSControlSizeRegular, self, @selector(toggleChanged:));
    toggle.identifier = key;
    return toggle;
}

- (NSView *)row:(NSString *)label hint:(NSString *)hint control:(NSView *)control {
    NSStackView *text = VStack(2, @[Label(label, 13, NSFontWeightRegular, ThemeTextColor())]);
    if (hint) [text addArrangedSubview:WrappingLabel(hint, 11.5, ThemeFaintColor())];
    if ([control isKindOfClass:NSSwitch.class]) control.accessibilityLabel = label;
    NSStackView *line = HStack(16, @[text, Spacer(), control]);
    NSView *cell = [NSView new];
    cell.translatesAutoresizingMaskIntoConstraints = NO;
    Pin(line, cell, NSEdgeInsetsMake(10, 16, 10, 16));
    [cell.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return cell;
}

- (NSView *)group:(NSString *)title footer:(NSString *)footer rows:(NSArray *)rows {
    NSStackView *stack = VStack(8, @[]);
    NSTextField *heading = Label(title, 13, NSFontWeightSemibold, ThemeTextColor());
    [stack addArrangedSubview:heading];
    [heading.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:4].active = YES;
    FillWidth(ListPanel(rows), stack);
    if (footer) {
        NSTextField *note = WrappingLabel(footer, 11.5, ThemeFaintColor());
        NSStackView *inset = VStack(0, @[note]);
        inset.edgeInsets = NSEdgeInsetsMake(0, 4, 0, 4);
        FillWidth(inset, stack);
    }
    return stack;
}

- (void)toggleChanged:(NSSwitch *)sender {
    BOOL on = sender.state == NSControlStateValueOn;
    NSString *key = sender.identifier;
    if ([key isEqual:@"monitoring"]) {
        [self.model setMonitoringEnabled:on];
        [self.host toast:on ? @"Monitoring resumed" : @"Monitoring paused" detail:on ? @"Watching tool folders and approved workspaces." : @"No changes will be detected until resumed."];
    } else if ([key isEqual:@"login"]) {
        [self.model setLaunchAtLoginEnabled:on];
    } else if ([key isEqual:@"notifications"]) {
        [self.model setNotificationsEnabled:on];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self refreshPermission]; });
    } else if ([key isEqual:@"paths"]) {
        self.model.includePaths = on;
    }
}

- (void)openNotificationSettings:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Notifications-Settings.extension"]];
}

@end
