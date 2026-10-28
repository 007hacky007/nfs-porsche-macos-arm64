#include "render.h"
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#x);exit(1);}}while(0)
int main(void){
 uint32_t out[4],palette[256]={0};
 uint16_t src[]={0xf800,0x07e0,0x001f,0xffff};
 CHECK(render_pixels(4,4,1,src,sizeof src,NULL,out));
 CHECK(out[0]==0xffff0000 && out[1]==0xff00ff00 && out[2]==0xff0000ff && out[3]==0xffffffff);
 CHECK(!render_pixels(4,4,1,src,sizeof src-1,NULL,out));
 uint16_t alpha[]={0x7fff,0xffff,0xf123,0x0123};
 CHECK(render_pixels(3,2,1,alpha,4,NULL,out));CHECK(out[0]==0xffffff && out[1]==0xffffffff);
 CHECK(render_pixels(7,2,1,alpha+2,4,NULL,out));CHECK(out[0]==0xff112233 && out[1]==0x112233);
 uint8_t indices[]={0x21};palette[1]=0x12345678;palette[2]=0x009abcde;
 CHECK(render_pixels(1,2,1,indices,1,palette,out));CHECK(out[0]==0xff345678 && out[1]==0xff9abcde);
 CHECK(!render_pixels(2,1,1,indices,1,NULL,out));
 puts("pixel formats: RGB565, ARGB1555, ARGB4444 and palettes passed");
}
