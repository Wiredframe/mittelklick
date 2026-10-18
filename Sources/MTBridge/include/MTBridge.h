// Schmale Brücke zu Apples privatem MultitouchSupport.framework.
// Das Framework wird zur Laufzeit per dlopen geladen, damit kein privater Header im Build nötig ist.
#pragma once
#include <stdbool.h>
#include <stdint.h>

/// Ein Kontakt auf der Oberfläche, Position normalisiert auf 0…1.
typedef struct {
    int identifier;
    int state;
    float x;
    float y;
} MKTouch;

/// Wird für jeden Frame eines Geräts aufgerufen, auf dem Thread des Frameworks.
typedef void (*MKFrameHandler)(uint64_t device, const MKTouch *touches, int count, double timestamp);

/// Startet alle Multitouch-Geräte. Liefert die Anzahl der gestarteten Geräte, -1 wenn das Framework fehlt.
int mk_start(MKFrameHandler handler);

/// Stoppt alle zuvor gestarteten Geräte.
void mk_stop(void);

/// Meldet per Rückruf auf dem Main-Runloop, wenn ein Multitouch-Gerät hinzukommt oder verschwindet.
void mk_watch_devices(void (*changed)(void));
