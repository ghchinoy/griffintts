package main

import (
	"strings"
	"testing"
)

func TestConvertPhoneticBonoMatchesConfirmedEmpiricalString(t *testing.T) {
	// "b aa n ou" is the exact, empirically-confirmed working phoneme
	// string for "Bono" from docs/prosody_and_affect.md §8. This test
	// cross-checks the converter's output against real, confirmed data,
	// not just internal self-consistency.
	syllables, err := convertPhonetic("/ˈbɑːnoʊ/", "ipa")
	if err != nil {
		t.Fatalf("convertPhonetic returned error: %v", err)
	}
	tag := buildPhonemeTag("bono", syllables, false) // no-stress form, matching the confirmed string exactly
	want := `<phoneme ph="b aa n ou">bono</phoneme>`
	if tag != want {
		t.Errorf("got %q, want %q", tag, want)
	}
}

func TestConvertPhoneticPizzaMatchesDictionaryEntry(t *testing.T) {
	// en_us_world.dictionary_full's real entry for "pizza" is
	// "1 p ii t | 0 s ah" — this test confirms an IPA transcription with
	// an explicit syllable-boundary dot reproduces it phoneme-for-phoneme
	// and stress-for-stress (minus the dictionary file's own "|" syllable
	// separator, which isn't part of ESML <phoneme> tag syntax).
	syllables, err := convertPhonetic("/ˈpiːt.sə/", "ipa")
	if err != nil {
		t.Fatalf("convertPhonetic returned error: %v", err)
	}
	tag := buildPhonemeTag("pizza", syllables, true)
	want := `<phoneme ph="1 p ii t 0 s ah">pizza</phoneme>`
	if tag != want {
		t.Errorf("got %q, want %q", tag, want)
	}
}

func TestConvertPhoneticWithoutSyllableDotCollapsesToOneSyllable(t *testing.T) {
	// Documents the honest limitation: without an explicit "." separator,
	// there's no signal for a syllable boundary after the stressed
	// syllable, so trailing content collapses into it as one syllable.
	syllables, err := convertPhonetic("/ˈpiːtsə/", "ipa")
	if err != nil {
		t.Fatalf("convertPhonetic returned error: %v", err)
	}
	if len(syllables) != 1 {
		t.Fatalf("expected 1 syllable (no dot separator), got %d: %+v", len(syllables), syllables)
	}
	tag := buildPhonemeTag("pizza", syllables, true)
	want := `<phoneme ph="1 p ii t s ah">pizza</phoneme>`
	if tag != want {
		t.Errorf("got %q, want %q", tag, want)
	}
}

func TestConvertPhoneticXSAMPA(t *testing.T) {
	syllables, err := convertPhonetic(`/pI"tsA:/`, "xsampa")
	if err != nil {
		t.Fatalf("convertPhonetic returned error: %v", err)
	}
	tag := buildPhonemeTag("pizza", syllables, true)
	want := `<phoneme ph="0 p iy 1 t s aa">pizza</phoneme>`
	if tag != want {
		t.Errorf("got %q, want %q", tag, want)
	}
}

func TestConvertPhoneticUnrecognizedSymbolFailsLoudly(t *testing.T) {
	_, err := convertPhonetic("/pɪˈzza/", "ipa")
	if err == nil {
		t.Fatal("expected an error for the unmapped bare-ASCII 'a', got nil")
	}
	if !strings.Contains(err.Error(), "unrecognized phonetic symbol") {
		t.Errorf("expected an 'unrecognized phonetic symbol' error, got: %v", err)
	}
	if !strings.Contains(err.Error(), `"a"`) {
		t.Errorf("expected the error to name the exact unrecognized symbol 'a', got: %v", err)
	}
}

func TestConvertPhoneticUnknownNotation(t *testing.T) {
	_, err := convertPhonetic("/test/", "klingon")
	if err == nil {
		t.Fatal("expected an error for an unknown notation, got nil")
	}
}

func TestConvertPhoneticEmptyInput(t *testing.T) {
	_, err := convertPhonetic("//", "ipa")
	if err == nil {
		t.Fatal("expected an error for empty phonetic content, got nil")
	}
}

func TestConvertPhoneticDiphthongsAndAffricates(t *testing.T) {
	// Exercises multi-rune symbols that must be greedily matched before
	// any shorter symbol that could be a prefix of them: "tʃ"/"dʒ"
	// affricates, and several diphthongs.
	cases := []struct {
		name  string
		input string
		want  string
	}{
		{"choice affricate", "/tʃɔɪs/", "tj oi s"}, // "choice"
		{"jab affricate", "/dʒæb/", "dj a b"},      // "jab" — matches en_us_world.phones' own example row
		{"price diphthong", "/praɪs/", "p r ai s"}, // "price" — matches en_us_world.phones' own example row
		{"mouth diphthong", "/maʊθ/", "m au th"},   // "mouth" — matches en_us_world.phones' own example row
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			syllables, err := convertPhonetic(tc.input, "ipa")
			if err != nil {
				t.Fatalf("convertPhonetic(%q) returned error: %v", tc.input, err)
			}
			if len(syllables) != 1 {
				t.Fatalf("expected 1 syllable, got %d", len(syllables))
			}
			got := strings.Join(syllables[0].phonemes, " ")
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestConvertPhoneticRhoticVowelAlternateNotations(t *testing.T) {
	// "ɜːr" (long form) and "ɝ" (single-codepoint alt) must both map to
	// the same Combilex "ur" (NURSE).
	for _, sym := range []string{"ɜːr", "ɝ"} {
		syllables, err := convertPhonetic("/n"+sym+"s/", "ipa")
		if err != nil {
			t.Fatalf("convertPhonetic with %q returned error: %v", sym, err)
		}
		got := strings.Join(syllables[0].phonemes, " ")
		want := "n ur s"
		if got != want {
			t.Errorf("with symbol %q: got %q, want %q", sym, got, want)
		}
	}
}

func TestBuildPhonemeTagStressFlag(t *testing.T) {
	syllables := []phoneticSyllable{
		{stress: 1, phonemes: []string{"p", "ii"}},
		{stress: 0, phonemes: []string{"t", "s", "ah"}},
	}
	withStress := buildPhonemeTag("pizza", syllables, true)
	if withStress != `<phoneme ph="1 p ii 0 t s ah">pizza</phoneme>` {
		t.Errorf("with stress: got %q", withStress)
	}
	withoutStress := buildPhonemeTag("pizza", syllables, false)
	if withoutStress != `<phoneme ph="p ii t s ah">pizza</phoneme>` {
		t.Errorf("without stress: got %q", withoutStress)
	}
}
