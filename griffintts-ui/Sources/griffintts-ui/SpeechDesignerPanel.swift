import SwiftUI
import AVFoundation

// MARK: - Jibonics effect identifiers confirmed from jibo-tts-service.json PostFilterMap
let jibonicsEffects: [(name: String, label: String)] = [
    ("woo_hoo_hoo",  "Woo-Hoo!"),
    ("laughter",     "Laugh"),
    ("laugh2",       "Laugh 2"),
    ("cool",         "Cool"),
    ("done",         "Done"),
    ("whoa",         "Whoa"),
    ("perfect",      "Perfect"),
    ("ok",           "OK"),
    ("sweet",        "Sweet"),
    ("what",         "What?"),
    ("aw",           "Aw"),
    ("oops",         "Oops"),
    ("my_bad",       "My Bad"),
    ("um",           "Um"),
    ("huh",          "Huh?"),
    ("nm_um",        "Hmm"),
    ("i_love_to_1",  "I Love To!"),
    ("argh",         "Argh"),
]

// MARK: - Speech Designer Panel
@MainActor
struct SpeechDesignerPanel: View {
    @Binding var prompt: String
    @Binding var speedFactor: Double
    @Binding var isNative: Bool
    @Binding var isSynthesizing: Bool
    @Binding var audioPlayer: AVAudioPlayer?
    let onSpeak: () -> Void
    let onStop: () -> Void

    // Track cursor insertion index via a simple approach:
    // store a helper string that we append to manually until we bridge NSTextView
    @State private var selectedEffect: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Section Header ─────────────────────────────────────────
            Text("Speech Designer")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            Divider().background(Color(white: 0.25))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    // ── Multi-line Prompt Editor ───────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Prompt", systemImage: "text.bubble")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gray)

                        TextEditor(text: $prompt)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color(white: 0.12))
                            .cornerRadius(8)
                            .frame(minHeight: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(white: 0.28), lineWidth: 1)
                            )

                        // ── Inline Helper Buttons (Appended at end until cursor bridging lands)
                        HStack(spacing: 8) {
                            insertButton("[lpau]", label: "Long Pause",  icon: "pause.rectangle")
                            insertButton("[spau]", label: "Short Pause", icon: "pause")
                            insertButton("[Pron: ]", label: "Pronunciation", icon: "character.phonetics")
                        }

                        // ── Jibonics Experimental Picker ─────────────
                        Menu {
                            ForEach(jibonicsEffects, id: \.name) { effect in
                                Button(effect.label) {
                                    prompt += " <audio name=\"\(effect.name)\" />"
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform.badge.plus")
                                Text("Insert Jibonics")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.15))
                            .cornerRadius(6)
                        }

                        // Experimental disclaimer
                        Label("Jibonics tags may be spoken as text on this firmware.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color.orange.opacity(0.7))
                    }
                    .padding(.horizontal, 14)

                    Divider().background(Color(white: 0.2))

                    // ── Speed Slider ───────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Speed", systemImage: "gauge.with.needle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gray)

                        HStack {
                            Text("0.5x")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)
                            Slider(value: $speedFactor, in: 0.5...2.0, step: 0.1)
                                .accentColor(.blue)
                            Text("2.0x")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        Text(String(format: "Current: %.1fx", speedFactor))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 14)

                    Divider().background(Color(white: 0.2))

                    // ── Mode & Controls ────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Options", systemImage: "gearshape")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.gray)

                        Toggle(isOn: $isNative) {
                            Text("Standalone Native Mode (en_us)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .toggleStyle(CheckboxToggleStyle())

                        HStack(spacing: 10) {
                            // Speak button
                            Button(action: onSpeak) {
                                Label("Speak", systemImage: "megaphone.fill")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSynthesizing || prompt.isEmpty)
                            .keyboardShortcut(.return, modifiers: .command)

                            // Stop button (confirmed via ykr.6: /tts_stop returns HTTP 200)
                            Button(action: onStop) {
                                Label("Stop", systemImage: "stop.fill")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(!isSynthesizing && !(audioPlayer?.isPlaying ?? false))
                            .keyboardShortcut(".", modifiers: .command)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .padding(.top, 12)
            }
        }
        .background(Color(white: 0.07))
        .frame(width: 290)
    }

    @ViewBuilder
    private func insertButton(_ token: String, label: String, icon: String) -> some View {
        Button(action: {
            // Appends to end of prompt. Full cursor-index insertion
            // requires NSViewRepresentable bridge (jibo-ykr.2).
            prompt += " \(token)"
        }) {
            Label(label, systemImage: icon)
                .font(.system(size: 10))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
