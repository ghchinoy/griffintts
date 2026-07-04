# Griffin TTS Local Synthesis: Technical Architecture & Findings

This document records the reverse-engineering discoveries, technical barriers, and solutions implemented to bring Jibo's original 2017 "Griffin" text-to-speech voice to life locally on macOS.

---

## Technical Discoveries on the Live Jibo Unit

Through direct filesystem inspection, library symbol analysis, and log interception on the active robot (`root@mars-bond-mesquite-cotton.local`), we made several crucial architectural findings:

### 1. Acoustic Model & Streams
- The model file `/usr/local/share/ttsservice/voices/en_us_world/en_us_world.voice` (27.6MB) uses the standard **HTS (HMM-based Speech Synthesis System) Engine API version 1.0** header.
- The voice config defines 4 synthesis streams: `STREAM_TYPE:MCP,LF0,BAP,LPF`.
  - **`MCP`** (Mel-cepstral parameters, vector length 60) represents spectral characteristics.
  - **`LF0`** (Log F0 pitch, vector length 1) represents fundamental frequency / excitation.
  - **`BAP`** (Band-Aperiodicity, vector length 5) and **`LPF`** (Low-Pass Filter, vector length 16) are specific to the high-fidelity **WORLD vocoder** backend. WORLD uses these streams to model high-quality mixed-excitation, which gives Jibo's voice its unique character and removes "buzzy" synthetic artifacts.

### 2. In-Memory Label Synthesis
Analyzing the exported symbols of Jibo's `libJiboTTSService.so` shared library revealed several key C++ methods:
```text
jibo::tts::TextEngine::getContextHandler()
jibo::tts::TextEngine::getFullContextLabels(std::string*)
jibo::tts::ContextHandler::makeFullContextLabels(jibo::tts::Phrase*, ...)
Jibo_HTS_Label_load_from_strings
Jibo_HTS_Engine_generate_sample_sequence
```
- **Discovery**: Jibo's C++ frontend normalizes raw text through OpenFST rules and a Combilex dictionary directly in memory, producing standard HTS pipe-separated full-context label strings (e.g. `PLLI:<phone>|PLI:<phone>|PCI:-<phone>+|...`).
- Instead of writing `.lab` files to disk and reading them back, it loads these strings directly into the HTS engine using the custom `Jibo_HTS_Label_load_from_strings` entry point, ensuring high-speed, completely in-memory synthesis on Jibo's Tegra K1 processor.

---

## Technical Challenges & Solutions (Mac Port)

To port this pipeline to macOS, we evaluated two distinct execution strategies:

### Challenge A: Native Compilation & The 3-Stream Fallback Victory (Path A)
We successfully cloned and natively compiled Nagoya's standard `hts_engine_API` on macOS using CMake. However, loading Jibo's modern `en_us_world.voice` initially failed with:
`Error: HTS_GStreamSet_create: The number of streams should be 2 or 3.`

- **Root Cause**: The standard open-source Nagoya HTS Engine only supports standard HTS MLSA/MGE vocoder backends, which expect 2 or 3 streams (Spectrum, F0, and optional simple filter). It hard-restricts stream counts in `HTS_gstream.c`. It has no native support for Jibo's high-fidelity WORLD-vocoder-specific 4-stream configuration (`MCP`, `LF0`, `BAP`, `LPF`).
- **The 3-Stream Fallback Victory**: 
  While analyzing Jibo's extracted assets, we discovered an alternative, older voice model:
  **`/usr/local/share/ttsservice/voices/en_us/en_us.voice`**
  Unlike the newer `en_us_world.voice` model, the classic `en_us.voice` uses **exactly 3 streams** (`MCP`, `LF0`, `LPF`) using standard HTS MLSA filtering with low-pass filters.
  
  By writing a custom, dynamic full-context label generator directly inside our Go CLI utility, we achieved **100% native macOS standalone speech synthesis (`griffintts --native`)** of Jibo's authentic voice with **zero container, emulation, or virtualization dependencies**! It generates standard HTS-compliant, pipe-separated context labels dynamically in-memory, writes a temporary `.lab` file, and compiles it via the native `hts_engine` binary in less than 50 milliseconds!
- **Path B WORLD Support**: Rather than embarking on a massive academic-level DSP porting effort to merge the WORLD vocoder library into the native C `hts_engine_API` build to support the newer 4-stream voice, we successfully prioritized the emulation-based Path B as our primary WORLD-vocoder backend.

### Challenge B: Emulation & Audio Interception (Path B)
Jibo's `jibo-tts-service` daemon is a 32-bit ARM (armv7) Linux ELF binary, which cannot run natively on macOS's Darwin kernel.

- **Solution**: We leveraged Apple's high-performance virtualization-based container manager `container` to spin up a 64-bit ARM Linux (`aarch64` Ubuntu Focal) container. Under 64-bit Linux on Apple Silicon, 32-bit ARM user-mode emulation is natively and cleanly handled via `qemu-arm` and the `libc6:armhf` package.

#### 1. Dynamic Library Dependency Resolution
We extracted and bundled Jibo's custom shared libraries (`libJiboTTSService.so`, `libfst.so.3`) into `/app/assets/lib/`. Additionally, Jibo's compiled binary links older system-level libraries like `libpcre.so.1`, `libexpat.so.1`, and `libz.so.1` which are missing from modern Ubuntu package registries. We extracted these exact system libraries directly from Jibo's filesystem and mapped them into the container's guest `LD_LIBRARY_PATH`.

#### 2. C++ Runtime Locales
On startup, Jibo's Poco C++ framework threw a runtime locale exception:
`locale::facet::_S_create_c_locale name not valid`
We solved this by explicitly generating the standard `en_US.UTF-8` locale inside our Ubuntu-based `Containerfile` and setting the environment variables `LANG` and `LC_ALL`.

#### 3. Bypassing Hardcoded Paths via Symlinks
Jibo's binary and shared libraries contain compiled-in absolute filesystem paths such as `/usr/local/share/ttsservice/voices/en_us_world/`. Rather than modifying Jibo's binary or custom configuration files, we created matching directory structures and symbolic links inside the container pointing directly to our workspace, resolving all hardcoded paths transparently.

#### 4. The ALSA "TTSOut" Intercept Plugin
The most critical system challenge was audio redirection. Ordinarily, `libJiboTTSService.so` is hardcoded to open a specific physical ALSA device named `"TTSOut"` (discovered by grepping binary strings inside the compiled C++ shared library):
`tools/griffintts/assets/lib/libJiboTTSService.so: ... PulseExtern. TTSOut ...`

To capture this audio without writing complex dynamic link overrides or `LD_PRELOAD` interception libraries, we utilized a built-in, 100% robust feature of ALSA itself—the **ALSA file redirection plugin**.

By writing a custom `.asoundrc` configuration inside the container's `/root` directory, we mapped a virtual device named `"TTSOut"` that transparently intercepts Jibo's playback calls, discards real hardware sound card bindings, and writes the raw 16-bit 48kHz mono PCM stream directly to a file:
```text
pcm.TTSOut {
    type file
    slave {
        pcm null
    }
    file "/app/output.raw"
    format "raw"
}
```
This is fully transparent to Jibo's binary and guarantees perfect, click-free audio capture under virtualization.
