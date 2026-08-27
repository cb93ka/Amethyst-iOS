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

/*
 * Everything the merged jar should hold: the client first, then each mod over
 * it, the last one winning where two touch the same file.
 *
 * META-INF is dropped on the way. The client carries a signature over its
 * classes there, and refuses to start once those classes no longer match it.
 */
+ (NSMutableDictionary<NSString *, NSData *> *)entriesFromArchives:(NSArray<NSString *> *)paths
                                                             error:(NSString **)outError
{
    NSMutableDictionary<NSString *, NSData *> *entries = [[NSMutableDictionary alloc] init];

    for (NSString *path in paths) {
        NSError *error;
        UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:&error];
        if (!archive) {
            *outError = error.localizedDescription;
            return nil;
        }

        [archive performOnDataInArchive:^(UZKFileInfo *info, NSData *data, BOOL *stop) {
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

/*
 * What the enabled mods look like right now, so a rebuild that would produce
 * the same jar can be skipped. Merging takes long enough to be worth not doing
 * on the way into a game.
 */
+ (NSString *)stampForMods:(NSArray<NSString *> *)modPaths {
    NSMutableArray<NSString *> *parts = [[NSMutableArray alloc] init];
    for (NSString *path in modPaths) {
        NSDictionary *attributes = [NSFileManager.defaultManager
            attributesOfItemAtPath:path error:nil];
        [parts addObject:[NSString stringWithFormat:@"%@:%@:%f",
            path.lastPathComponent,
            attributes[NSFileSize] ?: @(0),
            [attributes[NSFileModificationDate] timeIntervalSince1970]]];
    }
    return [parts componentsJoinedByString:@"|"];
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

    NSString *readError = nil;
    NSMutableDictionary<NSString *, NSData *> *entries =
        [self entriesFromArchives:[@[baseJar] arrayByAddingObjectsFromArray:modPaths]
                            error:&readError];
    if (!entries) {
        return readError;
    }

    /*
     * Written out in one pass as a jar of its own, rather than edited into a
     * copy of the client. Changing an entry of an archive in place rewrites the
     * whole archive, and the mods between them have as many entries as it would
     * take rewrites; the wait was long enough to look like the launcher had
     * stopped. Building from nothing also means starting from the untouched
     * client every time, so switching a mod off really removes it.
     */
    NSString *newDir = [root stringByAppendingPathComponent:newId];
    [fm removeItemAtPath:newDir error:nil];

    NSError *error;
    if (![fm createDirectoryAtPath:newDir withIntermediateDirectories:YES attributes:nil error:&error]) {
        return error.localizedDescription;
    }

    NSString *newJar = [newDir stringByAppendingPathComponent:
        [newId stringByAppendingPathExtension:@"jar"]];
    UZKArchive *jar = [[UZKArchive alloc] initWithPath:newJar error:&error];
    if (!jar) {
        return error.localizedDescription;
    }

    for (NSString *name in entries) {
        // Nothing here is written twice, so there is no entry to overwrite, and
        // saying so keeps each write from copying the archive to find that out
        if (![jar writeData:entries[name] filePath:name fileDate:nil
                posixPermissions:0644 compressionMethod:UZKCompressionMethodDefault
                password:nil overwrite:NO error:&error]) {
            return error.localizedDescription;
        }
    }

    // A jar that came out short would be found by the game rather than here,
    // as a missing class in the middle of starting up
    NSUInteger written = [[[UZKArchive alloc] initWithPath:newJar error:nil]
        listFilenames:nil].count;
    if (written != entries.count) {
        [fm removeItemAtPath:newDir error:nil];
        return localize(@"profile.jarmod.error.incomplete", nil);
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
    BOOL wasPatched = base.length > 0;
    if (!wasPatched) {
        base = profile[@"lastVersionId"];
    }
    if (base.length == 0) {
        return nil;
    }

    NSArray<NSString *> *mods = [self enabledModsAt:[self jarModsPathForProfile:profileName]];
    NSString *derived = [self derivedIdForBase:base profile:profileName];

    // Nothing was ever merged and nothing asks to be, which is every profile
    // that has no jar mods at all
    if (mods.count == 0 && !wasPatched) {
        return nil;
    }

    NSString *stamp = [self stampForMods:mods];
    if (wasPatched && [profile[@"jarmodStamp"] isEqualToString:stamp] &&
        [NSFileManager.defaultManager fileExistsAtPath:
            [self.versionsDirectory stringByAppendingPathComponent:derived]]) {
        // The jar already standing is the one this would build
        return nil;
    }

    if (mods.count == 0) {
        // Nothing switched on: the profile goes back to the version it started
        // from, and the patched one is of no further use
        [NSFileManager.defaultManager removeItemAtPath:
            [self.versionsDirectory stringByAppendingPathComponent:derived] error:nil];
        profile[@"lastVersionId"] = base;
        [profile removeObjectForKey:@"jarmodBase"];
        [profile removeObjectForKey:@"jarmodStamp"];
        [PLProfiles.current save];
        return nil;
    }

    NSString *error = [self buildVersion:derived fromBase:base mods:mods];
    if (error) {
        return error;
    }

    profile[@"jarmodBase"] = base;
    profile[@"jarmodStamp"] = stamp;
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
