#include "display.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
const unsigned display_mode_sizes[DISPLAY_MODE_COUNT][2]={
    {640,480},{800,600},{1024,768},{1280,1024},{1600,1200},
    {1920,1080},{1920,1200},{2048,1536},{2560,1440},{2560,1600},
    {2560,1920},{2880,1800},{2880,2160},{3024,1964},{3840,2160},{4096,3072}
};
int display_resolution(const char *value,unsigned *w,unsigned *h){
    if(!value)return 0;
    for(unsigned i=0;i<DISPLAY_MODE_COUNT;i++){
        char name[32];snprintf(name,sizeof name,"%ux%u",display_mode_sizes[i][0],display_mode_sizes[i][1]);
        if(!strcmp(value,name)){if(w)*w=display_mode_sizes[i][0];if(h)*h=display_mode_sizes[i][1];return 1;}
    }
    return 0;
}
uint64_t display_frame_deadline(uint64_t now,uint64_t previous,unsigned fps){
    if(!fps||fps>240)return now;
    uint64_t next=previous?previous+1000000000ull/fps:now;
    return next>now?next:now;
}
DisplayRect display_fit(unsigned w,unsigned h,double vw,double vh){
    if(!w||!h||vw<=0||vh<=0)return (DisplayRect){0};
    double scale=fmin(vw/w,vh/h),width=w*scale,height=h*scale;
    return (DisplayRect){(vw-width)/2,(vh-height)/2,width,height};
}
void display_mouse(unsigned w,unsigned h,double vw,double vh,double px,double py,int *x,int *y){
    *x=*y=0;if(!w||!h||vw<=0||vh<=0)return;
    *x=(int)fmax(0,fmin(w-1,floor(px*w/vw)));
    *y=(int)fmax(0,fmin(h-1,floor(py*h/vh)));
}
