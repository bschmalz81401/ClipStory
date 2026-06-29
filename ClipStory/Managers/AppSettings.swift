import Foundation
import ServiceManagement

// Single source of truth for user-configurable settings.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // MARK: - Keys

    private enum Key {
        static let historyLimit   = "historyLimit"
        static let persistHistory = "persistHistory"
        static let launchAtLogin  = "launchAtLogin"
        static let hotkeyKeyCode  = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
    }

    // MARK: - Published properties (UserDefaults-backed)

    @Published var historyLimit: Int {
        didSet { UserDefaults.standard.set(historyLimit, forKey: Key.historyLimit) }
    }

    @Published var persistHistory: Bool {
        didSet { UserDefaults.standard.set(persistHistory, forKey: Key.persistHistory) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Key.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    // Carbon virtual key code for the hotkey (default: V = 0x09).
    var hotkeyKeyCode: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: Key.hotkeyKeyCode)) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hotkeyKeyCode) }
    }

    // Carbon modifier flags (default: cmdKey | shiftKey).
    var hotkeyModifiers: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: Key.hotkeyModifiers)) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hotkeyModifiers) }
    }

    // MARK: - Init

    private init() {
        // Register defaults.
        let defaults: [String: Any] = [
            Key.historyLimit:    50,
            Key.persistHistory:  true,
            Key.launchAtLogin:   false,
            // V key = 0x09, Cmd+Shift = cmdKey(256) + shiftKey(512) = 768
            Key.hotkeyKeyCode:   0x09,
            Key.hotkeyModifiers: 768,
        ]
        UserDefaults.standard.register(defaults: defaults)

        historyLimit   = UserDefaults.standard.integer(forKey: Key.historyLimit)
        persistHistory = UserDefaults.standard.bool(forKey: Key.persistHistory)
        launchAtLogin  = UserDefaults.standard.bool(forKey: Key.launchAtLogin)
    }

    // MARK: - Launch at login

    private func applyLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enable {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                print("Launch-at-login error: \(error)")
            }
        }
    }
}
