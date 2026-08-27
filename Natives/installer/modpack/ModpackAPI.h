#import <Foundation/Foundation.h>
#import "ModpackUtils.h"
#import "UnzipKit.h"

@class MinecraftResourceDownloadTask;

@interface ModpackAPI : NSObject
@property(nonatomic) NSString *baseURL;
@property(nonatomic) NSError *lastError;
@property(nonatomic) BOOL reachedLastPage;
// Sent with every request; CurseForge authenticates through one
@property(nonatomic) NSDictionary *headers;

- (instancetype)initWithURL:(NSString *)url;
- (NSMutableArray *)searchModWithFilters:(NSDictionary *)filters previousPageResult:(NSMutableArray *)prevResult;
- (void)loadDetailsOfMod:(NSMutableDictionary *)item;

- (void)installModpackFromDetail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion;
// A mod belongs to one profile; nil means whichever is selected
- (void)installModFromDetail:(NSDictionary *)modDetail atIndex:(NSUInteger)selectedVersion toProfile:(NSString *)profileName;
- (void)downloader:(MinecraftResourceDownloadTask *)downloader submitDownloadTasksFromPackage:(NSString *)packagePath toPath:(NSString *)destPath;

- (id)getEndpoint:(NSString *)endpoint params:(NSDictionary *)params;
- (id)postEndpoint:(NSString *)endpoint body:(NSDictionary *)body;

@end
