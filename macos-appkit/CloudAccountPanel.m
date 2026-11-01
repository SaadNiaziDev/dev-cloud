#import "CloudAccountPanel.h"
#import "CloudAccount.h"
#import "Theme.h"

@interface CloudAccountPanel () <NSTextFieldDelegate>
@end

@implementation CloudAccountPanel {
    CloudAccount *_account;
    void (^_notice)(NSString *, NSString *);
    NSTextField *_confirmation;
    NSButton *_deleteButton;
    NSString *_confirmedDevice;
    NSString *_confirmedEmail;
}

- (instancetype)initWithAccount:(CloudAccount *)account notice:(void (^)(NSString *, NSString *))notice {
    if ((self = [super init])) {
        _account = account;
        _notice = [notice copy];
        self.orientation = NSUserInterfaceLayoutOrientationVertical;
        self.alignment = NSLayoutAttributeLeading;
        self.spacing = 10;
        NSButton *refresh = PushButton(@"Refresh", NO, self, @selector(refresh:));
        refresh.enabled = !account.busy;
        FillWidth(SectionHeader(@"Connected Macs", @"Remove access for a lost or unused Mac", refresh), self);
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *device in account.devices) {
            NSView *action;
            if ([device[@"this_mac"] boolValue]) action = Label(@"This Mac", 12, NSFontWeightMedium, ThemeSubColor());
            else {
                NSButton *remove = PushButton(@"Remove Access…", NO, self, @selector(removeDevice:));
                remove.identifier = device[@"identifier"];
                remove.accessibilityLabel = [@"Remove access for " stringByAppendingString:device[@"name"]];
                remove.enabled = !account.busy;
                action = remove;
            }
            NSStackView *row = HStack(12, @[Label(device[@"name"], 13, NSFontWeightMedium, ThemeTextColor()), Spacer(), action]);
            row.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
            [rows addObject:row];
        }
        FillWidth(rows.count ? ListPanel(rows) : WrappingLabel(@"Refresh to load the Macs on this account.", 13, ThemeSubColor()), self);
        FillWidth(WrappingLabel(@"Removing access ends that Mac’s session and pending uploads. Saved backups remain available.", 12, ThemeSubColor()), self);
        NSButton *delete = PushButton(@"Delete Cloud Account…", NO, self, @selector(deleteAccount:));
        delete.enabled = !account.busy;
        FillWidth(HStack(12, @[WrappingLabel(@"Account deletion removes every Mac and cloud backup on this account.", 12, ThemeSubColor()), Spacer(), delete]), self);
    }
    return self;
}

- (void)refresh:(id)sender { [_account refreshBackups]; }

- (void)removeDevice:(NSButton *)sender {
    NSString *identifier = sender.identifier;
    NSString *name = nil;
    for (NSDictionary *device in _account.devices) if ([device[@"identifier"] isEqual:identifier]) name = device[@"name"];
    if (!name) return;
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Remove access for %@?", name];
    alert.informativeText = @"This ends its enrolled session and pending uploads. Saved cloud backups stay available. That Mac must sign in again to back up.";
    [alert addButtonWithTitle:@"Remove Access"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [self->_account revokeDevice:identifier completion:^(NSError *error) {
            self->_notice(error ? @"Couldn’t remove access" : @"Access removed", error.localizedDescription ?: @"Saved backups stay available.");
        }];
    }];
}

- (void)deleteAccount:(id)sender {
    _confirmedDevice = _account.deviceIdentifier;
    _confirmedEmail = _account.email;
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Delete your DevCloud cloud account?";
    alert.informativeText = [NSString stringWithFormat:@"Permanently removes %@, every connected Mac and all saved cloud backups. Backup cleanup may finish later. Local scans and exported files stay. Type delete my account to confirm.", _account.email ?: @"this cloud account"];
    _confirmation = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 340, 28)];
    _confirmation.placeholderString = @"delete my account";
    _confirmation.accessibilityLabel = @"Type delete my account to confirm";
    _confirmation.delegate = self;
    alert.accessoryView = _confirmation;
    [alert addButtonWithTitle:@"Delete Cloud Account"];
    [alert addButtonWithTitle:@"Cancel"];
    _deleteButton = alert.buttons.firstObject;
    _deleteButton.enabled = NO;
    _deleteButton.keyEquivalent = @"";
    alert.buttons.lastObject.keyEquivalent = @"\r";
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        NSString *confirmation = self->_confirmation.stringValue;
        self->_confirmation = nil;
        self->_deleteButton = nil;
        if (response != NSAlertFirstButtonReturn) return;
        if (![self sameAccount]) { self->_notice(@"Account changed", @"Review the signed-in account before deleting it."); return; }
        [self->_account deleteAccountWithConfirmation:confirmation completion:^(NSError *error) {
            self->_notice(error ? @"Couldn’t delete account" : @"Account deletion requested",
                error.localizedDescription ?: @"Access ended. Cloud backup cleanup is queued.");
        }];
    }];
}

- (BOOL)sameAccount {
    return _account.state == CloudSignedIn && [_confirmedDevice isEqual:_account.deviceIdentifier] &&
        ((_confirmedEmail == nil && _account.email == nil) || [_confirmedEmail isEqual:_account.email]);
}

- (void)controlTextDidChange:(NSNotification *)notification {
    _deleteButton.enabled = [_confirmation.stringValue isEqual:@"delete my account"] && [self sameAccount] && !_account.busy;
}
@end
