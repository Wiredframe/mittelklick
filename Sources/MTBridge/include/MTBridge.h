// Thin bridge to Apple's private MultitouchSupport.framework.
// The framework is loaded at runtime via dlopen, so the build needs no private headers.
#pragma once
#include <stdbool.h>
#include <stdint.h>

/// A contact on the surface, position normalized to 0…1.
typedef struct {
    int identifier;
    int state;
    float x;
    float y;
} MKTouch;

/// Called for every frame of a device, on the framework's thread.
typedef void (*MKFrameHandler)(uint64_t device, const MKTouch *touches, int count, double timestamp);

/// Starts all multitouch devices. Returns the number of devices started, -1 if the framework is missing.
int mk_start(MKFrameHandler handler);

/// Stops all previously started devices.
void mk_stop(void);

/// Calls back on the main run loop when a multitouch device appears or disappears.
void mk_watch_devices(void (*changed)(void));
