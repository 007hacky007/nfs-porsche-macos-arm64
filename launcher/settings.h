#import <Cocoa/Cocoa.h>
@interface NFSVLaunchSettingsView : NSView
@property(nonatomic,strong) NSPopUpButton *resolution;
@property(nonatomic,strong) NSPopUpButton *frameLimit;
@property(nonatomic,strong) NSSlider *hudScale;
@property(nonatomic,strong) NSSlider *stickSensitivity;
@property(nonatomic,strong) NSButton *fullscreen;
@property(nonatomic,strong) NSButton *hideCursor;
@property(nonatomic,strong) NSButton *enhancedGraphics;
@property(nonatomic,strong) NSButton *vibration;
@property(nonatomic,strong) NSButton *checkUpdates;
@property(nonatomic,strong,readonly) NSView *updateNotice;
@property(nonatomic,strong) NSUserDefaults *defaults;
@property(nonatomic,copy) void (^openURL)(NSURL *);
@property(nonatomic,copy) void (^onResize)(void);
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (void)saveToDefaults:(NSUserDefaults *)defaults;
/* nil or empty for an app built without NFSV Builder, which cannot look for updates. */
- (void)setBuilderVersion:(NSString *)stamp;
- (void)showUpdate:(NSDictionary *)release;
- (void)hideUpdate;
@end
NSDictionary *launcher_environment(NSUserDefaults *,NSDictionary *);
#import "update.h"
/* The launcher dialog; `fetcher` asks GitHub for the latest Builder release when a check is due. */
NSAlert *launcher_settings_dialog(NSUserDefaults *,NSString *stamp,NFSVFetcher fetcher);
BOOL launcher_choose_settings(NSUserDefaults *,NSString *stamp);
