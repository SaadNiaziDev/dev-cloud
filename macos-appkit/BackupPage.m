#import "Pages.h"
#import "CloudAccount.h"
#import "CloudAccountPanel.h"
#import "RecoveryPlan.h"

@implementation BackupPage {
    PageScrollView *_scroll;
    CloudAccount *_account;
    CloudState _shownState;
}

- (instancetype)initWithHost:(id<PageHost>)host {
    self = [super initWithHost:host];
    if (self) {
        _scroll = [[PageScrollView alloc] initWithMaxWidth:720];
        Pin(_scroll, self, NSEdgeInsetsZero);
        _account = CloudAccount.shared;
        _shownState = _account.state;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged:) name:CloudAccountDidChangeNotification object:_account];
        [_account restore];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)accountChanged:(NSNotification *)notification {
    if (_shownState == CloudSigningIn && _account.state == CloudSignedIn) {
        [self.host toast:@"Signed in" detail:_account.email ?: @"This Mac can now back up its inventory."];
    }
    [self reload];
}

- (NSString *)signature {
    CloudAccount *account = _account;
    ScanModel *model = self.model;
    NSArray *ids = [account.backups valueForKey:@"identifier"];
    return [NSString stringWithFormat:@"%ld|%d|%@|%@|%@|%@|%d%d|%@|%lu|%@|%@|%d",
        (long)account.state, account.busy, account.errorMessage, account.userCode, account.email,
        [ids componentsJoinedByString:@","], model.scanning, model.report != nil, model.lastScanDate,
        (unsigned long)account.pendingBackups, account.uploadMessage, account.devices, account.automaticBackupsEnabled];
}

- (void)rebuild {
    CloudState state = _account.state;
    NSMutableArray *sections = [NSMutableArray arrayWithObject:Label(@"Cloud backup", 20, NSFontWeightSemibold, ThemeTextColor())];
    NSView *animated = nil;
    switch (state) {
        case CloudUnavailable: [sections addObject:[self unavailable]]; break;
        case CloudSignedOut: [sections addObject:[self signedOut]]; break;
        case CloudSigningIn: animated = [self signingIn]; [sections addObject:animated]; break;
        case CloudSignedIn: [sections addObjectsFromArray:[self signedIn]]; break;
    }
    if (_account.errorMessage) [sections insertObject:WrappingLabel(_account.errorMessage, 13, NSColor.systemOrangeColor) atIndex:1];
    [_scroll setSections:sections];
    // The code card is the one new thing on screen; everything else is a quiet state swap.
    if (animated && _shownState != CloudSigningIn) AnimateIn(@[animated], 8, 0);
    _shownState = state;
}

#pragma mark States

- (NSView *)card:(NSString *)symbol title:(NSString *)title body:(NSString *)body actions:(NSArray<NSView *> *)actions {
    NSStackView *text = VStack(8, @[Label(title, 14, NSFontWeightSemibold, ThemeTextColor())]);
    FillWidth(WrappingLabel(body, 13, ThemeSubColor()), text);
    NSStackView *top = HStack(14, @[SymbolView(symbol, 22, NSFontWeightRegular, NSColor.systemBlueColor), text]);
    top.alignment = NSLayoutAttributeTop;
    NSStackView *stack = VStack(14, @[]);
    FillWidth(top, stack);
    if (actions.count) FillWidth(HStack(8, [@[Spacer()] arrayByAddingObjectsFromArray:actions]), stack);
    return PaddedPanel(stack, 24);
}

- (NSView *)unavailable {
    return [self card:@"icloud.slash" title:@"Not available in this build"
                 body:@"This copy of DevCloud isn’t connected to a cloud service. Scans, history and snapshots keep working on this Mac without an account." actions:@[]];
}

- (NSView *)signedOut {
    NSButton *signIn = PushButton(_account.busy ? @"Starting…" : @"Sign In…", YES, self, @selector(signIn:));
    signIn.enabled = !_account.busy;
    NSStackView *stack = VStack(10, @[]);
    FillWidth([self card:@"icloud.and.arrow.up" title:@"Keep a copy of your setup off this Mac"
                     body:@"Backups hold tool names, versions and providers, plus your macOS version and chip. Paths, project names, settings and secrets never leave this Mac." actions:@[signIn]], stack);
    FillWidth([self footnote:@"Sign-in happens in your browser. Your password stays in the browser; the Mac app receives only a session."], stack);
    return stack;
}

- (NSView *)signingIn {
    NSTextField *code = Label(_account.userCode ?: @"", 30, NSFontWeightMedium, ThemeTextColor());
    code.font = [NSFont monospacedSystemFontOfSize:30 weight:NSFontWeightMedium];
    code.selectable = YES;
    code.accessibilityLabel = [@"Sign-in code " stringByAppendingString:[[_account.userCode ?: @"" componentsSeparatedByString:@"-"] componentsJoinedByString:@" "]];
    NSString *expiry = [NSDateFormatter localizedStringFromDate:_account.codeExpiry ?: NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
    NSStackView *stack = VStack(12, @[Label(@"Confirm this code in your browser", 14, NSFontWeightSemibold, ThemeTextColor()), code]);
    FillWidth(WrappingLabel(@"Your browser opened DevCloud’s sign-in page. Check the code matches this one, then approve. Never approve a code someone sent you.", 13, ThemeSubColor()), stack);
    FillWidth(HStack(8, @[Label([NSString stringWithFormat:@"Waiting for approval · Expires at %@", expiry], 12, NSFontWeightRegular, ThemeFaintColor()), Spacer(),
                         PushButton(@"Cancel", NO, self, @selector(cancelSignIn:)), PushButton(@"Open Browser Again", NO, self, @selector(openBrowser:))]), stack);
    return PaddedPanel(stack, 24);
}

- (NSArray<NSView *> *)signedIn {
    NSButton *signOut = PushButton(@"Sign Out", NO, self, @selector(signOut:));
    signOut.enabled = !_account.busy;
    NSStackView *who = VStack(2, @[Label(_account.email ?: @"Signed in", 13, NSFontWeightMedium, ThemeTextColor()),
                                   Label([NSString stringWithFormat:@"%@ · Connected", NSHost.currentHost.localizedName ?: @"This Mac"], 11.5, NSFontWeightRegular, ThemeFaintColor())]);
    NSStackView *account = HStack(12, @[SymbolView(@"person.crop.circle", 22, NSFontWeightRegular, ThemeSubColor()), who, Spacer(),
                                        [PillView pill:@"Connected" tone:ToneGreen dot:YES], signOut]);

    ScanModel *model = self.model;
    BOOL ready = model.report && !model.scanning && !model.errorMessage;
    NSButton *backUp = PushButton(_account.busy ? @"Backing Up…" : @"Back Up Now", YES, self, @selector(backUp:));
    backUp.enabled = ready && !_account.busy;
    NSString *source = !model.report ? @"Scan this Mac first, then back up the result." :
        (model.scanning ? @"Waiting for the current scan to finish." :
         [NSString stringWithFormat:@"Sends the scan from %@: %lu inventory records, names, versions and providers only.", RelativeDate(model.lastScanDate), (unsigned long)[model.report[@"resources"] count]]);
    NSStackView *now = HStack(16, @[WrappingLabel(source, 13, ThemeSubColor()), Spacer(), backUp]);

    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *backup in _account.backups) [rows addObject:[self backupRow:backup]];
    NSString *caption = _account.backups.count ? [NSString stringWithFormat:@"%lu saved · Newest first", (unsigned long)_account.backups.count] : @"None yet";
    NSStackView *list = VStack(10, @[]);
    FillWidth(SectionHeader(@"Backups", caption, nil), list);
    FillWidth(rows.count ? ListPanel(rows) : WrappingLabel(@"Backups from every Mac on this account appear here.", 13, ThemeFaintColor()), list);
    FillWidth([self footnote:@"Signing out clears pending uploads and removes this Mac from your account. Saved backups stay available on your other Macs."], list);
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[PaddedPanel(account, 24), PaddedPanel(now, 24)]];
    if (_account.pendingBackups || _account.uploadMessage) {
        NSButton *retry = PushButton(@"Retry Now", NO, self, @selector(retryQueue:));
        NSButton *clear = PushButton(@"Clear Queue", NO, self, @selector(clearQueue:));
        retry.enabled = clear.enabled = !_account.busy;
        NSString *message = _account.uploadMessage ?: @"Uploads resume automatically while DevCloud is open. Queued items are not backed up yet.";
        NSStackView *queue = VStack(10, @[Label([NSString stringWithFormat:@"%lu queued", (unsigned long)_account.pendingBackups], 13, NSFontWeightMedium, ThemeTextColor()),
            WrappingLabel(message, 13, ThemeSubColor()), HStack(8, @[retry, clear])]);
        [sections addObject:PaddedPanel(queue, 24)];
    }
    [sections addObject:list];
    __weak BackupPage *weakSelf = self;
    [sections addObject:[[CloudAccountPanel alloc] initWithAccount:_account notice:^(NSString *title, NSString *detail) {
        [weakSelf.host toast:title detail:detail];
    }]];
    return sections;
}

- (NSView *)backupRow:(NSDictionary *)backup {
    NSString *date = [NSDateFormatter localizedStringFromDate:backup[@"created"] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
    NSString *origin = [backup[@"this_mac"] boolValue] ? @"This Mac" : backup[@"device_name"];
    NSString *size = [NSByteCountFormatter stringFromByteCount:[backup[@"byte_count"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    NSButton *download = PushButton(@"Download…", NO, self, @selector(download:));
    download.identifier = backup[@"identifier"];
    download.accessibilityLabel = [@"Download backup from " stringByAppendingString:date];
    NSButton *review = PushButton(@"Review…", NO, self, @selector(review:));
    review.identifier = backup[@"identifier"];
    review.accessibilityLabel = [@"Review backup from " stringByAppendingString:date];
    NSButton *remove = PushButton(@"Delete…", NO, self, @selector(remove:));
    remove.identifier = backup[@"identifier"];
    remove.accessibilityLabel = [@"Delete backup from " stringByAppendingString:date];
    download.enabled = remove.enabled = !_account.busy;
    review.enabled = !_account.busy && self.model.report && !self.model.scanning && !self.model.errorMessage;
    NSStackView *row = HStack(12, @[VStack(4, @[Label(date, 13, NSFontWeightMedium, ThemeTextColor()),
                                                Label([NSString stringWithFormat:@"%@ · %@", origin, size], 12, NSFontWeightRegular, ThemeSubColor())]),
                                    Spacer(), review, download, remove]);
    row.edgeInsets = NSEdgeInsetsMake(16, 20, 16, 20);
    return row;
}

- (NSView *)footnote:(NSString *)text {
    NSStackView *inset = VStack(0, @[WrappingLabel(text, 11.5, ThemeFaintColor())]);
    inset.edgeInsets = NSEdgeInsetsMake(0, 4, 0, 4);
    return inset;
}

#pragma mark Actions

- (void)signIn:(id)sender { [_account beginSignIn]; }
- (void)cancelSignIn:(id)sender { [_account cancelSignIn]; }
- (void)openBrowser:(id)sender { [_account openVerificationPage]; }

- (void)signOut:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Sign out of DevCloud?";
    alert.informativeText = @"Sign Out removes this Mac’s cloud access. If you are offline, Sign Out Locally removes its saved session but does not revoke cloud access. Pending uploads on this Mac are cleared.";
    [alert addButtonWithTitle:@"Sign Out"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Sign Out Locally"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) [self->_account signOut];
        else if (response == NSAlertThirdButtonReturn) [self->_account signOutLocally];
    }];
}

- (void)backUp:(id)sender {
    __weak BackupPage *weakSelf = self;
    [_account backUpReport:self.model.report completion:^(NSUInteger tools, NSError *error) {
        if (error) { [weakSelf.host toast:@"Backup failed" detail:error.localizedDescription]; return; }
        [weakSelf.host toast:@"Backup queued" detail:[NSString stringWithFormat:@"%lu inventory records · Inventory only", (unsigned long)tools]];
    }];
}

- (void)retryQueue:(id)sender { [_account retryPendingBackups]; }
- (void)clearQueue:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Clear queued backups?";
    alert.informativeText = @"Removes only pending local uploads. Your saved cloud backups stay.";
    [alert addButtonWithTitle:@"Clear Queue"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) [self->_account discardPendingBackups];
    }];
}

- (void)download:(NSButton *)sender {
    NSString *identifier = sender.identifier;
    NSSavePanel *panel = NSSavePanel.savePanel;
    panel.nameFieldStringValue = [NSString stringWithFormat:@"DevCloud-Backup-%@.json", [identifier substringToIndex:MIN((NSUInteger)8, identifier.length)]];
    panel.message = @"Saves the backup for inspection. Nothing is installed or applied.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        NSURL *url = panel.URL;
        [self->_account downloadBackup:identifier completion:^(NSData *data, NSError *error) {
            if (data && ![data writeToURL:url options:NSDataWritingAtomic error:&error]) data = nil;
            if (data) [self.host toast:@"Backup downloaded" detail:[url.lastPathComponent stringByAppendingString:@" · Checksum verified"]];
            else [self.host toast:@"Download failed" detail:error.localizedDescription];
        }];
    }];
}

- (void)review:(NSButton *)sender {
    NSDictionary *scan = self.model.report;
    [_account downloadBackup:sender.identifier completion:^(NSData *data, NSError *error) {
        NSArray *plan = data ? RecoveryPlan(data, scan, &error) : nil;
        if (!plan) { [self.host toast:@"Couldn’t review backup" detail:error.localizedDescription]; return; }
        NSString *text = RecoveryPlanDescription(plan);
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Review backup";
        alert.informativeText = @"Nothing will be installed or changed.";
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 520, 300)];
        scroll.hasVerticalScroller = YES;
        NSTextView *content = [[NSTextView alloc] initWithFrame:scroll.bounds];
        content.editable = NO;
        content.string = text;
        content.font = [NSFont systemFontOfSize:12];
        content.verticallyResizable = YES;
        content.textContainer.containerSize = NSMakeSize(scroll.contentSize.width, CGFLOAT_MAX);
        content.textContainer.widthTracksTextView = YES;
        scroll.documentView = content;
        alert.accessoryView = scroll;
        [alert addButtonWithTitle:@"Done"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }];
}

- (void)remove:(NSButton *)sender {
    NSString *identifier = sender.identifier;
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Delete this backup?";
    alert.informativeText = @"It’s removed from your account for every Mac. This can’t be undone.";
    NSButton *confirm = [alert addButtonWithTitle:@"Delete"];
    confirm.hasDestructiveAction = YES;
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [self->_account deleteBackup:identifier completion:^(NSError *error) {
            if (error) [self.host toast:@"Couldn’t delete backup" detail:error.localizedDescription];
            else [self.host toast:@"Backup deleted" detail:@"Removed from your account"];
        }];
    }];
}

@end
