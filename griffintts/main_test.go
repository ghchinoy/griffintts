package main

import (
	"os"
	"testing"
)

func TestParseDictionary(t *testing.T) {
	// Create a temporary mock dictionary file containing both formats
	tempDict, err := os.CreateTemp("", "mock-dict-*.txt")
	if err != nil {
		t.Fatalf("Failed to create temp dict: %v", err)
	}
	defer os.Remove(tempDict.Name())

	// Write mock entries:
	// 1. Standard format (word | 1 ph1 ph2)
	// 2. POS-tagged format (word | POS | 1 ph1 ph2)
	// 3. Comments and blank lines
	mockContent := `# Mock dictionary
hello | 1 h e | 0 l ou
world | NN | 1 w ur r l d

aletter | 1 ei
bletter | 1 b ii
`
	if _, err := tempDict.WriteString(mockContent); err != nil {
		t.Fatalf("Failed to write mock dict: %v", err)
	}
	tempDict.Close()

	dictMap, err := parseDictionary(tempDict.Name())
	if err != nil {
		t.Fatalf("parseDictionary returned error: %v", err)
	}

	// Assert "hello" parsed correctly
	helloPhs, ok := dictMap["hello"]
	if !ok {
		t.Errorf("Expected word 'hello' to be parsed")
	} else if len(helloPhs) != 4 || helloPhs[0] != "h" || helloPhs[1] != "e" || helloPhs[2] != "l" || helloPhs[3] != "ou" {
		t.Errorf("Unexpected phonemes for 'hello': %v", helloPhs)
	}

	// Assert POS-tagged "world" parsed correctly
	worldPhs, ok := dictMap["world"]
	if !ok {
		t.Errorf("Expected word 'world' to be parsed")
	} else if len(worldPhs) != 5 || worldPhs[0] != "w" || worldPhs[1] != "ur" || worldPhs[2] != "r" || worldPhs[3] != "l" || worldPhs[4] != "d" {
		t.Errorf("Unexpected phonemes for 'world': %v", worldPhs)
	}

	// Assert letter entries parsed
	aLetterPhs, ok := dictMap["aletter"]
	if !ok || len(aLetterPhs) != 1 || aLetterPhs[0] != "ei" {
		t.Errorf("Unexpected phonemes for 'aletter': %v", aLetterPhs)
	}
}

func TestPhonetizeText(t *testing.T) {
	dictMap := map[string][]string{
		"hello":   {"h", "e", "l", "ou"},
		"world":   {"w", "ur", "r", "l", "d"},
		"aletter": {"ei"},
		"bletter": {"b", "ii"},
	}

	// Test 1: Punctuation stripping, casing, and standard dictionary lookups
	prompt := "Hello, World!"
	phones := phonetizeText(prompt, dictMap)

	expected := []string{"lpau", "h", "e", "l", "ou", "w", "ur", "r", "l", "d", "lpau"}
	if len(phones) != len(expected) {
		t.Fatalf("Expected %d phones, got %d: %v", len(expected), len(phones), phones)
	}
	for i, ph := range phones {
		if ph != expected[i] {
			t.Errorf("At index %d: expected %s, got %s", i, expected[i], ph)
		}
	}

	// Test 2: Fallback to letter-spelling for unknown words
	promptUnknown := "ab"
	phonesUnknown := phonetizeText(promptUnknown, dictMap)

	expectedUnknown := []string{"lpau", "ei", "b", "ii", "lpau"} // spells out a-b using "aletter" and "bletter"
	if len(phonesUnknown) != len(expectedUnknown) {
		t.Fatalf("Expected %d phones, got %d: %v", len(expectedUnknown), len(phonesUnknown), phonesUnknown)
	}
	for i, ph := range phonesUnknown {
		if ph != expectedUnknown[i] {
			t.Errorf("At index %d: expected %s, got %s", i, expectedUnknown[i], ph)
		}
	}
}

func TestGenerateLabels(t *testing.T) {
	phones := []string{"lpau", "h", "lpau"}
	phoneFeatures := map[string][]string{
		"lpau": {"XX", "XX", "XX", "XX", "XX", "XX", "XX", "XX", "XX"},
		"h":    {"C", "C", "C", "C", "C", "C", "F", "G", "U"},
	}

	labels := generateLabels(phones, phoneFeatures)
	if len(labels) != 3 {
		t.Fatalf("Expected 3 labels, got %d", len(labels))
	}

	// Verify that the context window handles edges correctly (PLLI, PLI, PCI, PRI, PRRI)
	// Index 0: "lpau"
	// PLLI: lpau, PLI: lpau, PCI: -lpau+, PRI: h, PRRI: lpau
	l0 := labels[0]
	if !containsSubstring(l0, "PLLI:lpau") || !containsSubstring(l0, "PLI:lpau") || !containsSubstring(l0, "PCI:-lpau+") || !containsSubstring(l0, "PRI:h") || !containsSubstring(l0, "PRRI:lpau") {
		t.Errorf("Unexpected label context for index 0: %s", l0)
	}

	// Index 1: "h"
	// PLLI: lpau, PLI: lpau, PCI: -h+, PRI: lpau, PRRI: lpau
	l1 := labels[1]
	if !containsSubstring(l1, "PLLI:lpau") || !containsSubstring(l1, "PLI:lpau") || !containsSubstring(l1, "PCI:-h+") || !containsSubstring(l1, "PRI:lpau") || !containsSubstring(l1, "PRRI:lpau") {
		t.Errorf("Unexpected label context for index 1: %s", l1)
	}
}

func containsSubstring(str, sub string) bool {
	return len(str) >= len(sub) && (str == sub || (len(sub) > 0 && (str[:len(sub)] == sub || containsSubstring(str[1:], sub))))
}
