# AGENTS.md

Operational guidance for coding agents working on **Silentio**. This file
complements `README.md`, `BUILD.md`, and `CONTRIBUTING.md`. Read it before
changing audio handling, player control, release automation, or persistent
settings.

> **Language:** Write code, identifiers, comments, feature scenarios, commit
> messages, issues, pull requests, and all `.md` files in English.
> Maintainer-facing conversation may use the language chosen by the maintainer.

---

## 1. Project Overview

Silentio is a native, sandboxed **macOS menu-bar app** that mutes the built-in
speakers and pauses supported music players when the default output switches to
the speakers (for example after headphones disconnect). It ships as a universal
app (arm64 + x86_64), targets macOS 13 and later, and uses the bundle identifier
`com.vd.Silentio`.

The shared scheme `Silentio` builds, runs, and tests everything:

```text
Silentio/                                 # Sandboxed SwiftUI/AppKit menu-bar app
  App/SilentioApp.swift                   # AppKit entry point
  App/AppDelegate.swift                   # Monitoring, mute/pause flow, windows, login item
  App/StatusItemController.swift          # Menu-bar item and menu
  App/UpdateController.swift              # Sparkle wrapper and beta channel
  Audio/AudioDeviceMonitor.swift          # CoreAudio default output and data source listeners
  Audio/DeviceMuter.swift                 # Mute/restore built-in speakers (CoreAudio backend)
  Audio/AudioDevice.swift                 # Output device model and classification
  Players/                                # PlayerController, AppleScriptPlayer, Spotify, Music, VLC, registry
  Models/SilentioSettings.swift           # Observable UserDefaults-backed settings
  Views/                                  # Settings, onboarding, app icon, localized strings
  Resources/                              # Info.plist, Silentio.entitlements, Assets.xcassets
SilentioTests/                            # XCTest and Swift Testing unit tests (app-hosted)
SilentioUITests/                          # Status item and settings window UI test
tests/                                    # Python release-pipeline tests
features/speaker-protection.feature       # Gherkin behavior specification
Design/AppIcon-master.png                 # App icon master artwork
scripts/build.sh                          # Universal build, signing, entitlement checks, ZIP
scripts/test.sh                           # Lint, Python and Xcode tests, coverage gate
scripts/release.sh                        # Release steps used by the workflow (DMG)
scripts/update_appcast.py                 # Structured Sparkle feed updater
scripts/generate-app-icon.sh              # App icon sizes from the master
scripts/generate-menu-bar-icon.swift      # Vector menu-bar template
.github/workflows/tests.yml               # Pull-request and branch tests
.github/workflows/build-release.yml       # Beta and stable publishing
```

Important constraints:

- Both architectures must keep working; never add Intel-only or arm64-only code
  without a fallback.
- The app is sandboxed. Its entitlements are part of the product: App Sandbox,
  `network.client` (Sparkle), Apple Events with temporary exceptions for Spotify,
  Music, and VLC, and Sparkle's `-spks`/`-spki` Mach lookups.
- Silentio only restores speaker state it changed itself, and never writes mute or
  volume to an output that is not classified as built-in speakers.
- The app makes no network requests except Sparkle update checks and downloads
  from GitHub. There is no telemetry.
- Sparkle is the only Swift package dependency and is resolved through SwiftPM.
- See `PRIVACY.md` before changing data handling or persisted settings.

---

## 2. Local Setup and Commands

| Purpose | Command |
| ------- | ------- |
| Clone and open | `git clone https://github.com/vordenken/Silentio.git && cd Silentio && open Silentio.xcodeproj` |
| Resolve Swift packages | `xcodebuild -resolvePackageDependencies -project Silentio.xcodeproj -scheme Silentio` |
| Full validation | `bash scripts/test.sh` (lint, Python and Xcode tests incl. UI test, coverage > 80 %) |
| CI validation | `bash scripts/test.sh --unit-only` (skips the UI test and the coverage gate) |
| Python release tests | `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests` |
| Format Swift | `xcrun swift-format format --in-place --recursive Silentio SilentioTests SilentioUITests` |
| Validate workflows | `actionlint` |
| Validate the appcast | `xmllint --noout appcast.xml` |
| Universal build | `bash scripts/build.sh` (app and ZIP in `dist/`, override with `OUTPUT_DIR`) |
| Regenerate icons | `bash scripts/generate-app-icon.sh` and `swift scripts/generate-menu-bar-icon.swift` |
| Encode a signing certificate | `base64 -i certificate.p12 \| pbcopy` |

In Xcode: open `Silentio.xcodeproj`, scheme `Silentio`, Run (⌘R) or Test (⌘U).
Scripts are not executable; always run them with `bash`. New source files in the
synchronized folders are picked up automatically.

---

## 3. Architecture and State

- `AudioDeviceMonitor` listens for default-output and data-source changes and
  reports `DeviceChange` events to `AppDelegate`. The `AudioMonitoring` protocol
  allows the delegate's monitoring flow to use a fake monitor in tests.
- `AppDelegate.handle(_:)` decides whether the speakers became active. After the
  optional mute delay it re-checks that the speakers are still active, then asks
  `DeviceMuter` to mute and `PlayerRegistry` to pause running, enabled players.
  Switching away from the speakers restores the previous state.
- `DeviceMuter` mutes built-in speakers (falling back to volume 0), remembers the
  previous state, and restores it only if the same device UID is still classified
  as built-in speakers. A shared speaker/headphone output therefore defers
  restoration. The CoreAudio access sits behind a protocol so tests use a mock.
- Players implement `PlayerController`; `AppleScriptPlayer` sends commands through
  `NSAppleScript` and surfaces Automation errors in Settings. `PlayerRegistry`
  accepts injected players for tests; production uses Spotify, Music, and VLC.
- `UpdateController.swift` owns Sparkle preferences and allowed beta channels.
- Launch at Login uses `SMAppService.mainApp`.
- Settings are stored in `UserDefaults` under `com.vd.Silentio`:
  `muteOnDisconnect`, `unmuteOnReconnect`, `pauseOnDisconnect`, `muteOnWake`,
  `muteDelay`, `enabledPlayers`, `launchAtLogin`, `hasCompletedOnboarding`,
  `alwaysPausePlayers`, `monitorAtStartup`, `muteWhenMonitoringStarts`, and
  `BetaUpdatesEnabled`.

Treat `UserDefaults` keys, player bundle identifiers, and the entitlements as
contracts. Changes may require migration logic or new Automation consent.

---

## 4. Branches, Commits, and Releases

### Branches

- `main` is stable. A push releases only when `semver.txt` changed.
- A release-relevant push to `feature/*` creates the next immutable beta tag,
  `vX.Y.Z-betaN`.
- Documentation-only, repository-metadata, test-only, design, feature-spec, and
  generated appcast changes do not trigger a release.
- Other branch names (`bugfix/*`, `hotfix/*`) do not trigger the release
  workflow. Use `feature/*` when a beta build is required.
- Long-lived branches should fetch and merge `origin/main` regularly because the
  release bot advances `main` with appcast commits.

### Commits and Pull Requests

- Use a short imperative subject, preferably no longer than 72 characters.
- Conventional Commits are welcome but not required.
- Keep each commit focused on one logical change.
- Open pull requests against `main`; do not commit directly to `main`.
- Explain what changed and why. Include screenshots or recordings for UI work.
- Obtain maintainer review before merging.

### Version Source of Truth

`semver.txt` contains the release version and changelog:

```text
X.Y.Z
---
### Section
- Current release entry

## X.Y.(Z-1)
- Previous release history
```

- Line 1 must be strict `X.Y.Z` SemVer.
- `---` starts the current release notes.
- A heading matching `## X.Y.Z` starts historical notes.
- Preserve all historical sections; do not add a separate changelog.
- User-visible changes need an entry in `semver.txt`.
- Keep `MARKETING_VERSION` in the Xcode project in sync with `semver.txt`.
- Do not edit build numbers for individual CI runs; the workflow injects them.
  Keep the checked-in `CURRENT_PROJECT_VERSION` aligned with the latest
  published build so local development builds are not offered older updates.
- Do not edit `appcast.xml` manually. `scripts/update_appcast.py` updates the
  canonical feed on `main`, keeps all stable entries, and retains five betas.
- Do not create, move, or force-push release tags unless explicitly requested.
  Published releases are never overwritten.

### Release Pipeline

The release workflow:

1. Selects the stable or beta channel from the branch name.
2. Reads version and release notes from `semver.txt`.
3. Runs `bash scripts/test.sh --unit-only`.
4. Builds and signs the universal app, verifies its entitlements, then creates
   the DMG.
5. Signs the DMG with Sparkle's EdDSA tool.
6. Publishes the GitHub Release.
7. Updates the canonical appcast on `main`.

Release jobs are globally serialized because all branches share tags and one
appcast. Running releases are not cancelled. GitHub Actions use floating major
tags, and the Sparkle tools use `SPARKLE_VERSION`, which tests require to match
`Package.resolved`. Keep the workflow logic in `scripts/` so local runs and CI
behave the same. See `BUILD.md` for secrets and branch-protection setup.

---

## 5. Code Conventions

### Swift

- Use Swift 6 language mode and complete concurrency checking. The app uses
  MainActor default isolation and Approachable Concurrency.
- The deployment target is macOS 13: use `ObservableObject` instead of
  `@Observable`, and guard newer APIs with `if #available`.
- Use four-space indentation. Format with `xcrun swift-format` and the
  repository's `.swift-format`; `scripts/test.sh` lints in strict mode.
- Use SwiftUI for window content and AppKit for the menu bar and window lifecycle.
- Keep identifiers, comments, and user-facing strings in English
  (`Views/Localizable.swift`).
- Prefer the narrowest practical access level (`private` or `fileprivate`).
- Use `Logger` (`os`, subsystem `com.vd.Silentio`) for diagnostics; do not add
  `print()` or `NSLog()` calls.
- Prefer `guard let`; force unwrap only compile-time-guaranteed resources.
- Check every CoreAudio `OSStatus` and log failures with the device and selector.
- All user preferences live in `SilentioSettings`; do not hard-code values that
  should be configurable.
- New players implement `PlayerController`, are registered in `PlayerRegistry`,
  and need an Apple Events temporary exception plus a usage description.

### Bash

- Use `set -euo pipefail`, quote variables, and keep scripts shellcheck-clean.
- Stay compatible with macOS's Bash 3.2.
- Print errors to stderr with actionable context and exit non-zero.
- Comment advanced commands with their intent and safety implications.

### Python

- Use the standard library only; tests use `unittest` under `tests/`.

### Behavior Specification

- Business behavior changes need an English scenario in
  `features/speaker-protection.feature` that uses the real UI strings.

### Icons

- Keep `Design/AppIcon-master.png` and the generated app icon sizes together.
- The menu-bar icon is a separate vector template; regenerate it with
  `scripts/generate-menu-bar-icon.swift` after changing its drawing code.

---

## 6. Validation Before a Pull Request

Quit any running Silentio instance first (press Stop in Xcode if it is paused in
the debugger). The app hosts the unit tests.

Run the automated checks relevant to the change:

```bash
bash scripts/test.sh
```

Add tests for every changed code path and keep production line coverage above
80 %. For workflow or release changes, also run:

```bash
actionlint
shellcheck scripts/build.sh scripts/test.sh scripts/release.sh scripts/generate-app-icon.sh
xmllint --noout appcast.xml
```

The automated suite covers device classification, the muter's mute/restore rules
(with a mock CoreAudio backend), settings, player command structure, the update
controller, the settings window lifecycle, the appcast updater, and the release
pipeline. It cannot exercise real audio hardware or Automation consent.

Perform the applicable manual tests before release, on Apple Silicon and Intel
hardware where available. Record Mac model, macOS version, output UID, data
source, starting mute/volume state, and the actual result for failures.

| Starting output | Action | Expected result |
| --- | --- | --- |
| Built-in 3.5 mm headphones | Unplug jack | Built-in speakers mute; enabled running players pause. |
| Bluetooth (e.g. AirPods) or USB headphones | Disconnect | Same, only if macOS selects built-in speakers. |
| HDMI/DisplayPort audio | Disconnect display | Same, only if macOS selects built-in speakers. |
| Built-in speakers | Connect headphones | Only Silentio's own mute/volume change is restored. |
| Shared built-in speaker/headphone output | Connect headphones while Silentio has muted speakers | No mute/volume write to the headphones; restoration is deferred. |
| Non-speaker output | Switch to another non-speaker output | No mute or player pause. |
| Any output | Disconnect and reconnect inside the mute delay | Pending mute is canceled. |
| Built-in speakers | Wake from sleep | Mute only when the wake preference is enabled. |
| Onboarding not completed | Wake from sleep | No speaker changes. |

Also verify:

1. Build and run in Xcode with no build warnings.
2. Automation allowed and denied for Spotify, Music, and VLC, each while playing,
   paused, stopped, and not running. Denial must show an error in Settings.
3. First launch, onboarding, Settings, the menu-bar menu, and Launch at Login from
   an app installed in `/Applications`.
4. Stable and beta Sparkle update checks from a signed release build.
5. The unified log for `com.vd.Silentio` has no unexpected errors.

---

## 7. High-Value Code Anchors

- Mute/pause decision flow: `handle(_:)`, `handleSpeakerActivation()`, and
  `handleSpeakerDeactivation()` in `Silentio/App/AppDelegate.swift`
- Device listeners: `Silentio/Audio/AudioDeviceMonitor.swift`
- Speaker classification: `Silentio/Audio/AudioDevice.swift`
- Mute and restore rules: `DeviceMuter` in `Silentio/Audio/DeviceMuter.swift`
- Player commands and Automation errors: `Silentio/Players/AppleScriptPlayer.swift`
  and `PlayerRegistry.swift`
- Settings and defaults: `Silentio/Models/SilentioSettings.swift`
- Settings and onboarding UI: `Silentio/Views/`
- Sparkle preferences and channels: `Silentio/App/UpdateController.swift`
- Entitlements: `Silentio/Resources/Silentio.entitlements`
- Release source of truth: `semver.txt`
- Release orchestration: `.github/workflows/build-release.yml` and `scripts/release.sh`
- Appcast transformation: `scripts/update_appcast.py`
- Automated checks: `.github/workflows/tests.yml`, `scripts/test.sh`, `tests/`,
  `SilentioTests/`, and `SilentioUITests/`

---

## 8. Change Boundaries for Agents

### Allowed Without Prior Approval

- Focused bug fixes and behavior-preserving refactors with passing tests.
- Tests and documentation that reflect verified behavior.
- UI polish that keeps the established settings and onboarding layout.

### Ask the Maintainer First

- Changes to speaker classification, mute/restore rules, or when players pause.
- Entitlement, sandbox, or Apple Events changes, including new players.
- `UserDefaults` schema changes that need migration.
- Substantial UI redesigns.
- New Swift packages, other dependencies, or external services.
- Release workflow, version parser, signing, or appcast behavior changes.
- Deleting releases, moving tags, or changing branch-protection behavior.

### Never Do

- Write mute or volume to outputs other than built-in speakers, or restore state
  Silentio did not change.
- Control real players or change real audio devices in automated tests.
- Add tracking, telemetry, analytics, or unrelated network calls.
- Commit `dist/`, `build/`, `DerivedData/`, `xcuserdata/`, secrets, tokens,
  certificates, private keys, Sparkle keys, or Apple IDs.
- Reuse another app's Sparkle key.
- Add `print()` or `NSLog()` diagnostics to shipped Swift code.
- Remove `semver.txt` history or edit generated appcast entries by hand.
- Force-push release tags or commit directly to `main`.
- Introduce large unrelated formatting changes.
- Change or remove copyright or license headers without explicit instruction.

---

## 9. Common Failure Modes

- **Tests launch the full app (onboarding, muting):** Unit-test mode is detected
  from `SILENTIO_UNIT_TESTING` or `XCTestConfigurationFilePath`. The scheme's Test
  action must keep `shouldUseLaunchSchemeArgsEnv = "NO"` so its own environment
  applies.
- **Tests hang or fail to launch:** A running Silentio instance blocks the test
  host. Quit it, or press Stop in Xcode if it is paused in the debugger.
- **UI test fails in CI or over SSH:** It needs a logged-in graphical session;
  CI uses `--unit-only` for this reason.
- **Players are not paused:** Automation was denied or never requested. Check
  **System Settings → Privacy & Security → Automation**; reset with
  `tccutil reset AppleEvents com.vd.Silentio`.
- **`codesign` fails with "resource fork, Finder information, or similar
  detritus":** Cloud-synced folders (for example iCloud Drive) add extended
  attributes. Build outside the checkout with `OUTPUT_DIR`; `scripts/test.sh`
  already uses a temporary folder.
- **Build fails with missing entitlements:** Signing must preserve the app's
  entitlements (`--preserve-metadata=entitlements`); `scripts/build.sh` verifies
  them after signing.
- **No signing certificate:** Configure the development team in Xcode, or pass
  `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` to `scripts/build.sh`.
- **Release skipped:** Test-only/documentation-only changes are intentionally
  ignored. On `main`, `semver.txt` must change. Other branches must use the
  `feature/*` naming convention or `workflow_dispatch`.
- **Appcast push rejected:** Verify the GitHub App credentials, Contents write
  permission, installation, and branch-protection bypass described in `BUILD.md`.
- **Sparkle version mismatch:** Keep `SPARKLE_VERSION` in the release workflow in
  sync with `Package.resolved`; the release tests enforce this.
- **Sparkle update not visible:** Check channel selection, appcast caching, build
  numbers, and the enclosure URL before republishing.
- **Actionlint reports `app-id`/`client-id`:** `.github/actionlint.yaml` suppresses
  only the stale schema warning for the current floating v3 action.

---

## 10. Escalation Checklist

Ask before proceeding when a change affects speaker safety, Automation, privacy,
persisted settings, entitlements, release/signing behavior, dependencies, or the
product's UI structure. For ordinary focused fixes, tests, and small refactors,
proceed on a feature branch and open a pull request. Use the
`silentio-readiness` skill (`.github/skills/`) before committing or opening a
pull request.

---

*Last updated: 2026-10-25. Keep this file synchronized with architecture,
testing, and release-workflow changes.*
