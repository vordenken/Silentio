import Combine
import CoreAudio
import Foundation
import os

@MainActor
protocol AudioMonitoring: AnyObject {
    var currentDevice: AudioDevice? { get }
    var onDeviceChange: ((AudioDeviceMonitor.DeviceChange) -> Void)? { get set }
    func startMonitoring()
    func stopMonitoring()
    func refreshCurrentDevice()
}

/// Monitors the default output and reports switches to and from the internal speakers.
@MainActor
final class AudioDeviceMonitor: ObservableObject, AudioMonitoring {
    private let logger = Logger(subsystem: "com.vd.Silentio", category: "AudioMonitoring")

    /// Shared instance used by the app delegate and views.
    static let shared = AudioDeviceMonitor()

    /// Event fired when the default audio output changes.
    nonisolated enum DeviceChange: Equatable {
        /// A non-speaker output changed to the internal speakers.
        case speakersActivated
        /// The internal speakers changed to another output.
        case speakersDeactivated
        /// The output changed between two non-speaker outputs.
        case otherOutputChanged
    }

    /// The current default output device, published so views can observe it.
    @Published private(set) var currentDevice: AudioDevice?

    /// Callback invoked on the main thread when the output device changes.
    var onDeviceChange: ((DeviceChange) -> Void)?

    private var isMonitoring = false
    private var listenedDeviceID: AudioDeviceID?
    private var transitions = OutputTransitionTracker()

    /// Starts monitoring the default audio output.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Set the initial device so views have a value immediately.
        currentDevice = Self.currentDefaultOutputDevice()
        transitions = OutputTransitionTracker(initial: currentDevice)
        updateDataSourceListener(to: currentDevice?.id)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioObjectPropertyListener,
            Unmanaged.passUnretained(self).toOpaque()
        )

        if status != noErr {
            logger.error(
                "Could not monitor default audio output (OSStatus \(status)); restart Silentio to retry"
            )
            updateDataSourceListener(to: nil)
            isMonitoring = false
        } else {
            // Close the gap between reading the initial device and subscribing.
            evaluateDeviceChange()
        }
    }

    /// Stops monitoring.
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        updateDataSourceListener(to: nil)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            audioObjectPropertyListener,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /// Re-reads the current default output device and publishes it.
    func refreshCurrentDevice() {
        evaluateDeviceChange()
    }

    // MARK: - Callback handling

    /// Called by the C callback and bounced to the main thread.
    nonisolated fileprivate func handleDefaultOutputDeviceChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isMonitoring else { return }
            self.evaluateDeviceChange()
        }
    }

    /// Reads the current default output device and determines the change.
    private func evaluateDeviceChange() {
        guard let current = Self.currentDefaultOutputDevice() else {
            currentDevice = nil
            logger.error(
                "Could not read default output device; waiting for the next output notification")
            return
        }

        // Publish the current device so views can observe it.
        currentDevice = current
        updateDataSourceListener(to: current.id)

        if let change = transitions.evaluate(current) {
            onDeviceChange?(change)
        }
    }

    nonisolated static func deviceChange(from previous: AudioDevice, to current: AudioDevice)
        -> DeviceChange?
    {
        if !previous.isBuiltInSpeaker && current.isBuiltInSpeaker { return .speakersActivated }
        if previous.isBuiltInSpeaker && !current.isBuiltInSpeaker { return .speakersDeactivated }
        if !current.isBuiltInSpeaker
            && (previous.uid != current.uid || previous.dataSource != current.dataSource)
        {
            return .otherOutputChanged
        }
        return nil
    }

    /// Some Macs change only the data source when a 3.5 mm jack is unplugged.
    private func updateDataSourceListener(to deviceID: AudioDeviceID?) {
        guard deviceID != listenedDeviceID else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if let previous = listenedDeviceID {
            AudioObjectRemovePropertyListener(
                previous, &address, audioObjectPropertyListener,
                Unmanaged.passUnretained(self).toOpaque())
        }
        listenedDeviceID = nil
        if let deviceID, AudioObjectHasProperty(deviceID, &address) {
            let status = AudioObjectAddPropertyListener(
                deviceID, &address, audioObjectPropertyListener,
                Unmanaged.passUnretained(self).toOpaque())
            if status == noErr {
                listenedDeviceID = deviceID
            } else {
                logger.error(
                    "Could not monitor output data source (OSStatus \(status)); shared-jack transitions may be missed"
                )
            }
        }
    }

    // MARK: - Device reading

    /// Reads the current default output device.
    static func currentDefaultOutputDevice() -> AudioDevice? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            return nil
        }

        return describeDevice(deviceID)
    }

    /// Describes an audio device and its active output data source.
    static func describeDevice(_ deviceID: AudioDeviceID) -> AudioDevice {
        let name = getStringProperty(deviceID, selector: kAudioObjectPropertyName) ?? "Unknown"
        let uid = getStringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? ""
        let transportRaw = getUInt32Property(deviceID, selector: kAudioDevicePropertyTransportType)
        let transport = AudioDevice.TransportType(rawValue: transportRaw ?? 0)
        let dataSource = getUInt32Property(
            deviceID, selector: kAudioDevicePropertyDataSource,
            scope: kAudioObjectPropertyScopeOutput)
        return AudioDevice(
            id: deviceID,
            name: name,
            uid: uid,
            transportType: transport,
            dataSource: dataSource
        )
    }

    // MARK: - Property helpers

    private static func getStringProperty(
        _ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard status == noErr else { return nil }

        // String properties are returned as CFString, not as a C string buffer.
        var cfValue: Unmanaged<CFString>?
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfValue)
        guard status == noErr, let cfValue else { return nil }

        return cfValue.takeRetainedValue() as String
    }

    private static func getUInt32Property(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }

        return value
    }
}

/// Remembers the first observed output so the next real transition is not lost.
nonisolated struct OutputTransitionTracker {
    private var previous: AudioDevice?

    init(initial: AudioDevice? = nil) {
        previous = initial
    }

    mutating func evaluate(_ current: AudioDevice) -> AudioDeviceMonitor.DeviceChange? {
        defer { previous = current }
        guard let previous else { return nil }
        return AudioDeviceMonitor.deviceChange(from: previous, to: current)
    }
}

// MARK: - C callback

/// C callback invoked by CoreAudio when the default output changes.
nonisolated private func audioObjectPropertyListener(
    _ inObjectID: AudioObjectID,
    _ inNumberAddresses: UInt32,
    _ inAddresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let inClientData else { return noErr }

    let monitor = Unmanaged<AudioDeviceMonitor>.fromOpaque(inClientData).takeUnretainedValue()
    monitor.handleDefaultOutputDeviceChanged()
    return noErr
}
