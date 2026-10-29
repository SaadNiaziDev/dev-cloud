// UI test harness, compiled only by scripts/test-ui.sh with -DCONTINUITY_TESTING.
// It drives every page, sheet, and the menu bar dropdown in light and dark mode at
// the default and minimum window sizes, renders each to PNG, and fails on
// accessibility or layout problems.
#ifdef CONTINUITY_TESTING
#import <Cocoa/Cocoa.h>
#import "MainWindowController.h"
#import "StatusMenu.h"

// The harness lives for the whole test process, so its step blocks retain it.
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface UITestHarness : NSObject
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) MainWindowController *controller;
@property(nonatomic, copy) NSString *output;
@property(nonatomic, strong) NSMutableArray<NSString *> *failures;
@property(nonatomic, strong) NSMutableArray<dispatch_block_t> *steps;
@property(nonatomic) NSUInteger checked;
@end

@implementation UITestHarness

+ (void)load {
    NSString *output = NSProcessInfo.processInfo.environment[@"CONTINUITY_UI_OUT"];
    if (!output) return;
    static UITestHarness *harness;
    harness = [UITestHarness new];
    harness.output = output;
    harness.failures = [NSMutableArray array];
    harness.steps = [NSMutableArray array];
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [harness start]; });
    }];
}

- (void)start {
    for (NSWindow *window in NSApp.windows) {
        if ([window.windowController isKindOfClass:MainWindowController.class]) self.window = window;
    }
    self.controller = self.window.windowController;
    if (!self.controller) { [self fail:@"main window not found"]; [self finish]; return; }
    __block NSUInteger presses = 0;
    PressableView *probe = [PressableView new];
    probe.onPress = ^{ presses++; };
    if (![probe accessibilityPerformPress]) [self fail:@"pressable accessibility press was rejected"];
    NSEvent *space = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@" " charactersIgnoringModifiers:@" " isARepeat:NO keyCode:49];
    [probe keyDown:space];
    if (presses != 2) [self fail:@"pressable keyboard or accessibility action did not run"];

    NSString *mode = NSProcessInfo.processInfo.environment[@"CONTINUITY_UI_MODE"] ?: @"full";
    // Approved folders and opt-ins so every page has content; each change rescans the fixture.
    NSString *roots = NSProcessInfo.processInfo.environment[@"CONTINUITY_UI_ROOTS"];
    if (roots.length) {
        [self.steps addObject:^{
            ScanModel *model = self.controller.model;
            for (NSString *root in [roots componentsSeparatedByString:@":"]) [model addApprovedRoot:root];
            model.inspectMCP = YES;
            model.inspectEditorSettings = YES;
            model.inspectPathTools = YES;
        }];
        for (int wait = 0; wait < 8; wait++) [self.steps addObject:^{}];
    }
    NSArray *sizes = @[[NSValue valueWithSize:NSMakeSize(1180, 760)], [NSValue valueWithSize:self.window.minSize]];
    for (NSString *appearance in @[@"light", @"dark"]) {
        for (NSValue *size in sizes) {
            for (NSUInteger page = 0; page < PageCatalog().count; page++) {
                [self.steps addObject:^{
                    NSApp.appearance = [NSAppearance appearanceNamed:[appearance isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                    [self.window setContentSize:size.sizeValue];
                    [self.controller showPage:(Page)page];
                }];
                NSString *name = [NSString stringWithFormat:@"%@-%@-%lu-%@", mode, appearance, (unsigned long)size.sizeValue.width, [PageCatalog()[page][@"title"] lowercaseString]];
                [self.steps addObject:^{ [self capture:name]; }];
            }
        }
        [self.steps addObject:^{
            [self.window setContentSize:NSMakeSize(1180, 760)];
            [self.controller showTool:@"nodejs"];
        }];
        [self.steps addObject:^{ [self capture:[NSString stringWithFormat:@"%@-%@-tool-selected", mode, appearance]]; }];
        [self.steps addObject:^{
            NSSearchField *field = [[self.controller valueForKey:@"pages"][@(PageTools)] valueForKey:@"search"];
            field.stringValue = @"no-such-tool";
            [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:field];
        }];
        [self.steps addObject:^{
            [self capture:[NSString stringWithFormat:@"%@-%@-no-matches", mode, appearance]];
            NSSearchField *field = [[self.controller valueForKey:@"pages"][@(PageTools)] valueForKey:@"search"];
            field.stringValue = @"";
            [NSNotificationCenter.defaultCenter postNotificationName:NSControlTextDidChangeNotification object:field];
        }];
        for (NSString *sheet in @[@"exportReport:", @"approveWorkspace:"]) {
            [self.steps addObject:^{
                [self.controller showPage:PageOverview];
                [NSApp sendAction:NSSelectorFromString(sheet) to:self.controller from:nil];
            }];
            [self.steps addObject:^{
                NSWindow *attached = self.window.attachedSheet;
                NSString *name = [NSString stringWithFormat:@"%@-%@-sheet-%@", mode, appearance, [sheet substringToIndex:sheet.length - 1]];
                if (attached) {
                    [self audit:attached.contentView name:name];
                    [self save:attached name:name];
                    [self.window endSheet:attached returnCode:NSModalResponseCancel];
                } else if ([mode isEqual:@"demo"] || [sheet isEqual:@"approveWorkspace:"]) {
                    [self fail:[NSString stringWithFormat:@"%@: sheet did not open", name]];
                }
            }];
        }
        [self.steps addObject:^{
            StatusMenu *menu = [(NSObject *)NSApp.delegate valueForKey:@"statusMenu"];
            [menu show];
        }];
        [self.steps addObject:^{
            StatusMenu *menu = [(NSObject *)NSApp.delegate valueForKey:@"statusMenu"];
            NSString *name = [NSString stringWithFormat:@"%@-%@-menu-bar", mode, appearance];
            [self audit:menu.panel.contentView name:name];
            [self save:menu.panel name:name];
            [menu close];
        }];
    }
    [self.steps addObject:^{ NSApp.appearance = nil; }];
    [self next];
}

- (void)next {
    if (self.steps.count == 0) { [self finish]; return; }
    dispatch_block_t step = self.steps.firstObject;
    [self.steps removeObjectAtIndex:0];
    step();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC * 45 / 100), dispatch_get_main_queue(), ^{ [self next]; });
}

- (void)capture:(NSString *)name {
    [self.window layoutIfNeeded];
    [self audit:self.window.contentView name:name];
    [self save:self.window name:name];
}

- (void)save:(NSWindow *)window name:(NSString *)name {
    NSView *frame = window.contentView.superview ?: window.contentView;
    NSBitmapImageRep *rep = [frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![png writeToFile:[self.output stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]] atomically:YES]) {
        [self fail:[NSString stringWithFormat:@"%@: screenshot not written", name]];
    }
}

- (BOOL)visible:(NSView *)view {
    for (NSView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (ancestor.isHidden || ancestor.alphaValue < 0.01) return NO;
    }
    return view.window != nil && !NSIsEmptyRect(view.visibleRect);
}

- (void)audit:(NSView *)root name:(NSString *)name {
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    NSRect content = [root convertRect:root.bounds toView:nil];
    while (queue.count) {
        NSView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        [queue addObjectsFromArray:view.subviews];
        if (![self visible:view]) continue;
        self.checked++;
        if (view.hasAmbiguousLayout) [self fail:[NSString stringWithFormat:@"%@: ambiguous layout in %@ (in %@, %@)", name, view.className, view.superview.className, NSStringFromRect(view.frame)]];
        if ([view isKindOfClass:NSButton.class] && ![view isKindOfClass:NSSwitch.class]) {
            NSButton *button = (NSButton *)view;
            if (!button.title.length && !button.accessibilityLabel.length && !button.image.accessibilityDescription.length) {
                [self fail:[NSString stringWithFormat:@"%@: button %@ without an accessible name (in %@)", name, button.className, button.superview.className]];
            }
        }
        if ([view isKindOfClass:NSSwitch.class] && !view.accessibilityLabel.length) [self fail:[NSString stringWithFormat:@"%@: switch without a label", name]];
        if ([view isKindOfClass:NSImageView.class] && view.isAccessibilityElement) {
            NSImageView *image = (NSImageView *)view;
            if (image.image && !image.accessibilityLabel.length && !image.image.accessibilityDescription.length) {
                [self fail:[NSString stringWithFormat:@"%@: image without a description", name]];
            }
        }
        if ([view isKindOfClass:PressableView.class] && ((PressableView *)view).onPress && !view.accessibilityLabel.length) {
            [self fail:[NSString stringWithFormat:@"%@: clickable view without a label", name]];
        }
        if ([view isKindOfClass:NSTextField.class] && !view.enclosingScrollView.documentView) {
            NSRect frame = [view convertRect:view.bounds toView:nil];
            if (NSMaxX(frame) > NSMaxX(content) + 1 || NSMinX(frame) < NSMinX(content) - 1) {
                [self fail:[NSString stringWithFormat:@"%@: text “%@” extends outside the window", name, ((NSTextField *)view).stringValue]];
            }
        }
    }
    for (NSScrollView *scroll in [self all:NSScrollView.class in:root]) {
        if (![self visible:scroll]) continue;
        CGFloat width = scroll.contentView.bounds.size.width;
        if (scroll.documentView.frame.size.width > width + 1 && !scroll.hasHorizontalScroller && ![scroll.documentView isKindOfClass:NSTableView.class]) {
            [self fail:[NSString stringWithFormat:@"%@: content is wider than its scroll view", name]];
        }
    }
}

- (NSArray *)all:(Class)class in:(NSView *)root {
    NSMutableArray *found = [NSMutableArray array];
    if ([root isKindOfClass:class]) [found addObject:root];
    for (NSView *view in root.subviews) [found addObjectsFromArray:[self all:class in:view]];
    return found;
}

- (void)fail:(NSString *)message {
    if (![self.failures containsObject:message]) [self.failures addObject:message];
}

- (void)finish {
    NSString *summary = [NSString stringWithFormat:@"checked %lu views, %lu failures\n%@\n", (unsigned long)self.checked, (unsigned long)self.failures.count, [self.failures componentsJoinedByString:@"\n"]];
    [summary writeToFile:[self.output stringByAppendingPathComponent:@"report.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    fprintf(stderr, "%s", summary.UTF8String);
    exit(self.failures.count ? 1 : 0);
}

@end
#endif
