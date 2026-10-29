#ifndef NFSV_LAUNCH_SETTINGS_H
#define NFSV_LAUNCH_SETTINGS_H
#include <stdint.h>
void launch_settings_init(void);
int launch_resolution_override(uint32_t,const char *);
#endif
