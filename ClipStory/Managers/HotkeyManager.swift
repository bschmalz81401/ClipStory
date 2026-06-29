import Carbon
import AppKit

// Registers a global hotkey using the Carbon RegisterEventHotKey API.
//
// Why Carbon and not CGEventTap?
//   RegisterEventHotKey is simpler, works without a full event tap, and does
//   not require the app to be frontmost or to install a system-level tap that
//   needs additional entitlements scrutiny.  The trade-off is that Carbon hotkeys
//   are exclusive — another app using the same combination will conflict.  For a
//   user-facing clipboard manager this is acceptable; the combination is configurable.

final class HotkeyManager {

    static let shared = HotkeyManager()

    // ── Hotkey definition ──────────────────────────────────────────────────────
    // Change these two constants to remap the shortcut app-wide.  Carbon key
    // codes: V = 0x09.  Carbon modifier masks: cmdKey = 1<<8, shiftKey = 1<<9.
    private static let defaultKeyCode:   UInt32 = 0x09          // V
    private static let defaultModifiers: UInt32 = UInt32(cmdKey | shiftKey)
    // ──────────────────────────────────────────────────────────────────────────

    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?
    // Retain the EventHandlerRef so Carbon doesn't deallocate it.
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    // Registers the hotkey and stores the callback.  Call once at launch.
    func register(callback: @escaping () -> Void) {
        self.handler = callback

        let settings = AppSettings.shared
        let keyCode  = settings.hotkeyKeyCode  != 0 ? settings.hotkeyKeyCode  : HotkeyManager.defaultKeyCode
        let mods     = settings.hotkeyModifiers != 0 ? settings.hotkeyModifiers : HotkeyManager.defaultModifiers

        // Install a Carbon event handler on the application event target.
        // The handler is a C-compatible closure captured by bridging through
        // the shared singleton's Unmanaged pointer.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind:  OSType(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                // userData is the HotkeyManager pointer.
                guard let ptr = userData else { return noErr }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
                mgr.handler?()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        // Assign hotkey ID 1 (arbitrary; must be unique among registered hotkeys).
        let hotkeyID = EventHotKeyID(signature: OSType(0x434C5053), // 'CLPS'
                                     id: 1)
        RegisterEventHotKey(keyCode, mods, hotkeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }

    // Re-registers with updated key/mods from AppSettings (call from Preferences).
    func reregister(callback: @escaping () -> Void) {
        unregister()
        register(callback: callback)
    }
}
