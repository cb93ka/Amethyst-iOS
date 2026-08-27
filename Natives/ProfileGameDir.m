#import "PLProfiles.h"
#import "ProfileGameDir.h"
#import "utils.h"

// Profile folders all live here, under the launcher root
static NSString *const kInstancesFolder = @"instances";

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
    return [NSString stringWithFormat:@"./%@/%@", kInstancesFolder, safe];
}

+ (BOOL)profileSharesRoot:(NSDictionary *)profile {
    NSString *dir = profile[@"gameDir"];
    return dir.length == 0 || [dir isEqualToString:@"."] || [dir isEqualToString:@"./"];
}

+ (void)removeFolderOfProfile:(NSDictionary *)profile {
    if ([self profileSharesRoot:profile]) {
        // Left over from the old layout: that folder is the launcher root
        return;
    }

    NSString *root = [@(getenv("POJAV_GAME_DIR")) stringByStandardizingPath];
    NSString *path = [[root stringByAppendingPathComponent:profile[@"gameDir"]]
        stringByStandardizingPath];

    // Only ever delete inside instances/. A profile whose gameDir points
    // somewhere else would otherwise take the launcher's own files with it.
    NSString *allowed = [[root stringByAppendingPathComponent:kInstancesFolder]
        stringByAppendingString:@"/"];
    if (![path hasPrefix:allowed] || path.length == allowed.length) {
        NSLog(@"[Profiles] Refusing to delete %@: outside %@", path, allowed);
        return;
    }

    NSError *error;
    if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]
            && error.code != NSFileNoSuchFileError) {
        NSLog(@"[Profiles] Could not delete %@: %@", path, error.localizedDescription);
    }
}

@end
