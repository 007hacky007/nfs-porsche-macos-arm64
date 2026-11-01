#import "settings.h"
#import "update.h"
#include "../runtime/display.h"
#include <math.h>

static BOOL boolean_setting(NSUserDefaults *defaults,NSString *key,BOOL fallback){
    id value=[defaults objectForKey:key];return [value isKindOfClass:NSNumber.class]?[value boolValue]:fallback;
}
static NSInteger hud_scale_setting(NSUserDefaults *defaults){
    id value=[defaults objectForKey:@"LaunchHUDScale"];
    double percent=[value isKindOfClass:NSNumber.class]?[value doubleValue]:100;
    return isfinite(percent)&&percent>=25&&percent<=100?lround(percent):100;
}
static NSInteger stick_sensitivity_setting(NSUserDefaults *defaults){
    id value=[defaults objectForKey:@"LaunchStickSensitivity"];
    double percent=[value isKindOfClass:NSNumber.class]?[value doubleValue]:100;
    return isfinite(percent)&&percent>=25&&percent<=200?lround(percent):100;
}
NSDictionary *launcher_environment(NSUserDefaults *defaults,NSDictionary *inherited){
    NSMutableDictionary *environment=[inherited mutableCopy];
    [environment removeObjectsForKeys:@[@"NFSV_RESOLUTION",@"NFSV_FPS_LIMIT"]];
    id resolution=[defaults objectForKey:@"LaunchResolution"];
    if([resolution isKindOfClass:NSString.class]&&display_resolution([resolution UTF8String],NULL,NULL))
        environment[@"NFSV_RESOLUTION"]=resolution;
    id limit=[defaults objectForKey:@"LaunchFrameLimit"];
    if([limit isKindOfClass:NSNumber.class]&&[@[@30,@60,@120] containsObject:limit])environment[@"NFSV_FPS_LIMIT"]=[limit stringValue];
    environment[@"NFSV_FULLSCREEN"]=boolean_setting(defaults,@"LaunchFullscreen",YES)?@"1":@"0";
    environment[@"NFSV_HIDE_CURSOR"]=boolean_setting(defaults,@"LaunchHideCursor",YES)?@"1":@"0";
    environment[@"NFSV_ENHANCED_GRAPHICS"]=boolean_setting(defaults,@"LaunchEnhancedGraphics",YES)?@"1":@"0";
    environment[@"NFSV_PAD_RUMBLE"]=boolean_setting(defaults,@"LaunchControllerVibration",YES)?@"1":@"0";
    environment[@"NFSV_HUD_SCALE"]=[@(hud_scale_setting(defaults)) stringValue];
    environment[@"NFSV_PAD_SENSITIVITY"]=[@(stick_sensitivity_setting(defaults)) stringValue];
    return environment;
}

@implementation NFSVLaunchSettingsView{
    NSTextField *hudSizeValue,*stickSensitivityValue,*updateText;
    NSDictionary *shownUpdate;
}
- (void)updateStickSensitivity:(id)sender{
    (void)sender;self.stickSensitivity.integerValue=lround(self.stickSensitivity.doubleValue/5)*5;
    stickSensitivityValue.stringValue=[NSString stringWithFormat:@"%ld%%",(long)self.stickSensitivity.integerValue];
    self.stickSensitivity.accessibilityValueDescription=stickSensitivityValue.stringValue;
}
- (void)updateHUDSize:(id)sender{
    (void)sender;self.hudScale.integerValue=lround(self.hudScale.doubleValue);
    hudSizeValue.stringValue=[NSString stringWithFormat:@"%ld%%",(long)self.hudScale.integerValue];
    self.hudScale.accessibilityValueDescription=hudSizeValue.stringValue;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults{
    if((self=[super initWithFrame:NSMakeRect(0,0,390,350)])){
        NSDictionary *settings=launcher_environment(defaults,@{});
        NSTextField *label=[NSTextField labelWithString:@"Race resolution:"];label.frame=NSMakeRect(0,317,140,22);[self addSubview:label];
        self.resolution=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(145,314,245,28) pullsDown:NO];
        self.resolution.accessibilityLabel=@"Race resolution";
        [self.resolution addItemWithTitle:@"Use in-game setting"];self.resolution.lastItem.representedObject=@"";
        for(unsigned i=0;i<DISPLAY_MODE_COUNT;i++){
            NSString *value=[NSString stringWithFormat:@"%ux%u",display_mode_sizes[i][0],display_mode_sizes[i][1]];
            [self.resolution addItemWithTitle:[NSString stringWithFormat:@"%u x %u",display_mode_sizes[i][0],display_mode_sizes[i][1]]];
            self.resolution.lastItem.representedObject=value;
            if([settings[@"NFSV_RESOLUTION"] isEqual:value])[self.resolution selectItem:self.resolution.lastItem];
        }
        [self addSubview:self.resolution];
        label=[NSTextField labelWithString:@"Frame-rate limit:"];label.frame=NSMakeRect(0,281,140,22);[self addSubview:label];
        self.frameLimit=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(145,278,245,28) pullsDown:NO];
        self.frameLimit.accessibilityLabel=@"Frame-rate limit";
        for(NSNumber *limit in @[@0,@30,@60,@120]){
            [self.frameLimit addItemWithTitle:limit.intValue?[NSString stringWithFormat:@"%@ FPS",limit]:@"Game default"];
            self.frameLimit.lastItem.representedObject=limit;
            if([settings[@"NFSV_FPS_LIMIT"] intValue]==limit.intValue)[self.frameLimit selectItem:self.frameLimit.lastItem];
        }
        [self addSubview:self.frameLimit];
        label=[NSTextField labelWithString:@"HUD size:"];label.frame=NSMakeRect(0,245,140,22);[self addSubview:label];
        self.hudScale=[NSSlider sliderWithValue:[settings[@"NFSV_HUD_SCALE"] doubleValue] minValue:25 maxValue:100 target:self action:@selector(updateHUDSize:)];
        self.hudScale.frame=NSMakeRect(145,243,185,24);self.hudScale.continuous=YES;
        self.hudScale.accessibilityLabel=@"HUD size";
        self.hudScale.toolTip=@"Percentage of the resolution-scaled HUD size. Never smaller than the original HUD.";
        [self addSubview:self.hudScale];
        hudSizeValue=[NSTextField labelWithString:@""];hudSizeValue.frame=NSMakeRect(335,245,55,22);
        hudSizeValue.alignment=NSTextAlignmentRight;[self addSubview:hudSizeValue];[self updateHUDSize:nil];
        label=[NSTextField labelWithString:@"Stick sensitivity:"];label.frame=NSMakeRect(0,209,140,22);[self addSubview:label];
        self.stickSensitivity=[NSSlider sliderWithValue:[settings[@"NFSV_PAD_SENSITIVITY"] doubleValue] minValue:25 maxValue:200 target:self action:@selector(updateStickSensitivity:)];
        self.stickSensitivity.frame=NSMakeRect(145,207,185,24);self.stickSensitivity.continuous=YES;
        self.stickSensitivity.accessibilityLabel=@"Stick sensitivity";
        self.stickSensitivity.toolTip=@"Game controller sticks. 100% is linear. Lower values steer more gently around the centre and still reach full lock at full stick; higher values reach full lock before the edge.";
        [self addSubview:self.stickSensitivity];
        stickSensitivityValue=[NSTextField labelWithString:@""];stickSensitivityValue.frame=NSMakeRect(335,209,55,22);
        stickSensitivityValue.alignment=NSTextAlignmentRight;[self addSubview:stickSensitivityValue];[self updateStickSensitivity:nil];
        self.fullscreen=[NSButton checkboxWithTitle:@"Start in fullscreen" target:nil action:nil];self.fullscreen.frame=NSMakeRect(0,171,390,24);
        self.fullscreen.state=[settings[@"NFSV_FULLSCREEN"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;[self addSubview:self.fullscreen];
        self.hideCursor=[NSButton checkboxWithTitle:@"Hide macOS cursor while playing" target:nil action:nil];self.hideCursor.frame=NSMakeRect(0,141,390,24);
        self.hideCursor.state=[settings[@"NFSV_HIDE_CURSOR"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;[self addSubview:self.hideCursor];
        self.enhancedGraphics=[NSButton checkboxWithTitle:@"Enhanced graphics (4x antialiasing, 16x filtering)" target:nil action:nil];self.enhancedGraphics.frame=NSMakeRect(0,111,390,24);
        self.enhancedGraphics.toolTip=@"Smooths jagged edges and keeps road textures sharp at an angle, as the Combined Patch recommends. Turn off for the original look or more speed.";
        self.enhancedGraphics.state=[settings[@"NFSV_ENHANCED_GRAPHICS"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;[self addSubview:self.enhancedGraphics];
        self.vibration=[NSButton checkboxWithTitle:@"Controller vibration" target:nil action:nil];self.vibration.frame=NSMakeRect(0,81,390,24);
        self.vibration.toolTip=@"Plays the game's force feedback (crashes, road surface, engine) on the game controller's motors. Each effect has its own setting on the game's force feedback tab.";
        self.vibration.state=[settings[@"NFSV_PAD_RUMBLE"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;[self addSubview:self.vibration];
        self.checkUpdates=[NSButton checkboxWithTitle:@"Check for updates" target:nil action:nil];self.checkUpdates.frame=NSMakeRect(0,51,390,24);
        self.checkUpdates.toolTip=@"Once a day the launcher asks GitHub whether a newer NFSV Builder is out and shows a notice here. Off: the launcher makes no network request.";
        self.checkUpdates.state=launcher_update_checks_enabled(defaults)?NSControlStateValueOn:NSControlStateValueOff;[self addSubview:self.checkUpdates];
        self.defaults=defaults;self.openURL=^(NSURL *url){[NSWorkspace.sharedWorkspace openURL:url];};
        label=[NSTextField wrappingLabelWithString:@"Menus and movies keep their original resolution.\nUse the in-game setting to let the game choose race resolution."];
        label.font=[NSFont systemFontOfSize:NSFont.smallSystemFontSize];label.textColor=NSColor.secondaryLabelColor;
        label.frame=NSMakeRect(0,0,390,38);[self addSubview:label];
    }
    return self;
}
- (void)saveToDefaults:(NSUserDefaults *)defaults{
    [defaults setObject:self.resolution.selectedItem.representedObject forKey:@"LaunchResolution"];
    [defaults setObject:self.frameLimit.selectedItem.representedObject forKey:@"LaunchFrameLimit"];
    [defaults setInteger:self.hudScale.integerValue forKey:@"LaunchHUDScale"];
    [defaults setInteger:self.stickSensitivity.integerValue forKey:@"LaunchStickSensitivity"];
    [defaults setBool:self.fullscreen.state==NSControlStateValueOn forKey:@"LaunchFullscreen"];
    [defaults setBool:self.hideCursor.state==NSControlStateValueOn forKey:@"LaunchHideCursor"];
    [defaults setBool:self.enhancedGraphics.state==NSControlStateValueOn forKey:@"LaunchEnhancedGraphics"];
    [defaults setBool:self.vibration.state==NSControlStateValueOn forKey:@"LaunchControllerVibration"];
    if(self.checkUpdates.enabled)[defaults setBool:self.checkUpdates.state==NSControlStateValueOn forKey:@"LaunchCheckUpdates"];
}
- (void)setBuilderVersion:(NSString *)stamp{
    if(stamp.length)return;
    self.checkUpdates.enabled=NO;self.checkUpdates.state=NSControlStateValueOff;
    self.checkUpdates.toolTip=@"This app was built without NFSV Builder. To update it, build it again.";
}
/* The notice sits below the settings; the view and its window grow to make room for it. */
- (void)resizeBy:(CGFloat)delta{
    for(NSView *view in self.subviews)if(view!=self.updateNotice)[view setFrameOrigin:NSMakePoint(view.frame.origin.x,view.frame.origin.y+delta)];
    [self setFrameSize:NSMakeSize(self.frame.size.width,self.frame.size.height+delta)];
    if(self.onResize)self.onResize();
}
- (void)showUpdate:(NSDictionary *)release{
    shownUpdate=release;
    if(!self.updateNotice){
        _updateNotice=[[NSView alloc] initWithFrame:NSMakeRect(0,0,390,50)];
        updateText=[NSTextField labelWithString:@""];updateText.frame=NSMakeRect(0,28,390,20);
        updateText.font=[NSFont boldSystemFontOfSize:NSFont.systemFontSize];[self.updateNotice addSubview:updateText];
        CGFloat x=0;
        for(NSArray *button in @[@[@"What's new",@"openReleasePage:"],@[@"Download",@"openDownload:"],@[@"Not now",@"dismissUpdate:"]]){
            NSButton *b=[NSButton buttonWithTitle:button[0] target:self action:NSSelectorFromString(button[1])];
            b.controlSize=NSControlSizeSmall;b.font=[NSFont systemFontOfSize:NSFont.smallSystemFontSize];[b sizeToFit];
            b.frame=NSMakeRect(x,0,b.frame.size.width+12,24);x+=b.frame.size.width+6;[self.updateNotice addSubview:b];
        }
    }
    updateText.stringValue=[NSString stringWithFormat:@"NFSV Builder %@ is available",release[@"version"]];
    if(self.updateNotice.superview)return;
    [self addSubview:self.updateNotice];[self resizeBy:60];
}
- (void)hideUpdate{
    if(!self.updateNotice.superview)return;
    [self.updateNotice removeFromSuperview];[self resizeBy:-60];
}
- (void)openReleasePage:(id)sender{(void)sender;self.openURL([NSURL URLWithString:shownUpdate[@"page"]]);}
- (void)openDownload:(id)sender{(void)sender;self.openURL([NSURL URLWithString:shownUpdate[@"download"]]);}
- (void)dismissUpdate:(id)sender{(void)sender;launcher_dismiss_update(self.defaults,shownUpdate[@"version"]);[self hideUpdate];}
@end

NSAlert *launcher_settings_dialog(NSUserDefaults *defaults,NSString *stamp,NFSVFetcher fetcher){
    NSAlert *dialog=[NSAlert new];dialog.messageText=@"Need for Speed: Porsche Unleashed";
    dialog.informativeText=@"Choose your settings, then start the game.";
    NFSVLaunchSettingsView *view=[[NFSVLaunchSettingsView alloc] initWithDefaults:defaults];dialog.accessoryView=view;
    [dialog addButtonWithTitle:@"Play"];[dialog addButtonWithTitle:@"Quit"];
    [view setBuilderVersion:stamp];
    __weak NSAlert *weakDialog=dialog;
    view.onResize=^{[weakDialog layout];};
    NSDictionary *pending=launcher_update_checks_enabled(defaults)?launcher_pending_update(defaults,stamp):nil;
    if(pending)[view showUpdate:pending];
    launcher_check_for_update(defaults,stamp,NSDate.date,fetcher,^(NSDictionary *release){[view showUpdate:release];});
    return dialog;
}

BOOL launcher_choose_settings(NSUserDefaults *defaults,NSString *stamp){
    NSAlert *dialog=launcher_settings_dialog(defaults,stamp,launcher_github_fetcher());
    NFSVLaunchSettingsView *view=(NFSVLaunchSettingsView *)dialog.accessoryView;
    [NSApp activateIgnoringOtherApps:YES];
    if([dialog runModal]!=NSAlertFirstButtonReturn)return NO;
    [view saveToDefaults:defaults];return YES;
}
