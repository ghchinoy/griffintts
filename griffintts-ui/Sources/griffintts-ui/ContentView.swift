import SwiftUI
import AVFoundation

struct TokenTime: Codable {
    let name: String
    let start: Double
    let end: Double
}

typealias TokenTimesList = [TokenTime]

struct TokenTimesWrapper: Codable {
    let tokens: TokenTimesList
}

struct TokenTimesResponse: Codable {
    let tokentimes: TokenTimesWrapper
}

// Global High-Resolution Logging Helper
func logDebug(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let timestamp = formatter.string(from: Date())
    print("[\(timestamp)] [GriffinUI] \(message)")
    fflush(stdout) // Ensure logs flush immediately to stdout
}

@MainActor
struct ContentView: View {
    @State private var prompt: String = "Hi there, I am Jibo, synthesized locally on macOS!"
    @State private var isNative: Bool = false
    @State private var isSynthesizing: Bool = false
    @State private var statusMessage: String = "Jibo ready"
    @State private var statusColor: Color = .green
    
    // Expressive Parametric Controls (jibo-6yu.3)
    @State private var speedFactor: Double = 1.0
    
    // Eye state variables
    @State private var blinkScaleY: CGFloat = 1.0
    @State private var talkScale: CGFloat = 1.0
    @State private var lookOffset: CGSize = .zero
    
    @State private var audioPlayer: AVAudioPlayer?
    @State private var animationTimer: Timer?
    @State private var blinkTimer: Timer?
    
    // Concurrency-safe State for Tracking First Active Animation Tick
    @State private var isFirstTick: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Jibo Face Bezel View
            ZStack(alignment: .bottom) {
                JiboEyeView(
                    blinkScaleY: blinkScaleY,
                    talkScale: talkScale,
                    lookOffset: lookOffset
                )
                // Mouse-tracking hover overlay
                .background(Color(white: 0.01))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        // Calculate offset of pupil relative to center of a 400x400 face area
                        let cx = point.x - 200
                        let cy = point.y - 200
                        let dist = sqrt(cx*cx + cy*cy)
                        let maxOffset: CGFloat = 20
                        
                        if dist > 0 {
                            let angle = atan2(cy, cx)
                            let scale = min(dist * 0.1, maxOffset)
                            lookOffset = CGSize(
                                width: cos(angle) * scale,
                                height: sin(angle) * scale
                            )
                        } else {
                            lookOffset = .zero
                        }
                    case .ended:
                        // Return to center when mouse leaves
                        withAnimation(.spring()) {
                            lookOffset = .zero
                        }
                    }
                }
                
                // Status Bezel Bar
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                    if isSynthesizing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.8))
            }
            .frame(height: 340)
            
            // Controller / Input Panel
            VStack(spacing: 12) {
                // Text input field
                HStack(spacing: 8) {
                    TextField("What should Jibo say?", text: $prompt, onCommit: {
                        triggerSynthesis()
                    })
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(Color(white: 0.15))
                    .cornerRadius(6)
                    .foregroundColor(.white)
                    .font(.system(.body, design: .rounded))
                    
                    Button(action: triggerSynthesis) {
                        Image(systemName: "megaphone.fill")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .disabled(isSynthesizing || prompt.isEmpty)
                }
                
                // Speed Factor Slider (jibo-6yu.3)
                HStack(spacing: 12) {
                    Image(systemName: "gauge.with.needle.fill")
                        .foregroundColor(.gray)
                    Text("Speed:")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 45, alignment: .leading)
                    Slider(value: $speedFactor, in: 0.5...2.0, step: 0.1) {
                        Text("Speed")
                    }
                    .accentColor(.blue)
                    
                    Text(String(format: "%.1fx", speedFactor))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(width: 35, alignment: .trailing)
                }
                .padding(.top, 4)
                
                // Configuration Toggles
                HStack {
                    Toggle(isOn: $isNative) {
                        Text("Standalone Native Mode (en_us)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .toggleStyle(CheckboxToggleStyle())
                    
                    Spacer()
                    
                    Button(action: resetEye) {
                        Text("Reset Face")
                            .font(.caption)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding(16)
            .background(Color(white: 0.08))
        }
        .frame(width: 400, height: 440)
        .preferredColorScheme(.dark)
        .onAppear {
            startBlinking()
        }
        .onDisappear {
            blinkTimer?.invalidate()
            animationTimer?.invalidate()
        }
    }
    
    private func resetEye() {
        lookOffset = .zero
        talkScale = 1.0
        blinkScaleY = 1.0
    }
    
    private func startBlinking() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            // Execute eye blink (scale down, sleep, scale up) on MainActor
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.05)) {
                    blinkScaleY = 0.05
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.easeInOut(duration: 0.05)) {
                        blinkScaleY = 1.0
                    }
                }
            }
        }
    }
    
    private func findProjectRoot() -> URL? {
        // Start at the current executable's directory
        guard let exeURL = Bundle.main.executableURL else { return nil }
        var dir = exeURL.deletingLastPathComponent()
        
        // Walk up the filesystem hierarchy (limit to 10 levels to prevent infinite loops)
        for _ in 0..<10 {
            let agentsMd = dir.appendingPathComponent("AGENTS.md")
            if FileManager.default.fileExists(atPath: agentsMd.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { // Reached root /
                break
            }
            dir = parent
        }
        return nil
    }
    
    private func triggerSynthesis() {
        guard !isSynthesizing && !prompt.isEmpty else { return }
        
        logDebug("--- NEW SYNTHESIS RUN TRIGGERED ---")
        logDebug("Prompt text: \"\(prompt)\"")
        logDebug("Is Native: \(isNative)")
        logDebug("Speed Factor: \(speedFactor)")
        
        isSynthesizing = true
        statusMessage = "Synthesizing..."
        statusColor = .orange
        
        let t = prompt
        let native = isNative
        let speed = speedFactor
        let wavPath = "/tmp/griffintts-ui.wav"
        
        Task {
            // Find Jibo project root directory dynamically
            guard let projectRoot = findProjectRoot() else {
                statusMessage = "Project root not found!"
                statusColor = .red
                isSynthesizing = false
                logDebug("[Error] Failed to dynamically locate Jibo project root directory.")
                return
            }
            logDebug("[Environment] Located project root: \(projectRoot.path)")
            
            // 1. FETCH TIMINGS FIRST (Takes only ~100ms, completely imperceptible!)
            logDebug("[Timing] Fetching token timings from container...")
            var timings: [TokenTime] = []
            if !native {
                // Adjust timings endpoint query context if we change timings in future
                timings = await fetchTokenTimings(text: t)
            }
            logDebug("[Timing] Timings fetched. Received \(timings.count) tokens.")
            
            // Calculate exact speech duration (end of last token + 350ms silence + 50ms comfort padding)
            // If speed is not 1.0, the synthesized duration is divided by the speed factor!
            var speechDuration: Double = 0.0
            if let lastToken = timings.last {
                speechDuration = (lastToken.end / speed) + 0.40
                logDebug("[Timing] Calculated exact audio duration: \(String(format: "%.3f", speechDuration))s (Last Token: '\(lastToken.name)' ends at \(lastToken.end)s, scaled by speed \(speed))")
            }
            
            // 2. RUN CLI SUBPROCESS WITH EXPLICIT DURATION AND SPEED FLAGS!
            let ttsBin = projectRoot.appendingPathComponent("tools/bin/griffintts").path
            
            var finalArgs = ["--ow", wavPath]
            if native {
                finalArgs.append("--native")
            } else if speechDuration > 0.0 {
                finalArgs.append("--duration")
                finalArgs.append(String(format: "%.2f", speechDuration))
            }
            
            // Pass the speed parameter natively to the backend (jibo-6yu.3)
            finalArgs.append("--speed")
            finalArgs.append(String(format: "%.2f", speed))
            
            finalArgs.append(t)
            
            logDebug("[Subprocess] Spawning Go CLI subprocess: \(ttsBin) \(finalArgs.joined(separator: " "))")
            let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                // Isolated, non-capturing background thread execution to prevent warnings
                let argsToPass = finalArgs
                let currentDir = projectRoot
                DispatchQueue.global(qos: .userInitiated).async {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: ttsBin)
                    task.arguments = argsToPass
                    task.currentDirectoryURL = currentDir
                    
                    let stderrPipe = Pipe()
                    task.standardError = stderrPipe
                    
                    do {
                        try task.run()
                        task.waitUntilExit()
                        continuation.resume(returning: task.terminationStatus == 0)
                    } catch {
                        continuation.resume(returning: false)
                    }
                }
            }
            logDebug("[Subprocess] Go CLI subprocess completed. Success status: \(success)")
            
            if !success {
                statusMessage = "Synthesis failed!"
                statusColor = .red
                isSynthesizing = false
                logDebug("[Error] Go CLI synthesis failed.")
                return
            }
            
            // Update UI & Play audio instantly!
            statusMessage = "Speaking..."
            statusColor = .blue
            isSynthesizing = false
            playAudio(path: wavPath, timings: timings)
        }
    }
    
    private func fetchTokenTimings(text: String) async -> [TokenTime] {
        let url = URL(string: "http://localhost:8089/tts_token_times")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = [
            "prompt": text,
            "locale": "en-US",
            "voice": "GRIFFIN",
            "mode": "TEXT"
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return [] }
        request.httpBody = jsonData
        
        do {
            logDebug("[Timing] URLSession sending POST to \(url)...")
            let (data, _) = try await URLSession.shared.data(for: request)
            logDebug("[Timing] URLSession received timings response.")
            if let response = try? JSONDecoder().decode(TokenTimesResponse.self, from: data) {
                return response.tokentimes.tokens
            }
        } catch {
            logDebug("[Error] Error fetching timings from container: \(error)")
        }
        return []
    }
    
    private func playAudio(path: String, timings: [TokenTime]) {
        let url = URL(fileURLWithPath: path)
        do {
            logDebug("[Audio] Loading AVAudioPlayer with: \(path)")
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            
            let dataSize = (try? Data(contentsOf: url).count) ?? 0
            logDebug("[Audio] AVAudioPlayer initialized successfully. File size: \(dataSize) bytes.")
            
            audioPlayer?.prepareToPlay()
            logDebug("[Audio] AVAudioPlayer prepared to play.")
            
            // Reset First-Tick state before starting animations
            isFirstTick = true
            
            audioPlayer?.play()
            logDebug("[Audio] audioPlayer.play() executed successfully.")
            
            // Execute speech-sync animations, passing current speed factor for timeline scaling (jibo-6yu.3)
            if !timings.isEmpty {
                logDebug("[Animation] Starting Token-Based mouth-sync animation...")
                animateMouthSyncWithTokens(timings: timings, speed: speedFactor)
            } else {
                logDebug("[Animation] Starting Procedural Fallback mouth-sync animation...")
                animateMouthSyncFallback(speed: speedFactor)
            }
            
        } catch {
            statusMessage = "Audio play failed"
            statusColor = .red
            logDebug("[Error] Failed to initialize/play AVAudioPlayer: \(error)")
        }
    }
    
    private func animateMouthSyncWithTokens(timings: [TokenTime], speed: Double) {
        animationTimer?.invalidate()
        let startTime = Date()
        
        logDebug("[Animation] Starting 20ms timer for Token-Based mouth-sync (Speed: \(speed)x).")
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let elapsedSys = Date().timeIntervalSince(startTime)
            
            Task { @MainActor in
                guard let player = self.audioPlayer, player.isPlaying else {
                    self.animationTimer?.invalidate()
                    self.statusMessage = "Jibo idle"
                    self.statusColor = .green
                    withAnimation(.spring()) {
                        self.talkScale = 1.0
                    }
                    logDebug("[Animation] Animation completed. Timer invalidated.")
                    return
                }
                
                // CRITICAL SYNC FIX: Query the exact, millisecond-precision CoreAudio playback head currentTime
                // instead of using system uptime offsets. This guarantees absolute phase-locked synchronization
                // and eliminates any audio device startup/hardware latencies!
                //
                // Note: Jibo's synthesized WAV contains a starting pause (LPAU) at the beginning which accounts
                // for ~350ms of initial silence, whereas the token timings are relative to the first spoken word.
                // We offset the elapsed time by 350ms to perfectly align the eye-pulse with Jibo's speech!
                let elapsedAudio = player.currentTime - 0.35
                
                // Scale the audio-head elapsed timeline back up by the speed factor so it matches Jibo's
                // baseline un-stretched token timestamps! (jibo-6yu.3)
                let elapsed = elapsedAudio * speed
                
                if self.isFirstTick {
                    self.isFirstTick = false
                    logDebug("[Animation] First active tick of Token-Based animation. System Elapsed: \(String(format: "%.3f", elapsedSys))s | Player currentTime (offset/scaled): \(String(format: "%.3f", elapsed))s")
                }
                
                // Check if we are currently inside any token's start-end time window
                var isSpeakingWord = false
                if elapsed >= 0 {
                    for token in timings {
                        // Buffer by 50ms for natural response
                        if elapsed >= token.start && elapsed <= (token.end + 0.05) {
                            isSpeakingWord = true
                            break
                        }
                    }
                }
                
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    if isSpeakingWord {
                        // Wiggle/pulse eye between 0.85 and 1.3 to simulate Jibo's animated vocal expressions
                        let pulse = 1.0 + 0.15 * sin(elapsed * 40.0)
                        self.talkScale = CGFloat(pulse)
                    } else {
                        self.talkScale = 1.0
                    }
                }
            }
        }
    }
    
    private func animateMouthSyncFallback(speed: Double) {
        animationTimer?.invalidate()
        let startTime = Date()
        
        logDebug("[Animation] Starting 20ms timer for Procedural Fallback mouth-sync (Speed: \(speed)x).")
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let elapsedSys = Date().timeIntervalSince(startTime)
            
            Task { @MainActor in
                guard let player = self.audioPlayer, player.isPlaying else {
                    self.animationTimer?.invalidate()
                    self.statusMessage = "Jibo idle"
                    self.statusColor = .green
                    withAnimation(.spring()) {
                        self.talkScale = 1.0
                    }
                    logDebug("[Animation] Fallback completed. Timer invalidated.")
                    return
                }
                
                // CRITICAL SYNC FIX: Query the exact CoreAudio playback head currentTime
                let elapsedAudio = player.currentTime - 0.35
                
                // Scale the fallback timeline back up by the speed factor
                let elapsed = elapsedAudio * speed
                
                if self.isFirstTick {
                    self.isFirstTick = false
                    logDebug("[Animation] First active tick of Fallback animation. System Elapsed: \(String(format: "%.3f", elapsedSys))s | Player currentTime (offset/scaled): \(String(format: "%.3f", elapsed))s")
                }
                
                // Procedural syllable/vocal pulse fallback
                if elapsed >= 0 {
                    let pulse = 1.0 + 0.18 * sin(elapsed * 22.0) * cos(elapsed * 8.0)
                    withAnimation(.spring(response: 0.12, dampingFraction: 0.55)) {
                        if pulse > 0.95 {
                            self.talkScale = CGFloat(pulse)
                        } else {
                            self.talkScale = 1.0
                        }
                    }
                } else {
                    withAnimation(.spring()) {
                        self.talkScale = 1.0
                    }
                }
            }
        }
    }
}
