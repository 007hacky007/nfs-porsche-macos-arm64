#ifndef NFSV_JOYSTICK_H
#define NFSV_JOYSTICK_H
#include <stdint.h>
struct CPU;
/* DIDEVTYPE_HID | DIDEVTYPEJOYSTICK_GAMEPAD << 8 | DIDEVTYPE_JOYSTICK */
#define JOYSTICK_DEVTYPE 0x00010404u
int joystick_available(void);
int joystick_matches_guid(uint32_t guid);
void joystick_reset(void);
uint32_t joystick_device_instance(uint32_t instance);
uint32_t joystick_caps(uint32_t caps);
uint32_t joystick_object_info(uint32_t instance, uint32_t object, uint32_t how);
uint32_t joystick_enum_objects(struct CPU *, uint32_t callback, uint32_t context, uint32_t flags);
uint32_t joystick_property(uint32_t self, int set, uint32_t property, uint32_t header);
uint32_t joystick_state(void *out, uint32_t size);

/* Force feedback on the pad (force.c). */
int force_enabled(void);
void force_reset(void);
uint32_t force_property(int set, uint32_t property, uint32_t value);
uint32_t force_create_effect(uint32_t guid, uint32_t parameters, uint32_t out);
uint32_t force_command(uint32_t flags);
uint32_t force_state(uint32_t out);
int force_effect_method(struct CPU *, uint32_t self, unsigned slot, uint32_t *result, uint32_t *nargs);
void force_release(uint32_t self);
void force_update(void);
#endif
