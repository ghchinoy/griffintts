import SwiftUI
import AVFoundation

// MARK: - ContentView
// Pure layout / UI state. All synthesis business logic lives in SynthesisCoordinator.
@MainActor
struct ContentView: View {
    @State private var prompt: String = "Hi there, I am Jibo, synthesized locally on macOS!"
    @State private var isNative: Bool = false
    @State private var speedFactor: Double = 1.0

    // Eye animation
    @State private var blinkScaleY: CGFloat = 1.0
    @State private var lookOffset: CGSize = .zero
    @State private var blinkTimer: Timer?

    // d4m.4: observe window active state to pause blinking when inactive
    @Environment(\.controlActiveState) private var controlActiveState

    @StateObject private var coordinator = SynthesisCoordinator()

    var body: some View {
        NavigationSplitView {
            // ── Sidebar: Speech Designer ───────────────────────────────
            SpeechDesignerPanel(
                prompt: $prompt,
                speedFactor: $speedFactor,
                isNative: $isNative,
                isSynthesizing: coordinator.isSynthesizing,
                audioPlayerIsPlaying: coordinator.audioPlayer?.isPlaying ?? false,
                onSpeak: triggerSynthesis,
                onStop: coordinator.stop
            )
            // Suppress the default centred system title; render our own flush-left.
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text("Speech Designer")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
            // min/ideal/max lets the user drag the gutter; sidebar grows with the window
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 480)
            // System sidebar toggle button intentionally kept — it's the standard
            // macOS control that collapses/expands the panel (Cmd+0).

        } detail: {
            // ── Detail: Jibo's Eye ─────────────────────────────────────
            ZStack(alignment: .bottom) {
                JiboEyeView(
                    blinkScaleY: blinkScaleY,
                    talkScale: coordinator.talkScale,
                    lookOffset: lookOffset
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        let cursorX = point.x - 200 // d4m.8: renamed cx→cursorX
                        let cursorY = point.y - 170 // d4m.8: renamed cy→cursorY
                        let dist = sqrt(cursorX * cursorX + cursorY * cursorY)
                        if dist > 0 {
                            let scale = min(dist * 0.1, 20)
                            lookOffset = CGSize(
                                width: cos(atan2(cursorY, cursorX)) * scale,
                                height: sin(atan2(cursorY, cursorX)) * scale
                            )
                        } else { lookOffset = .zero }
                    case .ended:
                        withAnimation(.spring()) { lookOffset = .zero }
                    }
                }

                // Bezel bar: status + speak + reset
                HStack(spacing: 10) {
                    Circle().fill(coordinator.statusColor.color).frame(width: 8, height: 8)
                    Text(coordinator.statusMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    if coordinator.isSynthesizing {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.6).frame(width: 16, height: 16)
                    }
                    Button(action: triggerSynthesis) {
                        Image(systemName: "megaphone.fill")
                            .foregroundColor(coordinator.isSynthesizing || prompt.isEmpty ? .gray : .white)
                    }
                    .buttonStyle(.plain)
                    .focusable() // d4m.7
                    .disabled(coordinator.isSynthesizing || prompt.isEmpty)
                    .help("Speak (⌘↩)")
                    .accessibilityLabel("Speak") // d4m.5

                    Button(action: resetEye) {
                        Image(systemName: "eye").foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .focusable() // d4m.7
                    .help("Reset Face")
                    .accessibilityLabel("Reset Face") // d4m.5
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            // Detail column has no fixed width — fills whatever remains after sidebar
            .toolbar(.hidden, for: .automatic)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .onAppear { startBlinking() }
        .onDisappear { blinkTimer?.invalidate(); coordinator.stop() }
        // d4m.4: pause blink timer when window goes inactive
        .onChange(of: controlActiveState) { _, newState in
            if newState == .active { startBlinking() } else {
                blinkTimer?.invalidate(); blinkTimer = nil
                withAnimation(.easeInOut(duration: 0.1)) { blinkScaleY = 1.0 }
            }
        }
        // Menu Bar routing
        .onReceive(NotificationCenter.default.publisher(for: .griffinSpeak)) { _ in
            triggerSynthesis()
        }
        .onReceive(NotificationCenter.default.publisher(for: .griffinStop)) { _ in
            coordinator.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .griffinToggleNative)) { _ in
            isNative.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .griffinClearPrompt)) { _ in
            prompt = ""
        }
    }

    // MARK: - Helpers
    private func resetEye() { lookOffset = .zero; blinkScaleY = 1.0 }

    private func startBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.05)) { blinkScaleY = 0.05 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.easeInOut(duration: 0.05)) { blinkScaleY = 1.0 }
                }
            }
        }
    }

    private func findProjectRoot() -> URL? {
        guard let exeURL = Bundle.main.executableURL else { return nil }
        var dir = exeURL.deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("AGENTS.md").path) { return dir }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    private func triggerSynthesis() {
        guard !coordinator.isSynthesizing && !prompt.isEmpty else { return }
        // d4m.8: renamed 't' → 'promptText' (in coordinator, variable is 'prompt' arg)
        let promptText = prompt
        logDebug("--- SYNTHESIS TRIGGERED: \"\(promptText)\" speed=\(speedFactor)x native=\(isNative)")
        coordinator.isSynthesizing = true
        coordinator.statusMessage = "Synthesizing..."
        coordinator.statusColor = .synthesizing
        guard let projectRoot = findProjectRoot() else {
            coordinator.statusMessage = "Project root not found!"
            coordinator.statusColor = .error
            coordinator.isSynthesizing = false
            return
        }
        Task { await coordinator.synthesize(prompt: promptText, isNative: isNative, speedFactor: speedFactor, projectRoot: projectRoot) }
    }
}
