#include "runtime.h"
#include "launch_settings.h"
#include "display.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* FEScreenResolutionAccessor in the supported USA image; preserve its original getter. */
enum {RESOLUTION_VTABLE=0x5b5354,RESOLUTION_GETTER=0x4bc4b0};
static guest_fn_t original_getter;
static char requested_resolution[32];

int launch_resolution_override(uint32_t object,const char *request){
    unsigned width,height;
    if(!display_resolution(request,&width,&height)||!mem_valid(object,0x44)||MR32(object)!=RESOLUTION_VTABLE)return 0;
    unsigned count=MR32(object+0x14);
    uint32_t widths=MR32(object+0x38),heights=MR32(object+0x3c),depths=MR32(object+0x40);
    if(!count||count>DISPLAY_MODE_COUNT*2||!mem_valid(widths,count*4)||!mem_valid(heights,count*4)||!mem_valid(depths,count*4))return 0;
    int selected=-1;
    for(unsigned i=0;i<count;i++)if(MR32(widths+i*4)==width&&MR32(heights+i*4)==height){
        selected=(int)i;if(MR32(depths+i*4)==32)break;
    }
    if(selected<0)return 0;
    if(MR32(object+0x18)!=(unsigned)selected)
        fprintf(stderr,"launcher race resolution: %ux%u, accessor choice %d\n",width,height,selected);
    MR32(object+0x18)=(unsigned)selected;return 1;
}
static void resolution_getter(CPU *cpu){
    launch_resolution_override(cpu->ecx,requested_resolution);
    original_getter(cpu);
}
void launch_settings_init(void){
    const char *request=getenv("NFSV_RESOLUTION");
    if(original_getter||!display_resolution(request,NULL,NULL))return;
    original_getter=dispatch_fast(RESOLUTION_GETTER);
    if(!original_getter)return;
    snprintf(requested_resolution,sizeof requested_resolution,"%s",request);
    g_dtab[RESOLUTION_GETTER-DISPATCH_TEXT_BASE]=resolution_getter;
}
