/* The virtual game pad (gamepad.m) as a DirectInput 5 joystick.

   Porsche.exe enumerates every DirectInput device once at start-up
   (0x532b80), creates each one, sets c_dfDIJoystick (80-byte DIJOYSTATE)
   on joysticks with exclusive foreground access, probes axes, POVs and
   buttons by offset with GetObjectInfo (0x56fdb0) and reads the raw state
   every frame. It never sets axis ranges, so the default 0..65535 applies.
   Its controls screen stores bindings by device index, so the pad is always
   listed after the keyboard and mouse, reading centred while no controller
   is connected; a controller can then be connected at any time.

   The device is a gamepad (DIDEVTYPEJOYSTICK_GAMEPAD); the game gives
   wheels (subtype 6) a different steering path. Force feedback is not
   reported, so the game skips its effects.

   The layout fits the game's own joystick defaults (its "reset defaults"
   button): steering on X, accelerate and brake on Y up and down, hand brake
   button 1, look behind 3, reset car 4, cameras 6, shift up 8 and down 9.
   The triggers therefore share the Y axis, as Xbox pads share one axis under
   DirectInput on Windows: the right trigger pulls it up, the left trigger
   down. Each control appears on exactly one object, so the game's rebinding
   screen always picks the input that moved.

     axes     X left stick X, Y triggers, Z left stick Y, Rx/Ry right stick
     POV 0    D-pad
     buttons  1 A/Cross, 2 B/Circle, 3 X/Square, 4 Y/Triangle,
              5 Start/Options, 6 Back/Share, 7 left stick, 8 RB/R1, 9 LB/L1,
              10 right stick */
#include "runtime.h"
#include "gamepad.h"
#include "joystick.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

void gheap_free(int, uint32_t);

#define DIERR_OBJECTNOTFOUND 0x80070002u
#define DIERR_INVALIDPARAM 0x80070057u
#define DIERR_UNSUPPORTED 0x80004001u
#define DIDFT_ABSAXIS 0x02u
#define DIDFT_PSHBUTTON 0x04u
#define DIDFT_POV 0x10u
#define DIDOI_ASPECTPOSITION 0x100u

enum { AXES = 5, POVS = 1, BUTTONS = 10, OBJECTS = AXES + POVS + BUTTONS };
static const uint32_t axis_guid[AXES] = {0xa36d02e0, 0xa36d02e1, 0xa36d02e2, 0xa36d02f4, 0xa36d02f5};
static const char *const axis_name[AXES] = {"X Axis", "Y Axis", "Z Axis", "X Rotation", "Y Rotation"};
static const int button_source[BUTTONS] = {PAD_A, PAD_B, PAD_X, PAD_Y, PAD_START, PAD_BACK, PAD_LS, PAD_RB, PAD_LB, PAD_RS};
static int32_t range_min[AXES], range_max[AXES];
static uint32_t deadzone[AXES], saturation[AXES];

static void write_guid(uint32_t p, uint32_t first, uint16_t second, uint16_t third, const char tail[8]){
    MR32(p) = first; MR16(p + 4) = second; MR16(p + 6) = third; memcpy(guest_ptr(p + 8, 8), tail, 8);
}
static void object_guid(uint32_t p, uint32_t first){ write_guid(p, first, 0xc9f3, 0x11cf, "\xbf\xc7" "DEST\0\0"); }
/* A stable instance GUID of the port's own, and a HID-style product GUID. */
static const uint8_t pad_instance[16] = {0x56, 0x53, 0x46, 0x4e, 0x41, 0x50, 0xd0, 0x11,
                                         0x80, 0x00, 'N', 'F', 'S', 'V', 'P', 'D'};
static void instance_guid(uint32_t p){ memcpy(guest_ptr(p, 16), pad_instance, 16); }
static void product_guid(uint32_t p){ write_guid(p, 0x53564e46, 0, 0, "\0\0PIDVID"); }

int joystick_available(void){
    int enabled = gamepad_enabled();
    if (enabled) gamepad_init();
    return enabled;
}
int joystick_matches_guid(uint32_t p){
    return mem_valid(p, 16) && !memcmp(guest_ptr(p, 16), pad_instance, 16);
}
void joystick_reset(void){
    for (unsigned i = 0; i < AXES; i++){ range_min[i] = 0; range_max[i] = 65535; deadzone[i] = 0; saturation[i] = 10000; }
}

uint32_t joystick_device_instance(uint32_t p){
    uint32_t size = MR32(p);
    if (size != 568 && size != 580) return DIERR_INVALIDPARAM;
    memset(guest_ptr(p, size), 0, size); MR32(p) = size;
    instance_guid(p + 4); product_guid(p + 20);
    MR32(p + 36) = JOYSTICK_DEVTYPE;
    strcpy((char *)guest_ptr(p + 40, 260), "Game Controller");
    strcpy((char *)guest_ptr(p + 300, 260), "Game Controller");
    if (size == 580){ MR16(p + 576) = 1; MR16(p + 578) = 5; }   /* HID generic desktop, game pad */
    return 0;
}

uint32_t joystick_caps(uint32_t p){
    uint32_t size = MR32(p);
    if (size != 24 && size != 44) return DIERR_INVALIDPARAM;
    memset(guest_ptr(p, size), 0, size); MR32(p) = size;
    MR32(p + 4) = 1;   /* DIDC_ATTACHED: always listed, so saved bindings keep their device */
    MR32(p + 8) = JOYSTICK_DEVTYPE; MR32(p + 12) = AXES; MR32(p + 16) = BUTTONS; MR32(p + 20) = POVS;
    return 0;
}

static uint32_t object_offset(unsigned i){
    return i < AXES ? 4 * i : i < AXES + POVS ? 0x20 + 4 * (i - AXES) : 0x30 + (i - AXES - POVS);
}
static uint32_t object_type(unsigned i){
    return i < AXES ? DIDFT_ABSAXIS | i << 8 : i < AXES + POVS ? DIDFT_POV | (i - AXES) << 8
                                                             : DIDFT_PSHBUTTON | (i - AXES - POVS) << 8;
}
static int find_object(uint32_t object, uint32_t how){
    for (unsigned i = 0; i < OBJECTS; i++){
        if (how == 1 && object == object_offset(i)) return (int)i;
        if (how == 2 && ((object >> 8) & 0xffff) == ((object_type(i) >> 8) & 0xffff) && (object & object_type(i) & 0xff)) return (int)i;
    }
    return -1;
}
static void fill_object(uint32_t p, uint32_t size, unsigned i){
    memset(guest_ptr(p, size), 0, size); MR32(p) = size;
    object_guid(p + 4, i < AXES ? axis_guid[i] : i < AXES + POVS ? 0xa36d02f2 : 0xa36d02f0);
    MR32(p + 20) = object_offset(i); MR32(p + 24) = object_type(i);
    MR32(p + 28) = i < AXES ? DIDOI_ASPECTPOSITION : 0;
    char *name = guest_ptr(p + 32, 260);
    if (i < AXES) strcpy(name, axis_name[i]);
    else if (i < AXES + POVS) strcpy(name, "Hat Switch");
    else snprintf(name, 260, "Button %u", i - AXES - POVS + 1);
    if (size == 316){
        MR16(p + 304) = i < AXES + POVS ? 1 : 9;
        MR16(p + 306) = i < AXES ? 0x30 + i : i < AXES + POVS ? 0x39 : i - AXES - POVS + 1;   /* HID X..Rz, hat, button n */
    }
}
uint32_t joystick_object_info(uint32_t p, uint32_t object, uint32_t how){
    uint32_t size = MR32(p);
    if (size != 292 && size != 316) return DIERR_INVALIDPARAM;
    if (how != 1 && how != 2) return DIERR_INVALIDPARAM;
    int i = find_object(object, how);
    if (i < 0) return DIERR_OBJECTNOTFOUND;
    fill_object(p, size, (unsigned)i);
    return 0;
}
uint32_t joystick_enum_objects(CPU *c, uint32_t callback, uint32_t context, uint32_t flags){
    uint32_t p = win32_alloc(316, 1);
    for (unsigned i = 0; i < OBJECTS; i++){
        if ((flags & 0xff) && !(object_type(i) & flags & 0xff)) continue;
        fill_object(p, 316, i);
        uint32_t args[] = {p, context};
        if (!call_guest(c, callback, 2, args)) break;
    }
    gheap_free(1, p);
    return 0;
}

/* Properties: DIPROPHEADER {dwSize, dwHeaderSize, dwObj, dwHow} followed by
   a DWORD (20 bytes) or a DIPROPRANGE pair (24 bytes). */
uint32_t joystick_property(uint32_t self, int set, uint32_t property, uint32_t p){
    if (property < 1 || property > 9) return DIERR_UNSUPPORTED;
    if (!mem_valid(p, 16) || MR32(p + 4) != 16) return DIERR_INVALIDPARAM;
    uint32_t size = MR32(p), object = MR32(p + 8), how = MR32(p + 12);
    if (size != (property == 4 ? 24u : 20u) || !mem_valid(p, size)) return DIERR_INVALIDPARAM;
    int axis = -1;
    if (how == 0){ if (object) return DIERR_INVALIDPARAM; }
    else if (how == 1 || how == 2){
        int i = find_object(object, how);
        if (i < 0) return DIERR_OBJECTNOTFOUND;
        if (i >= AXES) return DIERR_UNSUPPORTED;
        axis = i;
    }
    else return DIERR_INVALIDPARAM;
    unsigned first = axis < 0 ? 0 : (unsigned)axis, last = axis < 0 ? AXES : (unsigned)axis + 1;
    switch (property){
    case 1:   /* DIPROP_BUFFERSIZE */
        if (axis >= 0) return DIERR_INVALIDPARAM;
        if (set) MR32(self + 16) = MR32(p + 16) > 1024 ? 1024 : MR32(p + 16);
        else MR32(p + 16) = MR32(self + 16);
        return 0;
    case 2:   /* DIPROP_AXISMODE: always absolute */
        if (set) return MR32(p + 16) == 0 ? 0 : DIERR_UNSUPPORTED;
        MR32(p + 16) = 0; return 0;
    case 3:   /* DIPROP_GRANULARITY */
        if (set) return DIERR_UNSUPPORTED;
        MR32(p + 16) = 1; return 0;
    case 4: { /* DIPROP_RANGE */
        if (!set){ MR32(p + 16) = (uint32_t)range_min[first]; MR32(p + 20) = (uint32_t)range_max[first]; return 0; }
        int32_t low = (int32_t)MR32(p + 16), high = (int32_t)MR32(p + 20);
        if (low >= high) return DIERR_INVALIDPARAM;
        for (unsigned i = first; i < last; i++){ range_min[i] = low; range_max[i] = high; }
        return 0;
    }
    case 5: case 6: { /* DIPROP_DEADZONE, DIPROP_SATURATION */
        uint32_t *values = property == 5 ? deadzone : saturation;
        if (!set){ MR32(p + 16) = values[first]; return 0; }
        uint32_t value = MR32(p + 16);
        if (value > 10000) return DIERR_INVALIDPARAM;
        for (unsigned i = first; i < last; i++) values[i] = value;
        return 0;
    }
    default:  /* force feedback gain, load and autocenter */
        return DIERR_UNSUPPORTED;
    }
}

/* DirectInput dead zone and saturation on the deflection from rest, in
   units of 1/10000 of full travel. */
static float shape(float deflection, unsigned i){
    float magnitude = fabsf(deflection) * 10000.f, zone = (float)deadzone[i], full = (float)saturation[i];
    if (full <= zone) return magnitude > zone ? copysignf(1.f, deflection) : 0.f;
    float scaled = magnitude <= zone ? 0.f : magnitude >= full ? 1.f : (magnitude - zone) / (full - zone);
    return copysignf(scaled, deflection);
}
static uint32_t pov(uint32_t buttons){
    int x = !!(buttons & 1u << PAD_DRIGHT) - !!(buttons & 1u << PAD_DLEFT);
    int y = !!(buttons & 1u << PAD_DDOWN) - !!(buttons & 1u << PAD_DUP);
    static const uint32_t angle[3][3] = {{31500, 0, 4500}, {27000, 0xffffffffu, 9000}, {22500, 18000, 13500}};
    return angle[y + 1][x + 1];
}
uint32_t joystick_state(void *out, uint32_t size){
    if (size != 0x50 && size != 0x110) return DIERR_INVALIDPARAM;
    PadState pad;
    gamepad_read(&pad);
    uint8_t *bytes = out;
    memset(bytes, 0, size);
    float deflection[AXES] = {pad.axis[PAD_AXIS_LX], pad.axis[PAD_AXIS_LT] - pad.axis[PAD_AXIS_RT],
                              pad.axis[PAD_AXIS_LY], pad.axis[PAD_AXIS_RX], pad.axis[PAD_AXIS_RY]};
    for (unsigned i = 0; i < AXES; i++){
        double position = (shape(deflection[i], i) + 1.0) * 0.5;
        int32_t value = (int32_t)floor(range_min[i] + position * ((double)range_max[i] - range_min[i]) + 0.5);
        memcpy(bytes + 4 * i, &value, 4);
    }
    uint32_t hats[4] = {pov(pad.buttons), 0xffffffffu, 0xffffffffu, 0xffffffffu};
    memcpy(bytes + 0x20, hats, sizeof hats);
    for (unsigned i = 0; i < BUTTONS; i++) bytes[0x30 + i] = pad.buttons & 1u << button_source[i] ? 0x80 : 0;
    return 0;
}
