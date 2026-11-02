#import "Theme.h"
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

#pragma mark - Motion

CAMediaTimingFunction *EaseOut(void) { return [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1]; }
CAMediaTimingFunction *EaseInOut(void) { return [CAMediaTimingFunction functionWithControlPoints:0.77 :0 :0.175 :1]; }
BOOL ReduceMotion(void) { return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion; }

static CABasicAnimation *Animation(NSString *keyPath, id from, id to, NSTimeInterval duration, CAMediaTimingFunction *timing) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:keyPath];
    animation.fromValue = from;
    animation.toValue = to;
    animation.duration = duration;
    animation.timingFunction = timing;
    return animation;
}

// AppKit anchors layers at their origin, so scale around the centre explicitly.
static CATransform3D CentredScale(NSView *view, CGFloat scale) {
    CGSize size = view.layer.bounds.size;
    CATransform3D transform = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0);
    transform = CATransform3DScale(transform, scale, scale, 1);
    return CATransform3DTranslate(transform, -size.width / 2, -size.height / 2, 0);
}

void AnimatePress(NSView *view, BOOL pressed) {
    if (ReduceMotion()) return;
    view.wantsLayer = YES;
    CALayer *layer = view.layer;
    NSValue *current = [NSValue valueWithCATransform3D:layer.presentationLayer ? layer.presentationLayer.transform : layer.transform];
    CATransform3D target = pressed ? CentredScale(view, 0.97) : CATransform3DIdentity;
    layer.transform = target;
    [layer addAnimation:Animation(@"transform", current, [NSValue valueWithCATransform3D:target], pressed ? 0.12 : 0.2, EaseOut()) forKey:@"press"];
}

void AnimateIn(NSArray<NSView *> *views, CGFloat offset, NSTimeInterval stagger) {
    CFTimeInterval now = CACurrentMediaTime();
    [views enumerateObjectsUsingBlock:^(NSView *view, NSUInteger index, BOOL *stop) {
        view.wantsLayer = YES;
        CFTimeInterval begin = now + index * stagger;
        CABasicAnimation *fade = Animation(@"opacity", @0, @1, 0.28, EaseOut());
        fade.beginTime = begin;
        fade.fillMode = kCAFillModeBackwards;
        [view.layer addAnimation:fade forKey:@"enter-fade"];
        if (ReduceMotion()) return;
        // Layer-backed views inside flipped parents keep a bottom-left layer origin.
        CGFloat dy = view.superview.isFlipped ? offset : -offset;
        CABasicAnimation *rise = Animation(@"transform", [NSValue valueWithCATransform3D:CATransform3DMakeTranslation(0, dy, 0)], [NSValue valueWithCATransform3D:CATransform3DIdentity], 0.28, EaseOut());
        rise.beginTime = begin;
        rise.fillMode = kCAFillModeBackwards;
        [view.layer addAnimation:rise forKey:@"enter-rise"];
    }];
}

void AnimateOut(NSView *view, CGFloat offset, void (^completion)(void)) {
    view.wantsLayer = YES;
    CGFloat dy = ReduceMotion() ? 0 : (view.superview.isFlipped ? offset : -offset);
    [CATransaction begin];
    [CATransaction setCompletionBlock:completion];
    CABasicAnimation *fade = Animation(@"opacity", @1, @0, 0.18, EaseOut());
    CABasicAnimation *sink = Animation(@"transform", [NSValue valueWithCATransform3D:CATransform3DIdentity], [NSValue valueWithCATransform3D:CATransform3DMakeTranslation(0, dy, 0)], 0.18, EaseOut());
    for (CABasicAnimation *animation in @[fade, sink]) {
        animation.fillMode = kCAFillModeForwards;
        animation.removedOnCompletion = NO;
    }
    [view.layer addAnimation:fade forKey:@"exit-fade"];
    [view.layer addAnimation:sink forKey:@"exit-sink"];
    [CATransaction commit];
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
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineSpacing = 3;
    label.attributedStringValue = [[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName: label.font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraph}];
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
    button.controlSize = NSControlSizeLarge;
    button.font = ThemeFont(13, NSFontWeightRegular);
    if (primary) {
        button.bezelColor = NSColor.controlAccentColor;
        button.keyEquivalent = @"\r";
    }
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:32].active = YES;
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
@end

@implementation StatusDot

+ (instancetype)dotWithTone:(Tone)tone {
    StatusDot *dot = [StatusDot new];
    dot.tone = tone;
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[dot.widthAnchor constraintEqualToConstant:8], [dot.heightAnchor constraintEqualToConstant:8]]];
    return dot;
}

- (void)drawRect:(NSRect)rect {
    [ToneColor(self.tone) setFill];
    [[NSBezierPath bezierPathWithOvalInRect:self.bounds] fill];
}

@end

@implementation ProgressBar {
    CALayer *_fill;
}

+ (instancetype)barWithHeight:(CGFloat)height {
    ProgressBar *bar = [ProgressBar new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [bar.heightAnchor constraintEqualToConstant:height].active = YES;
    bar.accessibilityElement = YES;
    bar.accessibilityRole = NSAccessibilityProgressIndicatorRole;
    bar.accessibilityLabel = @"Scan progress";
    bar.wantsLayer = YES;
    bar->_fill = [CALayer layer];
    bar->_fill.backgroundColor = NSColor.systemBlueColor.CGColor;
    bar->_fill.cornerRadius = height / 2;
    [bar.layer addSublayer:bar->_fill];
    return bar;
}

- (CGRect)fillFrame {
    CGRect bounds = self.bounds;
    bounds.size.width = MAX(bounds.size.height * 2, bounds.size.width * MAX(0.05, self.value));
    return bounds;
}

- (void)setValue:(double)value {
    _value = MIN(1, MAX(0, value));
    self.accessibilityValue = @(_value);
    // Progress glides to its new value instead of jumping.
    [CATransaction begin];
    [CATransaction setAnimationDuration:ReduceMotion() ? 0 : 0.3];
    [CATransaction setAnimationTimingFunction:EaseOut()];
    _fill.frame = [self fillFrame];
    [CATransaction commit];
}

- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.frame = [self fillFrame];
    [CATransaction commit];
}

- (void)drawRect:(NSRect)rect {
    CGFloat radius = self.bounds.size.height / 2;
    [ThemeHairlineColor() setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius] fill];
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
- (void)mouseExited:(NSEvent *)event {
    self.hovered = NO;
    if (self.pressed) AnimatePress(self, NO);
    self.pressed = NO;
    self.needsDisplay = YES;
}

- (void)mouseDown:(NSEvent *)event {
    self.pressed = YES;
    self.needsDisplay = YES;
    if (self.onPress) AnimatePress(self, YES);
}

- (void)mouseUp:(NSEvent *)event {
    BOOL inside = NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds);
    if (self.pressed) AnimatePress(self, NO);
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
