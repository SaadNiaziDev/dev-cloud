#import "BrandMark.h"

// The mark: this Mac at the centre, its tools in orbit. The upper-right node is
// the active installation, so it is solid; the others are rings.
typedef struct {
    NSPoint center;
    CGFloat orbit;
    CGFloat stroke;
    CGFloat node;
} MarkGeometry;

// Small renderings drop detail so the shape survives at 16 and 32 pixels.
static MarkGeometry Geometry(NSRect rect, BOOL small) {
    CGFloat side = MIN(rect.size.width, rect.size.height);
    return small
        ? (MarkGeometry){NSMakePoint(NSMidX(rect), NSMidY(rect)), side * 0.32, side * 0.12, side * 0.15}
        : (MarkGeometry){NSMakePoint(NSMidX(rect), NSMidY(rect)), side * 0.34, side * 0.075, side * 0.11};
}

static NSPoint NodeCenter(MarkGeometry g, CGFloat degrees) {
    CGFloat radians = degrees * M_PI / 180.0;
    return NSMakePoint(g.center.x + g.orbit * cos(radians), g.center.y + g.orbit * sin(radians));
}

static const CGFloat NodeAngles[3] = {42, 168, 288};

static NSBezierPath *OrbitPath(MarkGeometry g) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat gap = asin(MIN(1, (g.node + g.stroke * 0.55) / g.orbit)) * 180.0 / M_PI;
    for (int i = 0; i < 3; i++) {
        CGFloat start = NodeAngles[i] + gap;
        CGFloat end = NodeAngles[(i + 1) % 3] - gap + (i == 2 ? 360 : 0);
        NSBezierPath *arc = [NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:g.center radius:g.orbit startAngle:start endAngle:end];
        [path appendBezierPath:arc];
    }
    path.lineWidth = g.stroke;
    path.lineCapStyle = NSLineCapStyleRound;
    return path;
}

static NSBezierPath *Circle(NSPoint center, CGFloat radius) {
    return [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - radius, center.y - radius, radius * 2, radius * 2)];
}

static NSBezierPath *RingNode(NSPoint center, CGFloat radius) {
    NSBezierPath *path = Circle(center, radius);
    [path appendBezierPath:Circle(center, radius * 0.46)];
    path.windingRule = NSWindingRuleEvenOdd;
    return path;
}

void ContinuityDrawMark(NSRect rect) {
    MarkGeometry g = Geometry(rect, NO);
    [OrbitPath(g) stroke];
    [Circle(g.center, g.node * 0.8) fill];
    [Circle(NodeCenter(g, NodeAngles[0]), g.node * 1.12) fill];
    for (int i = 1; i < 3; i++) [RingNode(NodeCenter(g, NodeAngles[i]), g.node) fill];
}

static NSColor *RGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [NSColor colorWithSRGBRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a];
}

static void WithShadow(NSColor *color, CGFloat blur, NSSize offset, void (^draw)(void)) {
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = color;
    shadow.shadowBlurRadius = blur;
    shadow.shadowOffset = offset;
    [shadow set];
    draw();
    [NSGraphicsContext restoreGraphicsState];
}

void ContinuityDrawAppIcon(NSRect rect) {
    CGFloat size = MIN(rect.size.width, rect.size.height);
    // Apple's icon grid: an 824/1024 rounded square centred on the canvas.
    NSRect tile = NSInsetRect(rect, size * 100.0 / 1024.0, size * 100.0 / 1024.0);
    tile.origin.y += size * 0.01;
    CGFloat radius = tile.size.width * 0.2237;
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:tile xRadius:radius yRadius:radius];

    WithShadow([NSColor colorWithWhite:0 alpha:0.32], size * 0.03, NSMakeSize(0, -size * 0.012), ^{
        [RGB(62, 92, 235, 1) set];
        [shape fill];
    });

    NSGradient *base = [[NSGradient alloc] initWithColorsAndLocations:
        RGB(92, 156, 255, 1), 0.0,
        RGB(76, 98, 245, 1), 0.55,
        RGB(102, 60, 224, 1), 1.0, nil];
    [base drawInBezierPath:shape angle:-90];

    [NSGraphicsContext saveGraphicsState];
    [shape addClip];
    NSGradient *glow = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:1 alpha:0.34] endingColor:[NSColor colorWithWhite:1 alpha:0]];
    [glow drawFromCenter:NSMakePoint(NSMidX(tile) - tile.size.width * 0.18, NSMaxY(tile) - tile.size.height * 0.05) radius:0
                toCenter:NSMakePoint(NSMidX(tile) - tile.size.width * 0.18, NSMaxY(tile) - tile.size.height * 0.05) radius:tile.size.width * 0.85
                 options:0];
    NSGradient *shade = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:0 alpha:0] endingColor:[NSColor colorWithWhite:0 alpha:0.16]];
    [shade drawInRect:NSMakeRect(tile.origin.x, tile.origin.y, tile.size.width, tile.size.height * 0.45) angle:-90];
    [NSGraphicsContext restoreGraphicsState];

    NSBezierPath *rim = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(tile, size * 0.002, size * 0.002) xRadius:radius yRadius:radius];
    rim.lineWidth = MAX(1, size * 0.004);
    [[NSColor colorWithWhite:1 alpha:0.22] setStroke];
    [rim stroke];

    BOOL small = size <= 40;
    MarkGeometry g = Geometry(NSInsetRect(tile, tile.size.width * (small ? 0.12 : 0.15), tile.size.width * (small ? 0.12 : 0.15)), small);
    WithShadow([NSColor colorWithRed:0.08 green:0.05 blue:0.35 alpha:0.45], size * 0.022, NSMakeSize(0, -size * 0.012), ^{
        [[NSColor colorWithWhite:1 alpha:0.9] setStroke];
        [OrbitPath(g) stroke];
        [[NSColor whiteColor] setFill];
        [Circle(g.center, g.node * 0.8) fill];
        for (int i = 1; i < 3; i++) {
            NSPoint center = NodeCenter(g, NodeAngles[i]);
            [(small ? Circle(center, g.node) : RingNode(center, g.node)) fill];
        }
    });
    NSBezierPath *active = Circle(NodeCenter(g, NodeAngles[0]), g.node * 1.12);
    WithShadow([NSColor colorWithRed:0.55 green:0.92 blue:1 alpha:0.9], size * 0.05, NSZeroSize, ^{
        [[NSColor whiteColor] setFill];
        [active fill];
    });
    NSGradient *accent = [[NSGradient alloc] initWithStartingColor:[NSColor whiteColor] endingColor:RGB(168, 236, 255, 1)];
    [accent drawInBezierPath:active angle:-90];
}

NSImage *ContinuityMenuBarImage(void) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor set];
        ContinuityDrawMark(NSInsetRect(rect, 0.5, 0.5));
        return YES;
    }];
    image.template = YES;
    image.accessibilityDescription = @"Continuity";
    return image;
}

NSImage *ContinuityAppIconImage(CGFloat size) {
    return [NSImage imageWithSize:NSMakeSize(size, size) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        ContinuityDrawAppIcon(rect);
        return YES;
    }];
}
