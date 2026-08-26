#import "MMCInstanceImport.h"
#import "PLProfiles.h"
#import "UnzipKit.h"
#import "modpack/ModpackUtils.h"
#import "utils.h"

static NSString *const kPackFile = @"mmc-pack.json";
static NSString *const kConfigFile = @"instance.cfg";

@implementation MMCInstanceImport

// An export may be zipped with or without a wrapping folder
+ (NSString *)prefixOfFileNamed:(NSString *)name in:(NSArray<NSString *> *)files {
    for (NSString *file in files) {
        if ([file.lastPathComponent isEqualToString:name]) {
            NSString *dir = file.stringByDeletingLastPathComponent;
            return dir.length > 0 ? [dir stringByAppendingString:@"/"] : @"";
        }
    }
    return nil;
}

// instance.cfg is a Java properties file; only the display name matters here
+ (NSString *)nameFromConfig:(NSString *)config {
    for (NSString *line in [config componentsSeparatedByCharactersInSet:
            NSCharacterSet.newlineCharacterSet]) {
        if ([line hasPrefix:@"name="]) {
            return [[line substringFromIndex:5]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }
    }
    return nil;
}

/**
 * Rewrites mmc-pack components into the shape a Modrinth pack declares its
 * dependencies in, so the version id and loader manifest come from the code
 * that already resolves them.
 */
+ (NSDictionary *)dependenciesFromPack:(NSDictionary *)pack {
    NSDictionary *uidMap = @{
        @"net.minecraft": @"minecraft",
        @"net.fabricmc.fabric-loader": @"fabric-loader",
        @"org.quiltmc.quilt-loader": @"quilt-loader",
        @"net.minecraftforge": @"forge",
        @"net.neoforged": @"neoforge"
    };

    NSMutableDictionary *dependencies = [[NSMutableDictionary alloc] init];
    for (NSDictionary *component in pack[@"components"]) {
        NSString *key = uidMap[component[@"uid"]];
        if (key && component[@"version"]) {
            dependencies[key] = component[@"version"];
        }
    }
    return dependencies;
}

+ (NSString *)gameFolderIn:(NSArray<NSString *> *)files prefix:(NSString *)prefix {
    // The folder was renamed between format versions
    for (NSString *candidate in @[@".minecraft", @"minecraft"]) {
        NSString *folder = [prefix stringByAppendingString:candidate];
        NSString *probe = [folder stringByAppendingString:@"/"];
        for (NSString *file in files) {
            if ([file hasPrefix:probe]) {
                return folder;
            }
        }
    }
    return nil;
}

+ (NSString *)runImportAtPath:(NSString *)path warning:(NSString **)outWarning {
    NSError *error;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:&error];
    if (!archive) {
        return error.localizedDescription;
    }

    NSArray<NSString *> *files = [archive listFilenames:&error];
    if (!files) {
        return error.localizedDescription;
    }

    NSString *prefix = [self prefixOfFileNamed:kPackFile in:files];
    if (!prefix) {
        return localize(@"profile.import.error.not_instance", nil);
    }

    NSData *packData = [archive extractDataFromFile:
        [prefix stringByAppendingString:kPackFile] error:&error];
    if (!packData) {
        return error.localizedDescription;
    }
    NSDictionary *pack = [NSJSONSerialization JSONObjectWithData:packData options:0 error:&error];
    if (!pack) {
        return error.localizedDescription;
    }

    NSDictionary *dependencies = [self dependenciesFromPack:pack];
    if (!dependencies[@"minecraft"]) {
        return localize(@"profile.import.error.no_version", nil);
    }

    NSString *name;
    NSData *configData = [archive extractDataFromFile:
        [prefix stringByAppendingString:kConfigFile] error:nil];
    if (configData) {
        name = [self nameFromConfig:
            [[NSString alloc] initWithData:configData encoding:NSUTF8StringEncoding]];
    }
    if (name.length == 0) {
        name = path.lastPathComponent.stringByDeletingPathExtension;
    }
    // The name becomes a directory, so it has to stay one path component
    name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"-"];

    NSString *gameFolder = [self gameFolderIn:files prefix:prefix];
    if (!gameFolder) {
        return localize(@"profile.import.error.no_gamedir", nil);
    }

    NSString *destPath = [NSString stringWithFormat:@"%s/custom_gamedir/%@",
        getenv("POJAV_GAME_DIR"), name];
    [ModpackUtils archive:archive extractDirectory:gameFolder toPath:destPath error:&error];
    if (error) {
        return error.localizedDescription;
    }

    NSDictionary *info = [ModpackUtils infoForDependencies:dependencies];
    NSString *versionId = info[@"id"] ?: dependencies[@"minecraft"];

    if (info[@"json"]) {
        // Fabric and Quilt publish a ready profile, so the loader can be set up here
        NSData *json = [NSData dataWithContentsOfURL:[NSURL URLWithString:info[@"json"]]];
        if (json) {
            NSString *jsonPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json",
                getenv("POJAV_GAME_DIR"), versionId];
            [NSFileManager.defaultManager
                createDirectoryAtPath:jsonPath.stringByDeletingLastPathComponent
                withIntermediateDirectories:YES attributes:nil error:nil];
            [json writeToFile:jsonPath atomically:YES];
        } else {
            *outWarning = localize(@"profile.import.warn.loader_offline", nil);
        }
    } else if (dependencies[@"forge"] || dependencies[@"neoforge"]) {
        // Forge has to be put in by its own installer, which needs a person
        *outWarning = [NSString stringWithFormat:
            localize(@"profile.import.warn.forge", nil), versionId];
    }

    PLProfiles.current.profiles[name] = @{
        @"name": name,
        @"gameDir": [@"./custom_gamedir/" stringByAppendingString:name],
        @"lastVersionId": versionId
    }.mutableCopy;
    PLProfiles.current.selectedProfileName = name;

    return nil;
}

+ (void)importFromZipAtPath:(NSString *)path
                 completion:(void (^)(NSString *error, NSString *warning))completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *warning = nil;
        NSString *error = [self runImportAtPath:path warning:&warning];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error, warning);
        });
    });
}

@end
