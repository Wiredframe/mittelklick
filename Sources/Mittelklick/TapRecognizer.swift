import Foundation
import MTBridge
import os

let log = Logger(subsystem: "de.wiredframe.mittelklick", category: "tap")

/// Recognizes a short tap with a given number of fingers, tracked per device.
final class TapRecognizer {
    /// Number of fingers for a middle click, 0 turns recognition off.
    var fingers: Int {
        get { lock.withLock { _fingers } }
        set { lock.withLock { _fingers = newValue; gestures.removeAll() } }
    }

    /// Drops unfinished gestures, e.g. when devices restart and the lift-off never arrives.
    func reset() {
        lock.withLock { gestures.removeAll() }
    }
    var onTap: (() -> Void)?
    /// Writes every finished gesture to the system log, category "tap".
    /// Turn on with `defaults write de.wiredframe.mittelklick debug -bool true` and relaunch.
    var debug = false

    private var _fingers = 4

    /// Fingers held longer than this are no longer a tap.
    private let maxDuration = 0.4
    /// Moving further than this (normalized, 1 = full width) counts as a swipe.
    private let maxMovement: Float = 0.04

    private struct Gesture {
        var start: Double
        var maxFingers = 0
        var origins: [Int32: (Float, Float)] = [:]
        var valid = true
    }

    private var gestures: [UInt64: Gesture] = [:]
    private let lock = NSLock()

    /// Contact states 4 (make touch) and 5 (touching); 1 to 3 are hovering, 6 to 8 lifting off.
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
                let result = isTap ? "middle click" : "nothing"
                log.notice("Gesture: \(gesture.maxFingers, privacy: .public) fingers, \(Int(duration * 1000), privacy: .public) ms, valid \(gesture.valid, privacy: .public): \(result, privacy: .public)")
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
