#import <Cocoa/Cocoa.h>

// Draws the full-colour app icon (tile and mark) filling `rect`.
void ContinuityDrawAppIcon(NSRect rect);

// Draws the mark alone in the current fill colour; used for template images.
void ContinuityDrawMark(NSRect rect);

// A template image of the mark for the menu bar.
NSImage *ContinuityMenuBarImage(void);

// The app icon at an arbitrary size, for in-app illustrations.
NSImage *ContinuityAppIconImage(CGFloat size);
