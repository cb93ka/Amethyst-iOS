#import "PLProfiles.h"
#import "ProfileModsViewController.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

// Every loader skips a file whose name ends this way
static NSString *const kDisabledSuffix = @".disabled";

@interface ProfileModsViewController ()
@property(nonatomic) NSString *modsPath;
@property(nonatomic) NSMutableArray<NSString *> *fileNames;
@end

@implementation ProfileModsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = localize(@"profile.title.manage_mods", nil);

    NSMutableDictionary *profile = PLProfiles.current.profiles[self.profileName];
    NSString *gameDir = [profile[@"gameDir"] length] > 0 ? profile[@"gameDir"] : @".";
    self.modsPath = [[[@(getenv("POJAV_GAME_DIR"))
        stringByAppendingPathComponent:gameDir]
        stringByAppendingPathComponent:@"mods"] stringByStandardizingPath];

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // A mod may have been added from the profile screen while this was open
    [self reload];
}

- (void)reload {
    NSArray *contents = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:self.modsPath error:nil];

    self.fileNames = [[NSMutableArray alloc] init];
    for (NSString *name in contents) {
        NSString *bare = [name hasSuffix:kDisabledSuffix]
            ? [name substringToIndex:name.length - kDisabledSuffix.length] : name;
        if ([bare.pathExtension.lowercaseString isEqualToString:@"jar"]) {
            [self.fileNames addObject:name];
        }
    }
    [self.fileNames sortUsingSelector:@selector(localizedStandardCompare:)];
    [self.tableView reloadData];
}

- (BOOL)isEnabled:(NSString *)fileName {
    return ![fileName hasSuffix:kDisabledSuffix];
}

- (NSString *)displayNameOf:(NSString *)fileName {
    NSString *bare = [self isEnabled:fileName] ? fileName
        : [fileName substringToIndex:fileName.length - kDisabledSuffix.length];
    return bare.stringByDeletingPathExtension;
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.fileNames.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.fileNames.count > 0) {
        return localize(@"profile.mods.footer", nil);
    }
    return localize(@"profile.mods.empty", nil);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
            reuseIdentifier:@"cell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSString *fileName = self.fileNames[indexPath.row];
    BOOL enabled = [self isEnabled:fileName];

    cell.textLabel.text = [self displayNameOf:fileName];
    cell.textLabel.enabled = enabled;
    cell.detailTextLabel.text = enabled ? nil : localize(@"profile.mods.disabled", nil);

    UISwitch *toggle = [UISwitch new];
    toggle.on = enabled;
    toggle.tag = indexPath.row;
    [toggle addTarget:self action:@selector(toggleMod:)
        forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;

    return cell;
}

- (void)toggleMod:(UISwitch *)sender {
    if (sender.tag >= self.fileNames.count) {
        return;
    }

    NSString *fileName = self.fileNames[sender.tag];
    NSString *target = [self isEnabled:fileName]
        ? [fileName stringByAppendingString:kDisabledSuffix]
        : [fileName substringToIndex:fileName.length - kDisabledSuffix.length];

    NSError *error;
    if (![NSFileManager.defaultManager
            moveItemAtPath:[self.modsPath stringByAppendingPathComponent:fileName]
            toPath:[self.modsPath stringByAppendingPathComponent:target]
            error:&error]) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
        sender.on = !sender.on;
        return;
    }

    self.fileNames[sender.tag] = target;
    [self.tableView reloadRowsAtIndexPaths:@[
        [NSIndexPath indexPathForRow:sender.tag inSection:0]]
        withRowAnimation:UITableViewRowAnimationNone];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
    editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }

    NSString *fileName = self.fileNames[indexPath.row];
    NSError *error;
    if (![NSFileManager.defaultManager
            removeItemAtPath:[self.modsPath stringByAppendingPathComponent:fileName]
            error:&error]) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
        return;
    }

    [self.fileNames removeObjectAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[indexPath]
        withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
