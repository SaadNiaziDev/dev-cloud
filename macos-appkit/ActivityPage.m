#import "Pages.h"

static NSString *DayLabel(NSDate *date) {
    NSCalendar *calendar = NSCalendar.currentCalendar;
    if ([calendar isDateInToday:date]) return @"Today";
    if ([calendar isDateInYesterday:date]) return @"Yesterday";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEEMMMd" options:0 locale:NSLocale.currentLocale];
    return [formatter stringFromDate:date];
}

// A line joining consecutive events on the timeline.
@interface TimelineRail : NSView
@end
@implementation TimelineRail
- (void)drawRect:(NSRect)rect {
    [ThemeHairlineColor() setFill];
    NSRectFillUsingOperation(NSMakeRect(NSMidX(self.bounds) - 0.5, 0, 1, self.bounds.size.height), NSCompositingOperationSourceOver);
}
@end

@implementation ActivityPage {
    PageScrollView *_scroll;
    NSSegmentedControl *_filter;
    NSArray<ActivityEvent *> *_events;
    NSString *_loadedKey;
}

- (instancetype)initWithHost:(id<PageHost>)host {
    self = [super initWithHost:host];
    if (self) {
        _scroll = [[PageScrollView alloc] initWithMaxWidth:760];
        Pin(_scroll, self, NSEdgeInsetsZero);
        _filter = [NSSegmentedControl segmentedControlWithLabels:@[@"All", @"Changes", @"Warnings", @"Scans"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(filterChanged:)];
        _filter.selectedSegment = 0;
        _filter.accessibilityLabel = @"Filter activity";
        _filter.translatesAutoresizingMaskIntoConstraints = NO;
        _events = @[];
    }
    return self;
}

- (NSString *)signature {
    return [NSString stringWithFormat:@"%p|%ld|%lu", self.model.report, (long)_filter.selectedSegment, (unsigned long)_events.count];
}

- (void)filterChanged:(id)sender { [self reload]; }

- (void)reload {
    [self loadEventsIfNeeded];
    [super reload];
}

// History can hold dozens of snapshots, so they are read off the main thread.
- (void)loadEventsIfNeeded {
    NSString *key = [NSString stringWithFormat:@"%p|%f", self.model.report, self.model.lastScanDate.timeIntervalSince1970];
    if ([key isEqual:_loadedKey] || self.model.scanning) return;
    _loadedKey = key;
    NSURL *directory = self.model.historyDirectory;
    NSDictionary *report = self.model.report;
    NSDate *lastScan = self.model.lastScanDate;
    __weak ActivityPage *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *events = LoadActivity(directory, report, lastScan);
        dispatch_async(dispatch_get_main_queue(), ^{
            ActivityPage *page = weakSelf;
            if (!page || ![page->_loadedKey isEqual:key]) return;
            page->_events = events;
            [page reload];
        });
    });
}

- (void)rebuild {
    NSInteger filter = _filter.selectedSegment;
    NSArray *kinds = @[[NSNull null], @(ActivityChange), @(ActivityWarning), @(ActivityScan)];
    NSArray *events = filter == 0 ? _events : [_events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind == %@", kinds[(NSUInteger)filter]]];

    NSStackView *bar = HStack(12, @[_filter, Spacer(), Label(@"Stored on this Mac only", 11.5, NSFontWeightRegular, ThemeFaintColor())]);
    NSMutableArray *sections = [NSMutableArray arrayWithObject:bar];
    if (!events.count) {
        NSTextField *empty = Label(self.model.report ? @"No activity of this type yet." : @"Activity appears after the first scan.", 12.5, NSFontWeightRegular, ThemeFaintColor());
        empty.alignment = NSTextAlignmentCenter;
        NSStackView *wrap = VStack(0, @[empty]);
        wrap.alignment = NSLayoutAttributeCenterX;
        wrap.edgeInsets = NSEdgeInsetsMake(60, 0, 60, 0);
        [sections addObject:wrap];
    }
    NSMutableOrderedSet *days = [NSMutableOrderedSet orderedSet];
    for (ActivityEvent *event in events) [days addObject:DayLabel(event.date)];
    for (NSString *day in days) {
        NSArray *dayEvents = [events filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ActivityEvent *e, id b) { return [DayLabel(e.date) isEqual:day]; }]];
        NSStackView *list = VStack(0, @[]);
        [dayEvents enumerateObjectsUsingBlock:^(ActivityEvent *event, NSUInteger index, BOOL *stop) {
            FillWidth([self eventRow:event last:index == dayEvents.count - 1], list);
        }];
        NSStackView *section = VStack(12, @[Label(day.uppercaseString, 11, NSFontWeightSemibold, ThemeFaintColor())]);
        FillWidth(list, section);
        [sections addObject:section];
    }
    [_scroll setSections:sections];
}

- (NSView *)eventRow:(ActivityEvent *)event last:(BOOL)last {
    NSArray *styles = @[@[@"smallcircle.filled.circle", @(ToneBlue)], @[@"arrow.clockwise", @(ToneGreen)], @[@"exclamationmark.triangle", @(ToneAmber)], @[@"info.circle", @(ToneNeutral)]];
    NSArray *style = styles[(NSUInteger)event.kind];
    Tone tone = [style[1] integerValue];
    PanelView *badge = [PanelView new];
    badge.cornerRadius = 13.5;
    badge.fill = ToneFillColor(tone);
    badge.border = nil;
    NSImageView *icon = SymbolView(style[0], 11, NSFontWeightSemibold, ToneColor(tone));
    [badge addSubview:icon];

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.timeStyle = NSDateFormatterShortStyle;
    NSTextField *time = Label([formatter stringFromDate:event.date], 11.5, NSFontWeightRegular, ThemeFaintColor());
    time.font = [NSFont monospacedDigitSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    [time setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *title = HStack(12, @[Label(event.title, 13, NSFontWeightMedium, ThemeTextColor()), Spacer(), time]);
    title.alignment = NSLayoutAttributeFirstBaseline;
    NSTextField *detail = WrappingLabel(event.detail, 12, ThemeSubColor());
    NSStackView *text = VStack(3, @[]);
    FillWidth(title, text);
    FillWidth(detail, text);

    NSView *row = [NSView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    TimelineRail *rail = [TimelineRail new];
    rail.translatesAutoresizingMaskIntoConstraints = NO;
    rail.hidden = last;
    for (NSView *view in @[rail, badge, text]) [row addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [badge.topAnchor constraintEqualToAnchor:row.topAnchor],
        [badge.widthAnchor constraintEqualToConstant:27],
        [badge.heightAnchor constraintEqualToConstant:27],
        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [rail.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [rail.widthAnchor constraintEqualToConstant:3],
        [rail.topAnchor constraintEqualToAnchor:badge.bottomAnchor constant:3],
        [rail.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-1],
        [text.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:16],
        [text.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [text.topAnchor constraintEqualToAnchor:row.topAnchor constant:4],
        [text.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:last ? 0 : -20],
    ]];
    row.accessibilityElement = YES;
    row.accessibilityRole = NSAccessibilityStaticTextRole;
    row.accessibilityLabel = [NSString stringWithFormat:@"%@, %@. %@", event.title, time.stringValue, event.detail];
    return row;
}

@end
