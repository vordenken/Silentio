import Foundation

/// Protocol for a music player that can be paused.
nonisolated protocol PlayerController {
    /// Bundle identifier of the app (e.g. `com.spotify.client`).
    var bundleIdentifier: String { get }

    /// Display name (e.g. "Spotify").
    var displayName: String { get }

    /// Player-specific command, including guards against starting playback.
    var pauseScript: String { get }

    /// Checks whether the app is currently running.
    @MainActor var isRunning: Bool { get }

    /// Pauses playback and returns a user-visible error message on failure.
    func pause() -> String?
}
