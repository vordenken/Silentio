# Security Policy

## Supported Versions

| Version | Supported |
| ------- | ------------------ |
| 1.0.x   | ✅ |
| < 1.0   | ❌ |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it privately:

1. **Do not** open a public issue
2. Use [GitHub's private vulnerability reporting](https://github.com/vordenken/Silentio/security/advisories/new)
3. Include the Silentio version, macOS version, Mac architecture, the audio devices
   and players involved, steps to reproduce and the impact

Please remove usernames, private file paths and other personal data from logs.
You can expect a response within 48 hours.

## Scope

Silentio runs in the macOS App Sandbox. It reads and changes the mute state and
volume of the built-in speakers through CoreAudio, and sends pause commands to
Spotify, Apple Music and VLC through Apple Events only after you allow it under
**System Settings → Privacy & Security → Automation**. Its only network access is
the Sparkle update check and download from GitHub; updates are verified with an
EdDSA signature before installation.
