#import "PLMotion.h"
#import "UIKit+hook.h"

const NSTimeInterval PLMotionDurationTap = 0.13;
const NSTimeInterval PLMotionDurationMicro = 0.2;
const NSTimeInterval PLMotionDurationBase = 0.28;
const NSTimeInterval PLMotionDurationPresent = 0.38;

// Delay between consecutive sections of a cascading table, and the number of
// sections that still receive one before the delay is clamped
static const NSTimeInterval PLMotionStaggerStep = 0.035;
static const NSInteger PLMotionStaggerMaxGroups = 5;

// How far an entering screen and its rows travel while fading in
static const CGFloat PLMotionPaneRise = 10.0;
static const CGFloat PLMotionRowRise = 7.0;

BOOL PLMotionIsReduced(void) {
    return UIAccessibilityIsReduceMotionEnabled();
}

static CAMediaTimingFunction *PLMotionTimingFunction(PLMotionCurve curve) {
    switch (curve) {
        case PLMotionCurveInOut:
            return [CAMediaTimingFunction functionWithControlPoints:0.45 :0.0 :0.25 :1.0];
        case PLMotionCurveSpring:
            return [CAMediaTimingFunction functionWithControlPoints:0.34 :1.4 :0.64 :1.0];
        case PLMotionCurveOut:
        default:
            return [CAMediaTimingFunction functionWithControlPoints:0.32 :0.72 :0.0 :1.0];
    }
}

void PLMotionAnimateWithDelay(NSTimeInterval duration, NSTimeInterval delay, PLMotionCurve curve,
    void (^animations)(void), void (^completion)(BOOL finished))
{
    if (animations == nil) {
        if (completion) completion(YES);
        return;
    }

    if (PLMotionIsReduced() || duration <= 0) {
        animations();
        if (completion) completion(YES);
        return;
    }

    // A CATransaction timing function applies to the UIView animations created
    // inside it, which is how we get curves UIViewAnimationOptions cannot express
    [CATransaction begin];
    [CATransaction setAnimationTimingFunction:PLMotionTimingFunction(curve)];
    [UIView animateWithDuration:duration delay:delay
        options:UIViewAnimationOptionAllowUserInteraction
        animations:animations completion:completion];
    [CATransaction commit];
}

void PLMotionAnimate(NSTimeInterval duration, PLMotionCurve curve,
    void (^animations)(void), void (^completion)(BOOL finished))
{
    PLMotionAnimateWithDelay(duration, 0, curve, animations, completion);
}

void PLMotionFadeSwap(UIView *view, void (^update)(void)) {
    if (update == nil) return;
    if (view == nil || view.window == nil || PLMotionIsReduced()) {
        update();
        return;
    }

    [UIView transitionWithView:view duration:PLMotionDurationMicro
        options:UIViewAnimationOptionTransitionCrossDissolve |
                UIViewAnimationOptionAllowUserInteraction
        animations:update completion:nil];
}

void PLMotionFadeSwapBarItem(UIBarButtonItem *item, NSString *title) {
    if (item == nil) return;

    // A bar button item is not a view; animate the one it is backed by when
    // it already exists, and fall back to setting the title outright
    UIView *itemView = [item respondsToSelector:@selector(view)] ? item.view : nil;
    PLMotionFadeSwap(itemView, ^{
        item.title = title;
    });
}

void PLMotionPaneIn(UIView *view) {
    if (view == nil || PLMotionIsReduced()) return;

    view.alpha = 0;
    view.transform = CGAffineTransformMakeTranslation(0, PLMotionPaneRise);
    PLMotionAnimate(PLMotionDurationBase, PLMotionCurveOut, ^{
        view.alpha = 1;
        view.transform = CGAffineTransformIdentity;
    }, ^(BOOL finished) {
        // Guarantee the resting state even if the animation was interrupted
        view.alpha = 1;
        view.transform = CGAffineTransformIdentity;
    });
}

void PLMotionStaggerTableView(UITableView *tableView) {
    if (tableView == nil || PLMotionIsReduced()) return;

    NSMutableArray<UIView *> *views = [[NSMutableArray alloc] init];
    NSMutableArray<NSNumber *> *groups = [[NSMutableArray alloc] init];

    for (UITableViewCell *cell in tableView.visibleCells) {
        NSIndexPath *indexPath = [tableView indexPathForCell:cell];
        if (indexPath == nil) continue;
        [views addObject:cell];
        [groups addObject:@(MIN(indexPath.section, PLMotionStaggerMaxGroups))];
    }

    for (NSInteger section = 0; section < tableView.numberOfSections; section++) {
        UIView *header = [tableView headerViewForSection:section];
        if (header == nil) continue;
        [views addObject:header];
        [groups addObject:@(MIN(section, PLMotionStaggerMaxGroups))];
    }

    for (NSUInteger i = 0; i < views.count; i++) {
        UIView *view = views[i];
        view.alpha = 0;
        view.transform = CGAffineTransformMakeTranslation(0, PLMotionRowRise);
        PLMotionAnimateWithDelay(PLMotionDurationBase,
            groups[i].doubleValue * PLMotionStaggerStep, PLMotionCurveOut, ^{
                view.alpha = 1;
                view.transform = CGAffineTransformIdentity;
            }, ^(BOOL finished) {
                // Cells outlive the animation and get reused, so never leave
                // one parked at zero opacity
                view.alpha = 1;
                view.transform = CGAffineTransformIdentity;
            });
    }
}
