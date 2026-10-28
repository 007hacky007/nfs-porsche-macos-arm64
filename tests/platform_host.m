/* Keep the real Metal backend, but don't create a visible window in platform tests. */
#define host_open_window unused_host_open_window
#include "../runtime/host.m"
#undef host_open_window
void host_open_window(unsigned w,unsigned h){(void)w;(void)h;}
