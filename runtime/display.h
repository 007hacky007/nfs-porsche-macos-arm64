#ifndef NFSV_DISPLAY_H
#define NFSV_DISPLAY_H
#include <stdint.h>
enum {DISPLAY_MODE_COUNT=16};
extern const unsigned display_mode_sizes[DISPLAY_MODE_COUNT][2];
int display_resolution(const char *,unsigned *,unsigned *);
uint64_t display_frame_deadline(uint64_t,uint64_t,unsigned);
typedef struct {double x,y,w,h;} DisplayRect;
DisplayRect display_fit(unsigned,unsigned,double,double);
void display_mouse(unsigned,unsigned,double,double,double,double,int *,int *);
#endif
