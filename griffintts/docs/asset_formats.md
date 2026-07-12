# Griffin Voice Asset File Formats

The extracted voice bundle (`assets/en_us_world/`, `assets/en_us/` — both
gitignored, pulled from a live unit per `README.md`'s "Voice Assets"
section) contains several distinct file formats. This doc explains each
one and how it fits into the synthesis pipeline, and specifically how
dictionary lookup relates to ESML markup (they're two independent
pronunciation-control mechanisms — see §7).

---

## 1. `.dictionary` / `.dictionary_full` / `.dictionary_trimmed` — the pronunciation lexicon

Pipe-delimited, one entry per line:

```
pizza | NN | 1 p ii t | 0 s ah
```

Fields, left to right:

1. **The word**, lowercased at lookup time.
2. **A part-of-speech tag** (Penn Treebank style: `NN`=noun, `JJ`=adjective,
   `VB`/`VBP`=verb forms, etc.) — or the literal placeholder `NANVAL` when
   no POS distinction applies (symbols, foreign letters, function words).
   This field is **optional**: some lines have only two pipe-delimited
   fields (`word | phonemes`) with no POS tag at all — both forms coexist
   in the same file, and `griffintts`'s own `parseDictionary()` detects
   which form it's looking at by checking whether field 2 contains a
   digit (a POS tag never does; a syllable field always starts with one).
3. **One field per syllable**, each formatted as `<stress> <phoneme>
   <phoneme> ...` — stress is `0` (none), `1` (primary), or `2`
   (secondary); phonemes use the Combilex/ARPABET-derived set.

Decoding the example: `pizza` → syllable 1 `1 p ii t` (primary stress,
"p-ii-t") + syllable 2 `0 s ah` (unstressed, "s-ah") → **PEET-sah**.

**The POS field's actual job — disambiguating heteronyms.** The same
spelling can appear multiple times with different POS tags and different
pronunciations:

```
record | JJ  | 1 r e | 0 k ah r d      (adjective/noun: REH-kərd)
record | NN  | 1 r e | 0 k ah r d      (noun: REH-kərd)
record | VBP | 0 r iy | 1 k o r d      (verb: ri-KORD)
record | VB  | 0 r iy | 1 k o r d      (verb: ri-KORD)
```

Multi-syllable words work the same way, one field per syllable:

```
computer | NN | 0 k ah m | 1 p j u | 0 dt ah r    → kəm-PYU-tər
```

This means correctly resolving `record`'s pronunciation requires knowing
*which* grammatical role it plays in the sentence — the frontend must be
running some form of POS tagging on the input text before dictionary
lookup, using `.pos` (§3) as (at least part of) that tagger's data.

**Three variants, one actually used**: `.dictionary` (46K lines),
`.dictionary_full` (198K lines), `.dictionary_trimmed` (50K lines).
Confirmed via `strings` on the real `libJiboTTSService.so`: the binary's
string table contains the literal suffix `.dictionary`, but **no**
occurrence of `.dictionary_full` or `.dictionary_trimmed` anywhere. The
daemon's config only specifies a directory (`resourcePath`), not a
filename — the `.dictionary` suffix is compiled into the binary itself.
`_full` and `_trimmed` are very likely build-time artifacts (a complete
Combilex export, and a size-optimization experiment, respectively) rather
than anything the shipped daemon actually reads at runtime.

---

## 2. `.phones` — phoneme articulatory features

Plaintext, self-documenting (the file has its own header comment). Each
phone gets one feature row, 9 space-separated columns:

```
PHONE VOWELORCONSONANT VOWELLENGTH VOWELHEIGHT VOWELFRONTNESS VOWELROUNDEDNESS VOWELRHOTICITY CONSONANTTYPE CONSONANTPLACEOFARTICULATION VOICING
```

| Column | Values |
|---|---|
| VowelOrConsonant | `V`owel, `C`onsonant, `XX` pause/n-a |
| VowelLength | `S`hort, `L`ong, `D`iphthong, `C` (n-a, consonant), `XX` |
| VowelHeight | `H`igh, `MH` mid-high, `M`id, `ML` mid-low, `L`ow, `C`, `MO` moving, `XX` |
| VowelFrontness | `F`ront, `M`id, `B`ack, `C`, `MO` moving, `XX` |
| VowelRoundedness | `R`ounded, `U`nrounded, `C`, `XX` |
| VowelRhoticity | `R`hotic, `N`on-rhotic, `C`, `XX` |
| ConsonantType | `S`top, `T`ap, `F`ricative, `AF`fricative, `N`asal, `L`iquid, `AP`proximant, `V`owel, `XX` |
| ConsonantPlaceOfArticulation | `LA`bial, `A`lveolar, `P`alatal, `LD` labio-dental, `D`ental, `LAT` lateral, `VE`lar, `G`lottal, `VO`wel, `XX` |
| Voicing | `V`oiced, `U`nvoiced |

Example rows (note: phone names are **uppercase** here, vs. lowercase in
the dictionary — matching is case-insensitive):

```
II V L H F U N V VO V        # FLEECE vowel ("ee") — vowel, long, high, front, unrounded, non-rhotic, voiced
P  C C C C C C S LA U        # /p/ — consonant, stop, labial, unvoiced
LPAU XX XX XX XX XX XX XX XX XX   # pause token — every field is "out of scope"
```

These 9 features are what `griffintts`'s own `generateLabels()` (and the
real daemon's HTS full-context label builder) uses to fill the `PLLVC`,
`PLLVL`, `PLLVH`... columns for each phone in a ±2-phone context window.

---

## 3. `.pos` — word-to-POS-tag lookup

Plaintext, two space-separated columns:

```
'Em NNP
'Oh NNP
```

Word (or symbol/contraction) on the left, its Penn Treebank POS tag on
the right. This is (at least part of) the frontend's source for tagging
words in context — the mechanism the dictionary's per-POS pronunciation
variants (§1) depend on to pick the right entry for a heteronym like
`record`.

---

## 4. `.g2p` — grapheme-to-phoneme fallback

**Not plaintext** — a compiled **OpenFST binary** (confirmed via its
`vector`/`standard` header strings and symbol-table structure, the same
binary FST format used by `textnorm/`'s files). This is the fallback
predictor used when a word isn't found in the dictionary at all: a
weighted finite-state transducer statistically predicts a phoneme
sequence from spelling alone. `griffintts`'s own `--native` path doesn't
reimplement this — it falls back to letter-spelling instead (see the
`main.go` `phonetizeText` fail-safe), which is a simplification, not a
faithful reproduction of what the real G2P transducer would predict.

---

## 5. `.contexts` — the HTS label schema

Plaintext, self-documenting. Lists the ordered field names that make up
each phone's full-context label string:

```
# Phone contexts +/- 2 phones
PLLI
PLI
PCI
PRI
PRRI
# Phone position in syll/word/phrase
PSFW
PSBW
...
```

This is the canonical schema — `griffintts`'s `generateLabels()` was
reverse-engineered to produce exactly this field set and order
independently; this file is the primary-source confirmation of that
reverse-engineering, not something the reimplementation reads directly.

---

## 6. `.config` — per-voice synthesis parameters

Plaintext, self-documenting `key = value` pairs:

```
durStretch = 1.0
pitchAddHalfTone = 3.0
pitchVarianceMod = 1.15
mgcVarianceMod = 1.35
bapVarianceMod = 1.2
engineAlpha = 0.76
charLimit = 600
enginePostFilterGain = 0.4
enginePostFilterCoeff = 1.1
```

Worth noting since it's easy to miss: **`en_us_world.config` bakes in a
+3 semitone pitch offset and elevated pitch/mgc variance modifiers by
default** — this is a baseline shift applied to *every* utterance
regardless of markup, separate from and prior to anything an ESML
`<pitch>` tag adds on top (see §7). This is very likely part of why
Griffin's "neutral" style already sounds more animated than a flat
baseline HTS voice would. These same knobs are also exposed at the
service level in `jibo-tts-service.json`'s `voiceParams` block under
abbreviated key names (`postFilter_b`, `halftone_fm`, `allPass_a`,
`gvMCEP_jm`) — same parameters, two different config surfaces.

---

## 7. How this all relates to ESML markup

Dictionary lookup and ESML markup are **two independent, non-overlapping
pronunciation-control mechanisms** that operate at different stages:

```
raw prompt text
  → MarkupHandler identifies <style>/<pitch>/<duration>/<break>/
    <phoneme>/<say-as> spans (Channel 1 audio-affect tags — see
    prosody_and_affect.md)
  → for each plain-text span NOT wrapped in <phoneme>:
      → OpenFST text normalization (dates, currency, ordinals)
      → dictionary lookup (§1, POS-disambiguated) or G2P fallback (§4)
        if the word isn't found
      → phoneme sequence with lexical stress markers
  → for each <phoneme ph="..."> span: the tag's phoneme string is used
    DIRECTLY, bypassing dictionary lookup and G2P entirely for that word
  → HTS full-context labels built from the phoneme sequence using
    .phones' features (§2) in .contexts' schema order (§5)
  → acoustic model (.voice) + .config's baseline parameters (§6)
  → <style>/<pitch>/<duration> tags apply their modifications on top of
    whatever the acoustic model + .config baseline already produced
  → WORLD vocoder → audio
```

Two practical consequences:

- **`<phoneme>` is the override valve for dictionary/G2P mispronunciations.**
  If a word is in the dictionary with a wrong or missing pronunciation (or
  isn't in the dictionary at all and G2P guesses wrong), `<phoneme
  ph="...">word</phoneme>` sidesteps both entirely for that one word in
  that one utterance — this is the ESML-side complement to editing the
  dictionary file itself (which is global and persistent, but requires
  on-device access; see `docs/FAQ.md`'s "Can Griffin's pronunciation
  dictionary actually be edited on-device" entry).
- **`<pitch>`/`<duration>` stack on top of `.config`'s baseline, not
  replace it.** A `<pitch halftone="+5">` tag adds 5 semitones on top of
  whatever `en_us_world.config`'s own `pitchAddHalfTone = 3.0` baseline
  already contributes — the two aren't in tension, they compose.

---

## Cross-references

- `docs/architecture.md` — the `.voice` acoustic model format (HTS
  version header, `STREAM_TYPE:MCP,LF0,BAP,LPF`) and `textnorm/`'s
  OpenFST text-normalization rules, both out of this doc's scope.
- `docs/prosody_and_affect.md` — the full ESML markup dialect (styles,
  pitch, duration, break, phoneme, say-as), empirically measured.
- `docs/FAQ.md` — on-device editability, the read-only-partition
  constraint, and the `.dictionary` vs. `.dictionary_full` finding in Q&A
  form.
