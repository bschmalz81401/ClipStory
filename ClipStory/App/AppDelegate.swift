import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Owned objects

    private var statusItem: NSStatusItem!
    private let monitor = ClipboardMonitor.shared
    private let hotkey  = HotkeyManager.shared
    private var pickerController: PickerWindowController?
    private var prefsWindow: NSWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the Dock icon programmatically as a belt-and-suspenders measure on
        // top of LSUIElement in Info.plist.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        monitor.start()

        // Check Accessibility on launch so the user is prompted immediately.
        AccessibilityManager.shared.requestIfNeeded()

        // Register Cmd+Shift+V.  The hotkey constant lives in HotkeyManager so
        // there is exactly one place to change it.
        hotkey.register { [weak self] in
            self?.togglePicker()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotkey.unregister()
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipStory")
            button.action = #selector(statusBarClicked(_:))
            button.target = self
        }
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: "Open Clipboard History", action: #selector(openPicker), keyEquivalent: "")
        menu.addItem(.separator())

        let recentHeader = NSMenuItem(title: "Recent Items", action: nil, keyEquivalent: "")
        recentHeader.isEnabled = false
        menu.addItem(recentHeader)

        // Show top 5 items inline.
        for item in monitor.history.prefix(5) {
            let title: String
            switch item.content {
            case .text(let s, _):
                let snippet = s.trimmingCharacters(in: .whitespacesAndNewlines)
                title = String(snippet.prefix(60))
            case .image:
                title = "📷 Image"
            }
            let menuItem = NSMenuItem(title: title.isEmpty ? "(empty)" : title, action: #selector(pasteFromMenu(_:)), keyEquivalent: "")
            menuItem.representedObject = item.id.uuidString
            menuItem.target = self
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipStory", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func statusBarClicked(_ sender: Any) {
        // Menu appears automatically; rebuild it with fresh items.
        buildMenu()
    }

    // MARK: - Picker

    @objc private func openPicker() {
        togglePicker()
    }

    func togglePicker() {
        if let ctrl = pickerController, ctrl.isVisible {
            ctrl.close()
            pickerController = nil
            return
        }
        let ctrl = PickerWindowController(monitor: monitor) { [weak self] in
            self?.pickerController = nil
        }
        pickerController = ctrl
        ctrl.showAtMouse()
    }

    // MARK: - Menu actions

    @objc private func pasteFromMenu(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let uuid  = UUID(uuidString: idStr),
              let item  = monitor.history.first(where: { $0.id == uuid }) else { return }
        monitor.putOnPasteboard(item)
        SyntheticPaste.send()
    }

    @objc private func clearHistory() {
        monitor.clearHistory()
        buildMenu()
    }

    @objc private func openPreferences() {
        if prefsWindow == nil {
            let view = PreferencesView(monitor: monitor)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "ClipStory Preferences"
            win.styleMask = [.titled, .closable]
            win.setContentSize(NSSize(width: 420, height: 320))
            win.center()
            win.isReleasedWhenClosed = false
            prefsWindow = win
        }
        prefsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
