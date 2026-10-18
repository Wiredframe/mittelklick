import AppKit
import ApplicationServices
import MTBridge
import ServiceManagement

/// Global, weil der Rückruf aus C keinen Kontext mitnehmen kann.
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

    /// Finger für den Mittelklick per Trackpad, 0 = aus.
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
        recognizer.onTap = { Clicks.middleClick() }
        startTouches()

        // Neue oder getrennte Geräte (Magic Trackpad) und Aufwachen: Geräteliste neu aufbauen.
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

    /// Bei ausgeblendetem Symbol bringt ein erneuter Start (Finder, `open -a Mittelklick`) es zurück.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        hideIcon = false
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(.sectionHeader(title: "Trackpad"))
        for (title, count) in [("Mit drei Fingern tippen", 3), ("Mit vier Fingern tippen", 4), ("Aus", 0)] {
            let item = menu.addItem(withTitle: title, action: #selector(setFingers(_:)), keyEquivalent: "")
            item.target = self
            item.tag = count
            item.state = fingers == count ? .on : .off
        }
        menu.addItem(.separator())
        let fn = menu.addItem(withTitle: "Fn und Linksklick als Mittelklick", action: #selector(toggleFn), keyEquivalent: "")
        fn.target = self
        fn.state = fnEnabled ? .on : .off
        menu.addItem(.separator())
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "Bedienungshilfen erlauben …", action: #selector(openAccessibility), keyEquivalent: "")
                .target = self
        }
        let login = menu.addItem(withTitle: "Beim Anmelden starten", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let hide = menu.addItem(withTitle: "Symbol ausblenden", action: #selector(hideStatusItem), keyEquivalent: "")
        hide.target = self
        hide.toolTip = "Zurück holt es ein erneuter Start von Mittelklick im Finder."
        menu.addItem(.separator())
        menu.addItem(withTitle: "Mittelklick beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func startTouches() {
        if mk_start(onFrame) < 0 { NSLog("Mittelklick: MultitouchSupport nicht verfügbar") }
    }

    private func restartTouches(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.startTouches() }
    }

    /// Klicks senden und Fn abfangen geht erst mit Bedienungshilfen-Freigabe, bis dahin wird nachgefragt.
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
        waitForTrust(prompt: true)
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
            NSLog("Mittelklick: Anmeldeobjekt nicht änderbar: \(error)")
        }
    }
}
