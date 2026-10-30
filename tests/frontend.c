#include "frontend.h"
#include <assert.h>
#include <stdio.h>

static uint32_t text_order;
static void enqueue_text(CPU *cpu){
    if(cpu->eax)text_order=MR32(0x65b970)++;
    cpu->eax=42;
}
static uint32_t enqueue_background(void){return ++MR32(0x65b970);}
int main(void){
    mem_init();mem_commit(0x658000,0x4000);
    CPU cpu={.eax=1,.ebx=91,.esp=0x12345678};
    uint32_t background=enqueue_background();
    frontend_text(&cpu,enqueue_text);
    assert(text_order>background); /* A tied resource address can paint the background over this glyph. */
    assert(MR32(0x65b970)>text_order); /* Opaque images reuse the current counter after text. */
    assert(MR32(0x65b970)==3&&cpu.eax==42&&cpu.ebx==91&&cpu.esp==0x12345678);
    uint32_t previous=text_order;cpu.eax=1;frontend_text(&cpu,enqueue_text);
    assert(text_order>previous&&MR32(0x65b970)==5);
    background=enqueue_background();assert(background>text_order);
    cpu.eax=1;frontend_text(&cpu,enqueue_text);assert(text_order>background&&MR32(0x65b970)==8);
    cpu.eax=0;frontend_text(&cpu,enqueue_text);assert(MR32(0x65b970)==8&&cpu.eax==42);
    puts("frontend: text stays after its background, including interleaved and transparent draws");
}
