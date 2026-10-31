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
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (void)saveToDefaults:(NSUserDefaults *)defaults;
@end
NSDictionary *launcher_environment(NSUserDefaults *,NSDictionary *);
BOOL launcher_choose_settings(NSUserDefaults *);
