# Jibo Griffin TTS CLI Utility

A high-fidelity local CLI speech synthesizer wrapping Jibo's original 2017 "Griffin" voice. 

By leveraging user-mode ARM emulation inside a native macOS container machine, this utility executes Jibo's full text normalization frontend (OpenFST, Combilex lexicon, G2P) and high-fidelity WORLD vocoder acoustic synthesizer offline on macOS.

---

## Prerequisites

To use this utility, ensure you have the following installed on your host Mac:
1. **FFmpeg**: Required on the host to convert raw PCM output to standard WAV format.
2. **Apple Container Platform** (Optional for native mode, required for container mode): The Swift-based container system (`container`).

Both dependencies are pre-verified as available and fully functional in this repository environment.

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

### 1. Standalone Native macOS Mode (Recommended Zero-Dependency)
By loading Jibo's classic `en_us` 3-stream voice model (using standard `MCP,LF0,LPF` streams), `griffintts` can synthesize Jibo's voice **natively on macOS without any containers, virtual machines, or QEMU emulators**!

To run natively, simply append the `--native` (or `-n`) flag:
```bash
bin/griffintts --native --ow native_output.wav "Hello! Synthesized 100% natively on macOS."
```

### 2. Emulated Container Mode (WORLD Vocoder)
Runs Jibo's original 32-bit ARM Linux binary under emulation inside a local container machine. On its **first run**, this mode will automatically configure, build, and start the underlying background container `tts_run` from the local `Containerfile` to expose Jibo's HTTP endpoints.

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
