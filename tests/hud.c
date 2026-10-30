#include "hud.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static unsigned expected_width,expected_height;
static float expected_scale,expected_offset;
static RenderVertex queued[4],submitted[4];
static unsigned queued_count,submitted_count;
uint32_t call_guest(CPU *cpu,uint32_t fn,int count,const uint32_t *args){
    assert(fn==0x41a330&&count==0&&!args);
    hud_vertices(queued,queued_count);
    for(unsigned i=0;i<queued_count;i++)submitted[submitted_count++]=queued[i];
    queued_count=0;cpu->eax=999;cpu->ebx=999;cpu->cf=0;
    cpu->top=4;cpu->st[2]=123;cpu->fcw=0x1234;cpu->fsw=456;cpu->xmm[3].u64[0]=0xdead;return 0;
}
static void original_anchor(CPU *cpu){
    cpu->eax=MR32(cpu->esp+4);cpu->edx=MR32(cpu->esp+8);
    if(cpu->edx+MR32(cpu->esp+16)>MR32(0x60c81c))cpu->edx=MR32(0x60c81c)-MR32(cpu->esp+16);
    cpu->eip=MR32(cpu->esp);cpu->esp+=4;
}
static void anchor(unsigned width,unsigned height,unsigned y,unsigned widget_height,unsigned expected_y){
    CPU cpu={.esp=0x12000,.ebx=93,.cf=1};MR32(0x60c900)=width;MR32(0x60c81c)=height;
    MR32(cpu.esp)=0x12345678;MR32(cpu.esp+4)=100;MR32(cpu.esp+8)=y;MR32(cpu.esp+12)=85;MR32(cpu.esp+16)=widget_height;
    hud_anchor(&cpu,original_anchor);
    assert(cpu.eax==100&&cpu.edx==expected_y);
    assert(cpu.esp==0x12004&&cpu.eip==0x12345678&&cpu.ebx==93&&cpu.cf==1);
}
static void original_init(CPU *cpu){
    assert(MR32(cpu->esp+12)==expected_width);
    assert(MR32(cpu->esp+16)==expected_height);
    MR32(0x60c900)=MR32(cpu->esp+12);
    MR32(0x60c81c)=MR32(cpu->esp+16);
    cpu->eax=42;cpu->eip=MR32(cpu->esp);cpu->esp+=4;
}
static void check_vertex(float x,float y){
    RenderVertex v={.x=x-.5f,.y=y-.5f,.z=.7f,.rhw=2,.diffuse=0xff123456,.u=.25f,.v=.75f};
    hud_vertices(&v,1);
    assert(fabsf(v.x-(x*expected_scale+expected_offset-.5f))<.001f);
    assert(fabsf(v.y-(y*expected_scale-.5f))<.001f);
    assert(v.z==.7f&&v.rhw==2&&v.diffuse==0xff123456&&v.u==.25f&&v.v==.75f);
}
static void physical_popup(CPU *cpu){
    RenderVertex v={.x=1920,.y=1080};hud_vertices(&v,1);
    assert(v.x==1920&&v.y==1080);
    int clip[]={1700,900,2100,1200};hud_clip(clip);assert(clip[0]==1700&&clip[3]==1200);
    queued[queued_count++]=(RenderVertex){.x=1920,.y=1080};
    cpu->eip=MR32(cpu->esp);cpu->esp+=4;
}
static void original_draw(CPU *cpu){
    assert(MR32(0x60c900)==expected_width&&MR32(0x60c81c)==expected_height);
    check_vertex(10,20); /* Damage box at the left edge. */
    check_vertex(expected_width-85,expected_height-35); /* Bottom-right gauge. */
    check_vertex(expected_width*.5f,0); /* Centered mirror. */
    queued_count=submitted_count=0;queued[queued_count++]=(RenderVertex){.x=9.5f,.y=19.5f};
    CPU nested=*cpu;hud_physical_draw(&nested,physical_popup);
    assert(queued_count==0&&submitted_count==2);
    assert(fabsf(submitted[0].x-(10*expected_scale+expected_offset-.5f))<.001f);
    assert(submitted[1].x==1920&&submitted[1].y==1080);
    assert(nested.eax==cpu->eax&&nested.ebx==cpu->ebx&&nested.cf==cpu->cf);
    assert(nested.top==cpu->top&&nested.st[2]==cpu->st[2]&&nested.fcw==cpu->fcw&&nested.fsw==cpu->fsw);
    assert(nested.xmm[3].u64[0]==cpu->xmm[3].u64[0]);
    check_vertex(10,20); /* The popup must restore its enclosing HUD scope. */
    int clip[]={10,20,110,120};hud_clip(clip);
    assert(clip[0]==(int)floorf(10*expected_scale+expected_offset));
    assert(clip[1]==(int)floorf(20*expected_scale));
    assert(clip[2]==(int)ceilf(110*expected_scale+expected_offset));
    assert(clip[3]==(int)ceilf(120*expected_scale));
    cpu->eax=77;cpu->eip=MR32(cpu->esp);cpu->esp+=4;
}
static void resolution(unsigned width,unsigned height,unsigned virtual_width,unsigned virtual_height,float scale){
    CPU cpu={.esp=0x12000,.ebx=91,.cf=1};
    expected_width=virtual_width;expected_height=virtual_height;
    expected_scale=scale;expected_offset=(width-virtual_width*scale)*.5f;
    MR32(cpu.esp)=0x12345678;MR32(cpu.esp+12)=width;MR32(cpu.esp+16)=height;
    hud_initialize(&cpu,original_init);
    assert(cpu.esp==0x12004&&cpu.eip==0x12345678&&cpu.eax==42&&cpu.ebx==91&&cpu.cf==1);
    assert(MR32(0x1200c)==width&&MR32(0x12010)==height);
    RenderVertex v={.x=10,.y=20};hud_vertices(&v,1);assert(v.x==10&&v.y==20);
    cpu.esp=0x12000;hud_draw(&cpu,original_draw);
    assert(cpu.esp==0x12004&&cpu.eip==0x12345678&&cpu.eax==77&&cpu.ebx==91&&cpu.cf==1);
    hud_vertices(&v,1);assert(v.x==10&&v.y==20);
    int clip[]={10,20,110,120};hud_clip(clip);assert(clip[0]==10&&clip[3]==120);
}
int main(void){
    mem_init();mem_commit(0x10000,0x4000);mem_commit(0x60c000,0x4000);
    anchor(640,512,444,35,476);
    anchor(640,512,100,35,100);
    anchor(640,512,240,35,240);
    anchor(640,512,444,100,412);
    anchor(640,480,444,35,444);
    anchor(853,480,444,35,444);
    resolution(3840,2160,853,480,4.5f);
    resolution(1920,1080,853,480,2.25f);
    resolution(2560,1440,853,480,3);
    resolution(1280,1024,640,512,2);
    resolution(640,480,640,480,1);
    puts("HUD: uniform scaling, edge/center anchors, clipping and guest ABI passed");
}
