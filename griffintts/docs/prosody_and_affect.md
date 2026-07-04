# Jibo Griffin TTS: Prosody, ESML Markup & Vocal Affect

This document explains the advanced linguistic, phonetic, and digital signal processing (DSP) parameters that govern Jibo's expressive vocal personality ("Griffin"), and serves as a handbook for speech designers looking to leverage these controls.

---

## The Four Levels of Expressive Control

Griffin TTS achieves Jibo's lifelike, charming character by layering control parameters across four distinct levels:

```text
  Linguistic Text   ==>   Linguistic Frontend   ==>   Acoustic Model   ==>   DSP Vocoder
 (Raw Text / ESML)       (OpenFST / Dictionary)       (HMM Preds / F0)       (Effects / LPF)
```

1.  **Linguistic Level (ESML)**: The input string is marked up with Embedded Speech Markup Language (ESML) tags specifying style, emphasis, or pauses.
2.  **Linguistic Frontend (Phoneme & Context Extraction)**: Words are translated into phone lists with stress numbers, and 113-dimension HTS context labels are generated representing syllable position, accents, and phrase-terminal boundaries.
3.  **Acoustic Model (HMM State Prediction)**: Jibo's HMM decision trees inside `.voice` match these context features to predict natural, context-aware durations, spectral parameters, and pitch (F0) contours.
4.  **DSP Vocoder Level (Post-Filtering & Effects)**: The synthesized waveforms are passed through real-time DSP phaser, flanger, or post-filtering resonators inside `libJiboTTSService.so` to inject Jibo's metallic robotic chirps or Jibonic chimes.

---

## 1. ESML (Embedded Speech Markup Language) Tag Reference

A speech designer can embed these XML-style tags directly within the text string passed to the emulated container mode:

### Emotional / Style Overrides
These tags wrap phrases to apply global vocal changes (shifting pitch, accelerating speed, or altering spectral variance):
*   `<excited>Text</excited>`: Raises average pitch, increases pitch variance (expressive range), and accelerates speaking rate.
*   `<worried>Text</worried>`: Increases pitch instability and adjusts post-filtering coefficients for a tighter, anxious resonance.
*   `<affectionate>Text</affectionate>`: Lowers average pitch, stretches vowel durations, and reduces spectral variance for a warm, soft tone.
*   `<sorrow>Text</sorrow>`: Decreases speaking speed, flattens pitch variance (monotonic), and dampens post-filter gain for a flat, somber tone.
*   `<whisper>Text</whisper>`: Blends 100% unvoiced noise into the excitation, bypassing the pitch (F0) contour entirely to create whisper-speech.

### Linguistic & Structural Overrides
*   `<emphasis>Word</emphasis>`: Tells the linguistic normalizer to mark this syllable as accented. The acoustic HMM automatically predicts a higher pitch (F0), longer vowel duration, and higher spectral energy on this word.
*   `<parenthesis>Text</parenthesis>`: Lowers the pitch and speaking volume, mimicking a brief aside or under-the-breath remark.
*   `<spau />` / `[spau]`: Inserts an explicit Short Pause (approx. 100ms silence).
*   `<lpau />` / `[lpau]`: Inserts an explicit Long Pause (approx. 350ms silence).

---

## 2. Jibonics & Sound Effects ("Pedals")

Jibo's unique character relies heavily on "Jibonics"—cute, non-speech robotic sound effects (chirps, giggles, whirs, hums) that are interspersed during speech. These are called **Pedals** inside Jibo's C++ framework, and they play raw sound files from Jibo's `effectsDir` (`/usr/local/share/ttsservice/effects/`) modulated by a volume parameter:

Below are Jibo's primary, compiled-in sound effect identifiers (mapped from Jibo's `jibo-tts-service.json` configuration):

| Effect Identifier | Description / Acoustic Character |
|---|---|
| `laughter` / `laugh2` | Adorable, high-pitch synthetic giggling. |
| `woo_hoo_hoo` | Jibo's signature high-pitch excited chime. |
| `cool` | A quick, upward-sliding electronic chirp. |
| `done` | A soft double-ping indicating a completed action. |
| `whoa` | A sweeping, downward resonant frequency slide. |
| `argh` / `oops` / `my_bad` | Whimsical, slightly metallic disappointed tones. |
| `perfect` / `ok` | Affirmative pings and electronic chirps. |
| `um` / `huh` | Vocalized, soft robotic fillers. |

### How to use Jibonics in speech:
You can embed these effects inside your speech string using Jibo's custom `<item>` tag:
```text
"That is <item name=\"perfect\" />! I am <item name=\"woo_hoo_hoo\" /> so happy!"
```

---

## 3. Global Synthesis Parametric Controls

In addition to inline markup, a speech designer can apply global, structural overrides that govern the entire utterance. These parameters are passed as flags to Jibo's CLI or configured inside `voiceParams`:

1.  **`pitch` (Scale [0.2 - 0.8])**: Controls Jibo's overall vocal pitch register. Recommended: `0.42` for standard Griffin. Higher values make Jibo sound younger/smaller, while lower values make him sound older/larger.
2.  **`pitchBandwidth` (Scale [0.0 - 2.0])**: Modulates Jibo's intonation range.
    -   `0.0`: Completely monotonic and robotic.
    -   `1.0`: Standard Jibo expressiveness.
    -   `2.0`: Maximum emotional variation.
3.  **`duration_stretch` (Scale [0.5 - 2.0])**: Modulates speaking speed. `1.0` is standard. `0.5` is double-speed (fast), while `2.0` is half-speed (slow).

---

## Workflow Gap & The SwiftUI "Speech Designer Playground"

Currently, writing raw XML-style ESML markup inside terminal strings is un-ergonomic and represents a **documentation/usability gap** for human speech designers.

### The Solution: A SwiftUI "Speech Playground" Editor
Rather than editing strings manually, we can easily build a **Speech Designer Playground** right inside our **`griffintts-ui`** application:

1.  **Expressive Presets Sidebar**: Add a sidebar containing Jibo's emotional states (Excited, Sorrow, Worried, Affectionate). Highlighting text and clicking "Excited" automatically wraps the string in `<excited>...</excited>`.
2.  **Parametric Sliders**: Provide native macOS sliders for `Pitch`, `Speed`, and `Intonation Range (Bandwidth)`. These bind directly to the Go CLI's `--pitch` and `--speed` command-line flags.
3.  **Jibonics Soundboard**: Add an "Insert Effect" dropdown menu. Selecting `"woo_hoo_hoo"` inserts Jibo's custom `<item name="woo_hoo_hoo" />` tag at the cursor's current insertion point, letting designers composite speech and sound effects effortlessly!
