#import "Pages.h"

NSArray<NSString *> *WorkspaceReadScope(void) { return @[@"Current branch name", @"Number of linked worktrees", @"Folder name"]; }
NSArray<NSString *> *WorkspaceNeverRead(void) { return @[@"File contents or source code", @".env files and private keys", @"Commit messages and remote URLs"]; }

@implementation WorkspacesPage {
    PageScrollView *_scroll;
}

- (instancetype)initWithHost:(id<PageHost>)host {
    self = [super initWithHost:host];
    if (self) {
        _scroll = [[PageScrollView alloc] initWithMaxWidth:1000];
        Pin(_scroll, self, NSEdgeInsetsZero);
    }
    return self;
}

- (NSString *)signature {
    return [NSString stringWithFormat:@"%@|%p|%d", [self.model.approvedRoots componentsJoinedByString:@":"], self.model.localMetadata, self.model.scanning];
}

- (void)rebuild {
    NSButton *add = PushButton(@"Add Workspace…", YES, self.host, @selector(approveWorkspace:));
    add.image = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:nil];
    add.imagePosition = NSImageLeading;
    add.keyEquivalent = @"";
    NSView *header = SectionHeader(@"Approved folders", @"Only folders you choose are inspected. Remove access at any time.", add);
    NSView *body = self.model.approvedRoots.count ? [self foldersPanel] : [self emptyPanel];
    [_scroll setSections:@[
        SectionWithHeader(header, body),
        SectionWithHeader(SectionHeader(@"What is read from workspaces", nil, nil), [self scopePanel]),
    ]];
}

- (NSDictionary *)workspaceForRoot:(NSString *)root {
    NSString *name = root.lastPathComponent;
    for (NSDictionary *workspace in self.inventory.workspaces) {
        NSString *path = StringValue(workspace[@"path"], nil);
        if (path ? [path isEqual:root] : [StringValue(workspace[@"name"], @"") isEqual:name]) return workspace;
    }
    return nil;
}

- (NSView *)foldersPanel {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *root in self.model.approvedRoots) {
        NSDictionary *workspace = [self workspaceForRoot:root];
        PanelView *tile = [PanelView new];
        tile.cornerRadius = 9;
        tile.fill = ToneFillColor(ToneBlue);
        tile.border = nil;
        NSImageView *icon = SymbolView(workspace ? @"folder.badge.gearshape" : @"folder", 15, NSFontWeightMedium, NSColor.systemBlueColor);
        [tile addSubview:icon];
        [NSLayoutConstraint activateConstraints:@[
            [tile.widthAnchor constraintEqualToConstant:36], [tile.heightAnchor constraintEqualToConstant:36],
            [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor], [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        ]];
        NSTextField *name = Label(root.lastPathComponent, 13, NSFontWeightMedium, ThemeTextColor());
        NSTextField *path = MonoLabel([root stringByAbbreviatingWithTildeInPath], 11, ThemeFaintColor());
        path.toolTip = root;
        NSStackView *text = VStack(2, @[name, path]);

        NSStackView *row = HStack(16, @[tile, text, Spacer()]);
        if (workspace) {
            NSUInteger worktrees = [workspace[@"linked_worktree_count"] unsignedIntegerValue];
            NSStackView *branch = HStack(5, @[SymbolView(@"arrow.triangle.branch", 11, NSFontWeightMedium, ThemeFaintColor()), MonoLabel(StringValue(workspace[@"branch"], @"detached"), 11.5, ThemeSubColor())]);
            NSStackView *trees = HStack(5, @[SymbolView(@"square.on.square", 11, NSFontWeightMedium, ThemeFaintColor()),
                                             Label([NSString stringWithFormat:@"%lu linked %@", (unsigned long)worktrees, worktrees == 1 ? @"worktree" : @"worktrees"], 12, NSFontWeightRegular, ThemeSubColor())]);
            [row addArrangedSubview:branch];
            [row addArrangedSubview:trees];
            [row addArrangedSubview:[workspace[@"is_linked_worktree"] boolValue] ? [PillView pill:@"Worktree" tone:ToneBlue dot:NO] : [PillView pill:@"Repository" tone:ToneGreen dot:NO]];
        } else {
            [row addArrangedSubview:Label(self.model.scanning ? @"Reading…" : @"Not a Git repository", 12, NSFontWeightRegular, ThemeFaintColor())];
        }
        NSButton *remove = LinkButton(@"Remove", self, @selector(remove:));
        remove.contentTintColor = ThemeFaintColor();
        remove.identifier = root;
        remove.accessibilityLabel = [NSString stringWithFormat:@"Remove access to %@", root.lastPathComponent];
        [row addArrangedSubview:remove];
        NSView *cell = [NSView new];
        cell.translatesAutoresizingMaskIntoConstraints = NO;
        Pin(row, cell, NSEdgeInsetsMake(13, 16, 13, 16));
        [rows addObject:cell];
    }
    return ListPanel(rows);
}

- (void)remove:(NSButton *)sender {
    NSString *root = sender.identifier;
    [self.model removeApprovedRoot:root];
    [self.host toast:@"Access removed" detail:[root stringByAbbreviatingWithTildeInPath]];
}

- (NSView *)emptyPanel {
    NSImageView *icon = SymbolView(@"folder.badge.plus", 28, NSFontWeightLight, ThemeFaintColor());
    NSTextField *message = WrappingLabel(@"Add a project folder to see its branch and worktrees. Nothing is read until you approve it.", 12, ThemeFaintColor());
    message.alignment = NSTextAlignmentCenter;
    [message.widthAnchor constraintLessThanOrEqualToConstant:320].active = YES;
    NSButton *add = PushButton(@"Add Workspace…", YES, self.host, @selector(approveWorkspace:));
    NSStackView *stack = VStack(6, @[icon, Label(@"No workspaces yet", 13, NSFontWeightMedium, ThemeTextColor()), message, add]);
    stack.alignment = NSLayoutAttributeCenterX;
    [stack setCustomSpacing:12 afterView:icon];
    [stack setCustomSpacing:16 afterView:message];
    stack.edgeInsets = NSEdgeInsetsMake(40, 0, 40, 0);
    return PaddedPanel(stack, 0);
}

- (NSView *)scopePanel {
    PanelView *panel = [PanelView new];
    NSView *read = [self scopeList:@"Read as metadata" items:WorkspaceReadScope() tone:ToneGreen];
    NSView *never = [self scopeList:@"Never read" items:WorkspaceNeverRead() tone:ToneNeutral];
    NSView *line = Hairline();
    NSStackView *row = HStack(0, @[read, line, never]);
    row.alignment = NSLayoutAttributeTop;
    [NSLayoutConstraint activateConstraints:@[
        [line.widthAnchor constraintEqualToConstant:1],
        [line.heightAnchor constraintEqualToAnchor:row.heightAnchor],
        [read.widthAnchor constraintEqualToAnchor:never.widthAnchor],
    ]];
    Pin(row, panel, NSEdgeInsetsZero);
    return panel;
}

- (NSView *)scopeList:(NSString *)title items:(NSArray<NSString *> *)items tone:(Tone)tone {
    NSStackView *stack = VStack(9, @[Label(title, 12.5, NSFontWeightSemibold, ThemeTextColor())]);
    [stack setCustomSpacing:12 afterView:stack.arrangedSubviews.firstObject];
    for (NSString *item in items) {
        StatusDot *dot = [StatusDot dotWithTone:tone pulse:NO];
        [stack addArrangedSubview:HStack(10, @[dot, Label(item, 12.5, NSFontWeightRegular, ThemeSubColor())])];
    }
    NSView *cell = [NSView new];
    cell.translatesAutoresizingMaskIntoConstraints = NO;
    Pin(stack, cell, NSEdgeInsetsMake(20, 20, 20, 20));
    return cell;
}

@end
