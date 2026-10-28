/* Exercise original lifted codec math without starting Windows or the GUI. */
#include "runtime.h"
#include "image.h"
#include <stdio.h>
#include <stdlib.h>
void guest_lock(CPU *);
void guest_unlock(void);
static CPU cpu;
static void cdecl_call(uint32_t fn,unsigned n,uint32_t *args){
 CPU *c=&cpu;uint32_t sp=c->esp;for(unsigned i=n;i>0;i--)PUSH32(args[i-1]);PUSH32(0xdeadc0de);dispatch_indirect(c,fn);c->esp+=n*4;
 if(c->esp!=sp||c->eip!=0xdeadc0de){fputs("codec call stack imbalance\n",stderr);exit(1);}
}
int main(int argc,char **argv){
 if(argc!=2)return 1;mem_init();if(mem_load_pe(argv[1]))return 1;
 mem_commit(0xc00000,0x20000);mem_commit(0x7f000000,0x10000);cpu.esp=0x7f010000;cpu.fs_base=0xc00000;cpu.fcw=0x37f;
 MR32(0xc00018)=0xc00000;MR32(0xc00024)=1;MR32(0xc0002c)=0xc01000;platform_init();dispatch_init();guest_lock(&cpu);
 uint32_t args[]={16};cdecl_call(0x56ad70,1,args);
 FILE *tables=fopen("out/codec-tables.bin","wb");if(!tables)return 1;fwrite(guest_ptr(0x6b62a0,0x2000),1,0x2000,tables);fclose(tables);
 uint32_t values[]={0x80808080,0x10801080,0xeb80eb80,0x00800080,0xff80ff80};
 for(unsigned i=0;i<5;i++){MR32(0xc02000)=values[i];uint32_t convert[]={0xc02000,0xc02020,1};cdecl_call(0x592610,3,convert);printf("%08x -> %08x\n",values[i],MR32(0xc02020));}
 mem_commit(0x2000000,0x200000);
 FILE *movie=fopen("local/game/FEData/movies/earts-av.mad","rb");if(!movie)return 1;size_t bytes=fread(guest_ptr(0x2080000,400000),1,400000,movie);fclose(movie);if(bytes<0x8e4)return 1;
 unsigned decoded=0;
 for(uint32_t offset=0;offset+24<bytes && decoded<12;){
  uint32_t packet=0x2080000+offset,length=MR32(packet+4)&0xffffff;if(length<8||offset+length>bytes)return 1;
  if(!memcmp(guest_ptr(packet,3),"MAD",3)){
   uint32_t init[]={packet+24,MR8(packet+3)!='k',MR8(packet+21)};cdecl_call(0x56ca50,3,init);
   for(unsigned y=0;y<240;y+=16)for(unsigned x=0;x<320;x+=16){uint32_t at=(y*320+x)*2;uint32_t block[]={0x2010000+at,0x2050000+at,320};cdecl_call(0x56cce0,3,block);}
   memcpy(guest_ptr(0x2010000,320*240*2),guest_ptr(0x2050000,320*240*2),320*240*2);decoded++;
  }
  offset+=length;
 }
 FILE *frame=fopen("out/codec-frame.bin","wb");if(!frame)return 1;fwrite(guest_ptr(0x2050000,320*240*2),1,320*240*2,frame);fclose(frame);
 for(unsigned y=0;y<240;y++){uint32_t row[]={0x2050000+y*640,0x2100000+y*640,160};cdecl_call(0x592610,3,row);}
 frame=fopen("out/codec-frame-rgb565.bin","wb");if(!frame)return 1;fwrite(guest_ptr(0x2100000,320*240*2),1,320*240*2,frame);fclose(frame);
 mem_commit(0x2200000,0x100000);memset(guest_ptr(0x5de620,48),0,48);
 MR32(0x5de620)=0x57494e44;MR32(0x5de624)=640;MR32(0x5de628)=480;MR32(0x5de62c)=0x01101078;MR8(0x5de630)=1;
 MR32(0x5de63c)=640;MR32(0x5de640)=200;MR32(0x5de644)=1280;MR32(0x5de64c)=0x2200000;
 uint32_t blit[]={0,0,0x2050000,320,240,3};cdecl_call(0x56a920,6,blit);
 frame=fopen("out/codec-blit.bin","wb");if(!frame)return 1;fwrite(guest_ptr(0x2200000,640*480*2),1,640*480*2,frame);fclose(frame);
 guest_unlock();return 0;
}
