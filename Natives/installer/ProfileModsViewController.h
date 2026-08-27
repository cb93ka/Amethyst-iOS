#import <UIKit/UIKit.h>

/**
 * The mods a profile has, the way MultiMC lists them: each one can be switched
 * off without losing it, or removed for good.
 *
 * Switching a mod off renames it to .disabled, which every loader knows to skip.
 * The file stays where it is, so switching it back on costs nothing.
 */
@interface ProfileModsViewController : UITableViewController

@property(nonatomic) NSString *profileName;

@end
