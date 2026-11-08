#ifndef DAYNIGHT_PRIVATE_API_H
#define DAYNIGHT_PRIVATE_API_H

#include <stdbool.h>
#include <stdint.h>

// Thin C wrappers over private DisplayServices and CoreBrightness symbols.
// Each returns false when the framework, the symbol or the device is missing.

bool DNDisplayCanChangeBrightness(uint32_t displayID);
bool DNDisplayGetBrightness(uint32_t displayID, float *brightness);
bool DNDisplaySetBrightness(uint32_t displayID, float brightness);

bool DNKeyboardAvailable(void);
bool DNKeyboardGetBrightness(float *brightness);
bool DNKeyboardSetBrightness(float brightness);
bool DNKeyboardGetAutoBrightness(bool *enabled);
bool DNKeyboardSetAutoBrightness(bool enabled);

#endif
