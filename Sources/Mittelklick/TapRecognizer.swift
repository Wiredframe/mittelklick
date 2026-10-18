import Foundation
import MTBridge
import os

let log = Logger(subsystem: "de.wiredframe.mittelklick", category: "tap")

/// Erkennt ein kurzes Tippen mit einer bestimmten Anzahl Finger, getrennt je Gerät.
final class TapRecognizer {
    /// Anzahl Finger für den Mittelklick, 0 schaltet die Erkennung ab.
    var fingers: Int {
        get { lock.withLock { _fingers } }
        set { lock.withLock { _fingers = newValue; gestures.removeAll() } }
    }
    var onTap: (() -> Void)?
    /// Schreibt jede beendete Geste ins Systemprotokoll, Kategorie „tap“.
    /// Einschalten mit `defaults write de.wiredframe.mittelklick debug -bool true` und Neustart.
    var debug = false

    private var _fingers = 4

    /// Länger gehaltene Finger sind kein Tippen mehr.
    private let maxDuration = 0.3
    /// Weiter als das (normalisiert, 1 = ganze Breite) bewegt, gilt als Wischen.
    private let maxMovement: Float = 0.04

    private struct Gesture {
        var start: Double
        var maxFingers = 0
        var origins: [Int32: (Float, Float)] = [:]
        var valid = true
    }

    private var gestures: [UInt64: Gesture] = [:]
    private let lock = NSLock()

    /// Kontaktzustände 4 (aufsetzen) und 5 (berühren); 1 bis 3 sind Annäherung, 6 bis 8 Abheben.
    private static func isTouching(_ touch: MKTouch) -> Bool { touch.state == 4 || touch.state == 5 }

    func handle(device: UInt64, touches: UnsafeBufferPointer<MKTouch>, timestamp: Double) {
        lock.lock()
        defer { lock.unlock() }
        guard _fingers > 0 else { gestures.removeAll(); return }

        let active = touches.filter(Self.isTouching)
        if active.isEmpty {
            guard let gesture = gestures.removeValue(forKey: device) else { return }
            let duration = timestamp - gesture.start
            let isTap = gesture.valid && gesture.maxFingers == _fingers && duration <= maxDuration
            if debug {
                let result = isTap ? "Mittelklick" : "nichts"
                log.notice("Geste \(gesture.maxFingers, privacy: .public) Finger, \(Int(duration * 1000), privacy: .public) ms, gültig \(gesture.valid, privacy: .public): \(result, privacy: .public)")
            }
            if isTap { DispatchQueue.main.async { [weak self] in self?.onTap?() } }
            return
        }

        var gesture = gestures[device] ?? Gesture(start: timestamp)
        gesture.maxFingers = max(gesture.maxFingers, active.count)
        for touch in active {
            let id = Int32(touch.identifier)
            if let (x, y) = gesture.origins[id] {
                if abs(touch.x - x) > maxMovement || abs(touch.y - y) > maxMovement { gesture.valid = false }
            } else {
                gesture.origins[id] = (touch.x, touch.y)
            }
        }
        if gesture.maxFingers > _fingers || timestamp - gesture.start > maxDuration { gesture.valid = false }
        gestures[device] = gesture
    }
}
