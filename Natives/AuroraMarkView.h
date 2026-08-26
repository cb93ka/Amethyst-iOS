#import <UIKit/UIKit.h>

/*
 * The Aurora mark, sized for a navigation title view.
 *
 * The band draws itself on once, then a pale highlight keeps travelling along
 * it. Contrast for that highlight is measured against the saturated band
 * rather than the page, so it reads on a light ground and a dark one alike.
 *
 * Honours Reduce Motion: the mark is then simply drawn, with no runner.
 */
@interface AuroraMarkView : UIView

// Set NO to show the mark on its own, without the wordmark. Default YES.
@property(nonatomic) BOOL showsWordmark;

@end
