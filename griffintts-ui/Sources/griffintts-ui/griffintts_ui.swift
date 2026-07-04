import SwiftUI

@main
struct GriffinTTSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle("Griffin TTS")
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
