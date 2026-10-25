import AppKit
import CoreAudio
import Foundation
import Testing

@testable import Silentio

@MainActor
private final class TestMonitor: AudioMonitoring {
    var currentDevice: AudioDevice?
    var onDeviceChange: ((AudioDeviceMonitor.DeviceChange) -> Void)?
    var starts = 0
    var stops = 0
    var refreshes = 0

    func startMonitoring() { starts += 1 }
    func stopMonitoring() { stops += 1 }
    func refreshCurrentDevice() { refreshes += 1 }

    func send(_ change: AudioDeviceMonitor.DeviceChange, device: AudioDevice?) {
        currentDevice = device
        onDeviceChange?(change)
    }
}

@MainActor
private final class TestSpeakerProperties: SpeakerAudioProperties {
    var mute: UInt32 = 0
    var writes: [UInt32] = []
    func deviceUID(_ id: AudioDeviceID) -> String { "test-speakers" }
    func isBuiltInSpeaker(_ id: AudioDeviceID) -> Bool { true }
    func readMute(on id: AudioDeviceID) -> UInt32? { mute }
    func canSetMute(on id: AudioDeviceID) -> Bool { true }
    func setMute(_ value: UInt32, on id: AudioDeviceID) -> Bool {
        mute = value
        writes.append(value)
        return true
    }
    func readVolume(on id: AudioDeviceID) -> Float? { nil }
    func canSetVolume(on id: AudioDeviceID) -> Bool { false }
    func setVolume(_ value: Float, on id: AudioDeviceID) -> Bool {
        Issue.record("Mute-capable speakers must not use the volume fallback")
        return false
    }
}

@MainActor
private final class MonitoringFixture {
    let domain = "MonitoringFlowTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let settings: SilentioSettings
    let monitor = TestMonitor()
    let audio = TestSpeakerProperties()
    let delegate: AppDelegate
    let speakers = AudioDevice(
        id: 123, name: "Test Speakers", uid: "test-speakers",
        transportType: .builtIn, dataSource: 0x6973_706B)
    let headphones = AudioDevice(
        id: 124, name: "Test Headphones", uid: "test-headphones",
        transportType: .usb, dataSource: nil)

    init() throws {
        defaults = try #require(UserDefaults(suiteName: domain))
        settings = SilentioSettings(defaults: defaults)
        settings.hasCompletedOnboarding = true
        settings.enabledPlayers = []
        delegate = AppDelegate(
            monitor: monitor, muter: DeviceMuter(audio: audio), settings: settings,
            players: PlayerRegistry(settings: settings, players: []))
        delegate.setupMonitoring()
    }

    func cleanUp() {
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification))
        defaults.removePersistentDomain(forName: domain)
    }
}

@MainActor
struct MonitoringFlowTests {
    @Test func speakerActivationMutesAndReconnectRestores() throws {
        let f = try MonitoringFixture()
        defer { f.cleanUp() }
        #expect(f.monitor.starts == 1)
        f.monitor.send(.speakersActivated, device: f.speakers)
        #expect(f.audio.writes == [1])
        f.monitor.send(.speakersDeactivated, device: f.headphones)
        #expect(f.audio.writes == [1, 0])
        f.monitor.send(.otherOutputChanged, device: f.headphones)
        #expect(f.audio.writes == [1, 0])
    }

    @Test(arguments: [true, false])
    func incompleteOnboardingOrDisabledMonitoringIgnoresChanges(onboarding: Bool) throws {
        let f = try MonitoringFixture()
        defer { f.cleanUp() }
        f.settings.hasCompletedOnboarding = onboarding
        f.settings.isMonitoringEnabled = !onboarding
        f.monitor.send(.speakersActivated, device: f.speakers)
        #expect(f.audio.writes.isEmpty)
    }

    @Test func muteAndRestorePreferencesAreRespected() throws {
        let f = try MonitoringFixture()
        defer { f.cleanUp() }
        f.settings.muteOnDisconnect = false
        f.monitor.send(.speakersActivated, device: f.speakers)
        #expect(f.audio.writes.isEmpty)
        f.settings.muteOnDisconnect = true
        f.monitor.send(.speakersActivated, device: f.headphones)
        #expect(f.audio.writes.isEmpty)
        f.monitor.send(.speakersActivated, device: f.speakers)
        f.settings.unmuteOnReconnect = false
        f.monitor.send(.speakersDeactivated, device: f.headphones)
        #expect(f.audio.writes == [1])
    }

    @Test(arguments: [true, false])
    func enablingMonitoringOnlyMutesWhenRequested(muteOnStart: Bool) throws {
        let f = try MonitoringFixture()
        defer { f.cleanUp() }
        f.monitor.currentDevice = f.speakers
        f.settings.muteWhenMonitoringStarts = muteOnStart
        f.delegate.setMonitoringEnabled(false)
        f.delegate.setMonitoringEnabled(false)
        #expect(!f.settings.isMonitoringEnabled)
        f.delegate.setMonitoringEnabled(true)
        #expect(f.settings.isMonitoringEnabled)
        #expect(f.audio.writes == (muteOnStart ? [1] : []))
        #expect(f.monitor.refreshes == (muteOnStart ? 1 : 0))
    }

    @Test func enablingMonitoringDoesNotMuteHeadphones() throws {
        let f = try MonitoringFixture()
        defer { f.cleanUp() }
        f.monitor.currentDevice = f.headphones
        f.delegate.setMonitoringEnabled(false)
        f.delegate.setMonitoringEnabled(true)
        #expect(f.monitor.refreshes == 1)
        #expect(f.audio.writes.isEmpty)
    }

    @Test func delayedMuteRunsAndVerificationReappliesSystemRevertedMute() async throws {
        let f = try MonitoringFixture()
        defer { f.cleanUp() }
        f.settings.muteDelay = 0.03
        f.monitor.send(.speakersActivated, device: f.speakers)
        #expect(f.audio.writes.isEmpty)
        try await waitForWrites([1], on: f.audio)
        #expect(f.audio.writes == [1])
        f.audio.mute = 0
        try await waitForWrites([1, 1], on: f.audio)
        #expect(f.audio.writes == [1, 1])
        f.monitor.send(.speakersDeactivated, device: f.headphones)
        #expect(f.audio.writes == [1, 1, 0])
        try await Task.sleep(for: .milliseconds(1100))
        #expect(f.audio.writes == [1, 1, 0])
    }

    @Test(arguments: ["reconnect", "disable", "preference", "device", "terminate"])
    func pendingMuteIsInvalidated(reason: String) async throws {
        let f = try MonitoringFixture()
        defer { f.cleanUp() }
        f.settings.muteDelay = 0.03
        f.monitor.send(.speakersActivated, device: f.speakers)
        switch reason {
        case "reconnect": f.monitor.send(.speakersDeactivated, device: f.headphones)
        case "disable": f.delegate.setMonitoringEnabled(false)
        case "preference": f.settings.muteOnDisconnect = false
        case "device": f.monitor.currentDevice = f.headphones
        default:
            f.delegate.applicationWillTerminate(
                Notification(name: NSApplication.willTerminateNotification))
            #expect(f.monitor.stops == 1)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(f.audio.writes.isEmpty)
    }

    private func waitForWrites(_ writes: [UInt32], on audio: TestSpeakerProperties) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while audio.writes != writes && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
