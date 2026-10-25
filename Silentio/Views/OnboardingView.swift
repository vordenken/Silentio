import SwiftUI

/// Onboarding shown on first launch. Introduces the app and collects the
/// most relevant settings before the user starts using Silentio.
struct OnboardingView: View {
    @ObservedObject private var settings = SilentioSettings.shared
    @ObservedObject private var updates = UpdateController.shared
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                featuresSection
                preferencesSection
                menuBarHint
            }
            .padding(24)

            Divider()

            footer
                .padding(20)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Silentio")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Silentio keeps your Mac quiet when it should be.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What Silentio does")
                .font(.headline)

            FeatureRow(
                icon: "speaker.slash",
                color: .red,
                title: "Mute on disconnect",
                subtitle:
                    "Internal speakers are muted automatically when headphones are disconnected."
            )
            FeatureRow(
                icon: "headphones",
                color: .blue,
                title: "Pause your music",
                subtitle:
                    "Spotify, Apple Music, and VLC pause automatically so nothing plays out loud."
            )
            FeatureRow(
                icon: "moon.zzz",
                color: .indigo,
                title: "Mute on wake",
                subtitle: "Speakers are muted when your Mac wakes from sleep."
            )
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preferences")
                .font(.headline)

            Toggle(
                Localizable.Settings.launchAtLogin,
                isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        applyLaunchAtLogin(newValue)
                    }
                ))

            Toggle(Localizable.Settings.muteOnDisconnect, isOn: $settings.muteOnDisconnect)
            Toggle(Localizable.Settings.pauseOnDisconnect, isOn: $settings.pauseOnDisconnect)
            Toggle(Localizable.Settings.muteOnWake, isOn: $settings.muteOnWake)
            Toggle(Localizable.Settings.checkAutomatically, isOn: $updates.automaticallyChecks)
        }
    }

    // MARK: - Menu bar hint

    private var menuBarHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    Color.accentColor.gradient,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Find Silentio in the menu bar")
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    "Look for the audio plug icon at the top of your screen. Click it to open the menu and settings."
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            Color.accentColor.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Skip") {
                finish()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Get Started") {
                finish()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func finish() {
        onFinish()
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            (NSApp.delegate as? AppDelegate)?.launchAtLoginDidChange(enabled)
        }
    }
}

/// A single feature row in the onboarding.
private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
