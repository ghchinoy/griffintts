# Jibo Griffin TTS SwiftUI Desktop Application

A gorgeous, highly interactive macOS desktop application featuring Jibo's iconic animated, blinking vector eye. It provides a visual frontend for Jibo's local speech synthesis, syncing Jibo's facial expressions with the generated audio in real-time.

---

## Features

### 1. Interactive Visual Bezel Layout
*   **Procedural Vector Jibo Eye**: Jibo's eye is rendered using pure, high-performance SwiftUI vector shapes and glows with Jibo's signature blue diffuse light aura.
*   **Proactive Cursor-Hover Pupil Tracking**: The pupil and glint reflections calculate coordinate offsets relative to your mouse pointer, **proactively tracking and following your cursor around the window!**
*   **Natural Random Blinking**: A background timer runs on a loop, executing a realistic blink sequence ( eyelids scale-squashing on the Y-axis) at random intervals every 3-5 seconds.

### 2. High-Precision Speech-Syllable Sync
*   **CoreAudio Phase-Locking**: Syncing is locked directly to `AVAudioPlayer.currentTime` (representing the physical audio playback head currently rendered by the speaker). This eliminates all filesystem read lag and CoreAudio device/hardware startup buffering latency.
*   **Initial Silence Offset Compensation**: Jibo's emulated C++ engine synthesizes a `350ms` starting pause (`LPAU` silence) at the front of each WAV file, whereas the token timings are relative to the first spoken word. We subtract `350ms` from the player's `currentTime` to ensure Jibo's eye-pulse and wiggling start in **perfect, phase-locked lock-step with the sound waves!**
*   **Procedural Fallback**: If timings are unavailable (e.g. in native fallback mode), the app activates a beautiful, organic procedural vocal wiggler (using sine/cosine waves) to simulate natural Jibo-style mouth-syncing.

### 3. Sane Subprocess Coordination & Fallbacks
*   **Unified Go CLI Backend**: The SwiftUI app runs our compiled `tools/bin/griffintts` binary as a background `Process`. This ensures Jibo's Go utility handles all container checks, ALSA-file-redirection seeks, and PCM-to-WAV conversions.
*   **Dual-Mode Toggle**: Check the **"Standalone Native Mode"** box to bypass the emulated container and run standard native HTS synthesis locally on macOS in under 50ms.

---

## Setup & Compilation

The application targets **macOS Sonoma (.macOS(.v14))** or newer to support modern continuous cursor tracking, and compiles natively using Apple's Swift toolchain.

Build the application from the root directory:
```bash
make griffintts-ui
```
This compiles the Swift package using the optimized production Release configuration and saves the standalone binary directly to **`./tools/bin/griffintts-ui`**.

---

## Usage & Keyboard Focus

Launch the compiled desktop application from your terminal:
```bash
./tools/bin/griffintts-ui
```

### Keyboard Focus & Standalone Integration
To enable typing, our code leverages standard macOS `AppKit` delegation to automatically elevate the terminal subprocess's activation policy to a regular foreground GUI app:
```swift
NSApp.setActivationPolicy(.regular)
NSApp.activate(ignoringOtherApps: true)
```
-   **Click to Type**: Simply click Jibo's dark status bar to focus the prompt text field, type your custom sentences, and press **Enter** to speak!
-   **Dock & App Switcher**: The app appears directly inside your macOS Dock and your standard `Cmd + Tab` App Switcher.

---

## High-Resolution Diagnostics Console Logs

When run from the terminal, the application prints detailed, millisecond-precision logs of the entire synthesis-to-playback timeline:
```text
[2026-07-04 13:59:23.700] [GriffinUI] --- NEW SYNTHESIS RUN TRIGGERED ---
[2026-07-04 13:59:23.710] [GriffinUI] [Timing] Launching parallel fetchTokenTimings task...
[2026-07-04 13:59:23.715] [GriffinUI] [Subprocess] Spawning Go CLI subprocess...
[2026-07-04 13:59:25.610] [GriffinUI] [Subprocess] Go CLI subprocess completed. Success status: true
[2026-07-04 13:59:25.611] [GriffinUI] [Timing] timingsFetch resolved. Fetched 9 tokens.
[2026-07-04 13:59:25.612] [GriffinUI] [Audio] Loading AVAudioPlayer...
[2026-07-04 13:59:25.655] [GriffinUI] [Audio] AVAudioPlayer prepared to play.
[2026-07-04 13:59:25.740] [GriffinUI] [Audio] audioPlayer.play() executed successfully.
[2026-07-04 13:59:25.761] [GriffinUI] [Animation] First active tick of Token-Based animation.
[2026-07-04 13:59:33.881] [GriffinUI] [Animation] Animation completed. Timer invalidated.
```
These logs are highly useful for inspecting audio device latency and ensuring perfect, sub-second coordination.
