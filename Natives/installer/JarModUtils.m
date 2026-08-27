#import "JarModUtils.h"
#import "UnzipKit.h"
#import "utils.h"

@implementation JarModUtils

+ (NSString *)versionsDirectory {
    return [NSString stringWithFormat:@"%s/versions", getenv("POJAV_GAME_DIR")];
}

+ (NSArray<NSString *> *)patchableVersions {
    NSString *root = self.versionsDirectory;
    NSMutableArray<NSString *> *versions = [[NSMutableArray alloc] init];

    for (NSString *versionId in [NSFileManager.defaultManager
            contentsOfDirectoryAtPath:root error:nil]) {
        NSString *jar = [NSString stringWithFormat:@"%1$@/%2$@/%2$@.jar", root, versionId];
        if ([NSFileManager.defaultManager fileExistsAtPath:jar]) {
            [versions addObject:versionId];
        }
    }
    return [versions sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

// Reads every mod, last one winning where two touch the same file
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

+ (NSString *)runPatch:(NSString *)baseVersionId
                  mods:(NSArray<NSString *> *)modPaths
             newVersion:(NSString **)outVersionId
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = self.versionsDirectory;
    NSString *baseJar = [NSString stringWithFormat:@"%1$@/%2$@/%2$@.jar", root, baseVersionId];
    NSString *baseJson = [NSString stringWithFormat:@"%1$@/%2$@/%2$@.json", root, baseVersionId];

    if (![fm fileExistsAtPath:baseJar]) {
        return localize(@"profile.jarmod.error.no_jar", nil);
    }

    NSString *modError = nil;
    NSDictionary<NSString *, NSData *> *modEntries = [self entriesFromMods:modPaths error:&modError];
    if (!modEntries) {
        return modError;
    }
    if (modEntries.count == 0) {
        return localize(@"profile.jarmod.error.empty_mod", nil);
    }

    // Keep the base version intact by patching a copy under a new id
    NSString *newId = [baseVersionId stringByAppendingString:@"-jarmod"];
    for (int n = 2; [fm fileExistsAtPath:[root stringByAppendingPathComponent:newId]]; n++) {
        newId = [NSString stringWithFormat:@"%@-jarmod-%d", baseVersionId, n];
    }

    NSString *newDir = [root stringByAppendingPathComponent:newId];
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

    // A self-contained manifest: inheriting would let the downloader restore the
    // stock client jar over the patched one on the next launch
    NSMutableDictionary *json = parseJSONFromFile(baseJson);
    if (json[@"NSErrorObject"]) {
        return [json[@"NSErrorObject"] localizedDescription];
    }
    json[@"id"] = newId;
    [json removeObjectForKey:@"downloads"];
    [json removeObjectForKey:@"inheritsFrom"];

    NSError *saveError = saveJSONToFile(json, [newDir stringByAppendingPathComponent:
        [newId stringByAppendingPathExtension:@"json"]]);
    if (saveError) {
        return saveError.localizedDescription;
    }

    *outVersionId = newId;
    return nil;
}

+ (void)patchVersion:(NSString *)baseVersionId
            withMods:(NSArray<NSString *> *)modPaths
          completion:(void (^)(NSString *error, NSString *newVersionId))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *newId = nil;
        NSString *error = [self runPatch:baseVersionId mods:modPaths newVersion:&newId];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error, newId);
        });
    });
}

@end
