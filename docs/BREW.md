# Homebrew as an install option for NaturalScrollToggle

Date: 2026-10-21. Machine: macOS 27.0.1, Apple Silicon, Command Line Tools only, Homebrew 7.0.10.

Tags used on every claim:

- [Verified here]: I ran it on this machine, or read the installed Homebrew source in `/opt/homebrew/Library/Homebrew`, and the output is quoted or paraphrased from it.
- [Read online]: taken from the linked page, not reproduced here.
- [Not verified]: reasoned or recalled, not tested. Needs a check before it is relied on.

## Summary

- homebrew/cask and homebrew/core are closed to this project for now, and the cask route stays closed even after the star count is fixed, because the app is not notarized.
- A personal tap works today. A cask in a tap installs the same zip as the GitHub release, verified by sha256.
- Homebrew quarantines every cask download. An ad-hoc signed, non-notarized app is therefore blocked on first launch. `--no-quarantine` no longer exists in Homebrew 7, and a cask has no stanza to opt out. A cask can still remove the flag itself in `postflight_steps`, which is what I recommend for a personal tap.
- A formula that builds from source avoids the block, but Homebrew puts the app in the Cellar, not in `/Applications`, so it is the clumsier route.
- Recommended: cask living inside the project repo, tapped by URL (section 6).

## Assumptions

1. The release zip is named `NaturalScrollToggle-<version>.zip`, the tag is `v<version>`, and the zip contains `NaturalScrollToggle.app` at its top level.
2. The runner builds for the runner's own architecture. GitHub's `macos-latest` is Apple Silicon, so the zip is arm64 only. The cask below does not declare `depends_on arch: :arm64`; add it if the zip stays arm64 only (style check passes with it, verified).
3. Minimum macOS is 14 (Package.swift `.macOS(.v14)`, `LSMinimumSystemVersion 14.0`), which is Sonoma.
4. The version in `build.sh` is overridable through the `VERSION` environment variable (it is: `VERSION="${VERSION:-0.2.0}"`).
5. The preferences file really is `~/Library/Preferences/com.matejbasic.NaturalScrollToggle.plist` (taken from the brief; the bundle id in `build.sh` is `com.matejbasic.NaturalScrollToggle`).
6. The sha256 values in the files below are all-zero placeholders, because no release exists yet. The GitHub repo and release URL return HTTP 404 today [Verified here, curl].

## 1. Official repositories

### Thresholds

The notability numbers are not on the two repo pages. Both link to the shared page https://docs.brew.sh/Package-Acceptance-Policy [Verified here, fetched and read in full].

From the shared policy [Read online, fetched 2026-10-21]:

- "A new package must demonstrate public interest beyond its author."
- A GitHub project normally meets this with at least 30 forks, 30 watchers or 75 stars (one of the three is enough).
- For a self-submission, meaning the repository owner or a commit author whose email is at the package's homepage, url or head domain: at least 90 forks, 90 watchers or 225 stars.
- "A code repository less than 30 days old is normally not eligible."
- The metrics apply to the canonical upstream repository, not mirrors.
- A new package needs a working `livecheck` that does not use `skip`.
- The software must be actively maintained, with a public presence and a homepage that explains it.
- Maintainer discretion applies both ways: meeting the numbers does not guarantee acceptance.

Cask-specific (https://docs.brew.sh/Acceptable-Casks) [Read online]:

- "On macOS, apps, installers and other executable artefacts that Gatekeeper can assess must pass Homebrew's Gatekeeper checks and must not require System Integrity Protection or Gatekeeper to be disabled or bypassed."
- Notability exceptions exist for established apps whose repo only hosts binaries, for established maintainers, and for "a recently released application" with "substantial, independently verifiable public interest and multiple requests for inclusion". They permit further review and do not guarantee inclusion.
- "Open-source graphical software without a current compiled distribution also normally belongs in homebrew/core."

Formula-specific (https://docs.brew.sh/Acceptable-Formulae) [Read online]:

- Upstream must provide a stable, immutable tag or release; software without one is not eligible.
- Sources must be verified with SHA-256, and the formula must build and pass its tests on the homebrew/core CI matrix (macOS and Linux). "Compiler support": must build with current stable Apple Clang.
- Section "Native macOS applications": "A formula whose primary output is a native macOS `.app` bundle is not eligible. A supported application bundle published by upstream belongs in homebrew/cask."

The Gatekeeper rule is also stated in Homebrew's own security document: Homebrew "applies macOS quarantine attributes to Cask downloads so Gatekeeper performs these checks instead of Homebrew bypassing them" (`/opt/homebrew/docs/Homebrew-Security-and-Supply-Chain.md`, line 217) [Verified here].

### Correction to the brief

The brief says the cask page sends open source graphical software without a compiled distribution to homebrew/core as a formula. The cask page does say that. The formula page then excludes any formula whose primary output is a `.app` bundle. Read together, a menu bar app that is ad-hoc signed and not notarized has no eligible official home: cask rejects it on Gatekeeper, core rejects it as a native app. [Read online, both pages]

### Does a fresh, single-author project qualify now?

No, for three independent reasons:

1. Repo age: under 30 days is "normally not eligible".
2. Notability: a self-submission needs 90 forks, 90 watchers or 225 stars, and the project has none yet. If someone else submits it, the bar drops to 30/30/75.
3. Gatekeeper: the app is rejected by the system assessor. Verified here on a copy of the built bundle:

```
$ codesign -dv gk/NaturalScrollToggle.app
Signature=adhoc
TeamIdentifier=not set
$ spctl --assess --type execute -vv gk/NaturalScrollToggle.app
gk/NaturalScrollToggle.app: rejected          (exit 3)
```

### What it would need later

- A Developer ID signature plus Apple notarization (this needs a paid Apple Developer Program membership), so that `spctl --assess` accepts the app. This is the real blocker. The stars can come with time; the notarization has to be paid for.
- A repo older than 30 days, a stable tagged release with a downloadable zip, a working livecheck (the cask in section 2 has one), and the star/fork/watcher count above.
- Then submit with `brew bump`-style tooling or `brew create --cask`, and run `brew audit --cask --new`. That step needs the network and a real sha256, so it was not run.

## 2. Personal tap, cask variant

### The cask file

This file passed `brew style` and `brew audit --cask --strict` (offline, placeholder sha256) [Verified here, details below].

```ruby
cask "natural-scroll-toggle" do
  version "0.2.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/matej-basic/natural-scroll-toggle/releases/download/v#{version}/NaturalScrollToggle-#{version}.zip"
  name "Natural Scroll Toggle"
  desc "Menu bar app that switches natural scrolling for mouse and trackpad"
  homepage "https://github.com/matej-basic/natural-scroll-toggle"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "NaturalScrollToggle.app"

  # Ad-hoc signed, not notarized: drop the quarantine flag Homebrew sets on cask
  # downloads, otherwise Gatekeeper blocks the first launch.
  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "{{appdir}}/NaturalScrollToggle.app"]
  end

  zap trash: "~/Library/Preferences/com.matejbasic.NaturalScrollToggle.plist"
end
```

Notes on the choices:

- `livecheck` uses `strategy :github_latest`, not `:github_releases`. The Brew-Livecheck page says to use GithubLatest when the repo has a reliable "latest" release and GithubReleases only when Latest is not enough (for example pre-releases mixed in) [Read online, https://docs.brew.sh/Brew-Livecheck]. If you later publish pre-releases, switch the strategy to `:github_releases`.
- `depends_on macos: :sonoma` is the form `brew style` demands. My first try, `depends_on macos: ">= :sonoma"`, was flagged by `Homebrew/OSDependsOn: Use depends_on macos: :sonoma.` [Verified here]. The cookbook says the symbol form declares the minimum release [Read online, https://docs.brew.sh/Cask-Cookbook].
- `postflight_steps` is the Homebrew 7 form. The older `postflight do ... end` block was rejected by style with `Cask/InstallSteps: Casks must use postflight_steps instead of postflight.` The cookbook says legacy blocks "remain available temporarily for third-party tap compatibility" [Verified here for the style message, Read online for the quote]. The steps run inside a sandbox that is allowed to write to the app directory (cookbook text) [Read online]. The `xattr` step itself was not executed, because no install was allowed [Not verified].
- If you want the cask without the quarantine removal (users then see the Gatekeeper dialog), delete the `postflight_steps` block. That variant passed style and audit too [Verified here].

### Validation commands and results

| Command | Result |
|---|---|
| `brew style --display-cop-names cask-test/Casks/natural-scroll-toggle.rb` | exit 0, "no offenses detected" [Verified here] |
| `brew audit --cask <path>` | exit 1, `Error: Calling 'brew audit [path ...]' is disabled! Use 'brew audit [name ...]' instead.` [Verified here] |
| `brew audit --cask --strict test/scratch/natural-scroll-toggle` (file inside a locally tapped git repo) | exit 0, no output [Verified here] |

So `brew style` works on a standalone file, but only when the file sits under a directory named `Casks/` (or `Formula/`). A file outside such a directory is treated as plain Ruby and gets Sorbet and frozen-string offenses [Verified here]. `brew audit` does not take paths any more; it needs the item to be in a tap. A throwaway tap from a local git repo does the job (section 4). The audit ran offline, so it did not check the real download, the sha256 or the livecheck endpoint [Verified here by omission; those checks need the release to exist].

`brew info --cask --json=v2` on the tapped cask showed the parsed `postflight_steps` as a `run` step with the three xattr arguments, so Homebrew parses the stanza as intended [Verified here].

The cask token `natural-scroll-toggle` is free in the official repos: `https://formulae.brew.sh/api/cask/natural-scroll-toggle.json` and `.../formula/natural-scroll-toggle.json` both return 404 [Verified here, curl]. Casks need globally unique names, which is why the tap guide suggests prefixing with a username when there is a clash [Read online, https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap].

### Will Gatekeeper block the app after `brew install --cask`?

Yes, unless the cask removes the quarantine flag itself. The chain, with evidence:

1. Homebrew sets `com.apple.quarantine` on every cask download. `cask/download.rb` calls `quarantine(downloaded_path)` unconditionally after fetching, and `Quarantine.propagate` copies the attribute onto the extracted contents. The attribute is written through LaunchServices with the agent name "Homebrew Cask" (`extend/os/mac/cask/quarantine.rb`, lines 78-105) [Verified here, source read].
2. Gatekeeper assesses quarantined software on first launch. The app is ad-hoc signed with no Team ID and no notarization ticket, and `spctl` says `rejected` (section 1) [Verified here].
3. Result: the first launch is refused.

What the user sees on macOS 15 and later [Read online for the flow, Not verified for the exact wording on macOS 27]:

1. Double-clicking the app (or `open`) shows a dialog titled along the lines of "NaturalScrollToggle Not Opened", with text that Apple could not verify the app is free of malware, and buttons "Done" and "Move to Trash". It has no "Open" button. I recalled this wording from Sequoia and Tahoe; Apple's support page does not quote it, and I did not trigger it here.
2. Open System Settings, then Privacy & Security, scroll to the Security section, and click "Open Anyway" next to the message that the app was blocked. Apple's page says: "This button is available for about an hour after you try to open the app." Then enter the login password and click OK. [Read online, https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac. The page lists macOS 27 in its version picker but describes no version differences.]
3. From macOS 15 on, the old Control-click then Open shortcut no longer offers the override; only the Privacy & Security route remains. [Read online, third-party reports such as https://appleinsider.com/inside/macos/tips/how-to-launch-any-macos-app-even-those-not-notarized-by-apple; the Apple page does not mention it.]
4. After that approval the app is stored as an exception and opens normally.

Every upgrade of a quarantined cask keeps the quarantine flag and, according to the source comments, carries the user's approval forward only when the signing identity is unchanged (`Quarantine.inherit_user_approval!`, `signing_identity_match`) [Verified here, source read]. An ad-hoc signature changes on every build, so I would expect the dialog to come back after each `brew upgrade` [Not verified; the identity-match logic for ad-hoc signatures was not tested].

### Is `--no-quarantine` still supported, and can a cask declare it?

No to both.

- In Homebrew 7.0.10, `brew install --cask --no-quarantine nonexistent-cask-xyz` fails with `Error: invalid option: --no-quarantine` and prints the usage text, which has no quarantine option [Verified here, exit 1].
- History in the Homebrew repo [Verified here, `git log -S"no-quarantine"` in `/opt/homebrew`]: 2025-09-29 commit `a84673836c` strengthened the warning ("--no-quarantine bypasses macOS's Gatekeeper, reducing system security"); 2025-10-23 commit `ffe954753b` hid the flag ("Prepare for deprecation"); 2026-07-30 commit `ba25213c81` "Remove leftover code for `--no-quarantine`". The `HOMEBREW_CASK_OPTS` quarantine switch went with it (`env_config.rb` in the same commit).
- No cask stanza exists for it. Searching the cask DSL and artifact code for "quarantine" finds only the internal helper [Verified here]. The documented way around it is the cask doing its own cleanup, as in the `postflight_steps` above. That is allowed in third-party taps and would be rejected in homebrew/cask under the Gatekeeper rule.

Trade-off to state in the README: the postflight step makes Gatekeeper skip the app, which is the same thing the planned `curl | bash` installer does. The sha256 in the cask still pins the exact zip that CI built, which `curl | bash` does not.

## 3. Personal tap, formula variant (build from source)

### The formula

Passed `brew style` (exit 0) and `brew audit --formula --strict` through a local tap (exit 0, offline, placeholder sha256). `brew install --dry-run` on it printed "Would install 1 formula" with no Xcode complaint. [Verified here] It was never built, because installing was not allowed, so the build steps are [Not verified].

```ruby
class NaturalScrollToggle < Formula
  desc "Menu bar app that switches natural scrolling for mouse and trackpad"
  homepage "https://github.com/matej-basic/natural-scroll-toggle"
  url "https://github.com/matej-basic/natural-scroll-toggle/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/matej-basic/natural-scroll-toggle.git", branch: "main"

  depends_on macos: :sonoma

  deny_network_access!

  def install
    # build.sh calls plain `swift build`; SwiftPM's own sandbox cannot nest
    # inside Homebrew's build sandbox, so switch it off the way std_swift_args does.
    inreplace "build.sh", "swift build -c release", "swift build -c release --disable-sandbox"
    ENV["VERSION"] = version.to_s
    system "./build.sh"

    prefix.install "build/NaturalScrollToggle.app"
    (bin/"natural-scroll-toggle").write <<~SH
      #!/bin/bash
      exec /usr/bin/open "#{opt_prefix}/NaturalScrollToggle.app"
    SH
  end

  service do
    run [opt_prefix/"NaturalScrollToggle.app/Contents/MacOS/NaturalScrollToggle"]
    keep_alive crashed: true
    process_type :interactive
  end

  def caveats
    <<~EOS
      Start it once with:
        natural-scroll-toggle
      Or at every login with:
        brew services start natural-scroll-toggle
    EOS
  end

  test do
    app = prefix/"NaturalScrollToggle.app"
    assert_path_exists app/"Contents/MacOS/NaturalScrollToggle"
    system "/usr/bin/codesign", "--verify", "--deep", app
  end
end
```

The formula reuses `build.sh`, so the Info.plist and the ad-hoc signing stay in one place. If `build.sh` ever changes its `swift build` line, the `inreplace` raises an error instead of silently doing nothing, which is the behaviour you want. The alternative is to build with `swift build *std_swift_args` in the formula and assemble the bundle there, which duplicates the plist.

### `xcode: :build` or nothing?

- `depends_on xcode:` is a requirement for the full Xcode.app. `XcodeRequirement#xcode_installed_version!` returns false unless `MacOS::Xcode.installed?`, and its message reads "A full installation of Xcode.app is required to compile this software. Installing just the Command Line Tools is not sufficient." [Verified here, `/opt/homebrew/Library/Homebrew/requirements/xcode_requirement.rb`]. Declaring it would lock out CLT-only users, who are the target of this project. Declare nothing.
- Swift comes from the CLT: `/usr/bin/swift`, Swift 6.4, `xcode-select -p` is `/Library/Developer/CommandLineTools` on this machine [Verified here]. Homebrew needs the CLT to build any formula from source on macOS anyway [Read online, Homebrew installation docs; Not verified here].
- The core Swift formulae add `uses_from_macos "swift" => :build` and, for most, `depends_on xcode: [..., :build]`. With `:build`, the Xcode requirement is skipped when a bottle is poured, which a third-party tap without bottles never does [Read online for the bottle semantics, formulae quoted below].

### How homebrew/core builds Swift packages

Fetched from `Homebrew/homebrew-core` HEAD on 2026-10-21 [Verified here, raw files saved in the scratchpad `core/` folder]:

| Formula | Build lines |
|---|---|
| swiftlint | `depends_on xcode: "8.0"`, `uses_from_macos "swift" => :build, since: :sonoma`, `deny_network_access!`; `def fetch` runs `system "swift", "package", "resolve", "--disable-sandbox"`; install: `system "swift", "build", "--product", "swiftlint", *std_swift_args` then `bin.install ".build/release/swiftlint"` |
| swift-format | same shape, `depends_on xcode: ["14.0", :build]`, `pour_bottle? only_if: :clt_installed` with the comment "bottles ... do not work out of the box on Xcode-only systems due to an incorrect sysroot" |
| swiftformat | `uses_from_macos "swift" => :build`, `deny_network_access!`, `system "swift", "build", *std_swift_args`, `bin.install ".build/release/swiftformat"` (no `fetch`, no Xcode line) |
| mas | `system "Scripts/build", ..., "--disable-sandbox", "-c", "release"` |
| sourcery | `system "swift", "package", "resolve", "--disable-sandbox", "--build-path", "build/"` |

The `fetch` blocks carry the comment: "SwiftPM tries to apply its own sandbox, which cannot nest inside the build sandbox; Homebrew's sandbox still confines the whole process." [Verified here]

### Is `--disable-sandbox` needed?

Yes, by the evidence in the table. `std_swift_args` on macOS is `["--disable-sandbox"].concat(super)`, and `super` is `["--configuration", "release", "--jobs", N]` (`extend/os/mac/formula.rb` line 39 and `formula.rb` line 2386) [Verified here, source read]. The project has no package dependencies (`Package.swift` declares only local targets), so no `fetch` block and no network access are needed, and `deny_network_access!` is safe [Verified here, Package.swift read]. Whether this particular build passes under the sandbox was not run [Not verified].

### Can a formula install a .app bundle?

- homebrew/core: no. The "Native macOS applications" section excludes it [Read online].
- Third-party tap: nothing in the tap guide forbids it, and `brew audit --strict` accepted `prefix.install "build/NaturalScrollToggle.app"` [Verified here; the audit is static, so it would not notice this either way]. There is precedent: the `d12frosted/emacs-plus` tap does `prefix.install "nextstep/Emacs.app"` and says in its caveats "Formulas don't install apps into /Applications" [Verified here, formula fetched from https://github.com/d12frosted/homebrew-emacs-plus].
- Consequence: the app ends up in `$(brew --prefix)/Cellar/natural-scroll-toggle/0.2.0/NaturalScrollToggle.app`, reachable as `$(brew --prefix natural-scroll-toggle)/NaturalScrollToggle.app` through the `opt` link. `brew link` does not put it in `/Applications`, so Spotlight and Launchpad will not find it unless the user symlinks or copies it, as the emacs-plus caveats suggest [Not verified here, inferred from the Cellar layout and the emacs-plus text]. The `bin` launcher in the formula above works around that for the command line.

### Does a source build avoid the quarantine problem?

Yes. The quarantine code in the Homebrew source lives only in the `Cask::` namespace (`cask/download.rb`, `cask/quarantine.rb`, `cask/artifact/moved.rb`, plus `diagnostic.rb`); formula downloads never call it [Verified here, grep of the whole `Library/Homebrew` tree excluding tests]. Formula sources are fetched with curl or git, which do not set `com.apple.quarantine`, and the compiled binary is written by a local process. Gatekeeper only assesses quarantined files, so the ad-hoc signed app opens with no dialog. Whether a non-quarantined, ad-hoc signed app launches silently on macOS 27 was not tested here [Not verified].

Costs of this route: the user needs the CLT and waits for a build (about 20 s by the project's own figure), and a new build is made on each upgrade.

### `brew services` and a menu bar app

What `brew services start` generates for the formula above [Verified here, `brew ruby -e 'puts Formula["test/formula/natural-scroll-toggle"].service.to_plist'`]:

```
<key>KeepAlive</key><dict><key>Crashed</key><true/></dict>
<key>Label</key><string>sh.brew.natural-scroll-toggle</string>
<key>LimitLoadToSessionType</key><array>Aqua Background LoginWindow StandardIO System</array>
<key>ProcessType</key><string>Interactive</string>
<key>ProgramArguments</key><array>/opt/homebrew/opt/natural-scroll-toggle/NaturalScrollToggle.app/Contents/MacOS/NaturalScrollToggle</array>
<key>RunAtLoad</key><true/>
```

- LaunchAgent or LaunchDaemon: without `sudo`, services go to `~/Library/LaunchAgents` and run at login; with `sudo` they go to `/Library/LaunchDaemons` and run at boot (`brew services` manpage, https://docs.brew.sh/Manpage) [Read online]. The source agrees: `services/system.rb` defines `user_path` as `~/Library/LaunchAgents` and `boot_path` as `/Library/LaunchDaemons`, and `domain_target` is `gui/<uid>` for a normal user session (it falls back to `user/<uid>` only under sudo or over SSH without console ownership) [Verified here, source read].
- GUI session: the generated plist lists `Aqua` among `LimitLoadToSessionType`. Aqua is the logged-in graphical session, so a menu bar item is possible in principle. The source comment says the field exists so a service started from a background session survives the user's later GUI login [Verified here].
- `process_type :interactive` only sets `ProcessType` to `Interactive`. Homebrew's own comment in `service.rb` says that field "is used to indicate process priority and not necessarily if it should run in a specific session type" [Verified here]. It gives the process no resource limits; it does not make it a GUI app.
- I used `keep_alive crashed: true` instead of the brief's `keep_alive true`. With `true`, choosing Quit in the menu would make launchd start the app again at once. `crashed: true` restarts only after a crash. The cookbook lists both forms [Read online, https://docs.brew.sh/Formula-Cookbook, "keep_alive options"].
- Not verified: that the app shows its status item when launchd starts the inner executable directly rather than through LaunchServices. I did not start the service. Two risks to test first: macOS privacy permissions (if the app needs any) may be attributed to a different process than when launched by `open`, and an unbundled launch skips LaunchServices registration of the app.
- A simpler alternative for "start at login" is a login item that the app registers itself, which needs no Homebrew involvement.

## 4. Tap mechanics

### Variants

(a) Separate repository `matej-basic/homebrew-tap` with `Casks/natural-scroll-toggle.rb`:

- Install in one command: `brew install --cask matej-basic/tap/natural-scroll-toggle`. Homebrew taps the repo automatically and trusts only that item. The tap guide shows `==> Tapping alice/homebrew-tap` followed by the install, and says "It also trusts only the formula being installed." [Read online, https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap and https://docs.brew.sh/Tap-Trust]. The auto-clone from GitHub could not be tested because the repo does not exist [Not verified]. I tested the trust half locally (below).
- The name `matej-basic/tap` comes from the repo name `homebrew-tap` with the `homebrew-` prefix dropped [Read online, tap guide].

(b) Cask in the project repo, with a `Casks/` directory at its root:

- Command: `brew tap matej-basic/natural-scroll-toggle https://github.com/matej-basic/natural-scroll-toggle`, then `brew install --cask matej-basic/natural-scroll-toggle/natural-scroll-toggle`.
- Confirmed to work: Homebrew accepts any git URL for a tap (tap guide: "you can use anything as long as it's a protocol that Git understands" and the `brew tap user/repo <URL>` form) [Read online]. I reproduced this with a local git repo that has a `Casks/` folder and is not named `homebrew-anything`: `brew tap test/scratch /path/to/repo` cloned it into `/opt/homebrew/Library/Taps/test/homebrew-scratch` and reported "Tapped 1 cask (14 files, 5.1KB)" [Verified here]. The tap guide says casks go in a `Casks` directory at the top level, and formulae in `Formula`, `HomebrewFormula` or the repo root [Read online].
- Short tap name is not possible without the URL: the one-argument form looks for `matej-basic/homebrew-natural-scroll-toggle`, which does not exist. So (b) always needs the two commands [Read online, tap guide; not tested].

### User experience compared

| | (a) separate tap repo | (b) cask inside project repo |
|---|---|---|
| Commands for the user | 1 | 2 |
| Extra repo to maintain | yes | no |
| Token for CI | fine-grained PAT with write access to the tap | none, the workflow's own `GITHUB_TOKEN` |
| `brew update` cost | clones a repo with one file | clones the whole project repo (small today) |
| Future apps | add more casks to the same tap | no |
| Command name users see | `matej-basic/tap/natural-scroll-toggle` | `matej-basic/natural-scroll-toggle/natural-scroll-toggle` |

### What the user types with Homebrew 7 tap trust

Facts from https://docs.brew.sh/Tap-Trust [Read online]: non-official taps need explicit trust by default since Homebrew 6.0.0; installing a fully qualified name trusts only that item; installing by short name needs the item or the tap trusted first; `brew trust` with no arguments lists, `brew untrust` lists untrusted entries.

Commands, with what I confirmed:

| Goal | Commands | Status |
|---|---|---|
| Minimal (a) | `brew install --cask matej-basic/tap/natural-scroll-toggle` | trust step confirmed locally; auto-tap step [Read online] |
| Minimal (b) | `brew tap matej-basic/natural-scroll-toggle https://github.com/matej-basic/natural-scroll-toggle` then `brew install --cask matej-basic/natural-scroll-toggle/natural-scroll-toggle` | [Verified here] with a local tap named `test/scratch` |
| Short name afterwards | `brew trust --cask matej-basic/natural-scroll-toggle/natural-scroll-toggle` then `brew install --cask natural-scroll-toggle` | the `brew trust --cask` form is printed by Homebrew's own error message [Verified here]; I ran the whole-tap form |
| Whole tap | `brew trust matej-basic/natural-scroll-toggle` (or `brew trust --tap ...`, per the docs) | [Verified here] for `brew trust test/scratch` |

Local test, with exact commands and results (scratch repo built from the cask above, nothing installed; all of this was undone afterwards):

```
$ brew tap test/scratch /private/tmp/.../scratchpad/tap-repo          exit 0  "Tapped 1 cask"
$ brew trust                                                          "No trusted taps, formulae, casks or commands."
$ brew untrust                                                        "Untrusted taps: test/scratch / Untrusted casks: test/scratch/natural-scroll-toggle"

$ brew install --cask natural-scroll-toggle          # short name, untrusted
Error: Refusing to load cask test/scratch/natural-scroll-toggle from untrusted tap test/scratch.
Run `brew trust --cask test/scratch/natural-scroll-toggle` or `brew trust test/scratch` to trust it.

$ brew install --cask test/scratch/natural-scroll-toggle   # fully qualified, untrusted
==> Trusted cask test/scratch/natural-scroll-toggle
==> Fetching downloads for: test/scratch/natural-scroll-toggle
Error: Download failed ... curl: (56) The requested URL returned error: 404
```

The last command passed the trust gate by itself and only failed because the release does not exist yet (the 404 is expected). `brew doctor` also warns about the untapped-trust state with "The following taps are not trusted" and lists `brew trust` and `brew untap` as the fixes [Verified here].

Cleanup commands, all exit 0: `brew untrust --cask test/scratch/natural-scroll-toggle`, `brew trust test/scratch`, `brew untrust test/scratch`, `brew untap test/scratch`. Afterwards `brew tap` printed nothing and `brew untrust` reported "No untrusted taps, formulae, casks or commands." [Verified here] The other three scratch taps (`test/formula`, `test/pf`, `test/pf2`) were trusted, audited and untapped the same way.

## 5. Automation on release

### Option 1: the release workflow edits the cask

Fits (b) best. The cask file sits in the same repo, so the workflow's own token can push to `main`. For (a) the step is the same but it checks out the tap repo with a separate token.

I tested only the `sed` line, on a copy of the cask (it changed exactly the `version` and `sha256` lines) [Verified here], and parsed the workflow YAML [Verified here]. The workflow itself was not run [Not verified].

```yaml
name: release
on:
  push:
    tags: ["v*"]
permissions:
  contents: write
jobs:
  release:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build zip
        run: |
          VERSION="${GITHUB_REF_NAME#v}" ./build.sh
          ditto -c -k --keepParent build/NaturalScrollToggle.app "NaturalScrollToggle-${GITHUB_REF_NAME#v}.zip"
      - name: Publish release
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh release create "$GITHUB_REF_NAME" "NaturalScrollToggle-${GITHUB_REF_NAME#v}.zip" --generate-notes
      - name: Bump cask in this repo
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          V="${GITHUB_REF_NAME#v}"
          SHA="$(shasum -a 256 "NaturalScrollToggle-$V.zip" | cut -d' ' -f1)"
          git fetch origin main && git checkout main
          sed -i '' -E "s/^  version \".*\"/  version \"$V\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/natural-scroll-toggle.rb
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git commit -am "cask: natural-scroll-toggle $V"
          git push origin main
```

Points to watch:

- Use `ditto -c -k --keepParent` for the zip, not `zip`, so the bundle's symlinks and signature survive. The sha256 must come from the exact file that is uploaded, which is why the bump runs after the zip is built and from the same file.
- A push made with `GITHUB_TOKEN` does not trigger other workflows, so there is no loop [Read online, GitHub Actions docs; Not verified here].
- If `main` is protected by a rule that blocks bot pushes, this step fails. A one-person repo usually has no such rule.
- The tag points at the commit before the bump, so the cask on `main` is always one commit ahead of the tag. Nothing depends on that.

### Option 2: `brew bump-cask-pr`

`brew bump-cask-pr [options] cask` "creates a pull request to update cask with a new version" and makes "a best effort to determine the SHA-256" [Verified here, `brew bump-cask-pr --help`]. Useful flags from the same help text: `--version`, `--url`, `--sha256`, `--no-fork`, `--write-only` with `--commit`, `--dry-run`, `--no-audit`, `--no-style`. It is built for pull requests into official or third-party taps, needs a GitHub token in the environment and a Homebrew install on the runner (macOS runners have one) [Read online, not exercised here]. For a one-person tap with no reviewers it adds a PR to merge on every release, plus a re-download of the zip to compute the checksum the workflow already has. `brew bump --tap=<tap> --open-pr` can run on a schedule using the livecheck block, which is the right tool if you did not control the release pipeline, and wrong for a project that is itself the release pipeline [Verified here that the `--tap` and `--open-pr` flags exist in `brew bump --help`; the rest is a judgment].

### Recommendation

Option 1 with the cask inside the project repo (variant b). It needs no second repo, no personal access token, and about eight lines of shell. If you pick variant (a) instead, change only the checkout step: add `actions/checkout` for `matej-basic/homebrew-tap` with a fine-grained token limited to that repo (Contents: read and write) stored as a secret, run the `sed` against that checkout, and push there. Fine-grained tokens expire (a year at most), which is the one recurring chore (a) adds [Read online, GitHub docs; Not verified here].

## 6. Recommendation

Ranking, best first, for this project as it stands (ad-hoc signed, not notarized, one author):

| Rank | Route | User friction | Maintenance | Gatekeeper |
|---|---|---|---|---|
| 1 | Release zip plus `curl \| bash` installer | one command, no Homebrew needed | lowest: the installer script and the release workflow | zip downloaded in a browser is quarantined and shows the Open Anyway flow; the installer removes the flag and the user sees nothing |
| 2 | Cask in a personal tap, with the `postflight_steps` quarantine removal | two commands, then `brew upgrade` and `brew uninstall --zap` work normally | low: one `sed` step in the existing release workflow | skipped by design, same trade as the installer, but the zip is pinned by sha256 |
| 3 | Cask in a personal tap without the postflight step | same | same | blocked on first launch and probably again after each upgrade; the user does the Open Anyway flow |
| 4 | Formula built from source in a personal tap | two commands, needs CLT, ~20 s build per upgrade | medium: formula plus a source tarball sha256, `inreplace` coupling to `build.sh`, app not in `/Applications` | no quarantine, so no dialog |
| 5 | Official homebrew/cask | one command | none for you after acceptance | must pass Gatekeeper; impossible without Developer ID and notarization, and not before 30 days and the notability numbers |

Why the cask beats the formula even though the formula avoids the quarantine: the cask delivers the identical binary that CI built and users can inspect, puts the app in `/Applications`, and upgrades with a checksum. The formula builds a different binary on every machine, leaves the app in the Cellar, and the `brew services` route is unproven for a menu bar app (section 3).

Rank 1 and rank 2 are not exclusive. The installer is the cheapest route for people without Homebrew, and the tap is the better one for people who already use it. Offering both costs one extra `sed` step.

### Commands for the recommended brew route

With the cask inside the project repo (variant b):

```
brew tap matej-basic/natural-scroll-toggle https://github.com/matej-basic/natural-scroll-toggle
brew install --cask matej-basic/natural-scroll-toggle/natural-scroll-toggle
```

The second command is the trust step: installing a fully qualified cask trusts only that cask, and no separate `brew trust` is required [Verified here with a local tap; the same rule is in the Tap-Trust docs]. If you want the short name `brew install --cask natural-scroll-toggle` to work, or `brew upgrade` in scripts, trust it explicitly first:

```
brew trust --cask matej-basic/natural-scroll-toggle/natural-scroll-toggle
```

Update and remove:

```
brew upgrade --cask natural-scroll-toggle
brew uninstall --cask --zap natural-scroll-toggle
brew untap matej-basic/natural-scroll-toggle
```

If the tap lives in `matej-basic/homebrew-tap` instead (variant a), the whole thing is one command:

```
brew install --cask matej-basic/tap/natural-scroll-toggle
```

Before telling anyone to use it, run the real thing once on a clean user account: publish a release, tap, install, confirm the app launches with no dialog, check `xattr -l /Applications/NaturalScrollToggle.app`, then bump to a second version and confirm `brew upgrade` works. None of these steps was possible here because no release exists.

## Side effects of this research

- `brew install --cask --no-quarantine ...` ran `brew update` automatically (auto-update is on by default) and moved Homebrew from 7.0.9 to 7.0.10. Later commands set `HOMEBREW_NO_AUTO_UPDATE=1`.
- `brew style` switched Homebrew developer mode on and installed its Ruby gems into `/opt/homebrew/Library/Homebrew/vendor/bundle`. I ran `brew developer off` afterwards (it reports "Developer mode is disabled."). The gems stay installed.
- Four scratch taps were added and removed (`test/scratch`, `test/formula`, `test/pf`, `test/pf2`; `test/scratch` twice). Final state: `brew tap` is empty, `brew trust` shows no trusted entries, `brew untrust` shows nothing untrusted. No cask or formula was installed. The pre-existing `font-carlito` cask in the Caskroom was not touched.
- Files created under the scratchpad: `<scratch directory outside the project>/` (`cask-test/`, `tap-formula/`, `tap-repo/`, `web/`, `core/`, `wf/`, `gk/`). Nothing else on disk changed besides this file.

## Sources

Read online (fetched 2026-10-21; the pages were also downloaded and read as text):

- https://docs.brew.sh/Acceptable-Casks
- https://docs.brew.sh/Acceptable-Formulae
- https://docs.brew.sh/Package-Acceptance-Policy
- https://docs.brew.sh/Tap-Trust
- https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap
- https://docs.brew.sh/Cask-Cookbook
- https://docs.brew.sh/Formula-Cookbook
- https://docs.brew.sh/Brew-Livecheck
- https://docs.brew.sh/Manpage (services section)
- https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac
- https://appleinsider.com/inside/macos/tips/how-to-launch-any-macos-app-even-those-not-notarized-by-apple (third-party, for the Sequoia override flow)
- https://raw.githubusercontent.com/Homebrew/homebrew-core/HEAD/Formula/s/swiftlint.rb, `.../swift-format.rb`, `.../swiftformat.rb`, `.../Formula/m/mas.rb`, `.../Formula/s/sourcery.rb`
- https://github.com/d12frosted/homebrew-emacs-plus (formula `emacs-plus@30`)

Verified here (local files and commands):

- `/opt/homebrew/Library/Homebrew/cask/quarantine.rb`, `cask/download.rb`, `extend/os/mac/cask/quarantine.rb`
- `/opt/homebrew/Library/Homebrew/requirements/xcode_requirement.rb`
- `/opt/homebrew/Library/Homebrew/extend/os/mac/formula.rb`, `formula.rb` (`std_swift_args`)
- `/opt/homebrew/Library/Homebrew/service.rb`, `services/system.rb`
- `/opt/homebrew/docs/Homebrew-Security-and-Supply-Chain.md`
- Homebrew git history: commits `a84673836c`, `ffe954753b`, `ba25213c81`
- Commands: `brew --version`, `brew tap`, `brew trust`, `brew untrust`, `brew install --cask` (trust and 404 behaviour), `brew install --dry-run`, `brew style`, `brew audit`, `brew info --json=v2`, `brew ruby`, `brew bump-cask-pr --help`, `spctl --assess`, `codesign -dv`, `curl` on release and API URLs
