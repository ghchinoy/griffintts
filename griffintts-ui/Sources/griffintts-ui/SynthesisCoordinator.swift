import AVFoundation
import Foundation
import SwiftUI // required for withAnimation, Color

// MARK: - SynthesisCoordinator (d4m.10)
// Extracted from ContentView to reduce its body below 250 lines.
// Owns all synthesis business logic: CLI subprocess, token timing fetch,
// audio playback, and mouth-sync animation timers.
// Marked @MainActor so all UI-touching callbacks stay on the main thread.
@MainActor
final class SynthesisCoordinator: ObservableObject {
    // Published state — ContentView observes these
    @Published var statusMessage: String = "Jibo ready"
    @Published var statusColor: SynthesisStatusColor = .ready
    @Published var isSynthesizing: Bool = false
    @Published var talkScale: CGFloat = 1.0

    // Internal audio / timer state
    private(set) var audioPlayer: AVAudioPlayer?
    private var animationTimer: Timer?
    private var isFirstTick: Bool = true

    // ── Stop ──────────────────────────────────────────────────────────
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        animationTimer?.invalidate()
        statusMessage = "Jibo idle"
        statusColor = .ready
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

    // ── Synthesize ────────────────────────────────────────────────────
    func synthesize(prompt: String, isNative: Bool, speedFactor: Double, griffinttsRepoRoot: URL) async {
        let wavPath = "/tmp/griffintts-ui.wav"
        var timings: [TokenTime] = []
        if !isNative { timings = await fetchTokenTimings(text: prompt) }
        logDebug("[Timing] \(timings.count) tokens received.")
        var speechDuration: Double = 0.0
        if let last = timings.last { speechDuration = (last.end / speedFactor) + 0.40 }
        let ttsBin = griffinttsRepoRoot.appendingPathComponent("griffintts/bin/griffintts").path
        var finalArgs = ["--ow", wavPath]
        if isNative { finalArgs.append("--native") } else if speechDuration > 0 {
            finalArgs.append(contentsOf: ["--duration", String(format: "%.2f", speechDuration)])
        }
        finalArgs.append(contentsOf: ["--speed", String(format: "%.2f", speedFactor)])
        finalArgs.append(prompt)
        logDebug("[Subprocess] \(ttsBin) \(finalArgs.joined(separator: " "))")
        let success = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let argsToPass = finalArgs
            // griffintts' own binary resolves its assets relative to its own
            // directory when invoked this way (see its main.go fallback
            // path) — so the subprocess's CWD needs to be griffintts/
            // itself, not its parent.
            let currentDir = griffinttsRepoRoot.appendingPathComponent("griffintts")
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: ttsBin)
                task.arguments = argsToPass
                task.currentDirectoryURL = currentDir
                task.standardError = Pipe()
                do {
                    try task.run()
                    task.waitUntilExit()
                    cont.resume(returning: task.terminationStatus == 0)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
        logDebug("[Subprocess] Completed. Success: \(success)")
        if !success {
            statusMessage = "Synthesis failed!"; statusColor = .error
            isSynthesizing = false; return
        }
        // Synthesis complete — spinner off before audio begins
        isSynthesizing = false
        statusMessage = "Speaking..."; statusColor = .speaking
        playAudio(path: wavPath, timings: timings, speed: speedFactor)
    }

    // ── Token Timings ─────────────────────────────────────────────────
    func fetchTokenTimings(text: String) async -> [TokenTime] {
        guard let url = URL(string: "http://localhost:8089/tts_token_times") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = ["prompt": text, "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return [] }
        req.httpBody = body
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let resp = try? JSONDecoder().decode(TokenTimesResponse.self, from: data) { return resp.tokentimes.tokens }
        } catch { logDebug("[Timing] Error: \(error)") }
        return []
    }

    // ── Audio Playback ────────────────────────────────────────────────
    private func playAudio(path: String, timings: [TokenTime], speed: Double) {
        let url = URL(fileURLWithPath: path)
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            let fileSize = (try? Data(contentsOf: url).count) ?? 0
            logDebug("[Audio] \(fileSize) bytes. Preparing...")
            audioPlayer?.prepareToPlay()
            isFirstTick = true
            audioPlayer?.play()
            logDebug("[Audio] play() called.")
            if !timings.isEmpty {
                animateMouthSyncWithTokens(timings: timings, speed: speed)
            } else {
                animateMouthSyncFallback(speed: speed)
            }
        } catch {
            statusMessage = "Audio play failed"; statusColor = .error
            logDebug("[Audio] Error: \(error)")
        }
    }

    // ── Mouth-sync animation (token-based) ────────────────────────────
    private func animateMouthSyncWithTokens(timings: [TokenTime], speed: Double) {
        animationTimer?.invalidate()
        let animationStartTime = Date()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let sysElapsed = Date().timeIntervalSince(animationStartTime)
            Task { @MainActor in
                guard let player = self.audioPlayer, player.isPlaying else {
                    self.animationTimer?.invalidate()
                    self.statusMessage = "Jibo idle"; self.statusColor = .ready
                    withAnimation(.spring()) { self.talkScale = 1.0 }
                    logDebug("[Animation] Complete (\(String(format: "%.2f", sysElapsed))s).")
                    return
                }
                let elapsed = (player.currentTime - 0.35) * speed
                if self.isFirstTick {
                    self.isFirstTick = false
                    logDebug("[Animation] First tick. elapsed(scaled)=\(String(format: "%.3f", elapsed))s")
                }
                var speaking = false
                if elapsed >= 0 {
                    for tok in timings where elapsed >= tok.start && elapsed <= tok.end + 0.05 {
                        speaking = true; break
                    }
                }
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    self.talkScale = speaking ? CGFloat(1.0 + 0.15 * sin(elapsed * 40.0)) : 1.0
                }
            }
        }
    }

    // ── Mouth-sync animation (procedural fallback) ────────────────────
    private func animateMouthSyncFallback(speed: Double) {
        animationTimer?.invalidate()
        let animationStartTime = Date()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let sysElapsed = Date().timeIntervalSince(animationStartTime)
            Task { @MainActor in
                guard let player = self.audioPlayer, player.isPlaying else {
                    self.animationTimer?.invalidate()
                    self.statusMessage = "Jibo idle"; self.statusColor = .ready
                    withAnimation(.spring()) { self.talkScale = 1.0 }
                    logDebug("[Animation] Fallback complete (\(String(format: "%.2f", sysElapsed))s).")
                    return
                }
                let elapsed = (player.currentTime - 0.35) * speed
                if self.isFirstTick {
                    self.isFirstTick = false
                    logDebug("[Animation] First fallback tick. elapsed(scaled)=\(String(format: "%.3f", elapsed))s")
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

// SynthesisStatusColor is defined in SharedTypes.swift
