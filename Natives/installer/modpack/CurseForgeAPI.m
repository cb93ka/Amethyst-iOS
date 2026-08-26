#import <Foundation/Foundation.h>
#import "CurseForgeAPI.h"
#import "MinecraftResourceDownloadTask.h"
#import "ModpackUtils.h"
#import "PLProfiles.h"
#import "config.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

// Minecraft, and the two categories worth searching in it
static const NSInteger kGameIDMinecraft = 432;
static const NSInteger kClassIDModpack = 4471;
static const NSInteger kClassIDMod = 6;

// CurseForge tags each hash with the algorithm that produced it
static const NSInteger kHashAlgoSHA1 = 1;

@implementation CurseForgeAPI

+ (NSString *)apiKey {
#ifdef CONFIG_HAS_CURSEFORGE_API_KEY
    NSString *key = @CONFIG_CURSEFORGE_API_KEY;
    return key.length > 0 ? key : nil;
#else
    return nil;
#endif
}

+ (BOOL)isAvailable {
    return CurseForgeAPI.apiKey != nil;
}

- (instancetype)init {
    self = [super initWithURL:@"https://api.curseforge.com/v1"];
    self.headers = @{@"x-api-key": CurseForgeAPI.apiKey ?: @""};
    return self;
}

#pragma mark - Search

- (NSMutableArray *)searchModWithFilters:(NSDictionary<NSString *, NSString *> *)searchFilters
                      previousPageResult:(NSMutableArray *)previousResult
{
    BOOL isModpack = searchFilters[@"isModpack"].boolValue;
    NSMutableDictionary *params = @{
        @"gameId": @(kGameIDMinecraft),
        @"classId": @(isModpack ? kClassIDModpack : kClassIDMod),
        @"searchFilter": searchFilters[@"name"] ?: @"",
        @"sortField": @(2), // Popularity
        @"sortOrder": @"desc",
        @"pageSize": @(50),
        @"index": @(previousResult.count)
    }.mutableCopy;

    if ([searchFilters[@"mcVersion"] length] > 0) {
        params[@"gameVersion"] = searchFilters[@"mcVersion"];
    }

    NSDictionary *response = [self getEndpoint:@"mods/search" params:params];
    if (!response) {
        return nil;
    }

    NSMutableArray *result = previousResult ?: [NSMutableArray new];
    for (NSDictionary *mod in response[@"data"]) {
        [result addObject:@{
            @"apiSource": @(0), // Constant CURSEFORGE
            @"isModpack": @(isModpack),
            @"id": [mod[@"id"] stringValue],
            @"title": mod[@"name"] ?: @"",
            @"description": mod[@"summary"] ?: @"",
            @"imageUrl": mod[@"logo"][@"thumbnailUrl"] ?: @""
        }.mutableCopy];
    }

    NSDictionary *pagination = response[@"pagination"];
    self.reachedLastPage = result.count >= [pagination[@"totalCount"] unsignedLongValue];
    return result;
}

- (void)loadDetailsOfMod:(NSMutableDictionary *)item {
    NSDictionary *response = [self getEndpoint:
        [NSString stringWithFormat:@"mods/%@/files", item[@"id"]]
        params:@{@"pageSize": @(50)}];
    if (!response) {
        return;
    }

    NSMutableArray *names = [NSMutableArray new];
    NSMutableArray *mcNames = [NSMutableArray new];
    NSMutableArray *urls = [NSMutableArray new];
    NSMutableArray *hashes = [NSMutableArray new];
    NSMutableArray *sizes = [NSMutableArray new];
    NSMutableArray *fileNames = [NSMutableArray new];

    for (NSDictionary *file in response[@"data"]) {
        [names addObject:file[@"displayName"] ?: file[@"fileName"] ?: @""];
        [mcNames addObject:[file[@"gameVersions"] firstObject] ?: @""];
        [sizes addObject:file[@"fileLength"] ?: @(0)];
        [fileNames addObject:file[@"fileName"] ?: @""];

        // Null when the author opted out of third-party distribution
        id url = file[@"downloadUrl"];
        [urls addObject:([url isKindOfClass:NSString.class] ? url : [NSNull null])];

        id sha = [NSNull null];
        for (NSDictionary *hash in file[@"hashes"]) {
            if ([hash[@"algo"] integerValue] == kHashAlgoSHA1 && hash[@"value"]) {
                sha = hash[@"value"];
                break;
            }
        }
        [hashes addObject:sha];
    }

    item[@"versionNames"] = names;
    item[@"mcVersionNames"] = mcNames;
    item[@"versionSizes"] = sizes;
    item[@"versionUrls"] = urls;
    item[@"versionHashes"] = hashes;
    item[@"versionFileNames"] = fileNames;
    item[@"versionDetailsLoaded"] = @(YES);
}

#pragma mark - Modpack installation

// manifest.json names a loader as "forge-47.3.11"; rewrite it into the
// dependency shape the rest of the launcher already resolves
- (NSDictionary *)dependenciesFromManifest:(NSDictionary *)manifest {
    NSMutableDictionary *dependencies = [NSMutableDictionary new];
    if (manifest[@"minecraft"][@"version"]) {
        dependencies[@"minecraft"] = manifest[@"minecraft"][@"version"];
    }

    for (NSDictionary *loader in manifest[@"minecraft"][@"modLoaders"]) {
        NSString *identifier = loader[@"id"];
        NSRange dash = [identifier rangeOfString:@"-"];
        if (dash.location == NSNotFound) {
            continue;
        }

        NSString *kind = [identifier substringToIndex:dash.location];
        NSString *version = [identifier substringFromIndex:NSMaxRange(dash)];
        if ([kind isEqualToString:@"fabric"]) {
            dependencies[@"fabric-loader"] = version;
        } else if ([kind isEqualToString:@"quilt"]) {
            dependencies[@"quilt-loader"] = version;
        } else if ([kind isEqualToString:@"forge"]) {
            dependencies[@"forge"] = version;
        } else if ([kind isEqualToString:@"neoforge"]) {
            dependencies[@"neoforge"] = version;
        }
    }
    return dependencies;
}

- (void)downloader:(MinecraftResourceDownloadTask *)downloader
    submitDownloadTasksFromPackage:(NSString *)packagePath
                            toPath:(NSString *)destPath
{
    NSError *error;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:packagePath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:
            @"Failed to open modpack package: %@", error.localizedDescription]];
        return;
    }

    NSData *manifestData = [archive extractDataFromFile:@"manifest.json" error:&error];
    NSDictionary *manifest = manifestData
        ? [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error] : nil;
    if (!manifest) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:
            @"Failed to parse manifest.json: %@", error.localizedDescription]];
        return;
    }

    // Asking about each file separately would be hundreds of round trips
    NSMutableArray *fileIDs = [NSMutableArray new];
    for (NSDictionary *file in manifest[@"files"]) {
        if (file[@"fileID"]) {
            [fileIDs addObject:file[@"fileID"]];
        }
    }

    NSDictionary *resolved = [self postEndpoint:@"mods/files" body:@{@"fileIds": fileIDs}];
    if (!resolved) {
        [downloader finishDownloadWithErrorString:
            self.lastError.localizedDescription ?: @"Failed to resolve the modpack's files"];
        return;
    }

    NSMutableArray<NSString *> *blocked = [NSMutableArray new];
    NSArray *entries = resolved[@"data"];
    downloader.progress.totalUnitCount = entries.count;

    for (NSDictionary *file in entries) {
        NSString *fileName = file[@"fileName"] ?: @"";
        id url = file[@"downloadUrl"];
        if (![url isKindOfClass:NSString.class]) {
            // The author turned third-party downloads off on purpose, so this
            // is reported rather than worked around
            [blocked addObject:fileName];
            downloader.progress.completedUnitCount++;
            continue;
        }

        NSString *sha = nil;
        for (NSDictionary *hash in file[@"hashes"]) {
            if ([hash[@"algo"] integerValue] == kHashAlgoSHA1) {
                sha = hash[@"value"];
                break;
            }
        }

        NSString *path = [[destPath stringByAppendingPathComponent:@"mods"]
            stringByAppendingPathComponent:fileName];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:url
            size:[file[@"fileLength"] unsignedLongLongValue]
            sha:sha altName:fileName toPath:path];

        if (task) {
            [downloader.fileList addObject:fileName];
            [task resume];
        } else if (!downloader.progress.cancelled) {
            downloader.progress.completedUnitCount++;
        } else {
            return;
        }
    }

    NSString *overrides = manifest[@"overrides"] ?: @"overrides";
    [ModpackUtils archive:archive extractDirectory:overrides toPath:destPath error:&error];
    if (error) {
        [downloader finishDownloadWithErrorString:[NSString stringWithFormat:
            @"Failed to extract overrides: %@", error.localizedDescription]];
        return;
    }

    [NSFileManager.defaultManager removeItemAtPath:packagePath error:nil];

    NSDictionary *dependencies = [self dependenciesFromManifest:manifest];
    NSDictionary *info = [ModpackUtils infoForDependencies:dependencies];
    NSString *versionId = info[@"id"] ?: dependencies[@"minecraft"];

    if (info[@"json"]) {
        NSString *jsonPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json",
            getenv("POJAV_GAME_DIR"), versionId];
        NSURLSessionDownloadTask *task = [downloader createDownloadTask:info[@"json"]
            size:0 sha:nil altName:nil toPath:jsonPath];
        [task resume];
    }

    NSString *tmpIconPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"icon.png"];
    NSString *name = manifest[@"name"] ?: destPath.lastPathComponent;
    PLProfiles.current.profiles[name] = @{
        @"gameDir": [NSString stringWithFormat:@"./custom_gamedir/%@", destPath.lastPathComponent],
        @"name": name,
        @"lastVersionId": versionId,
        @"icon": [NSString stringWithFormat:@"data:image/png;base64,%@",
            [[NSData dataWithContentsOfFile:tmpIconPath] base64EncodedStringWithOptions:0]]
    }.mutableCopy;
    PLProfiles.current.selectedProfileName = name;

    if (blocked.count > 0) {
        showDialog(localize(@"modpack.title.blocked_files", nil),
            [NSString stringWithFormat:localize(@"modpack.message.blocked_files", nil),
                (unsigned long)blocked.count, [blocked componentsJoinedByString:@"\n"]]);
    }
}

@end
