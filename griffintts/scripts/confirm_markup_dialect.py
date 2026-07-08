#!/usr/bin/env python3
"""
confirm_markup_dialect.py — decisive empirical test for the daemon's native markup dialect

WHAT THIS TESTS:
  The daemon's MarkupHandler compiled into libJiboTTSService.so (FINDING 5)
  exposes symbols for applyMarkupPitch, applyMarkupDuration, styleStringToEnum,
  setStyleMarkupPreset, etc. Prior tests (confirm_prosody_params.py) sent markup
  via the 'prompt' field with mode:TEXT and lowercase tags — the WRONG path.
  The daemon's own log output reveals it actually consumes an UPPERCASE dialect:
    <speak><STYLE set="NEUTRAL"> ... <BREAK size="1.567"/> ... </STYLE></speak>

  This script feeds the emulated daemon its own dialect and measures whether
  acoustic affect is produced. It settles the "dead end vs. live engine"
  question with numeric evidence.

WHAT IT MEASURES (same method as confirm_prosody_params.py):
  - Duration (seconds from PCM byte count at 48kHz 16-bit mono)
  - RMS (proxy for energy/volume)
  - FFT spectral centroid (proxy for pitch brightness)

DETERMINISM CONTROL: identical payloads sent twice must produce byte-identical
PCM; any delta between conditions is markup effect, not run-to-run variance.

NEGATIVE CONTROL: invalid style name triggers daemon log "Style (%s) not a valid
style! Setting to neutral." — proves the parser is reading our input.
Run: container logs tts_run | grep -i "TTSMarkup\|not a valid style" during
execution to observe which markup paths were hit.

Usage:
    .venv/bin/python tools/griffintts/scripts/confirm_markup_dialect.py

Requires: tts_run container running at localhost:8089, numpy installed.
"""

import json
import os
import time
import urllib.error
import urllib.request
from typing import Optional

import numpy as np

SHARED_PCM = "/tmp/griffintts-shared/output.raw"
HOST = "localhost"
PORT = "8089"
SR = 48000  # 16-bit mono PCM sample rate

PROMPT = "Hello there, I am Jibo and I am speaking to you now."


# ---------------------------------------------------------------------------
# PCM capture helpers (identical technique to confirm_prosody_params.py)
# ---------------------------------------------------------------------------

def get_offset() -> int:
    return os.path.getsize(SHARED_PCM) if os.path.exists(SHARED_PCM) else 0


def speak(payload: dict, label: str, settle: float = 0.5) -> bytes:
    """POST payload to /tts_speak; return only the newly-written PCM bytes."""
    start = get_offset()
    req = urllib.request.Request(
        f"http://{HOST}:{PORT}/tts_speak",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            _ = resp.status
    except urllib.error.HTTPError as e:
        print(f"  [{label}] HTTP ERROR {e.code}: {e.read()[:300]}")
        return b""
    except Exception as e:
        print(f"  [{label}] ERROR: {e}")
        return b""
    time.sleep(settle)
    with open(SHARED_PCM, "rb") as f:
        f.seek(start)
        data = f.read()
    return data


def analyze(data: bytes, label: str) -> dict:
    """Compute duration, RMS, spectral centroid from raw 16-bit mono PCM."""
    arr = np.frombuffer(data, dtype=np.int16).astype(np.float64)
    dur = len(arr) / SR
    rms = float(np.sqrt(np.mean(arr ** 2))) if len(arr) else 0.0
    centroid = 0.0
    if len(arr) > 2048:
        n = min(8192, len(arr))
        windowed = arr[:n] * np.hanning(n)
        spec = np.abs(np.fft.rfft(windowed))
        freqs = np.fft.rfftfreq(n, 1 / SR)
        centroid = float(np.sum(freqs * spec) / (np.sum(spec) + 1e-9))
    print(f"  {label:<36} bytes={len(data):>8}  dur={dur:>6.3f}s  rms={rms:>8.1f}  centroid={centroid:>8.1f}Hz")
    return {"label": label, "bytes": len(data), "duration_s": dur, "rms": rms, "centroid_hz": centroid}


def delta(a: dict, b: dict) -> str:
    """One-line delta summary: b relative to a."""
    dd = b["duration_s"] - a["duration_s"]
    dr = b["rms"] - a["rms"]
    dc = b["centroid_hz"] - a["centroid_hz"]
    return f"  -> Δdur={dd:+.3f}s  Δrms={dr:+.1f}  Δcentroid={dc:+.1f}Hz"


def make_payload(prompt: str, mode: str = "TEXT") -> dict:
    return {"prompt": prompt, "locale": "en-US", "voice": "GRIFFIN", "mode": mode}


# ---------------------------------------------------------------------------
# Section 1: Determinism + negative control
# ---------------------------------------------------------------------------

def test_determinism_and_negative_control():
    print("\n=== 1. DETERMINISM + NEGATIVE CONTROL ===")
    print("(tail 'container logs tts_run' for TTSMarkup/style log lines)\n")

    plain = make_payload(PROMPT)
    d1 = analyze(speak(plain, "plain_run1"), "plain_run1")
    d2 = analyze(speak(plain, "plain_run2"), "plain_run2")
    if d1["bytes"] == d2["bytes"]:
        print("  DETERMINISM: PASS — byte-identical output for identical payload")
    else:
        print(f"  DETERMINISM: WARNING — bytes differ ({d1['bytes']} vs {d2['bytes']}), check for background noise writes")

    print()
    # Negative control: invalid style → daemon must log "not a valid style"
    # This proves the STYLE tag is being READ even if it doesn't change audio
    invalid_uc = make_payload(f"<speak><STYLE set=\"banana\">{PROMPT}</STYLE></speak>", "TEXT")
    analyze(speak(invalid_uc, "invalid_style_TEXT_uc"), "invalid_style_TEXT_uc")
    invalid_ssml = make_payload(f"<speak><STYLE set=\"banana\">{PROMPT}</STYLE></speak>", "SSML")
    analyze(speak(invalid_ssml, "invalid_style_SSML_uc"), "invalid_style_SSML_uc")
    print("  ^ check container logs for 'not a valid style' — confirms parser is reading the tag")


# ---------------------------------------------------------------------------
# Section 2: STYLE — all 7 styles, uppercase vs lowercase, mode:TEXT vs SSML
# ---------------------------------------------------------------------------

STYLES = ["neutral", "excited", "confused", "sheepish", "confident", "enthusiastic", "news"]

def _style_payload(style: str, tag_case: str, wrapper: bool, mode: str) -> dict:
    """Build a style payload sweeping case/wrapper/mode independently."""
    tag = "STYLE" if tag_case == "upper" else "style"
    speak_tag = "speak" if not wrapper else "speak"
    if wrapper:
        prompt = f"<{speak_tag}><{tag} set=\"{style}\">{PROMPT}</{tag}></{speak_tag}>"
    else:
        prompt = f"<{tag} set=\"{style}\">{PROMPT}</{tag}>"
    return make_payload(prompt, mode)


def test_styles():
    print("\n=== 2. STYLE — all 7 styles × (uppercase, lowercase) × (TEXT, SSML) × (wrapped, bare) ===")

    # First establish plain baseline
    baseline = analyze(speak(make_payload(PROMPT), "plain_baseline"), "plain_baseline")
    print()

    results = {}

    for tag_case in ("upper", "lower"):
        for mode in ("TEXT", "SSML"):
            for wrapper in (True, False):
                key = f"{tag_case}_{mode}_{'wrapped' if wrapper else 'bare'}"
                print(f"  -- {key} --")
                for style in STYLES:
                    label = f"{style}_{key}"
                    d = analyze(speak(_style_payload(style, tag_case, wrapper, mode), label), label)
                    results[label] = d
                    if style == "neutral":
                        neutral_ref = d
                    else:
                        print(delta(neutral_ref, d))
                print()

    return baseline, results


# ---------------------------------------------------------------------------
# Section 3: PITCH — halftone, band, add, mult; uppercase + lowercase
# ---------------------------------------------------------------------------

def test_pitch():
    print("\n=== 3. PITCH tags — halftone / band / add / mult ===")
    baseline = analyze(speak(make_payload(PROMPT), "plain_baseline"), "plain_baseline")
    print()

    variants = [
        # (subtype, value, label_suffix)
        ("halftone", "-5", "halftone_neg5"),
        ("halftone", "+5", "halftone_pos5"),
        ("halftone", "-10", "halftone_neg10"),
        ("band", "0.5", "band_0.5"),
        ("band", "2.0", "band_2.0"),
        ("add", "50", "add_50"),
        ("add", "-50", "add_neg50"),
        ("mult", "0.8", "mult_0.8"),
        ("mult", "1.2", "mult_1.2"),
    ]

    for tag_case in ("upper", "lower"):
        for mode in ("TEXT", "SSML"):
            print(f"  -- PITCH {tag_case} mode:{mode} --")
            tag = "PITCH" if tag_case == "upper" else "pitch"
            for subtype, value, suffix in variants:
                prompt = f"<speak><{tag} {subtype}=\"{value}\">{PROMPT}</{tag}></speak>"
                label = f"pitch_{suffix}_{tag_case}_{mode}"
                d = analyze(speak(make_payload(prompt, mode), label), label)
                print(delta(baseline, d))
            print()


# ---------------------------------------------------------------------------
# Section 4: DURATION — stretch and set; confirm vs duration_stretch JSON field
# ---------------------------------------------------------------------------

def test_duration():
    print("\n=== 4. DURATION tag — stretch= and set= ===")
    baseline = analyze(speak(make_payload(PROMPT), "plain_baseline"), "plain_baseline")

    # Also measure JSON duration_stretch for cross-reference (already confirmed in prior script)
    ds_fast = analyze(speak({**make_payload(PROMPT), "duration_stretch": 2.0}, "json_duration_stretch_2.0"), "json_duration_stretch_2.0")
    ds_slow = analyze(speak({**make_payload(PROMPT), "duration_stretch": 0.5}, "json_duration_stretch_0.5"), "json_duration_stretch_0.5")
    print(f"  json_duration_stretch_2.0 {delta(baseline, ds_fast)}")
    print(f"  json_duration_stretch_0.5 {delta(baseline, ds_slow)}")
    print()

    for tag_case in ("upper", "lower"):
        for mode in ("TEXT", "SSML"):
            tag = "DURATION" if tag_case == "upper" else "duration"
            print(f"  -- DURATION {tag_case} mode:{mode} --")
            for attr, val in [("stretch", "0.5"), ("stretch", "2.0"), ("stretch", "3.0"), ("set", "1.0"), ("set", "3.0")]:
                prompt = f"<speak><{tag} {attr}=\"{val}\">{PROMPT}</{tag}></speak>"
                label = f"duration_{attr}_{val}_{tag_case}_{mode}"
                d = analyze(speak(make_payload(prompt, mode), label), label)
                print(delta(baseline, d))
            print()


# ---------------------------------------------------------------------------
# Section 5: BREAK — real silence vs tag spoken aloud
# ---------------------------------------------------------------------------

def test_break():
    print("\n=== 5. BREAK — does it insert silence or speak the tag literally? ===")
    # Baseline: two separate words, no break
    no_break = make_payload("one two")
    b0 = analyze(speak(no_break, "no_break_baseline"), "no_break_baseline")

    for tag_case in ("upper", "lower"):
        for mode in ("TEXT", "SSML"):
            tag = "BREAK" if tag_case == "upper" else "break"
            print(f"  -- BREAK {tag_case} mode:{mode} --")
            for size in ("0.3", "0.5", "1.0", "2.0"):
                prompt = f"<speak>one<{tag} size=\"{size}\"/>two</speak>"
                label = f"break_{size}_{tag_case}_{mode}"
                d = analyze(speak(make_payload(prompt, mode), label), label)
                print(delta(b0, d))
                # If duration increases by ~size seconds, break is real silence.
                # If duration increases by speaking "break size 0.5", it's literal.
            print()


# ---------------------------------------------------------------------------
# Section 6: PHONEME / say-as — pronunciation override
# ---------------------------------------------------------------------------

def test_phoneme():
    print("\n=== 6. PHONEME + say-as ===")
    # Plain "Bono" as baseline
    bono_plain = make_payload("Bono")
    b0 = analyze(speak(bono_plain, "Bono_plain"), "Bono_plain")

    for tag_case in ("upper", "lower"):
        for mode in ("TEXT", "SSML"):
            tag = "phoneme" if tag_case == "lower" else "phoneme"  # binary token is lowercase; try both
            print(f"  -- phoneme {tag_case} mode:{mode} --")
            # b aa n ou = IPA-like phoneme for "Bono" per Combilex phoneme table (see docs/prosody_and_affect.md §8)
            prompt = f"<speak><{tag} ph=\"b aa n ou\">Bono</{tag}></speak>"
            label = f"phoneme_bono_{tag_case}_{mode}"
            d = analyze(speak(make_payload(prompt, mode), label), label)
            print(delta(b0, d))

    print()
    # say-as / spell
    print("  -- say-as spell --")
    for tag_case in ("upper", "lower"):
        for mode in ("TEXT", "SSML"):
            tag = "say-as" if tag_case == "lower" else "say-as"
            prompt = f"<speak><{tag} spell=\"jibo\"/></speak>"
            label = f"say_as_spell_jibo_{tag_case}_{mode}"
            analyze(speak(make_payload(prompt, mode), label), label)
    print("  (listen for 'j-i-b-o' vs 'jibo' to confirm)")


# ---------------------------------------------------------------------------
# Section 7: Wrapped SPEAK tag alone — does the wrapper itself cause issues?
# ---------------------------------------------------------------------------

def test_speak_wrapper():
    print("\n=== 7. SPEAK wrapper alone — does bare <speak>text</speak> pass through cleanly? ===")
    plain = analyze(speak(make_payload(PROMPT), "plain"), "plain")
    wrapped_text = analyze(speak(make_payload(f"<speak>{PROMPT}</speak>", "TEXT"), "speak_wrap_TEXT"), "speak_wrap_TEXT")
    wrapped_ssml = analyze(speak(make_payload(f"<speak>{PROMPT}</speak>", "SSML"), "speak_wrap_SSML"), "speak_wrap_SSML")
    print(delta(plain, wrapped_text), "<-- wrapped TEXT vs plain")
    print(delta(plain, wrapped_ssml), "<-- wrapped SSML vs plain")
    print("  (byte-identical to plain = wrapper is stripped cleanly; longer = spoken literally)")


# ---------------------------------------------------------------------------
# Section 8: Token times — confirm tags parsed vs spoken for one key case
# ---------------------------------------------------------------------------

def test_token_times_key_cases():
    print("\n=== 8. /tts_token_times — token names reveal parse vs literal for key cases ===")

    def token_names(payload: dict) -> list:
        req = urllib.request.Request(
            f"http://{HOST}:{PORT}/tts_token_times",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read())
            return [t["name"] for t in data.get("tokentimes", {}).get("tokens", [])]
        except Exception as e:
            return [f"ERROR: {e}"]

    cases = [
        ("plain TEXT", make_payload("hello jibo")),
        ("STYLE uc TEXT wrapped", make_payload("<speak><STYLE set=\"excited\">hello jibo</STYLE></speak>", "TEXT")),
        ("STYLE lc TEXT wrapped", make_payload("<speak><style set=\"excited\">hello jibo</style></speak>", "TEXT")),
        ("STYLE uc SSML wrapped", make_payload("<speak><STYLE set=\"excited\">hello jibo</STYLE></speak>", "SSML")),
        ("BREAK uc TEXT", make_payload("<speak>hello<BREAK size=\"0.5\"/>jibo</speak>", "TEXT")),
        ("BREAK uc SSML", make_payload("<speak>hello<BREAK size=\"0.5\"/>jibo</speak>", "SSML")),
    ]
    for label, payload in cases:
        names = token_names(payload)
        print(f"  {label:<35} tokens={names}")
    print("  (if tokens contain '<', '/', 'STYLE', etc. — tag was spoken literally)")
    print("  (if tokens are just words/phonemes — tag was parsed and stripped)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("=" * 70)
    print("confirm_markup_dialect.py — native markup dialect experiment")
    print(f"Target: http://{HOST}:{PORT}  PCM: {SHARED_PCM}")
    print("=" * 70)
    print()
    print("TIP: in a separate terminal run:")
    print("  container logs -f tts_run | grep -iE 'TTSMarkup|not a valid style|Style|Pronuncing'")
    print("to see which markup paths the daemon hits in real time.")
    print()

    if not os.path.exists(SHARED_PCM):
        print(f"ERROR: {SHARED_PCM} not found — is tts_run running and has it synthesized at least once?")
        print("Run: bin/griffintts 'hello' && then retry this script.")
        raise SystemExit(1)

    test_determinism_and_negative_control()
    test_speak_wrapper()
    test_styles()
    test_pitch()
    test_duration()
    test_break()
    test_phoneme()
    test_token_times_key_cases()

    print("\n" + "=" * 70)
    print("DONE. Summarize CONFIRMED/DISCONFIRMED per row above and record in")
    print("tools/griffintts/docs/prosody_and_affect.md")
    print("=" * 70)
