#ifndef NFSV_HUD_H
#define NFSV_HUD_H
#include "runtime.h"
#include "render.h"
void hud_initialize(CPU *,guest_fn_t);
void hud_anchor(CPU *,guest_fn_t);
void hud_draw(CPU *,guest_fn_t);
void hud_physical_draw(CPU *,guest_fn_t);
void hud_vertices(RenderVertex *,unsigned);
void hud_clip(int [4]);
#endif
