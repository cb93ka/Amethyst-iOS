#import <Foundation/Foundation.h>
#import "UnzipKit.h"

@interface ModpackUtils : NSObject

+ (void)archive:(UZKArchive *)archive extractDirectory:(NSString *)dir toPath:(NSString *)path error:(NSError **)error;
+ (NSDictionary *)infoForDependencies:(NSDictionary *)dependency;

// Pulls the loader and the Minecraft version back out of a profile's version id,
// so a mod search can be narrowed to what that profile could actually load.
+ (NSDictionary *)loaderInfoForVersionId:(NSString *)versionId;

@end
