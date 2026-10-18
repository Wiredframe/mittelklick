#include "MTBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>

// Speicherlayout eines Kontakts, wie es MultitouchSupport liefert (96 Byte, bekannt aus der Community).
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerId;
    int handId;
    MTVector normalized;
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector mm;
    int zero2[2];
    float unknown;
} MTTouch;

typedef void *MTDeviceRef;
typedef void (*MTFrameCallback)(MTDeviceRef, MTTouch *, int, double, int, void *);

static CFMutableArrayRef (*MTDeviceCreateList)(void);
static void (*MTRegisterContactFrameCallbackWithRefcon)(MTDeviceRef, MTFrameCallback, void *);
static void (*MTUnregisterContactFrameCallback)(MTDeviceRef, MTFrameCallback);
static int (*MTDeviceStart)(MTDeviceRef, int);
static int (*MTDeviceStop)(MTDeviceRef);
static int (*MTDeviceGetDeviceID)(MTDeviceRef, uint64_t *);

static MKFrameHandler frameHandler;
static CFMutableArrayRef devices;

static bool load(void) {
    static void *lib;
    if (lib) return true;
    lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!lib) return false;
    MTDeviceCreateList = dlsym(lib, "MTDeviceCreateList");
    MTRegisterContactFrameCallbackWithRefcon = dlsym(lib, "MTRegisterContactFrameCallbackWithRefcon");
    MTUnregisterContactFrameCallback = dlsym(lib, "MTUnregisterContactFrameCallback");
    MTDeviceStart = dlsym(lib, "MTDeviceStart");
    MTDeviceStop = dlsym(lib, "MTDeviceStop");
    MTDeviceGetDeviceID = dlsym(lib, "MTDeviceGetDeviceID");
    return MTDeviceCreateList && MTRegisterContactFrameCallbackWithRefcon && MTDeviceStart;
}

static void onFrame(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame, void *refcon) {
    (void)frame;
    (void)refcon;
    MKTouch copy[32];
    int n = count < 32 ? count : 32;
    for (int i = 0; i < n; i++) {
        copy[i] = (MKTouch){ touches[i].identifier, touches[i].state,
                             touches[i].normalized.position.x, touches[i].normalized.position.y };
    }
    uint64_t id = (uint64_t)(uintptr_t)device;
    if (MTDeviceGetDeviceID) MTDeviceGetDeviceID(device, &id);
    if (frameHandler) frameHandler(id, copy, n, timestamp);
}

int mk_start(MKFrameHandler handler) {
    if (!load()) return -1;
    mk_stop();
    frameHandler = handler;
    devices = MTDeviceCreateList();
    if (!devices) return 0;
    CFIndex n = CFArrayGetCount(devices);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        MTRegisterContactFrameCallbackWithRefcon(device, onFrame, NULL);
        MTDeviceStart(device, 0);
    }
    return (int)n;
}

void mk_stop(void) {
    if (!devices) return;
    CFIndex n = CFArrayGetCount(devices);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        if (MTUnregisterContactFrameCallback) MTUnregisterContactFrameCallback(device, onFrame);
        if (MTDeviceStop) MTDeviceStop(device);
    }
    CFRelease(devices);
    devices = NULL;
}

static void (*deviceChanged)(void);

static void onDeviceNotification(void *refcon, io_iterator_t iterator) {
    bool initial = refcon != NULL;
    io_object_t service;
    while ((service = IOIteratorNext(iterator))) IOObjectRelease(service);
    if (!initial && deviceChanged) deviceChanged();
}

void mk_watch_devices(void (*changed)(void)) {
    deviceChanged = changed;
    IONotificationPortRef port = IONotificationPortCreate(kIOMainPortDefault);
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port), kCFRunLoopDefaultMode);
    // Eingebaute Trackpads hängen an AppleMultitouchDevice, per Bluetooth verbundene je nach Modell nur am HID-Treiber.
    const char *classes[] = { "AppleMultitouchDevice", "AppleMultitouchTrackpadHIDEventDriver" };
    const io_name_t types[] = { kIOFirstMatchNotification, kIOTerminatedNotification };
    for (int c = 0; c < 2; c++) {
        for (int i = 0; i < 2; i++) {
            io_iterator_t iterator;
            if (IOServiceAddMatchingNotification(port, types[i], IOServiceMatching(classes[c]),
                                                 onDeviceNotification, NULL, &iterator) == KERN_SUCCESS) {
                // Den Iterator einmal leeren, damit er scharf ist; vorhandene Geräte lösen dabei nichts aus.
                onDeviceNotification((void *)1, iterator);
            }
        }
    }
}
