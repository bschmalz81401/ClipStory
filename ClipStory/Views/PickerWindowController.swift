import AppKit
import SwiftUI

// Manages the floating clipboard-picker panel.
//
// Panel style choices:
//   • NSPanel instead of NSWindow so it can appear over fullscreen apps.
//   • .nonactivatingPanel so it does NOT steal keyboard focus from the target
//     text field — the user can keep typing in their document.
//   • NSPanel with .nonactivatingPanel still receives key events via the
//     makeKey() call when we want to let the user navigate with arrow keys.

final class PickerWindowController: NSObject {

    private var panel: NSPanel!
    private let onDismiss: () -> Void
    private let monitor: ClipboardMonitor

    var isVisible: Bool { panel?.isVisible ?? false }

    init(monitor: ClipboardMonitor, onDismiss: @escaping () -> Void) {
        self.monitor   = monitor
        self.onDismiss = onDismiss
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        let view = PickerView(monitor: monitor) { [weak self] item in
            self?.select(item)
        } onDismiss: { [weak self] in
            self?.close()
        }

        let hosting = NSHostingController(rootView: view)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 360, height: 480)

        panel = NSPanel(
            contentRect:  hosting.view.frame,
            styleMask:    [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing:      .buffered,
            defer:        false
        )
        panel.titleVisibility         = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.contentViewController   = hosting
        panel.level                   = .popUpMenu
        panel.isOpaque                = false
        panel.backgroundColor         = .clear
        panel.hasShadow               = true
        panel.delegate                = self
    }

    // Shows the panel near the mouse cursor, nudging it on-screen if needed.
    func showAtMouse() {
        guard let screen = NSScreen.main else { return }
        var origin = NSEvent.mouseLocation
        // Offset so the panel appears just below and to the right of the cursor.
        origin.x += 4
        origin.y -= panel.frame.height + 4

        // Clamp to screen bounds.
        let screenFrame = screen.visibleFrame
        origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - panel.frame.width))
        origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - panel.frame.height))

        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        // Make key so the SwiftUI list can receive arrow-key navigation.
        panel.makeKey()
    }

    func close() {
        panel.orderOut(nil)
        onDismiss()
    }

    private func select(_ item: ClipboardItem) {
        monitor.putOnPasteboard(item)
        close()
        SyntheticPaste.send()
    }
}

extension PickerWindowController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Close when the user clicks outside the panel.
        close()
    }
}
