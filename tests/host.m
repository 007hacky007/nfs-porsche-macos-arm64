#import <Cocoa/Cocoa.h>
#include "runtime.h"
#include "input.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
void win32_signal_event(uint32_t h){(void)h;}
static uint32_t chars[4096];static unsigned nchar;static unsigned activation_messages,focus_losses,focus_gains;
void win32_post_message(uint32_t m,uint32_t w,uint32_t l){(void)l;if(m==6||m==0x1c)activation_messages++;if(m==8)focus_losses++;if(m==7)focus_gains++;if(m==0x102&&nchar<4096)chars[nchar++]=w;}
static void drain_paste(unsigned count){
    for(unsigned i=0;i<100&&nchar<count;i++){usleep(40000);input_pump();}
    CHECK(nchar==count);
}
@interface NFSVView : NSView
- (void)insertText:(id)text replacementRange:(NSRange)range;
@end
@interface TestPasteView : NFSVView
@end
@implementation TestPasteView
- (void)paste:(id)sender{(void)sender;[self insertText:@"Bookkeeper" replacementRange:NSMakeRange(NSNotFound,0)];}
@end
@interface CursorTestView : NFSVView
@property(nonatomic,strong) NSCursor *installedCursor;
@end
@implementation CursorTestView
- (void)addCursorRect:(NSRect)rect cursor:(NSCursor *)cursor{(void)rect;self.installedCursor=cursor;}
@end
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];
    CursorTestView *cursorView=[[CursorTestView alloc] initWithFrame:NSMakeRect(0,0,640,480)];
    [cursorView resetCursorRects];CHECK(cursorView.installedCursor);
    CHECK(cursorView.installedCursor.image.valid&&cursorView.installedCursor.image.representations.count);
    NSBitmapImageRep *cursorPixels=[NSBitmapImageRep imageRepWithData:cursorView.installedCursor.image.TIFFRepresentation];
    CHECK(cursorPixels&&cursorPixels.hasAlpha);
    for(NSInteger y=0;y<cursorPixels.pixelsHigh;y++)for(NSInteger x=0;x<cursorPixels.pixelsWide;x++)
        CHECK([cursorPixels colorAtX:x y:y].alphaComponent==0);
    setenv("NFSV_HIDE_CURSOR","0",1);[cursorView resetCursorRects];CHECK(cursorView.installedCursor==NSCursor.arrowCursor);
    unsetenv("NFSV_HIDE_CURSOR");
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1440,1080)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    NFSVView *view=[[NSClassFromString(@"NFSVView") alloc] initWithFrame:NSMakeRect(0,0,1440,1080)];
    window.contentView=view;
    NSEvent *event=[NSEvent mouseEventWithType:NSEventTypeMouseMoved location:NSMakePoint(720,540)
        modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
    [view mouseMoved:event];
    int x,y;input_cursor(&x,&y);CHECK(x==320&&y==240);
    event=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(1439,1)
        modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    [view mouseDown:event];input_cursor(&x,&y);CHECK(x==639&&y==479);
    unsigned char mouse[20];input_mouse_state(mouse,sizeof mouse);CHECK(mouse[12]==128);
    input_key(200,38,1);
    input_focus(0);
    uint8_t keys[256];input_keyboard_state(keys);input_mouse_state(mouse,sizeof mouse);
    CHECK(!keys[200]&&!input_key_state(38)&&!mouse[12]);
    InputEvent events[1024];unsigned n=input_events(1,events,1024,0);int released=0;
    for(unsigned i=0;i<n;i++)if(events[i].offset==200&&events[i].value==0)released=1;
    CHECK(released);
    input_pump();input_focus(1);input_pump();CHECK(!activation_messages&&focus_losses==1&&focus_gains==1);nchar=0;
    [(id<NSTextInputClient>)view insertText:@"Bookkeeper" replacementRange:NSMakeRange(NSNotFound,0)];
    input_pump();CHECK(nchar==1&&chars[0]=='B');drain_paste(13);
    const uint32_t expected[]={'B','o',2,'o','k',2,'k','e',2,'e','p','e','r'};
    CHECK(nchar==sizeof expected/sizeof expected[0]);CHECK(!memcmp(chars,expected,sizeof expected));
    nchar=0;
    [(id<NSTextInputClient>)view insertText:@"A\nB\tC" replacementRange:NSMakeRange(NSNotFound,0)];input_pump();drain_paste(3);
    CHECK(nchar==3&&chars[0]=='A'&&chars[1]=='B'&&chars[2]=='C');
    TestPasteView *pasteView=[[TestPasteView alloc] initWithFrame:NSZeroRect];
    nchar=0;
    event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
        timestamp:0 windowNumber:window.windowNumber context:nil characters:@"v" charactersIgnoringModifiers:@"v" isARepeat:NO keyCode:9];
    CHECK([pasteView performKeyEquivalent:event]);input_pump();drain_paste(13);
    nchar=0;
    event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagControl
        timestamp:0 windowNumber:window.windowNumber context:nil characters:@"\x16" charactersIgnoringModifiers:@"v" isARepeat:NO keyCode:9];
    [pasteView keyDown:event];input_pump();drain_paste(13);
    nchar=0;
    [view insertText:[@"" stringByPaddingToLength:63 withString:@"A" startingAtIndex:0] replacementRange:NSMakeRange(NSNotFound,0)];
    input_pump();CHECK(nchar==1);unsigned previous=nchar;
    for(unsigned i=0;i<70&&nchar<125;i++){usleep(40000);input_pump();CHECK(nchar-previous<=2);previous=nchar;}
    CHECK(nchar==125);unsigned letters=0;for(unsigned i=0;i<nchar;i++)if(chars[i]=='A')letters++;CHECK(letters==63);
    nchar=0;[view insertText:@"Cancel" replacementRange:NSMakeRange(NSNotFound,0)];input_focus(0);input_pump();usleep(40000);input_pump();CHECK(nchar==0);
    CHECK(!window.visible);
    puts("Cocoa input: scaled game coordinates and clicks passed without displaying a window");
}}
