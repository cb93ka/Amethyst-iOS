#import "PLProfiles.h"
#import "ProfileGameDir.h"
#import "utils.h"

/**
 * Everything in the instance root that either belongs to the launcher or is
 * shared between every profile, and so must not follow one profile into its
 * own folder.
 *
 * This is a list of what stays rather than a list of what moves, so that game
 * data nobody thought of - a mod's own folder, a new resource kind - travels
 * with the profile instead of being left behind.
 */
static NSArray<NSString *> *PLSharedEntries(void) {
    return @[
        @"versions", @"libraries", @"assets",
        @"resources",       // legacy assets, mapped by name for old versions
        @"custom_gamedir",  // where the separated folders themselves live
        @"launcher_profiles.json", @"launcher_preferences.plist"
    ];
}

@implementation ProfileGameDir

+ (NSString *)relativePathForProfileName:(NSString *)name {
    // The name becomes a directory, so anything that would split a path goes
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:"];
    NSString *safe = [[name componentsSeparatedByCharactersInSet:illegal]
        componentsJoinedByString:@"-"];
    safe = [safe stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (safe.length == 0) {
        safe = @"profile";
    }
    return [@"./custom_gamedir/" stringByAppendingString:safe];
}

+ (BOOL)profileSharesRoot:(NSDictionary *)profile {
    NSString *dir = profile[@"gameDir"];
    return dir.length == 0 || [dir isEqualToString:@"."] || [dir isEqualToString:@"./"];
}

+ (NSString *)separateProfileNamed:(NSString *)name {
    NSMutableDictionary *profile = PLProfiles.current.profiles[name];
    if (!profile) {
        return localize(@"profile.gamedir.error.missing", nil);
    }

    NSString *relative = [self relativePathForProfileName:name];
    NSString *root = @(getenv("POJAV_GAME_DIR"));
    NSString *destination = [[root stringByAppendingPathComponent:relative]
        stringByStandardizingPath];

    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error;
    if (![fm createDirectoryAtPath:destination withIntermediateDirectories:YES
            attributes:nil error:&error]) {
        return error.localizedDescription;
    }

    NSArray<NSString *> *shared = PLSharedEntries();
    for (NSString *entry in [fm contentsOfDirectoryAtPath:root error:nil]) {
        if ([shared containsObject:entry]) {
            continue;
        }

        NSString *from = [root stringByAppendingPathComponent:entry];
        NSString *to = [destination stringByAppendingPathComponent:entry];
        if ([fm fileExistsAtPath:to]) {
            // Something is already there; leaving both alone beats overwriting
            continue;
        }
        [fm moveItemAtPath:from toPath:to error:nil];
    }

    profile[@"gameDir"] = relative;
    [PLProfiles.current save];
    return nil;
}

@end
