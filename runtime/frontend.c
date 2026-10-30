#include "frontend.h"

void frontend_text(CPU *cpu,guest_fn_t original){
    /* Give text a separate order so the background cannot paint over its first glyph. */
    uint32_t reserved=++MR32(0x65b970);
    original(cpu);
    if(MR32(0x65b970)==reserved)MR32(0x65b970)--;
}
