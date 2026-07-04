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

## griffintts-ui: build the Jibo SwiftUI face and sync speech player
griffintts-ui:
	@mkdir -p $(BIN)
	swift build --package-path griffintts-ui -c release
	@cp griffintts-ui/.build/release/griffintts-ui $(BIN)/griffintts-ui
	@echo "  built $(BIN)/griffintts-ui (Native macOS SwiftUI App)"

## clean: remove the tools bin directory
clean:
	rm -rf $(BIN)
	@echo "  cleaned $(BIN)"
