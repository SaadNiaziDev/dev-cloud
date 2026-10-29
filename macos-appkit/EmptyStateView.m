#import "EmptyStateView.h"
#import "BrandMark.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat IllustrationSize = 172;

@interface EmptyRingView : NSView
@property(nonatomic, strong) NSColor *tint;
@property(nonatomic) CGFloat fill;
@property(nonatomic) BOOL orbitDots;
@end

@implementation EmptyRingView
- (void)drawRect:(NSRect)rect {
    NSRect circle = NSInsetRect(self.bounds, 1, 1);
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:circle];
    [[self.tint colorWithAlphaComponent:self.fill] setFill];
    [path fill];
    [[self.tint colorWithAlphaComponent:self.fill + 0.06] setStroke];
    path.lineWidth = 1;
    [path stroke];
    if (!self.orbitDots) return;
    // The brand orbit: three nodes at the same angles as the app icon.
    CGFloat radius = circle.size.width / 2;
    NSPoint center = NSMakePoint(NSMidX(circle), NSMidY(circle));
    CGFloat angles[3] = {42, 168, 288};
    CGFloat sizes[3] = {9, 6, 6};
    for (int i = 0; i < 3; i++) {
        CGFloat radians = angles[i] * M_PI / 180;
        NSPoint point = NSMakePoint(center.x + radius * cos(radians), center.y + radius * sin(radians));
        [[self.tint colorWithAlphaComponent:i == 0 ? 0.75 : 0.35] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(point.x - sizes[i] / 2, point.y - sizes[i] / 2, sizes[i], sizes[i])] fill];
    }
}
@end

@interface EmptyBadgeView : NSView
@property(nonatomic, strong) NSColor *tint;
@property(nonatomic) BOOL showsAppIcon;
@end

@implementation EmptyBadgeView
- (void)drawRect:(NSRect)rect {
    if (self.showsAppIcon) {
        ContinuityDrawAppIcon(self.bounds);
        return;
    }
    NSRect circle = NSInsetRect(self.bounds, 8, 8);
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:circle];
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [self.tint colorWithAlphaComponent:0.45];
    shadow.shadowBlurRadius = 14;
    shadow.shadowOffset = NSMakeSize(0, -4);
    [shadow set];
    [self.tint setFill];
    [path fill];
    [NSGraphicsContext restoreGraphicsState];
    NSColor *light = [self.tint blendedColorWithFraction:0.35 ofColor:NSColor.whiteColor] ?: self.tint;
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:light endingColor:self.tint];
    [gradient drawInBezierPath:path angle:-90];
    [[NSColor colorWithWhite:1 alpha:0.25] setStroke];
    path.lineWidth = 1;
    [path stroke];
}
@end

@interface EmptyStateView ()
@property(nonatomic, strong) EmptyRingView *outerRing;
@property(nonatomic, strong) EmptyRingView *innerRing;
@property(nonatomic, strong) EmptyBadgeView *badge;
@property(nonatomic, strong) NSImageView *glyph;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *messageLabel;
@property(nonatomic, strong) NSButton *actionButton;
@property(nonatomic, strong) NSTextField *hintLabel;
@property(nonatomic, strong) NSStackView *stack;
@property(nonatomic, copy) NSString *shownTitle;
@end

@implementation EmptyStateView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self build];
    return self;
}

- (void)build {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *illustration = [NSView new];
    illustration.translatesAutoresizingMaskIntoConstraints = NO;
    illustration.wantsLayer = YES;
    self.outerRing = [self ring:IllustrationSize fill:0.05 in:illustration];
    self.outerRing.orbitDots = YES;
    self.innerRing = [self ring:IllustrationSize - 48 fill:0.09 in:illustration];
    self.badge = [EmptyBadgeView new];
    self.badge.translatesAutoresizingMaskIntoConstraints = NO;
    [illustration addSubview:self.badge];
    self.glyph = [NSImageView new];
    self.glyph.translatesAutoresizingMaskIntoConstraints = NO;
    self.glyph.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:30 weight:NSFontWeightSemibold];
    self.glyph.contentTintColor = NSColor.whiteColor;
    // The illustration is decorative; the title and message carry the meaning.
    for (NSView *view in @[illustration, self.glyph]) view.accessibilityElement = NO;
    [illustration addSubview:self.glyph];
    [NSLayoutConstraint activateConstraints:@[
        [illustration.widthAnchor constraintEqualToConstant:IllustrationSize],
        [illustration.heightAnchor constraintEqualToConstant:IllustrationSize],
        [self.badge.widthAnchor constraintEqualToConstant:96],
        [self.badge.heightAnchor constraintEqualToConstant:96],
        [self.badge.centerXAnchor constraintEqualToAnchor:illustration.centerXAnchor],
        [self.badge.centerYAnchor constraintEqualToAnchor:illustration.centerYAnchor],
        [self.glyph.centerXAnchor constraintEqualToAnchor:illustration.centerXAnchor],
        [self.glyph.centerYAnchor constraintEqualToAnchor:illustration.centerYAnchor constant:-1],
    ]];

    self.titleLabel = [NSTextField labelWithString:@""];
    self.titleLabel.font = [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold];
    self.titleLabel.accessibilityRole = NSAccessibilityStaticTextRole;
    self.titleLabel.alignment = NSTextAlignmentCenter;
    self.messageLabel = [NSTextField wrappingLabelWithString:@""];
    self.messageLabel.font = [NSFont systemFontOfSize:13];
    self.messageLabel.textColor = NSColor.secondaryLabelColor;
    self.messageLabel.alignment = NSTextAlignmentCenter;
    self.messageLabel.selectable = NO;
    self.actionButton = [NSButton buttonWithTitle:@"" target:self action:@selector(actionClicked:)];
    self.actionButton.controlSize = NSControlSizeLarge;
    self.actionButton.bezelStyle = NSBezelStylePush;
    self.actionButton.keyEquivalent = @"\r";
    self.hintLabel = [NSTextField labelWithString:@""];
    self.hintLabel.font = [NSFont systemFontOfSize:11];
    self.hintLabel.textColor = NSColor.tertiaryLabelColor;

    self.stack = [NSStackView stackViewWithViews:@[illustration, self.titleLabel, self.messageLabel, self.actionButton, self.hintLabel]];
    self.stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.stack.alignment = NSLayoutAttributeCenterX;
    self.stack.spacing = 8;
    [self.stack setCustomSpacing:22 afterView:illustration];
    [self.stack setCustomSpacing:20 afterView:self.messageLabel];
    [self.stack setCustomSpacing:10 afterView:self.actionButton];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-24],
        [self.stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:32],
        [self.messageLabel.widthAnchor constraintLessThanOrEqualToConstant:400],
    ]];
}

- (EmptyRingView *)ring:(CGFloat)size fill:(CGFloat)fill in:(NSView *)container {
    EmptyRingView *ring = [EmptyRingView new];
    ring.fill = fill;
    ring.wantsLayer = YES;
    ring.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:ring];
    [NSLayoutConstraint activateConstraints:@[
        [ring.widthAnchor constraintEqualToConstant:size],
        [ring.heightAnchor constraintEqualToConstant:size],
        [ring.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [ring.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    ]];
    return ring;
}

- (void)showSymbol:(NSString *)symbol tint:(NSColor *)tint title:(NSString *)title message:(NSString *)message action:(NSString *)action hint:(NSString *)hint busy:(BOOL)busy {
    for (EmptyRingView *ring in @[self.outerRing, self.innerRing]) { ring.tint = tint; ring.needsDisplay = YES; }
    self.badge.tint = tint;
    self.badge.showsAppIcon = symbol == nil;
    self.badge.needsDisplay = YES;
    self.glyph.image = symbol ? [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title] : nil;
    self.glyph.hidden = symbol == nil;
    self.titleLabel.stringValue = title ?: @"";
    self.messageLabel.stringValue = message ?: @"";
    self.actionButton.title = action ?: @"";
    self.actionButton.hidden = action == nil;
    self.hintLabel.stringValue = hint ?: @"";
    self.hintLabel.hidden = hint.length == 0;
    [self setPulsing:busy];

    BOOL reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    if (![self.shownTitle isEqual:title] && !reduceMotion) {
        self.stack.alphaValue = 0;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.28;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            self.stack.animator.alphaValue = 1;
        }];
    }
    self.shownTitle = title;
}

- (void)setPulsing:(BOOL)pulsing {
    NSArray *rings = @[self.innerRing, self.outerRing];
    if (!pulsing || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        for (EmptyRingView *ring in rings) [ring.layer removeAnimationForKey:@"pulse"];
        return;
    }
    [rings enumerateObjectsUsingBlock:^(EmptyRingView *ring, NSUInteger index, BOOL *stop) {
        if ([ring.layer animationForKey:@"pulse"]) return;
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
        pulse.fromValue = @1;
        pulse.toValue = @0.25;
        pulse.duration = 0.9;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        pulse.beginTime = CACurrentMediaTime() + index * 0.3;
        pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [ring.layer addAnimation:pulse forKey:@"pulse"];
    }];
}

- (void)actionClicked:(id)sender {
    if (self.onAction) self.onAction();
}

@end
