#!/usr/bin/env python3
"""
Automated Regression and Fingerprint Verification Script for Griffin TTS.
Synthesizes our canonical reference corpus under multiple speed factors,
computes DSP fingerprints (bytes, duration, RMS, spectral centroid), and
compares them against a "golden" reference JSON baseline to ensure zero regressions.

Usage:
    .venv/bin/python tools/griffintts/scripts/verify_corpus.py [--generate]
    Use --generate to write/overwrite the golden_fingerprints.json file.
"""
import json
import os
import subprocess
import sys
import time

import numpy as np

CORPUS_PATH = "tools/griffintts/testdata/reference_corpus.txt"
GOLDEN_PATH = "tools/griffintts/testdata/golden_fingerprints.json"
CLI_PATH = "tools/bin/griffintts"


def load_corpus():
    with open(CORPUS_PATH, "r") as f:
        return f.read().strip()


def run_synthesis(text, speed, out_path):
    cmd = [CLI_PATH, "--ow", out_path, "--speed", f"{speed:.2f}", text]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error running griffintts: {res.stderr}")
        return False
    return True


def analyze_wav(wav_path, sr=48000):
    # Convert WAV to raw PCM using ffmpeg for analysis
    raw_path = wav_path + ".raw"
    cmd = ["ffmpeg", "-y", "-i", wav_path, "-f", "s16le", "-ac", "1", "-ar", str(sr), raw_path]
    subprocess.run(cmd, capture_output=True)
    
    data = np.fromfile(raw_path, dtype=np.int16).astype(np.float64)
    os.remove(raw_path)
    
    n_samples = len(data)
    dur = n_samples / sr
    rms = float(np.sqrt(np.mean(data**2))) if n_samples > 0 else 0.0
    
    # Calculate spectral centroid
    centroid = 0.0
    if n_samples > 2048:
        n = min(8192, n_samples)
        windowed = data[:n] * np.hanning(n)
        spec = np.abs(np.fft.rfft(windowed))
        freqs = np.fft.rfftfreq(n, 1 / sr)
        centroid = float(np.sum(freqs * spec) / (np.sum(spec) + 1e-9))
        
    return {
        "bytes": os.path.getsize(wav_path),
        "duration_s": round(dur, 3),
        "rms": round(rms, 1),
        "centroid_hz": round(centroid, 1)
    }


def main():
    generate_mode = "--generate" in sys.argv
    
    if not os.path.exists(CLI_PATH):
        print(f"Error: griffintts binary not found at {CLI_PATH}. Run 'make griffintts' first.")
        sys.exit(1)
        
    text = load_corpus()
    print(f"Loaded reference corpus: \"{text}\"")
    
    runs = [
        ("baseline", 1.0, "/tmp/corpus_baseline.wav"),
        ("fast", 1.5, "/tmp/corpus_fast.wav"),
        ("slow", 0.7, "/tmp/corpus_slow.wav"),
    ]
    
    current_fingerprints = {}
    
    for label, speed, path in runs:
        print(f"Synthesizing '{label}' variant at speed {speed:.1f}x...")
        if not run_synthesis(text, speed, path):
            print("Synthesis failed!")
            sys.exit(1)
        
        # Analyze output
        fingerprints = analyze_wav(path)
        current_fingerprints[label] = fingerprints
        os.remove(path) # Clean up
        
    if generate_mode or not os.path.exists(GOLDEN_PATH):
        print(f"\nWriting golden fingerprints to {GOLDEN_PATH}...")
        with open(GOLDEN_PATH, "w") as f:
            json.dump(current_fingerprints, f, indent=2)
        print("Success! Golden baseline successfully established.")
        sys.exit(0)
        
    # Standard verification mode
    print(f"\nLoading golden fingerprints from {GOLDEN_PATH}...")
    with open(GOLDEN_PATH, "r") as f:
        golden = json.load(f)
        
    all_pass = True
    print("\n=== REGRESSION REPORT ===")
    print(f"{'Run Label':<12}{'Metric':<14}{'Golden':>10}{'Current':>10}{'Diff':>10}{'Status':>10}")
    print("-" * 70)
    
    for label, metrics in current_fingerprints.items():
        g_metrics = golden.get(label, {})
        for metric_name, val in metrics.items():
            g_val = g_metrics.get(metric_name, 0.0)
            diff = val - g_val
            
            # Tolerances (strict but allowing minor floating point / container buffering jitter)
            tolerance = 0.05
            if metric_name == "bytes":
                tolerance = 4096 # Allow up to 4KB size jitter due to ffmpeg container block writes
            elif metric_name == "rms":
                tolerance = 25.0
            elif metric_name == "centroid_hz":
                tolerance = 50.0
                
            status = "PASS"
            if abs(diff) > tolerance:
                status = "FAIL"
                all_pass = False
                
            diff_str = f"{diff:+.3f}" if isinstance(diff, float) else f"{diff:+d}"
            val_str = f"{val:.3f}" if isinstance(val, float) else f"{val}"
            g_val_str = f"{g_val:.3f}" if isinstance(g_val, float) else f"{g_val}"
            
            print(f"{label:<12}{metric_name:<14}{g_val_str:>10}{val_str:>10}{diff_str:>10}{status:>10}")
            
    if all_pass:
        print("\n\033[32m[PASS]\033[0m All speech synthesis metrics match golden baseline! Zero regressions detected.")
        sys.exit(0)
    else:
        print("\n\033[31m[FAIL]\033[0m One or more speech parameters deviated from the golden baseline. Regression suspected!")
        sys.exit(1)


if __name__ == "__main__":
    main()
