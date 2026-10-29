#import "StatusMenu.h"
#import "BrandMark.h"
#import "Inventory.h"
#import "Theme.h"

// Borderless panels refuse key status by default; this one needs it for Escape.
@interface StatusPanel : NSPanel
@end
@implementation StatusPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (void)cancelOperation:(id)sender { [self orderOut:nil]; }
@end

// A menu command: blue highlight and white text on hover, like a native menu item.
@interface MenuRow : NSView
@property(nonatomic) SEL action;
@property(nonatomic, weak) id target;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL highlighted;
@property(nonatomic, strong) NSTextField *title;
@property(nonatomic, strong) NSTextField *shortcut;
@end

@implementation MenuRow

+ (instancetype)row:(NSString *)title shortcut:(NSString *)shortcut action:(SEL)action target:(id)target {
    MenuRow *row = [MenuRow new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.action = action;
    row.target = target;
    row.enabled = YES;
    row.title = Label(title, 13, NSFontWeightRegular, ThemeTextColor());
    row.shortcut = Label(shortcut, 12, NSFontWeightRegular, ThemeFaintColor());
    Pin(HStack(8, @[row.title, Spacer(), row.shortcut]), row, NSEdgeInsetsMake(0, 10, 0, 10));
    [row.heightAnchor constraintEqualToConstant:24].active = YES;
    row.accessibilityElement = YES;
    row.accessibilityRole = NSAccessibilityMenuItemRole;
    row.accessibilityLabel = title;
    row.title.accessibilityElement = NO;
    row.shortcut.accessibilityElement = NO;
    return row;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}

- (void)setHighlighted:(BOOL)highlighted {
    _highlighted = highlighted && self.enabled;
    self.title.textColor = !self.enabled ? ThemeFaintColor() : (_highlighted ? NSColor.whiteColor : ThemeTextColor());
    self.shortcut.textColor = _highlighted ? [NSColor.whiteColor colorWithAlphaComponent:0.7] : ThemeFaintColor();
    self.needsDisplay = YES;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    self.accessibilityEnabled = enabled;
    self.highlighted = self.highlighted;
}

- (void)mouseEntered:(NSEvent *)event { self.highlighted = YES; }
- (void)mouseExited:(NSEvent *)event { self.highlighted = NO; }
- (void)mouseUp:(NSEvent *)event { if (NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds)) [self accessibilityPerformPress]; }
- (void)mouseDown:(NSEvent *)event {}

- (BOOL)accessibilityPerformPress {
    if (!self.enabled) return NO;
    self.highlighted = NO;
    [NSApp sendAction:self.action to:self.target from:self];
    return YES;
}

- (void)drawRect:(NSRect)rect {
    if (!self.highlighted) return;
    [NSColor.systemBlueColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:5 yRadius:5] fill];
}

@end

@interface StatusMenu ()
@property(nonatomic, strong) ScanModel *model;
@property(nonatomic, weak) NSStatusItem *statusItem;
@property(nonatomic, weak) id target;
@property(nonatomic, strong, readwrite) NSPanel *panel;
@property(nonatomic, strong) NSStackView *stack;
@property(nonatomic, strong) NSView *badge;
@property(nonatomic, strong) id localMonitor;
@property(nonatomic, strong) id globalMonitor;
@property(nonatomic, strong) NSDate *closedAt;
@end

@implementation StatusMenu

- (instancetype)initWithModel:(ScanModel *)model statusItem:(NSStatusItem *)item target:(id)target {
    self = [super init];
    if (!self) return nil;
    _model = model;
    _statusItem = item;
    _target = target;
    item.button.image = ContinuityMenuBarImage();
    item.button.target = self;
    item.button.action = @selector(toggle);
    item.button.accessibilityLabel = @"Continuity";
    // An amber dot on the mark says something needs attention.
    _badge = [PanelView new];
    ((PanelView *)_badge).cornerRadius = 2.5;
    ((PanelView *)_badge).fill = NSColor.systemOrangeColor;
    ((PanelView *)_badge).border = nil;
    [item.button addSubview:_badge];
    [NSLayoutConstraint activateConstraints:@[
        [_badge.widthAnchor constraintEqualToConstant:5], [_badge.heightAnchor constraintEqualToConstant:5],
        [_badge.trailingAnchor constraintEqualToAnchor:item.button.trailingAnchor constant:-3],
        [_badge.topAnchor constraintEqualToAnchor:item.button.topAnchor constant:3],
    ]];
    [self buildPanel];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:ScanModelDidChangeNotification object:model];
    [self refresh];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self removeMonitors];
}

- (void)buildPanel {
    self.panel = [[StatusPanel alloc] initWithContentRect:NSMakeRect(0, 0, 320, 300) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:YES];
    self.panel.level = NSPopUpMenuWindowLevel;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.hidesOnDeactivate = NO;
    self.panel.releasedWhenClosed = NO;
    self.panel.accessibilityLabel = @"Continuity menu";
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(close) name:NSWindowDidResignKeyNotification object:self.panel];

    NSVisualEffectView *background = [NSVisualEffectView new];
    background.material = NSVisualEffectMaterialMenu;
    background.state = NSVisualEffectStateActive;
    background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    background.maskImage = [NSImage imageWithSize:NSMakeSize(25, 25) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:12 yRadius:12] fill];
        return YES;
    }];
    background.maskImage.capInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    background.maskImage.resizingMode = NSImageResizingModeStretch;
    PanelView *border = [PanelView new];
    border.cornerRadius = 12;
    border.fill = NSColor.clearColor;
    border.border = [ThemeTextColor() colorWithAlphaComponent:0.12];
    Pin(border, background, NSEdgeInsetsZero);
    self.stack = VStack(0, @[]);
    Pin(self.stack, background, NSEdgeInsetsMake(6, 6, 6, 6));
    [self.stack.widthAnchor constraintEqualToConstant:308].active = YES;
    self.panel.contentView = background;
}

#pragma mark Content

- (void)refresh {
    ScanModel *model = self.model;
    Inventory *inventory = [Inventory inventoryForModel:model];
    NSUInteger warnings = inventory.attention.count;
    self.badge.hidden = warnings == 0 && model.errorMessage == nil;
    self.statusItem.button.appearsDisabled = !model.monitoring;
    self.statusItem.button.toolTip = model.scanning ? [NSString stringWithFormat:@"Continuity: %@", model.phase] : (model.monitoring ? @"Continuity: monitoring" : @"Continuity: monitoring paused");

    for (NSView *view in self.stack.arrangedSubviews) { [self.stack removeArrangedSubview:view]; [view removeFromSuperview]; }
    FillWidth([self header], self.stack);
    FillWidth([self statusCard:inventory], self.stack);
    NSStackView *heading = VStack(0, @[Label(@"Recent warnings", 11, NSFontWeightSemibold, ThemeFaintColor())]);
    heading.edgeInsets = NSEdgeInsetsMake(12, 12, 4, 12);
    FillWidth(heading, self.stack);
    NSArray *items = [inventory.attention subarrayWithRange:NSMakeRange(0, MIN(2u, inventory.attention.count))];
    for (AttentionItem *item in items) FillWidth([self warningRow:item.title detail:item.detail], self.stack);
    if (!items.count) {
        NSStackView *none = HStack(8, @[SymbolView(@"checkmark.circle", 11, NSFontWeightMedium, NSColor.systemGreenColor), Label(model.report ? @"Nothing needs attention" : @"Appears after the first scan", 12, NSFontWeightRegular, ThemeSubColor())]);
        none.edgeInsets = NSEdgeInsetsMake(4, 12, 4, 12);
        FillWidth(none, self.stack);
    }
    [self separator];
    FillWidth([MenuRow row:@"Open Continuity" shortcut:@"⌘O" action:@selector(openMainWindow:) target:self.target], self.stack);
    MenuRow *scan = [MenuRow row:model.scanning ? @"Scanning…" : @"Scan Now" shortcut:@"⌘R" action:@selector(scanNow:) target:self.target];
    scan.enabled = !model.scanning;
    FillWidth(scan, self.stack);
    MenuRow *export = [MenuRow row:@"Export JSON…" shortcut:@"⌘E" action:@selector(exportReport:) target:self.target];
    export.enabled = model.report != nil;
    FillWidth(export, self.stack);
    [self separator];
    FillWidth([MenuRow row:@"Settings…" shortcut:@"⌘," action:@selector(openSettings:) target:self.target], self.stack);
    FillWidth([MenuRow row:@"Quit Continuity" shortcut:@"⌘Q" action:@selector(quit:) target:self.target], self.stack);
    if (self.panel.isVisible) [self position];
}

- (NSView *)header {
    NSImageView *icon = [NSImageView imageViewWithImage:ContinuityAppIconImage(30)];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.accessibilityElement = NO;
    BOOL on = self.model.monitoring;
    NSStackView *status = HStack(6, @[[StatusDot dotWithTone:on ? ToneGreen : ToneAmber pulse:NO], Label(on ? @"Monitoring" : @"Monitoring paused", 11, NSFontWeightRegular, ThemeSubColor())]);
    NSSwitch *toggle = Switch(on, NSControlSizeMini, self, @selector(toggleMonitoring:));
    toggle.accessibilityLabel = @"Background monitoring";
    NSStackView *row = HStack(12, @[icon, VStack(2, @[Label(@"Continuity", 13, NSFontWeightSemibold, ThemeTextColor()), status]), Spacer(), toggle]);
    row.edgeInsets = NSEdgeInsetsMake(8, 10, 10, 10);
    return row;
}

- (NSView *)statusCard:(Inventory *)inventory {
    ScanModel *model = self.model;
    NSStackView *stack = VStack(4, @[]);
    if (model.scanning) {
        FillWidth(Label([NSString stringWithFormat:@"%@…", model.phase ?: @"Scanning"], 12.5, NSFontWeightRegular, ThemeTextColor()), stack);
        ProgressBar *bar = [ProgressBar barWithHeight:3];
        bar.value = model.progress > 0 ? model.progress : MIN(0.9, 0.12 + model.completedPhases.count * 0.16);
        [stack setCustomSpacing:8 afterView:stack.arrangedSubviews.lastObject];
        FillWidth(bar, stack);
    } else if (model.errorMessage) {
        FillWidth(Label(@"Last scan failed", 12.5, NSFontWeightRegular, NSColor.systemOrangeColor), stack);
        FillWidth(WrappingLabel(model.errorMessage, 11, ThemeFaintColor()), stack);
    } else if (model.report) {
        FillWidth(Label(@"Environment scan complete", 12.5, NSFontWeightRegular, ThemeTextColor()), stack);
        NSUInteger warnings = inventory.attention.count;
        NSString *detail = [NSString stringWithFormat:@"%lu tools · %lu %@ · %@", (unsigned long)inventory.developerToolCount, (unsigned long)warnings, warnings == 1 ? @"warning" : @"warnings", RelativeDate(model.lastScanDate)];
        if (model.changeSummary) detail = [detail stringByAppendingFormat:@"\nLast change: %@", model.changeSummary];
        FillWidth(WrappingLabel(detail, 11, ThemeFaintColor()), stack);
    } else {
        FillWidth(Label(@"No scan yet", 12.5, NSFontWeightRegular, ThemeTextColor()), stack);
        FillWidth(Label(@"Choose Scan Now to take inventory.", 11, NSFontWeightRegular, ThemeFaintColor()), stack);
    }
    PanelView *card = PaddedPanel(stack, 10);
    card.cornerRadius = 8;
    card.border = nil;
    card.fill = [ThemeTextColor() colorWithAlphaComponent:0.045];
    NSStackView *inset = VStack(0, @[]);
    inset.edgeInsets = NSEdgeInsetsMake(0, 4, 0, 4);
    FillWidth(card, inset);
    return inset;
}

- (NSView *)warningRow:(NSString *)title detail:(NSString *)detail {
    NSImageView *icon = SymbolView(@"exclamationmark.triangle", 10, NSFontWeightSemibold, NSColor.systemOrangeColor);
    NSStackView *text = VStack(1, @[Label(title, 12, NSFontWeightRegular, ThemeTextColor()), Label(detail, 11, NSFontWeightRegular, ThemeFaintColor())]);
    NSStackView *row = HStack(9, @[icon, text]);
    row.alignment = NSLayoutAttributeTop;
    row.edgeInsets = NSEdgeInsetsMake(5, 12, 5, 12);
    return row;
}

- (void)separator {
    NSStackView *wrap = VStack(0, @[]);
    wrap.edgeInsets = NSEdgeInsetsMake(6, 10, 6, 10);
    FillWidth(Hairline(), wrap);
    FillWidth(wrap, self.stack);
}

- (void)toggleMonitoring:(NSSwitch *)sender {
    [self.model setMonitoringEnabled:sender.state == NSControlStateValueOn];
}

#pragma mark Showing

- (void)toggle {
    // Clicking the icon first resigns the panel's key status; don't reopen it.
    BOOL justClosed = self.closedAt && -self.closedAt.timeIntervalSinceNow < 0.3;
    if (self.panel.isVisible) [self close];
    else if (!justClosed) [self show];
}

- (void)show {
    [self refresh];
    [self position];
    [self.panel makeKeyAndOrderFront:nil];
    self.statusItem.button.highlighted = YES;
    __weak StatusMenu *weakSelf = self;
    self.localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:^NSEvent *(NSEvent *event) {
        if (event.window != weakSelf.panel && event.window != weakSelf.statusItem.button.window) [weakSelf close];
        return event;
    }];
    self.globalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:^(NSEvent *event) { [weakSelf close]; }];
}

- (void)position {
    [self.panel.contentView layoutSubtreeIfNeeded];
    NSSize size = self.panel.contentView.fittingSize;
    NSRect anchor = self.statusItem.button.window.frame;
    NSRect screen = (self.statusItem.button.window.screen ?: NSScreen.mainScreen).visibleFrame;
    CGFloat x = MIN(NSMaxX(anchor) - size.width + 8, NSMaxX(screen) - size.width - 6);
    [self.panel setFrame:NSMakeRect(MAX(NSMinX(screen) + 6, x), NSMinY(anchor) - size.height - 4, size.width, size.height) display:YES];
}

- (void)close {
    if (!self.panel.isVisible) return;
    [self.panel orderOut:nil];
    self.closedAt = NSDate.date;
    self.statusItem.button.highlighted = NO;
    [self removeMonitors];
}

- (void)removeMonitors {
    if (self.localMonitor) [NSEvent removeMonitor:self.localMonitor];
    if (self.globalMonitor) [NSEvent removeMonitor:self.globalMonitor];
    self.localMonitor = nil;
    self.globalMonitor = nil;
}

@end
