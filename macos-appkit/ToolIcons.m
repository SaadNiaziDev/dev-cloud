#import "ToolIcons.h"

NSImage *ToolIconForIdentifier(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || !identifier.length) return nil;
    static NSDictionary<NSString *, NSString *> *names;
    static NSCache<NSString *, NSImage *> *images;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"node": @"nodejs", @"nodejs": @"nodejs", @"python": @"python", @"python3": @"python", @"pip": @"python",
            @"git": @"git", @"docker": @"docker", @"go": @"go", @"rust": @"rust", @"rustc": @"rust", @"rustup": @"rust", @"cargo": @"rust",
            @"npm": @"npm", @"yarn": @"yarn", @"pnpm": @"pnpm", @"bun": @"bun", @"brew": @"homebrew", @"homebrew": @"homebrew",
            @"vscode": @"vscode", @"code": @"vscode", @"visual-studio-code": @"vscode", @"swift": @"swift", @"java": @"java", @"openjdk": @"java",
            @"terraform": @"terraform", @"kubectl": @"kubernetes", @"kubernetes": @"kubernetes", @"gh": @"github", @"github": @"github",
            @"redis": @"redis", @"postgres": @"postgresql", @"postgresql": @"postgresql", @"mysql": @"mysql", @"cmake": @"cmake"
        };
        images = [NSCache new];
    });
    NSString *base = [identifier.lowercaseString componentsSeparatedByString:@"@"].firstObject;
    NSString *name = names[base];
    if (!name) return nil;
    NSImage *image = [images objectForKey:name];
    if (image) return image;
    NSURL *url = nil;
#ifdef CONTINUITY_TESTING
    NSString *directory = NSProcessInfo.processInfo.environment[@"CONTINUITY_TOOL_ICONS_DIR"];
    if (directory.length) url = [[NSURL fileURLWithPath:directory isDirectory:YES] URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"svg"]];
#endif
    if (!url) url = [NSBundle.mainBundle URLForResource:name withExtension:@"svg" subdirectory:@"ToolIcons"];
    if (!url) return nil;
    image = [[NSImage alloc] initWithContentsOfURL:url];
    if (image) [images setObject:image forKey:name];
    return image;
}
