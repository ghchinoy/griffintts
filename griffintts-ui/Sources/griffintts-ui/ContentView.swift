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

@MainActor
struct ContentView: View {
    @State private var prompt: String = "Hi there, I am Jibo, synthesized locally on macOS!"
    @State private var isNative: Bool = false
    @State private var isSynthesizing: Bool = false
    @State private var statusMessage: String = "Jibo ready"
    @State private var statusColor: Color = .green
    
    // Eye state variables
    @State private var blinkScaleY: CGFloat = 1.0
    @State private var talkScale: CGFloat = 1.0
    @State private var lookOffset: CGSize = .zero
    
    @State private var audioPlayer: AVAudioPlayer?
    @State private var animationTimer: Timer?
    @State private var blinkTimer: Timer?
    
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
    
    private func triggerSynthesis() {
        guard !isSynthesizing && !prompt.isEmpty else { return }
        
        isSynthesizing = true
        statusMessage = "Synthesizing..."
        statusColor = .orange
        
        let t = prompt
        let native = isNative
        let wavPath = "/tmp/griffintts-ui.wav"
        
        Task {
            // 1. START TIMINGS FETCH IN PARALLEL! (Asynchronous background Task)
            async let timingsFetch: [TokenTime] = {
                if !native {
                    return await fetchTokenTimings(text: t)
                }
                return []
            }()
            
            // 2. RUN CLI SUBPROCESS IN PARALLEL!
            let ttsBin = "/Users/ghchinoy/projects/jibo/tools/bin/griffintts"
            
            let argsList = ["--ow", wavPath]
            var finalArgs = argsList
            if native {
                finalArgs.append("--native")
            }
            finalArgs.append(t)
            
            let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                // Isolated, non-capturing background thread execution to prevent warnings
                let argsToPass = finalArgs
                DispatchQueue.global(qos: .userInitiated).async {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: ttsBin)
                    task.arguments = argsToPass
                    task.currentDirectoryURL = URL(fileURLWithPath: "/Users/ghchinoy/projects/jibo")
                    
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
            
            // 3. AWAIT TIMINGS FETCH RESOLUTION (Will likely already be completed in parallel!)
            let timings = await timingsFetch
            
            if !success {
                statusMessage = "Synthesis failed!"
                statusColor = .red
                isSynthesizing = false
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
            let (data, _) = try await URLSession.shared.data(for: request)
            if let response = try? JSONDecoder().decode(TokenTimesResponse.self, from: data) {
                return response.tokentimes.tokens
            }
        } catch {
            print("Error fetching timings: \(error)")
        }
        return []
    }
    
    private func playAudio(path: String, timings: [TokenTime]) {
        let url = URL(fileURLWithPath: path)
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            // Execute speech-sync animations
            if !timings.isEmpty {
                animateMouthSyncWithTokens(timings: timings)
            } else {
                animateMouthSyncFallback()
            }
            
        } catch {
            statusMessage = "Audio play failed"
            statusColor = .red
        }
    }
    
    private func animateMouthSyncWithTokens(timings: [TokenTime]) {
        animationTimer?.invalidate()
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            Task { @MainActor in
                // Reference self.audioPlayer on MainActor dynamically without capturing timer parameter
                guard let player = self.audioPlayer, player.isPlaying else {
                    self.animationTimer?.invalidate()
                    self.statusMessage = "Jibo idle"
                    self.statusColor = .green
                    withAnimation(.spring()) {
                        self.talkScale = 1.0
                    }
                    return
                }
                
                // CRITICAL SYNC FIX: Query the exact, millisecond-precision CoreAudio playback head currentTime
                // instead of using system uptime offsets. This guarantees absolute phase-locked synchronization
                // and eliminates any audio device startup/hardware latencies!
                //
                // Note: Jibo's synthesized WAV contains a starting pause (LPAU) at the beginning which accounts
                // for ~350ms of initial silence, whereas the token timings are relative to the first spoken word.
                // We offset the elapsed time by 350ms to perfectly align the eye-pulse with Jibo's speech!
                let elapsed = player.currentTime - 0.35
                
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
    
    private func animateMouthSyncFallback() {
        animationTimer?.invalidate()
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            Task { @MainActor in
                // Reference self.audioPlayer on MainActor dynamically without capturing timer parameter
                guard let player = self.audioPlayer, player.isPlaying else {
                    self.animationTimer?.invalidate()
                    self.statusMessage = "Jibo idle"
                    self.statusColor = .green
                    withAnimation(.spring()) {
                        self.talkScale = 1.0
                    }
                    return
                }
                
                // CRITICAL SYNC FIX: Query the exact CoreAudio playback head currentTime
                let elapsed = player.currentTime - 0.35
                
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
