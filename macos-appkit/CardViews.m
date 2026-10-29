#import "CardViews.h"

NSColor *ToolColor(NSString *identifier) {
    NSDictionary<NSString *, NSArray<NSNumber *> *> *known = @{
        @"nodejs": @[@0.33, @0.69, @0.31], @"npm": @[@0.80, @0.22, @0.20], @"pnpm": @[@0.96, @0.62, @0.10],
        @"python": @[@0.22, @0.46, @0.78], @"pip": @[@0.22, @0.46, @0.78], @"uv": @[@0.55, @0.30, @0.85],
        @"git": @[@0.94, @0.32, @0.20], @"go": @[@0.00, @0.68, @0.85], @"rustc": @[@0.80, @0.42, @0.22],
        @"cargo": @[@0.80, @0.42, @0.22], @"docker": @[@0.11, @0.52, @0.93], @"gh": @[@0.35, @0.35, @0.40],
        @"brew": @[@0.85, @0.58, @0.18], @"swift": @[@0.98, @0.42, @0.20], @"java": @[@0.85, @0.25, @0.22],
        @"terraform": @[@0.48, @0.30, @0.88], @"kubectl": @[@0.20, @0.42, @0.90], @"vscode": @[@0.14, @0.54, @0.91],
        @"cursor": @[@0.25, @0.25, @0.28], @"xcode": @[@0.13, @0.56, @0.98], @"redis": @[@0.86, @0.22, @0.18],
    };
    NSArray<NSNumber *> *rgb = known[identifier];
    if (!rgb) {
        NSString *base = [identifier componentsSeparatedByString:@"@"].firstObject ?: identifier;
        if ([base isEqual:@"openjdk"]) rgb = known[@"java"];
        if ([base isEqual:@"postgresql"]) rgb = @[@0.20, @0.40, @0.65];
        if ([base isEqual:@"mariadb"] || [base isEqual:@"mysql"]) rgb = @[@0.00, @0.45, @0.60];
    }
    if (rgb) return [NSColor colorWithSRGBRed:rgb[0].doubleValue green:rgb[1].doubleValue blue:rgb[2].doubleValue alpha:1];
    NSUInteger hash = 5381;
    for (NSUInteger i = 0; i < identifier.length; i++) hash = hash * 33 + [identifier characterAtIndex:i];
    return [NSColor colorWithHue:(hash % 360) / 360.0 saturation:0.55 brightness:0.80 alpha:1];
}

#pragma mark - Card

@interface CardView ()
@property(nonatomic) BOOL hovering;
@end

@implementation CardView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        _cornerRadius = 14;
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    BOOL dark = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
    NSColor *fill = self.fill ?: (dark ? [NSColor colorWithWhite:1 alpha:0.055] : NSColor.whiteColor);
    NSColor *border = self.selected ? NSColor.controlAccentColor
        : (self.hovering ? [NSColor.controlAccentColor colorWithAlphaComponent:0.45]
                         : [NSColor colorWithWhite:dark ? 1 : 0 alpha:dark ? 0.09 : 0.08]);
    __block CGColorRef fillColor, borderColor;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        fillColor = fill.CGColor;
        borderColor = border.CGColor;
    }];
    self.layer.backgroundColor = fillColor;
    self.layer.borderColor = borderColor;
    self.layer.borderWidth = self.selected ? 2 : 1;
    self.layer.cornerRadius = self.cornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.shadowColor = NSColor.blackColor.CGColor;
    self.layer.shadowOpacity = dark ? 0 : (self.hovering ? 0.10 : 0.04);
    self.layer.shadowRadius = self.hovering ? 10 : 4;
    self.layer.shadowOffset = CGSizeMake(0, -2);
    self.layer.masksToBounds = NO;
}

- (void)setSelected:(BOOL)selected { _selected = selected; self.needsDisplay = YES; }
- (void)setFill:(NSColor *)fill { _fill = fill; self.needsDisplay = YES; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    if (!self.interactive) return;
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect | NSTrackingCursorUpdate owner:self userInfo:nil]];
}

- (void)mouseEntered:(NSEvent *)event { self.hovering = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event { self.hovering = NO; self.needsDisplay = YES; }
- (void)cursorUpdate:(NSEvent *)event { if (self.interactive) [NSCursor.pointingHandCursor set]; }

- (BOOL)acceptsFirstResponder { return self.interactive && self.onPress != nil; }
- (BOOL)canBecomeKeyView { return self.acceptsFirstResponder; }
- (NSRect)focusRingMaskBounds { return self.bounds; }
- (void)drawFocusRingMask {
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:self.cornerRadius yRadius:self.cornerRadius] fill];
}
- (void)keyDown:(NSEvent *)event {
    if (self.onPress && ([event.charactersIgnoringModifiers isEqual:@" "] || [event.charactersIgnoringModifiers isEqual:@"\r"])) self.onPress();
    else [super keyDown:event];
}
- (BOOL)accessibilityPerformPress {
    if (!self.onPress) return NO;
    self.onPress();
    return YES;
}

- (void)mouseUp:(NSEvent *)event {
    if (self.onPress && NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds)) self.onPress();
    else [super mouseUp:event];
}

@end

#pragma mark - Avatar

@implementation AvatarView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.accessibilityElement = NO;
    }
    return self;
}

- (void)setToolIdentifier:(NSString *)toolIdentifier { _toolIdentifier = [toolIdentifier copy]; self.needsDisplay = YES; }
- (void)setName:(NSString *)name { _name = [name copy]; self.needsDisplay = YES; }

- (void)drawRect:(NSRect)rect {
    NSColor *color = ToolColor(self.toolIdentifier ?: @"");
    CGFloat radius = self.bounds.size.width * 0.28;
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[color blendedColorWithFraction:0.25 ofColor:NSColor.whiteColor] endingColor:color];
    [gradient drawInBezierPath:shape angle:-90];
    NSArray *words = [[self.name ?: @"?" componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    NSString *initials = words.count > 1
        ? [[words[0] substringToIndex:1] stringByAppendingString:[words[1] substringToIndex:1]]
        : [(words.firstObject ?: @"?") substringToIndex:MIN(2u, [(NSString *)(words.firstObject ?: @"?") length])];
    initials = words.count > 1 ? initials.uppercaseString : initials.capitalizedString;
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:self.bounds.size.height * 0.4 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor,
    };
    NSSize size = [initials sizeWithAttributes:attributes];
    [initials drawAtPoint:NSMakePoint(NSMidX(self.bounds) - size.width / 2, NSMidY(self.bounds) - size.height / 2) withAttributes:attributes];
}

@end

#pragma mark - Pill

@interface PillView ()
@property(nonatomic, strong) NSTextField *label;
@end

@implementation PillView

+ (instancetype)pill:(NSString *)text tint:(NSColor *)tint {
    PillView *pill = [PillView new];
    pill.tint = tint;
    pill.text = text;
    return pill;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.label = [NSTextField labelWithString:@""];
        self.label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        self.label.translatesAutoresizingMaskIntoConstraints = NO;
        self.label.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:self.label];
        [NSLayoutConstraint activateConstraints:@[
            [self.label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
            [self.label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
            [self.label.topAnchor constraintEqualToAnchor:self.topAnchor constant:2],
            [self.label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],
        ]];
    }
    return self;
}

- (void)setText:(NSString *)text { _text = [text copy]; self.label.stringValue = text ?: @""; }
- (void)setTint:(NSColor *)tint { _tint = tint; self.label.textColor = tint; self.needsDisplay = YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    __block CGColorRef color;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{ color = [self.tint colorWithAlphaComponent:0.14].CGColor; }];
    self.layer.backgroundColor = color;
    self.layer.cornerRadius = 9;
    self.layer.cornerCurve = kCACornerCurveContinuous;
}

- (void)layout {
    [super layout];
    self.layer.cornerRadius = self.bounds.size.height / 2;
}

@end

#pragma mark - Tool card

@interface ToolCardItem ()
@property(nonatomic, strong) CardView *card;
@property(nonatomic, strong) AvatarView *avatar;
@property(nonatomic, strong) NSTextField *nameLabel;
@property(nonatomic, strong) NSTextField *kindLabel;
@property(nonatomic, strong) NSTextField *versionLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSStackView *chips;
@end

@implementation ToolCardItem

- (void)loadView {
    self.card = [CardView new];
    self.card.interactive = YES;
    self.card.translatesAutoresizingMaskIntoConstraints = YES;
    self.view = self.card;

    self.avatar = [AvatarView new];
    self.nameLabel = [self label:13 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.kindLabel = [self label:11 weight:NSFontWeightRegular color:NSColor.secondaryLabelColor];
    self.versionLabel = [self label:22 weight:NSFontWeightSemibold color:NSColor.labelColor];
    self.versionLabel.font = [NSFont monospacedDigitSystemFontOfSize:22 weight:NSFontWeightSemibold];
    self.statusLabel = [self label:11 weight:NSFontWeightMedium color:NSColor.secondaryLabelColor];
    self.chips = [NSStackView new];
    self.chips.spacing = 4;
    self.chips.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *view in @[self.avatar, self.nameLabel, self.kindLabel, self.versionLabel, self.statusLabel, self.chips]) [self.card addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [self.avatar.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:14],
        [self.avatar.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:14],
        [self.avatar.widthAnchor constraintEqualToConstant:34],
        [self.avatar.heightAnchor constraintEqualToConstant:34],
        [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.avatar.trailingAnchor constant:10],
        [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.card.trailingAnchor constant:-14],
        [self.nameLabel.topAnchor constraintEqualToAnchor:self.avatar.topAnchor constant:1],
        [self.kindLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
        [self.kindLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.card.trailingAnchor constant:-14],
        [self.kindLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:1],
        [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.avatar.leadingAnchor],
        [self.versionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.card.trailingAnchor constant:-14],
        [self.versionLabel.topAnchor constraintEqualToAnchor:self.avatar.bottomAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.avatar.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.card.trailingAnchor constant:-14],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.versionLabel.bottomAnchor constant:2],
        [self.chips.leadingAnchor constraintEqualToAnchor:self.avatar.leadingAnchor],
        [self.chips.trailingAnchor constraintLessThanOrEqualToAnchor:self.card.trailingAnchor constant:-14],
        [self.chips.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-14],
    ]];
}

- (NSTextField *)label:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (void)configureWithName:(NSString *)name identifier:(NSString *)identifier kind:(NSString *)kind version:(NSString *)version source:(NSString *)source otherVersions:(NSArray<NSString *> *)otherVersions active:(BOOL)active {
    self.avatar.toolIdentifier = identifier;
    self.avatar.name = name;
    self.nameLabel.stringValue = name;
    self.kindLabel.stringValue = kind;
    self.versionLabel.stringValue = version.length ? version : @"Version unknown";
    self.versionLabel.font = version.length ? [NSFont monospacedDigitSystemFontOfSize:22 weight:NSFontWeightSemibold] : [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
    self.versionLabel.textColor = version.length ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    self.statusLabel.stringValue = active ? [NSString stringWithFormat:@"● First on scan PATH · %@", source] : source;
    self.statusLabel.textColor = active ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
    for (NSView *view in self.chips.arrangedSubviews) { [self.chips removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSUInteger shown = MIN(otherVersions.count, 3u);
    for (NSUInteger i = 0; i < shown; i++) [self.chips addArrangedSubview:[PillView pill:otherVersions[i] tint:NSColor.secondaryLabelColor]];
    if (otherVersions.count > shown) [self.chips addArrangedSubview:[PillView pill:[NSString stringWithFormat:@"+%lu", (unsigned long)(otherVersions.count - shown)] tint:NSColor.secondaryLabelColor]];
    self.card.accessibilityElement = YES;
    self.card.accessibilityRole = NSAccessibilityButtonRole;
    self.card.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@%@", name, version.length ? version : @"version unknown", active ? @"first on scan PATH, " : @"", source];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    self.card.selected = selected;
}

@end
