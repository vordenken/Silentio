import Foundation

/// Spotify player control.
nonisolated final class SpotifyPlayer: AppleScriptPlayer {
    init() {
        super.init(
            bundleIdentifier: "com.spotify.client",
            displayName: "Spotify"
        )
    }
}
