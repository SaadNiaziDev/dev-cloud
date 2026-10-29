#import <AppKit/AppKit.h>
#import "ToolIcons.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 1;
        setenv("CONTINUITY_TOOL_ICONS_DIR", "/nonexistent/continuity-icons", 1);
        if (ToolIconForIdentifier(@"nodejs")) return 1;
        setenv("CONTINUITY_TOOL_ICONS_DIR", argv[1], 1);
        NSArray<NSString *> *identifiers = @[@"nodejs", @"python", @"git", @"docker", @"go", @"rustc", @"npm", @"yarn", @"pnpm", @"bun", @"brew", @"vscode", @"swift", @"java", @"terraform", @"kubectl", @"gh", @"redis", @"postgresql", @"mysql", @"cmake"];
        for (NSString *identifier in identifiers) {
            NSImage *image = ToolIconForIdentifier(identifier);
            if (!image || image.size.width <= 0 || image.size.height <= 0) {
                fprintf(stderr, "Could not load icon for %s\n", identifier.UTF8String);
                return 1;
            }
        }
        if (ToolIconForIdentifier(@"node@22") != ToolIconForIdentifier(@"nodejs")) return 1;
        if (ToolIconForIdentifier(@"openjdk@17") != ToolIconForIdentifier(@"java")) return 1;
        if (ToolIconForIdentifier(@"../../unknown") || ToolIconForIdentifier(@"unknown")) return 1;
        printf("Verified %lu bundled tool icons and fallbacks\n", (unsigned long)identifiers.count);
    }
    return 0;
}
