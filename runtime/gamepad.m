/* GameController.framework input for the virtual game pad.

   Connect and disconnect notifications arrive on the main thread, which runs
   the Cocoa event loop. Value changes run on a private serial queue and copy
   the controller state under a lock. The original game's thread reads it
   through gamepad_read() whenever it polls its DirectInput joystick.

   While another app is active the pad reads neutral, like the keyboard,
   so a held trigger or stick cannot stay applied after switching apps.

     NFSV_PAD=0                    no game controller device at all
     NFSV_PAD_DEADZONE=<f>         radial stick dead zone (default 0.08)
     NFSV_PAD_TRIGGER_DEADZONE=<f> trigger dead zone (default 0.02)
     NFSV_PAD_LOG=1                log controllers connecting and disconnecting */
#import <Cocoa/Cocoa.h>
#import <GameController/GameController.h>
#include <os/lock.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "gamepad.h"

static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
static PadState real_pad, synthetic_pad;
static int app_active = 1, logging;
static unsigned generation;           /* bumped under the lock when the active controller changes */
static GCController *active;          /* main thread only */
static NSMutableArray *order;         /* connected controllers, oldest first */
static dispatch_queue_t queue;

static int env_flag(const char *name, int fallback){
    const char *value = getenv(name);
    if (!value || !*value) return fallback;
    if ((*value >= '0' && *value <= '9') || *value == '-' || *value == '+') return atoi(value) != 0;
    return strcasecmp(value, "off") && strcasecmp(value, "no") && strcasecmp(value, "false");
}
static float env_float(const char *name, float fallback, float low, float high){
    const char *value = getenv(name);
    if (!value || !*value) return fallback;
    float v = (float)atof(value);
    return v < low ? low : v > high ? high : v;
}
int gamepad_enabled(void){
    static int enabled = -1;
    if (enabled < 0) enabled = env_flag("NFSV_PAD", 1);
    return enabled;
}

static void copy_state(GCExtendedGamepad *pad, unsigned expected){
    uint32_t buttons = 0;
#define BUTTON(element, bit) do { GCControllerButtonInput *e = (element); if (e && e.pressed) buttons |= 1u << (bit); } while (0)
    BUTTON(pad.buttonA, PAD_A); BUTTON(pad.buttonB, PAD_B);
    BUTTON(pad.buttonX, PAD_X); BUTTON(pad.buttonY, PAD_Y);
    BUTTON(pad.leftShoulder, PAD_LB); BUTTON(pad.rightShoulder, PAD_RB);
    BUTTON(pad.buttonOptions, PAD_BACK); BUTTON(pad.buttonMenu, PAD_START);
    BUTTON(pad.leftThumbstickButton, PAD_LS); BUTTON(pad.rightThumbstickButton, PAD_RS);
    BUTTON(pad.dpad.up, PAD_DUP); BUTTON(pad.dpad.down, PAD_DDOWN);
    BUTTON(pad.dpad.left, PAD_DLEFT); BUTTON(pad.dpad.right, PAD_DRIGHT);
#undef BUTTON
    /* GameController's y axes point up; DirectInput's point down. */
    float axes[PAD_NAXES] = {
        pad.leftThumbstick.xAxis.value, -pad.leftThumbstick.yAxis.value,
        pad.rightThumbstick.xAxis.value, -pad.rightThumbstick.yAxis.value,
        pad.leftTrigger.value, pad.rightTrigger.value };
    os_unfair_lock_lock(&lock);
    if (expected == generation){
        real_pad.buttons = buttons;
        memcpy(real_pad.axis, axes, sizeof axes);
    }
    os_unfair_lock_unlock(&lock);
}

static void refresh(void){
    if (!active) return;
    unsigned expected;
    os_unfair_lock_lock(&lock); expected = generation; os_unfair_lock_unlock(&lock);
    GCExtendedGamepad *pad = active.extendedGamepad;
    if (pad) dispatch_async(queue, ^{ copy_state(pad, expected); });
}

static void pick_active(void){
    GCController *best = nil;
    for (GCController *controller in order) if (controller.extendedGamepad){ best = controller; break; }
    if (best == active) return;
    if (active) active.extendedGamepad.valueChangedHandler = nil;
    active = best;
    os_unfair_lock_lock(&lock);
    unsigned expected = ++generation;
    memset(&real_pad, 0, sizeof real_pad);
    if (best){
        real_pad.connected = 1;
        const char *name = best.vendorName.length ? best.vendorName.UTF8String : "Game Controller";
        unsigned n = 0;
        for (; *name && n < sizeof real_pad.name - 1; name++)
            if (*name >= 32 && *name < 127) real_pad.name[n++] = *name;
        real_pad.name[n] = 0;
    }
    os_unfair_lock_unlock(&lock);
    if (best){
        best.handlerQueue = queue;
        best.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element){
            (void)element; copy_state(pad, expected);
        };
        refresh();
    }
    fprintf(stderr, "game controller: %s\n", best ? real_pad.name : "none");
}

static void setup(void){
    order = [NSMutableArray array];
    queue = dispatch_queue_create("org.nfsv.gamepad", DISPATCH_QUEUE_SERIAL);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSOperationQueue *main = NSOperationQueue.mainQueue;
    [center addObserverForName:GCControllerDidConnectNotification object:nil queue:main usingBlock:^(NSNotification *note){
        GCController *controller = note.object;
        if (logging) fprintf(stderr, "game controller connected: %s (%s)\n",
                             controller.vendorName.UTF8String ?: "?", controller.productCategory.UTF8String ?: "?");
        if (![order containsObject:controller]) [order addObject:controller];
        pick_active();
    }];
    [center addObserverForName:GCControllerDidDisconnectNotification object:nil queue:main usingBlock:^(NSNotification *note){
        GCController *controller = note.object;
        if (logging) fprintf(stderr, "game controller disconnected: %s\n", controller.vendorName.UTF8String ?: "?");
        [order removeObject:controller];
        pick_active();
    }];
    [center addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:main usingBlock:^(NSNotification *note){
        (void)note; os_unfair_lock_lock(&lock); app_active = 0; os_unfair_lock_unlock(&lock);
    }];
    [center addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:main usingBlock:^(NSNotification *note){
        (void)note; os_unfair_lock_lock(&lock); app_active = 1; os_unfair_lock_unlock(&lock);
        refresh();
    }];
    for (GCController *controller in GCController.controllers)
        if (![order containsObject:controller]) [order addObject:controller];
    pick_active();
}

void gamepad_init(void){
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        logging = env_flag("NFSV_PAD_LOG", 0);
        if (NSThread.isMainThread) setup();
        else dispatch_async(dispatch_get_main_queue(), ^{ setup(); });
    });
}

/* Radial dead zone with the remaining travel rescaled, so half a stick still
   reads about half. */
static void stick_deadzone(float *x, float *y, float zone){
    float r = sqrtf(*x * *x + *y * *y);
    if (r <= zone || r <= 0.f){ *x = *y = 0.f; return; }
    float k = (r >= 1.f ? 1.f : (r - zone) / (1.f - zone)) / r;
    *x = fmaxf(-1.f, fminf(1.f, *x * k));
    *y = fmaxf(-1.f, fminf(1.f, *y * k));
}
static float trigger_deadzone(float v, float zone){
    if (v <= zone) return 0.f;
    return v >= 1.f ? 1.f : (v - zone) / (1.f - zone);
}

int gamepad_read(PadState *state){
    static float zone = -1.f, trigger_zone;
    if (zone < 0.f){
        trigger_zone = env_float("NFSV_PAD_TRIGGER_DEADZONE", 0.02f, 0.f, 0.9f);
        zone = env_float("NFSV_PAD_DEADZONE", 0.08f, 0.f, 0.9f);
    }
    os_unfair_lock_lock(&lock);
    *state = synthetic_pad.connected ? synthetic_pad : real_pad;
    int neutral = !app_active && !synthetic_pad.connected;
    os_unfair_lock_unlock(&lock);
    if (neutral){ state->buttons = 0; memset(state->axis, 0, sizeof state->axis); }
    stick_deadzone(&state->axis[PAD_AXIS_LX], &state->axis[PAD_AXIS_LY], zone);
    stick_deadzone(&state->axis[PAD_AXIS_RX], &state->axis[PAD_AXIS_RY], zone);
    state->axis[PAD_AXIS_LT] = trigger_deadzone(state->axis[PAD_AXIS_LT], trigger_zone);
    state->axis[PAD_AXIS_RT] = trigger_deadzone(state->axis[PAD_AXIS_RT], trigger_zone);
    return state->connected;
}

void gamepad_synth_connect(int on){
    os_unfair_lock_lock(&lock);
    if ((on != 0) != synthetic_pad.connected){
        memset(&synthetic_pad, 0, sizeof synthetic_pad);
        synthetic_pad.connected = on != 0;
        snprintf(synthetic_pad.name, sizeof synthetic_pad.name, "Virtual Controller");
    }
    os_unfair_lock_unlock(&lock);
}
void gamepad_synth_button(int button, int down){
    if (button < 0 || button >= PAD_NBUTTONS) return;
    gamepad_synth_connect(1);
    os_unfair_lock_lock(&lock);
    if (down) synthetic_pad.buttons |= 1u << button; else synthetic_pad.buttons &= ~(1u << button);
    os_unfair_lock_unlock(&lock);
}
void gamepad_synth_axis(int axis, float value){
    if (axis < 0 || axis >= PAD_NAXES) return;
    gamepad_synth_connect(1);
    float low = axis >= PAD_AXIS_LT ? 0.f : -1.f;
    os_unfair_lock_lock(&lock);
    synthetic_pad.axis[axis] = value < low ? low : value > 1.f ? 1.f : value;
    os_unfair_lock_unlock(&lock);
}

int gamepad_button_by_name(const char *name){
    static const struct { const char *name; int button; } names[] = {
        {"A",PAD_A},{"CROSS",PAD_A},{"B",PAD_B},{"CIRCLE",PAD_B},{"X",PAD_X},{"SQUARE",PAD_X},
        {"Y",PAD_Y},{"TRIANGLE",PAD_Y},{"LB",PAD_LB},{"L1",PAD_LB},{"RB",PAD_RB},{"R1",PAD_RB},
        {"BACK",PAD_BACK},{"SHARE",PAD_BACK},{"START",PAD_START},{"OPTIONS",PAD_START},
        {"LS",PAD_LS},{"L3",PAD_LS},{"RS",PAD_RS},{"R3",PAD_RS},
        {"UP",PAD_DUP},{"DOWN",PAD_DDOWN},{"LEFT",PAD_DLEFT},{"RIGHT",PAD_DRIGHT},
    };
    for (unsigned i = 0; i < sizeof names / sizeof *names; i++)
        if (!strcasecmp(name, names[i].name)) return names[i].button;
    return -1;
}
int gamepad_axis_by_name(const char *name){
    static const char *const names[PAD_NAXES] = {"LX","LY","RX","RY","LT","RT"};
    for (int i = 0; i < PAD_NAXES; i++) if (!strcasecmp(name, names[i])) return i;
    if (!strcasecmp(name, "L2")) return PAD_AXIS_LT;
    if (!strcasecmp(name, "R2")) return PAD_AXIS_RT;
    return -1;
}
