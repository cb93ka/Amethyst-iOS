#import <Foundation/Foundation.h>

/**
 * Keeps each profile's game files apart.
 *
 * Profiles used to share the instance root, so worlds, mods and options from
 * every version piled up in one folder. A profile now gets a folder of its
 * own instead.
 *
 * What stays shared is the content that is identical for every profile and
 * measured in gigabytes: versions, libraries and assets. Prism draws the line
 * in the same place.
 */
@interface ProfileGameDir : NSObject

// Where a profile of this name should keep its files, in the relative form a
// profile's gameDir is stored in.
+ (NSString *)relativePathForProfileName:(NSString *)name;

// YES when the profile still shares the instance root with everything else.
+ (BOOL)profileSharesRoot:(NSDictionary *)profile;

/**
 * Moves an existing profile's files out of the shared root into its own folder.
 * Returns nil on success, or a message describing what stopped it.
 */
+ (NSString *)separateProfileNamed:(NSString *)name;

/**
 * Deletes the folder a profile kept its files in. Does nothing when the
 * profile shared the instance root, since those files belong to the others too.
 */
+ (void)removeFolderOfProfile:(NSDictionary *)profile;

@end
