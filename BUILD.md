# Building & Releasing

## 🔨 Build from Source

### Prerequisites

- macOS 13 or later (macOS 14 or later to run the tests)
- Xcode 26 or later (Swift 6.2+ toolchain, macOS SDK)
- Sparkle (the only dependency, resolved automatically through Swift Package Manager)

### Run from Xcode

Open [Silentio.xcodeproj](Silentio.xcodeproj), select the **Silentio** scheme and
press **Run** (⌘R). On first launch Silentio shows its welcome window; afterwards it
lives in the menu bar (no Dock icon). **Product › Test** (⌘U) runs all unit and UI
tests. To review the update reminder without a newer release, enable the
`--preview-update-reminder` argument (Debug builds only) under
**Product › Scheme › Edit Scheme… › Run › Arguments**.

| Target | Product |
| --- | --- |
| `Silentio` | Sandboxed menu bar app (SwiftUI/AppKit, CoreAudio, Apple Events) |
| `SilentioTests` | XCTest and Swift Testing unit tests, hosted by the app |
| `SilentioUITests` | UI test for the status item and settings window lifecycle |

In unit tests the app detects its XCTest host and skips onboarding, audio
monitoring, wake handling, login-item registration and Sparkle. UI tests launch the
app with `SILENTIO_UI_TESTING=1`. Neither mode exists in Release builds.

### Universal release build

```bash
git clone https://github.com/vordenken/Silentio.git
cd Silentio
bash scripts/build.sh
open dist/Silentio.app
```

The [build script](scripts/build.sh):

1. Reads the version from line 1 of [semver.txt](semver.txt) and validates it.
2. Runs `xcodebuild` in Release for `arm64` and `x86_64` with that version, using a
   temporary DerivedData folder outside the checkout.
3. Strips local paths from the binary and fails if a `/Users/` path remains.
4. Signs Sparkle's nested services and the app with the hardened runtime, keeping the
   app's sandbox and Apple Events entitlements, then verifies signatures, entitlements
   and architectures. Local builds use ad-hoc signing; CI supplies its certificate.
5. Writes `dist/Silentio.app` and `dist/Silentio.zip`.

The script prints Xcode's full build output and progress markers before each signing
operation, verification and packaging. If a CI build stops making progress, inspect
the last command after the most recent `==>` marker to distinguish compilation from
a signing or packaging stall. Do not enable shell tracing (`set -x`) in release jobs,
because it can expose signing credentials.

The Bash-only build script accepts these environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `BUILD_NUMBER` | Xcode project's `CURRENT_PROJECT_VERSION` | Positive integer for `CFBundleVersion`; CI uses its workflow run number + 10 |
| `CODE_SIGN_IDENTITY` | `-` (ad-hoc) | Certificate name or SHA-1 identity for the app and all nested code |
| `DEVELOPMENT_TEAM` | Xcode project setting | Team for certificate-signed builds; CI uses `NRKZZ9TFF7` |
| `OUTPUT_DIR` | `dist/` | Output folder; choose a non-cloud-synced folder if Finder metadata breaks verification |

For example:

```bash
BUILD_NUMBER=11 CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=NRKZZ9TFF7 \
  OUTPUT_DIR=/tmp/Silentio-release bash scripts/build.sh
```

### Test

```bash
bash scripts/test.sh
```

The [validation script](scripts/test.sh) runs Swift formatting lint, Bash syntax
checks, appcast validation, the Python release-pipeline tests and all Xcode unit
and UI tests. **Production line coverage of the app must be greater than 80%.**
CoreAudio listeners and Apple Events need real hardware and permissions, so the
deterministic tests cover the output and restoration rules, settings, player
commands, the update controller and the window lifecycle instead. The app delegate
uses an injected monitor and speaker backend in tests to exercise delayed muting,
cancellation and restoration without changing real devices. Player dispatcher
tests use synthetic scripts without controlling installed players.

The UI test drives the real menu bar and settings window and needs a logged-in
graphical session. `bash scripts/test.sh --unit-only` runs the same checks but
skips the UI test and the coverage gate. A running Silentio instance prevents the
test host from launching; quit it before running the tests.

### Continuous Integration

[`.github/workflows/tests.yml`](.github/workflows/tests.yml) runs on pull requests
and on pushes to `main` and `feature/*` that touch code, scripts or workflows:

- `actionlint` validates the workflows on Ubuntu.
- `bash scripts/test.sh --unit-only` runs on the arm64 `xcode-27` runner
  (macOS 27, public preview), matching the release toolchain.

The UI test and the coverage gate run only locally. Run the full
`bash scripts/test.sh` before opening a pull request.

The [feature specification](features/speaker-protection.feature) documents the
behavior covered by the tests.

> [!NOTE]
> The scripts build in a temporary folder because cloud-synced folders (iCloud
> Drive, file providers) add Finder metadata that code signing rejects. Xcode's
> default DerivedData location is not affected.

### Icons

The original app artwork is [Design/AppIcon-master.png](Design/AppIcon-master.png).
The menu bar icon is a separate vector template drawn in code. Regenerate them with:

```bash
bash scripts/generate-app-icon.sh
swift scripts/generate-menu-bar-icon.swift
```

Commit the generated files in `Silentio/Resources/Assets.xcassets`.

## 🚀 How to Release

Releases are automated by
[`.github/workflows/build-release.yml`](.github/workflows/build-release.yml).
Its release logic lives in [scripts/release.sh](scripts/release.sh); both local and
CI app builds use [scripts/build.sh](scripts/build.sh).

### Version and release notes

[semver.txt](semver.txt) is the version and release-notes source of truth.
Set a strict `MAJOR.MINOR.PATCH` version on line 1 and describe changes after `---`:

```text
1.1.0
---
### ✨ What's New

- Added something useful

### 🐛 Bug Fixes

- Fixed something annoying

## 1.0.0
...previous release notes...
```

- **Line 1:** Current version (strict [semver](https://semver.org/) `MAJOR.MINOR.PATCH`)
- **`---`:** Separator
- **Lines after `---`:** Changelog for the current version (Markdown list items, optional headings prefixed by `###`)
- **`## x.y.z`:** Previous release changelogs (preserved history)

Move the notes of the previous release into a `## x.y.z` section at the bottom
so the file keeps the full history. CI and the local build script inject the version
into `CFBundleShortVersionString` without editing the checkout. Keep the project's
`MARKETING_VERSION` in sync for Xcode builds. After a release, keep its checked-in
`CURRENT_PROJECT_VERSION` aligned with the latest published build, so local Xcode
builds are not offered an older update. No release has been published yet.

### Branches and publishing

1. Create a `feature/*` branch and update `semver.txt`.
2. A release-relevant push creates the next beta, such as `v1.0.0-beta1`,
   `v1.0.0-beta2`, and so on. Beta numbering is shared across feature branches.
3. Merge into `main` with a changed `semver.txt` to publish the stable `v1.0.0`.

`bugfix/*` and `hotfix/*` do not publish betas. Documentation-only, repository
metadata, test-only, design, feature-specification and generated appcast changes do
not trigger a release. Manual `workflow_dispatch` accepts only `main` (stable) or
`feature/*` (beta); other branches fail explicitly. The first push to a new
repository counts as a release-relevant change.

Every release runs lint and unit tests **before importing signing credentials**,
builds the universal app with the run number + 10 as `CFBundleVersion`, creates and
certificate-signs `Silentio.dmg`, and adds its Sparkle EdDSA signature to the feed.
Sparkle tools are pinned to `Package.resolved` (currently 2.10.0). The published
GitHub Release uses the tag as its title, contains the DMG, release notes,
Gatekeeper and Automation instructions, and is marked as a prerelease for betas.

After importing the certificate, `python3 scripts/check_signing.py` diagnoses signing
on temporary copies of `/usr/bin/true`, first without and then with a timestamp.
Each signing attempt has a 90-second timeout and each verification has a 30-second
timeout. A failure stops the release before the build; no keychain settings or
release signing options are changed. If the first probe fails, investigate key
access and certificate trust. If only the timestamped probe fails, investigate the
timestamp service/network and the printed `codesign` errors.

Release jobs are serialized across all branches and are never cancelled while
running. Existing tags are never moved, and existing releases/assets are not
overwritten. A retry before publication reuses the beta tag for the same commit.
If the release already exists, the workflow stops before rebuilding or signing.

The canonical [appcast.xml](appcast.xml) is read from `main` for every release and
updated on `main` **only after** the release is published. All stable entries and
the five newest betas are retained. Do not edit the generated feed manually during
normal development.

If publication succeeds but pushing the appcast fails, download the matching
`Silentio-vX.Y.Z[-betaN]` workflow artifact. It contains both the **original DMG
and its signed appcast**. Check the feed against current `main`, then restore it
through the authorized maintainer/bot process. Never rebuild or replace that
release's DMG: the feed signature and length must describe the original bytes.

### Repository setup and secrets

Enable Actions and
[private vulnerability reporting](https://docs.github.com/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository)
before the first release. Configure:

| Secret / Variable | Required | Description |
| --- | --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Yes | Base64-encoded `.p12` signing identity |
| `P12_PASSWORD` | Yes | Password of that `.p12` file |
| `SPARKLE_PRIVATE_KEY` | Yes | Silentio's own EdDSA private key; never reuse another app's key |
| `CLIENT_ID` (variable) | For protected `main` | GitHub App client ID |
| `APP_PRIVATE_KEY` | With `CLIENT_ID` | GitHub App private key |

In GitHub, open **Settings → Secrets and variables → Actions**. Use
**Secrets → New repository secret** for the four secrets and
**Variables → New repository variable** for `CLIENT_ID`. Use repository scope, not
an environment: this workflow does not select a GitHub environment. Paste values
only, without shell assignments or surrounding quotes.

- **`BUILD_CERTIFICATE_BASE64`:** Export the signing identity from Keychain Access
  as a password-protected `.p12`, including its private key, then run
  `base64 -i certificate.p12 | pbcopy` on macOS. Paste that Base64 text, not the
  file path or a `.cer`.
- **`P12_PASSWORD`:** Paste that `.p12` export password unchanged, not Base64.
- **`SPARKLE_PRIVATE_KEY`:** Locate Sparkle's `bin/generate_keys` in the Silentio
  DerivedData `SourcePackages/artifacts/sparkle/Sparkle` folder. First run
  `generate_keys --account silentio -p` and compare its public output with
  `SUPublicEDKey` in [Info.plist](Silentio/Resources/Info.plist). Stop on any
  mismatch. Export with `generate_keys --account silentio -x /private/export/path`,
  using a new file in an owner-only temporary directory (`umask 077`). Paste the
  exported file's text **unchanged**: it is already Base64. Do not encode it again
  or substitute another app's key. Securely back it up and remove the temporary export.
- **`APP_PRIVATE_KEY`:** Paste the entire private-key `.pem` downloaded from the
  GitHub App settings, including the `BEGIN` and `END` lines. Preserve actual
  newlines; do not Base64-encode the file or insert literal `\n` sequences.
- **`CLIENT_ID`:** Paste the same GitHub App's Client ID as a repository variable,
  not its numeric App ID or Installation ID. When reusing an existing App (for
  example CoreTamer's), add Silentio to its installation without removing other
  repositories, and allow that App to bypass Silentio's protected-branch rules for
  direct appcast pushes. `scripts/release.sh` recognizes `silentio-ci-bot` and
  `coretamer-ci-bot`; add the App's name there if you use a different one.

GitHub does not reveal stored secret values or copy repository secrets between
repositories. Use the original files/password manager; never commit key material
or paste it into logs or chat. Clear the clipboard after setup. `GITHUB_TOKEN`
is supplied automatically; this workflow needs no PAT or notarization secrets.

The certificate must contain exactly one valid signing identity for team
`NRKZZ9TFF7`. The workflow imports it into a temporary keychain and deletes the
certificate/keychain even when a later step fails. The import explicitly trusts
`/usr/bin/codesign` for private-key access (`-T`), in addition to setting the key
partition list, so signing does not require interactive Keychain approval. The
Sparkle private key is written only to an owner-readable temporary file and
deleted on exit.

For protected `main`, install a GitHub App with **Contents: Read & Write** on the
repository and allow it to bypass the rule that prevents the generated appcast
commit. The workflow otherwise uses `GITHUB_TOKEN`; enable its Contents write
permission. Feature branches should regularly merge `main` because feed commits
advance it.

The selected release action is `softprops/action-gh-release@v3`;
other actions are official `actions/*`.

### Local validation before publishing

```bash
bash scripts/test.sh
bash scripts/build.sh
actionlint
lipo -archs dist/Silentio.app/Contents/MacOS/Silentio
codesign --verify --deep --strict --verbose=2 dist/Silentio.app
codesign -d --entitlements - dist/Silentio.app
```

The `lipo` result must contain `arm64` and `x86_64`, and the entitlements must still
include the App Sandbox, network client and Apple Events access. Then perform the
manual device and Automation tests listed in [AGENTS.md](AGENTS.md). Release-script
regression tests run with the normal test command and can also run separately:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests
```

### Optional: Developer ID signing and notarization

The automated release uses an Apple Development certificate and is **not
notarized**. For distribution without Gatekeeper warnings, use your own Developer
ID certificate and notarize. Keep credentials in the Keychain, never in this
repository. This remains a separate manual process, not part of CI:

```bash
set -euo pipefail
export OUTPUT_DIR=/tmp/Silentio-notarization
CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID bash scripts/build.sh
APP="$OUTPUT_DIR/Silentio.app"
PROFILE="YOUR_NOTARYTOOL_KEYCHAIN_PROFILE"

xcrun notarytool submit "$OUTPUT_DIR/Silentio.zip" --keychain-profile "$PROFILE" --wait

xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"
# Repackage after stapling so the download contains the notarization ticket.
ditto -c -k --norsrc --keepParent "$APP" "$OUTPUT_DIR/Silentio.zip"
```

Running `build.sh` without signing variables produces an ad-hoc build again.
Package and Sparkle-sign updates only **after** any notarization/stapling, since
either operation changes the signed download's bytes.
