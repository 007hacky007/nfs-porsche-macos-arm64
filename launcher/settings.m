#import "settings.h"
#include "../runtime/display.h"

static BOOL boolean_setting(NSUserDefaults *defaults,NSString *key,BOOL fallback){
    id value=[defaults objectForKey:key];return [value isKindOfClass:NSNumber.class]?[value boolValue]:fallback;
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
    return environment;
}

@implementation NFSVLaunchSettingsView
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults{
    if((self=[super initWithFrame:NSMakeRect(0,0,390,188)])){
        NSDictionary *settings=launcher_environment(defaults,@{});
        NSTextField *label=[NSTextField labelWithString:@"Race resolution:"];label.frame=NSMakeRect(0,155,140,22);[self addSubview:label];
        self.resolution=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(145,152,245,28) pullsDown:NO];
        self.resolution.accessibilityLabel=@"Race resolution";
        [self.resolution addItemWithTitle:@"Use in-game setting"];self.resolution.lastItem.representedObject=@"";
        for(unsigned i=0;i<DISPLAY_MODE_COUNT;i++){
            NSString *value=[NSString stringWithFormat:@"%ux%u",display_mode_sizes[i][0],display_mode_sizes[i][1]];
            [self.resolution addItemWithTitle:[NSString stringWithFormat:@"%u x %u",display_mode_sizes[i][0],display_mode_sizes[i][1]]];
            self.resolution.lastItem.representedObject=value;
            if([settings[@"NFSV_RESOLUTION"] isEqual:value])[self.resolution selectItem:self.resolution.lastItem];
        }
        [self addSubview:self.resolution];
        label=[NSTextField labelWithString:@"Frame-rate limit:"];label.frame=NSMakeRect(0,119,140,22);[self addSubview:label];
        self.frameLimit=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(145,116,245,28) pullsDown:NO];
        self.frameLimit.accessibilityLabel=@"Frame-rate limit";
        for(NSNumber *limit in @[@0,@30,@60,@120]){
            [self.frameLimit addItemWithTitle:limit.intValue?[NSString stringWithFormat:@"%@ FPS",limit]:@"Game default"];
            self.frameLimit.lastItem.representedObject=limit;
            if([settings[@"NFSV_FPS_LIMIT"] intValue]==limit.intValue)[self.frameLimit selectItem:self.frameLimit.lastItem];
        }
        [self addSubview:self.frameLimit];
        self.fullscreen=[NSButton checkboxWithTitle:@"Start in fullscreen" target:nil action:nil];self.fullscreen.frame=NSMakeRect(0,81,390,24);
        self.fullscreen.state=[settings[@"NFSV_FULLSCREEN"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;[self addSubview:self.fullscreen];
        self.hideCursor=[NSButton checkboxWithTitle:@"Hide macOS cursor while playing" target:nil action:nil];self.hideCursor.frame=NSMakeRect(0,51,390,24);
        self.hideCursor.state=[settings[@"NFSV_HIDE_CURSOR"] boolValue]?NSControlStateValueOn:NSControlStateValueOff;[self addSubview:self.hideCursor];
        label=[NSTextField wrappingLabelWithString:@"Menus and movies keep their original resolution.\nUse the in-game setting to let the game choose race resolution."];
        label.font=[NSFont systemFontOfSize:NSFont.smallSystemFontSize];label.textColor=NSColor.secondaryLabelColor;
        label.frame=NSMakeRect(0,0,390,38);[self addSubview:label];
    }
    return self;
}
- (void)saveToDefaults:(NSUserDefaults *)defaults{
    [defaults setObject:self.resolution.selectedItem.representedObject forKey:@"LaunchResolution"];
    [defaults setObject:self.frameLimit.selectedItem.representedObject forKey:@"LaunchFrameLimit"];
    [defaults setBool:self.fullscreen.state==NSControlStateValueOn forKey:@"LaunchFullscreen"];
    [defaults setBool:self.hideCursor.state==NSControlStateValueOn forKey:@"LaunchHideCursor"];
}
@end

BOOL launcher_choose_settings(NSUserDefaults *defaults){
    NSAlert *dialog=[NSAlert new];dialog.messageText=@"Need for Speed: Porsche Unleashed";
    dialog.informativeText=@"Choose your settings, then start the game.";
    NFSVLaunchSettingsView *view=[[NFSVLaunchSettingsView alloc] initWithDefaults:defaults];dialog.accessoryView=view;
    [dialog addButtonWithTitle:@"Play"];[dialog addButtonWithTitle:@"Quit"];
    [NSApp activateIgnoringOtherApps:YES];
    if([dialog runModal]!=NSAlertFirstButtonReturn)return NO;
    [view saveToDefaults:defaults];return YES;
}
