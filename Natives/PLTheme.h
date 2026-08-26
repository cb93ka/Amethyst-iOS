#import <UIKit/UIKit.h>

/*
 * The Aurora palette, kept in one place so the launcher can be recoloured
 * from a single file.
 *
 * The brand is a band of light running teal -> periwinkle -> magenta. It is
 * only ever used as a fill; where a flat colour is needed, PLThemeTint gives
 * a single accent that holds its contrast on both a light and a dark ground.
 */

UIColor* PLThemeTint(void);

// The three stops of the band, in order.
NSArray<UIColor *>* PLThemeAuroraColors(void);

// A horizontal gradient drawn at `size`. Stretch it to fill a control.
UIImage* PLThemeAuroraImage(CGSize size);

// Ink dark enough to stay legible on top of the band.
UIColor* PLThemeOnAuroraColor(void);
