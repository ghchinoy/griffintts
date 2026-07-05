import SwiftUI
import AVFoundation

// MARK: - Token Timing Types
struct TokenTime: Codable {
    let name: String
    let start: Double
    let end: Double
}
struct TokenTimesWrapper: Codable { let tokens: [TokenTime] }
struct TokenTimesResponse: Codable { let tokentimes: TokenTimesWrapper }

// MARK: - Logging
func logDebug(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    print("[\(formatter.string(from: Date()))] [GriffinUI] \(message)")
    fflush(stdout)
}

// MARK: - ContentView
// Uses NavigationSplitView for a proper macOS sidebar/detail split.
// The sidebar is the Speech Designer panel; the detail column is Jibo's face.
// This gives us:
//   • Standard macOS split-view chrome and collapse button for free
//   • No custom WindowResizer / AppKit bridge needed (no crash vector)
//   • Starts with sidebar visible (sidebarIsShown default)
@MainActor
struct ContentView: View {
    // Shared state — single source of truth passed as bindings to the panel
    @State private var prompt: String = "Hi there, I am Jibo, synthesized locally on macOS!"
    @State private var isNative: Bool = false
    @State private var isSynthesizing: Bool = false
    @State private var statusMessage: String = "Jibo ready"
    @State private var statusColor: Color = .green
    @State private var speedFactor: Double = 1.0

    // Eye animation
    @State private var blinkScaleY: CGFloat = 1.0
    @State private var talkScale: CGFloat = 1.0
    @State private var lookOffset: CGSize = .zero

    // Audio / timers
    @State private var audioPlayer: AVAudioPlayer?
    @State private var animationTimer: Timer?
    @State private var blinkTimer: Timer?
    @State private var isFirstTick: Bool = true

    var body: some View {
        NavigationSplitView {
            // ── Sidebar: Speech Designer Panel ────────────────────────
            SpeechDesignerPanel(
                prompt: $prompt,
                speedFactor: $speedFactor,
                isNative: $isNative,
                isSynthesizing: $isSynthesizing,
                audioPlayer: $audioPlayer,
                onSpeak: triggerSynthesis,
                onStop: triggerStop
            )
            // Remove the sidebar toolbar / navigation title chrome
            .navigationSplitViewColumnWidth(min: 280, ideal: 310, max: 380)
            .toolbar(removing: .sidebarToggle)

        } detail: {
            // ── Detail: Jibo's Face ────────────────────────────────────
            VStack(spacing: 0) {
                // Eye bezel (fills the detail column)
                ZStack(alignment: .bottom) {
                    JiboEyeView(
                        blinkScaleY: blinkScaleY,
                        talkScale: talkScale,
                        lookOffset: lookOffset
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            let cx = point.x - 200, cy = point.y - 170
                            let dist = sqrt(cx*cx + cy*cy)
                            if dist > 0 {
                                let angle = atan2(cy, cx)
                                let scale = min(dist * 0.1, 20)
                                lookOffset = CGSize(width: cos(angle)*scale, height: sin(angle)*scale)
                            } else { lookOffset = .zero }
                        case .ended:
                            withAnimation(.spring()) { lookOffset = .zero }
                        }
                    }

                    // ── Compact status bar + speak button ─────────────
                    // The prompt lives in the sidebar. When the sidebar is
                    // collapsed, the user can still trigger speech with the
                    // megaphone button here (the prompt binding remains live).
                    HStack(spacing: 10) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(statusMessage)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        if isSynthesizing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        }
                        // Speak button — always accessible even when sidebar collapsed
                        Button(action: triggerSynthesis) {
                            Image(systemName: "megaphone.fill")
                                .foregroundColor(isSynthesizing || prompt.isEmpty ? .gray : .white)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSynthesizing || prompt.isEmpty)
                        .help("Speak (⌘↩)")

                        // Reset eye geometry
                        Button(action: resetEye) {
                            Image(systemName: "eye")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                        .help("Reset Face")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }
            }
            // Remove the default navigation toolbar in the detail column
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .automatic)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .onAppear { startBlinking() }
        .onDisappear {
            blinkTimer?.invalidate()
            animationTimer?.invalidate()
        }
        // ── Menu Bar command receivers ─────────────────────────────────
        .onReceive(NotificationCenter.default.publisher(for: .griffinSpeak))        { _ in triggerSynthesis() }
        .onReceive(NotificationCenter.default.publisher(for: .griffinStop))         { _ in triggerStop() }
        .onReceive(NotificationCenter.default.publisher(for: .griffinToggleNative)) { _ in isNative.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: .griffinClearPrompt))  { _ in prompt = "" }
    }

    // MARK: - Actions

    private func resetEye() {
        lookOffset = .zero; talkScale = 1.0; blinkScaleY = 1.0
    }

    private func startBlinking() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.05)) { blinkScaleY = 0.05 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.easeInOut(duration: 0.05)) { blinkScaleY = 1.0 }
                }
            }
        }
    }

    // /tts_stop — confirmed working (ykr.6): HTTP 200, halts PCM growth
    func triggerStop() {
        audioPlayer?.stop()
        audioPlayer = nil
        animationTimer?.invalidate()
        statusMessage = "Jibo idle"
        statusColor = .green
        withAnimation(.spring()) { talkScale = 1.0 }
        Task {
            guard let url = URL(string: "http://localhost:8089/tts_stop") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            logDebug("[Stop] Firing /tts_stop...")
            _ = try? await URLSession.shared.data(for: req)
            logDebug("[Stop] /tts_stop sent.")
        }
    }

    // MARK: - findProjectRoot
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

    // MARK: - Synthesis
    func triggerSynthesis() {
        guard !isSynthesizing && !prompt.isEmpty else { return }
        logDebug("--- SYNTHESIS TRIGGERED: \"\(prompt)\" speed=\(speedFactor)x native=\(isNative)")
        isSynthesizing = true
        statusMessage = "Synthesizing..."
        statusColor = .orange
        let t = prompt, native = isNative, speed = speedFactor
        let wavPath = "/tmp/griffintts-ui.wav"
        Task {
            guard let projectRoot = findProjectRoot() else {
                statusMessage = "Project root not found!"; statusColor = .red; isSynthesizing = false; return
            }
            var timings: [TokenTime] = []
            if !native { timings = await fetchTokenTimings(text: t) }
            logDebug("[Timing] \(timings.count) tokens received.")
            var speechDuration: Double = 0.0
            if let last = timings.last { speechDuration = (last.end / speed) + 0.40 }
            let ttsBin = projectRoot.appendingPathComponent("tools/bin/griffintts").path
            var finalArgs = ["--ow", wavPath]
            if native { finalArgs.append("--native") }
            else if speechDuration > 0 { finalArgs.append(contentsOf: ["--duration", String(format: "%.2f", speechDuration)]) }
            finalArgs.append(contentsOf: ["--speed", String(format: "%.2f", speed)])
            finalArgs.append(t)
            logDebug("[Subprocess] \(ttsBin) \(finalArgs.joined(separator: " "))")
            let success = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                let argsToPass = finalArgs
                let currentDir = projectRoot
                DispatchQueue.global(qos: .userInitiated).async {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: ttsBin)
                    task.arguments = argsToPass
                    task.currentDirectoryURL = currentDir
                    task.standardError = Pipe()
                    do { try task.run(); task.waitUntilExit(); cont.resume(returning: task.terminationStatus == 0) }
                    catch { cont.resume(returning: false) }
                }
            }
            logDebug("[Subprocess] Completed. Success: \(success)")
            if !success { statusMessage = "Synthesis failed!"; statusColor = .red; isSynthesizing = false; return }
            statusMessage = "Speaking..."; statusColor = .blue; isSynthesizing = false
            playAudio(path: wavPath, timings: timings, speed: speed)
        }
    }

    // MARK: - Timings
    private func fetchTokenTimings(text: String) async -> [TokenTime] {
        guard let url = URL(string: "http://localhost:8089/tts_token_times") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = ["prompt": text, "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return [] }
        req.httpBody = body
        do {
            logDebug("[Timing] Fetching token times...")
            let (data, _) = try await URLSession.shared.data(for: req)
            logDebug("[Timing] Response received.")
            if let resp = try? JSONDecoder().decode(TokenTimesResponse.self, from: data) { return resp.tokentimes.tokens }
        } catch { logDebug("[Timing] Error: \(error)") }
        return []
    }

    // MARK: - Audio + Animation
    private func playAudio(path: String, timings: [TokenTime], speed: Double) {
        let url = URL(fileURLWithPath: path)
        do {
            logDebug("[Audio] Loading \(path)")
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            let sz = (try? Data(contentsOf: url).count) ?? 0
            logDebug("[Audio] \(sz) bytes. Preparing...")
            audioPlayer?.prepareToPlay()
            isFirstTick = true
            audioPlayer?.play()
            logDebug("[Audio] play() called.")
            if !timings.isEmpty { animateMouthSyncWithTokens(timings: timings, speed: speed) }
            else { animateMouthSyncFallback(speed: speed) }
        } catch {
            statusMessage = "Audio play failed"; statusColor = .red
            logDebug("[Audio] Error: \(error)")
        }
    }

    private func animateMouthSyncWithTokens(timings: [TokenTime], speed: Double) {
        animationTimer?.invalidate()
        let t0 = Date()
        logDebug("[Animation] Token-based, speed=\(speed)x")
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let sys = Date().timeIntervalSince(t0)
            Task { @MainActor in
                guard let player = self.audioPlayer, player.isPlaying else {
                    self.animationTimer?.invalidate()
                    self.statusMessage = "Jibo idle"; self.statusColor = .green
                    withAnimation(.spring()) { self.talkScale = 1.0 }
                    logDebug("[Animation] Complete (\(String(format: "%.2f", sys))s elapsed).")
                    return
                }
                let elapsed = (player.currentTime - 0.35) * speed
                if self.isFirstTick {
                    self.isFirstTick = false
                    logDebug("[Animation] First tick. sys=\(String(format: "%.3f", sys))s elapsed(scaled)=\(String(format: "%.3f", elapsed))s")
                }
                var speaking = false
                if elapsed >= 0 {
                    for tok in timings where elapsed >= tok.start && elapsed <= tok.end + 0.05 { speaking = true; break }
                }
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    self.talkScale = speaking ? CGFloat(1.0 + 0.15 * sin(elapsed * 40.0)) : 1.0
                }
            }
        }
    }

    private func animateMouthSyncFallback(speed: Double) {
        animationTimer?.invalidate()
        let t0 = Date()
        logDebug("[Animation] Procedural fallback, speed=\(speed)x")
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let sys = Date().timeIntervalSince(t0)
            Task { @MainActor in
                guard let player = self.audioPlayer, player.isPlaying else {
                    self.animationTimer?.invalidate()
                    self.statusMessage = "Jibo idle"; self.statusColor = .green
                    withAnimation(.spring()) { self.talkScale = 1.0 }
                    logDebug("[Animation] Fallback complete (\(String(format: "%.2f", sys))s).")
                    return
                }
                let elapsed = (player.currentTime - 0.35) * speed
                if self.isFirstTick {
                    self.isFirstTick = false
                    logDebug("[Animation] First fallback tick. sys=\(String(format: "%.3f", sys))s elapsed(scaled)=\(String(format: "%.3f", elapsed))s")
                }
                if elapsed >= 0 {
                    let pulse = 1.0 + 0.18 * sin(elapsed * 22.0) * cos(elapsed * 8.0)
                    withAnimation(.spring(response: 0.12, dampingFraction: 0.55)) {
                        self.talkScale = pulse > 0.95 ? CGFloat(pulse) : 1.0
                    }
                } else {
                    withAnimation(.spring()) { self.talkScale = 1.0 }
                }
            }
        }
    }
}
