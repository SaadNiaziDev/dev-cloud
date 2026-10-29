#import <Cocoa/Cocoa.h>

// Draws the full-colour app icon (tile and mark) filling `rect`.
void DevCloudDrawAppIcon(NSRect rect);

// Draws the mark alone in the current fill colour; used for template images.
void DevCloudDrawMark(NSRect rect);

// A template image of the mark for the menu bar.
NSImage *DevCloudMenuBarImage(void);

// The app icon at an arbitrary size, for in-app illustrations.
NSImage *DevCloudAppIconImage(CGFloat size);
