#import <Foundation/Foundation.h>
#import "ModpackAPI.h"

@interface CurseForgeAPI : ModpackAPI

// CurseForge refuses every request without a key, so the source is only worth
// offering when one was compiled in
+ (BOOL)isAvailable;

@end
