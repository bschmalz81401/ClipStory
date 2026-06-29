import SwiftUI

@main
struct ClipStoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows declared here; the app is fully menu-bar driven.
        // Preferences and picker panels are created imperatively by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
