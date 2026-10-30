#include "hud.h"
#include <math.h>
#include <stdlib.h>

static float scale=1,offset_x,offset_y;
static unsigned drawing;

void hud_anchor(CPU *cpu,guest_fn_t original){
    int y=(int32_t)MR32(cpu->esp+8),widget_height=(int32_t)MR32(cpu->esp+16);
    int width=(int32_t)MR32(0x60c900),height=(int32_t)MR32(0x60c81c);
    original(cpu);
    /* The original width guard also skips bottom anchoring in a 640x512 HUD. */
    if(width==640&&height>480&&y>240){
        int bottom=(int32_t)cpu->edx+height-480,limit=height-widget_height;
        cpu->edx=(uint32_t)(bottom>limit?limit:bottom);
    }
}

void hud_initialize(CPU *cpu,guest_fn_t original){
    uint32_t args=cpu->esp,width=MR32(args+12),height=MR32(args+16);
    const char *setting=getenv("NFSV_HUD_SCALE");char *end;
    long percent=setting?strtol(setting,&end,10):100;
    if(setting&&(*setting<'0'||*setting>'9'||*end||percent<25||percent>100))percent=100;
    scale=fminf(width/640.f,height/480.f)*percent/100.f;if(scale<1)scale=1;
    unsigned virtual_width=(unsigned)lroundf(width/scale),virtual_height=(unsigned)lroundf(height/scale);
    offset_x=(width-virtual_width*scale)*.5f;offset_y=(height-virtual_height*scale)*.5f;
    /* The original layout anchors fixed-size widgets in this coordinate space. */
    MR32(args+12)=virtual_width;MR32(args+16)=virtual_height;
    original(cpu);
    MR32(args+12)=width;MR32(args+16)=height;
}
void hud_draw(CPU *cpu,guest_fn_t original){
    drawing++;original(cpu);drawing--;
}
static void flush(CPU *cpu){
    CPU saved=*cpu;call_guest(cpu,0x41a330,0,NULL);*cpu=saved;
}
void hud_physical_draw(CPU *cpu,guest_fn_t original){
    unsigned saved=drawing;
    /* Guest popup geometry is batched until the HUD submits it to Metal. */
    if(saved)flush(cpu);
    drawing=0;original(cpu);
    if(saved)flush(cpu);
    drawing=saved;
}
void hud_vertices(RenderVertex *vertices,unsigned count){
    if(!drawing)return;
    for(unsigned i=0;i<count;i++){
        vertices[i].x=(vertices[i].x+.5f)*scale+offset_x-.5f;
        vertices[i].y=(vertices[i].y+.5f)*scale+offset_y-.5f;
    }
}
void hud_clip(int clip[4]){
    if(!drawing)return;
    clip[0]=(int)floorf(clip[0]*scale+offset_x);clip[1]=(int)floorf(clip[1]*scale+offset_y);
    clip[2]=(int)ceilf(clip[2]*scale+offset_x);clip[3]=(int)ceilf(clip[3]*scale+offset_y);
}
