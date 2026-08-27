#import "JarModUtils.h"
#import "PLProfiles.h"
#import "UnzipKit.h"
#import "utils.h"

// Same convention the mods folder uses, so one rule covers both
static NSString *const kDisabledSuffix = @".disabled";

@implementation JarModUtils

+ (NSString *)versionsDirectory {
    return [NSString stringWithFormat:@"%s/versions", getenv("POJAV_GAME_DIR")];
}

+ (NSString *)jarModsPathForProfile:(NSString *)profileName {
    NSMutableDictionary *profile = PLProfiles.current.profiles[profileName];
    NSString *gameDir = [profile[@"gameDir"] length] > 0 ? profile[@"gameDir"] : @".";
    return [[[@(getenv("POJAV_GAME_DIR"))
        stringByAppendingPathComponent:gameDir]
        stringByAppendingPathComponent:@"jarmods"] stringByStandardizingPath];
}

+ (NSArray<NSString *> *)enabledModsAt:(NSString *)path {
    NSMutableArray<NSString *> *enabled = [[NSMutableArray alloc] init];
    for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil]
            sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if ([name hasSuffix:kDisabledSuffix] || [name hasPrefix:@"."]) {
            continue;
        }
        [enabled addObject:[path stringByAppendingPathComponent:name]];
    }
    return enabled;
}

// Reads every mod, the last one winning where two touch the same file
+ (NSDictionary<NSString *, NSData *> *)entriesFromMods:(NSArray<NSString *> *)modPaths
                                                  error:(NSString **)outError
{
    NSMutableDictionary<NSString *, NSData *> *entries = [[NSMutableDictionary alloc] init];

    for (NSString *modPath in modPaths) {
        NSError *error;
        UZKArchive *mod = [[UZKArchive alloc] initWithPath:modPath error:&error];
        if (!mod) {
            *outError = error.localizedDescription;
            return nil;
        }

        [mod performOnDataInArchive:^(UZKFileInfo *info, NSData *data, BOOL *stop) {
            if (info.isDirectory || [info.filename hasPrefix:@"META-INF/"]) {
                return;
            }
            entries[info.filename] = data;
        } error:&error];

        if (error) {
            *outError = error.localizedDescription;
            return nil;
        }
    }
    return entries;
}

+ (NSString *)derivedIdForBase:(NSString *)base profile:(NSString *)profileName {
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\: "];
    NSString *safe = [[profileName componentsSeparatedByCharactersInSet:illegal]
        componentsJoinedByString:@"-"];
    return [NSString stringWithFormat:@"%@-jarmod-%@", base, safe];
}

#pragma mark - Building

+ (NSString *)buildVersion:(NSString *)newId
                  fromBase:(NSString *)base
                      mods:(NSArray<NSString *> *)modPaths
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = self.versionsDirectory;
    NSString *baseJar = [NSString stringWithFormat:@"%1$@/%2$@/%2$@.jar", root, base];
    NSString *baseJson = [NSString stringWithFormat:@"%1$@/%2$@/%2$@.json", root, base];

    if (![fm fileExistsAtPath:baseJar]) {
        return localize(@"profile.jarmod.error.no_jar", nil);
    }

    NSString *modError = nil;
    NSDictionary<NSString *, NSData *> *modEntries = [self entriesFromMods:modPaths error:&modError];
    if (!modEntries) {
        return modError;
    }

    // Always start from the untouched base, so switching a mod off really
    // removes it rather than leaving it merged in from a previous build
    NSString *newDir = [root stringByAppendingPathComponent:newId];
    [fm removeItemAtPath:newDir error:nil];

    NSError *error;
    if (![fm createDirectoryAtPath:newDir withIntermediateDirectories:YES attributes:nil error:&error]) {
        return error.localizedDescription;
    }

    NSString *newJar = [newDir stringByAppendingPathComponent:
        [newId stringByAppendingPathExtension:@"jar"]];
    if (![fm copyItemAtPath:baseJar toPath:newJar error:&error]) {
        return error.localizedDescription;
    }

    // Editing a copy of a valid archive, rather than building one from nothing
    UZKArchive *jar = [[UZKArchive alloc] initWithPath:newJar error:&error];
    if (!jar) {
        return error.localizedDescription;
    }

    // The client carries a signature over its classes there and refuses to
    // start once those classes no longer match it
    for (NSString *entry in [jar listFilenames:&error]) {
        if ([entry hasPrefix:@"META-INF/"] && ![jar deleteFile:entry error:&error]) {
            return error.localizedDescription;
        }
    }
    if (error) {
        return error.localizedDescription;
    }

    for (NSString *entry in modEntries) {
        if (![jar writeData:modEntries[entry] filePath:entry error:&error]) {
            return error.localizedDescription;
        }
    }

    // A self-contained manifest: inheriting would keep the base version's client
    // download, and the downloader would restore the stock jar over this one
    NSMutableDictionary *json = parseJSONFromFile(baseJson);
    if (json[@"NSErrorObject"]) {
        return [json[@"NSErrorObject"] localizedDescription];
    }
    json[@"id"] = newId;
    [json removeObjectForKey:@"downloads"];
    [json removeObjectForKey:@"inheritsFrom"];

    NSError *saveError = saveJSONToFile(json, [newDir stringByAppendingPathComponent:
        [newId stringByAppendingPathExtension:@"json"]]);
    return saveError.localizedDescription;
}

+ (NSString *)rebuildProfileNow:(NSString *)profileName {
    NSMutableDictionary *profile = PLProfiles.current.profiles[profileName];
    if (!profile) {
        return nil;
    }

    NSString *base = profile[@"jarmodBase"];
    if (base.length == 0) {
        base = profile[@"lastVersionId"];
    }
    if (base.length == 0) {
        return nil;
    }

    NSArray<NSString *> *mods = [self enabledModsAt:[self jarModsPathForProfile:profileName]];
    NSString *derived = [self derivedIdForBase:base profile:profileName];

    if (mods.count == 0) {
        // Nothing switched on: the profile goes back to the version it started
        // from, and the patched one is of no further use
        [NSFileManager.defaultManager removeItemAtPath:
            [self.versionsDirectory stringByAppendingPathComponent:derived] error:nil];
        profile[@"lastVersionId"] = base;
        [profile removeObjectForKey:@"jarmodBase"];
        [PLProfiles.current save];
        return nil;
    }

    NSString *error = [self buildVersion:derived fromBase:base mods:mods];
    if (error) {
        return error;
    }

    profile[@"jarmodBase"] = base;
    profile[@"lastVersionId"] = derived;
    [PLProfiles.current save];
    return nil;
}

#pragma mark - Entry points

+ (void)rebuildProfile:(NSString *)profileName completion:(void (^)(NSString *error))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *error = [self rebuildProfileNow:profileName];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error);
        });
    });
}

+ (void)addMods:(NSArray<NSString *> *)modPaths
      toProfile:(NSString *)profileName
     completion:(void (^)(NSString *error))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *destination = [self jarModsPathForProfile:profileName];
        [fm createDirectoryAtPath:destination withIntermediateDirectories:YES
            attributes:nil error:nil];

        NSString *failure = nil;
        for (NSString *path in modPaths) {
            NSString *target = [destination stringByAppendingPathComponent:path.lastPathComponent];
            [fm removeItemAtPath:target error:nil];

            NSError *error;
            if (![fm copyItemAtPath:path toPath:target error:&error]) {
                failure = error.localizedDescription;
                break;
            }
        }

        NSString *error = failure ?: [self rebuildProfileNow:profileName];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error);
        });
    });
}

@end
