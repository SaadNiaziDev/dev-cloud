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

static void Section(NSMutableString *text, NSString *title, NSSet<NSString *> *lines) {
    if (!lines.count) return;
    [text appendFormat:@"\n# %@\n", title];
    for (NSString *line in [lines.allObjects sortedArrayUsingSelector:@selector(compare:)]) [text appendFormat:@"%@\n", line];
}

NSString *SetupBrewfile(NSDictionary *inventory, NSUInteger *entries, NSError **error) {
    NSData *data = [inventory isKindOfClass:NSDictionary.class] ? CloudInventoryData(inventory, NULL, error) : nil;
    NSDictionary *validated = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![validated isKindOfClass:NSDictionary.class]) {
        if (error && !*error) *error = [NSError errorWithDomain:@"DevCloudSetup" code:1 userInfo:@{NSLocalizedDescriptionKey: @"This inventory can’t be turned into a setup file. Scan again and try once more."}];
        return nil;
    }
    NSMutableSet *formulae = [NSMutableSet set], *casks = [NSMutableSet set], *extensions = [NSMutableSet set];
    NSMutableSet *steps = [NSMutableSet set], *cursorExtensions = [NSMutableSet set];
    BOOL commandLineTools = NO;
    for (NSDictionary *item in validated[@"resources"]) {
        NSString *tool = item[@"canonical_tool_id"];
        NSString *provider = [item[@"installation_provider"] isKindOfClass:NSString.class] ? item[@"installation_provider"] : @"";
        id version = item[@"version"];
        if ([tool hasPrefix:@"vscode-extension:"]) {
            NSString *identifier = [tool substringFromIndex:17];
            if (Full(identifier, ExtensionPattern)) [extensions addObject:[NSString stringWithFormat:@"vscode \"%@\"", identifier]];
        } else if ([tool hasPrefix:@"cursor-extension:"]) {
            NSString *identifier = [tool substringFromIndex:17];
            if (Full(identifier, ExtensionPattern)) [cursorExtensions addObject:[@"# cursor --install-extension " stringByAppendingString:identifier]];
            [casks addObject:@"cask \"cursor\""];
        } else if ([provider isEqual:@"homebrew_cask"]) {
            if (Full(tool, FormulaPattern)) [casks addObject:[NSString stringWithFormat:@"cask \"%@\"", tool]];
        } else if ([tool isEqual:@"vscode"]) {
            [casks addObject:@"cask \"visual-studio-code\""];
        } else if ([tool isEqual:@"cursor"] && ![provider isEqual:@"homebrew_formula"]) {
            [casks addObject:@"cask \"cursor\""];
        } else if ([provider isEqual:@"homebrew_formula"] || [provider isEqual:@"homebrew"]) {
            NSString *formula = Formula(tool, version);
            if (formula) [formulae addObject:[NSString stringWithFormat:@"brew \"%@\"", formula]];
        } else if ([provider isEqual:@"macos_system"] || [provider isEqual:@"xcode"]) {
            commandLineTools = YES;
        } else {
            NSString *step = ManagerStep(tool, provider, version);
            if (step) [steps addObject:[@"# " stringByAppendingString:step]];
        }
    }
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
    Section(text, @"Command-line tools", formulae);
    Section(text, @"Apps", casks);
    Section(text, @"VS Code extensions", extensions);
    Section(text, @"Runtime versions (run after their managers are set up)", steps);
    Section(text, @"Cursor extensions (run after installing Cursor)", cursorExtensions);
    if (entries) *entries = formulae.count + casks.count + extensions.count + steps.count + cursorExtensions.count;
    return text;
}
