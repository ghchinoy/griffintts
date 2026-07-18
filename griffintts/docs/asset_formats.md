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
   (secondary); phonemes use the Combilex/ARPABET-derived set. Note: the
   `2` (secondary stress) digit is valid in this dictionary file format, but
   is **not supported** in the `<phoneme ph="...">` ESML tag — see §8.

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

**Three variants, one actually used**: `.dictionary` (46K lines, 29,507
words), `.dictionary_full` (198K lines, 128,776 words),
`.dictionary_trimmed` (50K lines, 30,089 words). Confirmed via `strings`
on the real `libJiboTTSService.so`: the binary's string table contains
the literal suffix `.dictionary`, but **no** occurrence of
`.dictionary_full` or `.dictionary_trimmed` anywhere — the `.dictionary`
suffix is compiled into the binary; `resourcePath` only supplies the
directory.

**What the other two actually are, confirmed by diffing content, not
guessed from naming.** `.dictionary_full` never uses a placeholder —
every single word/POS entry has real, fully-specified phonemes, no
exceptions. Both `.dictionary` and `.dictionary_trimmed` selectively
replace *some* rarer POS-variant entries with the literal string `G2P`
in place of phonemes — a flag telling the runtime "predict this one
live via the G2P transducer (§4) instead of a stored lookup." For
`guillotined`: `_full` has real phonemes for all three of `JJ`/`VBN`/`VBD`;
the shipped `.dictionary` keeps `JJ`'s real phonemes but drops `VBN`/`VBD`
to `G2P`; `.dictionary_trimmed` makes the *identical* substitution for
the same word. So:

- **`.dictionary_full`** is the master, fully-curated source dictionary
  — plausibly what `.g2p` (§4) was itself trained on.
- **`.dictionary`** (what actually ships) is a size/memory-optimized
  derivation of `_full`, deliberately punting rarer grammatical-form
  pronunciations to live G2P prediction rather than storing them.
- **`.dictionary_trimmed`** is a near-identical sibling of the same
  derivation process (different word count, same substitution pattern)
  — very likely an earlier or alternate build of the same trimming
  pipeline, not what ships in this specific binary, but genuine kin
  rather than an unrelated file.

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

## 8. IPA / X-SAMPA ↔ Combilex, and the `--ipa`/`--xsampa` converter

Combilex isn't a notation most people know. If you're trying to fix a
mispronounced word, you're far more likely to find its pronunciation on
Wiktionary (IPA) than to already know Combilex. `griffintts` can convert
either IPA or the ASCII-safe X-SAMPA equivalent into a ready-to-use
`<phoneme ph="...">` tag directly:

```bash
griffintts --ipa "/ˈpiːt.sə/" pizza
# <phoneme ph="1 p ii t 0 s ah">pizza</phoneme>

griffintts --xsampa '/pI"tsA:/' pizza
# <phoneme ph="0 p iy 1 t s aa">pizza</phoneme>

griffintts --ipa "/ˈbɑːnoʊ/" --no-stress bono
# <phoneme ph="b aa n ou">bono</phoneme>  — matches the confirmed empirical
#   Bono string in prosody_and_affect.md §8 exactly
```

This prints the tag and exits — it's a pure text transform, no
synthesis, no container/native mode involved. Paste the result into a
larger `--markup` string, or into the dictionary directly if the
mispronunciation is common enough to fix globally (see `docs/FAQ.md`'s
on-device-editability entry).

### The crosswalk table

Covers exactly the 41 real phonetic segments in `en_us_world.phones`
(§2) plus common alternate notations for the same sounds. This is the
authoritative reference for what `--ipa`/`--xsampa` actually support —
anything outside this table fails loudly, naming the exact unrecognized
symbol and its position, rather than guessing.

| Combilex | Example (Wells set) | IPA | X-SAMPA |
|---|---|---|---|
| `ii` | fleece (FLEECE) | iː | i: |
| `iy` | kit (KIT) | ɪ | I |
| `e` | Ed (DRESS) | ɛ | E |
| `a` | trap (TRAP) | æ | { |
| `ah` | comma (COMMA/schwa) | ə | @ |
| `uh` | strut (STRUT) | ʌ | V |
| `aa` | palm (PALM) | ɑː | A: |
| `o` | thought (THOUGHT) | ɔː | O: |
| `uo` | hood (FOOT) | ʊ | U |
| `u` | goose (GOOSE) | uː | u: |
| `ou` | goat (GOAT) | oʊ | @U / oU |
| `ei` | waist (FACE) | eɪ | eI |
| `ai` | price (PRICE) | aɪ | aI |
| `oi` | choice (CHOICE) | ɔɪ | OI |
| `au` | mouth (MOUTH) | aʊ | aU |
| `ur` | nurse (NURSE) | ɜːr / ɜː / ɝ | 3:r / 3: |
| `or` | north (NORTH) | ɔːr / ɔr | O:r / Or |
| `ah r` | (unstressed -er, e.g. "computer") | ɚ | @r |
| `p b t d k g m n l h r j w` | (standard) | direct correspondents | direct correspondents |
| `ng` | ping | ŋ | N |
| `th` / `dh` | theta / thee | θ / ð | T / D |
| `f` / `v` / `s` / `z` | (standard) | direct correspondents | direct correspondents |
| `sh` / `zh` | she / seizure | ʃ / ʒ | S / Z |
| `tj` / `dj` | cheese / jab | tʃ / dʒ | tS / dZ |
| `dt` | tentative | ɾ (flap) | 4 |
| `ls` / `ms` / `ns` | cattle / spasm / garden | l̩ / m̩ / n̩ (syllabic) | l= / m= / n= |
| `lf` | healed | uncertain — the file's own comment flags this as "arguably not voiced"; not independently resolved here |

### Two honest limitations

- **Syllable boundaries need an explicit `.`** IPA/X-SAMPA don't mark
  unstressed-syllable boundaries by convention — only stress marks
  (`ˈ`/`ˌ`, or `"`/`%` in X-SAMPA) signal a break. Without a `.`
  separator, everything after a stress mark up to the next one (or the
  end of the word) collapses into a single syllable: `/ˈpiːtsə/` (no dot)
  produces one syllable `1 p ii t s ah`, while `/ˈpiːt.sə/` (with the
  dot) produces Jibo's own actual two-syllable dictionary shape, `1 p ii
  t 0 s ah`. Include `.` at syllable breaks in your source transcription
  for accurate results.
- **Stress-digit embedding in `<phoneme ph="...">` — use only `0` and `1`;
  do not use `2`.** The `.dictionary` file format uses `0` (none),
  `1` (primary), and `2` (secondary) stress digits for lexicon entries.
  However, the MIT HRI2024 ESML SDK reference (Jibo Inc. archive) explicitly
  states that secondary stress marker `2` is **not supported** at the
  `<phoneme>` tag level. Every empirically tested example in
  `prosody_and_affect.md` §8 also omitted stress digits entirely.
  **Use `--no-stress`** for the confirmed-working stress-digit-free form.
  If stress digits are desired, use only `0` and `1`; never `2` in a
  `<phoneme ph="...">` attribute.

---

## 9. `textnorm/` — text normalization (numbers, dates, currency, abbreviations)

`en_us_world/textnorm/` and `en_us/textnorm/` contain the OpenFST-based
text-normalization stage — the pipeline step that turns `03/21/1987`
into "march twenty first nineteen eighty seven" before dictionary
lookup ever happens.

**Not Thrax.** The natural assumption (`.grm` is Thrax's usual source
extension) is wrong here — `Main.spec`'s own header comment states
plainly this is written in **Jibo's own NLU parser grammar format**, the
same DSL as skill `launch.rule` files (`$Var`, `{_out='...'}`, `[optional]`,
`*`/`+` repetition, `~0.1` weighted-dispreference penalties, and
`$handle:Name` cross-file references) — confirmed by direct comparison
against real `launch.rule` syntax elsewhere in this project. It compiles
to OpenFST via a tool named `grm2fst` in the comments (not present on
disk in this checkout).

**Four files, three roles:**

| File | Role |
|---|---|
| `rules.grm` | The shared body of normalization sub-rules (1621 lines): numbers, currency, dates, time, measures, addresses, phone numbers, web/domains, math, abbreviations, roman numerals, letter-spelling, overrides, special characters. Its own header: *"The main rules file - to be cat'ed to the toprule files."* |
| `Main.spec` | A thin "toprule" entry point defining `TopRule`, pulling in `rules.grm`'s definitions. Compiles to `Main.fst` — the general normalizer. |
| `Digit.spec` | A second, separate toprule for a standalone digit→word converter, referenced from `Main.spec`/`rules.grm` via `$handle:Digit` and split out specifically "to ensure the final FST size is manageable." Compiles to `Digit.fst`. |
| `Main.tmp` / `Digit.tmp` | The literal concatenation of each `.spec` + `rules.grm` (confirmed byte-for-byte via diff) — the actual intermediate source text fed to the compiler. `Main.fst`/`Digit.fst` are OpenFST's compiled output (confirmed via `file`: `OpenFst binary FST data, fst type: vector, arc type: standard`). |

**Confirmed scope, from `rules.grm`'s own top-level rule list:**

```
NormRules = $Numbers{...} | $Abbreviation{...}~1 | $Measures{...} | $Dates{...} |
            $Time{...} | $Website{...} | $SpecChar{...} | $Address{...} |
            $PhoneNo{...} | $Maths{...}~0.1 | $Overrides{...};
```

That's the exhaustive list: numbers (cardinal/ordinal/decimal), currency
(24 currencies), dates, clock time, measurement units, US addresses,
phone numbers, URLs/domains, arithmetic expressions, and a long tail of
abbreviation/acronym/roman-numeral special cases (`FBI`→spelled out
letter names, `Dr.`→`doctor`, etc.) — confirmed against `textnorm.test`
(a 301-line `NAME ||| INPUT ||| EXPECTED_OUTPUT` test-case file bundled
alongside the grammar).

**What it does not do**: no character-substitution decoding of any
kind. The only character-level machinery in `rules.grm` is a pure
identity letter mapping (used for spelling out acronyms like `FBI`) and
digit→word conversion (`Numbers`) — nothing maps a digit standing in for
a letter (leetspeak-style, e.g. "3" meaning "e") back to that letter. A
mixed alphanumeric token that isn't a recognized number/date/measure
format falls through to the catch-all `Anything = $* {_out=_parsed}` —
passed to dictionary/G2P unmodified. Confirmed both by reading the
grammar and empirically: synthesizing a deliberately leetspeak-style
token takes noticeably longer than the natural-English equivalent
(consistent with character-by-character G2P/spelling fallback, not
normalization), not shorter or crashing.

`en_us` vs. `en_us_world`: nearly identical; `en_us` is an earlier,
smaller build of the same grammar (missing some later additions).

---

## Cross-references

- `docs/architecture.md` — the `.voice` acoustic model format (HTS
  version header, `STREAM_TYPE:MCP,LF0,BAP,LPF`), out of this doc's scope.
- `docs/prosody_and_affect.md` — the full ESML markup dialect (styles,
  pitch, duration, break, phoneme, say-as), empirically measured.
- `docs/FAQ.md` — on-device editability, the read-only-partition
  constraint, and the `.dictionary` vs. `.dictionary_full` finding in Q&A
  form.
