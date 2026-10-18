import CoreGraphics

enum Clicks {
    /// Sendet einen Mittelklick an der aktuellen Zeigerposition.
    static func middleClick() {
        let location = CGEvent(source: nil)?.location ?? .zero
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .center)
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Macht aus Fn + Linksklick einen Mittelklick, einschließlich Ziehen.
final class FnClick {
    private var tap: CFMachPort?
    private var converting = false

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            let fnClick = Unmanaged<FnClick>.fromOpaque(refcon!).takeUnretainedValue()
            return fnClick.process(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        self.tap = nil
        converting = false
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown where event.flags.contains(.maskSecondaryFn):
            converting = true
            convert(event, to: .otherMouseDown)
        case .leftMouseDragged where converting:
            convert(event, to: .otherMouseDragged)
        case .leftMouseUp where converting:
            converting = false
            convert(event, to: .otherMouseUp)
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func convert(_ event: CGEvent, to type: CGEventType) {
        event.type = type
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(CGMouseButton.center.rawValue))
        event.flags.remove(.maskSecondaryFn)
    }
}
