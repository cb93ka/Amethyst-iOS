#import <UIKit/UIKit.h>

@interface ModpackInstallViewController : UITableViewController<UISearchResultsUpdating>

/**
 * When set, the screen searches for mods and installs them into that profile.
 * When nil it searches for modpacks, which bring a profile of their own.
 */
@property(nonatomic) NSString *targetProfileName;

@end
