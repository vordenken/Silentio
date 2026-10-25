import Foundation

/// Apple Music player control.
nonisolated final class AppleMusicPlayer: AppleScriptPlayer {
    init() {
        super.init(
            bundleIdentifier: "com.apple.Music",
            displayName: "Apple Music"
        )
    }
}
