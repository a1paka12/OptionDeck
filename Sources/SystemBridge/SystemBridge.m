#import "SystemBridge.h"
#import <Cocoa/Cocoa.h>
#import <CoreFoundation/CoreFoundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <math.h>

// Undocumented ABI, loaded optionally. All positions are validated before use.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
    int frame; double timestamp;
    int identifier, state, fingerID, handID;
    MTVector normalized; float size; int zero1;
    float angle, majorAxis, minorAxis;
    MTVector absolute; int zero2, zero3; float density;
} MTTouch;
_Static_assert(sizeof(MTTouch) == 96, "Multitouch contact ABI must be 96 bytes");
typedef int (*MTCallback)(void *, MTTouch *, int, double, int);
static void *mtLibrary;
static CFArrayRef mtDevices;
static void (*mtRegister)(void *, MTCallback);
static void (*mtUnregister)(void *, MTCallback);
static void (*mtStart)(void *, int);
static void (*mtStop)(void *);
static ODFrameCallback frameCallback;
static atomic_bool trackingEnabled = false;
static atomic_uint trackingGeneration = 0;
static void *activeDevice;

static int receiveFrame(void *device, MTTouch *touches, int count, double time, int frame) {
    if (!atomic_load(&trackingEnabled) || count < 0 || count > 16) return 0;
    ODContact contacts[16];
    int active = 0;
    for (int i = 0; i < count; i++) {
        // 3/4 are touching/moving; 5/6/7 are break, linger and out of range.
        if (touches[i].state != 3 && touches[i].state != 4) continue;
        float x = touches[i].normalized.position.x, y = touches[i].normalized.position.y;
        if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) continue;
        contacts[active++] = (ODContact){touches[i].identifier, x, 1.0 - y};
    }
    NSData *copy = [NSData dataWithBytes:contacts length:sizeof(ODContact) * active];
    unsigned generation = atomic_load(&trackingGeneration);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!atomic_load(&trackingEnabled) || generation != atomic_load(&trackingGeneration)) return;
        if (!activeDevice && active) activeDevice = device;
        if (activeDevice != device) return;
        if (frameCallback) frameCallback(copy.bytes, active, time);
        if (!active) activeDevice = NULL;
    });
    return 0;
}

bool ODTrackpadStart(ODFrameCallback callback) {
    if (mtDevices) return true;
    mtLibrary = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!mtLibrary) return false;
    CFArrayRef (*createList)(void) = dlsym(mtLibrary, "MTDeviceCreateList");
    mtRegister = dlsym(mtLibrary, "MTRegisterContactFrameCallback");
    mtUnregister = dlsym(mtLibrary, "MTUnregisterContactFrameCallback");
    mtStart = dlsym(mtLibrary, "MTDeviceStart");
    mtStop = dlsym(mtLibrary, "MTDeviceStop");
    if (!createList || !mtRegister || !mtUnregister || !mtStart || !mtStop) return false;
    mtDevices = createList();
    if (!mtDevices || CFArrayGetCount(mtDevices) == 0) {
        if (mtDevices) CFRelease(mtDevices);
        mtDevices = NULL; return false;
    }
    frameCallback = callback;
    for (CFIndex i = 0; i < CFArrayGetCount(mtDevices); i++) {
        void *device = (void *)CFArrayGetValueAtIndex(mtDevices, i);
        mtRegister(device, receiveFrame); mtStart(device, 0);
    }
    return true;
}

void ODTrackpadEnable(bool enabled) {
    atomic_store(&trackingEnabled, enabled);
    atomic_fetch_add(&trackingGeneration, 1);
    activeDevice = NULL;
}

void ODTrackpadStop(void) {
    ODTrackpadEnable(false);
    if (mtDevices) {
        for (CFIndex i = 0; i < CFArrayGetCount(mtDevices); i++) {
            void *device = (void *)CFArrayGetValueAtIndex(mtDevices, i);
            mtUnregister(device, receiveFrame); mtStop(device);
        }
        CFRelease(mtDevices); mtDevices = NULL;
    }
    frameCallback = NULL;
    // Keep the library loaded: the driver may still have a callback in flight.
}

int ODTrackpadDeviceCount(void) { return mtDevices ? (int)CFArrayGetCount(mtDevices) : 0; }

static void *displayLibrary;
static int (*getBrightness)(uint32_t, float *);
static int (*setBrightness)(uint32_t, float);
static void loadDisplay(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        displayLibrary = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW);
        if (displayLibrary) {
            getBrightness = dlsym(displayLibrary, "DisplayServicesGetBrightness");
            setBrightness = dlsym(displayLibrary, "DisplayServicesSetBrightness");
        }
    });
}
bool ODGetBrightness(uint32_t display, float *value) {
    loadDisplay();
    return value && getBrightness && getBrightness(display, value) == 0 && isfinite(*value) && *value >= 0 && *value <= 1;
}
bool ODSetBrightness(uint32_t display, float value) {
    loadDisplay();
    return setBrightness && isfinite(value) && setBrightness(display, fminf(1, fmaxf(0, value))) == 0;
}

bool ODRequestAccessibility(void) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

bool ODSendMediaKey(int key) {
    if (key < 16 || key > 18 || !AXIsProcessTrusted()) return false;
    for (int down = 1; down >= 0; down--) {
        int state = down ? 0xA : 0xB;
        NSEvent *event = [NSEvent otherEventWithType:NSEventTypeSystemDefined
            location:NSZeroPoint modifierFlags:(NSEventModifierFlags)(state << 8)
            timestamp:0 windowNumber:0 context:nil subtype:8
            data1:(key << 16) | (state << 8) data2:-1];
        if (!event.CGEvent) return false;
        CGEventPost(kCGHIDEventTap, event.CGEvent);
    }
    return true;
}

bool ODMediaCommand(int command) {
    if (command != 2 && command != 4 && command != 5 && command != 12 && command != 13) return false;
    static Boolean (*sendCommand)(int, CFDictionaryRef);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (library) sendCommand = dlsym(library, "MRMediaRemoteSendCommand");
    });
    // A fallback hardware Play key can launch Apple Music even if no media
    // session exists. Let the Swift router open the preferred app instead.
    return sendCommand && sendCommand(command, NULL);
}
