BIN := ./bin

.PHONY: all build test clean help

all: build

## build: compile the griffintts CLI into ./bin/griffintts
build:
	@mkdir -p $(BIN)
	go build -o $(BIN)/griffintts .
	@echo "  built $(BIN)/griffintts"

## test: run the test suite
test:
	go test ./...

## clean: remove ./bin
clean:
	rm -rf $(BIN)
	@echo "  cleaned $(BIN)"

## help: list available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
