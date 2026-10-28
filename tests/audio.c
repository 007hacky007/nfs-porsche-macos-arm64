#include "cpu.h"
#include "audio.h"
#include <assert.h>
#include <string.h>
int main(void){
    mem_init();mem_commit(0x10000,0x4000);
    for(unsigned i=0;i<64;i++)MR16(0x10000+2*i)=10000;
    int sound=audio_create(0x10000,128,44100,1,16);
    assert(sound>0);
    audio_play(sound,1);
    int16_t output[16];audio_mix(output,8);
    for(unsigned i=0;i<16;i++)assert(output[i]==10000);
    uint32_t play,write;audio_cursors(sound,&play,&write);assert(play==16);
    audio_set_position(sound,4);audio_cursors(sound,&play,&write);assert(play==4);
    audio_set_pan(sound,10000);audio_mix(output,8);
    for(unsigned i=0;i<8;i++){assert(output[2*i]==0);assert(output[2*i+1]==10000);}
    audio_set_volume(sound,-10000);audio_mix(output,8);
    for(unsigned i=0;i<16;i++)assert(output[i]==0);
    audio_stop(sound);assert(!audio_playing(sound));
    audio_destroy(sound);
    memset(g_mem+0x10000,128,64);
    sound=audio_create(0x10000,64,44100,1,8);audio_play(sound,0);audio_mix(output,8);
    for(unsigned i=0;i<16;i++)assert(output[i]==0);
    audio_destroy(sound);
    return 0;
}
