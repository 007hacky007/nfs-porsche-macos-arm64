#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
#include <time.h>
#include "runtime.h"
#include "render.h"
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
CPU *g_cur_cpu;
static id<MTLDevice> device;
static id<MTLCommandQueue> queue;
void *host_metal_device(void){if(!device)device=MTLCreateSystemDefaultDevice();return (__bridge void *)device;}
void *host_metal_queue(void){if(!queue)queue=[device newCommandQueue];return (__bridge void *)queue;}
void *host_metal_layer(void){return NULL;}
void host_frame_presented(void){}
static unsigned opened_w,opened_h;
void host_open_window(unsigned w,unsigned h){opened_w=w;opened_h=h;}
void guest_lock(CPU *c){(void)c;}
void guest_unlock(void){}
int main(void){@autoreleasepool{
 CHECK(render_mode(640,480));int clip[]={0,0,640,480};uint32_t p;
 render_clear(0xff00ff00,1,0,clip);CHECK(render_read(100,100,1,1,&p,0)&&p==0xff00ff00);
 RenderState s={.depth_func=7,.brightness=1,.stencil_func=7,.clip={0,0,640,480}};
 RenderVertex v[3]={{.x=0,.y=0,.z=.5,.rhw=1,.diffuse=0xffff0000},{.x=500,.y=0,.z=.5,.rhw=1,.diffuse=0xffff0000},{.x=0,.y=400,.z=.5,.rhw=1,.diffuse=0xffff0000}};
 render_draw(v,3,0,&s);CHECK(render_read(100,100,1,1,&p,0)&&p==0xffff0000);
 uint32_t blue=0xff0000ff;CHECK(render_texture(7,1,1,0,1,&blue));s.texture[0]=7;
 for(unsigned i=0;i<3;i++)v[i].diffuse=0xffffffff;
 render_draw(v,3,0,&s);CHECK(render_read(100,100,1,1,&p,0)&&p==blue);
 s.alpha_ref=128;s.alpha_func=4;for(unsigned i=0;i<3;i++)v[i].diffuse=0x00ffffff;
 render_draw(v,3,0,&s);CHECK(render_read(100,100,1,1,&p,0)&&p==blue);
 int partial[]={90,90,110,110};render_clear(0xffffff00,1,0,partial);CHECK(render_read(100,100,1,1,&p,0)&&p==0xffffff00);
 CHECK(render_read(80,80,1,1,&p,0)&&p==blue);
 render_clear(0xff000000,1,1,partial);CHECK(render_read(100,100,1,1,&p,0)&&p==0xffffff00);
 CHECK(render_write(100,100,1,1,&blue,1));CHECK(render_read(100,100,1,1,&p,1)&&p==blue);
 CHECK(render_read(100,100,1,1,&p,0)&&p==0xffffff00);
 render_clear(0xff000000,1,0,clip);
 s=(RenderState){.depth_func=7,.brightness=1,.stencil=1,.stencil_func=7,.stencil_pass=5,.clip={0,0,640,480}};
 for(unsigned i=0;i<3;i++)v[i].diffuse=0xffff0000;
 render_draw(v,3,0,&s);s.stencil_func=2;s.stencil_pass=0;
 for(unsigned i=0;i<3;i++)v[i].diffuse=0xff00ff00;
 render_draw(v,3,0,&s);CHECK(render_read(100,100,1,1,&p,0)&&p==0xffff0000);
 render_clear(0,1,1,partial);render_draw(v,3,0,&s);
 CHECK(render_read(100,100,1,1,&p,0)&&p==0xff00ff00);
 CHECK(render_read(80,80,1,1,&p,0)&&p==0xffff0000);
 render_texture_free(7);puts("Metal GPU: triangle, texture, alpha test and partial clears passed");
 CHECK(render_mode(3840,2160));CHECK(opened_w==3840&&opened_h==2160);
 int uhd[]={0,0,3840,2160};render_clear(0xff123456,1,0,uhd);
 CHECK(render_read(3839,2159,1,1,&p,0)&&p==0xff123456);
 CHECK(!render_mode(4097,2160));puts("Metal GPU: native 4K target and readback passed");
 /* Capture must own a snapshot even if the next frame or mode replaces it. */
 p=0xff123456;CHECK(render_write(0,0,1,1,&p,1));
 void render_capture_frame(unsigned);void render_capture_wait(void);
 double start=[NSDate timeIntervalSinceReferenceDate];render_capture_frame(999999);
 fprintf(stderr,"4K capture submission: %.1f ms\n",([NSDate timeIntervalSinceReferenceDate]-start)*1000);
 p=0xff0000ff;CHECK(render_write(0,0,1,1,&p,1));CHECK(render_mode(640,480));render_capture_wait();
 NSBitmapImageRep *capture=(NSBitmapImageRep *)[NSBitmapImageRep imageRepWithContentsOfFile:@"out/frame-999999.png"];
 CHECK(capture.pixelsWide==3840&&capture.pixelsHigh==2160);
 NSUInteger rgba[4];[capture getPixel:rgba atX:0 y:0];
 CHECK(rgba[0]==0x12&&rgba[1]==0x34&&rgba[2]==0x56&&rgba[3]==255);
 CHECK([NSFileManager.defaultManager removeItemAtPath:@"out/frame-999999.png" error:nil]);
 puts("capture: asynchronous snapshot survives frame and mode changes");
}}
