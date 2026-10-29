#include "runtime.h"
#include "launch_settings.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
guest_fn_t g_dtab[DISPATCH_TEXT_SIZE];
static void original_getter(CPU *c){c->eax=MR32(c->ecx+0x18);POP32(c->eip);}
int main(void){
    mem_init();mem_commit(0x10000,0x4000);
    uint32_t object=0x10000;
    MR32(object)=0x5b5354;MR32(object+0x14)=3;
    MR32(object+0x38)=0x11000;MR32(object+0x3c)=0x11100;MR32(object+0x40)=0x11200;
    for(unsigned i=0;i<3;i++){
        MR32(0x11000+i*4)=i?1920:640;MR32(0x11100+i*4)=i?1080:480;MR32(0x11200+i*4)=i==2?32:16;
    }
    assert(launch_resolution_override(object,"1920x1080")&&MR32(object+0x18)==2);
    MR32(object+0x18)=0;
    assert(!launch_resolution_override(object,"1920x1080junk")&&MR32(object+0x18)==0);
    MR32(object)=123;assert(!launch_resolution_override(object,"1920x1080"));MR32(object)=0x5b5354;
    MR32(object+0x14)=100;assert(!launch_resolution_override(object,"1920x1080"));MR32(object+0x14)=3;
    MR32(object+0x38)=0xfffffff8;assert(!launch_resolution_override(object,"1920x1080"));MR32(object+0x38)=0x11000;
    g_dtab[0x4bc4b0-DISPATCH_TEXT_BASE]=original_getter;
    setenv("NFSV_RESOLUTION","1920x1080",1);launch_settings_init();
    CPU cpu={.ecx=object,.esp=0x12000,.cf=1};MR32(cpu.esp)=0x12345678;
    dispatch_fast(0x4bc4b0)(&cpu);
    assert(cpu.eax==2&&cpu.esp==0x12004&&cpu.eip==0x12345678&&cpu.cf==1);
    puts("Launch resolution: original accessor selection, 32-bit mode, validation and callback ABI passed");
}
