/* The virtual game pad between GameController.framework (gamepad.m) and the
   DirectInput joystick the original game sees (joystick.c).

   One virtual pad exists. The first connected controller with an extended
   gamepad profile (DualShock 4, DualSense, Xbox, Switch Pro, MFi) drives it;
   the next one takes over when it disconnects. The local input-control FIFO
   can drive a synthetic pad instead, which then takes the same path.
   Buttons are positional with Xbox names: A is the bottom face button
   (Cross on a PlayStation pad), B right, X left, Y top. */
#ifndef NFSV_GAMEPAD_H
#define NFSV_GAMEPAD_H
#include <stdint.h>

enum {
    PAD_A, PAD_B, PAD_X, PAD_Y, PAD_LB, PAD_RB, PAD_BACK, PAD_START,
    PAD_LS, PAD_RS, PAD_DUP, PAD_DDOWN, PAD_DLEFT, PAD_DRIGHT, PAD_NBUTTONS
};
enum { PAD_AXIS_LX, PAD_AXIS_LY, PAD_AXIS_RX, PAD_AXIS_RY, PAD_AXIS_LT, PAD_AXIS_RT, PAD_NAXES };

typedef struct {
    int connected;
    uint32_t buttons;            /* 1u << PAD_x */
    float axis[PAD_NAXES];       /* sticks -1..1 (+x right, +y down), triggers 0..1 */
    char name[64];
} PadState;

/* 0 when NFSV_PAD is 0, off, no or false. */
int gamepad_enabled(void);
/* Starts controller discovery once; safe from any thread. */
void gamepad_init(void);
/* The pad after dead zones, neutral while the game is not the active app. */
int gamepad_read(PadState *state);

void gamepad_synth_connect(int on);
void gamepad_synth_button(int button, int down);
void gamepad_synth_axis(int axis, float value);
int gamepad_button_by_name(const char *name);
int gamepad_axis_by_name(const char *name);
#endif
