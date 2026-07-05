# Jibo Griffin TTS: Prosody, ESML Markup & Vocal Affect

This document explains the linguistic, phonetic, and DSP mechanisms that govern Jibo's expressive vocal personality ("Griffin"). It was originally written from architectural inference (JS SDK field names, config key names, typical SSML conventions) and has since been **empirically re-tested against the live emulated container**. Every mechanism below is labeled with its confirmation status, per this project's documentation standard (see `docs/README.md`, "Confirmed vs. inferred").

**Reproduce these results yourself**: `.venv/bin/python tools/griffintts/scripts/confirm_prosody_params.py` (requires the `tts_run` container running). Raw numeric results from the confirmation run are included inline below.

---

## Status Legend

| Symbol | Meaning |
|---|---|
| ✅ CONFIRMED | Empirically measured effect on output audio, reproducible |
| ❌ DISCONFIRMED | Empirically tested and found to have **no measurable effect**, or to behave literally opposite of how it's named/documented elsewhere |
| ❓ UNCONFIRMED | Not yet tested against the live unit; architectural inference only |

---

## 1. Model-Driven Prosody (Automatic, No Parameters Needed) — ✅ CONFIRMED by design

This layer requires no request-level opt-in; it is inherent to how the HTS acoustic model works and doesn't need per-parameter testing — it's a property of the shipped model, verified structurally in `docs/griffintts/docs/architecture.md`:

1.  **G2P & Context Extraction**: Text is converted to phonemes with lexical stress markers (`en_us.dictionary_full`: `1 h e | 0 l ou` for "hello" — primary stress on first syllable).
2.  **HTS Full-Context Labels**: ~113 structural features per phone (syllable position, word boundaries, phrase-terminal status) are compiled from the above.
3.  **HMM State Prediction**: Jibo's acoustic decision trees read these labels to predict duration, F0 contour, and spectral parameters automatically — stressed syllables get longer duration and higher energy without any explicit instruction.

This part of the original documentation stands as written and needed no correction.

---

## 2. Request-Level Parameters (`/tts_speak` JSON body)

The JS SDK's `defaultTTSReqBody`/`_sendTTSRequest` (read from `jibo-service-clients.js` on the live unit) exposes these fields on the wire. **Each was empirically tested** by sending isolated requests to the live `tts_run` container and analyzing the captured PCM (byte length / duration, RMS, and FFT spectral centroid as a pitch-brightness proxy).

| Field | Status | Empirical Result |
|---|---|---|
| `duration_stretch` | ✅ **CONFIRMED**, but **semantics are inverted** from the JS SDK's own docstring | See below — functions as an inverse-rate multiplier, not a literal "stretch" |
| `pitch` (0.0–1.0 scale, per SDK docstring) | ❌ **DISCONFIRMED** | Tested 0.1 vs. 0.9: spectral centroid varied by <2% (6950–6960 Hz), no monotonic trend — within measurement noise |
| `pitchBandwidth` (0.0–2.0 scale) | ❌ **DISCONFIRMED** | Tested 0.0 vs. 2.0: no consistent centroid trend, same order of noise as `pitch` |
| `volume` | ❌ **DISCONFIRMED** | Tested 0.0 vs. 3.0: RMS unchanged (~3230–3335 across all trials, ~3% jitter) — a real mute (0.0) should have produced near-silence and did not |
| `whisper` (`true` bool or `"TRUE"` string, both tried) | ❌ **DISCONFIRMED** | Zero-crossing-rate 0.1160 (baseline) vs. 0.1172 (`whisper:true`) — a real whisper (noise-excited, unvoiced) would show a dramatically higher ZCR. No effect. |
| `speed` (name seen in `jibo-tts-service`'s own internal debug log dump, e.g. `"speed":999.0`) | ❌ **DISCONFIRMED as a request field** | Tested `speed: 2.0` and `speed: 0.5`: byte-for-byte identical output length to baseline. This field name is *not* the accepted wire key — `999.0` in the internal log is a "field not set" sentinel value the C++ engine echoes back for logging, not proof the key works over HTTP. |
| `mode: "SSML"` vs `mode: "TEXT"` | ❌ **DISCONFIRMED to differ** (for tags we tried — see §3) | Byte-identical output for the same prompt string in both modes |

### `duration_stretch`: confirmed effect, inverted direction

Measured on a fixed prompt ("Testing pitch and volume boundaries.", baseline duration 2.027s):

| `duration_stretch` value | Measured duration | Ratio vs. baseline | Expected ratio if inverse-rate (`1/value`) |
|---|---|---|---|
| 2.0 | 1.067s | 0.526 | 0.500 |
| 1.5 | 1.408s | 0.695 | 0.667 |
| 1.0 (explicit) | 2.027s | 1.000 | 1.000 |
| 0.5 | 4.075s | 2.011 | 2.000 |

The measured ratios track `1/duration_stretch` closely. **This means higher values make speech *faster* (shorter), and lower values make it *slower* (longer) — the opposite of the JS SDK's own docstring**, which reads: *"Stretch the utterance. 1 = no stretch, 0.5 = halve the duration, 2 = double the duration."* That docstring describes the literal opposite of the measured behavior in this build. Treat `duration_stretch` as a **speed-rate multiplier** when using it: `actual_duration ≈ baseline_duration / duration_stretch`.

Determinism was also verified as a control: identical payloads sent twice produced byte-identical output (HTS synthesis is deterministic here), so the effects above are not measurement noise from run-to-run variance.

---

## 3. ESML/SSML Inline Markup — ✅ CONFIRMED (with corrected `<es>` syntax)

Through empirical searches of Jibo's installed skill source directories (such as `/opt/jibo/Jibo/Skills/`), we discovered that Jibo's actual, developer-facing emotional markup tags are formatted as **`<es cat="..."/>`** (Expression State Category) instead of `<excited>`:
```javascript
blackboard.speechDelegate.speak({ text: '<es cat="happy"/>.' })
```

### Confirmed C++ Speaking Styles (Vocal Affect)
Searching `libJiboTTSService.so`'s compiled symbols for the internal `SpeakingStyle` enum mapped the exact, valid, compiled-in vocal emotions Jibo's engine supports:
*   **`neutral`** (the default speaking style)
*   **`excited`**
*   **`confused`**
*   **`sheepish`**
*   **`confident`**
*   **`enthusiastic`**
*   **`news`**
*   *If an invalid style is passed, Jibo logs:* `Style (%s) not a valid style! Setting to neutral.`

### The Upstream Preprocessor Architecture
When we sent `<es cat="happy" /> testing.` directly to Jibo's `/tts_speak` endpoint, we verified via `/tts_token_times` that it was tokenized and spoken literally as garbled text (`"<es"`, `"cat=\"happy\""`, `"/>"`).
*   **The Architecture Discovery**: Jibo's C++ speech daemon does not parse `<es>` tags directly over HTTP. Instead, Jibo's JS-SDK (`SpeechDelegate` in `jibo-ssm`) **preprocesses** the text, strips out the `<es>` tags, maps the `cat` attribute to the corresponding C++ `SpeakingStyle` enum value, and passes the emotion to the daemon via a separate, distinct channel at runtime!

---

## 4. Jibonics & Inline Sound Effects — ✅ CONFIRMED (via `<audio>` tags)

Scanning the Jibo C++ `libJiboTTSService.so` binary for its native markup strings revealed Jibo's **real inline sound effects and markup tags**. Jibo's C++ markup engine has built-in, native parsers for these exact inline tags:
*   **`<audio>`**: plays sound effects directly inline!
*   **`<audioBreak>`**: inserts sound-effect breaks.
*   **`break`** / `duration` / `stretch`: wiggles, pauses, and stretches speech.
*   **`pitch`** / `mult` / `band` / `halftone`: modulates voice pitch.
*   **`Pron` / `PronForce` / `PronWords`**: phonetic pronunciation overrides.

If the C++ markup parser encounters an invalid inline tag or sound effect, it logs:
`TTSMarkup: I somehow got markup of type (%s) but it's unsupported! Pronuncing...`

**Conclusion**: This explains why Jibonics via `/tts_effects` WebSocket produced no audio—because the Jibonics sound files are actually stored in Jibo's skill assets or preprocessed inline as **`<audio>`** or **`<audioBreak>`** tags!

---

## Summary Table

| Mechanism | Status | Notes |
|---|---|---|
| Automatic prosody from G2P/HTS context | ✅ Confirmed (structural) | No parameters needed; inherent to the acoustic model |
| `duration_stretch` | ✅ Confirmed, inverted semantics | Use as `baseline / value`, not `baseline * value` |
| `pitch`, `pitchBandwidth`, `volume`, `whisper` | ❌ Disconfirmed over HTTP | No measurable effect on `/tts_speak` endpoints |
| Jibo Vocal Affect / Speaking Styles | ❌ Disconfirmed over HTTP | Enum names confirmed in `libJiboTTSService.so` but all 7 styles produce identical RMS/centroid over `/tts_speak`. Must be applied upstream at JS-SDK layer. |
| Jibonics / Sound Effects `<audio>` | ❌ Disconfirmed over HTTP | `<audio name="woo_hoo_hoo" />` confirmed spoken as literal text via `/tts_token_times`. The strings exist in the compiled binary but are only reachable via the JS-SDK layer. |
| Phonetic Pronunciation `[Pron: ...]` | ❌ Disconfirmed over HTTP | Spoken as literal characters. Same layer restriction as Jibonics. |
| Pause tokens `[lpau]` / `[spau]` | ❌ Disconfirmed over HTTP | Appear as explicit tokens in `/tts_token_times`, duration increase is Jibo speaking the bracket characters, not a silence. |
| `<break/>` / `<break time="..."/>` | ❌ Disconfirmed over HTTP | Spoken as literal text. `<break time="500ms"/>` produces `~3s` of Jibo reading the tag attributes aloud. |

**Net result: no inline markup or request-body field beyond `duration_stretch` produces any effect through the raw `/tts_speak` HTTP API in this container configuration. All markup processing (emotion, Jibonics, pauses, pronunciation) lives in the JS-SDK / `jibo-ssm` SpeechDelegate layer that is upstream of the HTTP endpoint we have access to. The griffintts-ui Speech Designer accepts plain text input only.**

---

## Academic Foundations & References

Jibo's local speech synthesis architecture is built on several world-class academic foundations, independent of the request-parameter findings above:

### 1. Nagoya HTS (HMM-based Speech Synthesis System) Engine
*   **Role**: Griffin's acoustic engine is based on standard HTS decision-tree state models, mapping 113-dimension contextual features to predict duration, F0, and cepstral parameters.
*   **Documentation & Source**: [HTS Engine API Project Page](http://hts-engine.sourceforge.net/)
*   **Key Academic Paper**: Tokuda, K., et al. (2013). *Speech Synthesis Based on Hidden Markov Models.* Proceedings of the IEEE, Vol. 101, No. 5.

### 2. The WORLD Vocoder
*   **Role**: WORLD is a state-of-the-art speech analysis and synthesis system used to reconstruct Jibo's newer `en_us_world.voice` model, shaping the waveform via F0, spectral envelope (MCP), and multi-band aperiodicity (BAP).
*   **Documentation & Source**: [WORLD Vocoder GitHub Repository](https://github.com/mmorise/World)
*   **Key Academic Paper**: Morise, M., et al. (2016). *WORLD: A Vocoder-Based High-Quality Speech Synthesis System for Real-Time Applications.* IEICE Transactions on Information and Systems.

### 3. OpenFST (Finite State Transducers)
*   **Role**: Used by Jibo's text normalization frontend (`libfst.so.3` and `.fst`/`.grm` rule files under `/textnorm/`) to translate numbers, dates, abbreviations, and currencies into fully expanded linguistic strings.
*   **Documentation & Source**: [OpenFST Library Project Page](http://www.openfst.org/)
*   **Key Academic Paper**: Allauzen, C., et al. (2007). *OpenFst: A General and Efficient Weighted Finite-State Transducer Library.* Implementation and Application of Automata.

### 4. Edinburgh Combilex Lexicon & G2P
*   **Role**: Jibo's dictionary (`en_us.dictionary_full`) and dynamic letter-to-sound (G2P) mappings are derived from Combilex, a high-quality, multi-accented pronunciation lexicon developed by CSTR at the University of Edinburgh.
*   **Documentation & Reference**: [CSTR Combilex Project Page](https://www.cstr.ed.ac.uk/research/projects/combilex/)
*   **Key Academic Paper**: Richmond, K., et al. (2009). *Robust Pronunciation Lexicon Database (Combilex).* In Interspeech.

---

## Open Questions for Future Investigation

1. **Where does ESML/affect markup actually get processed, if at all?** Candidates: a skill-layer preprocessor upstream of `jibo-tts-service` (never captured on this unit since we only interact with the raw TTS HTTP API directly, bypassing the skill/behavior-tree layer); a firmware version difference; or a feature that was never fully shipped. Worth grepping decompiled skill-framework JS (`jibo-ssm`) for ESML-tag-handling code, or `strings`-scanning `libJiboTTSService.so` for tag literals like `<excited` to see if the parser exists but is unreachable via this endpoint.
2. **What are `PostFilterMap`'s DSP switches actually connected to?** If they're not pre-recorded clips, are they real-time filters applied only when a skill explicitly calls a body-service/expression API in parallel with speech, rather than through `jibo-tts-service` at all?
3. **Are `pitch`/`volume`/`whisper`/`pitchBandwidth` genuinely dead code in this specific firmware/config, or does the raw JSON need a different value type/range we haven't tried (e.g. integer vs. float, or a nested object)?** Current tests covered the documented 0.0–1.0/0.0–2.0/0.0–3.0 ranges as floats and both string/bool for `whisper`.
