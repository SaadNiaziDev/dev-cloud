#import "Pages.h"
#import "CloudAccount.h"
#import "SetupFile.h"
#import "SetupInstaller.h"

static NSString *const KindTitles[] = {@"Command-line tools", @"Apps", @"VS Code extensions"};
static NSString *const InstallKinds[] = {@"brew", @"cask", @"vscode"};

@implementation SetupPage {
    PageScrollView *_scroll;
    CloudAccount *_account;
    NSString *_backupIdentifier;
    NSDictionary *_backup;
    NSArray<NSDictionary *> *_items;
    NSMutableSet<NSString *> *_skipped;
    NSMutableDictionary<NSString *, NSButton *> *_checkboxes;
    NSMutableDictionary<NSString *, NSTextField *> *_statuses;
    NSTextField *_summary;
    NSTextField *_progress;
    NSButton *_install;
    SetupInstaller *_installer;
    NSString *_error;
    BOOL _loading;
    NSUInteger _version;
}

- (instancetype)initWithHost:(id<PageHost>)host {
    if ((self = [super initWithHost:host])) {
        _scroll = [[PageScrollView alloc] initWithMaxWidth:760];
        Pin(_scroll, self, NSEdgeInsetsZero);
        _account = CloudAccount.shared;
        _skipped = [NSMutableSet set];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged:) name:CloudAccountDidChangeNotification object:_account];
        [self accountChanged:nil];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

// Opens the newest backup from another Mac, or this Mac's newest, once backups arrive.
- (void)accountChanged:(NSNotification *)notification {
    NSArray *backups = _account.backups;
    if (_backupIdentifier && ![[backups valueForKey:@"identifier"] containsObject:_backupIdentifier]) {
        _backupIdentifier = nil;
        _backup = nil;
    }
    if (!_backupIdentifier && backups.count) {
        NSDictionary *chosen = backups.firstObject;
        for (NSDictionary *backup in backups) if (![backup[@"this_mac"] boolValue]) { chosen = backup; break; }
        [self load:chosen[@"identifier"]];
    }
    [self reload];
}

- (void)load:(NSString *)identifier {
    _backupIdentifier = identifier;
    _backup = nil;
    _error = nil;
    _loading = YES;
    [_skipped removeAllObjects];
    _version++;
    __weak SetupPage *weakSelf = self;
    [_account downloadBackup:identifier completion:^(NSData *data, NSError *error) {
        SetupPage *page = weakSelf;
        if (!page || ![identifier isEqual:page->_backupIdentifier]) return;
        id inventory = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        page->_loading = NO;
        page->_backup = [inventory isKindOfClass:NSDictionary.class] ? inventory : nil;
        page->_error = page->_backup ? nil : (error.localizedDescription ?: @"That backup couldn’t be read.");
        page->_version++;
        [page reload];
    }];
}

- (NSString *)signature {
    ScanModel *model = self.model;
    return [NSString stringWithFormat:@"%lu|%ld|%@|%d|%d|%@", (unsigned long)_version, (long)_account.state,
        [[_account.backups valueForKey:@"identifier"] componentsJoinedByString:@","], model.scanning, model.report != nil, model.lastScanDate];
}

#pragma mark Layout

- (void)rebuild {
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:HStack(12, @[Label(@"Set up this Mac", 20, NSFontWeightSemibold, ThemeTextColor()), Spacer(), [self backupPicker]])];
    [sections addObject:WrappingLabel(@"Install the tools, apps and VS Code extensions from a backup. DevCloud compares it with this Mac and installs only what you select, using Homebrew.", 13, ThemeSubColor())];
    if (_error) [sections addObject:WrappingLabel(_error, 13, NSColor.systemOrangeColor)];
    _checkboxes = [NSMutableDictionary dictionary];
    _statuses = [NSMutableDictionary dictionary];
    _summary = nil;
    _progress = nil;
    _install = nil;

    if (!_account.backups.count) {
        [sections addObject:[self card:@"No backups yet"
                                  body:@"On your old Mac, open DevCloud and choose Back Up Now on the Backup page. The backup appears here."
                               actions:@[PushButton(@"Refresh", NO, self, @selector(refresh:)), PushButton(@"Back Up This Mac", YES, self, @selector(showBackup:))]]];
        [_scroll setSections:sections];
        return;
    }
    if (_loading || !_backup) {
        if (_loading) [sections addObject:[self card:@"Loading backup…" body:@"Downloading and checking it against its recorded checksum." actions:@[]]];
        [_scroll setSections:sections];
        return;
    }

    _items = SetupItems(_backup, self.model.report, nil) ?: @[];
    if (!SetupInstaller.homebrew) {
        [sections addObject:[self card:@"Install Homebrew first"
                                  body:@"DevCloud installs your tools with Homebrew. Install it from brew.sh, then choose Check Again."
                               actions:@[PushButton(@"Open brew.sh", NO, self, @selector(openHomebrew:)), PushButton(@"Check Again", YES, self, @selector(checkAgain:))]]];
    }
    [sections addObject:[self summaryPanel]];
    for (NSUInteger index = 0; index < 3; index++) {
        NSView *section = [self sectionFor:InstallKinds[index] title:KindTitles[index]];
        if (section) [sections addObject:section];
    }
    NSView *manual = [self manualSteps];
    if (manual) [sections addObject:manual];
    [sections addObject:WrappingLabel(@"Homebrew installs its current versions, which may be newer than your backup. Settings, dotfiles and secrets aren’t part of a backup.", 12, ThemeFaintColor())];
    [_scroll setSections:sections];
    [self updateSummary];
}

- (NSView *)backupPicker {
    NSArray *backups = _account.backups;
    if (!backups.count) return Spacer();
    NSPopUpButton *picker = [NSPopUpButton new];
    picker.target = self;
    picker.action = @selector(chooseBackup:);
    picker.accessibilityLabel = @"Backup to set up from";
    for (NSDictionary *backup in backups) {
        NSString *date = [NSDateFormatter localizedStringFromDate:backup[@"created"] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
        NSString *device = [backup[@"this_mac"] boolValue] ? @"This Mac" : ([backup[@"device_name"] isKindOfClass:NSString.class] ? backup[@"device_name"] : @"Another Mac");
        [picker addItemWithTitle:[NSString stringWithFormat:@"%@ · %@", device, date]];
        picker.lastItem.representedObject = backup[@"identifier"];
        if ([backup[@"identifier"] isEqual:_backupIdentifier]) [picker selectItem:picker.lastItem];
    }
    picker.enabled = !_installer.running;
    return picker;
}

- (NSView *)card:(NSString *)title body:(NSString *)body actions:(NSArray<NSView *> *)actions {
    NSStackView *stack = VStack(10, @[Label(title, 14, NSFontWeightSemibold, ThemeTextColor())]);
    FillWidth(WrappingLabel(body, 13, ThemeSubColor()), stack);
    if (actions.count) FillWidth(HStack(8, [@[Spacer()] arrayByAddingObjectsFromArray:actions]), stack);
    return PaddedPanel(stack, 20);
}

- (NSView *)summaryPanel {
    _summary = Label(@"", 15, NSFontWeightSemibold, ThemeTextColor());
    _progress = WrappingLabel(@"", 12, ThemeSubColor());
    _install = PushButton(@"Install…", YES, self, @selector(install:));
    NSButton *save = PushButton(@"Save Setup File…", NO, self, @selector(saveFile:));
    NSMutableArray *actions = [NSMutableArray arrayWithObjects:save, nil];
    if (_installer.running) {
        NSProgressIndicator *spinner = [NSProgressIndicator new];
        spinner.style = NSProgressIndicatorStyleSpinning;
        spinner.controlSize = NSControlSizeSmall;
        [spinner startAnimation:nil];
        [actions insertObject:spinner atIndex:0];
        [actions addObject:PushButton(@"Stop", NO, self, @selector(stop:))];
    } else {
        if (_installer.finished) [actions insertObject:PushButton(@"Show Log", NO, self, @selector(showLog:)) atIndex:0];
        [actions addObject:_install];
    }
    NSStackView *row = HStack(10, [@[_summary, Spacer()] arrayByAddingObjectsFromArray:actions]);
    NSStackView *stack = VStack(8, @[]);
    FillWidth(row, stack);
    FillWidth(_progress, stack);
    return PaddedPanel(stack, 20);
}

- (NSArray<NSDictionary *> *)itemsOfKind:(NSString *)kind {
    return [_items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind == %@", kind]];
}

- (NSView *)sectionFor:(NSString *)kind title:(NSString *)title {
    NSArray *items = [self itemsOfKind:kind];
    if (!items.count) return nil;
    NSUInteger present = [[items valueForKey:@"installed"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF == YES"]].count;
    NSButton *toggle = LinkButton(@"Select All", self, @selector(toggleSection:));
    toggle.identifier = kind;
    toggle.enabled = !_installer.running;
    toggle.accessibilityLabel = [@"Select or clear all " stringByAppendingString:title];
    NSString *caption = [NSString stringWithFormat:@"%lu in backup · %lu already on this Mac", (unsigned long)items.count, (unsigned long)present];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSString *line = item[@"line"];
        BOOL installed = [item[@"installed"] boolValue];
        NSButton *box = [NSButton checkboxWithTitle:item[@"name"] target:self action:@selector(toggleItem:)];
        box.identifier = line;
        box.font = ThemeFont(13, NSFontWeightRegular);
        box.state = !installed && ![_skipped containsObject:line] ? NSControlStateValueOn : NSControlStateValueOff;
        box.enabled = !installed && !_installer.running && !(_installer && [_installer stateFor:item[@"name"]] == SetupItemDone);
        NSTextField *status = Label(@"", 12, NSFontWeightMedium, ThemeFaintColor());
        if (!installed) _checkboxes[line] = box;
        _statuses[line] = status;
        [self paint:status item:item];
        NSStackView *row = HStack(12, @[box, Spacer(), status]);
        row.edgeInsets = NSEdgeInsetsMake(8, 14, 8, 14);
        [rows addObject:row];
    }
    return SectionWithHeader(SectionHeader(title, caption, toggle), ListPanel(rows));
}

- (NSView *)manualSteps {
    NSArray *steps = [[self itemsOfKind:@"step"] arrayByAddingObjectsFromArray:[self itemsOfKind:@"cursor"]];
    NSArray *missing = [steps filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"installed == NO"]];
    if (!missing.count) return nil;
    NSMutableArray *commands = [NSMutableArray array];
    for (NSDictionary *item in missing) [commands addObject:[item[@"line"] substringFromIndex:2]];
    NSStackView *body = VStack(6, @[]);
    FillWidth(MonoLabel([commands componentsJoinedByString:@"\n"], 12, ThemeTextColor()), body);
    NSButton *copy = PushButton(@"Copy Commands", NO, self, @selector(copySteps:));
    copy.identifier = [commands componentsJoinedByString:@"\n"];
    return SectionWithHeader(SectionHeader(@"Finish in Terminal", @"Runtime versions and Cursor extensions, after the installs above", copy), PaddedPanel(body, 14));
}

- (void)paint:(NSTextField *)status item:(NSDictionary *)item {
    NSString *text = @"";
    NSColor *color = ThemeFaintColor();
    if ([item[@"installed"] boolValue]) text = @"On this Mac";
    else if (_installer && [_installer stateFor:item[@"name"]] != SetupItemWaiting) {
        switch ([_installer stateFor:item[@"name"]]) {
            case SetupItemInstalling: text = @"Installing…"; color = NSColor.systemBlueColor; break;
            case SetupItemDone: text = @"Installed"; color = NSColor.systemGreenColor; break;
            case SetupItemFailed: text = @"Not installed"; color = NSColor.systemRedColor; break;
            case SetupItemWaiting: break;
        }
    }
    status.stringValue = text;
    status.textColor = color;
}

- (NSArray<NSDictionary *> *)selectedItems {
    NSMutableArray *selected = [NSMutableArray array];
    for (NSDictionary *item in _items) {
        BOOL done = _installer && [_installer stateFor:item[@"name"]] == SetupItemDone;
        if (SetupItemInstallable(item) && ![item[@"installed"] boolValue] && !done && ![_skipped containsObject:item[@"line"]]) [selected addObject:item];
    }
    return selected;
}

- (void)updateSummary {
    NSUInteger count = self.selectedItems.count;
    NSUInteger present = 0, installable = 0;
    for (NSDictionary *item in _items) if (SetupItemInstallable(item)) { installable++; if ([item[@"installed"] boolValue]) present++; }
    if (_installer.running) {
        _summary.stringValue = [NSString stringWithFormat:@"Installing %lu items…", (unsigned long)_installer.total];
        _progress.stringValue = _installer.lastLine ?: @"Starting Homebrew…";
    } else if (_installer.finished) {
        NSUInteger failed = 0;
        for (NSDictionary *item in _items) if (SetupItemInstallable(item) && [_installer stateFor:item[@"name"]] == SetupItemFailed) failed++;
        NSUInteger installed = _installer.total - failed;
        _summary.stringValue = failed ? [NSString stringWithFormat:@"Installed %lu · %lu couldn’t be installed", (unsigned long)installed, (unsigned long)failed]
                                      : [NSString stringWithFormat:@"Installed %lu items", (unsigned long)installed];
        _progress.stringValue = failed ? @"Show Log has Homebrew’s reason. Apps that need your password can be installed from Terminal with `brew install --cask <name>`."
                                       : @"Your tools are ready. Finish the steps below in Terminal, if any.";
    } else {
        _summary.stringValue = count ? [NSString stringWithFormat:@"%lu to install", (unsigned long)count] : @"Nothing selected";
        _progress.stringValue = [NSString stringWithFormat:@"%lu of %lu items from this backup are already on this Mac.", (unsigned long)present, (unsigned long)installable];
    }
    _install.title = count ? [NSString stringWithFormat:@"Install %lu…", (unsigned long)count] : @"Install…";
    _install.enabled = count > 0 && SetupInstaller.homebrew && !self.model.scanning;
}

#pragma mark Actions

- (void)chooseBackup:(NSPopUpButton *)sender {
    NSString *identifier = sender.selectedItem.representedObject;
    if (identifier && ![identifier isEqual:_backupIdentifier]) { [self load:identifier]; [self reload]; }
}

- (void)refresh:(id)sender { [_account refreshBackups]; }
- (void)showBackup:(id)sender { [self.host showPage:PageBackup]; }
- (void)openHomebrew:(id)sender { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://brew.sh"]]; }
- (void)checkAgain:(id)sender { _version++; [self reload]; }
- (void)saveFile:(id)sender { SaveSetupFile(self.window, self.host, _backup); }

- (void)toggleItem:(NSButton *)sender {
    if (sender.state == NSControlStateValueOn) [_skipped removeObject:sender.identifier];
    else [_skipped addObject:sender.identifier];
    [self updateSummary];
}

- (void)toggleSection:(NSButton *)sender {
    NSArray *lines = [[self itemsOfKind:sender.identifier] valueForKey:@"line"];
    BOOL anySkipped = NO;
    for (NSString *line in lines) if (_checkboxes[line] && [_skipped containsObject:line]) anySkipped = YES;
    for (NSString *line in lines) {
        NSButton *box = _checkboxes[line];
        if (!box) continue;
        if (anySkipped) [_skipped removeObject:line]; else [_skipped addObject:line];
        box.state = anySkipped ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self updateSummary];
}

- (void)copySteps:(NSButton *)sender {
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:sender.identifier forType:NSPasteboardTypeString];
    [self.host toast:@"Commands copied" detail:@"Paste them into Terminal after the installs finish"];
}

- (void)install:(id)sender {
    NSArray *selected = self.selectedItems;
    if (!selected.count || _installer.running) return;
    NSArray *names = [selected valueForKey:@"name"];
    NSString *list = [[names subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)6, names.count))] componentsJoinedByString:@", "];
    if (names.count > 6) list = [list stringByAppendingFormat:@" and %lu more", (unsigned long)(names.count - 6)];
    NSAlert *alert = [NSAlert new];
    alert.messageText = [NSString stringWithFormat:@"Install %lu items with Homebrew?", (unsigned long)selected.count];
    alert.informativeText = [NSString stringWithFormat:@"%@.\n\nHomebrew downloads and installs their current versions. This can take a while; keep DevCloud open. Apps that need your password may need installing from Terminal afterwards.", list];
    [alert addButtonWithTitle:@"Install"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) [self startInstall:selected];
    }];
}

- (void)startInstall:(NSArray *)selected {
    SetupInstaller *installer = [[SetupInstaller alloc] initWithItems:selected];
    __weak SetupPage *weakSelf = self;
    __weak SetupInstaller *weakInstaller = installer;
    installer.onChange = ^{ [weakSelf installerChanged:weakInstaller]; };
    NSError *error = nil;
    _installer = installer;
    if (![installer start:&error]) {
        _installer = nil;
        [self.host toast:@"Couldn’t start the install" detail:error.localizedDescription];
        return;
    }
    _version++;
    [self reload];
}

// Output arrives line by line; only labels change until the run ends.
- (void)installerChanged:(SetupInstaller *)installer {
    if (installer != _installer) return;
    if (installer.finished) {
        [self.host toast:installer.succeeded ? @"Setup finished" : @"Setup finished with problems"
                  detail:installer.succeeded ? @"Scanning this Mac again" : @"Some items weren’t installed"];
        _version++;
        [self reload];
        [self.model scan];
        return;
    }
    for (NSDictionary *item in _items) if (_statuses[item[@"line"]]) [self paint:_statuses[item[@"line"]] item:item];
    [self updateSummary];
}

- (void)stop:(id)sender { [_installer cancel]; }

- (void)showLog:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Homebrew output";
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 560, 320)];
    scroll.hasVerticalScroller = YES;
    NSTextView *text = [[NSTextView alloc] initWithFrame:scroll.bounds];
    text.editable = NO;
    text.string = _installer.log.length ? _installer.log : @"No output.";
    text.font = ThemeMono(11);
    text.verticallyResizable = YES;
    text.textContainer.containerSize = NSMakeSize(scroll.contentSize.width, CGFLOAT_MAX);
    text.textContainer.widthTracksTextView = YES;
    scroll.documentView = text;
    alert.accessoryView = scroll;
    [alert addButtonWithTitle:@"Done"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
    [text scrollToEndOfDocument:nil];
}
@end
