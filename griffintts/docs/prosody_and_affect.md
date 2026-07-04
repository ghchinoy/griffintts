# Jibo Griffin TTS: Prosody, ESML Markup & Vocal Affect

This document explains the linguistic, phonetic, and DSP mechanisms that govern Jibo's expressive vocal personality ("Griffin"). It was originally written from architectural inference (JS SDK field names, config key names, typical SSML conventions) and has since been **empirically re-tested against the live emulated container**. Every mechanism below is labeled with its confirmation status, per this project's documentation standard (see `docs/documentation-plan.md`, "Confirmed vs. inferred").

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

## 3. ESML/SSML Inline Markup — ❌ DISCONFIRMED (as previously documented)

The original version of this document proposed tags like `<excited>Text</excited>` and `<item name="woo_hoo_hoo" />` based on typical SSML conventions and the `PostFilterMap` config's switch names. **This was inference, not fact, and it does not survive contact with the live unit.**

Sending `<excited>Excited test.</excited>` in either `mode: "TEXT"` or `mode: "SSML"` produces **the literal tag text spoken aloud**, confirmed via `/tts_token_times`:
```json
{"tokens": [
  {"name": "<excited>Excited", "start": 0, "end": 1.235},
  {"name": "test.", "start": 1.235, "end": 1.96},
  {"name": "</excited>", "start": 1.96, "end": 2.8},
  {"name": "[lpau]", "start": 2.8, "end": 2.85}
]}
```
Jibo tokenizes `<excited>Excited` and `</excited>` as garbled literal text tokens — there is no markup parser active at this endpoint in this configuration. The same is true for the guessed `<item name="woo_hoo_hoo" />` tag.

**Conclusion**: whatever emotional/affect authoring mechanism Jibo's original skill system used (if any — see open questions below), it is **not** exposed as inline text markup on `jibo-tts-service`'s `/tts_speak` HTTP endpoint as configured in this container. It may live at a different layer (e.g. a skill/behavior-tree preprocessor that converts author-facing markup into `PostFilterMap` API calls before ever reaching this service), or may not exist as an author-facing feature at all on this firmware version.

---

## 4. Jibonics / "Pedals" Sound Effects — ❌ DISCONFIRMED (mechanism unconfirmed, assets missing)

Original hypothesis: real-time DSP effects or pre-recorded clips (`woo_hoo_hoo`, `laughter`, `oops`, etc.) triggered via a `startEffect`/`stopEffect` WebSocket call to `/tts_effects`, based on `jibo-tts-service.json`'s `PostFilterMap` switch names (`excitedSwitch`, `phaserSwitch`, `ringmodSwitch`, etc. — these config keys **are** confirmed to exist in the live config file) and the JS SDK's `startEffect(name, value)` function signature.

**Empirical test**: Opened a WebSocket to `ws://localhost:8089/tts_effects`, sent `{"name": "woo_hoo_hoo", "action": "START", "param": "1"}`. The connection opened without error, but:
- **Zero bytes** were written to the shared ALSA output stream during a 2-second observation window.
- A live filesystem search on the actual Jibo unit found **no `effectsDir` directory at all** — `/usr/local/share/ttsservice/effects/` (the path configured in `jibo-tts-service.json`) does not exist on disk.
- A repo-wide and unit-wide search for effect-named audio assets (`woo_hoo_hoo`, `jibonic`, etc.) found no matches anywhere on the live filesystem.

**Conclusion**: The `PostFilterMap` switch names are confirmed to exist in configuration, but we have **no confirmed, reproducible way to trigger audible output through them** on this unit, and the assumption that Jibonics are pre-recorded sound clips is likely wrong — the switch names (`phaserSwitch`, `ringmodSwitch`, `flangerSwitch`, `chorusSwitch`, `autotuneSwitch`) read more like **real-time DSP effect toggles applied to the live vocoder output** (procedurally generated, like a robot-voice effects rack) than sample playback IDs. This needs further investigation before any UI is built around it — see the rescoped tasks below.

---

## Summary Table

| Mechanism | Status | Notes |
|---|---|---|
| Automatic prosody from G2P/HTS context | ✅ Confirmed (structural) | No parameters needed; inherent to the acoustic model |
| `duration_stretch` | ✅ Confirmed, inverted semantics | Use as `baseline / value`, not `baseline * value` |
| `pitch` | ❌ Disconfirmed | No measurable effect |
| `pitchBandwidth` | ❌ Disconfirmed | No measurable effect |
| `volume` | ❌ Disconfirmed | No measurable effect |
| `whisper` | ❌ Disconfirmed | No measurable effect |
| `speed` (alt field name) | ❌ Disconfirmed | Wrong wire key; use `duration_stretch` |
| `mode: SSML` | ❌ Disconfirmed to differ | Byte-identical to `TEXT` mode for tags tried |
| Inline ESML tags (`<excited>`, etc.) | ❌ Disconfirmed | Spoken literally as garbled text |
| Jibonics via `/tts_effects` WebSocket | ❌ Disconfirmed | Connects, but produces no audio; asset directory doesn't exist on unit |

**Net result: the only confirmed, functioning "lever of control" beyond plain text is `duration_stretch`.** This substantially changes the scope of what a "Speech Designer Playground" UI can responsibly expose today — see the rescoped `jibo-6yu` epic.

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
