#import <Foundation/Foundation.h>

/**
 * Jar mods, kept the way MultiMC keeps them.
 *
 * Versions old enough to have no mod loader can only take a mod by having it
 * merged into the client jar. Merging is one-way, so the mods themselves are
 * kept in the profile, under jarmods/, and the patched version is rebuilt from
 * the untouched base plus whatever is currently switched on. That is what makes
 * a mod possible to switch off again, or remove.
 *
 * The profile remembers its base in jarmodBase, so rebuilding never patches an
 * already patched jar.
 */
@interface JarModUtils : NSObject

// Where a profile keeps the jar mods it was given
+ (NSString *)jarModsPathForProfile:(NSString *)profileName;

// Whether the version this profile patches has been downloaded, and so whether
// there is anything to merge into yet
+ (BOOL)canPatchProfile:(NSString *)profileName;

// Copies the files in, then rebuilds. Calls back on the main thread.
+ (void)addMods:(NSArray<NSString *> *)modPaths
      toProfile:(NSString *)profileName
     completion:(void (^)(NSString *error))completion;

// Rebuilds after a mod was switched or removed. Calls back on the main thread.
+ (void)rebuildProfile:(NSString *)profileName
            completion:(void (^)(NSString *error))completion;

/**
 * Same, on the calling thread, for use just before a launch so the version
 * about to run is the current one. Returns nil when there was nothing to do,
 * or when it succeeded.
 */
+ (NSString *)rebuildProfileNow:(NSString *)profileName;

@end
