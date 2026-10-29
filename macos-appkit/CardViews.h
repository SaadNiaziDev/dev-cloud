#import <Cocoa/Cocoa.h>

// A stable accent colour per tool, so Node.js is always green, Python blue.
NSColor *ToolColor(NSString *identifier);

// Rounded surface with a hairline border, a hover lift, and a selected state.
@interface CardView : NSView
@property(nonatomic) BOOL selected;
@property(nonatomic) BOOL interactive;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic, strong) NSColor *fill;
@property(nonatomic, copy) void (^onPress)(void);
@end

// Rounded square with the tool's initials over its accent gradient.
@interface AvatarView : NSView
@property(nonatomic, copy) NSString *toolIdentifier;
@property(nonatomic, copy) NSString *name;
@end

// A capsule label, tinted.
@interface PillView : NSView
+ (instancetype)pill:(NSString *)text tint:(NSColor *)tint;
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) NSColor *tint;
@end

// One tool in the grid: avatar, name, the version that runs, and its other installs.
@interface ToolCardItem : NSCollectionViewItem
- (void)configureWithName:(NSString *)name
               identifier:(NSString *)identifier
                     kind:(NSString *)kind
                  version:(NSString *)version
                   source:(NSString *)source
            otherVersions:(NSArray<NSString *> *)otherVersions
                   active:(BOOL)active;
@end
