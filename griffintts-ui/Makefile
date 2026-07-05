.PHONY: all build clean help

all: build

## build: compile the release Swift build and package it into ./bin/GriffinTTS.app
build:
	./scripts/build_app_bundle.sh

## clean: remove ./bin and the Swift .build directory
clean:
	rm -rf ./bin ./.build
	@echo "  cleaned ./bin and ./.build"

## help: list available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
