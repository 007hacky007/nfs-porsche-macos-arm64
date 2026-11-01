#import <Cocoa/Cocoa.h>
#import "../launcher/settings.h"
#import "../launcher/game.h"
#import "../launcher/update.h"
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
static NSData *release_json(NSString *tag,BOOL withImage){
    NSString *base=@"https://github.com/007hacky007/nfs-porsche-macos-arm64/releases/";
    NSMutableDictionary *release=[@{@"tag_name":tag,@"html_url":[base stringByAppendingFormat:@"tag/%@",tag],@"draft":@NO,@"prerelease":@NO} mutableCopy];
    release[@"assets"]=withImage?@[@{@"name":@"NFSV-Builder.dmg.sha256",@"browser_download_url":[base stringByAppendingFormat:@"download/%@/NFSV-Builder.dmg.sha256",tag]},
                                    @{@"name":@"NFSV-Builder.dmg",@"browser_download_url":[base stringByAppendingFormat:@"download/%@/NFSV-Builder.dmg",tag]}]:@[];
    return [NSJSONSerialization dataWithJSONObject:release options:0 error:nil];
}
static NSRect in_window(NSView *view){return [view convertRect:view.bounds toView:nil];}
static void check_layout(NSAlert *dialog){
    NSRect accessory=in_window(dialog.accessoryView),content=dialog.window.contentView.bounds;
    CHECK(NSContainsRect(content,accessory));
    for(NSButton *button in dialog.buttons)CHECK(!NSIntersectsRect(in_window(button),accessory)&&NSContainsRect(content,in_window(button)));
}
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
    problem=@"stale";NSURL *bundled=launcher_bundled_game(resources,7,sha,&problem);
    CHECK(bundled&&!problem&&[bundled.path isEqualToString:game.path]);
    CHECK([files removeItemAtURL:resources error:nil]);

    // Update check: version order, a day between requests, nothing sent when off or unstamped.
    CHECK(launcher_compare_versions(@"1.2.10",@"1.2.9")==NSOrderedDescending&&launcher_compare_versions(@"1.2",@"1.2.0")==NSOrderedSame);
    CHECK(launcher_compare_versions(@"1.9.9",@"2.0.0")==NSOrderedAscending&&launcher_compare_versions(@"0.0.0-dev",@"1.0.0")==NSOrderedAscending);
    defaults=[[NSUserDefaults alloc] initWithSuiteName:domain];
    __block NSUInteger requests=0;__block NSData *reply=nil;__block NSURLRequest *sent=nil;
    NFSVFetcher fake=^(NSURLRequest *request,NFSVFetchCompletion done){requests++;sent=request;done(reply);};
    __block NSDictionary *found=nil;void (^remember)(NSDictionary *)=^(NSDictionary *release){found=release;};
    NSDate *start=[NSDate dateWithTimeIntervalSince1970:2000000000];
    CHECK(!launcher_check_for_update(defaults,nil,start,fake,remember)&&!launcher_check_for_update(defaults,@"",start,fake,remember)&&requests==0);
    [defaults setBool:NO forKey:@"LaunchCheckUpdates"];
    CHECK(!launcher_check_for_update(defaults,@"1.2.0",start,fake,remember)&&requests==0);
    [defaults removeObjectForKey:@"LaunchCheckUpdates"];CHECK(launcher_update_checks_enabled(defaults));
    reply=release_json(@"v1.3.0",YES);
    CHECK(launcher_check_for_update(defaults,@"1.2.0",start,fake,remember)&&requests==1);
    CHECK([sent.URL.absoluteString isEqual:@"https://api.github.com/repos/007hacky007/nfs-porsche-macos-arm64/releases/latest"]);
    CHECK([[sent valueForHTTPHeaderField:@"User-Agent"] isEqual:@"NFSV-Launcher"]&&sent.timeoutInterval==5&&!sent.HTTPBody);
    CHECK([found[@"version"] isEqual:@"1.3.0"]&&[found[@"download"] hasSuffix:@"/download/v1.3.0/NFSV-Builder.dmg"]&&[found[@"page"] hasSuffix:@"/tag/v1.3.0"]);
    CHECK(!launcher_check_for_update(defaults,@"1.2.0",[start dateByAddingTimeInterval:23*3600],fake,remember)&&requests==1);
    CHECK([launcher_pending_update(defaults,@"1.2.0") isEqual:found]&&!launcher_pending_update(defaults,@"1.3.0")&&!launcher_pending_update(defaults,nil));
    launcher_dismiss_update(defaults,@"1.3.0");CHECK(!launcher_pending_update(defaults,@"1.2.0"));
    found=nil;CHECK(launcher_check_for_update(defaults,@"1.2.0",[start dateByAddingTimeInterval:24*3600],fake,remember)&&requests==2&&!found);
    reply=release_json(@"v1.4.0",NO);
    CHECK(launcher_check_for_update(defaults,@"1.2.0",[start dateByAddingTimeInterval:-60],fake,remember)&&requests==3);  // clock set back
    CHECK([found[@"version"] isEqual:@"1.4.0"]&&[found[@"download"] isEqual:found[@"page"]]);
    for(NSData *bad in @[[NSData data],[@"{\"tag_name\":\"v9.0.0\",\"html_url\":\"https://example.com/x\"}" dataUsingEncoding:NSUTF8StringEncoding],
                         [@"{\"tag_name\":\"nightly\",\"html_url\":\"https://github.com/007hacky007/nfs-porsche-macos-arm64/releases/tag/nightly\"}" dataUsingEncoding:NSUTF8StringEncoding]])
        CHECK(!launcher_parse_release(bad));
    CHECK(!launcher_parse_release(nil));
    [defaults removePersistentDomainForName:domain];

    // The notice in the launcher window: shown when a newer release arrives, gone after Not now.
    defaults=[[NSUserDefaults alloc] initWithSuiteName:domain];
    __block NFSVFetchCompletion pendingReply=nil;requests=0;
    NFSVFetcher later=^(NSURLRequest *request,NFSVFetchCompletion done){(void)request;requests++;pendingReply=done;};
    NSAlert *dialog=launcher_settings_dialog(defaults,@"1.2.0",later);
    NFSVLaunchSettingsView *settingsView=(NFSVLaunchSettingsView *)dialog.accessoryView;
    CHECK(requests==1&&settingsView.checkUpdates.enabled&&settingsView.checkUpdates.state==NSControlStateValueOn);
    [dialog layout];check_layout(dialog);
    CGFloat height=dialog.window.frame.size.height;
    CHECK(!settingsView.updateNotice.superview);
    pendingReply(release_json(@"v1.3.0",YES));
    CHECK(settingsView.updateNotice.superview&&dialog.window.frame.size.height>=height+60);check_layout(dialog);
    NSMutableArray *opened=[NSMutableArray new];settingsView.openURL=^(NSURL *url){[opened addObject:url.absoluteString];};
    NSArray *noticeButtons=[settingsView.updateNotice.subviews filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self isKindOfClass: %@",NSButton.class]];
    CHECK(noticeButtons.count==3);
    for(NSButton *button in noticeButtons)if(![button.title isEqual:@"Not now"])[button performClick:nil];
    CHECK(opened.count==2&&[opened[0] hasSuffix:@"/tag/v1.3.0"]&&[opened[1] hasSuffix:@"/NFSV-Builder.dmg"]);
    [noticeButtons.lastObject performClick:nil];
    CHECK(!settingsView.updateNotice.superview&&fabs(dialog.window.frame.size.height-height)<1);check_layout(dialog);
    CHECK([[defaults stringForKey:@"UpdateDismissedVersion"] isEqual:@"1.3.0"]);
    settingsView.checkUpdates.state=NSControlStateValueOff;[settingsView saveToDefaults:defaults];
    CHECK(!launcher_update_checks_enabled(defaults));
    dialog=launcher_settings_dialog(defaults,@"1.2.0",later);   // off: no request and no remembered notice
    CHECK(requests==1&&((NFSVLaunchSettingsView *)dialog.accessoryView).checkUpdates.state==NSControlStateValueOff);
    [defaults removePersistentDomainForName:domain];
    defaults=[[NSUserDefaults alloc] initWithSuiteName:domain];
    [defaults setObject:@"1.3.0" forKey:@"UpdateLatestVersion"];
    [defaults setObject:@"https://github.com/007hacky007/nfs-porsche-macos-arm64/releases/tag/v1.3.0" forKey:@"UpdateLatestPage"];
    [defaults setObject:@"https://github.com/007hacky007/nfs-porsche-macos-arm64/releases/download/v1.3.0/NFSV-Builder.dmg" forKey:@"UpdateLatestDownload"];
    [defaults setObject:NSDate.date forKey:@"UpdateLastCheck"];
    dialog=launcher_settings_dialog(defaults,@"1.2.0",later);   // remembered from an earlier check, no new request
    CHECK(requests==1&&((NFSVLaunchSettingsView *)dialog.accessoryView).updateNotice.superview);
    [dialog layout];check_layout(dialog);
    dialog=launcher_settings_dialog(defaults,nil,later);   // a Terminal build has no stamp
    settingsView=(NFSVLaunchSettingsView *)dialog.accessoryView;
    CHECK(requests==1&&!settingsView.checkUpdates.enabled&&!settingsView.updateNotice.superview);
    [settingsView saveToDefaults:defaults];CHECK(![defaults objectForKey:@"LaunchCheckUpdates"]);
    [defaults removePersistentDomainForName:domain];
    puts("Launcher: defaults, saved choices, inherited environment, invalid preferences, the bundled game check, the dropped game folder, the update check and its notice passed without displaying a window");
}}
