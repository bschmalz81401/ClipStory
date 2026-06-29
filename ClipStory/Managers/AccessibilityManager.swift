import AppKit
import ApplicationServices

// Checks whether ClipStory has been granted Accessibility (AX) permission,
// and if not, prompts the user to enable it in System Settings.
//
// AX permission is required for:
//   • CGEvent synthesis (the synthetic Cmd+V paste after picker selection)
//   • Some CGEventTap configurations
// The Carbon RegisterEventHotKey path does NOT require AX permission.

final class AccessibilityManager {

    static let shared = AccessibilityManager()
    private init() {}

    var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    // Called on launch.  If permission is already granted, this is a no-op.
    // If not, shows a one-time alert explaining why it's needed, then opens
    // System Settings so the user can grant it.
    func requestIfNeeded() {
        guard !hasPermission else { return }

        // Passing `prompt: true` to AXIsProcessTrustedWithOptions causes macOS to
        // open the System Settings panel automatically; however the user experience
        // is better with our own explanatory alert first.
        let alert = NSAlert()
        alert.messageText     = "Accessibility Permission Required"
        alert.informativeText = """
ClipStory needs Accessibility access to paste clipboard items into other apps \
using a synthetic keyboard shortcut (⌘V).

Click "Open System Settings" to grant access, then enable ClipStory in \
Privacy & Security > Accessibility.
"""
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
