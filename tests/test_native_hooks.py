import unittest
import subprocess
import tempfile
from pathlib import Path

from tools.native_hooks import NATIVE_HOOKS,wrap_native


class NativeHookTests(unittest.TestCase):
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
