#include "display.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
int main(void){
    unsigned width=0,height=0;
    CHECK(display_resolution("1920x1080",&width,&height)&&width==1920&&height==1080);
    CHECK(display_resolution("640x480",&width,&height)&&width==640&&height==480);
    CHECK(!display_resolution("9999x9999",&width,&height));
    CHECK(!display_resolution("1920x1080extra",&width,&height));
    CHECK(!display_resolution(NULL,&width,&height));
    CHECK(display_frame_deadline(1000000000,0,60)==1000000000);
    CHECK(display_frame_deadline(1001000000,1000000000,60)==1016666666);
    CHECK(display_frame_deadline(1200000000,1000000000,60)==1200000000);
    CHECK(display_frame_deadline(1001000000,1000000000,0)==1001000000);
    DisplayRect r=display_fit(640,480,1920,1080);
    CHECK(r.x==240&&r.y==0&&r.w==1440&&r.h==1080);
    r=display_fit(1920,1080,800,600);
    CHECK(r.x==0&&r.y==75&&r.w==800&&r.h==450);
    int x,y;
    display_mouse(640,480,1440,1080,720,540,&x,&y);
    CHECK(x==320&&y==240);
    display_mouse(3840,2160,960,540,959.9,539.9,&x,&y);
    CHECK(x==3839&&y==2159);
    display_mouse(640,480,800,600,-10,700,&x,&y);
    CHECK(x==0&&y==479);
    r=display_fit(640,480,0,0);CHECK(r.w==0&&r.h==0);
    display_mouse(640,480,0,0,100,100,&x,&y);CHECK(x==0&&y==0);
    puts("display: aspect fit, scaled pointer and bounds passed");
}
