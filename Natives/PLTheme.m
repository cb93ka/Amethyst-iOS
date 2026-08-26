#import "PLTheme.h"

static UIColor *PLThemeColor(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

UIColor* PLThemeTint(void) {
    // Deeper on a light ground, brighter on a dark one: the same hue would
    // fail its contrast in one of the two otherwise
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return PLThemeColor(traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? 0x2AD3BC : 0x0B8C7E);
    }];
}

NSArray<UIColor *>* PLThemeAuroraColors(void) {
    return @[PLThemeColor(0x2AD3BC), PLThemeColor(0x6D7BF2), PLThemeColor(0xE056A8)];
}

UIColor* PLThemeOnAuroraColor(void) {
    return PLThemeColor(0x04231F);
}

UIImage* PLThemeAuroraImage(CGSize size) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        NSMutableArray *colors = [[NSMutableArray alloc] init];
        for (UIColor *color in PLThemeAuroraColors()) {
            [colors addObject:(__bridge id)color.CGColor];
        }

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat locations[] = {0.0, 0.52, 1.0};
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locations);

        CGContextDrawLinearGradient(context.CGContext, gradient,
            CGPointZero, CGPointMake(size.width, 0), 0);

        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    }];
}
