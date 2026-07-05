BIN := ./bin

.PHONY: all build griffintts griffintts-ui clean

all: build

## build: compile all tools in the tools workspace into ./bin
build: griffintts griffintts-ui

## griffintts: build the local Griffin TTS speech synthesizer wrapper
griffintts:
	@mkdir -p $(BIN)
	go build -C griffintts -o ../$(BIN)/griffintts .
	@echo "  built $(BIN)/griffintts"

## griffintts-ui: build the Jibo SwiftUI face and sync speech player app bundle
griffintts-ui:
	@mkdir -p $(BIN)
	./griffintts-ui/scripts/build_app_bundle.sh

## clean: remove the tools bin directory
clean:
	rm -rf $(BIN)
	@echo "  cleaned $(BIN)"
