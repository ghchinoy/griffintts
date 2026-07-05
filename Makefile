.PHONY: all build griffintts griffintts-ui test clean help

all: build

## build: compile griffintts and griffintts-ui via their own independent Makefiles
build: griffintts griffintts-ui

## griffintts: build the local Griffin TTS speech synthesizer wrapper (see griffintts/Makefile)
griffintts:
	$(MAKE) -C griffintts build

## griffintts-ui: build the Jibo SwiftUI face and sync speech player app bundle (see griffintts-ui/Makefile)
griffintts-ui:
	$(MAKE) -C griffintts-ui build

## test: run griffintts' test suite (griffintts-ui has no automated tests yet)
test:
	$(MAKE) -C griffintts test

## clean: clean both tools' own build outputs
clean:
	$(MAKE) -C griffintts clean
	$(MAKE) -C griffintts-ui clean

## help: list available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
