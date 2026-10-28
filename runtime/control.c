/* Optional local FIFO for repeatable input tests, never opened by default. */
#include "input.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
static int fd=-1;
static char line[256];
static unsigned used;
void control_init(void){
 const char *path=getenv("NFSV_CONTROL");if(!path||!*path)return;
 fd=open(path,O_RDWR|O_NONBLOCK);struct stat st;
 if(fd<0||fstat(fd,&st)||!S_ISFIFO(st.st_mode)){if(fd>=0)close(fd);fd=-1;fputs("input control requires a local FIFO\n",stderr);exit(1);}
}
static void command(const char *s){
 int a,b,c,d,e;char extra;
 if(!strcmp(s,"capture")){void render_request_capture(void);render_request_capture();}
 else if(!strcmp(s,"fullscreen")){void host_toggle_fullscreen(void);host_toggle_fullscreen();}
 else if(!strcmp(s,"close")){void host_close_window(void);host_close_window();}
 else if(!strcmp(s,"windowinfo")){void host_window_info(void);host_window_info();}
 else if(sscanf(s,"key %d %d %d %c",&a,&b,&c,&extra)==3 && a>0&&a<256&&b>=0&&b<256&&(c==0||c==1))input_key(a,b,c);
 else if(sscanf(s,"text %d %c",&a,&extra)==1&&a>0&&a<65536)input_text(a);
 else if(sscanf(s,"mouse %d %d %d %d %d %c",&a,&b,&c,&d,&e,&extra)==5&&c>=-1&&c<4&&(d==0||d==1))input_mouse(a,b,c,d,e);
 else fprintf(stderr,"invalid input control command\n");
}
void control_pump(void){
 if(fd<0)return;char bytes[512];ssize_t n;
 while((n=read(fd,bytes,sizeof bytes))>0)for(ssize_t i=0;i<n;i++){
  if(bytes[i]=='\n'){line[used]=0;command(line);used=0;}
  else if(used<sizeof line-1)line[used++]=bytes[i];
  else{used=0;fputs("input control line too long\n",stderr);}
 }
}
