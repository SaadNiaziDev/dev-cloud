#import "SetupFile.h"
#import "CloudInventory.h"

// Every name below comes from a validated inventory, but a backup is still untrusted input:
// each value must match a strict pattern before it reaches the file, so it cannot name a
// third-party tap, leave its quotes, or start a new line.
static BOOL Full(id value, NSString *pattern) {
    if (![value isKindOfClass:NSString.class] || [value length] > 120) return NO;
    NSString *anchored = [NSString stringWithFormat:@"^(?:%@)$", pattern];
    return [value rangeOfString:anchored options:NSRegularExpressionSearch].location != NSNotFound;
}

static NSString *const FormulaPattern = @"[a-z0-9][a-z0-9._-]*(@[a-z0-9._-]+)?";
static NSString *const ExtensionPattern = @"[a-z0-9][a-z0-9-]*\\.[a-z0-9][a-z0-9._-]*";
static NSString *const VersionPattern = @"[0-9][0-9A-Za-z.+_-]{0,40}";

static NSString *Formula(NSString *tool, id version) {
    // Bundled with another formula or with Homebrew itself.
    if ([@[@"brew", @"pip", @"npm"] containsObject:tool]) return nil;
    if ([tool isEqual:@"nodejs"]) return @"node";
    if ([tool isEqual:@"python"]) {
        NSArray *parts = Full(version, VersionPattern) ? [version componentsSeparatedByString:@"."] : @[];
        return parts.count >= 2 && [parts[0] isEqual:@"3"] && Full(parts[1], @"[0-9]{1,2}") ? [@"python@3." stringByAppendingString:parts[1]] : @"python";
    }
    return Full(tool, FormulaPattern) ? tool : nil;
}

static NSString *ManagerStep(NSString *tool, NSString *provider, id version) {
    if (!Full(version, VersionPattern)) return nil;
    if ([tool isEqual:@"nodejs"]) {
        if ([provider isEqual:@"nvm"]) return [@"nvm install " stringByAppendingString:version];
        if ([provider isEqual:@"fnm"]) return [@"fnm install " stringByAppendingString:version];
        if ([provider isEqual:@"volta"]) return [@"volta install node@" stringByAppendingString:version];
    }
    if ([tool isEqual:@"python"] && [provider isEqual:@"pyenv"]) return [@"pyenv install " stringByAppendingString:version];
    return nil;
}

static NSArray<NSString *> *Kinds(void) { return @[@"brew", @"cask", @"vscode", @"step", @"cursor"]; }

static NSDictionary *Item(NSString *kind, NSString *name, NSString *line) {
    return @{@"kind": kind, @"name": name, @"line": line};
}

static NSDictionary *Validated(NSDictionary *inventory, NSError **error) {
    NSData *data = [inventory isKindOfClass:NSDictionary.class] ? CloudInventoryData(inventory, NULL, error) : nil;
    NSDictionary *validated = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![validated isKindOfClass:NSDictionary.class]) {
        if (error && !*error) *error = [NSError errorWithDomain:@"DevCloudSetup" code:1 userInfo:@{NSLocalizedDescriptionKey: @"This inventory can’t be turned into a setup file. Scan again and try once more."}];
        return nil;
    }
    return validated;
}

// Items in a fixed order: formulae, apps, VS Code extensions, runtime steps, Cursor extensions.
static NSArray<NSDictionary *> *Collect(NSDictionary *validated, BOOL *commandLineTools) {
    NSMutableDictionary<NSString *, NSDictionary *> *items = [NSMutableDictionary dictionary];
    void (^add)(NSString *, NSString *, NSString *) = ^(NSString *kind, NSString *name, NSString *line) { items[line] = Item(kind, name, line); };
    for (NSDictionary *item in validated[@"resources"]) {
        NSString *tool = item[@"canonical_tool_id"];
        NSString *provider = [item[@"installation_provider"] isKindOfClass:NSString.class] ? item[@"installation_provider"] : @"";
        id version = item[@"version"];
        if ([tool hasPrefix:@"vscode-extension:"]) {
            NSString *identifier = [tool substringFromIndex:17];
            if (Full(identifier, ExtensionPattern)) add(@"vscode", identifier, [NSString stringWithFormat:@"vscode \"%@\"", identifier]);
        } else if ([tool hasPrefix:@"cursor-extension:"]) {
            NSString *identifier = [tool substringFromIndex:17];
            if (Full(identifier, ExtensionPattern)) add(@"cursor", identifier, [@"# cursor --install-extension " stringByAppendingString:identifier]);
            add(@"cask", @"cursor", @"cask \"cursor\"");
        } else if ([provider isEqual:@"homebrew_cask"]) {
            if (Full(tool, FormulaPattern)) add(@"cask", tool, [NSString stringWithFormat:@"cask \"%@\"", tool]);
        } else if ([tool isEqual:@"vscode"]) {
            add(@"cask", @"visual-studio-code", @"cask \"visual-studio-code\"");
        } else if ([tool isEqual:@"cursor"] && ![provider isEqual:@"homebrew_formula"]) {
            add(@"cask", @"cursor", @"cask \"cursor\"");
        } else if ([provider isEqual:@"homebrew_formula"] || [provider isEqual:@"homebrew"]) {
            NSString *formula = Formula(tool, version);
            if (formula) add(@"brew", formula, [NSString stringWithFormat:@"brew \"%@\"", formula]);
        } else if ([provider isEqual:@"macos_system"] || [provider isEqual:@"xcode"]) {
            if (commandLineTools) *commandLineTools = YES;
        } else {
            NSString *step = ManagerStep(tool, provider, version);
            if (step) add(@"step", step, [@"# " stringByAppendingString:step]);
        }
    }
    return [items.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSUInteger x = [Kinds() indexOfObject:a[@"kind"]], y = [Kinds() indexOfObject:b[@"kind"]];
        return x != y ? (x < y ? NSOrderedAscending : NSOrderedDescending) : [a[@"line"] compare:b[@"line"]];
    }];
}

static void Section(NSMutableString *text, NSString *title, NSArray<NSDictionary *> *items, NSString *kind) {
    NSArray *matching = [items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"kind == %@", kind]];
    if (!matching.count) return;
    [text appendFormat:@"\n# %@\n", title];
    for (NSDictionary *item in matching) [text appendFormat:@"%@\n", item[@"line"]];
}

BOOL SetupItemInstallable(NSDictionary *item) {
    return [@[@"brew", @"cask", @"vscode"] containsObject:item[@"kind"]];
}

NSArray<NSDictionary *> *SetupItems(NSDictionary *inventory, NSDictionary *current, NSError **error) {
    NSDictionary *validated = Validated(inventory, error);
    if (!validated) return nil;
    NSDictionary *here = current ? Validated(current, NULL) : nil;
    NSSet *present = here ? [NSSet setWithArray:[Collect(here, NULL) valueForKey:@"line"]] : [NSSet set];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *item in Collect(validated, NULL)) {
        NSMutableDictionary *row = [item mutableCopy];
        row[@"installed"] = @([present containsObject:item[@"line"]]);
        [items addObject:row];
    }
    return items;
}

NSString *SetupInstallFile(NSArray<NSDictionary *> *items) {
    NSMutableString *text = [NSMutableString stringWithString:@"# Written by DevCloud for one install run.\n"];
    for (NSDictionary *item in items) if (SetupItemInstallable(item)) [text appendFormat:@"%@\n", item[@"line"]];
    return text;
}

NSString *SetupBrewfile(NSDictionary *inventory, NSUInteger *entries, NSError **error) {
    NSDictionary *validated = Validated(inventory, error);
    if (!validated) return nil;
    BOOL commandLineTools = NO;
    NSArray *items = Collect(validated, &commandLineTools);
    NSDictionary *host = validated[@"host"];
    NSDateFormatter *format = [NSDateFormatter new];
    format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    format.dateFormat = @"yyyy-MM-dd";
    NSString *date = [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[validated[@"observed_at_unix_seconds"] doubleValue]]];
    NSString *os = [host[@"os_version"] isKindOfClass:NSString.class] ? [@"macOS " stringByAppendingString:host[@"os_version"]] : @"macOS";

    NSMutableString *text = [NSMutableString string];
    [text appendString:@"# DevCloud setup file\n"];
    [text appendFormat:@"# From the inventory of %@ (%@), %@.\n", os, host[@"architecture"], date];
    [text appendString:@"#\n# Review every line, then on the new Mac run:\n#   brew bundle --file <path to this file>\n#\n"];
    [text appendString:@"# DevCloud never runs this file. Homebrew installs its current versions, not the ones\n"];
    [text appendString:@"# recorded here, and the list includes dependencies that were on the old Mac.\n"];
    [text appendString:@"# Formulae from third-party taps (for example MongoDB) need their `brew tap` first;\n"];
    [text appendString:@"# `brew bundle` reports any it can't find and installs the rest.\n"];
    if (commandLineTools) [text appendString:@"#\n# Install Apple's Command Line Tools first:\n#   xcode-select --install\n"];
    Section(text, @"Command-line tools", items, @"brew");
    Section(text, @"Apps", items, @"cask");
    Section(text, @"VS Code extensions", items, @"vscode");
    Section(text, @"Runtime versions (run after their managers are set up)", items, @"step");
    Section(text, @"Cursor extensions (run after installing Cursor)", items, @"cursor");
    if (entries) *entries = items.count;
    return text;
}
