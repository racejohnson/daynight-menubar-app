/*
 Display brightness bridge adapted from nriley/brightness (BSD-2-Clause).
 Keyboard brightness bridge adapted from rakalex/mac-brightnessctl (MIT).
 Full license text is included in THIRD_PARTY_NOTICES.md and the app bundle.
*/

#import "DayNightPrivateAPI.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>

typedef bool (*DNCanChangeBrightnessFunction)(uint32_t);
typedef int (*DNGetBrightnessFunction)(uint32_t, float *);
typedef int (*DNSetBrightnessFunction)(uint32_t, float);

static DNCanChangeBrightnessFunction dnCanChangeBrightness;
static DNGetBrightnessFunction dnGetBrightness;
static DNSetBrightnessFunction dnSetBrightness;
static bool dnDisplayServicesLoaded;

static void DNLoadDisplayServices(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (handle == NULL) {
            return;
        }

        dnCanChangeBrightness = (DNCanChangeBrightnessFunction)dlsym(
            handle, "DisplayServicesCanChangeBrightness"
        );
        dnGetBrightness = (DNGetBrightnessFunction)dlsym(
            handle, "DisplayServicesGetBrightness"
        );
        dnSetBrightness = (DNSetBrightnessFunction)dlsym(
            handle, "DisplayServicesSetBrightness"
        );
        dnDisplayServicesLoaded = (
            dnCanChangeBrightness != NULL &&
            dnGetBrightness != NULL &&
            dnSetBrightness != NULL
        );
    });
}

bool DNDisplayCanChangeBrightness(uint32_t displayID) {
    DNLoadDisplayServices();
    return dnDisplayServicesLoaded && dnCanChangeBrightness(displayID);
}

bool DNDisplayGetBrightness(uint32_t displayID, float *brightness) {
    DNLoadDisplayServices();
    if (!dnDisplayServicesLoaded || brightness == NULL) {
        return false;
    }
    return dnGetBrightness(displayID, brightness) == 0;
}

bool DNDisplaySetBrightness(uint32_t displayID, float brightness) {
    DNLoadDisplayServices();
    if (!dnDisplayServicesLoaded) {
        return false;
    }
    float clamped = fmaxf(0.0f, fminf(1.0f, brightness));
    return dnSetBrightness(displayID, clamped) == 0;
}

@interface NSObject (DNKeyboardBrightnessClient)
- (BOOL)isAutoBrightnessEnabledForKeyboard:(unsigned long long)keyboardID;
- (BOOL)isKeyboardBuiltIn:(unsigned long long)keyboardID;
- (BOOL)enableAutoBrightness:(BOOL)enabled
                forKeyboard:(unsigned long long)keyboardID;
- (BOOL)setBrightness:(float)brightness
          forKeyboard:(unsigned long long)keyboardID;
- (float)brightnessForKeyboard:(unsigned long long)keyboardID;
- (id)copyKeyboardBacklightIDs;
@end

static id dnKeyboardClient;
static NSNumber *dnBuiltInKeyboardID;

static void DNLoadKeyboardClient(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleWithPath:
            @"/System/Library/PrivateFrameworks/CoreBrightness.framework"];
        if (![bundle load]) {
            return;
        }

        Class clientClass = NSClassFromString(@"KeyboardBrightnessClient");
        if (clientClass == Nil) {
            return;
        }

        dnKeyboardClient = [[clientClass alloc] init];
        if (dnKeyboardClient == nil) {
            return;
        }

        id identifiers = [dnKeyboardClient copyKeyboardBacklightIDs];
        if ([identifiers conformsToProtocol:@protocol(NSFastEnumeration)]) {
            for (id value in identifiers) {
                if (![value respondsToSelector:@selector(unsignedLongLongValue)]) {
                    continue;
                }
                unsigned long long keyboardID = [value unsignedLongLongValue];
                if ([dnKeyboardClient isKeyboardBuiltIn:keyboardID]) {
                    dnBuiltInKeyboardID = @(keyboardID);
                    break;
                }
            }
        }

        // Current Apple notebooks use identifier 1. Retain the upstream
        // fallback for OS releases where copyKeyboardBacklightIDs is empty.
        if (dnBuiltInKeyboardID == nil &&
            [dnKeyboardClient isKeyboardBuiltIn:1]) {
            dnBuiltInKeyboardID = @1;
        }
    });
}

static unsigned long long DNBuiltInKeyboardID(void) {
    DNLoadKeyboardClient();
    return dnBuiltInKeyboardID.unsignedLongLongValue;
}

bool DNKeyboardAvailable(void) {
    DNLoadKeyboardClient();
    return dnKeyboardClient != nil && dnBuiltInKeyboardID != nil;
}

bool DNKeyboardGetBrightness(float *brightness) {
    if (!DNKeyboardAvailable() || brightness == NULL) {
        return false;
    }
    *brightness = [dnKeyboardClient
        brightnessForKeyboard:DNBuiltInKeyboardID()];
    return isfinite(*brightness) && *brightness >= 0.0f && *brightness <= 1.0f;
}

bool DNKeyboardSetBrightness(float brightness) {
    if (!DNKeyboardAvailable()) {
        return false;
    }
    float clamped = fmaxf(0.0f, fminf(1.0f, brightness));
    return [dnKeyboardClient setBrightness:clamped
                              forKeyboard:DNBuiltInKeyboardID()];
}

bool DNKeyboardGetAutoBrightness(bool *enabled) {
    if (!DNKeyboardAvailable() || enabled == NULL) {
        return false;
    }
    *enabled = [dnKeyboardClient
        isAutoBrightnessEnabledForKeyboard:DNBuiltInKeyboardID()];
    return true;
}

bool DNKeyboardSetAutoBrightness(bool enabled) {
    if (!DNKeyboardAvailable()) {
        return false;
    }
    return [dnKeyboardClient enableAutoBrightness:enabled
                                       forKeyboard:DNBuiltInKeyboardID()];
}
