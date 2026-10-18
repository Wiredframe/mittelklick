import AppKit
import ApplicationServices
import MTBridge
import ServiceManagement

/// Global because the C callback cannot carry any context.
private let recognizer = TapRecognizer()

private func onFrame(device: UInt64, touches: UnsafePointer<MKTouch>?, count: Int32, timestamp: Double) {
    guard let touches else { return }
    recognizer.handle(device: device, touches: UnsafeBufferPointer(start: touches, count: Int(count)), timestamp: timestamp)
}

private extension Notification.Name {
    static let devicesChanged = Notification.Name("de.wiredframe.mittelklick.devicesChanged")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let fnClick = FnClick()
    private let defaults = UserDefaults.standard
    private var trustTimer: Timer?
    private var restartWork: DispatchWorkItem?

    /// Fingers for a middle click on the trackpad, 0 = off.
    private var fingers: Int {
        get { defaults.object(forKey: "fingers") as? Int ?? 4 }
        set { defaults.set(newValue, forKey: "fingers"); recognizer.fingers = newValue }
    }
    private var fnEnabled: Bool {
        get { defaults.bool(forKey: "fnClick") }
        set { defaults.set(newValue, forKey: "fnClick"); applyFnClick() }
    }
    private var hideIcon: Bool {
        get { defaults.bool(forKey: "hideIcon") }
        set { defaults.set(newValue, forKey: "hideIcon"); statusItem.isVisible = !newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "Mittelklick")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.isVisible = !hideIcon

        recognizer.fingers = fingers
        recognizer.debug = defaults.bool(forKey: "debug")
        recognizer.onTap = {
            // Pressing with four fingers instead of tapping is already a left click, and palms can look like a tap
            // while typing. Only the time of the last click or key press is queried, never which key.
            func secondsSince(_ type: CGEventType) -> Double {
                CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
            }
            guard secondsSince(.leftMouseDown) > 0.5, secondsSince(.keyDown) > 0.5 else {
                if recognizer.debug { log.notice("Suppressed: clicked or typed just before") }
                return
            }
            Clicks.middleClick()
        }
        startTouches()

        // A Magic Trackpad connecting or disconnecting, or waking from sleep: rebuild the device list.
        mk_watch_devices { NotificationCenter.default.post(name: .devicesChanged, object: nil) }
        NotificationCenter.default.addObserver(forName: .devicesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.restartTouches(after: 1)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            self?.restartTouches(after: 2)
        }

        waitForTrust(prompt: true)
    }

    /// With the icon hidden, launching the app again (Finder, `open -a Mittelklick`) brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        hideIcon = false
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(.sectionHeader(title: String(localized: "Trackpad")))
        let options = [(String(localized: "Tap with three fingers"), 3),
                       (String(localized: "Tap with four fingers"), 4),
                       (String(localized: "Off"), 0)]
        for (title, count) in options {
            let item = menu.addItem(withTitle: title, action: #selector(setFingers(_:)), keyEquivalent: "")
            item.target = self
            item.tag = count
            item.state = fingers == count ? .on : .off
        }
        menu.addItem(.separator())
        let fn = menu.addItem(withTitle: String(localized: "Fn + click as middle click"), action: #selector(toggleFn),
                              keyEquivalent: "")
        fn.target = self
        fn.state = fnEnabled ? .on : .off
        menu.addItem(.separator())
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: String(localized: "Allow Accessibility …"), action: #selector(openAccessibility),
                         keyEquivalent: "").target = self
        }
        let login = menu.addItem(withTitle: String(localized: "Launch at Login"), action: #selector(toggleLogin),
                                 keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let hide = menu.addItem(withTitle: String(localized: "Hide Menu Bar Icon"), action: #selector(hideStatusItem),
                                keyEquivalent: "")
        hide.target = self
        hide.toolTip = String(localized: "Launch Mittelklick again from the Finder to bring it back.")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Mittelklick"), action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
    }

    private func startTouches() {
        recognizer.reset()
        if mk_start(onFrame) < 0 { log.error("MultitouchSupport not available") }
    }

    /// Several notifications in quick succession (one device shows up via several drivers) cause a single restart.
    private func restartTouches(after delay: TimeInterval) {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startTouches() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Posting clicks and catching Fn only work once Accessibility is granted, so keep checking until then.
    private func waitForTrust(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            applyFnClick()
            return
        }
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.applyFnClick()
        }
    }

    private func applyFnClick() {
        if fnEnabled, AXIsProcessTrusted() { fnClick.start() } else { fnClick.stop() }
    }

    @objc private func setFingers(_ sender: NSMenuItem) {
        fingers = sender.tag
    }

    @objc private func toggleFn() {
        fnEnabled.toggle()
    }

    @objc private func openAccessibility() {
        waitForTrust(prompt: false)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func hideStatusItem() {
        hideIcon = true
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("Could not change login item: \(error, privacy: .public)")
        }
    }
}
