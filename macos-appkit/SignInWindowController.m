#import "SignInWindowController.h"
#import "BrandMark.h"
#import "CloudAccount.h"
#import "Theme.h"

@implementation SignInWindowController {
    CloudAccount *_account;
    PageScrollView *_page;
    CloudState _shownState;
}

- (instancetype)initWithAccount:(CloudAccount *)account {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 500)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        _account = account;
        _shownState = account.state;
        window.title = @"Sign In to DevCloud";
        window.backgroundColor = ThemeWindowColor();
        [window center];
        _page = [[PageScrollView alloc] initWithMaxWidth:480 inset:32];
        Pin(_page, window.contentView, NSEdgeInsetsZero);
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged:) name:CloudAccountDidChangeNotification object:account];
        [self rebuild];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)accountChanged:(NSNotification *)notification { [self rebuild]; }

- (void)rebuild {
    NSImageView *icon = [NSImageView imageViewWithImage:DevCloudAppIconImage(64)];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.accessibilityLabel = @"DevCloud";
    [icon.widthAnchor constraintEqualToConstant:64].active = YES;
    [icon.heightAnchor constraintEqualToConstant:64].active = YES;
    NSStackView *intro = VStack(12, @[icon, Label(@"Your setup, remembered.", 28, NSFontWeightSemibold, ThemeTextColor())]);
    FillWidth(WrappingLabel(@"Sign in to see your tools, back them up, and set up a new Mac from your backup.", 15, ThemeSubColor()), intro);

    NSView *card = nil;
    switch (_account.state) {
        case CloudUnavailable: card = [self unavailable]; break;
        case CloudSignedOut: card = [self signedOut]; break;
        case CloudSigningIn: card = [self signingIn]; break;
        case CloudSignedIn: card = [self finishing]; break;
    }
    NSMutableArray *sections = [NSMutableArray arrayWithObjects:intro, card, nil];
    if (_account.errorMessage) [sections addObject:WrappingLabel(_account.errorMessage, 13, NSColor.systemOrangeColor)];
    [sections addObject:WrappingLabel(@"DevCloud reads tool names and versions only. Settings, secrets and source code never leave this Mac.", 12, ThemeFaintColor())];
    [_page setSections:sections];
    // The code card is the one new thing on screen; other changes are quiet swaps.
    if (_account.state == CloudSigningIn && _shownState != CloudSigningIn) AnimateIn(@[card], 8, 0);
    _shownState = _account.state;
}

- (NSView *)panel:(NSArray<NSView *> *)views {
    NSStackView *stack = VStack(14, @[]);
    for (NSView *view in views) FillWidth(view, stack);
    return PaddedPanel(stack, 24);
}

- (NSView *)unavailable {
    NSTextField *title = Label(@"This copy can’t sign in", 16, NSFontWeightSemibold, ThemeTextColor());
    NSTextField *body = WrappingLabel(@"It was built without a DevCloud cloud address, so it can’t be used. Download DevCloud from its GitHub releases page.", 13, ThemeSubColor());
    return [self panel:@[title, body, HStack(8, @[Spacer(), PushButton(@"Quit", NO, NSApp, @selector(terminate:))])]];
}

- (NSView *)signedOut {
    NSButton *signIn = PushButton(_account.busy ? @"Starting…" : @"Sign In with GitHub…", YES, self, @selector(signIn:));
    signIn.enabled = !_account.busy;
    NSTextField *title = Label(@"Sign in to continue", 16, NSFontWeightSemibold, ThemeTextColor());
    NSTextField *body = WrappingLabel(@"Sign-in happens in your browser. The app receives only a session, kept in your Keychain.", 13, ThemeSubColor());
    return [self panel:@[title, body, HStack(8, @[Spacer(), PushButton(@"Quit", NO, NSApp, @selector(terminate:)), signIn])]];
}

- (NSView *)signingIn {
    if (!_account.userCode) return [self finishing];
    NSTextField *code = Label(_account.userCode, 30, NSFontWeightMedium, ThemeTextColor());
    code.font = [NSFont monospacedSystemFontOfSize:30 weight:NSFontWeightMedium];
    code.selectable = YES;
    code.accessibilityLabel = [@"Sign-in code " stringByAppendingString:[[_account.userCode componentsSeparatedByString:@"-"] componentsJoinedByString:@" "]];
    NSString *expiry = [NSDateFormatter localizedStringFromDate:_account.codeExpiry ?: NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
    NSTextField *title = Label(@"Confirm this code in your browser", 16, NSFontWeightSemibold, ThemeTextColor());
    NSTextField *body = WrappingLabel(@"Check the code matches, then approve. Never approve a code someone sent you.", 13, ThemeSubColor());
    NSStackView *actions = HStack(8, @[Label([NSString stringWithFormat:@"Expires at %@", expiry], 12, NSFontWeightRegular, ThemeFaintColor()), Spacer(),
                                       PushButton(@"Cancel", NO, self, @selector(cancel:)), PushButton(@"Open Browser Again", NO, self, @selector(openBrowser:))]);
    return [self panel:@[title, code, body, actions]];
}

- (NSView *)finishing {
    NSProgressIndicator *spinner = [NSProgressIndicator new];
    spinner.style = NSProgressIndicatorStyleSpinning;
    spinner.controlSize = NSControlSizeSmall;
    [spinner startAnimation:nil];
    return [self panel:@[HStack(10, @[spinner, Label(@"Finishing sign-in…", 14, NSFontWeightMedium, ThemeTextColor()), Spacer()])]];
}

- (void)signIn:(id)sender { [_account beginSignIn]; }
- (void)cancel:(id)sender { [_account cancelSignIn]; }
- (void)openBrowser:(id)sender { [_account openVerificationPage]; }
@end
