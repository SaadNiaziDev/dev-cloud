#import <Cocoa/Cocoa.h>

// A centred illustration, title, message, and optional action, in the style of
// first-run screens: tinted concentric rings around a glyph badge.
@interface EmptyStateView : NSView

@property(nonatomic, copy) void (^onAction)(void);

// `symbol` nil shows the app icon. `busy` pulses the rings (unless Reduce Motion is on).
- (void)showSymbol:(NSString *)symbol
              tint:(NSColor *)tint
             title:(NSString *)title
           message:(NSString *)message
            action:(NSString *)action
              hint:(NSString *)hint
              busy:(BOOL)busy;

@end
