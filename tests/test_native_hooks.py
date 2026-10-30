import unittest
import subprocess
import tempfile
from pathlib import Path

from tools.native_hooks import NATIVE_HOOKS,wrap_native


class NativeHookTests(unittest.TestCase):
    def test_countdown_and_replay_keep_physical_coordinates(self):
        # These widgets lay themselves out from the physical display size.
        source=['#include "hud.h"\n#include <assert.h>\n#include <stdlib.h>\n']
        for address in (0x4184f0,0x42d1e0):
            source.append(wrap_native(address,f'''void sub_{address:08x}(CPU *restrict c) {{
                RenderVertex v={{.x=1919.5f,.y=2129.5f}};
                hud_vertices(&v,1);assert(v.x==1919.5f&&v.y==2129.5f);
                int clip[]={{1800,2000,2100,2160}};hud_clip(clip);
                assert(clip[0]==1800&&clip[3]==2160);
            }}'''))
        source.append('''
uint32_t call_guest(CPU *c,uint32_t fn,int count,const uint32_t *args){return 0;}
void initialize(CPU *c){}
void draw(CPU *c){sub_004184f0(c);sub_0042d1e0(c);}
int main(void){
    mem_init();mem_commit(0x10000,0x4000);CPU c={.esp=0x10000};
    MR32(c.esp+12)=3840;MR32(c.esp+16)=2160;
    const char *settings[]={"100","75","25"};
    for(unsigned i=0;i<3;i++){
        setenv("NFSV_HUD_SCALE",settings[i],1);hud_initialize(&c,initialize);hud_draw(&c,draw);
    }
    MR32(c.esp+12)=640;MR32(c.esp+16)=480;
    hud_initialize(&c,initialize);hud_draw(&c,draw);return 0;
}
''')
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'physical.c';path.write_text('\n'.join(source))
            binary=Path(tmp)/'physical'
            subprocess.run(['clang','-O1','-DNFSV_NO_IMAGE','-Iruntime',str(path),
                            'runtime/hud.c','runtime/memory.c','-o',str(binary)],check=True)
            subprocess.run([str(binary)],check=True)

    def test_hud_wrappers_run_hooks_for_direct_and_indirect_calls(self):
        source=['#include "cpu.h"\n#include <assert.h>\n']
        calls=[]
        for address,hook in NATIVE_HOOKS.items():
            if not hook.startswith('hud_'):
                continue
            name=f'sub_{address:08x}'
            body=(f'void {name}(CPU *restrict c) {{'
                  ' if(c->ecx){c->eax+=100;return;} c->eax=c->eax*3+7; }')
            source.append(wrap_native(address,body))
            calls.append(f'check({name});')
            calls.append(f'c=(CPU){{.eax=10}}; {name}(&c); assert(c.eax==45&&c.ebx==2);')
        source.append('''
void hud_initialize(CPU *c,void (*original)(CPU *)){
    c->eax++;c->ebx++;original(c);c->eax+=5;c->ebx++;
}
void hud_draw(CPU *c,void (*original)(CPU *)){hud_initialize(c,original);}
void hud_anchor(CPU *c,void (*original)(CPU *)){hud_initialize(c,original);}
void hud_physical_draw(CPU *c,void (*original)(CPU *)){hud_initialize(c,original);}
void check(void (*fn)(CPU *)){
    CPU c={.eax=10};fn(&c);assert(c.eax==45&&c.ebx==2);
    c=(CPU){.eax=10,.ecx=1};fn(&c);assert(c.eax==116&&c.ebx==2);
}
''')
        source.append('int main(void){CPU c;'+''.join(calls)+'return 0;}')
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'hooks.c';path.write_text('\n'.join(source))
            binary=Path(tmp)/'hooks'
            subprocess.run(['clang','-O1','-Iruntime',str(path),'-o',str(binary)],check=True)
            subprocess.run([str(binary)],check=True)

    def test_world_and_menu_functions_are_unmodified(self):
        body='void sub_00402000(CPU *restrict c) { POP32(c->eip); }'
        self.assertEqual(wrap_native(0x402000,body),body)
