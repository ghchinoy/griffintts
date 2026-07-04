import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Elevate the app's activation policy to a regular foreground GUI app!
        // This enables macOS keyboard focus (so you can click and type into the prompt text field),
        // makes the app appear in the Dock and Cmd+Tab App Switcher, and configures a standard menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct GriffinTTSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle("Griffin TTS")
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
