#import "WelcomeWindowController.h"
#import "Theme.h"
#import "BrandMark.h"

@implementation WelcomeWindowController {
    void (^_completion)(BOOL);
}

- (instancetype)initWithCloudAvailable:(BOOL)available completion:(void (^)(BOOL))completion {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 660)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        _completion = [completion copy];
        window.title = @"Welcome to DevCloud";
        window.backgroundColor = ThemeWindowColor();
        [window center];
        PageScrollView *page = [[PageScrollView alloc] initWithMaxWidth:500 inset:32];
        Pin(page, window.contentView, NSEdgeInsetsZero);
        NSImageView *icon = [NSImageView imageViewWithImage:DevCloudAppIconImage(64)];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.accessibilityLabel = @"DevCloud";
        [icon.widthAnchor constraintEqualToConstant:64].active = YES;
        [icon.heightAnchor constraintEqualToConstant:64].active = YES;
        NSStackView *intro = VStack(12, @[icon, Label(@"Your setup, remembered.", 28, NSFontWeightSemibold, ThemeTextColor())]);
        FillWidth(WrappingLabel(@"See your development tools, track changes, and keep an inventory copy off this Mac.", 15, ThemeSubColor()), intro);
        NSView *local = [self option:@"Start on this Mac" body:@"Find tools and versions with a read-only scan. No account needed; nothing is uploaded."
            button:PushButton(@"Scan This Mac", YES, self, @selector(scan:))];
        NSMutableArray *sections = [NSMutableArray arrayWithObjects:intro, local, nil];
        if (available) [sections addObject:[self option:@"Connect your account" body:@"Sign in with GitHub in your browser to access inventory backups. Uploads stay under your control."
            button:PushButton(@"Sign In with GitHub…", NO, self, @selector(signIn:))]];
        else [sections addObject:WrappingLabel(@"Cloud sign-in is unavailable in this build. Local scans and snapshots work without it.", 13, ThemeSubColor())];
        [sections addObject:WrappingLabel(@"Inventory only. Settings, secrets and files are not backed up or restored.", 13, ThemeSubColor())];
        [page setSections:sections];
    }
    return self;
}

- (NSView *)option:(NSString *)title body:(NSString *)body button:(NSButton *)button {
    NSStackView *stack = VStack(12, @[Label(title, 16, NSFontWeightSemibold, ThemeTextColor())]);
    FillWidth(WrappingLabel(body, 13, ThemeSubColor()), stack);
    FillWidth(HStack(12, @[Spacer(), button]), stack);
    return PaddedPanel(stack, 24);
}

- (void)scan:(id)sender { [self finish:NO]; }
- (void)signIn:(id)sender { [self finish:YES]; }
- (void)finish:(BOOL)signIn {
    void (^completion)(BOOL) = _completion;
    [self close];
    if (completion) completion(signIn);
}
@end
