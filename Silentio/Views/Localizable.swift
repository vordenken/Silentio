import SwiftUI

/// Centralized UI strings.
///
/// All user-facing text lives here as `LocalizedStringKey` constants. This keeps
/// the UI in English for now while making it trivial to localize later: the keys
/// can be picked up by `.strings` / `.xcstrings` catalogs without touching the views.
@MainActor
enum Localizable {

    // MARK: - Settings

    @MainActor enum Settings {
        static let behaviorSection = LocalizedStringKey("Behavior")
        static let muteOnDisconnect = LocalizedStringKey("Mute built-in speakers on disconnect")
        static let unmuteOnReconnect = LocalizedStringKey("Unmute on reconnect")
        static let pauseOnDisconnect = LocalizedStringKey("Pause players on disconnect")
        static let muteOnWake = LocalizedStringKey("Mute on wake from sleep")

        static let muteDelaySection = LocalizedStringKey("Mute delay")
        static let muteDelayLabel = LocalizedStringKey("Delay")

        static let generalSection = LocalizedStringKey("General")
        static let launchAtLogin = LocalizedStringKey("Launch at login")
        static let monitorAtStartup = LocalizedStringKey("Monitor at startup")
        static let muteWhenMonitoringStarts = LocalizedStringKey("Mute when monitoring is enabled")
        static let alwaysPausePlayers = LocalizedStringKey("Always pause players")
        static let alwaysPausePlayersDescription = LocalizedStringKey(
            "Pause the selected players whenever the default audio output changes.")

        static let playersSection = LocalizedStringKey("Players")

        static let updatesSection = LocalizedStringKey("Updates")
        static let checkAutomatically = LocalizedStringKey("Check for updates automatically")
        static let downloadAutomatically = LocalizedStringKey("Download automatically")
        static let betaUpdates = LocalizedStringKey("Beta versions")
        static let checkNow = LocalizedStringKey("Check Now…")
    }
}
