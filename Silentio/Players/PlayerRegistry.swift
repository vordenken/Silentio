import Combine
import Foundation

/// Manages all known players and pauses the enabled ones.
@MainActor
final class PlayerRegistry: ObservableObject {

    static let shared = PlayerRegistry()

    /// All known players.
    let players: [any PlayerController]

    private let settings: SilentioSettings
    private let pauseQueue = DispatchQueue(
        label: "com.vd.Silentio.player-pause", qos: .userInitiated)
    @Published private(set) var lastAutomationError: String?

    init(
        settings: SilentioSettings = .shared,
        players: [any PlayerController] = [SpotifyPlayer(), AppleMusicPlayer(), VLCPlayer()]
    ) {
        self.settings = settings
        self.players = players
    }

    /// Handles player automation off the main thread, one permission prompt at a time.
    func pauseAllEnabled() {
        lastAutomationError = nil
        let enabled = players.filter {
            settings.isPlayerEnabled($0.bundleIdentifier) && $0.isRunning
        }
        .map { (script: $0.pauseScript, displayName: $0.displayName) }
        guard !enabled.isEmpty else { return }

        pauseQueue.async { [weak self] in
            for item in enabled {
                if let error = AppleScriptPlayer.execute(
                    script: item.script, displayName: item.displayName)
                {
                    DispatchQueue.main.async { [weak self] in
                        self?.lastAutomationError = error
                    }
                }
            }
        }
    }
}
