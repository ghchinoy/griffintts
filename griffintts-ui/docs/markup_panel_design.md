# griffintts-ui — Markup Authoring Panel Design

**oge.8 design document** | Status: DESIGN ONLY — not yet implemented

---

## 1. What the UI currently does

### Current panel structure

The UI is a macOS SwiftUI `NavigationSplitView` with two columns:

- **Sidebar: Speech Designer** (`SpeechDesignerPanel.swift`) — three controls:
  1. **Prompt** — multi-line `TextEditor` for raw text input
  2. **Speed** — a `Slider` (0.5×–2.0×) bound to `speedFactor`, passed to the
     CLI as `--speed <n>` (maps to `duration_stretch`; plain-text path only)
  3. **Options** — a single checkbox: "Standalone Native Mode" (`--native`)
  4. **Speak / Stop** buttons at the bottom

- **Detail: Jibo's Eye** (`JiboEyeView.swift` via `ContentView.swift`) — the
  animated eye panel; not affected by markup authoring.

### How it calls the CLI

`SynthesisCoordinator.synthesize()` builds a `Process` and calls:

```
griffintts --ow /tmp/griffintts-ui.wav [--native] [--duration N] --speed N "prompt text"
```

It does **not** currently pass `--markup` at all. The prompt is always sent
as plain text. Adding markup authoring means constructing a markup string and
adding `--markup` to the args when the user has configured any markup
controls.

### Speaking-motion approximation

`SynthesisCoordinator` has two animation paths:

1. **Token-based** (container mode): calls `GET /tts_token_times` before
   synthesis, then drives `talkScale` in a `Timer` that reads
   `AVAudioPlayer.currentTime` at 50 Hz, synchronized to the token start/end
   timestamps (with a −350 ms LPAU silence offset). Eye scales on both X and Y
   axes via `talkScale` in `JiboEyeView`.

2. **Procedural fallback** (native mode, or when token fetch fails): a
   `sin`/`cos` waveform drives `talkScale` organically for the duration of
   playback.

**Does this need updating for markup mode?** Minimally. The token-timing
endpoint (`/tts_token_times`) is called with `mode: "TEXT"` and only the inner
spoken text payload — it ignores markup tags and returns timings for the
spoken words. So the token-based path continues to work when `--markup` is
used, as long as the coordinator passes the same plain text to
`/tts_token_times` and the processed markup to the CLI. The only required
change: in markup mode, pass the plain prompt to `fetchTokenTimings` (not the
generated ESML string), since the endpoint expects plain text.

---

## 2. What to add: Markup Authoring Panel

The addition is a new section inside `SpeechDesignerPanel.swift`, inserted
between the Prompt section and the Speed slider. When the user engages any
markup control, a `--markup '<generated ESML>'` flag is injected at synthesis
time.

The panel does **not** replace the Prompt TextEditor — it acts as a builder
that generates an ESML string from GUI controls, which the synthesizer then
receives instead of the raw prompt.

### 2.1 UI elements to add

#### A. Mode toggle (header of the new section)

A labeled `Toggle` or segmented `Picker` to switch between **Plain Text** mode
(current behaviour, no changes) and **Markup** mode (new). When off, the Speed
slider and plain-text flow work exactly as today. When on:

- Speed slider is hidden or disabled with a note ("Speed controlled by
  `<duration>` in markup mode — see §6 of prosody_and_affect.md")
- The markup builder controls below become visible
- The synthesize call switches to `--markup '<esml>'`

Placement: immediately below the Prompt section divider, above Speed.

#### B. Style picker

A `Picker` with `.segmented` style (or a dropdown if 7 items are too wide for
segmented on narrow sidebars) showing the 7 confirmed C++ `SpeakingStyle`
enum values:

| Display label | `set=` value | Status |
|---|---|---|
| Neutral | `neutral` | Confirmed |
| Excited | `excited` | Marginal — note in tooltip |
| Confused | `confused` | Confirmed |
| Sheepish | `sheepish` | Confirmed |
| Confident | `confident` | Confirmed |
| Enthusiastic | `enthusiastic` | Confirmed |
| News | `news` | Confirmed |

Generates: `<style set="confident">...</style>` wrapping the prompt text.

Default: `neutral` (no `<style>` tag emitted when neutral is selected, to
keep the ESML clean).

#### C. Pitch control

A `Slider` with range -100 to +100 semitones (halftone offset), labelled
"Pitch offset (halftones)", with a centred zero-reset button. Integer steps
only. Generates: `<pitch halftone="N"/>` before the text span.

Empirically: pitch via markup is confirmed live (`tools/griffintts/docs/
prosody_and_affect.md §5`). Reasonable human range is roughly −20 to +20; the
slider should go wider (−100/+100) to let the user explore.

#### D. Duration (rate) control

A `Slider` with range 0.5 to 2.0, labelled "Duration stretch". **Note**: the
`<DURATION>` tag has **inverse semantics** from the `--speed` CLI flag — higher
value = slower speech (prosody_and_affect.md §6). Label it clearly: "Speech
rate (1.0 = normal; lower = faster; higher = slower)". Generates:
`<duration stretch="N"/>` before the text span.

Only visible/active when markup mode is on.

#### E. Break insertion

A button `+ Insert break` that appends `<break time="500ms"/>` at the cursor
position in the Prompt TextEditor, or at the end if cursor position is
unavailable (SwiftUI `TextEditor` does not expose cursor position in macOS 14;
appending at end is the safe fallback). The break time can be a small
`TextField` beside the button, defaulting to 500ms.

#### F. Markup preview field

A read-only, monospaced `Text` (or non-editable `TextEditor`) showing the
generated ESML string as the user adjusts controls. This is the exact string
that will be passed to `--markup`. Example output:

```
<speak><pitch halftone="5"/><duration stretch="0.8"/><style set="confident">Hi there, I am Jibo.</style></speak>
```

Use `.font(.system(.caption, design: .monospaced))` and a subtle background.
Label it "ESML preview". This is the single most useful debugging affordance
for authors.

#### G. Synthesize button

No new button needed — the existing "Speak" (`⌘↩`) button triggers synthesis.
When markup mode is on, `triggerSynthesis()` reads the generated ESML string
(from a `@State var generatedMarkup: String`) and calls the CLI with
`--markup` instead of the raw prompt.

---

## 3. What NOT to add

- **No changes to synthesis logic in `SynthesisCoordinator`** except:
  - thread the `isMarkupMode: Bool` and `generatedMarkup: String` arguments
    through `synthesize()`, and
  - when markup mode is on, pass `--markup '<generatedMarkup>'` to the CLI args
    and strip markup tags before calling `fetchTokenTimings`.
- **No `<phoneme>` authoring UI** — lowest priority, most complex. The daemon
  supports it, but phoneme authoring requires knowing Jibo's phoneme inventory
  and is not useful to most authors. Leave as future work.
- **No `<say-as>` UI** — similarly low priority; add later if requested.
- **No `<sfx>` or `<sound>` UI** — these tags are in the ESML closed
  vocabulary but are out of scope for griffintts (no audio asset bank
  available offline). The CLI strips them the same way it strips animation
  tags... actually: per the current implementation, `preprocessMarkup` does NOT
  strip `<sfx>`/`<sound>` — it leaves them for the daemon to handle (or ignore).
  The UI should not emit these tags until sfx support is confirmed.
- **No `<tts params=...>` wrapper** — this is the outer ESML root wrapper from
  the original SDK vocabulary, pre-dating the `<speak>` wrapper. The daemon
  uses `<speak>`, and `preprocessMarkup` already adds it. The UI should
  generate `<speak>` wrappers, not `<tts>` wrappers.
- **No changes to JiboEyeView** — the speaking motion approximation works fine
  with markup-synthesized audio; the token-timing path is unchanged.

---

## 4. ESML string construction logic

The generated markup string is a pure computed property (or `@State` updated
via `onChange`) in `SpeechDesignerPanel`, following this template:

```
<speak>
  [pitch tag if offset ≠ 0]
  [duration tag if stretch ≠ 1.0]
  [style open tag if style ≠ neutral]
  [prompt text, with any inline <break> tags already embedded]
  [style close tag if style ≠ neutral]
</speak>
```

All on one line (no newlines inside the ESML string — the daemon parses it
fine but single-line is cleaner for the preview field and CLI argument
quoting).

Tag order matches Jibo's SDK examples: `<pitch>` and `<duration>` before
`<style>`, `<style>` wrapping the text.

---

## 5. Files to modify

| File | Change |
|---|---|
| `SpeechDesignerPanel.swift` | Primary change: add `@Binding var isMarkupMode`, `@Binding var generatedMarkup`, and the new UI sections (mode toggle, style picker, pitch/duration sliders, break button, preview field). |
| `ContentView.swift` | Add `@State var isMarkupMode: Bool = false` and `@State var generatedMarkup: String = ""`. Pass both to `SpeechDesignerPanel`. Pass `isMarkupMode` and `generatedMarkup` into `triggerSynthesis()`. |
| `SynthesisCoordinator.swift` | Add `isMarkupMode: Bool` and `markupPrompt: String` parameters to `synthesize()`. When markup mode: prepend `--markup` arg with the ESML string; pass the raw plain-text prompt to `fetchTokenTimings()` (not the ESML string). |

No new files are required. No changes to `SharedTypes.swift`, `JiboEyeView.swift`, `griffintts_ui.swift`.

---

## 6. Rough implementation order

Build in this order — each step is independently testable:

1. **Mode toggle + passthrough** — add the markup mode toggle and wire it so
   that when on, `--markup '<prompt text>'` is passed (no other markup
   controls yet). This confirms the CLI flag roundtrip works from the UI.
   Verifiable: speak "Hello" with markup mode on; CLI output should show
   `markup_mode: true` in `--json` output.

2. **Style picker** — highest value, simplest control. A `Picker` with the 7
   styles generating a `<style set="...">` wrapper. Most immediately audible
   difference for users.

3. **Markup preview field** — add the read-only ESML preview. Makes all
   subsequent controls immediately verifiable without running synthesis.

4. **Duration slider** — `<duration stretch="N"/>`. Easy to hear (speech rate
   changes). Note the inverse semantics clearly in the UI label.

5. **Pitch slider** — `<pitch halftone="N"/>`. Audibly obvious.

6. **Break button** — `<break time="Nms"/>` appended to prompt. Lower value
   than style/pitch but useful for pacing.

7. **`fetchTokenTimings` fix for markup mode** — ensure the coordinator passes
   plain text (not the ESML string) to `/tts_token_times` so mouth-sync stays
   accurate in markup mode.

8. **`<phoneme>` authoring** — future work; not in initial scope.

---

## 7. Notes on oge.2 boundary

oge.2 confirmed that `preprocessMarkup` in the CLI handles the animation-strip
correctly. The UI markup panel does NOT need to strip animation tags — it
should never generate `<anim>`, `<ssa>`, or `<es>` tags in the first place
(they're not in the UI's control set). The CLI's `--markup` flag with
`preprocessMarkup` is a safety net for when users paste raw ESML with
animation tags into the Prompt field and enable markup mode. That path already
works.

The `<tts params=...>` wrapper from the original SDK closed tag vocabulary:
the UI generates `<speak>` wrappers, not `<tts>`, matching the daemon's actual
dialect. Authors pasting old SDK-style `<tts>` strings into the prompt should
be warned (or the preview should show the `<speak>` output).
