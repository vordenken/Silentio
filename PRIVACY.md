# Privacy Policy

Silentio respects your privacy.

## Data Collection

- **No personal data** is collected
- **No analytics** or tracking
- **No audio** is recorded or analyzed
- **No network connections** except update checks via Sparkle (see below)
- **No data** is shared with third parties

## Local Data

Silentio uses CoreAudio to read the default audio output, its active data source,
and the mute state and volume of the built-in speakers. It uses this information
only to detect a switch to the speakers and to mute or restore them. This
information never leaves your Mac.

The following settings are stored locally in the macOS preferences domain
`com.vd.Silentio`:

- Mute, restore, pause and wake behavior, including the mute delay
- Which players Silentio may pause
- Whether monitoring starts automatically and whether the speakers are muted when it starts
- Whether the first-launch welcome has been completed
- Update preferences (automatic checks, automatic downloads, beta versions)

Launch at login is managed by macOS (`SMAppService`) and can be changed in
System Settings.

## Player Control

Silentio pauses Spotify, Apple Music and VLC with Apple Events. macOS asks for
your permission first; you can revoke it at any time under
**System Settings → Privacy & Security → Automation**. Silentio only checks
whether a player is playing and sends a pause command; it does not read your
library, playlists or listening history.

## Software Updates

- Silentio uses the open-source [Sparkle](https://sparkle-project.org) framework to check for and download updates.
- Automatic update checks are enabled by default and can be disabled in Silentio's settings or during the first-launch welcome. Automatic downloads and beta updates are also configurable.
- Sparkle retrieves the update feed from `raw.githubusercontent.com` and update packages from Silentio releases hosted by GitHub.
- These requests disclose standard connection information to GitHub, such as the IP address, request time, requested URL and HTTP metadata required to deliver the update.
- Silentio does not enable Sparkle system profiling and does not attach audio device information, settings or other local data to update requests.

GitHub processes connection data under its own privacy policy.

## Contact

Questions? Open an [issue](https://github.com/vordenken/Silentio/issues).
