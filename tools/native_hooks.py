"""Keep native runtime hooks outside the translated game function bodies."""

NATIVE_HOOKS={0x41e170:'hud_initialize',0x41e480:'hud_anchor',0x425950:'hud_draw',0x4da350:'frontend_text'}
# HBillBoard-derived popups use physical screen coordinates via layout method 0x41adb0.
NATIVE_HOOKS.update(dict.fromkeys((0x41a7a0,0x41bfc0,0x421b20,0x4283d0,0x428e00,0x42a650,
                                 0x42c080,0x42e2a0,0x431a80,0x4339c0,0x4376d0),'hud_physical_draw'))
# The map camera already projects its geometry into the scaled physical viewport.
NATIVE_HOOKS.update(dict.fromkeys((0x432b60,0x433690),'hud_physical_draw'))
# H321Go and HReplay lay out from the physical display globals, not the HUD dimensions.
NATIVE_HOOKS.update(dict.fromkeys((0x4184f0,0x42d1e0),'hud_physical_draw'))


def wrap_native(address,code):
    hook=NATIVE_HOOKS.get(address)
    if not hook:
        return code
    name=f'sub_{address:08x}'
    code=code.replace(f'void {name}(CPU *restrict c)',f'void {name}_orig(CPU *restrict c)',1)
    return (code+f'\nextern void {hook}(CPU *,void (*)(CPU *));\n'
            f'void {name}(CPU *restrict c) {{ {hook}(c,{name}_orig); }}\n')
