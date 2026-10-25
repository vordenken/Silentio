import Foundation

/// VLC player control.
nonisolated final class VLCPlayer: AppleScriptPlayer {
    override var pauseScript: String {
        // VLC's play command toggles playback; never send it to a paused player.
        """
        if application id "\(bundleIdentifier)" is running then
            tell application id "\(bundleIdentifier)"
                if playing then play
            end tell
        end if
        """
    }

    init() {
        super.init(
            bundleIdentifier: "org.videolan.vlc",
            displayName: "VLC"
        )
    }
}
