/* DirectInput force feedback on the virtual game pad, played as rumble.

   Porsche.exe creates four effects on a force-feedback device when a race
   starts (0x411d20) and drives them from its car model, each with its own
   switch and strength on the controls screen's force feedback tab:
     constant force  collisions and hard landings: a jolt as long and as
                     strong as the impact (0x412230, 0x412cf0)
     square wave     the road surface, by speed band and surface (0x4128b0)
     sine wave       the engine, following the revs (0x4127a0)
     spring          steering self-centring (0x412630)
   A pad has two motors and no steering motor, so the running effects are
   mixed every frame the game polls the pad: forces (constant, ramp) drive
   the heavy low-frequency motor, vibrations (periodic) the light one, and
   conditions (spring, damper, inertia, friction) have nothing to vibrate.
   The game's slider values (stick volume as the device gain, each effect's
   own gain) scale the motors.

     NFSV_PAD_RUMBLE=0  no force feedback (the launcher's vibration switch)
     NFSV_FF_LOG=1      log effect changes and motor levels */
#include "runtime.h"
#include "gamepad.h"
#include "joystick.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

uint32_t com_object(unsigned, unsigned);

#define DIERR_INVALIDPARAM 0x80070057u
#define DIERR_UNSUPPORTED 0x80004001u
#define DIERR_DEVICENOTREG 0x80040154u
#define DIERR_NOTINITIALIZED 0x80070015u
#define INFINITE_TIME 0xffffffffu

enum { CONSTANT, RAMP, PERIODIC, CONDITION, CUSTOM };
enum { MAX_EFFECTS = 32, EFFECT_FAMILY = 3 };

typedef struct {
    int used, kind, playing;
    uint32_t object, guid;              /* the guest COM object and the effect's GUID Data1 */
    uint32_t duration, gain, iterations;
    int has_envelope;
    uint32_t attack_level, attack_time, fade_level, fade_time;
    int32_t level[2];                   /* constant: magnitude; ramp: start, end; periodic: magnitude, offset */
    uint32_t period;
    uint64_t start;
} Effect;

static Effect effects[MAX_EFFECTS];
static uint32_t device_gain = 10000, autocenter = 1;
static int actuators_on = 1, paused, logging = -1;
static float shown_strong = -1, shown_weak = -1;

static uint64_t now_us(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000u + (uint64_t)ts.tv_nsec / 1000u;
}
static int log_enabled(void){
    if (logging < 0){ const char *v = getenv("NFSV_FF_LOG"); logging = v && *v && strcmp(v, "0"); }
    return logging;
}

int force_enabled(void){ return gamepad_enabled() && gamepad_rumble_enabled(); }

void force_reset(void){
    for (unsigned i = 0; i < MAX_EFFECTS; i++) effects[i].playing = 0;
    device_gain = 10000; autocenter = 1; actuators_on = 1; paused = 0;
}

/* DIPROP_FFGAIN (7), DIPROP_FFLOAD (8) and DIPROP_AUTOCENTER (9); value
   points at the DWORD after the property header. */
uint32_t force_property(int set, uint32_t property, uint32_t value){
    if (!force_enabled() || property < 7 || property > 9) return DIERR_UNSUPPORTED;
    if (property == 8){ if (set) return DIERR_UNSUPPORTED; MR32(value) = 0; return 0; }
    uint32_t *target = property == 7 ? &device_gain : &autocenter;
    if (!set){ MR32(value) = *target; return 0; }
    uint32_t v = MR32(value);
    if (property == 7 ? v > 10000 : v > 1) return DIERR_INVALIDPARAM;
    *target = v;
    return 0;
}

/* Effect GUIDs are {13541C2x-8E33-11D0-9AD0-00A0C9A06E35}. */
static int effect_kind(uint32_t p){
    static const uint8_t tail[12] = {0x33, 0x8e, 0xd0, 0x11, 0x9a, 0xd0, 0x00, 0xa0, 0xc9, 0xa0, 0x6e, 0x35};
    if (!mem_valid(p, 16) || memcmp(guest_ptr(p + 4, 12), tail, 12)) return -1;
    uint32_t first = MR32(p);
    if (first == 0x13541c20) return CONSTANT;
    if (first == 0x13541c21) return RAMP;
    if (first >= 0x13541c22 && first <= 0x13541c26) return PERIODIC;
    if (first >= 0x13541c27 && first <= 0x13541c2a) return CONDITION;
    if (first == 0x13541c2b) return CUSTOM;
    return -1;
}
static Effect *effect_of(uint32_t self){
    uint32_t index = MR32(self + 32);
    return index && index <= MAX_EFFECTS && effects[index - 1].used ? &effects[index - 1] : NULL;
}

static void start(Effect *e, uint32_t iterations){
    e->playing = 1; e->iterations = iterations ? iterations : 1; e->start = now_us();
}

/* DIEFFECT (DX5: 52 bytes, DX6: 56) with the DIEP_* flags. */
static uint32_t set_parameters(Effect *e, uint32_t p, uint32_t flags){
    if (!mem_valid(p, 52)) return DIERR_INVALIDPARAM;
    uint32_t size = MR32(p);
    if (size != 52 && size != 56) return DIERR_INVALIDPARAM;
    if (flags & 0x01) e->duration = MR32(p + 8);
    if (flags & 0x04){ uint32_t gain = MR32(p + 16); if (gain > 10000) return DIERR_INVALIDPARAM; e->gain = gain; }
    if (flags & 0x80){
        uint32_t envelope = MR32(p + 40);
        e->has_envelope = envelope != 0;
        if (envelope){
            if (!mem_valid(envelope, 20) || MR32(envelope) != 20) return DIERR_INVALIDPARAM;
            e->attack_level = MR32(envelope + 4); e->attack_time = MR32(envelope + 8);
            e->fade_level = MR32(envelope + 12); e->fade_time = MR32(envelope + 16);
        }
    }
    if (flags & 0x100){
        uint32_t bytes = MR32(p + 44), params = MR32(p + 48);
        if (bytes && !mem_valid(params, bytes)) return DIERR_INVALIDPARAM;
        if (e->kind == CONSTANT && bytes >= 4) e->level[0] = (int32_t)MR32(params);
        else if (e->kind == RAMP && bytes >= 8){ e->level[0] = (int32_t)MR32(params); e->level[1] = (int32_t)MR32(params + 4); }
        else if (e->kind == PERIODIC && bytes >= 16){
            e->level[0] = (int32_t)MR32(params); e->level[1] = (int32_t)MR32(params + 4); e->period = MR32(params + 12);
        }
    }
    if (log_enabled())
        fprintf(stderr, "force effect %08x set flags=%08x duration=%u gain=%u levels=%d,%d period=%u\n",
                e->guid, flags, e->duration, e->gain, e->level[0], e->level[1], e->period);
    if (flags & 0x20000000) start(e, 1);
    return 0;
}

uint32_t force_create_effect(uint32_t guid, uint32_t parameters, uint32_t out){
    if (mem_valid(out, 4)) MR32(out) = 0;
    if (!force_enabled()) return DIERR_UNSUPPORTED;
    int kind = effect_kind(guid);
    if (kind < 0) return DIERR_DEVICENOTREG;
    if (!mem_valid(out, 4)) return DIERR_INVALIDPARAM;
    unsigned i = 0;
    while (i < MAX_EFFECTS && effects[i].used) i++;
    if (i == MAX_EFFECTS) return 0x8007000eu;   /* E_OUTOFMEMORY */
    Effect *e = &effects[i];
    memset(e, 0, sizeof *e);
    e->used = 1; e->kind = kind; e->guid = MR32(guid);
    e->duration = INFINITE_TIME; e->gain = 10000;
    e->object = com_object(EFFECT_FAMILY, 0);
    MR32(e->object + 32) = i + 1;
    if (parameters){
        uint32_t r = set_parameters(e, parameters, 0x1ff);
        if (r){ e->used = 0; return r; }
    }
    MR32(out) = e->object;
    return 0;
}

void force_release(uint32_t self){
    Effect *e = effect_of(self);
    if (e) e->used = 0;
}

/* SendForceFeedbackCommand: DISFFC_RESET 1, STOPALL 2, PAUSE 4, CONTINUE 8,
   SETACTUATORSON 0x10, SETACTUATORSOFF 0x20. */
uint32_t force_command(uint32_t flags){
    if (!force_enabled()) return DIERR_UNSUPPORTED;
    if (flags & 3) for (unsigned i = 0; i < MAX_EFFECTS; i++) effects[i].playing = 0;
    if (flags & 1) paused = 0, actuators_on = 1;
    if (flags & 4) paused = 1;
    if (flags & 8) paused = 0;
    if (flags & 0x10) actuators_on = 1;
    if (flags & 0x20) actuators_on = 0;
    if (log_enabled()) fprintf(stderr, "force command %02x\n", flags);
    return 0;
}

uint32_t force_state(uint32_t out){
    if (!force_enabled()) return DIERR_UNSUPPORTED;
    if (!mem_valid(out, 4)) return DIERR_INVALIDPARAM;
    int playing = 0;
    for (unsigned i = 0; i < MAX_EFFECTS; i++) playing |= effects[i].used && effects[i].playing;
    /* DIGFFS_PAUSED 4, STOPPED 2, ACTUATORSON 0x10, ACTUATORSOFF 0x20, POWERON 0x40 */
    MR32(out) = (paused ? 4 : 0) | (playing ? 0 : 2) | (actuators_on ? 0x10 : 0x20) | 0x40;
    return 0;
}

/* IDirectInputEffect methods after IUnknown. */
int force_effect_method(CPU *c, uint32_t self, unsigned slot, uint32_t *result, uint32_t *nargs){
    /* Arguments are read per method: one-argument methods end at the stack top. */
#define a1 MR32(c->esp + 4)
#define a2 MR32(c->esp + 8)
    Effect *e = effect_of(self);
    *result = 0;
    switch (slot){
    case 3: *nargs = 4; break;                                   /* Initialize */
    case 4: *nargs = 2;                                          /* GetEffectGuid */
        if (!e || !mem_valid(a1, 16)){ *result = DIERR_INVALIDPARAM; break; }
        MR32(a1) = e->guid; MR16(a1 + 4) = 0x8e33; MR16(a1 + 6) = 0x11d0;
        memcpy(guest_ptr(a1 + 8, 8), "\x9a\xd0\x00\xa0\xc9\xa0\x6e\x35", 8);
        break;
    case 5: *nargs = 3;                                          /* GetParameters: the scalar fields */
        if (!e || !mem_valid(a1, 52)){ *result = DIERR_INVALIDPARAM; break; }
        if (a2 & 0x01) MR32(a1 + 8) = e->duration;
        if (a2 & 0x04) MR32(a1 + 16) = e->gain;
        break;
    case 6: *nargs = 3; *result = e ? set_parameters(e, a1, a2) : DIERR_NOTINITIALIZED; break;   /* SetParameters */
    case 7: *nargs = 3;                                          /* Start */
        if (!e){ *result = DIERR_NOTINITIALIZED; break; }
        start(e, a1);
        if (log_enabled()) fprintf(stderr, "force effect %08x start\n", e->guid);
        break;
    case 8: case 11: *nargs = 1;                                 /* Stop, Unload */
        if (e){ e->playing = 0; if (log_enabled()) fprintf(stderr, "force effect %08x stop\n", e->guid); }
        break;
    case 9: *nargs = 2;                                          /* GetEffectStatus: DIEGES_PLAYING */
        if (!mem_valid(a1, 4)){ *result = DIERR_INVALIDPARAM; break; }
        force_update();
        MR32(a1) = e && e->playing ? 1 : 0;
        break;
    case 10: *nargs = 1; break;                                  /* Download */
    case 12: *nargs = 2; *result = DIERR_UNSUPPORTED; break;     /* Escape */
    default: return 0;
    }
    return 1;
#undef a1
#undef a2
}

/* The effect's strength 0..1 at time t (us) since it started, or -1 once
   it has finished. */
static float strength(const Effect *e, uint64_t t){
    uint64_t local = t;
    if (e->duration != INFINITE_TIME){
        if (!e->duration) return -1;
        if (e->iterations != INFINITE_TIME && t >= (uint64_t)e->duration * e->iterations) return -1;
        local = t % e->duration;
    }
    float level;
    if (e->kind == CONSTANT) level = abs(e->level[0]) / 10000.f;
    else if (e->kind == RAMP){
        float f = e->duration != INFINITE_TIME ? (float)local / e->duration : 0.f;
        level = abs((int)(e->level[0] + (e->level[1] - e->level[0]) * f)) / 10000.f;
    }
    else if (e->kind == PERIODIC){
        level = (abs(e->level[0]) + abs(e->level[1])) / 10000.f;
        /* Slow waves (bumps) pulse; faster ones are a steady buzz at the
           rate the motors can follow. */
        if (e->period >= 150000 && (local % e->period) >= e->period / 2) level *= 0.35f;
    }
    else return 0.f;
    if (e->has_envelope){
        float peak = level;
        if (local < e->attack_time && e->attack_time)
            level = e->attack_level / 10000.f + (peak - e->attack_level / 10000.f) * local / e->attack_time;
        if (e->duration != INFINITE_TIME && e->fade_time && local + e->fade_time > e->duration){
            float f = (float)(e->duration - local) / e->fade_time;
            level = e->fade_level / 10000.f + (peak - e->fade_level / 10000.f) * f;
        }
    }
    level *= e->gain / 10000.f * device_gain / 10000.f;
    return level < 0.f ? 0.f : level > 1.f ? 1.f : level;
}

void force_update(void){
    if (!force_enabled()) return;
    float strong = 0.f, weak = 0.f;
    uint64_t now = now_us();
    for (unsigned i = 0; i < MAX_EFFECTS; i++){
        Effect *e = &effects[i];
        if (!e->used || !e->playing) continue;
        float level = strength(e, now - e->start);
        if (level < 0.f){ e->playing = 0; continue; }
        if (e->kind == PERIODIC){ if (level > weak) weak = level; }
        else if (level > strong) strong = level;
    }
    if (paused || !actuators_on) strong = weak = 0.f;
    /* The game's defaults (50% stick volume, 50% collision) give a full
       crash 0.25, which a pad's heavy motor barely turns at; a square-root
       curve makes it about half while 100% still reaches full. The engine
       and road vibrations stay linear so the idle buzz stays faint. */
    strong = sqrtf(strong);
    if (log_enabled() && (fabsf(strong - shown_strong) > 0.05f || fabsf(weak - shown_weak) > 0.05f)){
        fprintf(stderr, "force motors strong=%.2f weak=%.2f\n", strong, weak);
        shown_strong = strong; shown_weak = weak;
    }
    gamepad_rumble(strong, weak);
}
