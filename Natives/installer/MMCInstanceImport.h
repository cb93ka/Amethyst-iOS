#import <Foundation/Foundation.h>

/**
 * Imports an instance exported from MultiMC or Prism Launcher.
 *
 * The export is a zip holding mmc-pack.json, instance.cfg and the game folder.
 * Its components map onto the same loader description a Modrinth pack declares,
 * so the version id and the loader manifest are resolved by the existing code
 * rather than a second implementation.
 */
@interface MMCInstanceImport : NSObject

/**
 * Runs off the main thread and calls back on it.
 *
 * `error` is nil when the instance was imported. `warning` is set when the
 * files landed but something still needs doing by hand - typically a Forge
 * loader, which cannot be installed without running its installer.
 */
+ (void)importFromZipAtPath:(NSString *)path
                 completion:(void (^)(NSString *error, NSString *warning))completion;

@end
