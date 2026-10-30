#import "Pages.h"
#import "SnapshotStore.h"

@implementation SnapshotsPage {
    PageScrollView *_scroll;
    SnapshotStore *_store;
    NSArray<NSDictionary *> *_snapshots;
    NSString *_selected;
    NSString *_baseline;
    NSDictionary *_comparison;
    NSString *_error;
    BOOL _loaded;
    BOOL _busy;
}

- (instancetype)initWithHost:(id<PageHost>)host {
    self = [super initWithHost:host];
    if (self) {
        _scroll = [[PageScrollView alloc] initWithMaxWidth:760];
        Pin(_scroll, self, NSEdgeInsetsZero);
        NSURL *directory = [[host.model.historyDirectory URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"Snapshots"];
        _store = [[SnapshotStore alloc] initWithDirectory:directory];
        _snapshots = @[];
    }
    return self;
}

- (void)reload {
    if (!_loaded && !_busy) [self loadSnapshots:nil];
    [super reload];
}

- (void)loadSnapshots:(id)sender { [self updateWithReport:nil]; }

- (void)capture:(id)sender {
    if (_busy || self.model.scanning || !self.model.report || self.model.errorMessage || self.model.showingSavedScan) return;
    [self updateWithReport:self.model.report];
}

- (void)updateWithReport:(NSDictionary *)report {
    if (_busy) return;
    _comparison = nil;
    _busy = YES;
    [self rebuild];
    SnapshotStore *store = _store;
    __weak SnapshotsPage *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL saved = report && [store captureReport:report error:&error];
        NSArray *snapshots = error ? nil : [store snapshotsWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            SnapshotsPage *page = weakSelf;
            if (!page) return;
            page->_busy = NO;
            page->_loaded = YES;
            page->_error = error.localizedDescription;
            if (snapshots) page->_snapshots = snapshots;
            if (saved || !page->_selected) page->_selected = page->_snapshots.firstObject[@"identifier"];
            [page reload];
            if (saved) [page.host toast:@"Snapshot saved" detail:@"Inventory only · Stored on this Mac"];
        });
    });
}

- (void)rebuild {
    NSButton *capture = PushButton(_busy ? @"Please wait…" : @"Save Snapshot", YES, self, @selector(capture:));
    capture.enabled = !_busy && !self.model.scanning && self.model.report && !self.model.errorMessage && !self.model.showingSavedScan;
    NSButton *refresh = PushButton(@"Refresh", NO, self, @selector(loadSnapshots:));
    refresh.enabled = !_busy;
    NSButton *check = PushButton(@"Check File…", NO, self, @selector(checkFile:));
    check.enabled = !_busy;
    NSMutableArray *sections = [NSMutableArray arrayWithArray:@[
        HStack(8, @[Label(@"Inventory snapshots", 17, NSFontWeightSemibold, ThemeTextColor()), Spacer(), check, refresh, capture]),
        WrappingLabel(@"Save the current scan’s tool names, versions and providers, including installation paths if enabled. Config files and workspace contents are excluded. Snapshots stay on this Mac until exported and are kept separately from automatic scan history.", 13, ThemeSubColor())
    ]];
    if (_error) [sections addObject:WrappingLabel(_error, 13, NSColor.systemOrangeColor)];
    if (self.model.showingSavedScan) [sections addObject:WrappingLabel(@"Scan again before saving a snapshot.", 13, ThemeSubColor())];
    if (!_snapshots.count) [sections addObject:WrappingLabel(_busy ? @"Loading snapshots…" : @"No snapshots saved yet.", 13, ThemeFaintColor())];
    NSMutableArray *rows = [NSMutableArray array];
    [_snapshots enumerateObjectsUsingBlock:^(NSDictionary *snapshot, NSUInteger index, BOOL *stop) {
        [rows addObject:[self snapshotRow:snapshot index:index]];
    }];
    if (rows.count) [sections addObject:ListPanel(rows)];
    for (NSDictionary *snapshot in _snapshots) {
        if ([snapshot[@"identifier"] isEqual:_selected] && ![snapshot[@"damaged"] boolValue]) {
            [sections addObject:[self comparisonControls]];
            if (_comparison) [sections addObject:[self comparisonDetails]];
            [sections addObject:[self details:snapshot]];
            break;
        }
    }
    [_scroll setSections:sections];
}

- (NSView *)snapshotRow:(NSDictionary *)snapshot index:(NSUInteger)index {
    BOOL damaged = [snapshot[@"damaged"] boolValue];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[snapshot[@"captured_at_unix_seconds"] doubleValue]];
    NSString *title = damaged ? @"Damaged or unsupported snapshot" : [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *detail = damaged ? @"Kept for inspection; export unavailable." : [NSString stringWithFormat:@"%lu inventory records · %@", (unsigned long)[snapshot[@"inventory"][@"resources"] count], [_selected isEqual:snapshot[@"identifier"]] ? @"Selected" : @"Stored locally"];
    NSButton *inspect = PushButton(@"View", NO, self, @selector(selectSnapshot:));
    inspect.tag = (NSInteger)index;
    inspect.enabled = !damaged && !_busy;
    inspect.accessibilityLabel = [@"View snapshot " stringByAppendingString:title];
    NSButton *export = PushButton(@"Export…", NO, self, @selector(exportSnapshot:));
    export.tag = (NSInteger)index;
    export.enabled = !damaged && !_busy;
    export.accessibilityLabel = [@"Export snapshot " stringByAppendingString:title];
    NSStackView *row = HStack(12, @[VStack(4, @[Label(title, 13, NSFontWeightMedium, ThemeTextColor()), Label(detail, 12, NSFontWeightRegular, ThemeSubColor())]), Spacer(), inspect, export]);
    row.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
    return row;
}

- (void)selectSnapshot:(NSButton *)sender {
    _selected = _snapshots[(NSUInteger)sender.tag][@"identifier"];
    _comparison = nil;
    [self rebuild];
}

- (void)checkFile:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.resolvesAliases = NO;
    panel.prompt = @"Check Snapshot";
    panel.message = @"Check an exported inventory snapshot without importing it or changing configurations.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSURL *url = panel.URL;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            NSDictionary *snapshot = [self->_store inspectFileAtURL:url error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [NSAlert new];
                alert.alertStyle = snapshot ? NSAlertStyleInformational : NSAlertStyleWarning;
                alert.messageText = snapshot ? @"Snapshot integrity checked" : @"Snapshot could not be validated";
                if (snapshot) {
                    NSDictionary *inventory = snapshot[@"inventory"];
                    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[inventory[@"observed_at_unix_seconds"] doubleValue]];
                    alert.informativeText = [NSString stringWithFormat:@"%@\n%lu inventory records · %@ · %@\nScanned %@\n\nInventory only. Nothing was imported or applied. The checksum detects corruption; it does not verify who created this file.", url.lastPathComponent, (unsigned long)[inventory[@"resources"] count], inventory[@"host"][@"platform"], inventory[@"host"][@"architecture"], [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle]];
                } else alert.informativeText = error.localizedDescription ?: @"The file is unreadable or unsupported.";
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
            });
        });
    }];
}

- (NSView *)comparisonControls {
    NSPopUpButton *picker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    picker.translatesAutoresizingMaskIntoConstraints = NO;
    picker.target = self;
    picker.action = @selector(baselineChanged:);
    picker.accessibilityLabel = @"Baseline snapshot";
    for (NSDictionary *snapshot in _snapshots) {
        if ([snapshot[@"damaged"] boolValue] || [snapshot[@"identifier"] isEqual:_selected]) continue;
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[snapshot[@"captured_at_unix_seconds"] doubleValue]];
        NSString *identifier = snapshot[@"identifier"];
        NSString *title = [NSString stringWithFormat:@"%@ · %@", [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle], [identifier substringToIndex:MIN((NSUInteger)8, identifier.length)]];
        [picker addItemWithTitle:title];
        picker.lastItem.representedObject = identifier;
    }
    for (NSMenuItem *item in picker.itemArray) if ([item.representedObject isEqual:_baseline]) [picker selectItem:item];
    _baseline = picker.selectedItem.representedObject;
    picker.enabled = !_busy && picker.numberOfItems > 0;
    NSButton *compare = PushButton(@"Compare", NO, self, @selector(compareSnapshots:));
    compare.enabled = !_busy && _baseline != nil;
    NSStackView *body = VStack(8, @[]);
    FillWidth(WrappingLabel(@"Compare the selected inventory against an earlier or later snapshot. Changes run from baseline to selected snapshot.", 13, ThemeSubColor()), body);
    FillWidth(HStack(10, @[Label(@"Baseline", 13, NSFontWeightMedium, ThemeTextColor()), picker, Spacer(), compare]), body);
    return body;
}

- (void)baselineChanged:(NSPopUpButton *)sender {
    _baseline = sender.selectedItem.representedObject;
    _comparison = nil;
    [self rebuild];
}

- (void)compareSnapshots:(id)sender {
    if (_busy || !_baseline || !_selected) return;
    _busy = YES;
    _comparison = nil;
    NSString *before = _baseline, *after = _selected;
    [self rebuild];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSDictionary *result = [self->_store compareSnapshot:before toSnapshot:after error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            self->_comparison = result;
            self->_error = error.localizedDescription;
            [self rebuild];
        });
    });
}

- (NSView *)comparisonDetails {
    NSArray *added = _comparison[@"added"], *removed = _comparison[@"removed"], *changed = _comparison[@"changed"];
    NSString *summary = [NSString stringWithFormat:@"%lu added · %lu removed · %lu changed", (unsigned long)added.count, (unsigned long)removed.count, (unsigned long)changed.count];
    NSStackView *body = VStack(12, @[]);
    FillWidth(SectionHeader(@"Inventory changes", summary, nil), body);
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *kind in @[@"added", @"removed"]) {
        for (NSDictionary *resource in _comparison[kind]) {
            [lines addObject:[NSString stringWithFormat:@"%@ · %@ · %@ · %@", kind.capitalizedString, resource[@"display_name"], StringValue(resource[@"version"], @"Version unknown"), ResourceProviderName(resource)]];
        }
    }
    NSDictionary *labels = @{@"version": @"Version", @"installation_path": @"Installation path", @"path_status": @"PATH priority"};
    for (NSDictionary *change in changed) {
        NSDictionary *before = change[@"before"], *after = change[@"after"];
        for (NSString *field in change[@"fields"]) {
            [lines addObject:[NSString stringWithFormat:@"Changed · %@ · %@ · %@: %@ → %@", after[@"display_name"], ResourceProviderName(after), labels[field], StringValue(before[field], @"Not recorded"), StringValue(after[field], @"Not recorded")]];
        }
    }
    FillWidth(WrappingLabel(lines.count ? [lines componentsJoinedByString:@"\n"] : @"No inventory changes.", 13, ThemeTextColor()), body);
    return body;
}

- (NSView *)details:(NSDictionary *)snapshot {
    NSDictionary *report = snapshot[@"inventory"];
    NSDate *scanned = [NSDate dateWithTimeIntervalSince1970:[report[@"observed_at_unix_seconds"] doubleValue]];
    NSString *caption = [NSString stringWithFormat:@"Scanned %@ · Integrity checked", [NSDateFormatter localizedStringFromDate:scanned dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle]];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *resource in report[@"resources"]) {
        [lines addObject:[NSString stringWithFormat:@"%@  ·  %@  ·  %@", resource[@"display_name"], StringValue(resource[@"version"], @"Version unknown"), ResourceProviderName(resource)]];
    }
    NSStackView *content = VStack(12, @[]);
    FillWidth(SectionHeader(@"Saved inventory", caption, nil), content);
    FillWidth(WrappingLabel(lines.count ? [lines componentsJoinedByString:@"\n"] : @"No tools recorded.", 13, ThemeTextColor()), content);
    if ([report[@"warnings"] count]) FillWidth(WrappingLabel([report[@"warnings"] componentsJoinedByString:@"\n"], 13, NSColor.systemOrangeColor), content);
    return content;
}

- (void)exportSnapshot:(NSButton *)sender {
    NSString *identifier = _snapshots[(NSUInteger)sender.tag][@"identifier"];
    NSSavePanel *panel = NSSavePanel.savePanel;
    panel.nameFieldStringValue = [@"DevCloud-Snapshot-" stringByAppendingString:identifier];
    panel.message = @"Exports saved inventory, including installation paths if they were enabled when scanned. Config files are excluded.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        SnapshotStore *store = self->_store;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            NSData *data = [store exportSnapshot:identifier error:&error];
            BOOL saved = data && [data writeToURL:panel.URL options:NSDataWritingAtomic error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_error = error.localizedDescription;
                [self rebuild];
                if (saved) [self.host toast:@"Snapshot exported" detail:panel.URL.lastPathComponent];
            });
        });
    }];
}
@end
