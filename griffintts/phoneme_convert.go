package main

import (
	"fmt"
	"sort"
	"strings"
)

// phoneme_convert.go — IPA / X-SAMPA -> Combilex phoneme conversion.
//
// Griffin's ESML <phoneme ph="..."> tag (confirmed working, see
// docs/prosody_and_affect.md §8) takes a Combilex phoneme string. Combilex
// is not a widely-known notation outside this specific voice's own asset
// files (see docs/asset_formats.md for the full inventory, sourced from
// en_us_world.phones' own self-documenting header). Most people looking up
// a word's pronunciation will find IPA (Wiktionary's default) or, less
// commonly, X-SAMPA (ASCII-safe IPA equivalent). This file translates
// either into the Combilex phones griffintts's --ipa/--xsampa flags accept.
//
// Symbol tables cover exactly the 41 real phonetic segments in
// en_us_world.phones (confirmed inventory, not guessed) plus common
// alternate notations for the same sounds (e.g. IPA transcriptions vary in
// whether NURSE is written "ɜːr" or the single-codepoint "ɝ"). Anything
// outside this set fails loudly with the exact unrecognized substring and
// position, rather than guessing or silently dropping it — getting this
// wrong would be worse than the tool not existing.
//
// Stress-digit embedding in <phoneme ph="..."> itself is NOT independently
// confirmed — every empirically-tested example in this project's docs
// (docs/prosody_and_affect.md §8, "Bono" -> "b aa n ou") omitted stress
// digits entirely. This converter embeds them by default (following the
// same 0/1/2 convention the dictionary file format and the docs' own
// "vowel stress: 0=none, 1=primary, 2=secondary" note describe), since the
// daemon's phoneme parser plausibly shares logic with its dictionary-entry
// parser — but this is a reasoned guess, not a confirmed behavior. Use
// --no-stress to reproduce the exact confirmed-safe stress-digit-free form
// if the default doesn't sound right.

// phonemeMapping is one entry in a notation's symbol table.
type phonemeMapping struct {
	symbol   string // the IPA or X-SAMPA symbol (may be multi-rune/multi-char)
	combilex string // the Combilex phone(s) it maps to (space-separated if >1)
}

// ipaTable covers en_us_world.phones' full 41-phone inventory (see
// docs/asset_formats.md) plus common alternate IPA notations for the same
// sounds. Longer symbols are matched before shorter ones (see
// sortedByLength) so e.g. "eɪ" is tried before bare "e", "ɔːr" before "ɔː".
var ipaTable = []phonemeMapping{
	// Vowels — Wells lexical set correspondences per en_us_world.phones
	{"iː", "ii"},  // FLEECE
	{"ɪ", "iy"},   // KIT
	{"ɛ", "e"},    // DRESS
	{"æ", "a"},    // TRAP
	{"ə", "ah"},   // COMMA / schwa
	{"ʌ", "uh"},   // STRUT
	{"ɑː", "aa"},  // PALM
	{"ɔː", "o"},   // THOUGHT
	{"ʊ", "uo"},   // FOOT
	{"uː", "u"},   // GOOSE
	{"oʊ", "ou"},  // GOAT
	{"eɪ", "ei"},  // FACE
	{"aɪ", "ai"},  // PRICE
	{"ɔɪ", "oi"},  // CHOICE
	{"aʊ", "au"},  // MOUTH
	{"ɜːr", "ur"}, // NURSE (rhotic, long form)
	{"ɜː", "ur"},  // NURSE (non-rhotic transcription; still mapped rhotic — en_us_world is American)
	{"ɝ", "ur"},   // NURSE (single-codepoint r-colored variant)
	{"ɔːr", "or"}, // NORTH (rhotic, long form)
	{"ɔr", "or"},  // NORTH (short form)
	{"ɚ", "ah r"}, // unstressed r-colored schwa (word-final "-er") — two phones, matches the "computer" dictionary entry's own "ah r" convention

	// Consonants
	{"p", "p"}, {"b", "b"}, {"t", "t"}, {"d", "d"}, {"k", "k"}, {"g", "g"},
	{"m", "m"}, {"n", "n"}, {"ŋ", "ng"},
	{"θ", "th"}, {"ð", "dh"},
	{"f", "f"}, {"v", "v"}, {"s", "s"}, {"z", "z"},
	{"ʃ", "sh"}, {"ʒ", "zh"},
	{"tʃ", "tj"}, {"dʒ", "dj"},
	{"l", "l"}, {"h", "h"},
	{"r", "r"}, {"ɹ", "r"}, // ɹ = strict-IPA alveolar approximant, common alt for English "r"
	{"j", "j"}, {"w", "w"},
	{"ɾ", "dt"},  // flap (American "tt"/"dd" as in "butter"/"ladder")
	{"l̩", "ls"}, // syllabic l (combining U+0329)
	{"m̩", "ms"}, // syllabic m
	{"n̩", "ns"}, // syllabic n
}

// xsampaTable is the ASCII-only equivalent of ipaTable.
var xsampaTable = []phonemeMapping{
	{"i:", "ii"}, {"I", "iy"}, {"E", "e"}, {"{", "a"}, {"@", "ah"},
	{"V", "uh"}, {"A:", "aa"}, {"O:", "o"}, {"U", "uo"}, {"u:", "u"},
	{"@U", "ou"}, {"oU", "ou"}, {"eI", "ei"}, {"aI", "ai"}, {"OI", "oi"},
	{"aU", "au"}, {"3:r", "ur"}, {"3:", "ur"}, {"O:r", "or"}, {"Or", "or"},
	{"@r", "ah r"}, // unstressed r-colored schwa

	{"p", "p"}, {"b", "b"}, {"t", "t"}, {"d", "d"}, {"k", "k"}, {"g", "g"},
	{"m", "m"}, {"n", "n"}, {"N", "ng"},
	{"T", "th"}, {"D", "dh"},
	{"f", "f"}, {"v", "v"}, {"s", "s"}, {"z", "z"},
	{"S", "sh"}, {"Z", "zh"},
	{"tS", "tj"}, {"dZ", "dj"},
	{"l", "l"}, {"h", "h"}, {"r", "r"}, {"j", "j"}, {"w", "w"},
	{"4", "dt"},
	{"l=", "ls"}, {"m=", "ms"}, {"n=", "ns"},
}

// sortedByLength returns table entries sorted by descending rune-length of
// symbol, so greedy tokenization tries multi-rune symbols (e.g. "eɪ", "tʃ")
// before any single-rune symbol that could be a prefix of them.
func sortedByLength(table []phonemeMapping) []phonemeMapping {
	sorted := make([]phonemeMapping, len(table))
	copy(sorted, table)
	sort.SliceStable(sorted, func(i, j int) bool {
		return len([]rune(sorted[i].symbol)) > len([]rune(sorted[j].symbol))
	})
	return sorted
}

const (
	ipaStressPrimary      = '\u02c8' // ˈ
	ipaStressSecondary    = '\u02cc' // ˌ
	xsampaStressPrimary   = '"'
	xsampaStressSecondary = '%'
)

// phoneticSyllable holds one syllable's stress level and Combilex phonemes.
type phoneticSyllable struct {
	stress   int // 0=none, 1=primary, 2=secondary
	phonemes []string
}

// convertPhonetic parses an IPA or X-SAMPA transcription into Combilex
// syllables. notation must be "ipa" or "xsampa". Returns an error naming
// the exact unrecognized substring and its position if anything in the
// input isn't in the supported symbol set — this never guesses.
func convertPhonetic(input string, notation string) ([]phoneticSyllable, error) {
	var table []phonemeMapping
	var stressPrimary, stressSecondary rune
	switch notation {
	case "ipa":
		table = sortedByLength(ipaTable)
		stressPrimary, stressSecondary = ipaStressPrimary, ipaStressSecondary
	case "xsampa":
		table = sortedByLength(xsampaTable)
		stressPrimary, stressSecondary = xsampaStressPrimary, xsampaStressSecondary
	default:
		return nil, fmt.Errorf("unknown notation %q (expected \"ipa\" or \"xsampa\")", notation)
	}

	// Strip common transcription delimiters (/.../  or [...]) and whitespace.
	cleaned := strings.TrimSpace(input)
	cleaned = strings.Trim(cleaned, "/[]")

	runes := []rune(cleaned)

	// Split into syllables at each stress mark AND at explicit syllable
	// separators ("." — standard IPA convention, also accepted for
	// X-SAMPA). Stress marks carry a stress level for the syllable they
	// start; a bare "." starts a new unstressed (0) syllable, since only
	// one syllable per stress mark is ever stressed at that level.
	//
	// Without a "." separator, IPA/X-SAMPA has no way to signal a syllable
	// boundary at all — trailing unstressed syllables after the stressed
	// one collapse into a single syllable unless the input marks them.
	// This is a real, honest limitation: "/ˈpiːtsə/" (no dot) produces one
	// syllable "1 p ii t s ah", while "/ˈpiːt.sə/" (with the dot) produces
	// Jibo's own two-syllable "1 p ii t | 0 s ah" shape.
	type rawSyllable struct {
		stress  int
		content []rune
	}
	var raw []rawSyllable
	cur := rawSyllable{stress: 0}
	flush := func() {
		if len(cur.content) > 0 || cur.stress != 0 {
			raw = append(raw, cur)
		}
	}
	for _, r := range runes {
		switch r {
		case stressPrimary:
			flush()
			cur = rawSyllable{stress: 1}
		case stressSecondary:
			flush()
			cur = rawSyllable{stress: 2}
		case '.':
			flush()
			cur = rawSyllable{stress: 0}
		default:
			cur.content = append(cur.content, r)
		}
	}
	flush()

	if len(raw) == 0 {
		return nil, fmt.Errorf("no phonetic content found in %q after removing stress marks and delimiters", input)
	}

	var syllables []phoneticSyllable
	for _, rs := range raw {
		if len(rs.content) == 0 {
			continue
		}
		phonemes, err := tokenizeSyllable(rs.content, table)
		if err != nil {
			return nil, err
		}
		syllables = append(syllables, phoneticSyllable{stress: rs.stress, phonemes: phonemes})
	}
	if len(syllables) == 0 {
		return nil, fmt.Errorf("no phonetic content found in %q", input)
	}
	return syllables, nil
}

// tokenizeSyllable greedily matches the longest table symbol at each
// position. Returns an error citing the exact unmatched substring and its
// rune offset if any position matches nothing in the table.
func tokenizeSyllable(content []rune, table []phonemeMapping) ([]string, error) {
	var phonemes []string
	pos := 0
	for pos < len(content) {
		matched := false
		for _, m := range table {
			symRunes := []rune(m.symbol)
			end := pos + len(symRunes)
			if end > len(content) {
				continue
			}
			if string(content[pos:end]) == m.symbol {
				phonemes = append(phonemes, strings.Fields(m.combilex)...)
				pos = end
				matched = true
				break
			}
		}
		if !matched {
			return nil, fmt.Errorf(
				"unrecognized phonetic symbol %q at position %d in %q — not in the supported Combilex-mapped symbol set (see docs/asset_formats.md for the full inventory)",
				string(content[pos]), pos, string(content))
		}
	}
	if len(phonemes) == 0 {
		return nil, fmt.Errorf("no phonemes extracted from %q", string(content))
	}
	return phonemes, nil
}

// buildPhonemeTag renders syllables as a griffintts-ready ESML
// <phoneme ph="..."> tag. When includeStress is true (the default), each
// syllable is prefixed with its stress digit, matching the dictionary
// file's own convention — NOT independently confirmed against the live
// daemon (see this file's header comment). When false, produces the
// flat, stress-digit-free form that IS confirmed working in every tested
// example in docs/prosody_and_affect.md.
func buildPhonemeTag(word string, syllables []phoneticSyllable, includeStress bool) string {
	var parts []string
	for _, syl := range syllables {
		if includeStress {
			parts = append(parts, fmt.Sprintf("%d", syl.stress))
		}
		parts = append(parts, syl.phonemes...)
	}
	ph := strings.Join(parts, " ")
	return fmt.Sprintf(`<phoneme ph="%s">%s</phoneme>`, ph, word)
}
