#import "Theme.h"
#import <QuartzCore/QuartzCore.h>
#import "ToolIcons.h"

static NSColor *Hex(uint32_t rgb, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:alpha];
}

static NSColor *Dynamic(NSColor *light, NSColor *dark) {
    return [NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *appearance) {
        return [[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqual:NSAppearanceNameDarkAqua] ? dark : light;
    }];
}

#define CACHED(expression) static NSColor *color; static dispatch_once_t once; dispatch_once(&once, ^{ color = (expression); }); return color

NSColor *ThemeWindowColor(void) { CACHED(Dynamic(Hex(0xffffff, 1), Hex(0x1a1a1c, 1))); }
NSColor *ThemeSidebarColor(void) { CACHED(Dynamic(Hex(0xf3f3f5, 1), Hex(0x202022, 1))); }
NSColor *ThemePanelColor(void) { CACHED(Dynamic(Hex(0x000000, 0.025), Hex(0xffffff, 0.028))); }
NSColor *ThemeHairlineColor(void) { CACHED(Dynamic(Hex(0x000000, 0.08), Hex(0xffffff, 0.06))); }
NSColor *ThemeHoverColor(void) { CACHED(Dynamic(Hex(0x000000, 0.035), Hex(0xffffff, 0.04))); }
NSColor *ThemeSelectionColor(void) { CACHED(Dynamic(Hex(0x000000, 0.07), Hex(0xffffff, 0.1))); }
NSColor *ThemeWellColor(void) { CACHED(Dynamic(Hex(0x000000, 0.04), Hex(0x000000, 0.3))); }
NSColor *ThemeTextColor(void) { CACHED(Dynamic(Hex(0x1d1d1f, 1), Hex(0xf5f5f7, 1))); }
NSColor *ThemeSubColor(void) { CACHED(Dynamic(Hex(0x5f5f64, 1), Hex(0xa1a1a6, 1))); }
NSColor *ThemeFaintColor(void) { CACHED(Dynamic(Hex(0x8a8a8f, 1), Hex(0x6e6e73, 1))); }

NSColor *ToneColor(Tone tone) {
    switch (tone) {
        case ToneGreen: return NSColor.systemGreenColor;
        case ToneAmber: return NSColor.systemOrangeColor;
        case ToneRed: return NSColor.systemRedColor;
        case ToneBlue: return NSColor.systemBlueColor;
        default: return ThemeSubColor();
    }
}

NSColor *ToneFillColor(Tone tone) {
    if (tone == ToneNeutral) { CACHED(Dynamic(Hex(0x000000, 0.06), Hex(0xffffff, 0.07))); }
    return [ToneColor(tone) colorWithAlphaComponent:tone == ToneBlue ? 0.14 : 0.12];
}

NSFont *ThemeFont(CGFloat size, NSFontWeight weight) { return [NSFont systemFontOfSize:size weight:weight]; }
NSFont *ThemeMono(CGFloat size) { return [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular]; }

NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = ThemeFont(size, weight);
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:300 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

NSTextField *MonoLabel(NSString *text, CGFloat size, NSColor *color) {
    NSTextField *label = Label(text, size, NSFontWeightRegular, color);
    label.font = ThemeMono(size);
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return label;
}

NSTextField *WrappingLabel(NSString *text, CGFloat size, NSColor *color) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text ?: @""];
    label.font = ThemeFont(size, NSFontWeightRegular);
    label.textColor = color;
    label.selectable = NO;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:300 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

static NSStackView *Stack(NSUserInterfaceLayoutOrientation orientation, CGFloat spacing, NSArray<NSView *> *views) {
    NSStackView *stack = [NSStackView stackViewWithViews:views ?: @[]];
    stack.orientation = orientation;
    stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = spacing;
    // Exact gaps; gravity areas leave `>=` gaps that make layouts ambiguous.
    stack.distribution = NSStackViewDistributionFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

NSStackView *VStack(CGFloat spacing, NSArray<NSView *> *views) { return Stack(NSUserInterfaceLayoutOrientationVertical, spacing, views); }
NSStackView *HStack(CGFloat spacing, NSArray<NSView *> *views) { return Stack(NSUserInterfaceLayoutOrientationHorizontal, spacing, views); }

NSImageView *SymbolView(NSString *name, CGFloat size, NSFontWeight weight, NSColor *tint) {
    NSImageView *view = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] ?: [NSImage new]];
    view.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    view.contentTintColor = tint;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.accessibilityElement = NO;
    [view setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [view setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}

@interface HairlineView : NSView
@end
@implementation HairlineView
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 1); }
- (void)drawRect:(NSRect)rect {
    [ThemeHairlineColor() setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
}
@end

NSView *Hairline(void) {
    HairlineView *line = [HairlineView new];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    return line;
}

NSView *Spacer(void) {
    NSView *spacer = [NSView new];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    // Collapses unless the stack is stretched, so its size is never ambiguous.
    NSLayoutConstraint *width = [spacer.widthAnchor constraintEqualToConstant:0];
    width.priority = 1;
    NSLayoutConstraint *height = [spacer.heightAnchor constraintEqualToConstant:0];
    height.priority = 1;
    [NSLayoutConstraint activateConstraints:@[width, height]];
    return spacer;
}

NSButton *PushButton(NSString *title, BOOL primary, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.controlSize = NSControlSizeRegular;
    if (primary) {
        button.bezelColor = NSColor.controlAccentColor;
        button.keyEquivalent = @"\r";
    }
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}

NSButton *LinkButton(NSString *title, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bordered = NO;
    button.font = ThemeFont(12, NSFontWeightRegular);
    button.contentTintColor = NSColor.linkColor;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}

NSSwitch *Switch(BOOL on, NSControlSize size, id target, SEL action) {
    NSSwitch *control = [NSSwitch new];
    control.controlSize = size;
    control.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    control.target = target;
    control.action = action;
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [control setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return control;
}

void Pin(NSView *view, NSView *container, NSEdgeInsets insets) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    if (view.superview != container) [container addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:insets.left],
        [view.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-insets.right],
        [view.topAnchor constraintEqualToAnchor:container.topAnchor constant:insets.top],
        [view.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-insets.bottom],
    ]];
}

void FillWidth(NSView *view, NSStackView *stack) {
    if (view.superview != stack) [stack addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-(stack.edgeInsets.left + stack.edgeInsets.right)].active = YES;
}

NSString *RelativeDate(NSDate *date) {
    if (!date) return @"never";
    NSTimeInterval seconds = -date.timeIntervalSinceNow;
    if (seconds < 45) return @"just now";
    if (seconds < 3600) return [NSString stringWithFormat:@"%.0f min ago", MAX(1, round(seconds / 60))];
    if (seconds < 86400) return [NSString stringWithFormat:@"%.0f hr ago", round(seconds / 3600)];
    NSRelativeDateTimeFormatter *formatter = [NSRelativeDateTimeFormatter new];
    return [formatter localizedStringForDate:date relativeToDate:NSDate.date];
}

@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - Panels

@implementation PanelView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _cornerRadius = 10;
        _fill = ThemePanelColor();
        _border = ThemeHairlineColor();
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (void)drawRect:(NSRect)rect {
    NSRect bounds = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:self.cornerRadius yRadius:self.cornerRadius];
    [self.fill setFill];
    [shape fill];
    if (self.border) {
        [self.border setStroke];
        shape.lineWidth = 1;
        [shape stroke];
    }
}

@end

PanelView *ListPanel(NSArray<NSView *> *rows) {
    PanelView *panel = [PanelView new];
    NSStackView *stack = VStack(0, @[]);
    [rows enumerateObjectsUsingBlock:^(NSView *row, NSUInteger index, BOOL *stop) {
        if (index > 0) FillWidth(Hairline(), stack);
        FillWidth(row, stack);
    }];
    Pin(stack, panel, NSEdgeInsetsZero);
    return panel;
}

PanelView *PaddedPanel(NSView *content, CGFloat inset) {
    PanelView *panel = [PanelView new];
    Pin(content, panel, NSEdgeInsetsMake(inset, inset, inset, inset));
    return panel;
}

#pragma mark - Pills, dots, meters

@interface PillView ()
@property(nonatomic) Tone tone;
@property(nonatomic) BOOL dot;
@property(nonatomic, strong) NSTextField *label;
@end

@implementation PillView

+ (instancetype)pill:(NSString *)text tone:(Tone)tone dot:(BOOL)dot {
    PillView *pill = [PillView new];
    pill.tone = tone;
    pill.dot = dot;
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.label = Label(text, 11, NSFontWeightMedium, tone == ToneNeutral ? ThemeSubColor() : ToneColor(tone));
    [pill.label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [pill addSubview:pill.label];
    [NSLayoutConstraint activateConstraints:@[
        [pill.heightAnchor constraintEqualToConstant:20],
        [pill.label.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:dot ? 20 : 8],
        [pill.label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-8],
        [pill.label.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
    ]];
    [pill setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [pill setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    pill.accessibilityElement = YES;
    pill.accessibilityRole = NSAccessibilityStaticTextRole;
    pill.accessibilityLabel = text;
    pill.label.accessibilityElement = NO;
    return pill;
}

- (void)drawRect:(NSRect)rect {
    CGFloat radius = self.bounds.size.height / 2;
    [ToneFillColor(self.tone) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius] fill];
    if (self.dot) {
        [ToneColor(self.tone) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(8, NSMidY(self.bounds) - 3, 6, 6)] fill];
    }
}

@end

@interface StatusDot ()
@property(nonatomic) Tone tone;
@property(nonatomic) BOOL pulse;
@property(nonatomic, strong) CALayer *ring;
@end

@implementation StatusDot

+ (instancetype)dotWithTone:(Tone)tone pulse:(BOOL)pulse {
    StatusDot *dot = [StatusDot new];
    dot.tone = tone;
    dot.pulse = pulse && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[dot.widthAnchor constraintEqualToConstant:8], [dot.heightAnchor constraintEqualToConstant:8]]];
    return dot;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.pulse || !self.window || self.ring) return;
    self.wantsLayer = YES;
    CALayer *ring = [CALayer layer];
    self.ring = ring;
    ring.frame = self.bounds;
    ring.cornerRadius = 4;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{ ring.backgroundColor = ToneColor(self.tone).CGColor; }];
    [self.layer insertSublayer:ring atIndex:0];
    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = @1;
    scale.toValue = @2.2;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0.5;
    fade.toValue = @0;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[scale, fade];
    group.duration = 1.6;
    group.repeatCount = HUGE_VALF;
    ring.opacity = 0;
    [ring addAnimation:group forKey:@"pulse"];
}

- (void)drawRect:(NSRect)rect {
    [ToneColor(self.tone) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:self.bounds] fill];
}

@end

@implementation ProgressBar

+ (instancetype)barWithHeight:(CGFloat)height {
    ProgressBar *bar = [ProgressBar new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [bar.heightAnchor constraintEqualToConstant:height].active = YES;
    bar.accessibilityElement = YES;
    bar.accessibilityRole = NSAccessibilityProgressIndicatorRole;
    bar.accessibilityLabel = @"Scan progress";
    return bar;
}

- (void)setValue:(double)value {
    _value = MIN(1, MAX(0, value));
    self.accessibilityValue = @(_value);
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)rect {
    CGFloat radius = self.bounds.size.height / 2;
    [ThemeHairlineColor() setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius] fill];
    NSRect filled = self.bounds;
    filled.size.width = MAX(filled.size.height * 2, filled.size.width * MAX(0.05, self.value));
    [NSColor.systemBlueColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:filled xRadius:radius yRadius:radius] fill];
}

@end

NSString *ConfidenceName(NSInteger level) {
    return level >= 3 ? @"Verified" : (level == 2 ? @"Likely" : @"Inferred");
}

@interface ConfidenceBars : NSView
@property(nonatomic) NSInteger level;
@end

@implementation ConfidenceBars
- (NSSize)intrinsicContentSize { return NSMakeSize(13, 13); }
- (void)drawRect:(NSRect)rect {
    for (NSInteger bar = 1; bar <= 3; bar++) {
        NSColor *color = bar > self.level ? [ThemeFaintColor() colorWithAlphaComponent:0.35] : (self.level == 3 ? NSColor.systemGreenColor : [ThemeTextColor() colorWithAlphaComponent:0.8]);
        [color setFill];
        CGFloat height = 4 + bar * 3;
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect((bar - 1) * 5, 0, 3, height) xRadius:1 yRadius:1] fill];
    }
}
@end

@implementation ConfidenceMeter

+ (instancetype)meterWithLevel:(NSInteger)level showLabel:(BOOL)showLabel {
    ConfidenceMeter *meter = [ConfidenceMeter new];
    meter.translatesAutoresizingMaskIntoConstraints = NO;
    ConfidenceBars *bars = [ConfidenceBars new];
    bars.level = level;
    bars.translatesAutoresizingMaskIntoConstraints = NO;
    bars.accessibilityElement = NO;
    [meter addSubview:bars];
    NSMutableArray *constraints = [@[
        [bars.widthAnchor constraintEqualToConstant:13], [bars.heightAnchor constraintEqualToConstant:13],
        [bars.leadingAnchor constraintEqualToAnchor:meter.leadingAnchor],
        [bars.topAnchor constraintEqualToAnchor:meter.topAnchor], [bars.bottomAnchor constraintEqualToAnchor:meter.bottomAnchor],
    ] mutableCopy];
    if (showLabel) {
        NSTextField *label = Label(ConfidenceName(level), 12, NSFontWeightRegular, ThemeSubColor());
        label.accessibilityElement = NO;
        [meter addSubview:label];
        [constraints addObjectsFromArray:@[
            [label.leadingAnchor constraintEqualToAnchor:bars.trailingAnchor constant:7],
            [label.trailingAnchor constraintEqualToAnchor:meter.trailingAnchor],
            [label.lastBaselineAnchor constraintEqualToAnchor:bars.bottomAnchor],
        ]];
    } else {
        [constraints addObject:[bars.trailingAnchor constraintEqualToAnchor:meter.trailingAnchor]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    meter.accessibilityElement = YES;
    meter.accessibilityRole = NSAccessibilityStaticTextRole;
    meter.accessibilityLabel = [NSString stringWithFormat:@"Confidence: %@", ConfidenceName(level)];
    return meter;
}

@end

#pragma mark - Tool glyph

@interface ToolGlyphView ()
@property(nonatomic, strong) NSImage *icon;
@property(nonatomic, copy) NSString *initials;
@property(nonatomic) BOOL muted;
@end

static NSString *Initials(NSString *name) {
    NSArray *words = [[name componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if (words.count >= 2) return [NSString stringWithFormat:@"%@%@", [words[0] substringToIndex:1].uppercaseString, [words[1] substringToIndex:1].uppercaseString];
    NSString *word = words.firstObject ?: @"?";
    return [word substringToIndex:MIN(2u, word.length)];
}

@implementation ToolGlyphView

+ (instancetype)glyphForTool:(NSString *)identifier name:(NSString *)name size:(CGFloat)size muted:(BOOL)muted {
    ToolGlyphView *view = [ToolGlyphView new];
    view.icon = muted ? nil : ToolIconForIdentifier(identifier);
    view.initials = Initials(name ?: identifier ?: @"?");
    view.muted = muted;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[view.widthAnchor constraintEqualToConstant:size], [view.heightAnchor constraintEqualToConstant:size]]];
    view.accessibilityElement = NO;
    return view;
}

- (void)drawRect:(NSRect)rect {
    CGFloat side = self.bounds.size.width;
    CGFloat radius = side * 0.26;
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:radius yRadius:radius];
    if (self.icon) {
        [Hex(0xf7f7f9, 1) setFill];
        [tile fill];
        [ThemeHairlineColor() setStroke];
        [tile stroke];
        CGFloat inset = side * 0.18;
        [self.icon drawInRect:NSInsetRect(self.bounds, inset, inset) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        return;
    }
    if (self.muted) {
        CGFloat dash[2] = {3, 2};
        [tile setLineDash:dash count:2 phase:0];
        [[ThemeFaintColor() colorWithAlphaComponent:0.6] setStroke];
        [tile stroke];
    } else {
        [ToneFillColor(ToneNeutral) setFill];
        [tile fill];
        [ThemeHairlineColor() setStroke];
        [tile stroke];
    }
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:side * 0.4 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: self.muted ? ThemeFaintColor() : ThemeTextColor(),
    };
    NSSize size = [self.initials sizeWithAttributes:attributes];
    [self.initials drawAtPoint:NSMakePoint((side - size.width) / 2, (side - size.height) / 2) withAttributes:attributes];
}

@end

#pragma mark - Pressable

@interface PressableView ()
@property(nonatomic) BOOL hovered;
@property(nonatomic) BOOL pressed;
@end

@implementation PressableView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityButtonRole;
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}

- (void)mouseEntered:(NSEvent *)event { self.hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovered = NO; self.pressed = NO; self.needsDisplay = YES; }
- (void)mouseDown:(NSEvent *)event { self.pressed = YES; self.needsDisplay = YES; }

- (void)mouseUp:(NSEvent *)event {
    BOOL inside = NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
    self.pressed = NO;
    self.needsDisplay = YES;
    if (inside && self.onPress) self.onPress();
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    self.needsDisplay = YES;
}

- (BOOL)acceptsFirstResponder { return self.onPress != nil; }
- (BOOL)canBecomeKeyView { return self.onPress != nil; }
- (BOOL)becomeFirstResponder { self.needsDisplay = YES; return YES; }
- (BOOL)resignFirstResponder { self.needsDisplay = YES; return YES; }

- (void)keyDown:(NSEvent *)event {
    if ([event.charactersIgnoringModifiers isEqual:@" "] || [event.charactersIgnoringModifiers isEqual:@"\r"]) {
        if (self.onPress) self.onPress();
        return;
    }
    [super keyDown:event];
}

- (BOOL)accessibilityPerformPress {
    if (!self.onPress) return NO;
    self.onPress();
    return YES;
}

- (void)drawRect:(NSRect)rect {
    NSColor *fill = self.selected ? ThemeSelectionColor() : (self.hovered && self.onPress ? (self.pressed ? ThemeSelectionColor() : ThemeHoverColor()) : nil);
    if (fill) {
        [fill setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.cornerRadius yRadius:self.cornerRadius] fill];
    }
    if (self.window.firstResponder == self) {
        [[NSColor.keyboardFocusIndicatorColor colorWithAlphaComponent:0.6] setStroke];
        NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1.5, 1.5) xRadius:MAX(2, self.cornerRadius - 1) yRadius:MAX(2, self.cornerRadius - 1)];
        ring.lineWidth = 2;
        [ring stroke];
    }
}

@end

#pragma mark - Sections and pages

NSView *SectionHeader(NSString *title, NSString *caption, NSView *action) {
    NSStackView *text = VStack(2, @[Label(title, 13, NSFontWeightSemibold, ThemeTextColor())]);
    if (caption.length) [text addArrangedSubview:Label(caption, 11.5, NSFontWeightRegular, ThemeFaintColor())];
    NSStackView *row = HStack(12, @[text]);
    row.alignment = NSLayoutAttributeBottom;
    if (action) {
        [row addArrangedSubview:Spacer()];
        [row addArrangedSubview:action];
    }
    row.edgeInsets = NSEdgeInsetsMake(0, 4, 0, 4);
    return row;
}

NSView *SectionWithHeader(NSView *header, NSView *body) {
    NSStackView *section = VStack(10, @[]);
    FillWidth(header, section);
    FillWidth(body, section);
    return section;
}

@implementation PageScrollView {
    NSStackView *_column;
}

- (instancetype)initWithMaxWidth:(CGFloat)maxWidth { return [self initWithMaxWidth:maxWidth inset:32]; }

- (instancetype)initWithMaxWidth:(CGFloat)maxWidth inset:(CGFloat)inset {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.hasVerticalScroller = YES;
        self.autohidesScrollers = YES;
        self.drawsBackground = NO;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        FlippedView *document = [FlippedView new];
        document.translatesAutoresizingMaskIntoConstraints = NO;
        self.documentView = document;
        _column = VStack(28, @[]);
        [document addSubview:_column];
        NSLayoutConstraint *fill = [_column.widthAnchor constraintEqualToAnchor:document.widthAnchor constant:-2 * inset];
        fill.priority = NSLayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            [document.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [document.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [document.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_column.centerXAnchor constraintEqualToAnchor:document.centerXAnchor],
            [_column.widthAnchor constraintLessThanOrEqualToConstant:maxWidth],
            [_column.widthAnchor constraintLessThanOrEqualToAnchor:document.widthAnchor constant:-2 * inset],
            fill,
            [_column.topAnchor constraintEqualToAnchor:document.topAnchor constant:MIN(26, inset)],
            [_column.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-30],
        ]];
    }
    return self;
}

- (NSStackView *)column { return _column; }

- (void)setSections:(NSArray<NSView *> *)sections {
    for (NSView *view in _column.arrangedSubviews) { [_column removeArrangedSubview:view]; [view removeFromSuperview]; }
    for (NSView *view in sections) FillWidth(view, _column);
}

@end
