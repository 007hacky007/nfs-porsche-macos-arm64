#import <Cocoa/Cocoa.h>
#import "../launcher/settings.h"
#import "../launcher/game.h"
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];
    NSString *domain=[@"org.nfsv.launcher-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:domain];
    NSDictionary *env=launcher_environment(defaults,@{@"KEEP":@"yes",@"NFSV_RESOLUTION":@"bad",@"NFSV_FPS_LIMIT":@"999",@"NFSV_HUD_SCALE":@"bad"});
    CHECK([env[@"NFSV_HUD_SCALE"] isEqual:@"100"]&&[env[@"NFSV_PAD_SENSITIVITY"] isEqual:@"100"]);
    CHECK([env[@"KEEP"] isEqual:@"yes"]&&[env[@"NFSV_FULLSCREEN"] isEqual:@"1"]&&[env[@"NFSV_HIDE_CURSOR"] isEqual:@"1"]);
    CHECK(!env[@"NFSV_RESOLUTION"]&&!env[@"NFSV_FPS_LIMIT"]);
    CHECK([env[@"NFSV_ENHANCED_GRAPHICS"] isEqual:@"1"]&&[env[@"NFSV_PAD_RUMBLE"] isEqual:@"1"]);
    NFSVLaunchSettingsView *view=[[NFSVLaunchSettingsView alloc] initWithDefaults:defaults];
    CHECK(![defaults objectForKey:@"LaunchResolution"]); // Opening or cancelling does not save edits.
    [view.resolution selectItemAtIndex:6];[view.frameLimit selectItemAtIndex:2];
    CHECK(view.hudScale.doubleValue==100&&view.hudScale.minValue==25&&view.hudScale.maxValue==100);
    view.hudScale.doubleValue=75;
    CHECK(view.stickSensitivity.doubleValue==100&&view.stickSensitivity.minValue==25&&view.stickSensitivity.maxValue==200);
    view.stickSensitivity.doubleValue=60;
    CHECK(view.enhancedGraphics.state==NSControlStateValueOn&&view.vibration.state==NSControlStateValueOn);
    view.vibration.state=NSControlStateValueOff;
    view.fullscreen.state=NSControlStateValueOff;view.hideCursor.state=NSControlStateValueOn;view.enhancedGraphics.state=NSControlStateValueOff;
    [view saveToDefaults:defaults];
    env=launcher_environment(defaults,@{});
    CHECK([env[@"NFSV_RESOLUTION"] isEqual:@"1920x1080"]&&[env[@"NFSV_FPS_LIMIT"] isEqual:@"60"]);
    CHECK([env[@"NFSV_FULLSCREEN"] isEqual:@"0"]&&[env[@"NFSV_HIDE_CURSOR"] isEqual:@"1"]);
    CHECK([env[@"NFSV_HUD_SCALE"] isEqual:@"75"]&&[env[@"NFSV_ENHANCED_GRAPHICS"] isEqual:@"0"]&&[env[@"NFSV_PAD_RUMBLE"] isEqual:@"0"]&&[env[@"NFSV_PAD_SENSITIVITY"] isEqual:@"60"]);
    view=[[NFSVLaunchSettingsView alloc] initWithDefaults:defaults];
    CHECK([view.resolution.selectedItem.representedObject isEqual:@"1920x1080"]);
    CHECK([view.frameLimit.selectedItem.representedObject isEqual:@60]&&view.fullscreen.state==NSControlStateValueOff);
    CHECK(view.hudScale.doubleValue==75&&view.enhancedGraphics.state==NSControlStateValueOff&&view.vibration.state==NSControlStateValueOff&&view.stickSensitivity.doubleValue==60);
    for(id invalid in @[@24,@101,@"75",@(NAN),@(INFINITY)]){
        [defaults setObject:invalid forKey:@"LaunchHUDScale"];
        CHECK([launcher_environment(defaults,@{})[@"NFSV_HUD_SCALE"] isEqual:@"100"]);
    }
    for(id invalid in @[@24,@201,@"75",@(NAN),@(INFINITY)]){
        [defaults setObject:invalid forKey:@"LaunchStickSensitivity"];
        CHECK([launcher_environment(defaults,@{})[@"NFSV_PAD_SENSITIVITY"] isEqual:@"100"]);
    }
    [defaults setObject:@"9999x9999" forKey:@"LaunchResolution"];
    [defaults setObject:@(-12) forKey:@"LaunchFrameLimit"];
    [defaults setObject:@"invalid" forKey:@"LaunchHideCursor"];
    [defaults setObject:@"invalid" forKey:@"LaunchEnhancedGraphics"];
    [defaults setObject:@"invalid" forKey:@"LaunchControllerVibration"];
    env=launcher_environment(defaults,@{});
    CHECK(!env[@"NFSV_RESOLUTION"]&&!env[@"NFSV_FPS_LIMIT"]&&[env[@"NFSV_HIDE_CURSOR"] isEqual:@"1"]);
    CHECK([env[@"NFSV_ENHANCED_GRAPHICS"] isEqual:@"1"]&&[env[@"NFSV_PAD_RUMBLE"] isEqual:@"1"]);
    [defaults setObject:@"/somewhere/else" forKey:@"GameFolder"];
    launcher_forget_game_folder(defaults);
    CHECK(![defaults objectForKey:@"GameFolder"]);
    launcher_forget_game_folder(defaults);
    [defaults removePersistentDomainForName:domain];

    // The app plays only the game files inside its own Resources/Game.
    NSFileManager *files=NSFileManager.defaultManager;
    NSURL *resources=[files.temporaryDirectory URLByAppendingPathComponent:[@"nfsv-launcher-test-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    CHECK([files createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:nil]);
    NSString *sha=@"f16d05ec6b29248d2c61adb1e9263f78e4f7bace1b955014a2d17872cfe4064d"; // SHA-256 of "fixture"
    NSString *problem=nil;
    CHECK(!launcher_bundled_game(nil,7,sha,&problem)&&[problem containsString:@"Build NFSV.app again with NFSV Builder"]);
    problem=nil;CHECK(!launcher_bundled_game(resources,7,sha,&problem)&&[problem containsString:@"game files are missing."]);
    NSURL *game=[resources URLByAppendingPathComponent:@"Game" isDirectory:YES];
    for(NSString *name in @[@"GameData",@"FEData"])
        CHECK([files createDirectoryAtURL:[game URLByAppendingPathComponent:name] withIntermediateDirectories:YES attributes:nil error:nil]);
    problem=nil;CHECK(!launcher_bundled_game(resources,7,sha,&problem)&&[problem containsString:@"missing fe.txt"]);
    for(NSString *name in @[@"fe.txt",@"install.txt"])
        CHECK([@"" writeToURL:[game URLByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil]);
    problem=nil;CHECK(!launcher_bundled_game(resources,7,sha,&problem)&&[problem containsString:@"missing Porsche.exe"]);
    CHECK([@"fixture" writeToURL:[game URLByAppendingPathComponent:@"Porsche.exe"] atomically:NO encoding:NSUTF8StringEncoding error:nil]);
    problem=nil;CHECK(!launcher_bundled_game(resources,8,sha,&problem)&&[problem containsString:@"does not match"]);
    problem=nil;CHECK(!launcher_bundled_game(resources,7,[sha uppercaseString],&problem)&&[problem containsString:@"does not match"]);
    problem=@"stale";NSURL *found=launcher_bundled_game(resources,7,sha,&problem);
    CHECK(found&&!problem&&[found.path isEqualToString:game.path]);
    CHECK([files removeItemAtURL:resources error:nil]);
    puts("Launcher: defaults, saved choices, inherited environment, invalid preferences, the bundled game check and the dropped game folder passed without displaying a window");
}}
