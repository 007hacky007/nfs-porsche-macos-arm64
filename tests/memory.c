#include "cpu.h"
#include <assert.h>
int mem_valid(uint32_t, uint64_t);
void mem_release(uint32_t, uint32_t, int);
int main(void){
    mem_init();
    assert(!mem_valid(0x10000, 4));
    mem_commit(0x10000, 0x8000);
    assert(mem_valid(0x10000, 0x8000));
    assert(!mem_valid(0x17fff, 2));
    assert(!mem_valid(0xffffffff, 2));
    MR32(0x10000) = 0x12345678;
    assert(MR32(0x10000) == 0x12345678);
    mem_release(0x10000, 0x8000, 1);
    assert(MR32(0x10000) == 0);
    mem_release(0x10000, 0x8000, 0);
    assert(!mem_valid(0x10000, 4));
    return 0;
}
