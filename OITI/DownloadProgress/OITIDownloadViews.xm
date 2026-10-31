// OITIDownloadViews.xm -- the views of the download progress feature: the progress bar, the Minimal look's content view and
// the stack the Detailed look puts in its Island element (OITI download progress).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 2, DownloadProgress). The class declarations and
// kOITIMinimalHeight are in OITIDownloadProgress.h because the pill and the Island notification element use them.

#import "Shared/OITIShared.h"
#import "DownloadProgress/OITIDownloadProgress.h"

// ---- Download progress element views ----------------------------------------------------------
// Apple's system blue (#007AFF) for the bar, a tint of it for the track, system green when finished. The ends are
// round: the corner radius is always half the bar height.
static UIColor *OITIDownloadBlue(void) { return [UIColor colorWithRed:0.0 green:122.0 / 255.0 blue:1.0 alpha:1.0]; }
static UIColor *OITIDownloadRed(void) { return [UIColor colorWithRed:255.0 / 255.0 green:69.0 / 255.0 blue:58.0 / 255.0 alpha:1.0]; }
static UIColor *OITIDownloadGreen(void) { return [UIColor colorWithRed:52.0 / 255.0 green:199.0 / 255.0 blue:89.0 / 255.0 alpha:1.0]; }


@implementation OITIProgressBarView {
    UIView *_fill;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _barHeight = 6.0;
        self.backgroundColor = [OITIDownloadBlue() colorWithAlphaComponent:0.28];
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        _fill = [[UIView alloc] initWithFrame:CGRectZero];
        _fill.backgroundColor = OITIDownloadBlue();
        _fill.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_fill];
    }
    return self;
}
- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, _barHeight);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = self.bounds.size.height / 2.0;
    self.layer.cornerRadius = radius;
    _fill.layer.cornerRadius = radius;
    _fill.frame = CGRectMake(0, 0, self.bounds.size.width * _fraction, self.bounds.size.height);
}
- (void)setFraction:(double)fraction animated:(BOOL)animated {
    _fraction = isfinite(fraction) ? MAX(0.0, MIN(1.0, fraction)) : 0.0;
    CGRect target = CGRectMake(0, 0, self.bounds.size.width * _fraction, self.bounds.size.height);
    if (animated && self.window) {
        [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveLinear
                         animations:^{ self->_fill.frame = target; } completion:nil];
    } else {
        _fill.frame = target;
    }
}
- (void)setComplete:(BOOL)complete {
    _fill.backgroundColor = complete ? OITIDownloadGreen() : OITIDownloadBlue();
}
- (void)setCancelled:(BOOL)cancelled {
    if (cancelled) _fill.backgroundColor = OITIDownloadRed();
}
@end

// The minimal look, on the WIDE layout. The same body for every download:
//
//          App Name - File Name
//                212 MB
//   9.4 MB/s [████████░░░░░░] 26%
//                800 MB
//
// The bar is in the middle of the row with the speed on its left and the percentage on its right; the downloaded size is
// centered above the bar and the total size centered below it. Everything is laid out from the view's bounds, so it
// follows whatever width the Island gives it. The constants are the knobs for size and spacing.
static const CGFloat kOITIMinimalWidth = 260.0;          // width it asks for
static const CGFloat kOITIMinimalSpeedWidth = 62.0;      // speed, left of the bar
static const CGFloat kOITIMinimalPercentWidth = 36.0;    // percentage, right of the bar
static const CGFloat kOITIMinimalGap = 6.0;
static const CGFloat kOITIMinimalBarHeight = 7.0;


@implementation OITIMinimalDownloadView {
    UILabel *_header;
    UILabel *_top;
    UILabel *_bottom;
    UILabel *_speed;
    UILabel *_percent;
    CAShapeLayer *_check;
    BOOL _completionShown;
}
- (UILabel *)minimalLabelWithSize:(CGFloat)size weight:(UIFontWeight)weight alignment:(NSTextAlignment)alignment {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont monospacedDigitSystemFontOfSize:size weight:weight];
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.9];
    label.textAlignment = alignment;
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.75;
    label.text = @" ";
    return label;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, kOITIMinimalWidth, kOITIMinimalHeight)])) {
        _bar = [[OITIProgressBarView alloc] initWithFrame:CGRectZero];
        _bar.barHeight = kOITIMinimalBarHeight;
        _header = [self minimalLabelWithSize:11 weight:UIFontWeightSemibold alignment:NSTextAlignmentCenter];
        _top = [self minimalLabelWithSize:10 weight:UIFontWeightMedium alignment:NSTextAlignmentCenter];
        _bottom = [self minimalLabelWithSize:10 weight:UIFontWeightMedium alignment:NSTextAlignmentCenter];
        _speed = [self minimalLabelWithSize:10 weight:UIFontWeightMedium alignment:NSTextAlignmentRight];
        _percent = [self minimalLabelWithSize:10 weight:UIFontWeightMedium alignment:NSTextAlignmentLeft];
        for (UIView *view in @[_header, _top, _bar, _bottom, _speed, _percent]) [self addSubview:view];
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(kOITIMinimalWidth, kOITIMinimalHeight); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(kOITIMinimalWidth, kOITIMinimalHeight); }
- (CGRect)completionCircleFrame {
    CGFloat diameter = 30.0;
    return CGRectMake((self.bounds.size.width - diameter) / 2.0, (self.bounds.size.height - diameter) / 2.0, diameter, diameter);
}
- (NSArray<UILabel *> *)allLabels {
    return @[_header, _top, _bottom, _speed, _percent];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (_completionShown) {   // the labels are faded out (and scaled, so their frames are left alone); only the circle needs placing
        _bar.frame = [self completionCircleFrame];
        return;
    }
    CGFloat width = self.bounds.size.width;
    CGFloat barX = kOITIMinimalSpeedWidth + kOITIMinimalGap;
    CGFloat barWidth = MAX(40.0, width - barX - kOITIMinimalGap - kOITIMinimalPercentWidth);
    CGFloat rowCenter = 36.0;   // the row with the bar: header 13, gap 2, downloaded 12, gap 2, row 14, gap 1, total 12
    _header.frame = CGRectMake(0, 0, width, 13);
    _top.frame = CGRectMake(barX, 15, barWidth, 12);
    _speed.frame = CGRectMake(0, rowCenter - 7, kOITIMinimalSpeedWidth, 14);
    _bar.frame = CGRectMake(barX, rowCenter - kOITIMinimalBarHeight / 2.0, barWidth, kOITIMinimalBarHeight);
    _percent.frame = CGRectMake(barX + barWidth + kOITIMinimalGap, rowCenter - 7, kOITIMinimalPercentWidth, 14);
    _bottom.frame = CGRectMake(barX, 44, barWidth, 12);
}
- (void)setHeader:(NSString *)header downloaded:(NSString *)downloaded total:(NSString *)total speed:(NSString *)speed
          percent:(NSString *)percent fraction:(double)fraction complete:(BOOL)complete {
    if (![_header.text isEqualToString:header]) _header.text = header;
    if (![_top.text isEqualToString:downloaded]) _top.text = downloaded;
    if (![_bottom.text isEqualToString:total]) _bottom.text = total;
    if (![_speed.text isEqualToString:speed]) _speed.text = speed;
    if (![_percent.text isEqualToString:percent]) _percent.text = percent;
    [_bar setComplete:complete];
    [_bar setFraction:fraction animated:YES];
}
// Completion: all the text fades and shrinks away while the bar contracts into a green circle, then a white check is drawn
// in the circle (a stroke animation). With Reduce Motion on, the end state appears at once.
- (void)playCompletion {
    if (_completionShown) return;
    _completionShown = YES;
    CGRect circle = [self completionCircleFrame];
    if (!_check) {
        _check = [CAShapeLayer layer];
        _check.fillColor = nil;
        _check.strokeColor = UIColor.whiteColor.CGColor;
        _check.lineWidth = 3.0;
        _check.lineCap = kCALineCapRound;
        _check.lineJoin = kCALineJoinRound;
        [self.layer addSublayer:_check];
    }
    CGFloat d = circle.size.width;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(CGRectGetMinX(circle) + d * 0.28, CGRectGetMinY(circle) + d * 0.52)];
    [path addLineToPoint:CGPointMake(CGRectGetMinX(circle) + d * 0.43, CGRectGetMinY(circle) + d * 0.67)];
    [path addLineToPoint:CGPointMake(CGRectGetMinX(circle) + d * 0.72, CGRectGetMinY(circle) + d * 0.35)];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _check.frame = self.bounds;
    _check.path = path.CGPath;
    _check.hidden = NO;
    _check.strokeEnd = reduceMotion ? 1.0 : 0.0;
    [CATransaction commit];
    [_bar.layer removeAllAnimations];
    for (UIView *subview in _bar.subviews) [subview.layer removeAllAnimations];
    if (reduceMotion) {
        for (UILabel *label in [self allLabels]) label.alpha = 0.0;
        _bar.frame = circle;
        [_bar setFraction:1.0 animated:NO];
        return;
    }
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        for (UILabel *label in [self allLabels]) {
            label.alpha = 0.0;
            label.transform = CGAffineTransformMakeScale(0.8, 0.8);
        }
    } completion:nil];
    [UIView animateWithDuration:0.45 delay:0.05 usingSpringWithDamping:0.78 initialSpringVelocity:0.0 options:0 animations:^{
        self->_bar.frame = circle;
    } completion:nil];
    [_bar setFraction:1.0 animated:YES];   // the bar's bounds are already the circle's, so the fill shrinks with it
    CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    draw.fromValue = @0.0;
    draw.toValue = @1.0;
    draw.duration = 0.32;
    draw.beginTime = [_check convertTime:CACurrentMediaTime() fromLayer:nil] + 0.32;
    draw.fillMode = kCAFillModeBackwards;
    draw.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _check.strokeEnd = 1.0;
    [CATransaction commit];
    [_check addAnimation:draw forKey:@"draw"];
}
- (void)resetCompletion {
    if (!_completionShown) return;
    _completionShown = NO;
    [_bar.layer removeAllAnimations];
    for (UIView *subview in _bar.subviews) [subview.layer removeAllAnimations];
    [_check removeAllAnimations];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _check.hidden = YES;
    _check.strokeEnd = 0.0;
    [CATransaction commit];
    for (UILabel *label in [self allLabels]) {
        label.alpha = 1.0;
        label.transform = CGAffineTransformIdentity;
    }
    [self setNeedsLayout];
}
@end

// The expanded body of the download element: the bar with one line of text under it.
OITINoticeStackView *OITIBuildDownloadStack(OITIProgressBarView **barOut, UILabel **detailOut) {
    OITIProgressBarView *bar = [[OITIProgressBarView alloc] initWithFrame:CGRectZero];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *detail = [[UILabel alloc] init];
    detail.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    detail.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    detail.numberOfLines = 1;
    detail.lineBreakMode = NSLineBreakByTruncatingTail;
    detail.adjustsFontSizeToFitWidth = YES;
    detail.minimumScaleFactor = 0.8;
    detail.text = @" ";
    OITINoticeStackView *stack = [OITINoticeStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionFill;
    stack.spacing = 7;
    [stack addArrangedSubview:bar];
    [stack addArrangedSubview:detail];
    CGSize size = [stack sizeThatFits:CGSizeMake(260, CGFLOAT_MAX)];
    stack.frame = CGRectMake(0, 0, size.width, size.height);
    *barOut = bar;
    *detailOut = detail;
    return stack;
}
