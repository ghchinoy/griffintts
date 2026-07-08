#!/usr/bin/env python3
"""
Empirical verification of three jibo-tts-service daemon behaviors:
1. SpeakingStyle trigger: find the actual field name (if any) for vocal style selection.
2. /tts_stop: confirm a GET to /tts_stop actually halts PCM byte growth mid-utterance.
3. <audio name="..."/>: verify inline audio tags in prompt text produce audible output.

Each test prints a CONFIRMED or DISCONFIRMED verdict with raw data.

Usage:
    .venv/bin/python tools/griffintts/scripts/verify_ykr6_endpoints.py
"""
import json
import os
import time
import threading
import urllib.request
import urllib.error

import numpy as np

SHARED_PCM = "/tmp/griffintts-shared/output.raw"
HOST = "localhost"
PORT = "8089"

def get_offset():
    return os.path.getsize(SHARED_PCM) if os.path.exists(SHARED_PCM) else 0

def speak(payload, timeout=15):
    req = urllib.request.Request(
        f"http://{HOST}:{PORT}/tts_speak",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, None
    except urllib.error.HTTPError as e:
        return e.code, e.read()

def capture_bytes(start_offset, settle=0.3):
    time.sleep(settle)
    with open(SHARED_PCM, "rb") as f:
        f.seek(start_offset)
        data = f.read()
    return data

def rms(data):
    if len(data) < 2:
        return 0.0
    arr = np.frombuffer(data, dtype=np.int16).astype(np.float64)
    return float(np.sqrt(np.mean(arr**2)))

def centroid(data, sr=48000):
    arr = np.frombuffer(data, dtype=np.int16).astype(np.float64)
    if len(arr) < 2048:
        return 0.0
    n = min(8192, len(arr))
    windowed = arr[:n] * np.hanning(n)
    spec = np.abs(np.fft.rfft(windowed))
    freqs = np.fft.rfftfreq(n, 1 / sr)
    return float(np.sum(freqs * spec) / (np.sum(spec) + 1e-9))

def print_verdict(label, confirmed, detail):
    symbol = "✅ CONFIRMED" if confirmed else "❌ DISCONFIRMED"
    print(f"\n  {symbol}: {label}")
    print(f"  {detail}")

# ── Test 1: SpeakingStyle field sweep ─────────────────────────────────────
def test_style_trigger():
    print("\n=== TEST 1: SpeakingStyle trigger field sweep ===")
    BASE = {"prompt": "Testing style trigger.", "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"}
    
    baseline_offset = get_offset()
    speak(BASE)
    baseline_data = capture_bytes(baseline_offset)
    b_rms = rms(baseline_data)
    b_cen = centroid(baseline_data)
    print(f"  Baseline: {len(baseline_data)} bytes, rms={b_rms:.1f}, centroid={b_cen:.1f}Hz")
    
    # Candidate field names to try for each known style
    # Based on: JS SDK field names, the <es cat="..."/> tag, and internal debug log keys
    candidates = [
        {"style": "excited"},
        {"cat": "excited"},
        {"speakingStyle": "excited"},
        {"es_cat": "excited"},
        {"emotion": "excited"},
        {"pitch": 999, "pitchBandwidth": 2.0},  # proxy for high excitation params
    ]
    
    any_effect = False
    for extra in candidates:
        label = str(extra)
        offset = get_offset()
        status, _ = speak({**BASE, **extra})
        data = capture_bytes(offset)
        r = rms(data)
        c = centroid(data)
        dur = len(data) / 2 / 48000
        rms_diff = abs(r - b_rms)
        cen_diff = abs(c - b_cen)
        dur_diff = abs(dur - len(baseline_data) / 2 / 48000)
        effect = (rms_diff > 20 or cen_diff > 30) and len(data) > 0
        print(f"    {label}: bytes={len(data)}, rms={r:.1f}(Δ{r-b_rms:+.1f}), centroid={c:.1f}(Δ{c-b_cen:+.1f}), dur={dur:.3f}s -> {'EFFECT' if effect else 'no effect'}")
        if effect:
            any_effect = True
    
    print_verdict(
        "SpeakingStyle can be triggered via raw /tts_speak HTTP field",
        any_effect,
        "One or more candidate fields produced measurable RMS or centroid deviation from baseline." if any_effect
        else "All candidate fields produced byte-identical or noise-level output. The style/emotion must be applied at the JS-SDK preprocessor layer (upstream of /tts_speak), not directly via HTTP."
    )
    return any_effect

# ── Test 2: /tts_stop halts PCM growth ───────────────────────────────────
def test_tts_stop():
    print("\n=== TEST 2: /tts_stop endpoint halts PCM byte growth ===")
    BASE = {"prompt": "One two three four five six seven eight nine ten. One two three four five six seven eight nine ten.", "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"}

    # Fire a long speak in background
    start_offset = get_offset()
    result = {"status": None}
    def do_speak():
        result["status"], _ = speak(BASE, timeout=20)
    t = threading.Thread(target=do_speak, daemon=True)
    t.start()

    # Wait for PCM to start growing
    waited = 0.0
    bytes_mid = 0
    for _ in range(20):
        time.sleep(0.15)
        waited += 0.15
        cur = get_offset()
        if cur > start_offset + 10000:
            bytes_mid = cur
            print(f"  PCM growing. Offset after {waited:.2f}s: {cur - start_offset} bytes. Firing /tts_stop...")
            break

    if bytes_mid == 0:
        print_verdict("/tts_stop halts PCM growth", False, "PCM never started growing — speak may have completed before we could interrupt it.")
        return False

    # Call /tts_stop
    try:
        req = urllib.request.Request(f"http://{HOST}:{PORT}/tts_stop", method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            stop_status = resp.status
    except Exception as e:
        print(f"  /tts_stop call failed: {e}")
        print_verdict("/tts_stop halts PCM growth", False, f"/tts_stop returned error: {e}")
        return False

    print(f"  /tts_stop returned HTTP {stop_status}")

    # Wait and check if growth continues
    time.sleep(0.5)
    bytes_after = get_offset()
    growth = bytes_after - bytes_mid

    confirmed = stop_status in (200, 204) and growth < 10000
    print_verdict(
        "/tts_stop halts PCM growth",
        confirmed,
        f"PCM grew {growth} bytes after /tts_stop call (HTTP {stop_status}). {'< 10KB suggests halted.' if growth < 10000 else 'Continued growing — stop had no effect on ALSA output.'}"
    )
    t.join(timeout=5)
    return confirmed

# ── Test 3: <audio name="..."/> inline tag produces output ────────────────
def test_inline_audio():
    print("\n=== TEST 3: <audio name='...'> inline tag produces audible output ===")
    
    # Baseline: plain text with no tag
    b_offset = get_offset()
    speak({"prompt": "Testing audio tag.", "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"})
    baseline = capture_bytes(b_offset)
    b_dur = len(baseline) / 2 / 48000
    
    # Test with inline <audio> tag
    a_offset = get_offset()
    speak({"prompt": "Testing audio tag. <audio name=\"woo_hoo_hoo\" /> done.", "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"})
    audio_data = capture_bytes(a_offset)
    a_dur = len(audio_data) / 2 / 48000
    
    # Also check via token_times to see if tag was spoken literally
    ttt_req = urllib.request.Request(
        f"http://{HOST}:{PORT}/tts_token_times",
        data=json.dumps({"prompt": "Testing audio tag. <audio name=\"woo_hoo_hoo\" /> done.", "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    tokens = []
    try:
        with urllib.request.urlopen(ttt_req, timeout=10) as resp:
            tdata = json.loads(resp.read())
            tokens = [t["name"] for t in tdata.get("tokentimes", {}).get("tokens", [])]
    except Exception:
        pass

    dur_diff = abs(a_dur - b_dur)
    tag_spoken_literally = any("<audio" in t or "woo_hoo_hoo" in t for t in tokens)
    sound_effect_likely = dur_diff > 0.3 and not tag_spoken_literally

    print(f"  Baseline duration: {b_dur:.3f}s | With-audio-tag duration: {a_dur:.3f}s (diff: {dur_diff:+.3f}s)")
    print(f"  Token times: {tokens}")
    print(f"  Tag spoken literally: {tag_spoken_literally}")

    print_verdict(
        "<audio name='...'> produces audible sound effect output",
        sound_effect_likely,
        (
            f"Duration increased {dur_diff:.3f}s and tag NOT in token list — suggests audio was rendered, not spoken."
            if sound_effect_likely else
            (
                f"Tag appears in token list as literal text ({[t for t in tokens if '<audio' in t or 'woo' in t]}) — C++ engine did NOT parse it."
                if tag_spoken_literally else
                f"Duration diff {dur_diff:.3f}s is within noise — no measurable additional audio rendered."
            )
        )
    )
    return sound_effect_likely

if __name__ == "__main__":
    print("=== Verifying SpeakingStyle, /tts_stop, and <audio> tags ===")
    style_ok   = test_style_trigger()
    stop_ok    = test_tts_stop()
    audio_ok   = test_inline_audio()
    
    print("\n=== SUMMARY ===")
    print(f"  SpeakingStyle via HTTP field:  {'CONFIRMED' if style_ok  else 'DISCONFIRMED'}")
    print(f"  /tts_stop halts playback:      {'CONFIRMED' if stop_ok  else 'DISCONFIRMED'}")
    print(f"  <audio> inline tag works:      {'CONFIRMED' if audio_ok else 'DISCONFIRMED'}")
