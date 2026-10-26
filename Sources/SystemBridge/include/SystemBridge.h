#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct { int identifier; double x; double y; } ODContact;
typedef void (*ODFrameCallback)(const ODContact *contacts, int count, double timestamp);
bool ODTrackpadStart(ODFrameCallback callback);
void ODTrackpadEnable(bool enabled);
void ODTrackpadStop(void);
int ODTrackpadDeviceCount(void);
bool ODGetBrightness(uint32_t display, float *value);
bool ODSetBrightness(uint32_t display, float value);
bool ODRequestAccessibility(void);
bool ODSendMediaKey(int key);
bool ODMediaCommand(int command);
