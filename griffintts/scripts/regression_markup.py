#!/usr/bin/env python3
"""
regression_markup.py — automated acoustic regression tests for affective markup rendering

Requires: tts_run container running at localhost:8089; skips gracefully if absent.

WHAT THIS DOES:
  Reads testdata/markup_corpus.json, synthesizes each entry's markup and
  plain_equivalent via the /tts_speak endpoint, measures duration/RMS/spectral
  centroid for both, then asserts the centroid_delta_hz_min threshold where
  specified.  Produces a PASS/FAIL line per entry and a summary count.

PCM CAPTURE TECHNIQUE:
  Identical to confirm_markup_dialect.py: record the file size of the shared
  PCM file before each POST, then read only the bytes appended by that
  synthesis call.  This isolates each utterance from background writes.

USAGE:
  # from the repo root, with .venv active:
  .venv/bin/python tools/griffintts/scripts/regression_markup.py

  # or from inside tools/griffintts/:
  ../../.venv/bin/python scripts/regression_markup.py

CONTAINER CHECK:
  A 2-second GET to http://localhost:8089/tts_speak (intentionally wrong
  method to get a non-timeout response) verifies reachability before the
  main loop.  If the check fails the script exits 0 with a clear skip message.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional

import numpy as np

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

HOST = "localhost"
PORT = "8089"
SHARED_PCM = "/tmp/griffintts-shared/output.raw"
SR = 48000  # 16-bit mono PCM sample rate

# Locate testdata relative to this script (works from repo root or script dir)
_SCRIPT_DIR = Path(__file__).resolve().parent
CORPUS_PATH = _SCRIPT_DIR.parent / "testdata" / "markup_corpus.json"

# How long to wait after a POST for the PCM file to be fully flushed.
# Match the settle time used in confirm_markup_dialect.py.
SETTLE_S = 0.5

# ---------------------------------------------------------------------------
# Container reachability check
# ---------------------------------------------------------------------------

def check_container_reachable(timeout: float = 2.0) -> bool:
    """
    Return True if the tts_run HTTP server is reachable.

    We send a GET (which the server will reject with 405 or similar), but a
    response of any kind — including an HTTP error — means it is up.
    A connection-refused or timeout means it is absent.
    """
    try:
        req = urllib.request.Request(
            f"http://{HOST}:{PORT}/tts_speak",
            method="GET",
        )
        urllib.request.urlopen(req, timeout=timeout)
        return True
    except urllib.error.HTTPError:
        # Any HTTP error (400, 405 …) means the server answered — it is up.
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------
# PCM capture helpers (same technique as confirm_markup_dialect.py)
# ---------------------------------------------------------------------------

def get_offset() -> int:
    return os.path.getsize(SHARED_PCM) if os.path.exists(SHARED_PCM) else 0


def speak(payload: dict, label: str, settle: float = SETTLE_S) -> bytes:
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
        print(f"    [{label}] HTTP ERROR {e.code}: {e.read()[:200]}", file=sys.stderr)
        return b""
    except Exception as e:
        print(f"    [{label}] ERROR: {e}", file=sys.stderr)
        return b""
    time.sleep(settle)
    with open(SHARED_PCM, "rb") as f:
        f.seek(start)
        data = f.read()
    return data


def analyze(data: bytes) -> dict:
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
    return {"bytes": len(data), "duration_s": dur, "rms": rms, "centroid_hz": centroid}


def make_payload(prompt: str, mode: str = "TEXT") -> dict:
    return {"prompt": prompt, "locale": "en-US", "voice": "GRIFFIN", "mode": mode}


# ---------------------------------------------------------------------------
# Per-entry regression
# ---------------------------------------------------------------------------

def run_entry(entry: dict) -> tuple[bool, str]:
    """
    Synthesize one corpus entry.  Returns (passed: bool, detail_line: str).

    passed is True when:
      - Both synthesis calls returned non-empty PCM.
      - centroid_delta_hz_min (if present) is satisfied:
          abs(centroid_markup - centroid_plain) >= threshold.
    """
    entry_id = entry["id"]
    markup_text = entry["markup"]
    plain_text = entry["plain_equivalent"]
    acoustic = entry.get("expected_acoustic", {})
    threshold = acoustic.get("centroid_delta_hz_min")

    markup_pcm = speak(make_payload(markup_text), f"{entry_id}:markup")
    plain_pcm = speak(make_payload(plain_text), f"{entry_id}:plain")

    if not markup_pcm or not plain_pcm:
        return False, f"  FAIL  [{entry_id}] synthesis returned empty PCM"

    m = analyze(markup_pcm)
    p = analyze(plain_pcm)

    delta_dur = m["duration_s"] - p["duration_s"]
    delta_rms = m["rms"] - p["rms"]
    delta_centroid = m["centroid_hz"] - p["centroid_hz"]

    metrics = (
        f"bytes={m['bytes']}vs{p['bytes']}"
        f"  dur={m['duration_s']:.3f}vs{p['duration_s']:.3f}s (Δ{delta_dur:+.3f})"
        f"  rms={m['rms']:.0f}vs{p['rms']:.0f} (Δ{delta_rms:+.0f})"
        f"  centroid={m['centroid_hz']:.1f}vs{p['centroid_hz']:.1f}Hz (Δ{delta_centroid:+.1f})"
    )

    if threshold is not None:
        passed = abs(delta_centroid) >= threshold
        verdict = "PASS" if passed else "FAIL"
        detail = (
            f"  {verdict}  [{entry_id}] centroid Δ={delta_centroid:+.1f}Hz "
            f"(need ≥{threshold}Hz)  {metrics}"
        )
    else:
        # No threshold — pass as long as PCM was non-empty (measured above).
        passed = True
        detail = f"  MEAS  [{entry_id}] no threshold  {metrics}"

    return passed, detail


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    print("=" * 72)
    print("regression_markup.py — affective markup acoustic regression")
    print(f"Corpus:  {CORPUS_PATH}")
    print(f"Target:  http://{HOST}:{PORT}  PCM: {SHARED_PCM}")
    print("=" * 72)
    print()

    # --- Container reachability check (2-second timeout, skip gracefully) ---
    print("Checking tts_run container reachability...")
    if not check_container_reachable(timeout=2.0):
        print()
        print("SKIP: tts_run container is not reachable at "
              f"http://{HOST}:{PORT}.")
        print("      Start the container (e.g. 'container start tts_run') "
              "and re-run this script.")
        print("      All Go unit tests (TestPreprocessMarkup etc.) remain "
              "runnable without the container.")
        sys.exit(0)
    print("  Container is reachable.")
    print()

    # --- Verify the shared PCM file exists (container must have spoken at least once) ---
    if not os.path.exists(SHARED_PCM):
        print(f"SKIP: {SHARED_PCM} not found.")
        print("      The container appears to be running but has not synthesised "
              "any audio yet.")
        print("      Run: bin/griffintts 'hello' — then retry this script.")
        sys.exit(0)

    # --- Load corpus ---
    if not CORPUS_PATH.exists():
        print(f"ERROR: corpus file not found: {CORPUS_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(CORPUS_PATH, encoding="utf-8") as f:
        corpus = json.load(f)

    print(f"Loaded {len(corpus)} entries from markup_corpus.json")
    print()

    # --- Run entries ---
    n_pass = 0
    n_fail = 0
    n_meas = 0  # entries with no threshold (measured, not asserted)

    for entry in corpus:
        entry_id = entry.get("id", "?")
        description = entry.get("description", "")
        print(f"[{entry_id}]  {description}")
        passed, detail = run_entry(entry)
        print(detail)
        print()

        if "MEAS" in detail:
            n_meas += 1
        elif passed:
            n_pass += 1
        else:
            n_fail += 1

    # --- Summary ---
    total_asserted = n_pass + n_fail
    print("=" * 72)
    print(f"SUMMARY:  {n_pass} PASS  {n_fail} FAIL  {n_meas} MEAS (no threshold)")
    if total_asserted > 0:
        pct = 100 * n_pass // total_asserted
        print(f"          {pct}% of asserted entries passed.")
    print("=" * 72)

    if n_fail > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
