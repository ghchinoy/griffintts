import SwiftUI
import AVFoundation

// MARK: - Speech Designer Panel
//
// Empirical findings (ykr.6 + subsequent sweep):
//   - [lpau] / [spau] / <break/> etc: spoken as literal text, NOT parsed as pauses.
//   - <audio name="..."/> Jibonics tags: spoken as literal text.
//   - [Pron: ...] / <pron ph='...'/> pronunciation overrides: spoken literally.
//   - No JSON field on /tts_speak triggers a SpeakingStyle register change.
//
// The only confirmed working control beyond plain text is `duration_stretch`
// (speed), already wired to the Speed slider.
//
// The inline helpers section has been removed entirely to avoid presenting
// controls that produce garbled literal speech as their only effect.
@MainActor
struct SpeechDesignerPanel: View {
    @Binding var prompt: String
    @Binding var speedFactor: Double
    @Binding var isNative: Bool
    @Binding var isSynthesizing: Bool
    @Binding var audioPlayer: AVAudioPlayer?
    let onSpeak: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────
            Text("Speech Designer")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Prompt ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Prompt", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        TextEditor(text: $prompt)
                            .font(.system(.body, design: .rounded))
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                            .cornerRadius(8)
                            .frame(minHeight: 160)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 14)

                    Divider()

                    // ── Speed ─────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Speed", systemImage: "gauge.with.needle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Text("Slow")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Slider(value: $speedFactor, in: 0.5...2.0, step: 0.1)
                            Text("Fast")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Spacer()
                            Text(String(format: "%.1fx", speedFactor))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.accentColor)
                            Button("Reset") { speedFactor = 1.0 }
                                .font(.caption)
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)

                    Divider()

                    // ── Options ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Options", systemImage: "gearshape")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)

                        Toggle(isOn: $isNative) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Standalone Native Mode")
                                    .font(.callout)
                                Text("Uses en_us HTS voice, no container required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    .padding(.horizontal, 14)

                    Divider()

                    // ── Actions ───────────────────────────────────────
                    HStack(spacing: 10) {
                        Button(action: onSpeak) {
                            Label("Speak", systemImage: "megaphone.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isSynthesizing || prompt.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)

                        Button(action: onStop) {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                        .disabled(!isSynthesizing && !(audioPlayer?.isPlaying ?? false))
                        .keyboardShortcut(".", modifiers: .command)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .padding(.top, 14)
            }
        }
    }
}
