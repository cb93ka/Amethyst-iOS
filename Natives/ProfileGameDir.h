#import <Foundation/Foundation.h>

/**
 * Where a profile keeps its game files.
 *
 * Every profile owns a folder under instances/. What stays shared is the
 * content that is identical for all of them and measured in gigabytes:
 * versions, libraries and assets. Prism draws the line in the same place.
 */
@interface ProfileGameDir : NSObject

// Where a profile of this name should keep its files, in the relative form a
// profile's gameDir is stored in.
+ (NSString *)relativePathForProfileName:(NSString *)name;

// YES when the profile still shares the instance root with everything else.
+ (BOOL)profileSharesRoot:(NSDictionary *)profile;

/**
 * Deletes the folder a profile kept its files in. Does nothing when the
 * profile shared the instance root, since those files belong to the others too.
 */
+ (void)removeFolderOfProfile:(NSDictionary *)profile;

@end
