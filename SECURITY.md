# Security policy

## Reporting a problem

Please report security problems privately, through the repository's Security tab ("Report a vulnerability"), not in a public issue. I will answer there. This is a one-person project, so a reply can take a few days.

Useful things to include: what you found, the version (`defaults read /Applications/NaturalScrollToggle.app/Contents/Info.plist CFBundleShortVersionString`), your macOS version, and steps to reproduce.

## Supported versions

Only the latest release gets fixes.

## What to expect from the builds

The app is signed ad hoc and is not notarized by Apple. The one-line installer and the Homebrew cask remove the quarantine flag, so Gatekeeper does not check the app on first launch. Each release has a `SHA256SUMS` file, and the cask pins the sha256 of the zip. Both come from the same GitHub repository as the zip, so they detect a broken or swapped download but cannot protect against someone who controls the repository or its release workflow. If that matters to you, build from source with `./build.sh`.

The latest security review is in [docs/SECURITY-REVIEW.md](docs/SECURITY-REVIEW.md).
