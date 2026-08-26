#import "AuroraMarkView.h"
#import "PLMotion.h"
#import "PLTheme.h"

// The mark is authored in a 24x24 box and scaled to whatever height it gets
static const CGFloat kMarkDesignSize = 24.0;
static const CGFloat kMarkSize = 28.0;
static const CGFloat kMarkGap = 8.0;
static const CGFloat kBandWidth = 3.2;
static const CGFloat kEchoWidth = 1.5;
static const CGFloat kSparkWidth = 1.5;

// A fifth of the band lights up at a time, and crosses it every 2.6s
static const CGFloat kSparkLength = 0.16;
static const NSTimeInterval kSparkDuration = 2.6;

@interface AuroraMarkView ()
@property(nonatomic) CAGradientLayer *gradientLayer;
@property(nonatomic) CAShapeLayer *bandLayer, *echoLayer, *sparkLayer;
@property(nonatomic) UILabel *wordmark;
@property(nonatomic) BOOL hasAnimated;
@end

@implementation AuroraMarkView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    _showsWordmark = YES;
    self.userInteractionEnabled = NO;

    // Band and echo live inside the gradient's mask, so animating them
    // reveals the colour rather than a flat shape
    _bandLayer = [CAShapeLayer layer];
    _bandLayer.fillColor = UIColor.clearColor.CGColor;
    _bandLayer.strokeColor = UIColor.whiteColor.CGColor;
    _bandLayer.lineCap = kCALineCapRound;

    _echoLayer = [CAShapeLayer layer];
    _echoLayer.fillColor = UIColor.clearColor.CGColor;
    _echoLayer.strokeColor = UIColor.whiteColor.CGColor;
    _echoLayer.lineCap = kCALineCapRound;
    _echoLayer.opacity = 0.42;

    CALayer *mask = [CALayer layer];
    [mask addSublayer:_bandLayer];
    [mask addSublayer:_echoLayer];

    _gradientLayer = [CAGradientLayer layer];
    _gradientLayer.startPoint = CGPointMake(0, 1);
    _gradientLayer.endPoint = CGPointMake(1, 0);
    _gradientLayer.locations = @[@0, @0.52, @1];
    _gradientLayer.mask = mask;
    [self.layer addSublayer:_gradientLayer];

    // The runner rides on top of the band, unmasked, with a soft halo
    _sparkLayer = [CAShapeLayer layer];
    _sparkLayer.fillColor = UIColor.clearColor.CGColor;
    _sparkLayer.strokeColor = [UIColor colorWithRed:0.95 green:1.0 blue:0.99 alpha:1].CGColor;
    _sparkLayer.lineCap = kCALineCapRound;
    _sparkLayer.opacity = 0;
    _sparkLayer.shadowColor = UIColor.whiteColor.CGColor;
    _sparkLayer.shadowOffset = CGSizeZero;
    _sparkLayer.shadowRadius = 2.5;
    _sparkLayer.shadowOpacity = 0.85;
    [self.layer addSublayer:_sparkLayer];

    _wordmark = [[UILabel alloc] init];
    _wordmark.text = @"Aurora";
    _wordmark.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _wordmark.textColor = UIColor.labelColor;
    [self addSubview:_wordmark];

    [self updateGradientColors];

    return self;
}

- (void)setShowsWordmark:(BOOL)showsWordmark {
    _showsWordmark = showsWordmark;
    self.wordmark.hidden = !showsWordmark;
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

- (void)updateGradientColors {
    NSMutableArray *colors = [[NSMutableArray alloc] init];
    for (UIColor *color in PLThemeAuroraColors()) {
        [colors addObject:(__bridge id)color.CGColor];
    }
    self.gradientLayer.colors = colors;
}

#pragma mark - Layout

- (CGSize)intrinsicContentSize {
    if (!self.showsWordmark) {
        return CGSizeMake(kMarkSize, kMarkSize);
    }
    CGSize textSize = [self.wordmark sizeThatFits:CGSizeMake(CGFLOAT_MAX, kMarkSize)];
    return CGSizeMake(kMarkSize + kMarkGap + textSize.width, kMarkSize);
}

- (CGSize)sizeThatFits:(CGSize)size {
    return self.intrinsicContentSize;
}

- (UIBezierPath *)bandPathForScale:(CGFloat)scale {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(2.5 * scale, 16.6 * scale)];
    [path addCurveToPoint:CGPointMake(13.0 * scale, 12.6 * scale)
            controlPoint1:CGPointMake(6.0 * scale, 9.6 * scale)
            controlPoint2:CGPointMake(9.5 * scale, 19.0 * scale)];
    [path addCurveToPoint:CGPointMake(21.5 * scale, 6.6 * scale)
            controlPoint1:CGPointMake(15.6 * scale, 7.7 * scale)
            controlPoint2:CGPointMake(19.0 * scale, 10.1 * scale)];
    return path;
}

- (UIBezierPath *)echoPathForScale:(CGFloat)scale {
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(3.0 * scale, 21.2 * scale)];
    [path addCurveToPoint:CGPointMake(12.0 * scale, 15.6 * scale)
            controlPoint1:CGPointMake(6.0 * scale, 16.6 * scale)
            controlPoint2:CGPointMake(9.0 * scale, 19.8 * scale)];
    [path addCurveToPoint:CGPointMake(18.6 * scale, 11.4 * scale)
            controlPoint1:CGPointMake(14.2 * scale, 12.6 * scale)
            controlPoint2:CGPointMake(16.6 * scale, 13.6 * scale)];
    return path;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat side = MIN(kMarkSize, self.bounds.size.height ?: kMarkSize);
    CGFloat scale = side / kMarkDesignSize;
    CGRect markFrame = CGRectMake(0, (self.bounds.size.height - side) / 2, side, side);

    // Layer geometry is not part of the implicit animation we want to run
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.gradientLayer.frame = markFrame;
    self.gradientLayer.mask.frame = self.gradientLayer.bounds;
    self.sparkLayer.frame = markFrame;

    UIBezierPath *band = [self bandPathForScale:scale];
    self.bandLayer.frame = self.gradientLayer.bounds;
    self.bandLayer.path = band.CGPath;
    self.bandLayer.lineWidth = kBandWidth * scale;

    self.echoLayer.frame = self.gradientLayer.bounds;
    self.echoLayer.path = [self echoPathForScale:scale].CGPath;
    self.echoLayer.lineWidth = kEchoWidth * scale;

    self.sparkLayer.path = band.CGPath;
    self.sparkLayer.lineWidth = kSparkWidth * scale;

    [CATransaction commit];

    self.wordmark.frame = CGRectMake(side + kMarkGap, 0,
        MAX(0, self.bounds.size.width - side - kMarkGap), self.bounds.size.height);

    if (!self.hasAnimated && self.window) {
        self.hasAnimated = YES;
        [self startAnimating];
    }
}

#pragma mark - Animation

- (void)startAnimating {
    if (PLMotionIsReduced()) {
        self.bandLayer.strokeEnd = 1;
        self.echoLayer.strokeEnd = 1;
        self.sparkLayer.hidden = YES;
        return;
    }

    // The band draws itself on, the echo a beat behind it
    for (CAShapeLayer *layer in @[self.bandLayer, self.echoLayer]) {
        CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        draw.fromValue = @0;
        draw.toValue = @1;
        draw.duration = 1.0;
        draw.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.32 :0.72 :0.0 :1.0];
        draw.fillMode = kCAFillModeBackwards;
        if (layer == self.echoLayer) {
            draw.beginTime = CACurrentMediaTime() + 0.14;
        }
        layer.strokeEnd = 1;
        [layer addAnimation:draw forKey:@"draw"];
    }

    // Then the highlight sweeps the band, over and over
    CABasicAnimation *start = [CABasicAnimation animationWithKeyPath:@"strokeStart"];
    start.fromValue = @0;
    start.toValue = @(1.0 - kSparkLength);

    CABasicAnimation *end = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    end.fromValue = @(kSparkLength);
    end.toValue = @1;

    // Fade at both ends so it slips in and out instead of popping
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = @[@0, @0.95, @0.95, @0];
    fade.keyTimes = @[@0, @0.1, @0.9, @1];

    CAAnimationGroup *sweep = [CAAnimationGroup animation];
    sweep.animations = @[start, end, fade];
    sweep.duration = kSparkDuration;
    sweep.repeatCount = HUGE_VALF;
    sweep.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    sweep.beginTime = CACurrentMediaTime() + 1.0;
    [self.sparkLayer addAnimation:sweep forKey:@"sweep"];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    // CGColors do not resolve themselves when the appearance flips
    [self updateGradientColors];
}

@end
