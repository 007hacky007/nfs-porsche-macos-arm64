#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>
#include "image.h"

static NSString *validate(NSURL *folder){
    NSFileManager *files=NSFileManager.defaultManager;
    for(NSString *name in @[@"GameData",@"FEData",@"fe.txt",@"install.txt"]){
        if(![files fileExistsAtPath:[folder URLByAppendingPathComponent:name].path])return [NSString stringWithFormat:@"The selected folder is missing %@.",name];
    }
    NSData *exe=[NSData dataWithContentsOfURL:[folder URLByAppendingPathComponent:@"Porsche.exe"] options:NSDataReadingMappedIfSafe error:nil];
    if(!exe)return @"The selected folder is missing Porsche.exe.";
    if(exe.length!=IMAGE_FILE_SIZE)return @"This build requires the original v3.5 USA executable.";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(exe.bytes,(CC_LONG)exe.length,digest);
    NSMutableString *hex=[NSMutableString new];for(unsigned i=0;i<sizeof digest;i++)[hex appendFormat:@"%02x",digest[i]];
    if(![hex isEqualToString:@IMAGE_SHA256])return @"This build requires the original v3.5 USA executable.";
    return nil;
}
static void alert(NSString *message){
    NSAlert *a=[NSAlert new];a.messageText=@"NFSV";a.informativeText=message;[a addButtonWithTitle:@"OK"];[a runModal];
}
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSUserDefaults *settings=NSUserDefaults.standardUserDefaults;
    NSString *saved=[settings stringForKey:@"GameFolder"];NSURL *folder=saved?[NSURL fileURLWithPath:saved isDirectory:YES]:nil;
    if(!folder||validate(folder)){
        for(;;){
            NSOpenPanel *panel=NSOpenPanel.openPanel;panel.title=@"NFSV";panel.message=@"Choose your extracted NFSV game folder.";
            panel.canChooseFiles=NO;panel.canChooseDirectories=YES;panel.allowsMultipleSelection=NO;panel.prompt=@"Play";
            [NSApp activateIgnoringOtherApps:YES];if([panel runModal]!=NSModalResponseOK)return 0;
            folder=panel.URL;NSString *problem=validate(folder);if(!problem)break;alert(problem);
        }
        [settings setObject:folder.path forKey:@"GameFolder"];
    }
    NSError *error=nil;NSFileManager *files=NSFileManager.defaultManager;
    NSURL *support=[[files URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"NFSV" isDirectory:YES];
    NSURL *output=[support URLByAppendingPathComponent:@"out" isDirectory:YES];
    if(![files createDirectoryAtURL:output withIntermediateDirectories:YES attributes:nil error:&error]){alert(error.localizedDescription);return 1;}
    NSURL *log=[support URLByAppendingPathComponent:@"NFSV.log"];
    if(![files createFileAtPath:log.path contents:nil attributes:nil]){alert(@"Cannot create the game log.");return 1;}
    NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:log.path];
    NSTask *task=[NSTask new];task.executableURL=[NSBundle.mainBundle.executableURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"NFSVEngine"];
    task.arguments=@[[folder URLByAppendingPathComponent:@"Porsche.exe"].path];task.currentDirectoryURL=support;
    NSMutableDictionary *environment=[NSProcessInfo.processInfo.environment mutableCopy];
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
