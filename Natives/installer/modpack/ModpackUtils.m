#import "installer/FabricUtils.h"
#import "ModpackUtils.h"

@implementation ModpackUtils

+ (void)archive:(UZKArchive *)archive extractDirectory:(NSString *)dir toPath:(NSString *)path error:(NSError *__autoreleasing*)error {
    [archive performOnFilesInArchive:^(UZKFileInfo *fileInfo, BOOL *stop) {
        if (![fileInfo.filename hasPrefix:dir] ||
            fileInfo.filename.length <= dir.length) {
            return;
        }
        NSString *fileName = [fileInfo.filename substringFromIndex:dir.length+1];
        NSString *destItemPath = [path stringByAppendingPathComponent:fileName];
        NSString *destDirPath = fileInfo.isDirectory ? destItemPath : destItemPath.stringByDeletingLastPathComponent;
        BOOL createdDir = [NSFileManager.defaultManager createDirectoryAtPath:destDirPath
            withIntermediateDirectories:YES
            attributes:nil error:error];
        if (!createdDir) {
            *stop = YES;
            return;
        } else if (fileInfo.isDirectory) {
            return;
        }

        NSData *data = [archive extractData:fileInfo error:error];
        BOOL written = [data writeToFile:destItemPath options:NSDataWritingAtomic error:error];
        *stop = !data || !written;
        if (!*stop) {
            NSLog(@"[ModpackDL] Extracted %@", fileInfo.filename);
        }
    } error:error];
}

+ (NSDictionary *)loaderInfoForVersionId:(NSString *)versionId {
    if (versionId.length == 0) return @{};

    NSString *lower = versionId.lowercaseString;
    NSString *loader = nil;
    // neoforge has to be tested before forge, since it contains it
    for (NSString *candidate in @[@"neoforge", @"fabric", @"quilt", @"forge"]) {
        if ([lower containsString:candidate]) {
            loader = candidate;
            break;
        }
    }

    // Version ids come in two shapes: "<loader>-loader-<x>-<mc>" and "<mc>-<loader>-<x>"
    NSString *mcVersion = versionId;
    NSRange loaderRange = loader ? [lower rangeOfString:loader] : NSMakeRange(NSNotFound, 0);
    if (loaderRange.location == 0) {
        NSRange lastDash = [versionId rangeOfString:@"-" options:NSBackwardsSearch];
        if (lastDash.location != NSNotFound) {
            mcVersion = [versionId substringFromIndex:NSMaxRange(lastDash)];
        }
    } else if (loaderRange.location != NSNotFound) {
        mcVersion = [versionId substringToIndex:loaderRange.location - 1];
    }

    NSMutableDictionary *info = [NSMutableDictionary new];
    if (loader) info[@"loader"] = loader;
    if (mcVersion.length) info[@"mcVersion"] = mcVersion;
    return info;
}

+ (NSDictionary *)infoForDependencies:(NSDictionary *)dependency {
    NSMutableDictionary *info = [NSMutableDictionary new];
    NSString *minecraftVersion = dependency[@"minecraft"];
    if (dependency[@"forge"]) {
        info[@"id"] = [NSString stringWithFormat:@"%@-forge-%@", minecraftVersion, dependency[@"forge"]];
    } else if (dependency[@"fabric-loader"]) {
        info[@"id"] = [NSString stringWithFormat:@"fabric-loader-%@-%@", dependency[@"fabric-loader"], minecraftVersion];
        info[@"json"] = [NSString stringWithFormat:FabricUtils.endpoints[@"Fabric"][@"json"], minecraftVersion, dependency[@"fabric-loader"]];
    } else if (dependency[@"quilt-loader"]) {
        info[@"id"] = [NSString stringWithFormat:@"quilt-loader-%@-%@", dependency[@"quilt-loader"], minecraftVersion];
        info[@"json"] = [NSString stringWithFormat:FabricUtils.endpoints[@"Quilt"][@"json"], minecraftVersion, dependency[@"quilt-loader"]];
    }
    return info;
}

@end
