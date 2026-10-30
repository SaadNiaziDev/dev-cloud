#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, Tone) { ToneNeutral, ToneGreen, ToneAmber, ToneRed, ToneBlue };

// Palette: macOS dark values from the design, with light equivalents.
NSColor *ThemeWindowColor(void);
NSColor *ThemeSidebarColor(void);
NSColor *ThemePanelColor(void);
NSColor *ThemeHairlineColor(void);
NSColor *ThemeHoverColor(void);
NSColor *ThemeSelectionColor(void);
NSColor *ThemeWellColor(void);
NSColor *ThemeTextColor(void);
NSColor *ThemeSubColor(void);
NSColor *ThemeFaintColor(void);
NSColor *ToneColor(Tone tone);
NSColor *ToneFillColor(Tone tone);

// Motion. Strong ease-out for anything entering or answering the user; ease-in-out
// for on-screen movement. Never ease-in. UI motion stays under 300 ms, exits are
// faster than entrances, and keyboard actions never animate.
CAMediaTimingFunction *EaseOut(void);
CAMediaTimingFunction *EaseInOut(void);
BOOL ReduceMotion(void);
// Scales a view to 0.97 while pressed, around its centre.
void AnimatePress(NSView *view, BOOL pressed);
// Fades views in from `offset` points below, `stagger` seconds apart.
// Reduce Motion keeps the fade and drops the movement.
void AnimateIn(NSArray<NSView *> *views, CGFloat offset, NSTimeInterval stagger);
// Fades a view out `offset` points downward, then runs `completion`.
void AnimateOut(NSView *view, CGFloat offset, void (^completion)(void));

NSFont *ThemeFont(CGFloat size, NSFontWeight weight);
NSFont *ThemeMono(CGFloat size);

NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color);
NSTextField *MonoLabel(NSString *text, CGFloat size, NSColor *color);
NSTextField *WrappingLabel(NSString *text, CGFloat size, NSColor *color);
NSStackView *VStack(CGFloat spacing, NSArray<NSView *> *views);
NSStackView *HStack(CGFloat spacing, NSArray<NSView *> *views);
NSImageView *SymbolView(NSString *name, CGFloat size, NSFontWeight weight, NSColor *tint);
NSView *Hairline(void);
NSView *Spacer(void);
NSButton *PushButton(NSString *title, BOOL primary, id target, SEL action);
NSButton *LinkButton(NSString *title, id target, SEL action);
NSSwitch *Switch(BOOL on, NSControlSize size, id target, SEL action);
void Pin(NSView *view, NSView *container, NSEdgeInsets insets);
void FillWidth(NSView *view, NSStackView *stack);
NSString *RelativeDate(NSDate *date);

@interface FlippedView : NSView
@end

// Rounded surface with a faint fill and a hairline border.
@interface PanelView : NSView
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic, strong) NSColor *fill;
@property(nonatomic, strong) NSColor *border;
@end

// A panel whose rows are separated by hairlines.
PanelView *ListPanel(NSArray<NSView *> *rows);
// A panel with `content` inset by `inset` on every side.
PanelView *PaddedPanel(NSView *content, CGFloat inset);

@interface PillView : NSView
+ (instancetype)pill:(NSString *)text tone:(Tone)tone dot:(BOOL)dot;
@end

@interface StatusDot : NSView
+ (instancetype)dotWithTone:(Tone)tone;
@end

// A thin rounded track filled to `value` (0–1) in blue.
@interface ProgressBar : NSView
+ (instancetype)barWithHeight:(CGFloat)height;
@property(nonatomic) double value;
@end

// Three ascending bars: how directly a version was read.
@interface ConfidenceMeter : NSView
+ (instancetype)meterWithLevel:(NSInteger)level showLabel:(BOOL)showLabel;
@end
NSString *ConfidenceName(NSInteger level);

// A tool's bundled logo on a light tile, or its initials.
@interface ToolGlyphView : NSView
+ (instancetype)glyphForTool:(NSString *)identifier name:(NSString *)name size:(CGFloat)size muted:(BOOL)muted;
@end

// Highlights on hover and runs `onPress` on click, Space, Return, or VoiceOver press.
@interface PressableView : NSView
@property(nonatomic, copy) void (^onPress)(void);
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) BOOL selected;
@end

NSView *SectionHeader(NSString *title, NSString *caption, NSView *action);
NSView *SectionWithHeader(NSView *header, NSView *body);

// A vertically scrolling page whose column is centred and capped at `maxWidth`.
@interface PageScrollView : NSScrollView
- (instancetype)initWithMaxWidth:(CGFloat)maxWidth;
- (instancetype)initWithMaxWidth:(CGFloat)maxWidth inset:(CGFloat)inset;
@property(nonatomic, readonly) NSStackView *column;
- (void)setSections:(NSArray<NSView *> *)sections;
@end
