#!/usr/bin/env python3
"""
Empirical confirmation harness for Jibo /tts_speak request parameters, SSML/ESML
markup, and the /tts_effects (Jibonics) WebSocket channel.

Purpose: this repo's docs previously *inferred* several "levers of control"
(pitch, whisper, volume, pitchBandwidth, ESML tags, inline sound-effect tags)
from a combination of the JS SDK's field names and typical SSML conventions,
without directly testing them against the live emulated container. This
script re-runs those tests mechanically so findings can be reproduced and
re-verified after any container/config/model change.

Requires: the emulated container (`tts_run`) running and reachable at
localhost:8089, plus `numpy` and `websocket-client` (pip/uv install).

Usage:
    .venv/bin/python tools/griffintts/scripts/confirm_prosody_params.py
"""
import json
import os
import threading
import time
import urllib.error
import urllib.request

import numpy as np
import websocket

SHARED_PCM = "/tmp/griffintts-shared/output.raw"
HOST = "localhost"
PORT = "8089"


def get_offset() -> int:
    return os.path.getsize(SHARED_PCM) if os.path.exists(SHARED_PCM) else 0


def speak(payload: dict, label: str, settle: float = 0.3) -> bytes:
    """POST to /tts_speak and capture exactly the newly-written PCM bytes
    using the same offset-seek technique as the griffintts CLI."""
    start = get_offset()
    req = urllib.request.Request(
        f"http://{HOST}:{PORT}/tts_speak",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            status = resp.status
    except urllib.error.HTTPError as e:
        print(f"[{label}] HTTP ERROR {e.code}: {e.read()[:300]}")
        return b""
    time.sleep(settle)
    with open(SHARED_PCM, "rb") as f:
        f.seek(start)
        data = f.read()
    return data


def token_times(payload: dict) -> dict:
    req = urllib.request.Request(
        f"http://{HOST}:{PORT}/tts_token_times",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def analyze(data: bytes, label: str, sr: int = 48000) -> dict:
    arr = np.frombuffer(data, dtype=np.int16).astype(np.float64)
    dur = len(arr) / sr
    rms = float(np.sqrt(np.mean(arr**2))) if len(arr) else 0.0
    centroid = 0.0
    if len(arr) > 2048:
        n = min(8192, len(arr))
        windowed = arr[:n] * np.hanning(n)
        spec = np.abs(np.fft.rfft(windowed))
        freqs = np.fft.rfftfreq(n, 1 / sr)
        centroid = float(np.sum(freqs * spec) / (np.sum(spec) + 1e-9))
    print(f"{label:<22} bytes={len(data):>8} dur={dur:>6.3f}s rms={rms:>8.1f} centroid={centroid:>8.1f}Hz")
    return {"bytes": len(data), "duration_s": dur, "rms": rms, "centroid_hz": centroid}


def test_request_body_fields():
    print("\n=== 1. /tts_speak JSON field effects (pitch, volume, whisper, pitchBandwidth, speed, duration_stretch) ===")
    base = {"prompt": "Testing pitch and volume boundaries.", "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"}

    b0 = analyze(speak(base, "baseline"), "baseline")
    analyze(speak({**base, "pitch": 0.1}, "pitch_0.1"), "pitch_0.1")
    analyze(speak({**base, "pitch": 0.9}, "pitch_0.9"), "pitch_0.9")
    analyze(speak({**base, "whisper": True}, "whisper_bool"), "whisper_bool")
    analyze(speak({**base, "whisper": "TRUE"}, "whisper_str"), "whisper_str")
    analyze(speak({**base, "volume": 0.0}, "volume_0.0"), "volume_0.0")
    analyze(speak({**base, "volume": 3.0}, "volume_3.0"), "volume_3.0")
    analyze(speak({**base, "pitchBandwidth": 0.0}, "bandwidth_0.0"), "bandwidth_0.0")
    analyze(speak({**base, "pitchBandwidth": 2.0}, "bandwidth_2.0"), "bandwidth_2.0")
    analyze(speak({**base, "speed": 2.0}, "speed_2.0"), "speed_2.0")
    analyze(speak({**base, "speed": 0.5}, "speed_0.5"), "speed_0.5")

    print("\n--- duration_stretch (CONFIRMED functional; verify inverse-rate relationship) ---")
    for v in (2.0, 1.5, 1.0, 0.5):
        d = analyze(speak({**base, "duration_stretch": v}, f"duration_stretch_{v}"), f"duration_stretch_{v}")
        ratio = d["duration_s"] / b0["duration_s"] if b0["duration_s"] else 0
        print(f"    -> ratio vs baseline: {ratio:.3f} (expect ~1/{v}={1/v:.3f} if inverse-rate)")

    print("\n--- determinism control (same payload twice; HTS synthesis should be deterministic) ---")
    analyze(speak(base, "determinism_run1"), "determinism_run1")
    analyze(speak(base, "determinism_run2"), "determinism_run2")


def test_markup():
    print("\n=== 2. ESML / SSML markup handling ===")
    plain = {"prompt": "Excited test.", "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"}
    esml_text = {"prompt": "<excited>Excited test.</excited>", "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"}
    esml_ssml = {"prompt": "<excited>Excited test.</excited>", "locale": "en-US", "voice": "GRIFFIN", "mode": "SSML"}
    item_tag = {"prompt": 'Testing sound effect <item name="woo_hoo_hoo" /> right here.',
                "locale": "en-US", "voice": "GRIFFIN", "mode": "TEXT"}

    analyze(speak(plain, "plain_baseline"), "plain_baseline")
    analyze(speak(esml_text, "esml_TEXT_mode"), "esml_TEXT_mode")
    analyze(speak(esml_ssml, "esml_SSML_mode"), "esml_SSML_mode")
    analyze(speak(item_tag, "item_tag_guess"), "item_tag_guess")

    print("\n--- token_times reveals whether tags are parsed or spoken literally ---")
    for payload, label in [(esml_text, "esml_TEXT"), (item_tag, "item_tag")]:
        tt = token_times(payload)
        names = [t["name"] for t in tt["tokentimes"]["tokens"]]
        print(f"{label}: tokens = {names}")


def test_effects_websocket():
    print("\n=== 3. /tts_effects WebSocket (Jibonics startEffect/stopEffect) ===")
    start_offset = get_offset()

    def on_open(ws):
        payload = json.dumps({"name": "woo_hoo_hoo", "action": "START", "param": "1"})
        ws.send(payload)
        print(f"[SENT] {payload}")

    ws = websocket.WebSocketApp(f"ws://{HOST}:{PORT}/tts_effects", on_open=on_open)
    t = threading.Thread(target=ws.run_forever, daemon=True)
    t.start()
    time.sleep(2)
    ws.close()

    end_offset = get_offset()
    print(f"PCM bytes written during effect window: {end_offset - start_offset}")
    if end_offset == start_offset:
        print("RESULT: No audio produced. Effect either not implemented in this build, "
              "wrong payload shape, or sourced from an asset directory not present on this unit.")


if __name__ == "__main__":
    test_request_body_fields()
    test_markup()
    test_effects_websocket()
