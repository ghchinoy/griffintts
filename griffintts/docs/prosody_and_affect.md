# Jibo Griffin TTS: Prosody, ESML Markup & Vocal Affect

This document explains the linguistic, phonetic, and DSP mechanisms that govern Jibo's expressive vocal personality ("Griffin"). Every mechanism below is labeled with its confirmation status per this project's documentation standard (see `docs/README.md`, "Confirmed vs. inferred"). All empirical results are from controlled measurements against the live emulated container.

**Reproduce these results yourself**: two scripts are available:
- `.venv/bin/python tools/griffintts/scripts/confirm_prosody_params.py` — original request-field sweep (§2 below)
- `.venv/bin/python tools/griffintts/scripts/confirm_markup_dialect.py` — native markup dialect sweep (§3–§6; this is the primary reference for affect control)

Both require `tts_run` container running and `numpy` installed.

---

## Status Legend

| Symbol | Meaning |
|---|---|
| ✅ CONFIRMED | Empirically measured effect on output audio, reproducible |
| ❌ DISCONFIRMED | Empirically tested and found to have **no measurable effect**, or behaviour opposite to documentation |
| ❓ UNCONFIRMED | Not yet tested; architectural inference only |
| ⚠️ MARGINAL | Measurable but weak — within noise for short prompts; increase prompt length to resolve |

---

## 1. Model-Driven Prosody (Automatic, No Parameters Needed) — ✅ CONFIRMED by design

This layer requires no request-level opt-in; it is inherent to how the HTS acoustic model works and doesn't need per-parameter testing — it's a property of the shipped model, verified structurally in [`docs/architecture.md`](architecture.md):

1. **G2P & Context Extraction**: Text is converted to phonemes with lexical stress markers (`en_us.dictionary_full`: `1 h e | 0 l ou` for "hello" — primary stress on first syllable).
2. **HTS Full-Context Labels**: ~113 structural features per phone (syllable position, word boundaries, phrase-terminal status) are compiled from the above.
3. **HMM State Prediction**: Jibo's acoustic decision trees read these labels to predict duration, F0 contour, and spectral parameters automatically — stressed syllables get longer duration and higher energy without any explicit instruction.

This part of the original documentation stands as written.

---

## 2. Request-Level JSON Fields (`/tts_speak` body)

These are the fields in the JSON body of a `/tts_speak` POST request, as exposed by the JS SDK's `defaultTTSReqBody`/`_sendTTSRequest`. Each was empirically tested by sending isolated requests to the emulated `tts_run` container and analyzing captured PCM (byte length / duration, RMS, spectral centroid).

**Important framing**: these JSON fields are a separate, shallower control path from the markup dialect (§3). Most affect is delivered via markup, not these fields — pitch and style fields here are confirmed dead; pitch and style via markup tags are confirmed live.

| Field | Status | Empirical Result |
|---|---|---|
| `duration_stretch` | ✅ **CONFIRMED**, but **semantics are inverted** from the JS SDK's own docstring | Functions as an inverse-rate multiplier: `actual_duration ≈ baseline_duration / value`. Higher values = faster speech. Opposite of the docstring "stretch." See §2.1. |
| `pitch` (0.0–1.0 scale) | ❌ **DISCONFIRMED** | Tested 0.1 vs. 0.9: spectral centroid varied <2%, no monotonic trend — noise only. Use `<PITCH>` markup instead (§4). |
| `pitchBandwidth` (0.0–2.0 scale) | ❌ **DISCONFIRMED** | No consistent centroid trend across tested range. Use `<PITCH band=>` markup instead (§4). |
| `volume` | ❌ **DISCONFIRMED** | RMS unchanged across 0.0–3.0 range — a true mute (0.0) produced no silence. |
| `whisper` (bool or string) | ❌ **DISCONFIRMED** | Zero-crossing-rate essentially unchanged vs. baseline; a real whisper would show dramatically higher ZCR. |
| `speed` (seen in daemon debug log) | ❌ **DISCONFIRMED as a request field** | The `999.0` value in the daemon's internal log is a "field not set" sentinel; sending `speed: 2.0` produces byte-identical output to baseline. |
| `mode: "SSML"` vs `mode: "TEXT"` | ✅ **CONFIRMED equivalent** (updated) | Both modes parse the markup dialect (§3) identically. `mode` does not gate markup processing. |

### §2.1: `duration_stretch` — confirmed effect, inverted direction

Measured on a fixed prompt (baseline 2.027s):

| `duration_stretch` value | Measured duration | Ratio vs. baseline | Expected if inverse-rate (`1/value`) |
|---|---|---|---|
| 2.0 | 1.067s | 0.526 | 0.500 |
| 1.5 | 1.408s | 0.695 | 0.667 |
| 1.0 | 2.027s | 1.000 | 1.000 |
| 0.5 | 4.075s | 2.011 | 2.000 |

Treat `duration_stretch` as a **speed-rate multiplier**: `actual_duration ≈ baseline_duration / duration_stretch`. The JS SDK docstring claiming it "doubles the duration" at value 2.0 is incorrect for this build — value 2.0 halves it.

Determinism also verified: identical payloads sent twice produce byte-identical PCM output.

---

## 3. The Daemon's Native Markup Dialect — ✅ CONFIRMED

**This is the primary path for affective speech.** The C++ `MarkupHandler` inside `libJiboTTSService.so` parses an XML-like markup dialect embedded in the `prompt` field. Prior testing (now superseded) tested this with lowercase tags sent as raw text with `mode:TEXT` — the MarkupHandler ignored that input. The correct path, revealed by the daemon's own log output captured from the live robot, wraps the prompt in the markup dialect directly.

### Working wire format

```json
POST /tts_speak
Content-Type: application/json

{
  "prompt": "<speak><STYLE set=\"excited\">Hello, I am Jibo.</STYLE></speak>",
  "locale": "en-US",
  "voice": "GRIFFIN",
  "mode": "TEXT"
}
```

**Tag case**: insensitive — uppercase and lowercase both parse identically. `<STYLE>` and `<style>` produce the same result.

**`mode` field**: `TEXT` and `SSML` are both equivalent for all confirmed markup types. `mode` does not gate markup processing.

**`<speak>` wrapper**: strips cleanly with zero byte overhead. Optional, but harmless.

### `libJiboTTSService.so` symbol evidence (FINDING 5)

The full markup engine is compiled into the binary we already run offline:

| Symbol | What it does |
|---|---|
| `jibo::tts::AudioEngine::applyMarkupPitch(Word*)` | Applies pitch markup at the waveform stage |
| `jibo::tts::AudioEngine::applyMarkupDuration(Word*)` | Applies duration markup at the waveform stage |
| `jibo::tts::MarkupHandler::{parseMarkup, identifyMarkup, openMarkup, closeMarkup, applyMarkup, getValidMarkup}` | Complete markup parser |
| `jibo::tts::MarkupHandler::{styleStringToEnum, styleEnumToString, setStyleMarkupPreset, reverseStyleMarkupPreset}` | Full style-enum machinery |
| `jibo::tts::Word::applyPhonePron(...)` | Pronunciation override |

Literal markup tokens present in the binary: `style`, `pitch`, `halftone`, `band`, `add`, `mult`, `duration`, `stretch`, `set`, `break`, `size`, `audio`, `audioBreak`, `phoneme`, `say-as`, `spell`.

---

## 4. Speaking Style — ✅ CONFIRMED (5/6 official styles measurably distinct)

### Official SDK style set (6 styles)

Per the MIT HRI2024 ESML SDK reference (Jibo Inc. archive, October 2023), the
official `SSMLStyleTagType` enum defines exactly **6** supported styles:
`neutral`, `sheepish`, `confused`, `confident`, `enthusiastic`, `news`.

> **`excited` is not an official SDK style.** It is compiled into the
> `libJiboTTSService.so` binary's C++ `SpeakingStyle` enum (7 values total),
> but it does not appear in the SDK-facing `SSMLStyleTagType` enum confirmed
> by the MIT source. Our empirical measurement independently confirms why:
> `excited` produces a ~10 Hz centroid shift, indistinguishable from `neutral`
> within short-FFT noise. It is a binary artifact — present in the C++ layer
> but not part of the supported SDK contract. Use `enthusiastic` instead
> (most distinct: +100 Hz centroid, most consistent across prompt lengths).

All six official styles are compiled into `libJiboTTSService.so`. Invalid
style names trigger: `Style (%s) not a valid style! Setting to neutral.`

### Syntax

```
<STYLE set="enthusiastic">Text to speak.</STYLE>
```

Case-insensitive. `mode` field irrelevant. `<speak>` wrapper optional.

### Empirical results (prompt: "Hello there, I am Jibo and I am speaking to you now.", baseline dur=2.816s centroid=1258Hz)

| Style | Δduration | ΔRMS | Δcentroid | Verdict |
|---|---|---|---|---|
| `neutral` | +0.000s | +4 | +9 Hz | Baseline — no effect vs. plain text, as expected |
| `excited` | +0.000s | +7 | +10 Hz | ⚠️ BINARY ARTIFACT — ~10 Hz; not an official SDK style; indistinguishable from neutral; do not use |
| `confused` | +0.085s | −18 | +85 Hz | ✅ CONFIRMED |
| `sheepish` | +0.107s | +5 | +65 Hz | ✅ CONFIRMED |
| `confident` | +0.064s | −25 | +91 Hz | ✅ CONFIRMED |
| `enthusiastic` | −0.021s | −67 | +100 Hz | ✅ CONFIRMED — most distinct from neutral |
| `news` | +0.085s | +17 | +87 Hz | ✅ CONFIRMED |

Token-times evidence: the `<STYLE>` tag disappears from `/tts_token_times` output entirely (not spoken, parsed into the acoustic model).

**Prior "DISCONFIRMED" result explained**: an earlier SpeakingStyle grid test sent styles via the `pitch`/`pitchBandwidth` JSON fields and via `<excited>...</excited>` lowercase tags in the prompt field. Neither path reaches `MarkupHandler`. The markup dialect path was untested until the experiment documented in `scripts/confirm_markup_dialect.py`.

---

## 5. Pitch Modification — ✅ CONFIRMED (all 4 subtypes, monotonic response)

### Syntax

```
<PITCH halftone="-5">Text</PITCH>
<PITCH band="1.2">Text</PITCH>
<PITCH add="50">Text</PITCH>
<PITCH mult="1.2">Text</PITCH>
```

### Empirical results (baseline centroid = 1262 Hz)

| Tag | Δcentroid | ΔRMS | Verdict |
|---|---|---|---|
| `halftone="-10"` | −103 Hz | +52 | ✅ CONFIRMED — lowers pitch brightness |
| `halftone="-5"` | −40 Hz | +47 | ✅ CONFIRMED — monotonic between −5 and −10 |
| `halftone="+5"` | +48 Hz | +52 | ✅ CONFIRMED — raises pitch brightness |
| `halftone="+10"` | +88 Hz | +323 | ✅ CONFIRMED — also significantly louder |
| `band="0.5"` | −30 Hz | +44 | ✅ CONFIRMED — narrows pitch bandwidth |
| `band="2.0"` | +40 Hz | +180 | ✅ CONFIRMED — widens pitch bandwidth |
| `add="-50"` | −47 Hz | +78 | ✅ CONFIRMED |
| `add="50"` | +44 Hz | +8 | ✅ CONFIRMED |
| `mult="0.8"` | −37 Hz | +77 | ✅ CONFIRMED |
| `mult="1.2"` | +34 Hz | +3 | ✅ CONFIRMED |

All 10 variants show monotonic, directionally-correct acoustic effects. **Prior "DISCONFIRMED" result** was from the `pitch`/`pitchBandwidth` JSON fields — a dead path, not the `<PITCH>` markup tag.

---

## 6. Duration Modification — ✅ CONFIRMED (`<DURATION>` tag; **different semantics from `duration_stretch`**)

### Syntax

```
<DURATION stretch="2.0">Text</DURATION>
<DURATION set="1.0">Text</DURATION>
```

### Empirical results (baseline dur = 2.816s)

| Control | Value | Measured duration | Δduration | Notes |
|---|---|---|---|---|
| JSON `duration_stretch` | 2.0 | 1.557s | −1.259s | Inverse-rate (faster) |
| JSON `duration_stretch` | 0.5 | 5.440s | +2.624s | Inverse-rate (slower) |
| `<DURATION stretch>` | 0.5 | 1.536s | −1.280s | Opposite to JSON: stretch=0.5 → faster |
| `<DURATION stretch>` | 2.0 | 5.440s | +2.624s | stretch=2.0 → slower |
| `<DURATION stretch>` | 3.0 | 8.085s | +5.269s | stretch=3.0 → much slower |
| `<DURATION set>` | 1.0 | 13.077s | +10.261s | Sets absolute seconds **per phoneme** — use carefully |
| `<DURATION set>` | 3.0 | 39.061s | +36.245s | 3s per phoneme — very slow |

**Key finding**: `<DURATION stretch>` and the JSON `duration_stretch` field have **inverted semantics relative to each other**:
- JSON `duration_stretch=2.0` → faster (the field is an inverse-rate multiplier; §2.1)
- `<DURATION stretch="2.0">` → slower (the tag is a direct rate multiplier)

They produce the same *magnitude* of duration change but in opposite *directions*. `<DURATION set=>` sets an absolute phoneme duration in seconds, not a ratio — values above ~1.0 produce impractically slow speech.

---

## 7. Pause / Break — ✅ CONFIRMED (real silence, not literal tag text)

### Syntax

```
<speak>First clause.<BREAK size="0.5"/>Second clause.</speak>
```

### Empirical results (baseline "one two" = 0.683s)

| Break size | Δduration | Verdict |
|---|---|---|
| 0.3s | +0.384s | ✅ Real silence (128% of requested — includes natural boundary) |
| 0.5s | +0.597s | ✅ Real silence (119% of requested) |
| 1.0s | +1.088s | ✅ Real silence (109% of requested) |
| 2.0s | +2.091s | ✅ Real silence (105% of requested) |

Break sizes scale correctly with requested values. The `<break>` token appears in `/tts_token_times` output as a `<break>` entry (not as literal angle-bracket characters), confirming it is parsed as a pause control, not spoken text.

Works for: uppercase/lowercase tags, `mode:TEXT`/`mode:SSML`. Case-insensitive, mode-independent.

**Prior finding explained**: `<break time="500ms"/>` was tested in the `prompt` field as an HTML-style self-closing tag without the `<speak>` wrapper — the MarkupHandler did not recognize that input and spoke it literally. The correct form uses `size=` (not `time=`) measured in seconds.

---

## 8. Phonetic Pronunciation — ✅ CONFIRMED

### Syntax

```
<speak><phoneme ph="b aa n ou">Bono</phoneme></speak>
```

Phoneme notation follows the Combilex phoneme set (documented in §9). Vowel
stress markers: `0`=none, `1`=primary. **Do not use stress marker `2`
(secondary stress) in `<phoneme ph="...">` tags** — the MIT HRI2024 ESML SDK
reference explicitly states secondary stress is not supported at the tag level.
(Stress marker `2` does appear in the `.dictionary` file format for lexicon
entries, where the pipeline handles it — but that is a different code path from
the `<phoneme>` tag's inline pronunciation override.) Use `--no-stress` in
`griffintts` to omit stress digits entirely, which is the confirmed-working
form for all tested empirical examples.

### Empirical result

| Condition | Duration | Δcentroid | Verdict |
|---|---|---|---|
| "Bono" plain | 0.491s | baseline | — |
| `<phoneme ph="b aa n ou">Bono</phoneme>` | 0.512s | +137 Hz | ✅ CONFIRMED — altered spectral shape and timing; mode-independent |

---

## 9. Spelling / Say-As — ✅ CONFIRMED

### Syntax

```
<speak><say-as spell="jibo"/></speak>
```

### Empirical result

| Condition | Duration | Verdict |
|---|---|---|
| "jibo" plain | 0.576s | — |
| `<say-as spell="jibo"/>` | 1.408s (2.44× longer) | ✅ CONFIRMED — each letter spoken individually |

---

## 10. ESML Animation Tags — architecture boundary, NOT a griffintts concern

`<anim cat="...">`, `<ssa cat="...">`, and Jibo's higher-level `<es cat="..."/>` tags coordinate speech with robot animation and sound effects. These are processed by `jibo.embodied.speech.speak()` — a client-side JS API running inside the on-robot `@be/be` Electron process — which builds a "Timeline" coordinating TTS + animation before the daemon ever sees the text.

**This is a permanent architectural boundary for griffintts**: griffintts is an offline Mac CLI/UI tool with no robot present. It structurally cannot host or call into `@be/be`. The daemon never sees animation tags; they are stripped by the JS layer before the HTTP call.

**griffintts scope**: reproduce and control the full **audio channel** of ESML (style, pitch, duration, break, phoneme, say-as). The animation channel is not rendered by these tools; `griffintts-ui` renders an approximation of speaking motion only.

---

## 11. Jibonics / Sound Effects (`<audio>`, `<audioBreak>`) — ❓ UNCONFIRMED (asset-dependent)

The `MarkupHandler` binary contains `<audio>` and `<audioBreak>` token strings, and the daemon logs `TTSMarkup: I somehow got markup of type (%s) but it's unsupported! Pronuncing...` for unrecognized tags. Whether inline audio tags trigger actual sound playback depends on the sound-effect asset banks (`effectsDir`), which are not present in the current emulated container setup.

The `/tts_effects` WebSocket channel (a separate, concurrent effects path) also produced no audio in testing — likely the same missing-assets root cause. Locating and extracting these asset banks from the live robot remains an open task.

---

## 12. Known Daemon Stability Issue

The emulated `jibo-tts-service` daemon crashes with `Poco::SystemException` + SIGABRT after sustained load (~40+ sequential synthesis calls in one session). `griffintts`'s `ensureContainerRunning()` detects and recovers from this automatically. Heavy regression test runs should restart the container between sessions to account for this.

---

## Summary Table

| Mechanism | Status | Notes |
|---|---|---|
| Automatic prosody from G2P/HTS context | ✅ Confirmed (structural) | No parameters needed; inherent to acoustic model |
| `duration_stretch` JSON field | ✅ Confirmed, inverted semantics | Use as `baseline / value` (speed-rate multiplier) |
| `pitch`, `pitchBandwidth`, `volume`, `whisper` JSON fields | ❌ Disconfirmed | No measurable effect; dead paths in this build |
| `<STYLE set="...">` markup | ✅ Confirmed (5/6 official styles measurably distinct) | `confused`, `sheepish`, `confident`, `enthusiastic`, `news` confirmed; `excited` is a binary artifact (not an official SDK style), indistinguishable from neutral; see §4 |
| `<PITCH halftone/band/add/mult>` markup | ✅ Confirmed (all 4 subtypes) | Monotonic, directionally correct response; see §5 |
| `<DURATION stretch/set>` markup | ✅ Confirmed | **Opposite direction** to `duration_stretch` JSON field; `set=` is per-phoneme seconds; see §6 |
| `<BREAK size="...">` markup | ✅ Confirmed — real silence | Scales with requested value; NOT spoken literally; see §7 |
| `<phoneme ph="...">` markup | ✅ Confirmed | Alters pronunciation and spectral shape; see §8 |
| `<say-as spell="...">` markup | ✅ Confirmed | Letters spelled individually (2.4× longer); see §9 |
| Animation tags (`<anim>`, `<ssa>`, `<es>`) | Architecture boundary | Processed by on-robot `@be/be`; permanent boundary for griffintts; see §10 |
| Jibonics / `<audio>` / `<audioBreak>` | ❓ Unconfirmed | Sound-bank assets not present in container; see §11 |
| Daemon stability | Known issue | Crashes after ~40 requests/session; auto-recovered by `ensureContainerRunning()` |

**Net result (corrected)**: the full affective audio engine — styles, pitch, duration, pause, pronunciation — is live in `libJiboTTSService.so` and reachable via the daemon's native markup dialect. The prior "no inline markup produces any effect" conclusion tested the wrong invocation path and is superseded by the empirical results in `scripts/confirm_markup_dialect.py`.

---

## Academic Foundations & References

### 1. Nagoya HTS (HMM-based Speech Synthesis System) Engine
- **Role**: Griffin's acoustic engine maps 113-dimension contextual features to predict duration, F0, and cepstral parameters.
- **Documentation**: [HTS Engine API Project Page](http://hts-engine.sourceforge.net/)
- **Key Paper**: Tokuda, K., et al. (2013). *Speech Synthesis Based on Hidden Markov Models.* Proceedings of the IEEE, 101(5).

### 2. The WORLD Vocoder
- **Role**: Reconstructs Jibo's `en_us_world.voice` model via F0, spectral envelope (MCP), and multi-band aperiodicity (BAP).
- **Documentation**: [WORLD Vocoder GitHub](https://github.com/mmorise/World)
- **Key Paper**: Morise, M., et al. (2016). *WORLD: A Vocoder-Based High-Quality Speech Synthesis System.* IEICE Transactions on Information and Systems.

### 3. OpenFST (Finite State Transducers)
- **Role**: Text normalization frontend (numbers, dates, abbreviations → expanded strings).
- **Documentation**: [OpenFST Library](http://www.openfst.org/)
- **Key Paper**: Allauzen, C., et al. (2007). *OpenFst: A General and Efficient Weighted Finite-State Transducer Library.* CIAA.

### 5. MIT HRI2024 ESML SDK Reference (Jibo Inc. Archive)

- **Role**: Official ESML SDK documentation, independently validated. Produced from `localhost:8000/docs/embodied-speech.html` (Jibo Inc. internal docs server), captured 2023-10-12 by the MIT Media Lab's Personal Robotics Group for the HRI2024 Jibo workshop.
- **URL**: `https://hri2024.jibo.media.mit.edu/` (Speak-Tweak docs, ESML reference)
- **Key confirmations for this document**: Official style set = 6 (`neutral`, `sheepish`, `confused`, `confident`, `enthusiastic`, `news`); `excited` absent from the SDK enum; stress marker `2` not supported in `<phoneme>` tags; `<phoneme>` confirmed working on live networked Jibo units by an independent team.

### 4. Edinburgh Combilex Lexicon & G2P
- **Role**: Jibo's dictionary and letter-to-sound mappings.
- **Documentation**: [CSTR Combilex Project Page](https://www.cstr.ed.ac.uk/research/projects/combilex/)
- **Key Paper**: Richmond, K., et al. (2009). *Robust Pronunciation Lexicon Database (Combilex).* Interspeech.

---

## Open Questions

1. **`<audio>`/`<audioBreak>` inline sound effects**: the markup parser tokens exist in the binary; actual playback depends on asset banks not yet extracted from the robot. (The question of where ESML animation tags are processed is now resolved — see §10.)

2. **`excited` style — resolved**: Δcentroid ~10 Hz, within short-FFT noise, and confirmed NOT an official SDK style per the MIT HRI2024 ESML reference (Jibo Inc. archive). The binary includes it as a C++ `SpeakingStyle` enum value but it is absent from the SDK-facing `SSMLStyleTagType` enum. Do not use it; use `enthusiastic` instead.

3. **`PostFilterMap` DSP switches**: if not pre-recorded clips, are they real-time filters applied only when a skill calls a body-service/expression API in parallel with speech, rather than through `jibo-tts-service` at all?

4. **Daemon stability root cause**: the `Poco::SystemException` crash under sustained load may be a resource leak in the emulated environment. Whether it occurs on-robot under equivalent load is unknown.
