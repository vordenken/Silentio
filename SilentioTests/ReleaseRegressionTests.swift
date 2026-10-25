import Foundation
import Testing

@testable import Silentio

@MainActor
struct ReleaseRegressionTests {
    @Test(arguments: [-10.0, 100.0, .nan, .infinity, -.infinity, 2.5, 0, 5])
    func runtimeDelayIsValidatedAndPersisted(value: Double) throws {
        let name = "ReleaseRegressionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SilentioSettings(defaults: defaults)
        settings.muteDelay = value
        let expected = value.isFinite ? min(max(value, 0), 5) : 0
        #expect(settings.muteDelay == expected)
        #expect(defaults.double(forKey: "muteDelay") == expected)
        #expect(SilentioSettings(defaults: defaults).muteDelay == expected)
    }

    @Test(arguments: [true, false], [true, false])
    func wakeRequiresCompletedOnboarding(completed: Bool, enabled: Bool) throws {
        let name = "ReleaseRegressionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SilentioSettings(defaults: defaults)
        settings.hasCompletedOnboarding = completed
        settings.muteOnWake = enabled
        #expect(settings.shouldMuteOnWake == (completed && enabled))
    }

    @Test(arguments: ["com.spotify.client", "com.apple.Music", "org.videolan.vlc"])
    func playerCommandsPreservePlayerSpecificPauseSemantics(bundleIdentifier: String) throws {
        let players: [any PlayerController] = [SpotifyPlayer(), AppleMusicPlayer(), VLCPlayer()]
        let player = try #require(players.first { $0.bundleIdentifier == bundleIdentifier })
        let command =
            bundleIdentifier == "org.videolan.vlc"
            ? "if playing then play" : "if player state is playing then pause"
        #expect(
            player.pauseScript == """
                if application id "\(bundleIdentifier)" is running then
                    tell application id "\(bundleIdentifier)"
                        \(command)
                    end tell
                end if
                """)
    }

    @Test
    func successfulAppleScriptHasNoAutomationError() {
        #expect(AppleScriptPlayer.execute(script: "return 1", displayName: "Test Player") == nil)
        let player = LocalScriptPlayer(bundleIdentifier: "test.player", displayName: "Test Player")
        #expect(player.pause() == nil)
    }

    nonisolated private final class LocalScriptPlayer: AppleScriptPlayer {
        override var pauseScript: String { "return 1" }
    }

    @Test
    func deniedAutomationExplainsHowToGrantPermission() {
        let error = AppleScriptPlayer.execute(
            script: "error \"Permission denied\" number -1743", displayName: "Test Player"
        )
        #expect(
            error
                == "Allow Silentio to control Test Player in System Settings → Privacy & Security → Automation."
        )
    }

    @Test
    func failedAutomationIncludesPlayerAndErrorContext() {
        let error = AppleScriptPlayer.execute(
            script: "error \"Playback unavailable\" number -10000", displayName: "Test Player"
        )
        #expect(error == "Could not pause Test Player: Playback unavailable")
    }
}
