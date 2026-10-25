import Foundation
import XCTest

@testable import Silentio

final class SilentioSettingsTests: XCTestCase {
    @MainActor
    func testDefaultsAreSafeForFirstLaunch() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SilentioSettings(defaults: defaults)

        XCTAssertTrue(settings.muteOnDisconnect)
        XCTAssertTrue(settings.unmuteOnReconnect)
        XCTAssertTrue(settings.pauseOnDisconnect)
        XCTAssertTrue(settings.muteOnWake)
        XCTAssertEqual(settings.muteDelay, 0)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertEqual(
            settings.enabledPlayers, ["com.spotify.client", "com.apple.Music", "org.videolan.vlc"])
    }

    @MainActor
    func testPreferencesPersistAcrossInstances() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SilentioSettings(defaults: defaults)
        settings.muteOnDisconnect = false
        settings.unmuteOnReconnect = false
        settings.pauseOnDisconnect = false
        settings.muteOnWake = false
        settings.muteDelay = 2.5
        settings.launchAtLogin = true
        settings.hasCompletedOnboarding = true
        settings.setPlayerEnabled("com.spotify.client", enabled: false)

        let restored = SilentioSettings(defaults: defaults)

        XCTAssertFalse(restored.muteOnDisconnect)
        XCTAssertFalse(restored.unmuteOnReconnect)
        XCTAssertFalse(restored.pauseOnDisconnect)
        XCTAssertFalse(restored.muteOnWake)
        XCTAssertEqual(restored.muteDelay, 2.5)
        XCTAssertTrue(restored.launchAtLogin)
        XCTAssertTrue(restored.hasCompletedOnboarding)
        XCTAssertFalse(restored.isPlayerEnabled("com.spotify.client"))
        XCTAssertTrue(restored.isPlayerEnabled("com.apple.Music"))
    }

    @MainActor
    func testPlayerSelectionCanBeEnabledAndDisabled() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SilentioSettings(defaults: defaults)
        settings.setPlayerEnabled("org.videolan.vlc", enabled: false)
        XCTAssertFalse(settings.isPlayerEnabled("org.videolan.vlc"))

        settings.setPlayerEnabled("org.videolan.vlc", enabled: true)
        XCTAssertTrue(settings.isPlayerEnabled("org.videolan.vlc"))
        XCTAssertEqual(SilentioSettings(defaults: defaults).enabledPlayers, settings.enabledPlayers)
    }

    @MainActor
    func testInvalidStoredDelayUsesSupportedRange() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(-10, forKey: "muteDelay")
        XCTAssertEqual(SilentioSettings(defaults: defaults).muteDelay, 0)

        defaults.set(100, forKey: "muteDelay")
        XCTAssertEqual(SilentioSettings(defaults: defaults).muteDelay, 5)

        defaults.set(Double.nan, forKey: "muteDelay")
        XCTAssertEqual(SilentioSettings(defaults: defaults).muteDelay, 0)
    }

    @MainActor
    func testRelaxParityDefaultsAndPersistence() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SilentioSettings(defaults: defaults)
        XCTAssertFalse(settings.alwaysPausePlayers)
        XCTAssertTrue(settings.monitorAtStartup)
        XCTAssertTrue(settings.muteWhenMonitoringStarts)
        XCTAssertTrue(settings.isMonitoringEnabled)

        settings.alwaysPausePlayers = true
        settings.monitorAtStartup = false
        settings.muteWhenMonitoringStarts = false

        let restored = SilentioSettings(defaults: defaults)
        XCTAssertTrue(restored.alwaysPausePlayers)
        XCTAssertFalse(restored.monitorAtStartup)
        XCTAssertFalse(restored.muteWhenMonitoringStarts)
        XCTAssertFalse(restored.isMonitoringEnabled)
    }

    @MainActor
    func testPlayerPauseRules() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SilentioSettings(defaults: defaults)
        XCTAssertFalse(
            settings.shouldPausePlayers(for: .speakersActivated), "No actions before onboarding")

        settings.hasCompletedOnboarding = true
        XCTAssertTrue(settings.shouldPausePlayers(for: .speakersActivated))
        XCTAssertFalse(settings.shouldPausePlayers(for: .speakersDeactivated))
        XCTAssertFalse(settings.shouldPausePlayers(for: .otherOutputChanged))

        settings.alwaysPausePlayers = true
        XCTAssertTrue(settings.shouldPausePlayers(for: .speakersDeactivated))
        XCTAssertTrue(settings.shouldPausePlayers(for: .otherOutputChanged))

        settings.isMonitoringEnabled = false
        XCTAssertFalse(settings.shouldPausePlayers(for: .speakersActivated))
        XCTAssertFalse(settings.shouldMuteOnWake)
        XCTAssertFalse(settings.shouldMuteWhenMonitoringStarts)
    }

    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "SilentioSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
