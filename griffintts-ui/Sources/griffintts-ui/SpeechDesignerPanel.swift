import SwiftUI
import AVFoundation

// MARK: - Speech Designer Panel
//
// Confirmed audio-channel controls (all empirically measured against the
// emulated tts_run container — see docs/prosody_and_affect.md):
//
//   Plain-text mode:
//     - duration_stretch JSON field (wired to Speed slider) — ✅ confirmed,
//       inverse-rate semantics: higher value = faster speech.
//
//   Markup mode (--markup flag on the CLI):
//     - <style set="...">  — ✅ confirmed; 6 official SDK styles produce
//       measurable centroid + duration shifts (5 clearly distinct; `excited`
//       is a binary artifact, ~10 Hz from neutral, not an official SDK style —
//       use `enthusiastic` instead). Tag parsed by libJiboTTSService.so's
//       MarkupHandler; not the JSON field path. MIT HRI2024 ESML SDK source
//       confirms SSMLStyleTagType enum = 6 styles (no `excited`).
//     - <pitch halftone="N"> — ✅ confirmed monotonic response.
//     - <duration stretch="N"> — ✅ confirmed; NOTE inverted vs Speed slider:
//       stretch > 1.0 = slower, < 1.0 = faster.
//     - <break size="N"/> — ✅ confirmed real silence (not spoken literally).
//
//   Animation tags (<anim>, <ssa>, <es>) are stripped by the CLI's
//   preprocessMarkup() with a warning — they require the robot's on-device
//   @be/be Electron process and AnimDB. The speaking-motion display in
//   griffintts-ui is an approximation only; it does not render AnimDB content.

// MARK: - Speaking Style

enum SpeakingStyle: String, CaseIterable, Identifiable {
    case neutral      = "neutral"
    case excited      = "excited"
    case confused     = "confused"
    case sheepish     = "sheepish"
    case confident    = "confident"
    case enthusiastic = "enthusiastic"
    case news         = "news"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neutral:      return "Neutral"
        case .excited:      return "Excited"
        case .confused:     return "Confused"
        case .sheepish:     return "Sheepish"
        case .confident:    return "Confident"
        case .enthusiastic: return "Enthusiastic"
        case .news:         return "News"
        }
    }

    // tooltip shown on hover — flags marginal styles honestly
    var note: String {
        switch self {
        case .neutral:      return "Baseline — no style modifier emitted."
        case .excited:      return "Marginal: ~10 Hz centroid shift. May be subtle."
        case .confused:     return "Confirmed: +85 Hz centroid, +85 ms duration."
        case .sheepish:     return "Confirmed: +65 Hz centroid, +107 ms duration."
        case .confident:    return "Confirmed: +91 Hz centroid, +64 ms duration."
        case .enthusiastic: return "Confirmed: +100 Hz centroid, −21 ms duration."
        case .news:         return "Confirmed: +87 Hz centroid, +85 ms duration."
        }
    }
}

// MARK: - ESML String Builder

/// Pure function — builds the ESML string from the current control state.
/// Returns nil when markup mode is off or all controls are at neutral.
func buildESML(
    prompt: String,
    style: SpeakingStyle,
    pitchHalftone: Int,
    durationStretch: Double,
    isMarkupMode: Bool
) -> String? {
    guard isMarkupMode else { return nil }

    var inner = prompt

    // Wrap with style (omit tag when neutral — keeps ESML clean)
    if style != .neutral {
        inner = "<style set=\"\(style.rawValue)\">\(inner)</style>"
    }

    // Prepend duration tag when not at default (omit at 1.0)
    if abs(durationStretch - 1.0) > 0.05 {
        let dStr = String(format: "%.2f", durationStretch)
        inner = "<duration stretch=\"\(dStr)\"/>\(inner)"
    }

    // Prepend pitch tag when not at zero
    if pitchHalftone != 0 {
        let sign = pitchHalftone > 0 ? "+" : ""
        inner = "<pitch halftone=\"\(sign)\(pitchHalftone)\"/>\(inner)"
    }

    return "<speak>\(inner)</speak>"
}

// MARK: - Speech Designer Panel View

@MainActor
struct SpeechDesignerPanel: View {
    @Binding var prompt: String
    @Binding var speedFactor: Double
    @Binding var isNative: Bool
    @Binding var isMarkupMode: Bool
    @Binding var selectedStyle: SpeakingStyle
    @Binding var pitchHalftone: Int
    @Binding var durationStretch: Double
    let isSynthesizing: Bool
    let audioPlayerIsPlaying: Bool
    let onSpeak: () -> Void
    let onStop: () -> Void

    // Derived ESML preview — recomputed on every relevant state change
    private var esmlPreview: String {
        buildESML(
            prompt: prompt,
            style: selectedStyle,
            pitchHalftone: pitchHalftone,
            durationStretch: durationStretch,
            isMarkupMode: isMarkupMode
        ) ?? prompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Prompt ────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Label("Prompt", systemImage: "text.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                TextEditor(text: $prompt)
                    .font(.system(.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .frame(maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Divider().padding(.top, 10)

            // ── Affective Markup ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {

                // Mode toggle header
                HStack {
                    Label("Affective Markup", systemImage: "waveform.badge.mic")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: $isMarkupMode)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help("When on, speech is rendered using the daemon's native markup dialect. Animation tags (<anim>, <ssa>, <es>) are stripped automatically.")
                }

                if isMarkupMode {

                    // ── Style ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Style")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Style", selection: $selectedStyle) {
                            ForEach(SpeakingStyle.allCases) { style in
                                Text(style.displayName)
                                    .tag(style)
                                    .help(style.note)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .help(selectedStyle.note)
                    }

                    // ── Pitch ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Pitch offset")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(pitchHalftone > 0 ? "+" : "")\(pitchHalftone) halftones")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(pitchHalftone == 0 ? .secondary : .accentColor)
                            Button("Reset") { pitchHalftone = 0 }
                                .font(.caption)
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                                .disabled(pitchHalftone == 0)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(pitchHalftone) },
                                set: { pitchHalftone = Int($0.rounded()) }
                            ),
                            in: -20...20,
                            step: 1
                        )
                        .help("Pitch offset in halftones. Confirmed range: −10 → −103 Hz centroid; +10 → +88 Hz centroid.")
                    }

                    // ── Duration ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Duration stretch")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.2f×", durationStretch))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(abs(durationStretch - 1.0) < 0.05 ? .secondary : .accentColor)
                            Button("Reset") { durationStretch = 1.0 }
                                .font(.caption)
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                                .disabled(abs(durationStretch - 1.0) < 0.05)
                        }
                        Slider(value: $durationStretch, in: 0.25...3.0, step: 0.05)
                            .help("Speech rate via <duration stretch>. NOTE: opposite direction to the Speed slider — higher value = slower speech. 1.0 = normal.")
                        HStack {
                            Text("Faster").font(.system(size: 10)).foregroundColor(.secondary)
                            Spacer()
                            Text("Slower").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }

                    // ── Break insertion ────────────────────────────────────
                    HStack(spacing: 8) {
                        Button {
                            prompt += "<break size=\"0.5\"/>"
                        } label: {
                            Label("Insert break", systemImage: "pause.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Appends <break size=\"0.5\"/> to the prompt. Confirmed: inserts ~0.6 s real silence.")

                        Text("0.5 s pause")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // ── ESML preview ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ESML preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ScrollView(.vertical) {
                            Text(esmlPreview)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                        }
                        .frame(maxHeight: 72)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                    }
                } // if isMarkupMode
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // ── Speed (plain-text mode only) ──────────────────────────────
            if !isMarkupMode {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Speed", systemImage: "gauge.with.needle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Text("Slow").font(.system(size: 10)).foregroundColor(.secondary)
                        Slider(value: $speedFactor, in: 0.5...2.0, step: 0.1)
                        Text("Fast").font(.system(size: 10)).foregroundColor(.secondary)
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
                .padding(.vertical, 10)

                Divider()
            }

            // ── Options ───────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Label("Options", systemImage: "gearshape")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Toggle(isOn: $isNative) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Standalone Native Mode").font(.callout)
                        Text("Uses en_us HTS voice, no container required")
                            .font(.caption).foregroundColor(.secondary)
                        if isMarkupMode && isNative {
                            Text("Note: markup tags are stripped in native mode")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // ── Speak / Stop ──────────────────────────────────────────────
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
                .disabled(!isSynthesizing && !audioPlayerIsPlaying)
                .keyboardShortcut(".", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}
