# Contributing to Silentio

Thanks for your interest in contributing! 🎉

## How to Contribute

1. Fork the repository
2. Create a branch (`feature/my-feature`, `bugfix/my-fix` or `hotfix/my-patch`)
3. Make your changes
4. Run the tests: `bash scripts/test.sh`
5. Update [semver.txt](semver.txt) for user-visible changes
6. Open a pull request

Open pull requests against `main`. Release-relevant pushes to `feature/*` create
beta releases. Use a `feature/*` branch when you need a beta build, including for
bug fixes. The `bugfix/*` and `hotfix/*` prefixes remain valid but do not trigger
beta releases. Stable releases are created from `main` when `semver.txt` changes.

New to pull requests? Check out [How to Contribute to an Open Source Project on GitHub](https://kcd.im/pull-request).

## Guidelines

- Keep changes focused and explain behavior changes in the pull request; include screenshots for UI changes.
- Follow the existing Swift style; format with `xcrun swift-format`.
- Keep the app compatible with macOS 13 and both architectures (arm64 and x86_64).
- Add tests for changed code paths; production line coverage must stay above 80%.
- Update the behavior specification in [features/speaker-protection.feature](features/speaker-protection.feature) when behavior changes.
- Keep user preferences in `SilentioSettings` and player integrations behind `PlayerController`.
- Do not add telemetry, tracking or analytics.
- Never commit build products, credentials, signing material, Sparkle keys or logs with personal data.

Changes to CoreAudio handling, Automation or sleep/wake behavior must also be
tested on a real Mac. For audio bugs, include the Mac model, macOS version,
output device type, whether a shared 3.5 mm jack is involved, and the expected
and actual output transition.

See [BUILD.md](BUILD.md) for build and release details. Contributions are made
under the [GNU GPL v3](LICENSE).
