/* Inject output failures at the stdio boundary; normal calls still use libc. */
#include <stdio.h>
#include <dlfcn.h>
#include <errno.h>
int test_fail_copy_write,test_fail_copy_close;
size_t fwrite(const void *data,size_t size,size_t count,FILE *file){
    if(test_fail_copy_write){test_fail_copy_write=0;errno=ENOSPC;return 0;}
    static size_t (*real_write)(const void *,size_t,size_t,FILE *);
    if(!real_write)real_write=dlsym(RTLD_NEXT,"fwrite");
    return real_write(data,size,count,file);
}
int fclose(FILE *file){
    static int (*real_close)(FILE *);
    if(!real_close)real_close=dlsym(RTLD_NEXT,"fclose");
    int result=real_close(file);
    if(test_fail_copy_close){test_fail_copy_close=0;errno=ENOSPC;return EOF;}
    return result;
}
