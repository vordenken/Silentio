import Foundation
import os

/// Central, observable app settings, stored in `UserDefaults`.
@MainActor
final class SilentioSettings: ObservableObject {
    private static let logger = Logger(subsystem: "com.vd.Silentio", category: "Settings")
    static let shared = SilentioSettings()

    // MARK: - Keys
    private enum Key {
        static let muteOnDisconnect = "muteOnDisconnect"
        static let unmuteOnReconnect = "unmuteOnReconnect"
        static let pauseOnDisconnect = "pauseOnDisconnect"
        static let muteOnWake = "muteOnWake"
        static let muteDelay = "muteDelay"
        static let enabledPlayers = "enabledPlayers"
        static let launchAtLogin = "launchAtLogin"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let alwaysPausePlayers = "alwaysPausePlayers"
        static let monitorAtStartup = "monitorAtStartup"
        static let muteWhenMonitoringStarts = "muteWhenMonitoringStarts"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Register defaults so the app behaves sensibly on first launch.
        defaults.register(defaults: [
            Key.muteOnDisconnect: true,
            Key.unmuteOnReconnect: true,
            Key.pauseOnDisconnect: true,
            Key.muteOnWake: true,
            Key.muteDelay: 0.0,
            Key.enabledPlayers: ["com.spotify.client", "com.apple.Music", "org.videolan.vlc"],
            Key.launchAtLogin: false,
            Key.hasCompletedOnboarding: false,
            Key.alwaysPausePlayers: false,
            Key.monitorAtStartup: true,
            Key.muteWhenMonitoringStarts: true,
        ])

        // Initialize stored properties from defaults.
        // (didSet is not called during initialization, which is fine here.)
        self.muteOnDisconnect = defaults.bool(forKey: Key.muteOnDisconnect)
        self.unmuteOnReconnect = defaults.bool(forKey: Key.unmuteOnReconnect)
        self.pauseOnDisconnect = defaults.bool(forKey: Key.pauseOnDisconnect)
        self.muteOnWake = defaults.bool(forKey: Key.muteOnWake)
        let storedDelay = defaults.double(forKey: Key.muteDelay)
        self.muteDelay = Self.validatedDelay(storedDelay)
        self.enabledPlayers = Set(defaults.stringArray(forKey: Key.enabledPlayers) ?? [])
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        self.alwaysPausePlayers = defaults.bool(forKey: Key.alwaysPausePlayers)
        self.monitorAtStartup = defaults.bool(forKey: Key.monitorAtStartup)
        self.muteWhenMonitoringStarts = defaults.bool(forKey: Key.muteWhenMonitoringStarts)
        self.isMonitoringEnabled = defaults.bool(forKey: Key.monitorAtStartup)
    }

    // MARK: - Published properties

    /// Mutes the built-in speakers on disconnect.
    @Published var muteOnDisconnect: Bool {
        didSet { defaults.set(muteOnDisconnect, forKey: Key.muteOnDisconnect) }
    }

    /// Unmutes the built-in speakers on reconnect.
    @Published var unmuteOnReconnect: Bool {
        didSet { defaults.set(unmuteOnReconnect, forKey: Key.unmuteOnReconnect) }
    }

    /// Pauses the players on disconnect.
    @Published var pauseOnDisconnect: Bool {
        didSet { defaults.set(pauseOnDisconnect, forKey: Key.pauseOnDisconnect) }
    }

    /// Mutes the built-in speakers when the Mac wakes from sleep.
    @Published var muteOnWake: Bool {
        didSet { defaults.set(muteOnWake, forKey: Key.muteOnWake) }
    }

    /// Delay in seconds before muting.
    @Published var muteDelay: Double {
        didSet {
            let validated = Self.validatedDelay(muteDelay)
            if muteDelay != validated { muteDelay = validated }
            defaults.set(muteDelay, forKey: Key.muteDelay)
        }
    }

    /// List of enabled player bundle identifiers.
    @Published var enabledPlayers: Set<String> {
        didSet { defaults.set(Array(enabledPlayers), forKey: Key.enabledPlayers) }
    }

    /// Whether the app should launch automatically at login.
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    /// Whether the user has completed the onboarding flow.
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// Pauses the enabled players whenever the default output changes, not only on disconnect.
    @Published var alwaysPausePlayers: Bool {
        didSet { defaults.set(alwaysPausePlayers, forKey: Key.alwaysPausePlayers) }
    }

    /// Whether monitoring is enabled when the app launches.
    @Published var monitorAtStartup: Bool {
        didSet { defaults.set(monitorAtStartup, forKey: Key.monitorAtStartup) }
    }

    /// Mutes the built-in speakers when monitoring is enabled while they are the active output.
    @Published var muteWhenMonitoringStarts: Bool {
        didSet { defaults.set(muteWhenMonitoringStarts, forKey: Key.muteWhenMonitoringStarts) }
    }

    /// Runtime enable/disable state toggled from the menu bar; starts from `monitorAtStartup`.
    @Published var isMonitoringEnabled: Bool

    // MARK: - Convenience

    var shouldMuteOnWake: Bool {
        hasCompletedOnboarding && isMonitoringEnabled && muteOnWake
    }

    var shouldMuteWhenMonitoringStarts: Bool {
        hasCompletedOnboarding && isMonitoringEnabled && muteWhenMonitoringStarts
    }

    /// Whether players should be paused for a given output change.
    func shouldPausePlayers(for change: AudioDeviceMonitor.DeviceChange) -> Bool {
        guard hasCompletedOnboarding, isMonitoringEnabled else { return false }
        if alwaysPausePlayers { return true }
        return change == .speakersActivated && pauseOnDisconnect
    }

    private static func validatedDelay(_ value: Double) -> Double {
        let validated = value.isFinite ? min(max(value, 0), 5) : 0
        if validated != value {
            logger.error(
                "Mute delay must be finite and between 0 and 5 seconds; correcting invalid preference"
            )
        }
        return validated
    }

    /// Checks whether a player (by bundle ID) is enabled.
    func isPlayerEnabled(_ bundleIdentifier: String) -> Bool {
        enabledPlayers.contains(bundleIdentifier)
    }

    /// Enables or disables a player.
    func setPlayerEnabled(_ bundleIdentifier: String, enabled: Bool) {
        if enabled {
            enabledPlayers.insert(bundleIdentifier)
        } else {
            enabledPlayers.remove(bundleIdentifier)
        }
    }
}
