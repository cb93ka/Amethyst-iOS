#import "JarModUtils.h"
#import "PLProfiles.h"
#import "ProfileModsViewController.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

// Every loader skips a file whose name ends this way, and the jar mod builder
// follows the same rule
static NSString *const kDisabledSuffix = @".disabled";

typedef NS_ENUM(NSUInteger, ProfileModSection) {
    kSectionMods,
    kSectionJarMods,
    kSectionCount
};

@interface ProfileModsViewController ()
@property(nonatomic) NSString *modsPath, *jarModsPath;
@property(nonatomic) NSMutableArray<NSString *> *mods, *jarMods;
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
    self.jarModsPath = [JarModUtils jarModsPathForProfile:self.profileName];

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Something may have been added from the profile screen while this was open
    [self reload];
}

- (NSMutableArray<NSString *> *)listAt:(NSString *)path onlyJars:(BOOL)onlyJars {
    NSMutableArray<NSString *> *found = [[NSMutableArray alloc] init];
    for (NSString *name in [NSFileManager.defaultManager
            contentsOfDirectoryAtPath:path error:nil]) {
        if ([name hasPrefix:@"."]) {
            continue;
        }
        NSString *bare = [name hasSuffix:kDisabledSuffix]
            ? [name substringToIndex:name.length - kDisabledSuffix.length] : name;
        if (onlyJars && ![bare.pathExtension.lowercaseString isEqualToString:@"jar"]) {
            continue;
        }
        [found addObject:name];
    }
    [found sortUsingSelector:@selector(localizedStandardCompare:)];
    return found;
}

- (void)reload {
    self.mods = [self listAt:self.modsPath onlyJars:YES];
    // A jar mod may be a zip just as well as a jar
    self.jarMods = [self listAt:self.jarModsPath onlyJars:NO];
    [self.tableView reloadData];
}

- (NSMutableArray<NSString *> *)filesForSection:(NSInteger)section {
    return section == kSectionMods ? self.mods : self.jarMods;
}

- (NSString *)pathForSection:(NSInteger)section {
    return section == kSectionMods ? self.modsPath : self.jarModsPath;
}

- (BOOL)isEnabled:(NSString *)fileName {
    return ![fileName hasSuffix:kDisabledSuffix];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self filesForSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return localize(section == kSectionMods
        ? @"profile.mods.header" : @"profile.jarmods.header", nil);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ([self filesForSection:section].count == 0) {
        return localize(section == kSectionMods
            ? @"profile.mods.empty" : @"profile.jarmods.empty", nil);
    }
    return localize(section == kSectionMods
        ? @"profile.mods.footer" : @"profile.jarmods.footer", nil);
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

    NSString *fileName = [self filesForSection:indexPath.section][indexPath.row];
    BOOL enabled = [self isEnabled:fileName];
    NSString *bare = enabled ? fileName
        : [fileName substringToIndex:fileName.length - kDisabledSuffix.length];

    cell.textLabel.text = bare.stringByDeletingPathExtension;
    cell.textLabel.enabled = enabled;
    cell.detailTextLabel.text = enabled ? nil : localize(@"profile.mods.disabled", nil);

    UISwitch *toggle = [UISwitch new];
    toggle.on = enabled;
    toggle.tag = indexPath.section * 1000 + indexPath.row;
    [toggle addTarget:self action:@selector(toggleFile:)
        forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;

    return cell;
}

- (void)toggleFile:(UISwitch *)sender {
    NSInteger section = sender.tag / 1000;
    NSInteger row = sender.tag % 1000;
    NSMutableArray<NSString *> *files = [self filesForSection:section];
    if (row >= files.count) {
        return;
    }

    NSString *fileName = files[row];
    NSString *directory = [self pathForSection:section];
    NSString *target = [self isEnabled:fileName]
        ? [fileName stringByAppendingString:kDisabledSuffix]
        : [fileName substringToIndex:fileName.length - kDisabledSuffix.length];

    NSError *error;
    if (![NSFileManager.defaultManager
            moveItemAtPath:[directory stringByAppendingPathComponent:fileName]
            toPath:[directory stringByAppendingPathComponent:target]
            error:&error]) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
        sender.on = !sender.on;
        return;
    }

    files[row] = target;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:section]]
        withRowAnimation:UITableViewRowAnimationNone];

    if (section == kSectionJarMods) {
        [self rebuildAfterJarModChange];
    }
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

    NSMutableArray<NSString *> *files = [self filesForSection:indexPath.section];
    NSString *path = [[self pathForSection:indexPath.section]
        stringByAppendingPathComponent:files[indexPath.row]];

    NSError *error;
    if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
        return;
    }

    [files removeObjectAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[indexPath]
        withRowAnimation:UITableViewRowAnimationAutomatic];

    if (indexPath.section == kSectionJarMods) {
        [self rebuildAfterJarModChange];
    }
}

// A jar mod only takes effect once it has been merged into the client jar, so
// any change to the list means building that jar again
- (void)rebuildAfterJarModChange {
    self.tableView.userInteractionEnabled = NO;
    [JarModUtils rebuildProfile:self.profileName completion:^(NSString *error) {
        self.tableView.userInteractionEnabled = YES;
        if (error) {
            showDialog(localize(@"Error", nil), error);
        }
    }];
}

@end
