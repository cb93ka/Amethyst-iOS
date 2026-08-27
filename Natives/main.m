#import <mach-o/dyld.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <UIKit/UIKit.h>

#import "AppDelegate.h"
#import "customcontrols/CustomControlsUtils.h"
#import "HostManagerBridge.h"
#import "JavaLauncher.h"
#import "LauncherPreferences.h"
#import "PLLogOutputView.h"
#import "PLProfiles.h"
#import "SurfaceViewController.h"
#import "UIKit+hook.h"
#import "config.h"

#include <libgen.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include "utils.h"
#include "codesign.h"

#define CS_PLATFORM_BINARY 0x4000000
#define PT_TRACE_ME 0
#define PT_DETACH 11 
int ptrace(int, pid_t, caddr_t, int);
#define fm NSFileManager.defaultManager
extern char** environ;

void printEntitlementAvailability(NSString *key) {
    NSLog(@"* %@: %@", key, getEntitlementValue(key) ? @"YES" : @"NO");
}

void uncaughtExceptionHandler(NSException *exception) {
    NSLog(@"Uncaught exception: %@", exception.description);
    NSLog(@"Call stack: %@", exception.callStackSymbols);
    usleep(10000);
    handle_fatal_exit(SIGABRT);
}

bool init_checkForsubstrated() {
    // Please kindly tell pwn20wnd that he sucks
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t miblen = 4;
    size_t size;
    int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
    struct kinfo_proc * process = NULL;
    struct kinfo_proc * newprocess = NULL;
    do {
        size += size / 10;
        newprocess = realloc(process, size);
        if (!newprocess){
            if (process){
                free(process);
            }
            return nil;
        }
        process = newprocess;
        st = sysctl(mib, miblen, process, &size, NULL, 0);
    } while (st == -1 && errno == ENOMEM);
    if (st == 0){
        if (size % sizeof(struct kinfo_proc) == 0){
            int nprocess = size / sizeof(struct kinfo_proc);
            if (nprocess){
                for (int i = nprocess - 1; i >= 0; i--){
                    if(strcmp(process[i].kp_proc.p_comm,"substrated") == 0) {
                        return true;
                    }
                }
            }
        }
    }
    return false;
}

bool init_checkForJailbreak() {
    if (NSProcessInfo.processInfo.macCatalystApp) {
        // macOS doesn't automatically enable JIT.
        return false;
    } else if (init_checkForsubstrated()) {
        return true;
    }

    // Check if posix_spawn is hooked
    for (int i=0; i < _dyld_image_count(); i++) {
        if (strcmp(_dyld_get_image_name(i),"/usr/lib/pspawn_payload-stg2.dylib") == 0 ||
            strstr(_dyld_get_image_name(i),"/systemhook.dylib") != NULL) {
            return true;
        }
    }

    // Check if we have platform bit set
    uint32_t flags;
    csops(0, CS_OPS_STATUS, &flags, sizeof(flags));
    if ((flags & CS_PLATFORM_BINARY) != 0) {
        return true;
    }

    return opendir("/Applications") != NULL;
}

void init_logDeviceAndVer(char *argument) {
    // Amethyst version
    NSLog(@"[Pre-Init] Amethyst INIT!");
    NSLog(@"[Pre-Init] Version: %@-%s", NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"], CONFIG_TYPE);
    NSLog(@"[Pre-Init] Commit: %s (%s)", CONFIG_COMMIT, CONFIG_BRANCH);
    
    NSString *tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
    const char *type;
    if (!access(tsPath.UTF8String, F_OK)) {
        type = "TrollStore";
    } else if (isJailbroken) {
        type = "Jailbroken";
    } else {
        type = "Unjailbroken";
    }
    setenv("POJAV_DETECTEDINST", type, 1);
    
    NSLog(@"[Pre-Init] Device: %@", [HostManager GetModelName]);
    NSLog(@"[Pre-Init] %@ (%s)", UIDevice.currentDevice.completeOSVersion, type);
    
    NSLog(@"[Pre-init] Entitlements availability:");
    printEntitlementAvailability(@"com.apple.developer.kernel.extended-virtual-addressing");
    printEntitlementAvailability(@"com.apple.developer.kernel.increased-memory-limit");
    printEntitlementAvailability(@"com.apple.private.security.no-sandbox");
    //printEntitlementAvailability(@"dynamic-codesigning");
}

void init_redirectStdio() {
    if (getenv("LOG_TO_CONSOLE") != NULL) {
        NSLog(@"[Pre-init] LOG_TO_CONSOLE is set, not logging to latestlog.txt");
        return;
    }

    NSLog(@"[Pre-init] Starting logging STDIO to latestlog.txt\n");

    NSString *home = @(getenv("POJAV_HOME"));
    NSString *currName = [home stringByAppendingPathComponent:@"latestlog.txt"];
    NSString *oldName = [home stringByAppendingPathComponent:@"latestlog.old.txt"];
    [fm removeItemAtPath:oldName error:nil];
    [fm moveItemAtPath:currName toPath:oldName error:nil];

    [fm createFileAtPath:currName contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:currName];

    if (!file) {
        NSLog(@"[Pre-init] Error: failed to open %@", currName);
        assert(0 && "Failed to open latestlog.txt. Check oslog for more details.");
    }

    setvbuf(stdout, 0, _IOLBF, 0); // make stdout line-buffered
    setvbuf(stderr, 0, _IONBF, 0); // make stderr unbuffered

    /* create the pipe and redirect stdout and stderr */
    static int pfd[2];
    pipe(pfd);
    dup2(pfd[1], fileno(stdout));
    dup2(pfd[1], fileno(stderr));

    /* create the logging thread */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        static BOOL filteredSessionID;
        ssize_t rsize;
        char buf[2048];
        while((rsize = read(pfd[0], buf, sizeof(buf)-1)) > 0) {
            if (rsize < 2048) {
                buf[rsize] = '\0';
            }
            // Filter out Session ID here
            int index;
            if (!filteredSessionID) {
                char *sessionStr = strstr(buf, "(Session ID is ");
                if (sessionStr) {
                    char *censorStr = "(Session ID is <censored>)\n\0";
                    strcpy(sessionStr, censorStr);
                    rsize = strlen(buf);
                    filteredSessionID = true;
                }
            }
            if (canAppendToLog) {
                [PLLogOutputView appendToLog:@(buf)];
            }
            [file writeData:[NSData dataWithBytes:buf length:rsize]];
            [file synchronizeFile];
        }
        [file closeFile];
    });

    // We can start catching exception right now
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
}

void init_setupAccounts() {
    NSString *controlPath = [@(getenv("POJAV_HOME")) stringByAppendingPathComponent:@"accounts"];
    [fm createDirectoryAtPath:controlPath withIntermediateDirectories:NO attributes:nil error:nil];
}

void init_setupCustomControls() {
    NSString *controlPath = [@(getenv("POJAV_HOME")) stringByAppendingPathComponent:@"controlmap"];
    [fm createDirectoryAtPath:controlPath withIntermediateDirectories:NO attributes:nil error:nil];
    generateAndSaveDefaultControl();
    NSString *gamepadControlPath = [controlPath stringByAppendingPathComponent:@"gamepads"];
    [fm createDirectoryAtPath:gamepadControlPath withIntermediateDirectories:NO attributes:nil error:nil];
    generateAndSaveDefaultControlForGamepad();
}

/*
 * Moves a launcher set up the old way over to the new layout, once.
 *
 * It used to be that every game directory kept its own copy of versions,
 * libraries and assets, while the profiles inside it shared one folder for
 * their worlds and mods. Now those downloads are shared by everything and each
 * profile has a folder to itself.
 *
 * Only moves: nothing is deleted, and anything already in the way is left be.
 */
void init_migrateToPerProfileLayout(NSString *root) {
    NSString *instanceName = getPrefObject(@"general.game_directory");
    if (instanceName.length == 0) {
        instanceName = @"default";
    }
    NSString *legacy = [[root stringByAppendingPathComponent:@"instances"]
        stringByAppendingPathComponent:instanceName];

    // The old layout is recognised by its versions folder sitting one level in
    if (![fm fileExistsAtPath:[legacy stringByAppendingPathComponent:@"versions"]]) {
        return;
    }
    NSLog(@"[Pre-init] Migrating %@ to the per-profile layout", legacy);

    // The downloads every profile shares move up to the launcher root
    for (NSString *name in @[@"versions", @"libraries", @"assets", @"resources",
                             @"launcher_profiles.json"]) {
        NSString *from = [legacy stringByAppendingPathComponent:name];
        NSString *to = [root stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:from] && ![fm fileExistsAtPath:to]) {
            [fm moveItemAtPath:from toPath:to error:nil];
        }
    }

    // Folders that modpacks were unpacked into become instances of their own
    NSString *customRoot = [legacy stringByAppendingPathComponent:@"custom_gamedir"];
    NSMutableDictionary<NSString *, NSString *> *renamed = [NSMutableDictionary new];
    for (NSString *name in [fm contentsOfDirectoryAtPath:customRoot error:nil]) {
        NSString *to = [[root stringByAppendingPathComponent:@"instances"]
            stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:to]) {
            continue;
        }
        if ([fm moveItemAtPath:[customRoot stringByAppendingPathComponent:name]
                toPath:to error:nil]) {
            renamed[name] = name;
        }
    }
    [fm removeItemAtPath:customRoot error:nil];

    // What is left in the old folder is what the shared profiles were using,
    // so it stays put and simply becomes one instance among the others
    NSMutableDictionary *profiles = parseJSONFromFile(
        [root stringByAppendingPathComponent:@"launcher_profiles.json"]);
    if (profiles[@"NSErrorObject"]) {
        return;
    }

    for (NSString *key in [profiles[@"profiles"] allKeys]) {
        NSMutableDictionary *profile = profiles[@"profiles"][key];
        NSString *dir = profile[@"gameDir"];

        if (dir.length == 0 || [dir isEqualToString:@"."] || [dir isEqualToString:@"./"]) {
            profile[@"gameDir"] = [@"./instances/" stringByAppendingString:instanceName];
        } else if ([dir hasPrefix:@"./custom_gamedir/"]) {
            NSString *name = dir.lastPathComponent;
            if (renamed[name]) {
                profile[@"gameDir"] = [@"./instances/" stringByAppendingString:name];
            }
        }
    }
    saveJSONToFile(profiles, [root stringByAppendingPathComponent:@"launcher_profiles.json"]);
}

/*
 * The launcher root holds what every profile shares - versions, libraries and
 * assets - while each profile keeps its worlds, mods and settings in a folder
 * of its own under instances/.
 */
void init_setupGameDirectory() {
    NSString *root = @(getenv("POJAV_HOME"));

    init_migrateToPerProfileLayout(root);

    for (NSString *name in @[@".demo", @"java_runtimes", @"instances", @"versions"]) {
        [fm createDirectoryAtPath:[root stringByAppendingPathComponent:name]
            withIntermediateDirectories:YES attributes:nil error:nil];
    }

    /*
     * Desktop Java believes it is on macOS and works out where Minecraft lives
     * from user.home. Installers - Forge's above all - offer that path as their
     * default and fail on it when it does not exist.
     *
     * The link goes in the container's own Library rather than under the
     * launcher folder: pointing at the launcher root from inside itself would
     * make a directory that contains itself, and it keeps the folder the person
     * browses free of it.
     */
    NSString *macPath = [@(getenv("HOME"))
        stringByAppendingPathComponent:@"Library/Application Support/minecraft"];
    [fm createDirectoryAtPath:macPath.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    [fm removeItemAtPath:macPath error:nil];
    [fm createSymbolicLinkAtPath:macPath withDestinationPath:root error:nil];

    [fm changeCurrentDirectoryPath:root];
    setenv("POJAV_GAME_DIR", root.UTF8String, 1);
}

void init_setupResolvConf() {
    // Write known DNS servers to the config
    NSString *path = [NSString stringWithFormat:@"%s/resolv.conf", getenv("POJAV_HOME")];
    if (![fm fileExistsAtPath:path]) {
        [@"nameserver 8.8.8.8\n"
         @"nameserver 8.8.4.4"
        writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

void init_setupHomeDirectory() {
    setenv("HOME", [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask]
        .lastObject.path.stringByDeletingLastPathComponent.UTF8String, 1);
    NSString *homeDir;
    NSError *homeError;
    
    BOOL isNotSandboxed = [@(getenv("HOME")).lastPathComponent isEqualToString:NSUserName()];
    homeDir = [NSString stringWithFormat:@"%s/Documents%@", getenv("HOME"),
        isNotSandboxed ? @"/AngelAuraAmethyst":@""];

    if (![fm fileExistsAtPath:homeDir] ) {
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:NO attributes:nil error:&homeError];
    }
    
    if(homeError != nil) {
        // TODO: Persistent storage
        homeError = nil;
        homeDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject;
        [fm createDirectoryAtPath:homeDir withIntermediateDirectories:YES attributes:nil error:&homeError];
    }
    
    setenv("POJAV_HOME", realpath(homeDir.UTF8String, NULL), 1);
}

int main(int argc, char *argv[]) {
    if (pJLI_Launch) {
        return pJLI_Launch(argc, (const char **)argv,
                   0, NULL, // sizeof(const_jargs) / sizeof(char *), const_jargs,
                   0, NULL, // sizeof(const_appclasspath) / sizeof(char *), const_appclasspath,
                   "1.8.0-internal",
                   "1.8",

                   "java", "openjdk",
                   /* (const_jargs != NULL) ? JNI_TRUE : */ JNI_FALSE,
                   JNI_TRUE, JNI_FALSE, JNI_TRUE);
    }

    if (!isJITEnabled(true) && argc == 2) {
        NSLog(@"calling ptrace(PT_TRACE_ME)");
        // Child process can call to PT_TRACE_ME
        // then both parent and child processes get CS_DEBUGGED
        int ret = ptrace(PT_TRACE_ME, 0, 0, 0);
        return ret;
    }

    setenv("BUNDLE_PATH", dirname(argv[0]), 1);
    isJailbroken = init_checkForJailbreak();
    init_setupHomeDirectory();
    init_redirectStdio();
    init_logDeviceAndVer(argv[0]);

    loadPreferences(NO);
    init_hookFunctions();
    init_hookUIKitConstructor();

    debugLogEnabled = getPrefBool(@"general.debug_logging");
    NSLog(@"[Debugging] Debug log enabled: %@", debugLogEnabled ? @"YES" : @"NO");

    init_setupResolvConf();
    init_setupGameDirectory();
    toggleIsolatedPref(NO);
    [PLProfiles updateCurrent];
    init_setupAccounts();
    init_setupCustomControls();

    // If sandbox is disabled, W^X JIT can be enabled by Amethyst itself
    if (!isJITEnabled(true) && getEntitlementValue(@"com.apple.private.security.no-sandbox")) {
        NSLog(@"[Pre-init] no-sandbox: YES, trying to enable JIT");
        int pid;
        int ret = posix_spawnp(&pid, argv[0], NULL, NULL, (char *[]){argv[0], "", NULL}, environ);
        if (ret == 0) {
            // Cleanup child process
            waitpid(pid, NULL, WUNTRACED);
            ptrace(PT_DETACH, pid, NULL, 0);
            kill(pid, SIGTERM);
            wait(NULL);

            if (isJITEnabled(true)) {
                NSLog(@"[Pre-init] JIT has been enabled with PT_TRACE_ME");
            } else {
                NSLog(@"[Pre-init] Failed to enable JIT: unknown reason");
            }
        } else {
            NSLog(@"[Pre-init] Failed to enable JIT: posix_spawn() failed errno %d", errno);
        }
    }

    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
