#import <Cocoa/Cocoa.h>
#include "runtime.h"
#include "input.h"
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
void win32_signal_event(uint32_t h){(void)h;}
void win32_post_message(uint32_t m,uint32_t w,uint32_t l){(void)m;(void)w;(void)l;}
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1440,1080)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    NSView *view=[[NSClassFromString(@"NFSVView") alloc] initWithFrame:NSMakeRect(0,0,1440,1080)];
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
    CHECK(!window.visible);
    puts("Cocoa input: scaled game coordinates and clicks passed without displaying a window");
}}
