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
#endif
