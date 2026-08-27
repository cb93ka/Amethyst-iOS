#import <Foundation/Foundation.h>

/**
 * Installs mods the way versions that predate a mod loader need them: by
 * patching the client jar itself, as MultiMC does.
 *
 * Files from the mods replace the client's own, and META-INF is dropped. The
 * client carries a signature over its classes there, and refuses to start once
 * those classes no longer match it.
 *
 * The original version is left untouched; the patched jar becomes a version of
 * its own, so the same base can be patched more than once.
 */
@interface JarModUtils : NSObject

// Locally installed versions that have a client jar available to patch
+ (NSArray<NSString *> *)patchableVersions;

/**
 * Runs off the main thread and calls back on it with nil on success, or a
 * message explaining what stopped it. On success the new version id is handed
 * back for the caller to point a profile at.
 */
+ (void)patchVersion:(NSString *)baseVersionId
            withMods:(NSArray<NSString *> *)modPaths
          completion:(void (^)(NSString *error, NSString *newVersionId))completion;

@end
