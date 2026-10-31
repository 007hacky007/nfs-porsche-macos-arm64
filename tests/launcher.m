#import <Cocoa/Cocoa.h>
#import "../launcher/settings.h"
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];
    NSString *domain=[@"org.nfsv.launcher-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:domain];
    NSDictionary *env=launcher_environment(defaults,@{@"KEEP":@"yes",@"NFSV_RESOLUTION":@"bad",@"NFSV_FPS_LIMIT":@"999",@"NFSV_HUD_SCALE":@"bad"});
    CHECK([env[@"NFSV_HUD_SCALE"] isEqual:@"100"]);
    CHECK([env[@"KEEP"] isEqual:@"yes"]&&[env[@"NFSV_FULLSCREEN"] isEqual:@"1"]&&[env[@"NFSV_HIDE_CURSOR"] isEqual:@"1"]);
    CHECK(!env[@"NFSV_RESOLUTION"]&&!env[@"NFSV_FPS_LIMIT"]);
    CHECK([env[@"NFSV_ENHANCED_GRAPHICS"] isEqual:@"1"]&&[env[@"NFSV_PAD_RUMBLE"] isEqual:@"1"]);
    NFSVLaunchSettingsView *view=[[NFSVLaunchSettingsView alloc] initWithDefaults:defaults];
    CHECK(![defaults objectForKey:@"LaunchResolution"]); // Opening or cancelling does not save edits.
    [view.resolution selectItemAtIndex:6];[view.frameLimit selectItemAtIndex:2];
    CHECK(view.hudScale.doubleValue==100&&view.hudScale.minValue==25&&view.hudScale.maxValue==100);
    view.hudScale.doubleValue=75;
    CHECK(view.enhancedGraphics.state==NSControlStateValueOn&&view.vibration.state==NSControlStateValueOn);
    view.vibration.state=NSControlStateValueOff;
    view.fullscreen.state=NSControlStateValueOff;view.hideCursor.state=NSControlStateValueOn;view.enhancedGraphics.state=NSControlStateValueOff;
    [view saveToDefaults:defaults];
    env=launcher_environment(defaults,@{});
    CHECK([env[@"NFSV_RESOLUTION"] isEqual:@"1920x1080"]&&[env[@"NFSV_FPS_LIMIT"] isEqual:@"60"]);
    CHECK([env[@"NFSV_FULLSCREEN"] isEqual:@"0"]&&[env[@"NFSV_HIDE_CURSOR"] isEqual:@"1"]);
    CHECK([env[@"NFSV_HUD_SCALE"] isEqual:@"75"]&&[env[@"NFSV_ENHANCED_GRAPHICS"] isEqual:@"0"]&&[env[@"NFSV_PAD_RUMBLE"] isEqual:@"0"]);
    view=[[NFSVLaunchSettingsView alloc] initWithDefaults:defaults];
    CHECK([view.resolution.selectedItem.representedObject isEqual:@"1920x1080"]);
    CHECK([view.frameLimit.selectedItem.representedObject isEqual:@60]&&view.fullscreen.state==NSControlStateValueOff);
    CHECK(view.hudScale.doubleValue==75&&view.enhancedGraphics.state==NSControlStateValueOff&&view.vibration.state==NSControlStateValueOff);
    for(id invalid in @[@24,@101,@"75",@(NAN),@(INFINITY)]){
        [defaults setObject:invalid forKey:@"LaunchHUDScale"];
        CHECK([launcher_environment(defaults,@{})[@"NFSV_HUD_SCALE"] isEqual:@"100"]);
    }
    [defaults setObject:@"9999x9999" forKey:@"LaunchResolution"];
    [defaults setObject:@(-12) forKey:@"LaunchFrameLimit"];
    [defaults setObject:@"invalid" forKey:@"LaunchHideCursor"];
    [defaults setObject:@"invalid" forKey:@"LaunchEnhancedGraphics"];
    [defaults setObject:@"invalid" forKey:@"LaunchControllerVibration"];
    env=launcher_environment(defaults,@{});
    CHECK(!env[@"NFSV_RESOLUTION"]&&!env[@"NFSV_FPS_LIMIT"]&&[env[@"NFSV_HIDE_CURSOR"] isEqual:@"1"]);
    CHECK([env[@"NFSV_ENHANCED_GRAPHICS"] isEqual:@"1"]&&[env[@"NFSV_PAD_RUMBLE"] isEqual:@"1"]);
    [defaults removePersistentDomainForName:domain];
    puts("Launcher: defaults, saved choices, inherited environment and invalid preferences passed without displaying a window");
}}
