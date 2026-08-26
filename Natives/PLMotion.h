#import <UIKit/UIKit.h>

/*
 * Motion system shared by the launcher UI.
 *
 * Curves and durations live in one place so the whole app can be retimed
 * from here. Every helper degrades to an instant, non-animated change when
 * the system-wide "Reduce Motion" switch is on.
 */

typedef NS_ENUM(NSInteger, PLMotionCurve) {
    // Presentation: leaves fast, settles slowly
    PLMotionCurveOut,
    // Colors and opacity
    PLMotionCurveInOut,
    // Taps, with a hint of overshoot
    PLMotionCurveSpring
};

extern const NSTimeInterval PLMotionDurationTap;
extern const NSTimeInterval PLMotionDurationMicro;
extern const NSTimeInterval PLMotionDurationBase;
extern const NSTimeInterval PLMotionDurationPresent;

BOOL PLMotionIsReduced(void);

void PLMotionAnimate(NSTimeInterval duration, PLMotionCurve curve,
    void (^animations)(void), void (^completion)(BOOL finished));
void PLMotionAnimateWithDelay(NSTimeInterval duration, NSTimeInterval delay, PLMotionCurve curve,
    void (^animations)(void), void (^completion)(BOOL finished));

// Replaces a label's contents behind a short cross-dissolve instead of snapping it
void PLMotionFadeSwap(UIView *view, void (^update)(void));
void PLMotionFadeSwapBarItem(UIBarButtonItem *item, NSString *title);

// Screen entrance: fades in while rising a few points
void PLMotionPaneIn(UIView *view);

// Cascades a table section by section, the way a table view fills in
void PLMotionStaggerTableView(UITableView *tableView);
