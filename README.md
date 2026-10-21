# NaturalScrollToggle

A small macOS menu bar app that turns natural scrolling on and off, by hand or automatically when an external mouse is connected. It has no Dock icon. It needs macOS 14 or later. The release builds are made on an Apple silicon runner; on an Intel Mac, build from source.

## Install

### One command

    curl -fsSL https://raw.githubusercontent.com/matej-basic/natural-scroll-toggle/main/install.sh | bash

The script downloads `SHA256SUMS` and the zip of the latest release into a temporary directory, checks the hash, extracts the app, removes the quarantine flag, quits a running copy, replaces `/Applications/NaturalScrollToggle.app` (or `~/Applications` if `/Applications` is not writable for you) and starts it. It uses only `curl`, `ditto`, `xattr` and `shasum`, which ship with macOS. Read [install.sh](install.sh) first if you like. To see the steps and URLs without downloading anything:

    curl -fsSL https://raw.githubusercontent.com/matej-basic/natural-scroll-toggle/main/install.sh | bash -s -- --dry-run

Set `NST_VERSION=v0.2.0` to install a specific release and `INSTALL_DIR=/some/dir` to install somewhere else.

### Homebrew

    brew tap matej-basic/natural-scroll-toggle https://github.com/matej-basic/natural-scroll-toggle
    brew install --cask matej-basic/natural-scroll-toggle/natural-scroll-toggle

Homebrew 6 and later refuse casks from taps you have not trusted. Installing the fully qualified name in the second command is the trust step, and it trusts only this cask. To use the short name afterwards, run `brew trust --cask matej-basic/natural-scroll-toggle/natural-scroll-toggle` once.

Upgrade with `brew upgrade --cask natural-scroll-toggle`. Remove it with `brew uninstall --cask --zap natural-scroll-toggle`, and `brew untap matej-basic/natural-scroll-toggle` if you no longer want the tap. The app is ad-hoc signed and not notarized, so the cask strips the quarantine flag after install; the sha256 in the cask pins the exact zip that CI built.

### From source

You need the Xcode Command Line Tools (`xcode-select --install`), not full Xcode.

    ./build.sh

This compiles the Swift package in release mode and produces `build/NaturalScrollToggle.app`, signed ad hoc. Start it with `open build/NaturalScrollToggle.app`. To copy it to `/Applications` (quitting a running copy first), run:

    ./build.sh install

`VERSION=x.y.z ./build.sh` puts a different version number in the app.

## Uninstall

Untick "Launch at login" in the menu first if you turned it on. Then:

    pkill -x NaturalScrollToggle
    rm -rf /Applications/NaturalScrollToggle.app
    defaults delete com.matejbasic.NaturalScrollToggle

With Homebrew, `brew uninstall --cask --zap natural-scroll-toggle` does the same. If the app was installed to `~/Applications`, remove it from there.

## Features

- A "Natural scrolling" checkbox in the menu bar. The icon is a filled circle when natural scrolling is on and an outline when it is off.
- "Switch off automatically when a mouse is connected". While a USB or Bluetooth mouse is present, natural scrolling is off. When the last one goes away, the setting you had before comes back. Off by default.
- A "Pointing devices" submenu that lists what the app sees. External mice have a checkbox: ticked means the device counts as a mouse, unticked means the app ignores it. The built-in trackpad and other rejected devices are listed greyed out, with the reason in brackets.
- "Launch at login".
- Command line options for testing without clicking (see below).

## Command line options

Run the binary inside the app, for example `build/NaturalScrollToggle.app/Contents/MacOS/NaturalScrollToggle --status`.

- `--status` prints `on` or `off`.
- `--toggle` flips the setting and prints the new value.
- `--set on|off` sets it.
- `--devices` watches devices for 1.5 seconds and prints one line per device: whether it is accepted, rejected or ignored, its key, its name, its transport, the Built-In flag and its HID usage pairs.
- `--backend` prints how the app applies the setting (see below).

## How it works

Natural scrolling is the boolean `com.apple.swipescrolldirection` in the global preference domain, the value `defaults read -g com.apple.swipescrolldirection` shows. Writing that value alone only takes effect at the next login. To apply it at once, the app calls `setSwipeScrollDirection`, a private function in `PreferencePanesSupport.framework` that System Settings uses for the same checkbox. It looks the function up when it runs, so a future macOS that removes it does not stop the app from starting. If it is missing, the app tries the older `CGSSetSwipeScrollDirection`, and if that is missing too, it only writes the preference and shows a warning in the menu that changes apply after the next login. `--backend` prints which of the three is in use: `PreferencePanesSupport`, `CGS` or `preferences only`. In every case the app also writes the preference and posts `SwipeScrollDirectionDidChangeNotification`, and it listens for that notification, so the checkbox follows changes made in System Settings. This code is in `Sources/NaturalScrollToggle/ScrollPreference.swift`.

Device detection uses IOKit's HID manager. The app asks to be told when any device that reports itself as a mouse (HID usage page 1, usage 2) comes or goes, and reads the device's properties. It never opens a device or reads its input, so macOS does not ask for the Input Monitoring permission. Trackpads also report as mice, so a device counts as an external mouse only if it is not built in, is connected over USB or Bluetooth, and does not report itself as a touch pad. That rules out the built-in trackpad and an Apple Magic Trackpad. A Magic Mouse counts as a mouse. One physical device often shows up as several HID objects; the app groups them by location ID and counts each device once. It waits 300 ms after the last change before acting, because a receiver or hub announces its parts in a quick burst. This code is in `Sources/NaturalScrollToggle/MouseMonitor.swift`.

The decision itself (which devices count, what the setting should become, what to remember) is in the `ScrollCore` library, `Sources/ScrollCore/`. It uses Foundation only and has unit tests, which run on macOS and Linux with `swift test`. The tests use the swift-testing library because the Command Line Tools do not include XCTest.

The app's own settings live in `~/Library/Preferences/com.matejbasic.NaturalScrollToggle.plist`: `autoSwitchEnabled`, `ignoredDeviceKeys` and `rememberedNaturalScrolling`. `defaults read com.matejbasic.NaturalScrollToggle` shows them.

### Wireless receivers

A USB receiver for a wireless mouse (for example a Logitech Unifying or Bolt receiver) looks the same to macOS whether the mouse is switched on, asleep or in a drawer. The app therefore treats "receiver plugged in" as "mouse connected". If that is wrong for you, for example because a receiver stays in a dock you also use with only the trackpad, untick it in the Pointing devices menu.

### Other things to know

- If you switch natural scrolling back on by hand while a mouse is connected, the app leaves it alone until devices change again (for example after sleep, when a receiver can reconnect). It then switches it off again.
- Turning automatic switching off leaves the current setting as it is and forgets the remembered value.
- With automatic switching on and no mouse present at startup, the app restores the remembered value, or turns natural scrolling on if nothing is remembered.
- Launch at login uses the system login item service. macOS may ask you to allow it in System Settings, General, Login Items; the menu item then says "(approve in System Settings)".

## Gatekeeper

The app is signed ad hoc, not with a paid Developer ID, and it is not notarized, so Gatekeeper rejects it when it carries the quarantine attribute that browsers and Homebrew put on downloads. Both the one-command installer and the Homebrew cask remove that attribute (`xattr -dr com.apple.quarantine`), so no dialog appears. A build from source never has it.

A zip downloaded by hand from the Releases page is quarantined. On first launch macOS refuses it; open System Settings, Privacy & Security, scroll to the Security section and click Open Anyway next to the message about NaturalScrollToggle, then confirm with your password. You only need to do this once per downloaded copy. Or run `xattr -dr com.apple.quarantine /Applications/NaturalScrollToggle.app` yourself.

## Quit

Click the menu bar icon and choose Quit, or run `pkill -x NaturalScrollToggle`.

## Development

    make test    # ScrollCore tests on Linux, in a swift:6.1 container
    make lint    # swift-format, shellcheck and actionlint, each in a container
    swift test   # the same tests on the Mac

`make build` and `make install` call `./build.sh` and `./build.sh install`. The container setup is in `compose.yaml`; the only prerequisite is Docker.

With the Command Line Tools alone, `swift test` from a clean checkout can fail with `plugin for module 'TestingMacros' not found`. Run `swift build --build-tests` once first; after that `swift test` works. A Mac with Xcode installed does not have this problem.

CI runs the Linux tests and the lint services in containers, and the macOS build (tests, `./build.sh`, signature and Info.plist checks, a smoke run of the binary) on a GitHub macOS runner. Pushing a tag like `v0.3.0` makes the release workflow build the app, publish the zip and `SHA256SUMS` as a GitHub release and update the version and sha256 in `Casks/natural-scroll-toggle.rb`.

## License

MIT, see [LICENSE](LICENSE).
