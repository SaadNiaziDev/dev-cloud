// Renders the app icon into an .iconset directory: make-icon <output.iconset>
#import <Cocoa/Cocoa.h>
#import "BrandMark.h"

static NSData *Render(CGFloat size) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size pixelsHigh:(NSInteger)size bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    ContinuityDrawAppIcon(NSMakeRect(0, 0, size, size));
    [NSGraphicsContext restoreGraphicsState];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: make-icon <output.iconset>\n");
            return 2;
        }
        NSString *directory = @(argv[1]);
        [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSNumber *points in @[@16, @32, @128, @256, @512]) {
            for (NSNumber *scale in @[@1, @2]) {
                NSString *name = scale.intValue == 1
                    ? [NSString stringWithFormat:@"icon_%dx%d.png", points.intValue, points.intValue]
                    : [NSString stringWithFormat:@"icon_%dx%d@2x.png", points.intValue, points.intValue];
                if (![Render(points.doubleValue * scale.doubleValue) writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]) return 1;
            }
        }
    }
    return 0;
}
