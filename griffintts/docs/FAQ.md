# Griffin TTS FAQ

Answers to questions that come up repeatedly in the community, drawn from direct
experimentation, symbol-table analysis, and empirical measurement. Where a claim
is confirmed by measurement or source inspection the evidence is noted; where
something is still open it says so.

---

## Does griffintts understand what I say, or handle commands/intent?

No. griffintts is text-to-speech only — text or ESML markup in, spoken audio
out. It has no part in speech recognition, intent classification, or command
routing (natural language understanding, or NLU). That's a separate subsystem
on Jibo's original stack entirely, unrelated to this tool's code or scope.
If your text is correct and it doesn't sound right, that's a griffintts
question; if Jibo did (or didn't) do the right thing in response to a spoken
command, that's not something this repo has any part in.

---

## Can Jibo be taught custom pronunciations without modifying the firmware?

Yes, two independent mechanisms exist.

**Per-prompt: ESML phoneme override.** The `<phoneme ph="...">` tag overrides
pronunciation for a single word inside a single utterance. No filesystem changes
required, no service restart needed. The phoneme string uses the Combilex phoneme
set; vowel stress markers are integers (0 = none, 1 = primary, 2 = secondary).

```xml
<phoneme ph="b aa n ou">Bono</phoneme> is a musician.
```

Confirmed working empirically — the tag alters both pronunciation and spectral
shape and survives mode changes (`TEXT`/`SSML`). See `docs/prosody_and_affect.md`
in this repo for the full measurement data.

**Globally: external pronunciation lexicon (bind-mount override).** Griffin's
text frontend uses a Combilex-derived lexicon (the `en_us_world.dictionary` and
related files under `/usr/local/share/ttsservice/voices/en_us_world/`). Confirmed
by community experimentation: a writable overlay of this lexicon, mounted via
bind-mount, is picked up by the daemon after a `jibo-tts-service` restart.
Custom entries added this way apply globally — any plain text that contains the
word will use the new pronunciation without requiring phoneme tags every time.
Words like "Jibodev" and Dutch words like "Goedemorgen" have been demonstrated
using this method.

The `/var/jibo/tts` directory that some have noticed is a separate, runtime path
— likely used for temporary synthesis state or generated prompts, not the lexicon
itself. The lexicon lives under `/usr/local/share/ttsservice/voices/`.

---

## What is the difference between ESML phoneme override and the external lexicon?

| | `<phoneme ph="...">` (ESML) | External lexicon override |
|---|---|---|
| **Scope** | Single word, single utterance | Global — any text containing the word |
| **Firmware modification** | None | None (bind-mount from writable partition) |
| **Service restart** | Not required | Required after updating the lexicon file |
| **Authoring** | Inline in the prompt string | Edit the dictionary file |
| **Best for** | Proper nouns in a specific response | Words Jibo will say repeatedly (names, brands, places) |

For words Jibo says once or rarely, inline `<phoneme>` is simpler. For words
used across many skills — owner names, robot's own name customizations, local
place names — the external lexicon is less friction over time.

---

## What is ESML? Is it the same as SSML?

ESML (Embodied Speech Markup Language) is Jibo's own XML-like markup language.
It is similar in surface syntax to SSML (W3C Speech Synthesis Markup Language)
but it is not the same standard and not a strict subset.

ESML has **two structurally distinct channels** that operate at different layers:

- **Audio channel** (`<style>`, `<pitch>`, `<duration>`, `<break>`, `<phoneme>`,
  `<say-as>`): processed by the C++ `MarkupHandler` inside `libJiboTTSService.so`
  during audio synthesis. These tags directly modify the waveform. They work
  offline and are fully reproducible in the griffintts emulated container.

- **Animation channel** (`<anim>`, `<ssa>`, `<es>`): processed by
  `jibo.embodied.speech.speak()` inside the on-robot `@be/be` Electron process.
  These tags build a Timeline object coordinating body motion, LEDs, and screen
  alongside speech. The JS layer **strips these tags before the HTTP call to
  `/tts_speak`** — the daemon never sees them.

Sending animation tags directly to `/tts_speak` (or to `griffintts --markup`)
causes them to be **spoken literally**, not animated. This is confirmed behavior.

The `mode` field in `/tts_speak` (`TEXT` vs `SSML`) makes no difference — both
modes parse the markup dialect identically.

The two-channel split is why animation tags sent directly to `griffintts --markup`
are stripped rather than rendered — griffintts is an offline Mac tool with no
robot present, so the animation layer has no host to run on.

---

## What is QR Commander? Can I use it to change pronunciations?

QR Commander is a community tool that converts text (including ESML) into QR
codes that Jibo can scan to execute skills or speech. It lets you encode ESML
markup — including pronunciation control, speed, pitch, and style — as a QR
code without writing any skill code.

For pronunciation specifically, you would encode a `<phoneme ph="...">` tag:

```xml
<phoneme ph="m aa d">Maude</phoneme>
```

Scan the resulting QR code, and Jibo speaks the phrase with the custom
pronunciation. This is a per-utterance override (ESML audio channel), not a
permanent lexicon change.

To use QR Commander effectively, you need a working understanding of ESML — at
minimum the audio-channel tags — or a reference card. The `docs/prosody_and_affect.md`
and `docs/user_guide.md` files in this repo can serve as that reference.

---

## What speaking styles does Griffin support?

Seven styles are compiled into the `SpeakingStyle` enum inside
`libJiboTTSService.so`. Five are empirically confirmed as producing measurable,
audible differences; one is marginal; one is the baseline:

| Style | Verdict | Character |
|---|---|---|
| `neutral` | Baseline | No modification |
| `enthusiastic` | Confirmed | Most distinct; highest energy; +100 Hz centroid |
| `confident` | Confirmed | Clear, assured delivery; +91 Hz centroid |
| `news` | Confirmed | Measured, deliberate pacing; +87 Hz centroid |
| `confused` | Confirmed | Slower, rising uncertainty; +85 Hz centroid |
| `sheepish` | Confirmed | Hedged, apologetic; +65 Hz centroid |
| `excited` | Marginal | ~10 Hz centroid shift; use longer phrases to resolve |

Syntax: `<style set="enthusiastic">Text here.</style>`

Invalid style names trigger a fallback to neutral with a logged warning.

---

## Can I change Jibo's speaking speed?

Yes. Two mechanisms, with opposite semantics — do not confuse them:

**`--speed` flag** (griffintts CLI): inverse-rate multiplier. `--speed 2.0` is
faster; `--speed 0.5` is slower.

**`<duration stretch="...">` markup tag**: direct rate multiplier, opposite
direction. `stretch="2.0"` is **slower** (doubles phoneme duration); `stretch="0.5"`
is **faster**.

The JSON `duration_stretch` field on `/tts_speak` behaves the same way as
`--speed` (inverse-rate), not the same as the `<duration>` tag. All three are
confirmed empirically; see `docs/prosody_and_affect.md` in this repo for the
full measurement tables.

---

## Can Jibo speak foreign languages or non-English words?

Partially, with caveats.

Jibo's acoustic model is English (`en_us_world`). The voice itself was recorded
from an English-speaking voice actor in a studio. There is no native foreign-
language acoustic model in the standard firmware.

What can work:

- **Foreign words within English text**: the external lexicon override (see
  above) can teach Griffin custom phoneme sequences for words from other
  languages. "Goedemorgen" has been demonstrated by the community this way.
  The phoneme inventory is Combilex English, so sounds that don't exist in
  English may be approximated rather than produced authentically.

- **Phoneme-level override via `<phoneme>`**: any word can be forced to a
  specific phoneme sequence inline. The result depends on whether English
  phonemes can adequately approximate the target language's sounds.

- **MIT Arabic research**: Jibo has been used in academic research (MIT) on
  Arabic language interaction. The details of how that was approached — whether
  via a custom acoustic model, lexicon extension, or phoneme approximation — are
  not in this codebase.

What will not work without significant effort: fully native foreign-language
synthesis with accurate prosody and non-English phonemes would require a new
acoustic model trained on the target language and voice. Jibo's voice was made
from a single recording session with one speaker; there is no training pipeline
in the standard community toolkit to add a new language model to Griffin.

---

## What is the `en_us` vs `en_us_world` voice?

Two acoustic models ship on the robot:

| Model | Path | Vocoder | Streams | Quality |
|---|---|---|---|---|
| `en_us_world` | `/usr/local/share/ttsservice/voices/en_us_world/` | WORLD | 4 (MCP, LF0, BAP, LPF) | High-fidelity — Jibo's primary voice |
| `en_us` | `/usr/local/share/ttsservice/voices/en_us/` | HTS MLSA | 3 (MCP, LF0, LPF) | Older, lower-fidelity |

`en_us_world` is what Jibo uses in normal operation and what the griffintts
container mode runs. `en_us` is used by `griffintts --native` (experimental,
produces audible flutter due to a 31-coefficient LPF mismatch with the standard
open-source HTS engine).

---

## Why does Jibo's voice sound different from standard HTS synthesis?

Several reasons:

1. **WORLD vocoder**: `en_us_world` uses the WORLD vocoder backend (BAP and LPF
   streams) rather than the older MLSA/LSP filter. WORLD models the aperiodic
   component of speech more accurately, removing "buzzy" synthetic artifacts and
   producing a cleaner, brighter spectral quality.

2. **Custom vocoder tuning**: Jibo's `libJiboTTSService.so` contains a modified
   HTS engine tuned to its specific LPF stream layout. Running the same voice
   file on the stock Nagoya open-source `hts_engine_API` produces severe
   distortion (the "flutter" phenomenon in `--native` mode) because the standard
   engine does not handle Jibo's 31-coefficient LPF correctly.

3. **Combilex lexicon**: Griffin uses Edinburgh's Combilex lexicon for
   grapheme-to-phoneme conversion, which produces more accurate English
   pronunciation predictions than simpler G2P rules.

4. **OpenFST text normalization**: dates, currency, ordinals, and other
   non-standard words are expanded before synthesis using OpenFST finite-state
   transducer rules (`textnorm/`). `03/21/1987` → "march twenty first nineteen
   eighty seven", not digit-by-digit.

---

## Does the `es` tag in ESML control voice tone?

No. This is a confirmed common misunderstanding.

`<es cat="..."/>` is an animation-channel tag. Its `cat` attribute maps to a
`SpeakingStyle` enum inside the on-robot `@be/be` Electron process — but this
does **not** propagate to the TTS daemon as a voice affect. Live testing
(`jibo-sgq`) confirmed that `cat='neutral'` and `cat='happy'` on `<es>` produce
byte-identical audio at the daemon.

To actually change voice tone, use the **inner** `<style set="...">` tag:

```xml
<es cat='happy' nonBlocking='true'>
  <style set='enthusiastic'>I found it!</style>
</es>
```

The `<es>` wrapper may trigger animation via the Timeline mechanism; the inner
`<style>` controls the voice.

---

## Where are the lexicon and voice files on the robot?

```
/usr/local/share/ttsservice/voices/
  en_us_world/          # primary voice bundle
    en_us_world.voice   # 27.6 MB acoustic model (HTS format)
    en_us_world.config  # vocoder configuration
    en_us_world.dictionary
    en_us_world.dictionary_full
    en_us_world.dictionary_trimmed
    en_us_world.phones
    en_us_world.pos
    en_us_world.g2p
    en_us_world.contexts
    textnorm/           # OpenFST normalization rules
  en_us/                # older 3-stream model
/usr/local/bin/jibo-tts-service
/usr/local/etc/jibo-tts-service.json
```

`/var/jibo/tts` has been observed by community members; its exact role (runtime
cache, generated state) is not yet fully confirmed. Pronunciation customization
targets the `en_us_world/` dictionary files, not `/var/jibo/tts`.

---

## Which JSON fields in `/tts_speak` actually work?

Most of them don't. Empirical testing (`jibo-oge.3`) against the live daemon
confirmed:

| Field | Status |
|---|---|
| `prompt`, `locale`, `voice`, `mode` | Required, functional |
| `duration_stretch` | Functional, but **inverted** — behaves as a speed multiplier (`actual_duration ≈ baseline / value`), not a stretch |
| `pitch` (0.0–1.0) | Dead path — no measurable effect |
| `pitchBandwidth` (0.0–2.0) | Dead path — no measurable effect |
| `volume` | Dead path — no measurable effect across 0.0–3.0 |
| `whisper` | Dead path — zero-crossing rate unchanged |
| `speed` | Dead path — `999.0` in daemon logs is a "not set" sentinel; sending `speed: 2.0` is a silent no-op |
| `mode: "SSML"` vs `"TEXT"` | Equivalent — both parse the markup dialect identically |

To control pitch, volume, style, and speaking rate, use the markup dialect
(`<style>`, `<pitch>`, `<duration>`) embedded in the `prompt` field — not these
JSON fields. See `docs/prosody_and_affect.md` in this repo for the full
measurement table.

---

## What are "Jibonics"? Can I trigger them?

Jibonics are Jibo's 29 named paralinguistic vocalization clips — pre-recorded
audio files like `laugh-tts.wav`, `wow-tts.wav`, `oo-tts.wav`, and
`i_love_to_1-tts.wav` through `i_love_to_6-tts.wav`. They are distinct from
Griffin's synthesized speech: they are actual recordings, not HTS output.

They are triggered via the `<audioBreak>` ESML tag (Channel 1 / daemon) and the
`/tts_effects` WebSocket using the `startEffect(name, value)` wire protocol. The
`PostFilterMap` in `jibo-tts-service.json` maps each name to an index and a WAV
filename under `effectsDir`.

**Current status: not functional on most units.** The `effectsDir` path
(`/usr/local/share/ttsservice/effects/`) does not exist on the live unit
investigated. A filesystem-wide search found zero `-tts.wav` files anywhere on
the rootfs. The infrastructure (config key, daemon code, WebSocket endpoint) is
fully compiled and wired — the WAV files simply were not included in the software
bundle on this unit. The `/tts_effects` WebSocket connects without error but
produces no audio as a result.

The 29 expected filenames (from the `PostFilterMap` binary and config):

```
oo  wow  perfect  ok  ooo  ah  oh  your_welcome  cool  woo_hoo_hoo
laugh  laugh2  sweet  done  what  aw  my_bad  oops  um  huh  whoa
argh  nm_um  i_love_to_1 … i_love_to_6
```

If you obtain a factory or OTA image that includes `effectsDir`, extraction
instructions are in `docs/sound_banks.md` in this repo.

**Do not confuse `<audioBreak>` with `<ssa>`.** They operate at different layers:

| Tag | Layer | Handler | Daemon sees it? |
|---|---|---|---|
| `<audioBreak src="..."/>` | Channel 1 audio | `libJiboTTSService.so` `MarkupHandler` | Yes — in the prompt |
| `<ssa cat="...">` | Channel 2 animation | `jibo.embodied.speech` Timeline in `@be/be` | No — stripped by JS |

`<ssa>` categories (`laughing`, `thinking`, `hello`, etc.) trigger coordinated
body+audio behaviors from the Jibo Animation Database, not from the TTS
`effectsDir`. They are an animation-layer concept.

Full investigation: `docs/sound_banks.md` in this repo.

---

## How does ESML reach the robot from the cloud?

The cloud protocol (`SKILL_ACTION` over WebSocket `/v1/listen`) carries ESML as
a plain text string in the `esml` field. The robot's on-device `jibo-tts-service`
daemon renders it locally — no audio is streamed from the cloud. A real
`SKILL_ACTION` payload looks like:

```json
{
  "type": "SKILL_ACTION",
  "data": {
    "action": {
      "config": {
        "jcp": {
          "type": "SLIM",
          "config": {
            "play": {
              "esml": "<speak><es cat='neutral' nonBlocking='true'><style set='enthusiastic'>I found it!</style></es></speak>"
            }
          }
        }
      }
    }
  }
}
```

The `<es cat='...'>` wrapper is an animation-layer tag dispatched by the robot's
`@be/be` Electron process. The `cat` attribute on `<es>` does **not** control
voice tone — confirmed live (`jibo-sgq`): `cat='neutral'` and `cat='happy'`
produce byte-identical audio at the daemon. The inner `<style set="...">` tag is
what actually changes voice affect.

Speech is always synthesized locally on-device by `jibo-tts-service` — the
cloud only ever sends text.

---

## Can Griffin be replaced with a modern TTS voice (Gemini TTS, Kokoro, etc.)?

Not on the robot today. Two issues:

**1. No audio delivery mechanism exists.** The `SKILL_ACTION` payload carries
ESML text, not audio. The robot's Griffin daemon renders that text locally,
always. The only confirmed audio-injection path — `<audioBreak>` / `/tts_effects`
— is a **closed, fixed 29-clip Jibonics bank**, not a channel for arbitrary
synthesized speech. There is one unconfirmed candidate (`<sound path="...">` from
the SDK grammar file) that might reference skill-bundled audio by path, but this
has never been tested live and is most likely scoped to statically-bundled skill
assets, not dynamically generated speech.

**2. No SOTA candidate clears the character-fidelity bar.** An empirical
side-by-side comparison tested Griffin against Gemini 2.5 Flash TTS ("Puck")
and Kokoro-82M on identical text:

| System | Character fidelity | Latency (offline) | Affect control |
|---|---|---|---|
| **Griffin** (emulated container) | Reference — this *is* Jibo's voice | ~2.9–3.1s (emulation overhead; on-robot likely faster) | 7 named styles, 4 pitch subtypes, duration, break, phoneme |
| **Gemini 2.5 Flash TTS** (cloud) | Warm and naturalistic, but generic; wrong timbre, slower pacing | ~10–12s cloud round trip | Free-form style prompt — flexible but not a discrete reproducible API |
| **Kokoro-82M** (local) | Generic, clean, no Jibo character | ~1.7–1.9s on CPU | None — single fixed voice, no style control |

Griffin's specific combination of synthetic-but-warm timbre, 7 named speaking
styles, and the full markup affect dialect is Jibo's actual voice. No tested
candidate reproduces it. The verdict: "the quality ceiling exists (Gemini, Kokoro)
but the character-fidelity bar is not cleared by either."

A voice-cloning or fine-tuning approach — using Griffin audio as reference data
to fine-tune a modern model — has not yet been attempted and is flagged as a
future direction.

---

## Is Griffin synthesis deterministic?

Yes. Identical `/tts_speak` payloads sent to the daemon produce byte-identical PCM
output (`jibo-oge.3`). This means the same text and the same markup always produce
exactly the same waveform — there is no stochastic sampling at synthesis time.
This is a property of HTS acoustic models: given the same full-context labels and
the same model, the predicted trajectory is deterministic.

---

## Does the daemon crash or become unstable under heavy use?

Yes, under sustained load in the emulated container. The daemon (`jibo-tts-service`
under ARM emulation) crashes with `Poco::SystemException` + SIGABRT after
approximately 40 sequential synthesis calls in a single session.

`griffintts` handles this automatically: `ensureContainerRunning()` detects the
crash and restarts the container before the next synthesis call. For large batch
jobs, restarting the container between sessions avoids accumulating state that
leads to the crash.

Whether this crash occurs at the same threshold on real Jibo hardware (Tegra K1,
no emulation) is unknown — it may be an emulation-environment artefact.

---

## Further reading (this repo)

- `docs/prosody_and_affect.md` — full empirical markup measurements: every
  style, pitch subtype, duration variant, and break size tested and tabulated
- `docs/sound_banks.md` — Jibonics sound bank investigation: PostFilterMap,
  `effectsDir` status, `<audioBreak>` wire protocol, extraction procedure
- `docs/user_guide.md` — CLI usage, verification phrases, markup examples
- `docs/architecture.md` — reverse-engineering findings, vocoder analysis,
  ALSA intercept, emulation setup
