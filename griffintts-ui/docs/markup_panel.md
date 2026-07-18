# griffintts-ui — Markup Authoring Panel

The Speech Designer sidebar builds Jibo's affective ESML markup from GUI
controls, layered on top of (or fully replacing) a plain-text prompt.

---

## 1. What the panel does

The griffintts-ui window is a macOS SwiftUI `NavigationSplitView` with two
columns:

- **Sidebar: Speech Designer** (`SpeechDesignerPanel.swift`) — the markup
  authoring UI described in this doc.
- **Detail: Jibo's Eye** (`JiboEyeView.swift` via `ContentView.swift`) — the
  animated eye panel; not affected by markup authoring, described briefly in
  §4 below.

### Panel layout, top to bottom

1. **Prompt** — a multi-line `TextEditor` for raw text input. This field
   accepts plain text *or* raw ESML tags typed/pasted directly — the markup
   controls below are a convenience builder that wrap whatever is in this
   field, they do not replace manual authoring. See §3.
2. **Affective Markup** section, visible only when the mode toggle is on:
   - **Style** picker — the 7 C++ `SpeakingStyle` enum values. Note: the official SDK defines 6 styles; `excited` is a binary artifact indistinguishable from neutral — prefer `enthusiastic`. See `tools/griffintts/docs/prosody_and_affect.md` §4.
   - **Pitch offset** slider — −20 to +20 halftones.
   - **Duration stretch** slider — 0.25× to 3.0×, clearly labeled with its
     inverted-vs-Speed semantics.
   - **Insert break** button — appends a fixed `<break size="0.5"/>` to the
     prompt.
   - **ESML preview** — a read-only, monospaced, scrollable, selectable
     rendering of the exact string that will be sent to `--markup`.
3. **Speed** slider (0.5×–2.0×) — only shown when Affective Markup mode is
   **off**. Maps to the CLI's `--speed` flag (`duration_stretch` JSON field,
   plain-text path only).
4. **Options** — "Standalone Native Mode" checkbox (`--native`). If both
   native mode and markup mode are on, the panel shows an inline warning
   ("markup tags are stripped in native mode") since the native HTS pipeline
   has no `MarkupHandler`.
5. **Speak / Stop** buttons (⌘↩ / ⌘.).

---

## 2. How it calls the CLI

`SpeechDesignerPanel`'s `buildESML()` is a pure function:

```swift
func buildESML(
    prompt: String,
    style: SpeakingStyle,
    pitchHalftone: Int,
    durationStretch: Double,
    isMarkupMode: Bool
) -> String? {
    guard isMarkupMode else { return nil }
    var inner = prompt
    if style != .neutral { inner = "<style set=\"\(style.rawValue)\">\(inner)</style>" }
    if abs(durationStretch - 1.0) > 0.05 { inner = "<duration stretch=\"...\"/>\(inner)" }
    if pitchHalftone != 0 { inner = "<pitch halftone=\"...\"/>\(inner)" }
    return "<speak>\(inner)</speak>"
}
```

**The only early-return is `isMarkupMode` itself** — not "all controls at
neutral." Turning the toggle on always produces a `<speak>...</speak>`-wrapped
string, even with every slider at its default, because `inner` starts as
whatever is in the Prompt field. Style/pitch/duration tags are layered on top
only when their control has moved off its default value.

`ContentView.swift` holds four `@State` vars (`isMarkupMode`, `selectedStyle`,
`pitchHalftone`, `durationStretch`), passes them into `SpeechDesignerPanel` as
bindings, and calls `buildESML()` when the Speak button fires.
`SynthesisCoordinator.synthesize(prompt:esmlPrompt:...)` treats `esmlPrompt !=
nil` as the markup-mode signal:

- **Markup mode**: `--markup '<esmlPrompt>'` is passed to the CLI. Token
  timings for mouth-sync are still fetched using the **plain** `prompt` text
  (not the ESML string) via `fetchTokenTimings()`, since `/tts_token_times`
  ignores markup and expects plain spoken text — this keeps mouth-sync
  accurate regardless of which tags are active.
- **Plain-text mode**: `--speed <speedFactor>` and the raw prompt are passed;
  no `--markup` flag.

## 3. Pasting raw ESML directly into the Prompt field

Because `buildESML()` only wraps the prompt's content (it never parses or
validates it), you can type or paste ESML tags directly into the Prompt
`TextEditor` — `<phoneme>`, `<say-as>`, multiple `<break>` insertions, etc. —
turn Affective Markup mode on, and they will be sent through `--markup`
exactly as typed, composed with whatever the Style/Pitch/Duration controls
add on top. This is how the panel supports tags that have no dedicated UI
control (see §5) without blocking them.

**One caveat, not yet tested empirically**: if the pasted text already
contains its own `<speak>...</speak>` wrapper, `buildESML()` will nest a
second one around it (`<speak><speak>...</speak></speak>`). The CLI's own
`preprocessMarkup()` correctly detects an existing outer `<speak>` and won't
add a third, but whether Griffin's daemon handles the inner nested `<speak>`
gracefully is unconfirmed. Safest practice: omit the outer `<speak>` tag when
pasting ESML into the panel and let it add the single wrapper.

## 4. Speaking-motion approximation

`SynthesisCoordinator` has two animation paths driving `JiboEyeView`'s
`talkScale`:

1. **Token-based** (container mode): fetches `/tts_token_times` before
   synthesis, then drives `talkScale` in a 50 Hz `Timer` reading
   `AVAudioPlayer.currentTime`, synchronized to token start/end timestamps
   (with a −350 ms LPAU-silence offset compensation). Works identically in
   markup and plain-text mode, since timings are always fetched from plain
   text (§2).
2. **Procedural fallback** (native mode, or when token fetch fails): a
   `sin`/`cos` waveform drives `talkScale` organically for the duration of
   playback.

This is a visual approximation only — it does not render Jibo's real AnimDB
content, which requires the on-robot `@be/be` Electron process and has no
offline equivalent. See `docs/subsystems/esml-two-channel-model.md` in the
main repo for the full audio-channel-vs-animation-channel architecture this
boundary comes from.

## 5. Permanently out of scope

These are deliberate exclusions, not gaps waiting to be filled:

- **No `<phoneme>` or `<say-as>` authoring UI** — the daemon supports both
  (confirmed, see `prosody_and_affect.md`), but authoring them requires
  knowing Jibo's Combilex phoneme inventory and isn't useful to most authors
  via a GUI control. Still fully usable by typing the tags directly into the
  Prompt field (§3).
- **No `<sfx>`/`<sound>` UI** — these ESML tokens exist in the parser's
  vocabulary, but there is no audio asset bank available offline for
  griffintts to play back (`sound_banks.md`'s 29-clip Jibonics bank was never
  extracted from a live unit). `preprocessMarkup()` does not strip these tags
  — it leaves them for the daemon to handle or ignore — so the UI should not
  emit them until sfx support is confirmed some other way.
- **No `<tts params=...>` wrapper** — this is the outer root wrapper from the
  original SDK's closed ESML vocabulary, predating the `<speak>` wrapper the
  daemon actually uses today. The panel generates `<speak>`, matching
  `preprocessMarkup()`'s own behavior. Authors pasting old SDK-style `<tts>`
  strings into the prompt should expect the preview field to show a nested
  `<speak><tts>...</tts></speak>` result, which is untested.
- **No changes to `JiboEyeView`** — the approximation in §4 works
  identically whether or not markup mode is active; there was never a reason
  to couple them.

## 6. Files involved

| File | Role |
|---|---|
| `Sources/griffintts-ui/SpeechDesignerPanel.swift` | `SpeakingStyle` enum, `buildESML()`, the full markup UI section |
| `Sources/griffintts-ui/ContentView.swift` | Owns the four `@State` vars, wires them to the panel and to `triggerSynthesis()` |
| `Sources/griffintts-ui/SynthesisCoordinator.swift` | `synthesize(prompt:esmlPrompt:...)` — builds the CLI `Process` args, decides `--markup` vs. `--speed` |

No changes were needed to `SharedTypes.swift`, `JiboEyeView.swift`, or
`griffintts_ui.swift`.
