# Jibo Griffin TTS CLI Utility

A high-fidelity local CLI speech synthesizer wrapping Jibo's original 2017 "Griffin" voice. 

By leveraging user-mode ARM emulation inside a native macOS container machine, this utility executes Jibo's full text normalization frontend (OpenFST, Combilex lexicon, G2P) and high-fidelity WORLD vocoder acoustic synthesizer offline on macOS.

**Scope**: this is a text-to-speech (TTS) engine only. It takes text (or ESML
markup) as input and produces spoken audio. It has no involvement in
understanding spoken language, classifying intent, or deciding what a
command means — that's natural language understanding (NLU), an entirely
separate subsystem on Jibo's original stack with no relationship to this
tool. If you're looking for how Jibo decides *what you asked for*, this
repo isn't it.

---

## Prerequisites

### 1. Voice Assets (required — must be pulled from a live Jibo unit)

The `assets/` directory is **gitignored** and must be populated by extracting files directly from a live Jibo robot over SSH before anything here will work. Both synthesis modes depend on it:

| Mode | Assets required |
|---|---|
| Container (primary) | `assets/en_us_world/`, `assets/bin/jibo-tts-service`, `assets/lib/*.so`, `assets/jibo-tts-service.json` |
| Native (`--native`) | `assets/en_us/en_us.voice`, `assets/en_us/en_us.dictionary_full`, `assets/en_us/en_us.phones` |

To extract from a live unit (replace `mars-bond-mesquite-cotton.local` with your unit's mDNS hostname):
```bash
# Voice model bundles
scp -r root@mars-bond-mesquite-cotton.local:/usr/local/share/ttsservice/voices/en_us_world assets/
scp -r root@mars-bond-mesquite-cotton.local:/usr/local/share/ttsservice/voices/en_us      assets/

# Jibo TTS service binary and config
mkdir -p assets/bin assets/lib
scp root@mars-bond-mesquite-cotton.local:/usr/local/bin/jibo-tts-service         assets/bin/
scp root@mars-bond-mesquite-cotton.local:/usr/local/etc/jibo-tts-service.json    assets/

# Dynamic library dependencies (required for the container)
ssh root@mars-bond-mesquite-cotton.local \
  "tar -czf - -C /usr/local/lib libJiboTTSService.so libJiboServiceFramework.so libJiboUtil.so && \
   tar -czf - -C /usr/lib libfst.so.3 libfst.so.3.0.0 libv8_base.so libv8_libbase.so \
             libv8_libplatform.so libv8_nosnapshot.so libv8_snapshot.so \
             libPocoFoundation.so.48 libPocoJSON.so.48 libPocoUtil.so.48 \
             libPocoXML.so.48 libPocoNet.so.48 libPocoNetSSL.so.48 libPocoCrypto.so.48 \
             libpcre.so.1 libexpat.so.1 libz.so.1" \
  | tar -xzf - -C assets/lib/
```

The full extraction process and rationale for each file is documented in [`docs/architecture.md`](docs/architecture.md).

### 2. `hts_engine_API` (required for `--native` mode only)

The `--native` synthesis path shells out to a natively-compiled `hts_engine` binary. It isn't vendored in this repo, it's a nested third-party project with its own build system, so clone and build it yourself:

```bash
git clone https://github.com/r9y9/hts_engine_API.git hts_engine_API
cd hts_engine_API/src
mkdir -p build && cd build
cmake ..
make
```

This should produce `hts_engine_API/src/build/bin/hts_engine`, which is exactly where `griffintts --native` looks for it. `hts_engine_API/` is gitignored; container mode (the default, high-fidelity path) doesn't need this at all.

### 3. Host Tools

Ensure the following are installed on your Mac:
- **FFmpeg** — converts raw PCM output to WAV (`brew install ffmpeg`)
- **Apple Container Platform** — required for container mode (primary high-fidelity voice); optional for `--native` mode
- **CMake** — only needed to build `hts_engine_API` above, for `--native` mode (`brew install cmake`)

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
  -m, --markup        Treat input as affective markup (audio tags: style, pitch, duration, break,
                      phoneme, say-as). Animation tags (anim, ssa, es) are stripped with a warning.
                      Container mode only.
  -n, --native        Use the 100% native macOS HTS standalone synthesizer (no containers)
  -o, --ow string     Path to save the synthesized WAV file (default "output.wav")
  -p, --port string   TTS container port (default "8089")
  -s, --speed float   Speaking speed multiplier (0.5 is slow, 2.0 is fast) (default 1.0)
```

### 1. Affective Markup (`--markup`)

Jibo's TTS daemon understands an XML-like markup dialect for audio affect. The `--markup` flag lets you author speech with real prosodic variation rendered by Jibo's own synthesis engine:

```bash
# Speaking style
bin/griffintts --markup '<style set="enthusiastic">Hello! Great to see you.</style>'

# Pitch adjustment
bin/griffintts --markup '<pitch halftone="-5">Speaking in a lower register.</pitch>'

# Real pause insertion
bin/griffintts --markup 'One moment.<break size="0.8"/>Here is your answer.'

# Phoneme override
bin/griffintts --markup '<phoneme ph="b aa n ou">Bono</phoneme> is a musician.'

# Spelling out
bin/griffintts --markup '<say-as spell="jibo"/> is my name.'

# Combined: animation tags are stripped, audio tags render
bin/griffintts --markup '<anim cat="happy" nonBlocking="true">Sure!</anim> <style set="confident">Here is what I found.</style>'
```

**Confirmed speaking styles**: `neutral`, `excited` (marginal), `confused`, `sheepish`, `confident`, `enthusiastic`, `news`

**Pitch subtypes**: `halftone`, `band`, `add`, `mult` — all produce measurable monotonic effects

**Duration tag semantics**: `<duration stretch="2.0">` makes speech *slower* (opposite of the `--speed` flag, which uses `duration_stretch` as an inverse-rate multiplier)

**Animation tags** (`<anim>`, `<ssa>`, `<es>`) are stripped — these require the robot's on-device animation system and cannot be rendered offline. Inner spoken text from bounded forms (e.g. `<anim cat="happy">Sure!</anim>`) is preserved.

**Native mode** (`--native --markup`): markup tags are stripped and only plain text is synthesized. The native HTS pipeline has no markup engine.

### 2. Shell Pipe / Stdin Support
You can pipe text directly into `griffintts` via standard input:
```bash
echo "Piped text is synthesized automatically." | bin/griffintts --native
```

### 3. AX (Agent Experience) Output
If `--json` is specified, all human status prints are suppressed, outputting only clean, machine-readable JSON data. In `--markup` mode the JSON output includes which animation tags were stripped:
```bash
bin/griffintts --json --native --ow native_test.wav "Validating agent-mode."
bin/griffintts --markup --json '<anim cat="happy"/> <style set="confident">Done.</style>'
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
  container build -t griffintts -f Containerfile .
  ```

---

## Technical Details

For detailed reverse-engineering findings, dynamic library dependency maps, and explanations of how we intercepted ALSA using virtual configuration files, see:
- **[Griffin TTS Technical Architecture & Findings](docs/architecture.md)**
- **[Prosody and Affect: what the `/tts_speak` API actually controls](docs/prosody_and_affect.md)**
