import CoreGraphics
import Carbon

// Synthesises a Cmd+V key event directed at the current frontmost application.
//
// How it works:
//   1. Create a CGEvent for the V key (keyCode 9) with the command modifier.
//   2. Post keyDown then keyUp to the HID event stream.
//   3. The frontmost app receives the events and performs its paste action.
//
// Why CGEvent and not AppleScript/NSApp.sendAction?
//   CGEvent works across all apps (native, Electron, web browsers) without needing
//   a per-app hook.  It requires the Accessibility permission granted in System
//   Settings; if that permission is missing the events are silently dropped.
//
// A brief delay (0.05 s) before posting lets the picker panel fully close and
// the target app regain focus so the paste lands in the right field.

enum SyntheticPaste {

    static func send() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            post(keyDown: true)
            post(keyDown: false)
        }
    }

    private static func post(keyDown: Bool) {
        // V key virtual key code = 9 (kVK_ANSI_V)
        let src = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: keyDown) else { return }
        event.flags = .maskCommand
        event.post(tap: .cghidEventTap)
    }
}
