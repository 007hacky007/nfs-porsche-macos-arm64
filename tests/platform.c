#include "runtime.h"
#include "image.h"
#include "input.h"
#include "audio.h"
#include "render.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <pthread.h>
#include <stdatomic.h>
#include <math.h>
#undef assert
#define assert(value) do { if(!(value)){fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#value);exit(1);} } while(0)

const uint32_t g_fn_count=0, g_fn_addr[1]={0};
const guest_fn_t g_fn_ptr[1]={0};
void guest_lock(CPU *);
void guest_unlock(void);
uint32_t com_object(unsigned,unsigned);
int environment_call(CPU *,const char *,uint32_t *);
void fileio_set_root(const char *);
void fileio_set_write_root(const char *);
void fileio_set_readonly_root(int);
static CPU cpu;
int fileio_call(CPU *,const char *,uint32_t *);
static uint32_t attributes(uint32_t path){
    CPU *c=&cpu;uint32_t out;PUSH32(path);
    assert(fileio_call(c,"GetFileAttributesA",&out));c->esp+=4;return out;
}
extern int test_fail_copy_write,test_fail_copy_close;
void heap_totals(uint64_t *,uint64_t *,uint64_t *,uint64_t *);
static _Atomic int scheduled;
void win32_post_message(uint32_t,uint32_t,uint32_t);
static void *message_worker(void *unused){
    (void)unused;usleep(10000);CPU other={.fs_base=0xc10000,.fcw=0x37f};
    guest_lock(&other);win32_post_message(0x400,123,456);guest_unlock();return NULL;
}
static void *scheduled_worker(void *unused){
    (void)unused;CPU other={.fs_base=0xc10000,.fcw=0x37f};MR32(0xc10024)=42;
    guest_lock(&other);atomic_store(&scheduled,1);guest_unlock();return NULL;
}

static uint32_t api(const char *name, int count, uint32_t *args){
    CPU *c=&cpu;
    uint32_t sp=c->esp;
    uint32_t index=0;
    for (;index<nfsv_import_count;index++) if (!strcmp(nfsv_imports[index].name,name)) break;
    assert(index<nfsv_import_count);
    assert(nfsv_imports[index].nargs==count);
    for (int i=count-1;i>=0;i--) PUSH32(args[i]);
    PUSH32(0xdeadc0de);
    platform_call(c,index);
    assert(c->eip==0xdeadc0de && c->esp==sp);
    return c->eax;
}

static void callback(CPU *c){
    assert(MR32(c->esp+4)==123 && MR32(c->esp+8)==456);
    c->eax=579; POP32(c->eip); c->esp+=8;
}

static uint32_t method(uint32_t self,unsigned slot,int count,uint32_t *args){
    CPU *c=&cpu;uint32_t sp=c->esp;
    for(int i=count-1;i>=0;i--)PUSH32(args[i]);
    PUSH32(0xdeadc0de);
    dispatch_indirect(c,MR32(MR32(self)+4*slot));
    assert(c->eip==0xdeadc0de && c->esp==sp);
    return c->eax;
}

int main(void){
    char registry[]="out/test-registry-XXXXXX";
    int regfd=mkstemp(registry);assert(regfd>=0);close(regfd);setenv("NFSV_REGFILE",registry,1);
    mem_init(); mem_commit(IMAGE_BASE,IMAGE_SIZE); mem_commit(0xc00000,0x20000);
    mem_commit(0x7f000000,0x10000);
    cpu.esp=0x7f010000; cpu.fs_base=0xc00000; cpu.fcw=0x37f;
    MR32(cpu.fs_base+0x18)=cpu.fs_base; MR32(cpu.fs_base+0x24)=1; MR32(cpu.fs_base+0x2c)=0xc01000;
    platform_init(); guest_lock(&cpu);
    if(IMAGE_SIZE>0x300000){
        cpu.top=0;cpu.st[0]=0.5;api("_CItan",0,NULL);assert(fabs(cpu.st[0]-tan(0.5))<1e-12);
        cpu.top=0;cpu.st[0]=2;cpu.st[1]=1;api("_CIatan2",0,NULL);assert(cpu.top==1&&fabs(cpu.st[1]-atan2(1,2))<1e-12);
        uint32_t placement=0xc0d100;memset(g_mem+placement,0,44);MR32(placement)=44;
        uint32_t window_args[]={0xb00001,placement};assert(api("GetWindowPlacement",2,window_args)==1);
        assert(MR32(placement)==44&&MR32(placement+8)==1&&MR32(placement+36)==640&&MR32(placement+40)==480);
    }
    uint32_t cbargs[]={123,456};
    g_dtab[0]=callback;
    assert(call_guest(&cpu,DISPATCH_TEXT_BASE,2,cbargs)==579);
    assert(cpu.esp==0x7f010000);
    g_dtab[0]=NULL;
    uint32_t args[]={0,1,0,0};
    uint32_t event=api("CreateEventA",4,args);
    assert(event);
    MR32(0xc02000)=event;
    uint32_t waitargs[]={1,0xc02000,0,0,0};
    assert(api("WaitForMultipleObjectsEx",5,waitargs)==258);
    assert(api("SetEvent",1,&event)==1);
    assert(api("WaitForMultipleObjectsEx",5,waitargs)==0);
    assert(api("CloseHandle",1,&event)==1);
    args[1]=0; args[2]=1;
    uint32_t first=api("CreateEventA",4,args);
    args[2]=0;
    uint32_t second=api("CreateEventA",4,args);
    MR32(0xc02000)=first; MR32(0xc02004)=second;
    waitargs[0]=2; waitargs[2]=1;
    assert(api("WaitForMultipleObjectsEx",5,waitargs)==258);
    waitargs[0]=1; waitargs[2]=0;
    assert(api("WaitForMultipleObjectsEx",5,waitargs)==0);
    assert(api("WaitForMultipleObjectsEx",5,waitargs)==258);
    api("SetEvent",1,&first); api("SetEvent",1,&second);
    waitargs[0]=2; waitargs[2]=1;
    assert(api("WaitForMultipleObjectsEx",5,waitargs)==0);
    assert(api("WaitForMultipleObjectsEx",5,waitargs)==258);
    MR32(0xc02000)=0x123456;
    waitargs[0]=1; waitargs[2]=0;
    assert(api("WaitForMultipleObjectsEx",5,waitargs)==0xffffffff);
    assert(api("GetLastError",0,NULL)==6);
    api("CloseHandle",1,&first); api("CloseHandle",1,&second);
    uint32_t wsargs[]={0x101,0xc03000};
    assert(api("WSAStartup",2,wsargs)==0);
    assert(MR16(0xc03000)==0x101 && MR16(0xc03002)==0x202);
    uint32_t socketargs[]={2,2,17};
    uint32_t sock=api("socket",3,socketargs);
    assert(sock!=0xffffffff);
    memset(g_mem+0xc04000,0,64); MR16(0xc04000)=2; MR32(0xc04004)=0x0100007f;
    uint32_t bindargs[]={sock,0xc04000,16};
    assert(api("bind",3,bindargs)==0);
    MR32(0xc04020)=16;
    uint32_t nameargs[]={sock,0xc04000,0xc04020};
    assert(api("getsockname",3,nameargs)==0 && MR16(0xc04002)!=0);
    memcpy(g_mem+0xc04030,"ping",4);
    uint32_t sendargs[]={sock,0xc04030,4,0,0xc04000,16};
    assert(api("sendto",6,sendargs)==4);
    uint32_t recvargs[]={sock,0xc04038,4,0,0xc04000,0xc04020};
    assert(api("recvfrom",6,recvargs)==4);
    assert(!memcmp(g_mem+0xc04038,"ping",4));
    assert(api("closesocket",1,&sock)==0);
    strcpy((char *)g_mem+0xc04100,"nfsv-local");uint32_t hostname=0xc04100;
    uint32_t hostentry=api("gethostbyname",1,&hostname);assert(hostentry);
    uint32_t virtual_address=MR32(MR32(MR32(hostentry+12)));
    assert(virtual_address==0x010200c0);
    sock=api("socket",3,socketargs);assert(sock!=0xffffffff);
    MR32(0xc04004)=virtual_address;MR16(0xc04002)=0;bindargs[0]=sock;
    assert(api("bind",3,bindargs)==0);nameargs[0]=sock;assert(api("getsockname",3,nameargs)==0&&MR32(0xc04004)==virtual_address);
    sendargs[0]=sock;recvargs[0]=sock;assert(api("sendto",6,sendargs)==4);assert(api("recvfrom",6,recvargs)==4);
    assert(!memcmp(g_mem+0xc04038,"ping",4));assert(api("closesocket",1,&sock)==0);
    assert(api("WSACleanup",0,NULL)==0);
    wsargs[0]=0x303;
    assert(api("WSAStartup",2,wsargs)==10092);
    uint32_t diargs[]={IMAGE_BASE,0x500,0xc05000,0};
    assert(api("DirectInputCreateA",4,diargs)==0);
    uint32_t di=MR32(0xc05000);
    MR32(0xc05020)=0x6f1d2b61;
    uint32_t createargs[]={di,0xc05020,0xc05004,0};
    assert(method(di,3,4,createargs)==0);
    uint32_t keyboard=MR32(0xc05004);
    uint32_t propertyargs[]={keyboard,999,0xc05080};
    assert(method(keyboard,6,3,propertyargs)==0x80004001);
    MR32(0xc05080)=20;MR32(0xc05084)=16;MR32(0xc05090)=32;
    propertyargs[1]=1;
    assert(method(keyboard,6,3,propertyargs)==0);
    MR32(0xc05090)=0;
    assert(method(keyboard,5,3,propertyargs)==0 && MR32(0xc05090)==32);
    uint32_t stateargs[]={keyboard,256,0xc06000};
    assert(method(keyboard,9,3,stateargs)==0x8007000c);
    assert(method(keyboard,7,1,&keyboard)==0);
    input_key(0x1e,'A',1);
    assert(method(keyboard,9,3,stateargs)==0 && MR8(0xc0601e)==128);
    input_key(0x1e,'A',0);
    assert(method(keyboard,9,3,stateargs)==0 && MR8(0xc0601e)==0);
    MR32(0xc050a0)=560;
    uint32_t infoargs[]={keyboard,0xc050a0};
    assert(method(keyboard,15,2,infoargs)==0 && MR32(0xc050a0+36)==3);
    MR32(0xc0e000)=316;uint32_t objectargs[]={keyboard,0xc0e000,30,1};
    assert(method(keyboard,14,4,objectargs)==0&&MR32(0xc0e014)==30&&(MR32(0xc0e018)&12));
    MR32(0xc05020)=0x6f1d2b60;assert(method(di,3,4,createargs)==0);uint32_t mouse=MR32(0xc05004);
    objectargs[0]=mouse;objectargs[2]=12;assert(method(mouse,14,4,objectargs)==0&&MR32(0xc0e014)==12);
    objectargs[2]=8;assert(method(mouse,14,4,objectargs)==0&&(MR32(0xc0e018)&3)==1);
    objectargs[2]=100;assert(method(mouse,14,4,objectargs)==0x80070002);
    assert(method(mouse,2,1,&mouse)==0);
    strcpy((char *)g_mem+0xc07000,"c:\\NfSv\\Data");
    uint32_t uppercase=0xc07000;
    assert(api("CharUpperA",1,&uppercase)==0xc07000);
    assert(!strcmp((char *)g_mem+0xc07000,"C:\\NFSV\\DATA"));
    uppercase='z';assert(api("CharUpperA",1,&uppercase)=='Z');
    uint32_t ds=com_object(4,0);
    memset(g_mem+0xc08000,0,256);
    MR32(0xc08000)=36;MR32(0xc08008)=64;MR32(0xc08010)=0xc08040;
    MR16(0xc08040)=1;MR16(0xc08042)=1;MR32(0xc08044)=44100;
    MR32(0xc08048)=88200;MR16(0xc0804c)=2;MR16(0xc0804e)=16;
    uint32_t dsargs[]={ds,0xc08000,0xc08020,0};
    assert(method(ds,3,4,dsargs)==0);
    uint32_t buffer=MR32(0xc08020);
    uint32_t lockargs[]={buffer,60,8,0xc08080,0xc08084,0xc08088,0xc0808c,0};
    assert(method(buffer,11,8,lockargs)==0);
    assert(MR32(0xc08084)==4 && MR32(0xc0808c)==4);
    uint32_t data=MR32(0xc08088);assert(MR32(0xc08080)==data+60);
    MR16(data)=10000;MR16(data+2)=10000;
    uint32_t unlockargs[]={buffer,data+60,4,data,4};
    assert(method(buffer,19,5,unlockargs)==0);
    uint32_t dupargs[]={ds,buffer,0xc08024};
    assert(method(ds,5,3,dupargs)==0);
    uint32_t duplicate=MR32(0xc08024);
    assert(method(buffer,2,1,&buffer)==0);
    uint32_t playargs[]={duplicate,0,0,0};
    assert(method(duplicate,12,4,playargs)==0);
    int16_t mixed[4];audio_mix(mixed,2);
    for(unsigned i=0;i<4;i++)assert(mixed[i]==10000);
    assert(method(duplicate,2,1,&duplicate)==0);
    assert(method(ds,2,1,&ds)==0);
    strcpy((char *)g_mem+0xc09000,"SOFTWARE\\Electronic Arts\\Need for Speed - Porsche 2000");
    strcpy((char *)g_mem+0xc09100,"Boundary Test");strcpy((char *)g_mem+0xc09180,"dx");
    uint32_t openkey[]={0x80000002,0xc09000,0,0xf003f,0xc09200};
    assert(api("RegOpenKeyExA",5,openkey)==0);
    uint32_t setvalue[]={MR32(0xc09200),0xc09100,0,1,0xc09180,2};
    MR8(0xc09182)=0xcd;
    assert(api("RegSetValueExA",6,setvalue)==0);
    MR32(0xc09210)=2;memset(g_mem+0xc09220,0xcd,4);
    uint32_t query[]={MR32(0xc09200),0xc09100,0,0,0xc09220,0xc09210};
    assert(api("RegQueryValueExA",6,query)==0);
    assert(MR32(0xc09210)==2 && MR8(0xc09220)=='d' && MR8(0xc09221)=='x' && MR8(0xc09222)==0xcd);
    MR8(0xc09182)=0;
    assert(api("RegSetValueExA",6,setvalue)==0);
    MR32(0xc09210)=4;
    assert(api("RegQueryValueExA",6,query)==0);
    assert(MR32(0xc09210)==3 && MR8(0xc09222)==0);
    strcpy((char *)g_mem+0xc09100,"Missing Value");MR32(0xc09210)=255;
    assert(api("RegQueryValueExA",6,query)==2);
    assert(MR32(0xc09210)==255);
    strcpy((char *)g_mem+0xc0a000,"NFSV_TEST_ENV");strcpy((char *)g_mem+0xc0a040,"native");
    const char *native_env=getenv("NFSV_TEST_ENV");
    uint32_t envargs[]={0xc0a000,0xc0a040};assert(api("SetEnvironmentVariableA",2,envargs)==1);
    assert(getenv("NFSV_TEST_ENV")==native_env);
    CPU *c=&cpu;uint32_t saved=c->esp,result;
    PUSH32(16);PUSH32(0xc0a080);PUSH32(0xc0a000);
    assert(environment_call(c,"GetEnvironmentVariableA",&result)&&result==6);
    assert(!strcmp((char *)g_mem+0xc0a080,"native"));c->esp=saved;
    uint32_t block=api("GetEnvironmentStringsW",0,NULL);assert(MR16(block)=='N');
    assert(api("FreeEnvironmentStringsW",1,&block)==1);
    strcpy((char *)g_mem+0xc0b000,".\\drivers\\dx7z");
    uint32_t drivername=0xc0b000,driver=api("LoadLibraryA",1,&drivername);
    assert(driver);
    assert(api("DisableThreadLibraryCalls",1,&driver)==1);
    strcpy((char *)g_mem+0xc0b080,"_THRASH_about@0");
    uint32_t procargs[]={driver,0xc0b080},fn=api("GetProcAddress",2,procargs);
    assert(fn);
    uint32_t about=call_guest(&cpu,fn,0,NULL);
    assert(MR32(about)==0x44334437 && MR32(about+4)==208 && MR32(about+8)==0x6b);
    assert(MR32(about+0x44)==2);
    uint32_t modes=MR32(about+0x40);
    assert(MR32(modes+40)==640 && MR32(modes+44)==480 && MR32(modes+48)==16);
    /* Exercise the original front end's range: it omits the last driver record. */
    unsigned hd=0,uhd=0;
    for(unsigned i=1;i<MR32(about+0x3c);i++){
        uint32_t p=modes+i*40;
        if(MR32(p)==1920&&MR32(p+4)==1080&&MR32(p+8)==32)hd=i;
        if(MR32(p)==3840&&MR32(p+4)==2160&&MR32(p+8)==32)uhd=i;
    }
    assert(hd && uhd);
    strcpy((char *)g_mem+0xc0b080,"_THRASH_setvideomode@12");
    uint32_t modeproc=api("GetProcAddress",2,procargs),modeargs[]={1,0,1};
    assert(call_guest(&cpu,modeproc,3,modeargs)==1);
    uint64_t mode_live_before,mode_live_after;heap_totals(&mode_live_before,NULL,NULL,NULL);
    for(unsigned i=0;i<3;i++){
        modeargs[0]=uhd;assert(call_guest(&cpu,modeproc,3,modeargs)==1);
        modeargs[0]=1;assert(call_guest(&cpu,modeproc,3,modeargs)==1);
    }
    heap_totals(&mode_live_after,NULL,NULL,NULL);
    assert(mode_live_after==mode_live_before);
    strcpy((char *)g_mem+0xc0b080,"_THRASH_setstate@8");
    uint32_t stateproc=api("GetProcAddress",2,procargs),disabled_state[]={0,1};
    assert(call_guest(&cpu,stateproc,2,disabled_state)==0);
    disabled_state[0]=0x6c;assert(call_guest(&cpu,stateproc,2,disabled_state)==0);
    uint32_t packet=0xc0e000,verts=packet+64,idx=verts+128;
    memset(g_mem+packet,0,256);MR32(packet)=4;MR32(packet+4)=0x1c4;MR32(packet+8)=verts;MR16(packet+12)=3;
    RenderVertex triangle[3]={{.x=10,.y=10,.z=.5,.rhw=1,.diffuse=0xffff0000},
        {.x=10,.y=60,.z=.5,.rhw=1,.diffuse=0xffff0000},{.x=60,.y=10,.z=.5,.rhw=1,.diffuse=0xffff0000}};
    for(unsigned i=0;i<3;i++)memcpy(g_mem+verts+i*32,&triangle[i],32);
    uint32_t packetargs[]={2,0};assert(call_guest(&cpu,stateproc,2,packetargs)==1);
    packetargs[0]=0x1b3;packetargs[1]=packet;
    int clip[]={0,0,640,480};render_clear(0xff000000,1,0,clip);
    assert(call_guest(&cpu,stateproc,2,packetargs)==1);
    uint32_t pixel;assert(render_read(20,20,1,1,&pixel,0));assert((pixel&0xffffff)==0xff0000);
    MR32(packet+16)=idx;MR16(packet+20)=3;MR16(idx)=0;MR16(idx+2)=1;MR16(idx+4)=2;
    render_clear(0xff000000,1,0,clip);assert(call_guest(&cpu,stateproc,2,packetargs)==1);
    assert(render_read(20,20,1,1,&pixel,0));assert((pixel&0xffffff)==0xff0000);
    MR16(idx+4)=3;assert(call_guest(&cpu,stateproc,2,packetargs)==0);
    strcpy((char *)g_mem+0xc0b080,"_THRASH_not_an_export@0");
    assert(api("GetProcAddress",2,procargs)==0);
    char files[]="out/test-files-XXXXXX",assets[256],saves[256],path[512];
    assert(mkdtemp(files));snprintf(assets,sizeof assets,"%s/assets",files);snprintf(saves,sizeof saves,"%s/saves",files);
    assert(!mkdir(assets,0755)&&!mkdir(saves,0755));
    snprintf(path,sizeof path,"%s/Porsche.exe",assets);fileio_set_root(path);fileio_set_write_root(saves);fileio_set_readonly_root(1);
    snprintf(path,sizeof path,"%s/Profile.sav",assets);FILE *fixture=fopen(path,"wb");assert(fixture);assert(fwrite("original",1,8,fixture)==8);assert(!fclose(fixture));
    strcpy((char *)g_mem+0xc0c000,"C:\\NFSV\\profile.SAV");
    uint32_t openfile[]={0xc0c000,0xc0000000,0,0,3,0,0};
    uint32_t file=api("CreateFileA",7,openfile);assert(file!=0xffffffff);
    uint32_t mappingargs[]={file,0,0x08000002,0,0,0};
    uint32_t mapping=api("CreateFileMappingA",6,mappingargs);assert(mapping);
    uint32_t viewargs[]={mapping,4,0,0,0};uint32_t view=api("MapViewOfFile",5,viewargs);
    assert(view&&!(view&0xffff)&&!memcmp(g_mem+view,"original",8));
    assert(api("CloseHandle",1,&mapping)==1);
    assert(!memcmp(g_mem+view,"original",8));assert(api("UnmapViewOfFile",1,&view)==1);assert(!mem_valid(view,1));
    mappingargs[2]=4;mapping=api("CreateFileMappingA",6,mappingargs);assert(mapping);
    viewargs[0]=mapping;viewargs[1]=2;view=api("MapViewOfFile",5,viewargs);assert(view);
    viewargs[1]=4;uint32_t alias=api("MapViewOfFile",5,viewargs);assert(alias&&alias!=view);
    MR8(view)='X';assert(MR8(alias)=='X');
    assert(api("CloseHandle",1,&mapping)==1);assert(api("UnmapViewOfFile",1,&view)==1);
    assert(MR8(alias)=='X');assert(api("UnmapViewOfFile",1,&alias)==1);
    uint32_t missingview=0;assert(api("UnmapViewOfFile",1,&missingview)==0);assert(api("GetLastError",0,NULL)==487);
    memcpy(g_mem+0xc0c100,"changed!",8);uint32_t writefile[]={file,0xc0c100,8,0xc0c200,0};
    assert(api("WriteFile",5,writefile)==1&&MR32(0xc0c200)==8);assert(api("CloseHandle",1,&file)==1);
    fixture=fopen(path,"rb");assert(fixture);char content[9]={0};assert(fread(content,1,8,fixture)==8);fclose(fixture);assert(!strcmp(content,"original"));
    openfile[4]=1;assert(api("CreateFileA",7,openfile)==0xffffffff);assert(api("GetLastError",0,NULL)==80);
    openfile[4]=3;file=api("CreateFileA",7,openfile);assert(file!=0xffffffff);
    uint32_t readfile[]={file,0xc0c100,8,0xc0c200,0};assert(api("ReadFile",5,readfile)==1&&MR32(0xc0c200)==8);assert(!memcmp(g_mem+0xc0c100,"changed!",8));api("CloseHandle",1,&file);
    openfile[4]=5;file=api("CreateFileA",7,openfile);assert(file!=0xffffffff);api("CloseHandle",1,&file);
    snprintf(path,sizeof path,"%s/profile.SAV",saves);struct stat st;assert(!stat(path,&st)&&st.st_size==0);unlink(path);
    strcpy((char *)g_mem+0xc0c300,"C:\\NFSV\\copy.sav");uint32_t copyargs[]={0xc0c000,0xc0c300,0};
    snprintf(path,sizeof path,"%s/copy.sav",saves);fixture=fopen(path,"wb");assert(fixture);assert(fwrite("preserve",1,8,fixture)==8);assert(!fclose(fixture));
    test_fail_copy_write=1;assert(api("CopyFileA",3,copyargs)==0);assert(api("GetLastError",0,NULL)==112);
    fixture=fopen(path,"rb");assert(fixture);assert(fread(content,1,8,fixture)==8&&!memcmp(content,"preserve",8));fclose(fixture);
    test_fail_copy_close=1;assert(api("CopyFileA",3,copyargs)==0);assert(api("GetLastError",0,NULL)==112);
    fixture=fopen(path,"rb");assert(fixture);assert(fread(content,1,8,fixture)==8&&!memcmp(content,"preserve",8));fclose(fixture);
    copyargs[2]=1;assert(api("CopyFileA",3,copyargs)==0);assert(api("GetLastError",0,NULL)==80);unlink(path);
    test_fail_copy_write=1;assert(api("CopyFileA",3,copyargs)==0);assert(stat(path,&st)==-1);
    test_fail_copy_write=1;openfile[4]=3;assert(api("CreateFileA",7,openfile)==0xffffffff);assert(api("GetLastError",0,NULL)==112);
    snprintf(path,sizeof path,"%s/profile.SAV",saves);assert(stat(path,&st)==-1);
    file=api("CreateFileA",7,openfile);assert(file!=0xffffffff);api("CloseHandle",1,&file);assert(!stat(path,&st)&&st.st_size==8);unlink(path);
    /* Deleting a bundled profile must hide it without modifying the app. */
    uint32_t profile=0xc0c000;
    assert(api("DeleteFileA",1,&profile)==1);
    assert(attributes(profile)==0xffffffff);
    openfile[1]=0x80000000;openfile[4]=3;
    assert(api("CreateFileA",7,openfile)==0xffffffff);
    assert(api("DeleteFileA",1,&profile)==0&&api("GetLastError",0,NULL)==2);
    snprintf(path,sizeof path,"%s/Profile.sav",assets);assert(!stat(path,&st)&&st.st_size==8);
    strcpy((char *)g_mem+0xc0c400,"C:\\NFSV\\*.sav");uint32_t scan[]={0xc0c400,0xc0c500};
    assert(api("FindFirstFileA",2,scan)==0xffffffff);
    /* The deletion persists when the overlay is reopened, and a new file can shadow it. */
    fileio_set_write_root(saves);
    assert(attributes(profile)==0xffffffff);
    openfile[1]=0xc0000000;openfile[4]=1;
    file=api("CreateFileA",7,openfile);assert(file!=0xffffffff);api("CloseHandle",1,&file);
    assert(attributes(profile)==0x80);
    assert(api("DeleteFileA",1,&profile)==1);
    assert(attributes(profile)==0xffffffff);
    /* Profile creation copies a default HUD, then deletes that default. */
    copyargs[0]=profile;assert(api("CopyFileA",3,copyargs)==0);
    snprintf(path,sizeof path,"%s/Defaults",assets);assert(!mkdir(path,0755));
    snprintf(path,sizeof path,"%s/Defaults/Default.hud",assets);fixture=fopen(path,"wb");assert(fixture);
    assert(fwrite("hud",1,3,fixture)==3&&!fclose(fixture));
    strcpy((char *)g_mem+0xc0c000,"C:\\NFSV\\Defaults\\DEFAULT.HUD");copyargs[2]=0;
    assert(api("CopyFileA",3,copyargs)==1);
    assert(api("DeleteFileA",1,&profile)==1);
    assert(attributes(profile)==0xffffffff);
    strcpy((char *)g_mem+0xc0c800,"C:\\NFSV\\Defaults");assert(attributes(0xc0c800)==0x10);
    assert(attributes(copyargs[1])==0x80);
    snprintf(path,sizeof path,"%s/copy.sav",saves);unlink(path);
    snprintf(path,sizeof path,"%s/Defaults/Default.hud",assets);unlink(path);
    snprintf(path,sizeof path,"%s/Defaults",assets);rmdir(path);
    snprintf(path,sizeof path,"%s/.nfsv-deleted/defaults/default.hud",saves);unlink(path);
    snprintf(path,sizeof path,"%s/.nfsv-deleted/defaults",saves);rmdir(path);
    snprintf(path,sizeof path,"%s/.nfsv-deleted/profile.sav",saves);unlink(path);
    snprintf(path,sizeof path,"%s/.nfsv-deleted",saves);rmdir(path);
    snprintf(path,sizeof path,"%s/Profile.sav",assets);unlink(path);rmdir(assets);rmdir(saves);rmdir(files);
    pthread_t worker;assert(!pthread_create(&worker,NULL,message_worker,NULL));
    uint32_t getmessage[]={0xc0d000,0,0,0};
    assert(api("GetMessageA",4,getmessage)==1&&MR32(0xc0d004)==0x400&&MR32(0xc0d008)==123);
    guest_unlock();assert(!pthread_join(worker,NULL));guest_lock(&cpu);
    win32_post_message(0x12,7,0);assert(api("GetMessageA",4,getmessage)==0&&MR32(0xc0d008)==7);
    assert(!pthread_create(&worker,NULL,scheduled_worker,NULL));
    for(unsigned i=0;i<1000000&&!atomic_load(&scheduled);i++)watch_check(0x401000);
    assert(atomic_load(&scheduled));
#ifdef GAME_KEYBOARD_BUFFER
    memset(g_mem+GAME_KEYBOARD_BUFFER,1,128);win32_post_message(8,0,0);
    for(unsigned i=0;i<128;i++)assert(!MR8(GAME_KEYBOARD_BUFFER+i));
#endif
    guest_unlock();assert(!pthread_join(worker,NULL));
    unlink(registry);
    puts("platform: callbacks, stdcall cleanup and extended waits passed");
    return 0;
}
