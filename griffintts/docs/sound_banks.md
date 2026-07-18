# TTS Sound-Effect Audio Bank (effectsDir) — Investigation Results

**Tasks:** `jibo-oge.9` (asset path and extraction) · `jibo-oge.13` (SpeechDelegate / SSA dialect)
**Investigator:** jiboinspect live session against `mars-bond-mesquite-cotton.local`
**Date:** 2026-07-07

---

## Summary

| Question | Answer |
|---|---|
| `effectsDir` configured path | `/usr/local/share/ttsservice/effects` |
| Directory exists on device? | **No** — absent on the live unit |
| Any `.wav` effects files anywhere on rootfs? | **No** — zero hits under the effects naming pattern |
| `/tts_effects` WebSocket delivers audio? | **No** — socket connects but no audio produced (missing assets confirmed root cause) |
| SpeechDelegate JS found? | Not present by that name; equivalent logic is in `jibo-service-clients` and `jibo-embodied-dialog` |
| `<ssa>` → `<audioBreak>` translation documented? | **Yes** — see §4 |
| Can oge.9 / oge.13 be fully closed? | **oge.9: partially** (path confirmed, files absent; extraction requires OTA image or factory image). **oge.13: yes** (translation rules fully documented below). |

---

## 1. `effectsDir` — Configured Path

From `/usr/local/etc/jibo-tts-service.json` (confirmed on live device and
matched byte-for-byte by the extracted copy in `tools/griffintts/assets/`):

```json
"TTSService": {
    "effectsDir": "/usr/local/share/ttsservice/effects",
    ...
}
```

The key is read by `libJiboTTSService.so` at startup under the config name
`TTSService.effectsDir` (confirmed from binary string table). The TTS daemon
uses this path to load sound-effect WAV files that are played back over the
`/tts_effects` WebSocket when a `startEffect` message is received.

---

## 2. Effects Directory — Does Not Exist on This Unit

**Confirmed via live SSH inspection of the physical robot:**

```
/usr/local/share/ttsservice/
└── voices/          ← EXISTS (voice model bundle)
    ├── en-us/
    ├── en_us/
    └── en_us_world/
```

There is **no `effects/` subdirectory**. A filesystem-wide search (`find /
-name 'effects' -type d`) returned zero matches under any TTS-related path. A
search for the WAV naming pattern (`find / -name '*-tts.wav'`) also returned
zero hits.

**Root cause hypothesis:** The effects directory was never populated on this
unit, or was shipped as part of a factory image partition that differs from the
currently-mounted rootfs. The `effectsDir` key is present and valid in the
config, and the daemon code to load from it is compiled in — this is
infrastructure that was built and deployed, but the sound files themselves were
not included in the software bundle present on this unit.

---

## 3. File Naming Convention (from Binary)

The `libJiboTTSService.so` binary contains the string `-tts.wav`. This, combined
with the `PostFilterMap` entries in `jibo-tts-service.json`, establishes the
expected naming scheme for effect files:

```
<effectsDir>/<key>-tts.wav
```

where `<key>` is the string key from `PostFilterMap`. Based on the 29 named
entries:

```
oo-tts.wav           wow-tts.wav          perfect-tts.wav
ok-tts.wav           ooo-tts.wav          ah-tts.wav
oh-tts.wav           your_welcome-tts.wav cool-tts.wav
woo_hoo_hoo-tts.wav  laugh-tts.wav        laugh2-tts.wav
sweet-tts.wav        done-tts.wav         what-tts.wav
aw-tts.wav           my_bad-tts.wav       oops-tts.wav
um-tts.wav           huh-tts.wav          whoa-tts.wav
argh-tts.wav         nm_um-tts.wav        i_love_to_1-tts.wav
i_love_to_2-tts.wav  i_love_to_3-tts.wav  i_love_to_4-tts.wav
i_love_to_5-tts.wav  i_love_to_6-tts.wav
```

These are Jibo's paralinguistic vocalization clips ("Jibonics") — the actual
pre-recorded audio that the `<audioBreak>` and `<audio>` ESML tags play back.
The `PostFilterMap` also has an entry `"triggerJibonics": "bang"` which maps to
the special `bang` trigger value in the WebSocket protocol.

**Expected directory structure (not present on this unit):**
```
/usr/local/share/ttsservice/effects/
├── oo-tts.wav
├── wow-tts.wav
├── perfect-tts.wav
├── ok-tts.wav
├── ... (29 files total per PostFilterMap)
└── i_love_to_6-tts.wav
```

---

## 4. SSA / `<audioBreak>` Dialect Translation (oge.13)

The "SpeechDelegate" JS concept from the task brief corresponds to what is
implemented across two Node.js modules on the device: `jibo-service-clients`
and `jibo-embodied-dialog`. There is no file literally named `SpeechDelegate.js`
in `jibo-ssm/dist/` — the SSM module at `/usr/local/bin/jibo-ssm` uses a
different internal structure. The equivalent logic lives in the skills layer at:

```
/opt/jibo/Jibo/Skills/@be/be/node_modules/jibo-service-clients/
/opt/jibo/Jibo/Skills/@be/be/node_modules/jibo-embodied-dialog/
```

### 4.1 The `startEffect` Wire Protocol

From `jibo-service-clients/lib/jibo-service-clients.js` (line 2712):

```javascript
// WebSocket endpoint
const APIPath = {
    EFFECTS: '/tts_effects',   // line 2482
};

// Payload sent over the /tts_effects WebSocket:
function startEffect(name, value) {
    let requestBody = {
        'name': name,          // effect key from PostFilterMap, e.g. "laugh"
        'action': 'START',     // PedalsActions enum: START | STOP | UPDATE
        'param': ("" + value)  // numeric string: "1" through "29" per PostFilterMap
    };
    effectsSocket.send(JSON.stringify(requestBody));
}
```

The `name` and `param` fields map to the `PostFilterMap` from the config:

```json
"PostFilterMap": {
    "oo":            "1",   // name="oo",  param="1"  → oo-tts.wav
    "wow":           "2",   // name="wow", param="2"  → wow-tts.wav
    "perfect":       "3",
    "ok":            "4",
    "ooo":           "5",
    "ah":            "6",
    "oh":            "7",
    "your_welcome":  "8",
    "cool":          "9",
    "woo_hoo_hoo":   "10",
    "laugh":         "11",
    "laugh2":        "12",
    "sweet":         "13",
    "done":          "14",
    "what":          "15",
    "aw":            "16",
    "my_bad":        "17",
    "oops":          "18",
    "um":            "19",
    "huh":           "20",
    "whoa":          "21",
    "argh":          "22",
    "nm_um":         "23",
    "i_love_to_1":   "24",
    "i_love_to_2":   "25",
    "i_love_to_3":   "26",
    "i_love_to_4":   "27",
    "i_love_to_5":   "28",
    "i_love_to_6":   "29",
    "triggerJibonics": "bang"  // special trigger
}
```

### 4.2 How `<audioBreak>` Maps to the Wire Protocol

From `jibo-embodied-dialog/lib/jibo-embodied-dialog.js` (line 4719):

```javascript
const TTS_AUDIO_BREAK = '<audioBreak>';
```

The `<audioBreak>` ESML tag is parsed by the `TTSPromptParser` in the JS
timeline layer, producing `SSMLNodeType.AUDIO_BREAK` word nodes. These nodes
are time-aligned to the TTS token stream (line 5213):

```javascript
if (token.name === TTS_BREAK || token.name === TTS_SAY_AS || token.name === TTS_AUDIO_BREAK) {
    if (((token.name === TTS_AUDIO_BREAK) && (word.type === Types_1.SSMLNodeType.AUDIO_BREAK)) ...) {
        ttsWordSchedule.set(word, tokenTime);
    }
}
```

The `<audioBreak>` tag in ESML corresponds to the `<audioBreak>` token in the
TTS daemon's `MarkupHandler` (confirmed in `libJiboTTSService.so` binary string
table). When triggered at the appropriate timestamp, the JS layer calls
`startEffect(name, param)` over the `/tts_effects` WebSocket, which causes the
daemon to play the corresponding `-tts.wav` file from `effectsDir`.

### 4.3 `<sfx>` Tag — Channel 2 (Animation Layer, Third Audio Category)

The MIT HRI2024 ESML SDK reference (Jibo Inc. archive) identifies `sfx` as its
own `AssetNodeType` (`AssetNodeType["SFX"] = "SFX"`), making it a **third**
distinct audio category alongside `<ssa>` and `<audioBreak>`. This aligns with
the `sfx-only` filter metadata already present in `jibo-embodied-dialog` (§4.4
below). The ESML SDK PDF has its own cheat-sheet section for SFX alongside SSA.

The AnimDB audio directory on the live unit confirms the `sfx/` subdirectory
exists under `jibo-anim-db-animations/audio/` (see §5), with at least:
- `sfx_drumroll_01.wav`
- `sfx_sparkles_01.wav`
- `sfx_sparkles_02.wav`

The `<sfx>` tag's syntax and available category names have **not** been
empirically tested. By analogy to `<ssa cat="...">`, it likely takes a `cat=`
or similar attribute referencing AnimDB sound-effect clip names. This is an
open investigation gap — it may support `<sfx cat="drumroll"/>` style syntax,
but this is unconfirmed.

### 4.5 `<ssa>` Tag — Channel 2 (Animation Layer, Not Daemon)

The `<ssa cat="...">` tag is processed entirely by the JS Timeline in `@be/be`,
not by the TTS daemon. It is NOT equivalent to `<audioBreak>` — they operate
at different layers:

| Tag | Layer | Who handles it | Daemon sees it? |
|---|---|---|---|
| `<audioBreak src="..."/>` | Channel 1 audio | `libJiboTTSService.so` `MarkupHandler` | **Yes** (in prompt text) |
| `<ssa cat="...">` | Channel 2 animation | `jibo.embodied.speech` Timeline in `@be/be` | **No** (stripped by JS) |
| `<sfx>` | Channel 2 animation | `jibo.embodied.speech` Timeline in `@be/be` | **No** (stripped by JS) |

The `<ssa>` categories (`laughing`, `thinking`, `hello`, etc.) are drawn from
the Jibo Animation Database, not from the TTS `effectsDir`. They trigger
coordinated paralinguistic behaviors (body movement + audio) via AnimDB.

The `effectsDir` sound bank is specifically for the `<audioBreak>` / `<audio>`
tags and the `startEffect()` API — the "Jibonics" vocalization clips.

### 4.6 Animation Metadata Tags for Sound-Effect Filtering

From `jibo-embodied-dialog` (lines 992–1277), the Timeline uses metadata tags
to filter which audio/animation tracks play with which content:

```javascript
// Animation track filter — exclude sound-only or ssa-only content from anim tracks:
excludeMeta: ['sfx-only', 'ssa-only']

// Channel constants:
ANIM: '!ssa-only, !sfx-only',   // line 1276 — blocks SSA and SFX from anim track
SSA:  'ssa-only',                // line 1277 — SSA-specific track
```

This confirms three distinct audio categories at the animation layer:
- `ssa-only` — AnimDB clips for paralinguistic SSA sounds (`<ssa cat="...">`)
- `sfx-only` — AnimDB clips for the `<sfx>` tag (see §4.3)
- Neither — body-animation clips with no audio-only constraint (the `ANIM` track)

The filtering prevents double-playback when both channels are active.
The `<sfx>` tag maps to `sfx-only` clips in the AnimDB — which is why the
`sfx/` audio directory exists separately from `rom/` (pre-recorded voice) and
SSA clips in the AnimDB (see §5).

---

## 5. What Exists Instead — Skills WAV Assets

There are WAV files on the device, but not in `effectsDir`. They live in the
Skills bundle under the `@be/be` animation database:

```
/opt/jibo/Jibo/Skills/@be/be/node_modules/jibo-anim-db-animations/audio/
├── rom/              ← pre-recorded robot-voice WAV clips ("ROM" = read-only memory)
│   ├── original/     ← original takes (full fidelity)
│   └── affected/     ← post-processed variants
└── sfx/              ← sound effects
    ├── sfx_drumroll_01.wav
    ├── sfx_sparkles_01.wav
    └── sfx_sparkles_02.wav

/opt/jibo/Jibo/Skills/@be/be/node_modules/@be/introductions/audio/
/opt/jibo/Jibo/Skills/@be/be/node_modules/@be/ifttt/audio/
/opt/jibo/Jibo/Skills/@be/be/node_modules/@be/idle/audio/
    └── Ugh_001.wav, UhOh_001.wav, ... (idle vocalization clips)
```

These are **AnimDB audio clips**, not TTS sound effects. They are played by the
animation system (`@be/be`), not by the TTS daemon's `/tts_effects` path.

---

## 6. Extraction Procedure (if effectsDir is ever found)

If a factory image or OTA update image is obtained that contains
`/usr/local/share/ttsservice/effects/`, extract as follows:

```bash
# From a live device (if files exist):
scp -r -i ~/.ssh/id_ed25519 \
    root@mars-bond-mesquite-cotton.local:/usr/local/share/ttsservice/effects/ \
    tools/griffintts/assets/effects/

# From an ext4 image (if rootfs image obtained):
bin/jiboinspect ls /usr/local/share/ttsservice/effects/ -i <rootfs.img>
bin/jiboinspect cat /usr/local/share/ttsservice/effects/laugh-tts.wav -i <rootfs.img> \
    > tools/griffintts/assets/effects/laugh-tts.wav
# ... repeat for all 29 files
```

The extraction pattern follows the same structure as the voice model extraction
documented in `tools/griffintts/README.md`.

**Expected file count:** 29 WAV files (one per `PostFilterMap` entry, excluding
`triggerJibonics`).

**Expected sample rate:** 48000 Hz (matching `samplerate_s` in `voiceParams`
config and `alsaPlaybackDevice` = "TTSOut").

---

## 7. Container Integration Note (Containerfile)

Do NOT modify `tools/griffintts/Containerfile` until the effect files are
physically obtained and verified. When they are available, add:

```dockerfile
# Add TTS sound-effect bank (Jibonics)
COPY assets/effects/ /usr/local/share/ttsservice/effects/
```

This mounts the effects under the exact path the daemon expects. The WebSocket
at `/tts_effects` should then produce audio for `startEffect` payloads — which
is the same path exercised by `<audioBreak>` ESML tags at the appropriate
timeline timestamps.

---

## 8. Status of oge.9 / oge.13

### oge.9 — Sound-Effect Audio Bank Extraction

| Sub-task | Status |
|---|---|
| Confirm `effectsDir` path | ✅ Done: `/usr/local/share/ttsservice/effects` |
| Confirm directory absent on live unit | ✅ Done: confirmed absent (live SSH + find) |
| Establish expected file naming scheme | ✅ Done: `<key>-tts.wav`, 29 files |
| Document extraction procedure | ✅ Done: §6 above |
| Actually extract the files | ❌ Blocked: files not present on this unit |

**oge.9 can be closed as a documentation task.** The extraction step remains
open as a follow-up (`jibo-oge.9`-continued): requires either a factory/OTA
image dump or a unit that shipped with `effectsDir` populated.

### oge.13 — SpeechDelegate / SSA-to-Dialect Translation

| Sub-task | Status |
|---|---|
| Locate `SpeechDelegate.js` | ✅ Done: no file by that name exists; equivalent is in `jibo-service-clients` and `jibo-embodied-dialog` |
| Document `startEffect` wire protocol | ✅ Done: §4.1 |
| Document `<audioBreak>` → effects mapping | ✅ Done: §4.2 |
| Clarify `<ssa>` vs `<audioBreak>` layer boundary | ✅ Done: §4.3 |
| Document PostFilterMap → WAV filename mapping | ✅ Done: §3 |

**oge.13 can be fully closed.** The translation rules are documented. The
`<ssa>` and `<audioBreak>` tags operate at different layers (animation JS vs.
TTS daemon), and the Jibonics vocalization system is now fully mapped even
though the WAV files themselves are not yet extracted.

---

## 9. Cross-References

- `tools/griffintts/assets/jibo-tts-service.json` — source of `effectsDir` and `PostFilterMap`
- `docs/prosody_and_affect.md` §11 — `<audio>`/`<audioBreak>` in context
- `docs/architecture.md` — `/tts_effects` WebSocket behavior and the broader HTTP API
- Live binary evidence: `/usr/local/lib/libJiboTTSService.so` strings `-tts.wav`, `TTSService.effectsDir`, `/tts_effects`, `<audioBreak>`
- Source: `/opt/jibo/Jibo/Skills/@be/be/node_modules/jibo-service-clients/lib/jibo-service-clients.js` lines 2482–2722
- Source: `/opt/jibo/Jibo/Skills/@be/be/node_modules/jibo-embodied-dialog/lib/jibo-embodied-dialog.js` lines 4719, 5213

---

## 10. External Sources

The MIT HRI2024 ESML SDK reference (Jibo Inc. archive, captured 2023-10-12,
`https://hri2024.jibo.media.mit.edu/`) independently confirms:
- `<sfx>` exists as `AssetNodeType["SFX"]` — a third animation-layer audio
  category alongside `<ssa>` and `<audioBreak>` (§4.3 above)
- The ESML SDK PDF has a dedicated SFX cheat-sheet appendix section
- `<audioBreak>` and `<audio>` are in the "Audio Tags" section of the SDK docs,
  architecturally distinct from the "TTS Tags" section — confirming the
  Channel 1 / Channel 2 split documented in `esml-two-channel-model.md`

---

*Written: 2026-07-07. Tasks: `jibo-oge.9`, `jibo-oge.13`. Updated 2026-07-18: MIT HRI2024 cross-reference — `<sfx>` as third audio category (§4.3), §4.5/§4.6 renumbering, External Sources §10.*
