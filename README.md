# griffintts

Local, high-fidelity speech synthesis using Jibo's original 2017 "Griffin"
voice, no cloud, no live robot required once the voice assets are pulled.

This repo has two pieces that ship together:

| Directory | What it is |
|---|---|
| [`griffintts/`](griffintts/) | The Go CLI. Does the actual synthesis work: container-emulated high-fidelity mode, or a fully native macOS fallback. Start here. |
| [`griffintts-ui/`](griffintts-ui/) | A SwiftUI macOS app: Jibo's animated eye, phase-locked to the audio `griffintts` produces. Optional, depends on `griffintts` being built first. |

## Build

```bash
make build     # builds both griffintts and griffintts-ui
make test      # griffintts' test suite (griffintts-ui has no automated tests yet)
make clean
```

Or build just one piece from its own directory (`make -C griffintts build`,
`make -C griffintts-ui build`), each has its own independent `Makefile`.

## Setup

`griffintts` needs Jibo's actual voice model files, pulled from a live unit
you own, see [`griffintts/README.md`](griffintts/README.md)'s "Voice
Assets" section before building. `griffintts-ui` has no setup of its own
beyond `griffintts` being built.

## License

Apache License 2.0, see [LICENSE](LICENSE).
