import SwiftUI

/// Settings view of the app.
struct SettingsView: View {
    @ObservedObject private var settings = SilentioSettings.shared
    @ObservedObject private var playerRegistry = PlayerRegistry.shared
    @ObservedObject var updates = UpdateController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            Form {
                Section(Localizable.Settings.generalSection) {
                    Toggle(
                        Localizable.Settings.launchAtLogin,
                        isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { newValue in
                                settings.launchAtLogin = newValue
                                applyLaunchAtLogin(newValue)
                            }
                        ))
                    Toggle(Localizable.Settings.monitorAtStartup, isOn: $settings.monitorAtStartup)
                    Toggle(
                        Localizable.Settings.muteWhenMonitoringStarts,
                        isOn: $settings.muteWhenMonitoringStarts)
                }

                Section(Localizable.Settings.behaviorSection) {
                    Toggle(Localizable.Settings.muteOnDisconnect, isOn: $settings.muteOnDisconnect)
                    Toggle(
                        Localizable.Settings.unmuteOnReconnect, isOn: $settings.unmuteOnReconnect)
                    Toggle(
                        Localizable.Settings.pauseOnDisconnect, isOn: $settings.pauseOnDisconnect)
                    Toggle(Localizable.Settings.muteOnWake, isOn: $settings.muteOnWake)
                }

                Section(Localizable.Settings.muteDelaySection) {
                    HStack {
                        Text(Localizable.Settings.muteDelayLabel)
                        Slider(value: $settings.muteDelay, in: 0...5, step: 0.5)
                        Text("\(settings.muteDelay, specifier: "%.1f") s")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }

                Section(Localizable.Settings.playersSection) {
                    Toggle(isOn: $settings.alwaysPausePlayers) {
                        Text(Localizable.Settings.alwaysPausePlayers)
                        Text(Localizable.Settings.alwaysPausePlayersDescription)
                    }
                    ForEach(playerRegistry.players, id: \.bundleIdentifier) { player in
                        Toggle(
                            player.displayName,
                            isOn: Binding(
                                get: { settings.isPlayerEnabled(player.bundleIdentifier) },
                                set: {
                                    settings.setPlayerEnabled(player.bundleIdentifier, enabled: $0)
                                }
                            ))
                    }
                    if let error = playerRegistry.lastAutomationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section(Localizable.Settings.updatesSection) {
                    Toggle(
                        Localizable.Settings.checkAutomatically, isOn: $updates.automaticallyChecks)
                    Toggle(
                        Localizable.Settings.downloadAutomatically,
                        isOn: $updates.automaticallyDownloads)
                    Toggle(Localizable.Settings.betaUpdates, isOn: $updates.betaUpdates)
                    Button(Localizable.Settings.checkNow) { updates.checkForUpdates() }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// App header with icon, name, and version.
    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Silentio")
                        .font(.title)
                        .fontWeight(.bold)
                    Text(versionString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(
                    "Automatically mute speakers and pause music when headphones are disconnected."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Reads the marketing version from the bundle.
    private var versionString: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.0"
        return "v\(version)"
    }

    /// Applies the launch-at-login setting via the app delegate.
    private func applyLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            (NSApp.delegate as? AppDelegate)?.launchAtLoginDidChange(enabled)
        }
    }
}
