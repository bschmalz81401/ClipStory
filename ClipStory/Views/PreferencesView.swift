import SwiftUI

struct PreferencesView: View {

    @ObservedObject private var settings = AppSettings.shared
    let monitor: ClipboardMonitor

    var body: some View {
        Form {
            Section("History") {
                Stepper("Keep \(settings.historyLimit) items",
                        value: $settings.historyLimit,
                        in: 10...500,
                        step: 10)

                Toggle("Persist history across launches", isOn: $settings.persistHistory)
                    .onChange(of: settings.persistHistory) { enabled in
                        if !enabled { monitor.clearHistory() }
                    }
            }

            Section("Behaviour") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Privacy") {
                Button("Clear All History Now") {
                    monitor.clearHistory()
                }
                .foregroundStyle(.red)
            }

            Section("Hotkey") {
                Text("Clipboard picker: ⌘⇧V")
                    .foregroundStyle(.secondary)
                Text("To change, edit HotkeyManager.swift — defaultKeyCode / defaultModifiers.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}
