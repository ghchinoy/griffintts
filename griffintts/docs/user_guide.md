# griffintts User Guide

A usage and validation reference for the griffintts CLI and UI. For setup (asset extraction, container installation, build), see [`README.md`](../README.md). For the full empirical prosody data behind everything here, see [`docs/prosody_and_affect.md`](prosody_and_affect.md).

---

## Two synthesis modes

| Mode | Flag | Voice model | Quality | Requirement |
|---|---|---|---|---|
| Container (default) | _(none)_ | `en_us_world` — WORLD vocoder | High-fidelity, characteristic Jibo voice | Voice assets + Apple Container Platform |
| Native | `--native` | `en_us` — classic HTS | Lower fidelity; 31-coeff LPF causes audible flutter | `hts_engine_API` binary only |

All markup (`--markup`) features are container mode only. Native mode strips all tags and synthesizes plain text.

---

## 1. Quick verification (plain text)

Run these five phrases in order when setting up a new installation. Each exercises a distinct capability of Griffin's synthesis pipeline.

### 1.1 Basic synthesis sanity check

```bash
bin/griffintts --ow test_basic.wav "Hi! I am Jibo."
```

**What to listen for**: two short words before the comma, natural rising intonation on "Hi", brief pause at the exclamation mark, then a clean declarative phrase. If the output file is silent or missing, the container did not start — run `container ls` and check `container logs tts_run`.

### 1.2 Date and number normalization (OpenFST)

```bash
bin/griffintts --ow test_norm.wav "On March twenty-first, nineteen eighty-seven, I calculated that I would meet you."
```

**What to listen for**: the date spoken as a natural English phrase ("march twenty-first, nineteen eighty-seven"), not digit-by-digit. If you hear "zero three slash two one..." the OpenFST text normalization is not running — verify the container has the `textnorm/` rules from the robot (see `docs/architecture.md`).

Alternatively, use the reference corpus sentence directly:

```bash
bin/griffintts --ow test_corpus.wav "$(cat testdata/reference_corpus.txt)"
```

This single sentence exercises date normalization (`03/21/1987`), currency (`$1.50`), ordinal (`124th`), explicit pause tokens (`[lpau]`, `[spau]`), and the G2P letter-spelling fallback (`macOS` → "m-a-c-o-s").

### 1.3 Proper noun and rhythm

```bash
bin/griffintts --ow test_rhythm.wav "My name is Jibo. It rhymes with... well, nothing actually."
```

**What to listen for**: "Jibo" pronounced as two distinct syllables ("JEE-bo"), not "jib-oh". A natural hesitation at the ellipsis. The phrase should feel conversational and slightly self-deprecating in rhythm — if it sounds robotic and metronomic, check that you are using the WORLD vocoder path (container mode, not `--native`).

### 1.4 Number and sentence complexity

```bash
bin/griffintts --ow test_complex.wav "I am safer than a toaster, but more dangerous than a pillow."
```

**What to listen for**: natural prosodic arc across the full sentence — the comma pause between clauses, slight emphasis on "safer" and "dangerous" from the acoustic model's stress-prediction, and clean closure on "pillow." This sentence has no normalization edge cases; it is a pure prosody check.

### 1.5 Speed scaling (rate validation)

```bash
bin/griffintts --speed 1.5 --ow test_fast.wav "Processing. Just a moment."
bin/griffintts --speed 0.7 --ow test_slow.wav "Processing. Just a moment."
```

**What to listen for**: the `1.5x` file should be noticeably shorter than the baseline (approximately 33% faster); the `0.7x` file noticeably longer (approximately 43% slower). Compare WAV durations with `ffprobe test_fast.wav` and `ffprobe test_slow.wav`. If both files are the same length, the `duration_stretch` parameter is not reaching the container — restart with `container rm -f tts_run` and re-run.

---

## 2. Affective markup test phrases

All commands below use `--markup` and run in container mode. Copy-paste ready; adjust `--ow` as needed.

### 2.1 Speaking styles

| Style | Δ spectral centroid | Character |
|---|---|---|
| `neutral` | baseline | Baseline — no modification |
| `enthusiastic` | +100 Hz, slightly faster | Most distinct; highest energy |
| `confident` | +91 Hz | Clear, assured delivery |
| `news` | +87 Hz, slightly slower | Measured, deliberate pacing |
| `confused` | +85 Hz, slightly slower | Rising uncertainty |
| `sheepish` | +65 Hz, slightly slower | Hedged, apologetic |
| `excited` | ~+10 Hz | Marginal — barely distinguishable from neutral on short text |

**enthusiastic** — a greeting

```bash
bin/griffintts --markup --ow style_enthusiastic.wav \
  '<style set="enthusiastic">Oh, hey! I was hoping you would come by.</style>'
```

Listen for: pitch brightness noticeably higher than the same phrase without the tag; slightly faster delivery; more energetic quality overall.

**sheepish** — an admission

```bash
bin/griffintts --markup --ow style_sheepish.wav \
  '<style set="sheepish">I may have said something that was not entirely accurate. My apologies.</style>'
```

Listen for: slightly slower than neutral, hesitant quality, pitch shifted up relative to neutral but with a softer energy.

**confident** — a factual answer

```bash
bin/griffintts --markup --ow style_confident.wav \
  '<style set="confident">The capital of France is Paris. You are welcome.</style>'
```

Listen for: assured, direct delivery; pitch brighter than neutral but without the rush of `enthusiastic`.

**news** — an information delivery

```bash
bin/griffintts --markup --ow style_news.wav \
  '<style set="news">Today is Tuesday, July seventh. Conditions are clear with light winds from the northwest.</style>'
```

Listen for: measured, slightly slower cadence, appropriate for reading aloud factual information; comparable brightness to `confident` but with more deliberate pacing.

**confused** — uncertainty

```bash
bin/griffintts --markup --ow style_confused.wav \
  '<style set="confused">I am not sure I understood that. Could you say it a different way?</style>'
```

Listen for: slower than neutral, pitch shifted up (uncertainty registers as higher centroid), questioning quality.

**excited** — binary artifact, not recommended

```bash
bin/griffintts --markup --ow style_excited.wav \
  '<style set="excited">I just discovered something and it is the most remarkable thing I have encountered in all of my operational experience.</style>'
```

**Do not use `excited` in production ESML.** It is not an official SDK style —
the MIT HRI2024 ESML SDK reference (Jibo Inc. archive) lists exactly 6 styles;
`excited` is absent. Empirically: ~10 Hz centroid shift, indistinguishable from
neutral even on long prompts. Use `enthusiastic` instead, which is the most
acoustically distinct official style. See `docs/prosody_and_affect.md` §4.

---

### 2.2 Pitch modification

All four pitch subtypes produce monotonic, directionally-correct effects measured against a 1262 Hz baseline centroid.

**pitch down — contemplative**

```bash
bin/griffintts --markup --ow pitch_down.wav \
  '<pitch halftone="-5">Give me a moment. Some questions deserve a slower answer.</pitch>'
```

Listen for: noticeably lower register; the same phrase without the tag will sound appreciably brighter.

**pitch up — surprised**

```bash
bin/griffintts --markup --ow pitch_up.wav \
  '<pitch halftone="+5">You remembered! That is actually kind of remarkable.</pitch>'
```

Listen for: noticeably higher, slightly thinner quality; also slightly louder (halftone=+10 produces a significant RMS increase; +5 is more moderate).

**pitch band narrow**

```bash
bin/griffintts --markup --ow pitch_band_narrow.wav \
  '<pitch band="0.5">I will keep this brief and to the point.</pitch>'
```

Listen for: flatter, less expressive delivery — reduced pitch variation across the phrase.

**pitch band wide**

```bash
bin/griffintts --markup --ow pitch_band_wide.wav \
  '<pitch band="2.0">Oh, that is a very interesting question. I have thoughts about this.</pitch>'
```

Listen for: more expressive, wider pitch range across the utterance.

---

### 2.3 Duration modification

**Important**: `<duration stretch="2.0">` makes speech **slower** (direct rate multiplier). This is the **opposite** of `--speed 2.0`, which makes speech faster. Do not confuse them — see §4 for the full explanation and `docs/prosody_and_affect.md` §6 for measurements.

**slower — for dramatic effect**

```bash
bin/griffintts --markup --ow duration_slow.wav \
  '<duration stretch="2.0">Every. Word. Matters.</duration>'
```

Listen for: approximately twice the duration of the same phrase without the tag. Measured baseline: `stretch=2.0` produces ~5.4s from a ~2.8s baseline.

**faster — for efficiency**

```bash
bin/griffintts --markup --ow duration_fast.wav \
  '<duration stretch="0.5">Okay okay okay I understand let us move on.</duration>'
```

Listen for: noticeably compressed, faster-than-normal delivery; `stretch=0.5` halves duration.

---

### 2.4 Break (real silence insertion)

The `<break>` tag inserts actual silence — it is not spoken as text. The `size=` attribute is in seconds; measured real durations run 105–128% of requested (natural phrase boundary contributes additional silence).

**dramatic pause in a punchline**

```bash
bin/griffintts --markup --ow break_pause.wav \
  'I have a lot of knowledge.<break size="0.8"/>Most of it is about penguins.'
```

Listen for: a genuine ~0.9s silence between the two clauses — not a word, not a breath sound, actual silence. Use `ffprobe` or an audio editor to verify silence amplitude near zero.

**short transition pause**

```bash
bin/griffintts --markup --ow break_short.wav \
  'Your request is processing.<break size="0.3"/>Here is what I found.'
```

Listen for: ~0.38s silence (measured: 0.3s requested → +0.384s actual at this size).

---

### 2.5 Phoneme override

```bash
bin/griffintts --markup --ow phoneme_bono.wav \
  '<phoneme ph="b aa n ou">Bono</phoneme> was not in Jibo'\''s dictionary, but that is fine now.'
```

Listen for: "Bono" pronounced with the explicit phoneme sequence rather than G2P-derived pronunciation. The phoneme notation follows the Combilex phoneme set; stress markers are integers (0=none, 1=primary, 2=secondary).

---

### 2.6 Say-as (spell out)

```bash
bin/griffintts --markup --ow say_as_jibo.wav \
  'My name is <say-as spell="jibo"/>. That is J, I, B, O.'
```

Listen for: "jibo" spelled letter-by-letter in the `<say-as>` portion, then spoken as a full word in "That is J, I, B, O." The spelled version is confirmed 2.44× longer than the plain word (0.576s vs. 1.408s).

---

## 3. Combined markup examples

These are representative of real Jibo skill response strings — the kind of text a skill action would send to the TTS daemon. Multiple tags can be composed; audio tags compose, animation tags are silently stripped.

### 3.1 Greeting with style and break

```bash
bin/griffintts --markup --ow combined_greeting.wav \
  '<style set="enthusiastic">Hey, good to see you!<break size="0.4"/>What can I do for you today?</style>'
```

What this exercises: `enthusiastic` style applied to the whole phrase, with a genuine pause mid-greeting separating the initial greeting from the follow-up question. The break fires inside the style tag and both effects apply.

### 3.2 Apology with sheepish delivery

```bash
bin/griffintts --markup --ow combined_apology.wav \
  '<style set="sheepish">I think I may have gotten that wrong.<break size="0.5"/>Let me try that again.</style>'
```

What this exercises: `sheepish` style + mid-phrase break. The combination produces the hesitant, regrouping quality of a genuine apology rather than a flat correction.

### 3.3 Information delivery with style and phoneme

```bash
bin/griffintts --markup --ow combined_info.wav \
  '<style set="news">Your appointment is confirmed with <phoneme ph="d r r eh b ax k">Dr. Rebak</phoneme> at three fifteen tomorrow afternoon.</style>'
```

What this exercises: `news` style for measured delivery + phoneme override for a proper noun that G2P would likely mispronounce. Replace the phoneme string with the Combilex transcription appropriate to the name you are testing.

### 3.4 Thinking response with confident delivery

```bash
bin/griffintts --markup --ow combined_thinking.wav \
  '<style set="confident">That is a reasonable question.<break size="0.3"/>Based on what I know, the answer is probably yes — though I would want to verify before committing to it.</style>'
```

What this exercises: `confident` style sets the overall delivery register; the break creates a brief thinking pause; the hedged content of the sentence contrasts interestingly with the confident delivery, which is plausible Jibo character behavior.

---

## 4. Speed flag (`--speed`)

The `--speed` flag and the `<duration stretch>` markup tag both change speech rate but via different mechanisms with **opposite semantics**:

| Control | Value | Effect | Mechanism |
|---|---|---|---|
| `--speed 2.0` | 2.0 | Faster | Sets `duration_stretch` JSON field as inverse-rate multiplier: `actual_duration ≈ baseline / 2.0` |
| `--speed 0.5` | 0.5 | Slower | Same mechanism: `actual_duration ≈ baseline / 0.5` |
| `<duration stretch="2.0">` | 2.0 | Slower | Direct rate multiplier: doubles phoneme duration |
| `<duration stretch="0.5">` | 0.5 | Faster | Halves phoneme duration |

**Speed flag examples:**

```bash
# 1.0x baseline (default)
bin/griffintts --ow speed_baseline.wav "I process language at a normal conversational pace."

# 1.5x fast
bin/griffintts --speed 1.5 --ow speed_fast.wav "I process language at a normal conversational pace."

# 0.7x slow
bin/griffintts --speed 0.7 --ow speed_slow.wav "I process language at a normal conversational pace."

# 2.0x fast (maximum useful range)
bin/griffintts --speed 2.0 --ow speed_max.wav "Quick answer: yes."
```

Compare output file durations with `ffprobe <file>.wav | grep Duration` to verify the scaling ratios. At 1.5x you should see approximately 0.67× the baseline duration; at 0.7x approximately 1.43× the baseline.

`--speed` and `--markup` can be combined; `--speed` sets the baseline rate and `<duration>` tags apply relative to that.

---

## 5. Validation: what good output sounds like

Correct synthesis through the container path has a distinctive quality that is immediately recognizable once you have heard it. Griffin's voice is slightly synthetic — this is intentional, it is the characteristic texture of HTS+WORLD vocoder synthesis — but it has natural-sounding prosodic variation: stressed syllables get longer duration and higher energy, phrase-final syllables drop in pitch, and complex sentences arc correctly across clauses without robotic uniformity.

Specific things to listen for that confirm correct operation:

- **WORLD vocoder brightness**: the voice has a slightly brighter, cleaner spectral quality than older HTS synthesis. If it sounds muffled or has a "talking through cloth" quality, the WORLD model path may not be loading — check that `assets/en_us_world/` is present and the container is running the correct binary.
- **Natural number expansion**: dates, currency, and ordinals should sound like a human reading them aloud, not digit strings. `03/21/1987` → "march twenty first nineteen eighty seven."
- **Markup effect size**: style differences should be audible without headphones. `enthusiastic` vs. `neutral` is the most reliable sanity check — if they sound identical, markup is not reaching the synthesis engine.
- **Silence fidelity**: `<break>` tags should produce true silence (near-zero amplitude), not a faint noise floor or a spoken word.

**If something sounds wrong:**

```bash
# Check if the container is running
container ls

# Fetch daemon logs for synthesis errors
container logs tts_run

# Hard restart if the container is in a bad state
container rm -f tts_run
# Next griffintts invocation will rebuild and restart it automatically

# Verify assets are present
ls assets/en_us_world/
ls assets/bin/jibo-tts-service
```

The daemon is known to crash with `Poco::SystemException` + SIGABRT after approximately 40 sequential synthesis calls in a single session. `griffintts` detects and recovers from this automatically via `ensureContainerRunning()`, but if you are running a large batch, restart the container between sessions. See `docs/prosody_and_affect.md` §12 for details.

For native mode (`--native`), the expected output quality is lower: the classic `en_us` model running on macOS with `hts_engine_API` exhibits audible flutter caused by phase misalignment with Jibo's custom 31-coefficient LPF stream. This is a known limitation of the native path, not a setup error.

---

## 6. griffintts-ui (interactive authoring)

The `griffintts-ui` SwiftUI app provides a visual frontend for the same synthesis backend. Build and launch:

```bash
make -C ../griffintts build     # griffintts binary must exist first
make -C ../griffintts-ui build
open ../griffintts-ui/bin/GriffinTTS.app
```

The app renders Jibo's eye with cursor-tracking and blink animation, and syncs the eye's speaking motion to synthesis token timings retrieved from the TTS daemon's `/tts_token_times` endpoint.

**Note on the speaking-motion display**: the eye-pulse and wiggle animation in `griffintts-ui` is an approximation computed from phoneme token timings. It is not driven by Jibo's actual `AnimDB` animation system — that system runs on-robot inside the `@be/be` Electron process and requires the robot's hardware. The visual sync in the UI is a plausible reconstruction, not a replay of canonical Jibo behavior. See `docs/prosody_and_affect.md` §10 for the architectural boundary.

Toggle "Standalone Native Mode" in the UI to switch to the `--native` path without rebuilding — useful for comparing the two synthesis modes interactively.

The UI logs millisecond-precision synthesis and playback timing to the terminal when launched from a shell, which is useful for debugging audio device latency. See the UI's `README.md` for details.

---

## 7. AX / agent usage

Two flags support machine-readable integration:

### `--json`

Suppresses human-readable status output and emits a JSON object. In markup mode, the JSON includes which animation tags were stripped:

```bash
bin/griffintts --json --ow output.wav "Hello from an automated pipeline."
```

```json
{"status":"ok","output_file":"output.wav","duration_s":1.234}
```

With markup containing animation tags:

```bash
bin/griffintts --markup --json --ow output.wav \
  '<anim cat="happy" nonBlocking="true">Sure!</anim> <style set="confident">Here is what I found.</style>'
```

```json
{"status":"ok","output_file":"output.wav","duration_s":0.987,"stripped_tags":["anim"]}
```

### `--dry-run`

Validates the input (parses markup, checks container reachability) without synthesizing audio or writing files. Use for pre-flight checks in pipelines:

```bash
bin/griffintts --markup --dry-run --json \
  '<style set="enthusiastic">Would this synthesis request work?</style>'
```

### Stdin pipe in a pipeline

```bash
# Generate text elsewhere, pipe into griffintts
echo "The weather today is partly cloudy." | bin/griffintts --ow weather.wav

# With markup via pipe
printf '<style set="news">Conditions: partly cloudy, high of 68.</style>' \
  | bin/griffintts --markup --ow weather_news.wav
```

Stdin and the positional argument are mutually exclusive; if both are provided, the positional argument takes precedence. The pipe form is the natural interface for skill-action orchestration where text is generated dynamically.
