import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ── Dock menu (d4m.6) ──────────────────────────────────────────────
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let speakItem = NSMenuItem(
            title: "Speak Last Prompt",
            action: #selector(dockSpeak),
            keyEquivalent: ""
        )
        speakItem.target = self
        menu.addItem(speakItem)

        let stopItem = NSMenuItem(
            title: "Stop",
            action: #selector(dockStop),
            keyEquivalent: ""
        )
        stopItem.target = self
        menu.addItem(stopItem)

        return menu
    }

    @objc private func dockSpeak() {
        NotificationCenter.default.post(name: .griffinSpeak, object: nil)
    }

    @objc private func dockStop() {
        NotificationCenter.default.post(name: .griffinStop, object: nil)
    }
}

// swiftlint:disable:next menu_bar_check
@main
struct GriffinTTSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle("GriffinTTS")
        }
        // d4m.3: Use default window style (removes HiddenTitleBarWindowStyle).
        // This restores the standard drag handle, traffic-light buttons, and
        // full-screen zoom. The NavigationSplitView provides its own chrome.
        //
        // d4m.1: Constrain to content size so the window cannot collapse to zero.
        .windowResizability(.contentSize)
        // d4m.1: Set a sensible default launch size.
        .defaultSize(width: 780, height: 520)
        // ── Native macOS Menu Bar (HIG: all commands must be menu-discoverable)
        .commands {
            CommandGroup(replacing: .newItem) {}

            // d4m.2: Standard Cmd+W close shortcut
            CommandGroup(after: .windowArrangement) {
                Button("Close Window") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

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
}
