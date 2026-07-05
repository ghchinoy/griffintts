# AGENTS.md — griffintts

Local, high-fidelity speech synthesis using Jibo's original 2017 "Griffin"
voice. Two components, see `README.md` for the overview, `griffintts/README.md`
and `griffintts-ui/README.md` for each one's own details.

## Build System

```bash
make build     # builds both griffintts and griffintts-ui
make test      # griffintts' test suite (griffintts-ui has no automated tests yet)
make clean
```

Or build just one from its own directory: `make -C griffintts build`,
`make -C griffintts-ui build`. `griffintts-ui` depends on `griffintts`
being built first, it shells out to the sibling binary at runtime.

## Non-negotiable: proprietary Jibo assets never get committed

`griffintts/assets/` (Jibo's actual trained voice model files, plus the
`jibo-tts-service` binary) and `griffintts/hts_engine_API/` (a third-party
dependency) are both gitignored on purpose and must stay that way. They're
pulled from a live Jibo unit you own (see `griffintts/README.md`'s "Voice
Assets" section) or cloned fresh (`hts_engine_API`'s section), never
vendored into this repo. If you're adding a new asset type, gitignore it
before you ever `git add` anything, not after.

## The sibling-binary lookup pattern

`griffintts-ui` finds and launches `griffintts`'s compiled binary at
runtime. This used to search upward from the app bundle's location for a
file called `AGENTS.md` to orient itself, a real bug: that file only
existed in the private monorepo this project used to live in exclusively,
so the app would have silently failed to find its own CLI backend the
moment it ran anywhere else, including this repo.

The fix, and the pattern to preserve: `findGriffinttsRepoRoot()` in
`griffintts-ui/Sources/griffintts-ui/ContentView.swift` computes a fixed
*structural* relative offset from the built `.app`'s own location
(`<root>/griffintts-ui/bin/GriffinTTS.app/Contents/MacOS/griffintts-ui` is
always 5 levels below `<root>`, and `<root>/griffintts/bin/griffintts` is
always the sibling binary), instead of searching for a marker file. Do not
reintroduce a marker-file search here, it silently breaks the moment this
code runs somewhere the marker doesn't exist.

## Build script portability

`griffintts-ui/scripts/build_app_bundle.sh` computes its own package root
from `${BASH_SOURCE[0]}`'s location rather than a hardcoded absolute path.
Keep that pattern if you touch this script, a hardcoded path only works on
the machine it was written on.
