# Jibo Griffin TTS: Canonical Reference Corpus

This directory contains our canonical, versioned reference text corpus and baseline audio "fingerprints" used for regression testing Jibo's local speech synthesis pipeline.

---

## The Reference Corpus Sentence

The primary reference sentence is stored in `reference_corpus.txt`:
```text
Hi! [lpau] On 03/21/1987, I had $1.50 in my pocket. [spau] Today is the 124th test, and it is fully operational on macOS!
```

This single, compact sentence is engineered to exercise **100% of Griffin's confirmed speech capabilities** in one pass:

### 1. Dictionary Lookup & Punctuation Stripping
*   **Target tokens**: `Hi!`, `I`, `had`, `in`, `my`, `pocket.`, `Today`, `is`, `test,`, `and`, `it`, `is`, `fully`, `operational`, `on`
*   **Mechanism**: Verifies that standard words are successfully located inside `en_us.dictionary_full`, and that trailing punctuation like `!`, `,`, or `.` is cleanly stripped out before dictionary queries to prevent lookups from failing.

### 2. Explicit Pause Tokens
*   **Target tokens**: `[lpau]`, `[spau]`
*   **Mechanism**: Verifies that Jibo's explicit Long Pause (`[lpau]`) and Short Pause (`[spau]`) are parsed as literal, silence-generating tokens rather than spoken aloud.

### 3. OpenFST Text Normalization
*   **Target tokens**: `03/21/1987`, `$1.50`, `124th`
*   **Mechanism**: Exercises the container's native OpenFST rules under `/textnorm/` to expand complex formatted text:
    -   `03/21/1987` $\rightarrow$ *"march twenty first nineteen eighty seven"*
    -   `$1.50` $\rightarrow$ *"one dollar fifty cents"*
    -   `124th` $\rightarrow$ *"one hundred twenty fourth"*

### 4. Dynamic Letter-Spelling Fallback
*   **Target tokens**: `macOS!`
*   **Mechanism**: Since `macOS` is absent from Jibo's 128,761-word dictionary, it triggers our custom Go G2P letter-spelling fallback, spelling it out as `m-a-c-o-s` using Jibo's native `mletter`, `aletter`, `cletter`, `oletter`, `sletter` dictionary entries.

### 5. Parametric Rate Scaling
*   **Mechanism**: The verification script runs this corpus at `1.0x`, `1.5x` (fast), and `0.7x` (slow) speeds to confirm that the container's `duration_stretch` parameter scales the output WAV sizes with the exact predicted ratio.

---

## Golden Fingerprints Reference

The script `confirm_prosody_params.py` (or automated tests) generates and compares live runs against a "golden" reference baseline in `golden_fingerprints.json` storing:
-   **File Size (Bytes)**: Confirming no data truncation or empty silence outputs.
-   **Exact Speech Duration (s)**: Verifying the ALSA-file-redirection offset seeking is working seamlessly.
-   **RMS Amplitude**: Verifying vocal levels and audibility.
-   **Spectral Centroid Pitch (Hz)**: Serving as a robust frequency-brightness proxy to ensure voice fidelity.
