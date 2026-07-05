# Jibo Griffin TTS CLI Utility

A high-fidelity local CLI speech synthesizer wrapping Jibo's original 2017 "Griffin" voice. 

By leveraging user-mode ARM emulation inside a native macOS container machine, this utility executes Jibo's full text normalization frontend (OpenFST, Combilex lexicon, G2P) and high-fidelity WORLD vocoder acoustic synthesizer offline on macOS.

---

## Prerequisites

### 1. Voice Assets (required — must be pulled from a live Jibo unit)

The `tools/griffintts/assets/` directory is **gitignored** and must be populated by extracting files directly from a live Jibo robot over SSH before anything here will work. Both synthesis modes depend on it:

| Mode | Assets required |
|---|---|
| Container (primary) | `assets/en_us_world/`, `assets/bin/jibo-tts-service`, `assets/lib/*.so`, `assets/jibo-tts-service.json` |
| Native (`--native`) | `assets/en_us/en_us.voice`, `assets/en_us/en_us.dictionary_full`, `assets/en_us/en_us.phones` |

To extract from a live unit (replace hostname if your unit's mDNS name differs):
```bash
# Voice model bundles
scp -r root@mars-bond-mesquite-cotton.local:/usr/local/share/ttsservice/voices/en_us_world tools/griffintts/assets/
scp -r root@mars-bond-mesquite-cotton.local:/usr/local/share/ttsservice/voices/en_us      tools/griffintts/assets/

# Jibo TTS service binary and config
mkdir -p tools/griffintts/assets/bin tools/griffintts/assets/lib
scp root@mars-bond-mesquite-cotton.local:/usr/local/bin/jibo-tts-service         tools/griffintts/assets/bin/
scp root@mars-bond-mesquite-cotton.local:/usr/local/etc/jibo-tts-service.json    tools/griffintts/assets/

# Dynamic library dependencies (required for the container)
ssh root@mars-bond-mesquite-cotton.local \
  "tar -czf - -C /usr/local/lib libJiboTTSService.so libJiboServiceFramework.so libJiboUtil.so && \
   tar -czf - -C /usr/lib libfst.so.3 libfst.so.3.0.0 libv8_base.so libv8_libbase.so \
             libv8_libplatform.so libv8_nosnapshot.so libv8_snapshot.so \
             libPocoFoundation.so.48 libPocoJSON.so.48 libPocoUtil.so.48 \
             libPocoXML.so.48 libPocoNet.so.48 libPocoNetSSL.so.48 libPocoCrypto.so.48 \
             libpcre.so.1 libexpat.so.1 libz.so.1" \
  | tar -xzf - -C tools/griffintts/assets/lib/
```

The full extraction process and rationale for each file is documented in [`docs/architecture.md`](docs/architecture.md) and the original extraction task `jibo-8uu` in the `bd` issue tracker.

### 2. Host Tools

Ensure the following are installed on your Mac:
- **FFmpeg** — converts raw PCM output to WAV (`brew install ffmpeg`)
- **Apple Container Platform** — required for container mode (primary high-fidelity voice); optional for `--native` mode

---

## Setup & Compilation

To build the command-line utility, simply run the main project target:
```bash
make griffintts
```
This compiles the native Go CLI wrapper and places the executable directly at **`bin/griffintts`**.

---

## Usage Guide

The `griffintts` CLI is designed to be highly flexible, supporting direct arguments, options, and shell pipes. It operates in **two distinct execution modes**:

### 1. Standalone Native macOS Mode (Experimental / Legacy Robotic Fallback)
Synthesizes Jibo's older `en_us` 3-stream voice model **natively on macOS without any containers or virtual machines**. 

*Note: Because Jibo's classic voice contains a custom 31-coefficient LPF (Low-Pass Filter) stream, running it on standard open-source HTS engines causes severe phase-misalignment, resulting in a wiggling "fluttering" sound. This mode remains a standalone, highly-robotic experimental fallback.*

To run natively, append the `--native` (or `-n`) flag:
```bash
bin/griffintts --native --ow native_output.wav "Hello! Synthesized natively on macOS."
```

### 2. Emulated Container Mode (Primary High-Fidelity Character Voice)
Runs Jibo's original 32-bit ARM Linux binary under emulation inside a local container machine. This is **Jibo's primary high-fidelity character voice**, as it runs Jibo's proprietary C++ vocoder to perfectly decode the custom LPF and 4-stream WORLD vocoder structures.

On its **first run**, this mode will automatically configure, build, and start the underlying background container `tts_run` to expose Jibo's HTTP endpoints.

Run the emulated mode by omitting the native flag:
```bash
bin/griffintts --ow emulated_output.wav "Hi there! I am Griffin, Jibo's voice."
```

---

## CLI Options & Pipes

The utility supports full POSIX double-dash flags. You can see all available configurations via `--help`:
```text
Usage of bin/griffintts:
      --dry-run       Dry run validation without modifying files or triggering synthesis (AX)
  -h, --help          help for griffintts
      --host string   TTS container host (default "localhost")
      --json          Output in machine-readable JSON format (AX)
  -n, --native        Use the 100% native macOS HTS standalone synthesizer (no containers)
  -o, --ow string     Path to save the synthesized WAV file (default "output.wav")
  -p, --port string   TTS container port (default "8089")
```

### 1. Shell Pipe / Stdin Support
You can pipe text directly into `griffintts` via standard input:
```bash
echo "Piped text is synthesized automatically." | bin/griffintts --native
```

### 2. AX (Agent Experience) Output
If `--json` is specified, all human status prints are suppressed, outputting only clean, machine-readable JSON data:
```bash
bin/griffintts --json --native --ow native_test.wav "Validating agent-mode."
```

---

## Troubleshooting & Container Management

Since the synthesizer runs as a daemon inside a background container, you can manage it using standard `container` commands on your Mac:

- **Check Container Status**:
  ```bash
  container ls
  ```
- **Fetch Daemon Logs**:
  ```bash
  container logs tts_run
  ```
- **Manually Restart/Rebuild**:
  If you need to force-rebuild the container environment:
  ```bash
  container rm -f tts_run
  container build -t griffintts -f tools/griffintts/Containerfile tools/griffintts/
  ```

---

## Technical Details

For detailed reverse-engineering findings, dynamic library dependency maps, and explanations of how we intercepted ALSA using virtual configuration files, see:
- **[Griffin TTS Technical Architecture & Findings](docs/architecture.md)**
- **[Subsystem Guide: Griffin TTS](../../docs/subsystems/griffin-tts.md)**
