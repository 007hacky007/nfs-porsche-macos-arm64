#include "display.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
int main(void){
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
