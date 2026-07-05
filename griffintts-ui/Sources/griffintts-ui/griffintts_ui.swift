import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Elevate the app's activation policy to a regular foreground GUI app.
        // Enables keyboard focus, Dock presence, and App Switcher integration.
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
                .navigationTitle("GriffinTTS")
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        // ── Native macOS Menu Bar (HIG: all commands must be menu-discoverable) ──
        .commands {
            // Remove the default Edit > New Window command that doesn't apply
            CommandGroup(replacing: .newItem) {}

            // Jibo Speech menu
            CommandMenu("Speech") {
                Button("Speak") {
                    NotificationCenter.default.post(name: .griffinSpeak, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Stop") {
                    NotificationCenter.default.post(name: .griffinStop, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                Button("Toggle Native Mode") {
                    NotificationCenter.default.post(name: .griffinToggleNative, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Clear Prompt") {
                    NotificationCenter.default.post(name: .griffinClearPrompt, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Toggle Speech Designer Panel") {
                    NotificationCenter.default.post(name: .griffinToggleDrawer, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
        }
    }
}

// MARK: - Notification names for Menu Bar → ContentView command routing
extension Notification.Name {
    static let griffinSpeak        = Notification.Name("griffinSpeak")
    static let griffinStop         = Notification.Name("griffinStop")
    static let griffinToggleNative = Notification.Name("griffinToggleNative")
    static let griffinClearPrompt  = Notification.Name("griffinClearPrompt")
    static let griffinToggleDrawer = Notification.Name("griffinToggleDrawer")
}
