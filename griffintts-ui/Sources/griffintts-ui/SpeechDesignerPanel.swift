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

    // NOTE: TextEditor(text:selection:) + TextSelection require macOS 15+, above our
    // macOS 14 minimum. Insertion helpers append at end-of-string for now.
    // Tracked in ykr.2: bump minimum to macOS 15 to enable cursor-index insertion.

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

                    // ── Multi-line Prompt Editor (ykr.2) ──────────────
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
                            .frame(minHeight: 130)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(white: 0.28), lineWidth: 1)
                            )

                        // ── Confirmed inline helpers (insert at cursor) ──
                        HStack(spacing: 8) {
                            insertAtCursor("[lpau]", label: "Long Pause",    icon: "pause.rectangle")
                            insertAtCursor("[spau]", label: "Short Pause",   icon: "pause")
                            insertAtCursor("[Pron: ]", label: "Pronunciation", icon: "character.phonetics")
                        }

                        // ── Jibonics (experimental, inserts at cursor) ─
                        Menu {
                            ForEach(jibonicsEffects, id: \.name) { effect in
                                Button(effect.label) {
                                    insertAtCursorText("<audio name=\"\(effect.name)\" />")
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

                        // Empirically disconfirmed per ykr.6: tag is spoken as literal text
                        Label("Jibonics tags may be spoken as text on this firmware (ykr.6: DISCONFIRMED).", systemImage: "exclamationmark.triangle.fill")
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

    // ── Cursor-aware insertion using native TextEditor(text:selection:) API ──
    // Available macOS 14+ (our minimum target). Inserts at the active caret
    // position, or appends to the end if no selection/caret is available.
    private func insertAtCursorText(_ token: String) {
        // TextEditor(text:selection:) requires macOS 15+ which is above our macOS 14 minimum.
        // Append to end-of-string for now. When the minimum is bumped, replace this with
        // the TextSelection-based cursor-index insertion.
        let space = prompt.isEmpty || prompt.hasSuffix(" ") ? "" : " "
        prompt += "\(space)\(token)"
    }

    @ViewBuilder
    private func insertAtCursor(_ token: String, label: String, icon: String) -> some View {
        Button(action: { insertAtCursorText(token) }) {
            Label(label, systemImage: icon)
                .font(.system(size: 10))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
