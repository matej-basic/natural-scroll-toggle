# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

`NaturalScrollToggle` is a small macOS menu bar app (no Dock icon) that turns natural scrolling on and off, by hand or automatically while an external mouse is connected. It is a solo project, published at https://github.com/matej-basic/natural-scroll-toggle. The app is ad-hoc signed and not notarized, so install routes (installer, Homebrew cask) strip the quarantine flag.

## Repository layout

- `Sources/ScrollCore/`: the decision logic (which devices count as an external mouse, what the setting should become, what to remember). Foundation only, so it builds on Linux.
- `Sources/NaturalScrollToggle/`: the menu bar app (AppKit, IOKit HID). Declared in `Package.swift` under `#if os(macOS)`, so Linux builds skip it.
- `Tests/ScrollCoreTests/`: swift-testing tests for ScrollCore. The Command Line Tools have no XCTest, which is why the tests use swift-testing.
- `Casks/natural-scroll-toggle.rb`: the Homebrew cask. The repo is its own tap. The release workflow rewrites `version` and `sha256` after each release.
- `build.sh`: builds, assembles and ad-hoc signs `build/NaturalScrollToggle.app`. `./build.sh install` copies it to `/Applications`.
- `install.sh`: the remote one-line installer that downloads the latest release. It is not a local-build helper.
- `compose.yaml`, `Makefile`: Docker services for the Linux tests and the linters.
- `.github/workflows/`: `ci.yml` (Linux tests, lint, macOS build) and `release.yml` (tag `v*` builds the zip, publishes the release, bumps the cask).
- `docs/`: research notes (`RESEARCH.md`, `BREW.md`). Reference only, not kept in sync with the code.

## Common commands

```bash
swift test                 # ScrollCore tests on the Mac
make test                  # the same tests on Linux, in swift:6.1
make lint                  # swift-format, shellcheck, actionlint in containers
./build.sh                 # build and sign build/NaturalScrollToggle.app
VERSION=0.3.0 ./build.sh   # set the bundle version (default is in build.sh)
./install.sh --dry-run     # show what the installer would do
build/NaturalScrollToggle.app/Contents/MacOS/NaturalScrollToggle --status   # on or off
```

## Conventions worth knowing

- English everywhere in the repo. No em dashes.
- Behaviour that can be decided without macOS goes into `ScrollCore` with a test. The app target only wires it to AppKit and IOKit.
- The private function that applies the setting is looked up at run time and has two fallbacks (see README, How it works). Do not link it directly.
- Swift style is enforced by `swift-format lint --strict` with the settings in `.swift-format` (4-space indent, 160 columns). Run `make lint` before pushing.
- The default version lives in `build.sh`; the release workflow overrides it from the tag. `Casks/natural-scroll-toggle.rb` carries a placeholder sha256 until the first release bumps it.
- Do not run `./install.sh` without `--dry-run` or `./build.sh install` while testing; both replace the installed app and quit the running one.
- With the Command Line Tools only, `swift test` on a clean `.build` can fail with a `TestingMacros` plugin error. Run `swift build --build-tests` first, then `swift test`.
- `CHANGELOG` has no file extension.
