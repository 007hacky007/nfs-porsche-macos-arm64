#import <Cocoa/Cocoa.h>
#include "image.h"
#import "game.h"
#import "settings.h"

static void alert(NSString *message){
    NSAlert *a=[NSAlert new];a.messageText=@"NFSV";a.informativeText=message;[a addButtonWithTitle:@"OK"];[a runModal];
}
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSUserDefaults *settings=NSUserDefaults.standardUserDefaults;
    launcher_forget_game_folder(settings);
    NSString *problem=nil;
    NSURL *folder=launcher_bundled_game(NSBundle.mainBundle.resourceURL,IMAGE_FILE_SIZE,@IMAGE_SHA256,&problem);
    if(!folder){[NSApp activateIgnoringOtherApps:YES];alert(problem);return 1;}
    if(!launcher_choose_settings(settings,NSBundle.mainBundle.infoDictionary[@"NFSBuilderVersion"]))return 0;
    NSError *error=nil;NSFileManager *files=NSFileManager.defaultManager;
    NSURL *support=[[files URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"NFSV" isDirectory:YES];
    NSURL *output=[support URLByAppendingPathComponent:@"out" isDirectory:YES];
    if(![files createDirectoryAtURL:output withIntermediateDirectories:YES attributes:nil error:&error]){alert(error.localizedDescription);return 1;}
    NSURL *log=[support URLByAppendingPathComponent:@"NFSV.log"];
    if(![files createFileAtPath:log.path contents:nil attributes:nil]){alert(@"Cannot create the game log.");return 1;}
    NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:log.path];
    NSTask *task=[NSTask new];task.executableURL=[NSBundle.mainBundle.executableURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"NFSVEngine"];
    task.arguments=@[[folder URLByAppendingPathComponent:@"Porsche.exe"].path];task.currentDirectoryURL=support;
    NSMutableDictionary *environment=[launcher_environment(settings,NSProcessInfo.processInfo.environment) mutableCopy];
    [environment removeObjectForKey:@"NFSV_CAPTURE"];
    environment[@"NFSV_SAVE_DIR"]=support.path;environment[@"NFSV_TIMEOUT"]=@"0";task.environment=environment;
    task.standardOutput=handle;task.standardError=handle;
    if(![task launchAndReturnError:&error]){[handle closeFile];alert(error.localizedDescription);return 1;}
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];[task waitUntilExit];[handle closeFile];
    if(task.terminationStatus){
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];[NSApp activateIgnoringOtherApps:YES];
        alert([NSString stringWithFormat:@"The game stopped. Its log is saved at %@.",log.path]);
    }
    return task.terminationStatus;
}}
