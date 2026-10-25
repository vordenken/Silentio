import CoreAudio
import Foundation
import os

/// Audio properties used by the speaker muter. Separating HAL access allows
/// restoration rules to be tested without changing a real device.
@MainActor
protocol SpeakerAudioProperties {
    func deviceUID(_ id: AudioDeviceID) -> String
    func isBuiltInSpeaker(_ id: AudioDeviceID) -> Bool
    func readMute(on id: AudioDeviceID) -> UInt32?
    func canSetMute(on id: AudioDeviceID) -> Bool
    func setMute(_ value: UInt32, on id: AudioDeviceID) -> Bool
    func readVolume(on id: AudioDeviceID) -> Float?
    func canSetVolume(on id: AudioDeviceID) -> Bool
    func setVolume(_ value: Float, on id: AudioDeviceID) -> Bool
}

/// Mutes only the built-in speakers and restores only changes made by Silentio.
@MainActor
final class DeviceMuter {
    private let logger = Logger(subsystem: "com.vd.Silentio", category: "SpeakerMuting")
    private enum PreviousState {
        case unmuted
        case volume(Float)
    }

    private let audio: any SpeakerAudioProperties
    private var changedDevice: (id: AudioDeviceID, uid: String, state: PreviousState)?

    init(audio: any SpeakerAudioProperties = CoreAudioSpeakerProperties()) {
        self.audio = audio
    }

    func muteBuiltInSpeakers(_ device: AudioDevice) {
        guard device.isBuiltInSpeaker else { return }
        guard !device.uid.isEmpty, audio.deviceUID(device.id) == device.uid,
            audio.isBuiltInSpeaker(device.id)
        else {
            logger.error(
                "Speaker output changed or could not be identified; skipping stale mute request")
            return
        }
        if let changedDevice {
            if changedDevice.id == device.id && changedDevice.uid == device.uid {
                switch changedDevice.state {
                case .unmuted where audio.readMute(on: device.id) == 1:
                    return
                case .volume where audio.readVolume(on: device.id) == 0:
                    return
                default:
                    break
                }
            }
            self.changedDevice = nil
        }

        if let muted = audio.readMute(on: device.id) {
            guard muted == 0 else { return }
            if audio.canSetMute(on: device.id), audio.setMute(1, on: device.id) {
                changedDevice = (device.id, device.uid, .unmuted)
                return
            }
        }

        if let volume = audio.readVolume(on: device.id),
            audio.canSetVolume(on: device.id), volume > 0,
            audio.setVolume(0, on: device.id)
        {
            changedDevice = (device.id, device.uid, .volume(volume))
            return
        }

        logger.error("Could not mute built-in speakers: no working writable mute or master volume")
    }

    func restoreBuiltInSpeakers() {
        guard let changedDevice else { return }
        // AudioDeviceID can be recycled. Never restore a different device.
        guard audio.deviceUID(changedDevice.id) == changedDevice.uid else {
            self.changedDevice = nil
            return
        }
        // A shared jack can retain its ID and UID while driving headphones.
        guard audio.isBuiltInSpeaker(changedDevice.id) else { return }

        switch changedDevice.state {
        case .unmuted:
            guard let mute = audio.readMute(on: changedDevice.id) else {
                logger.error(
                    "Could not read speaker mute during restoration; retaining state for retry")
                return
            }
            guard mute == 1 else {
                self.changedDevice = nil
                return
            }
            if audio.setMute(0, on: changedDevice.id) {
                self.changedDevice = nil
            }
        case .volume(let previous):
            guard let volume = audio.readVolume(on: changedDevice.id) else {
                logger.error(
                    "Could not read speaker volume during restoration; retaining state for retry")
                return
            }
            guard volume == 0 else {
                self.changedDevice = nil
                return
            }
            if audio.setVolume(previous, on: changedDevice.id) {
                self.changedDevice = nil
            }
        }
    }
}

/// CoreAudio HAL implementation for the built-in speaker's output properties.
@MainActor
private struct CoreAudioSpeakerProperties: SpeakerAudioProperties {
    private let logger = Logger(subsystem: "com.vd.Silentio", category: "CoreAudio")
    /// The HAL virtual master volume selector (`vlmm`).
    private let virtualMainVolume = AudioObjectPropertySelector(0x766C_6D6D)

    func deviceUID(_ id: AudioDeviceID) -> String {
        AudioDeviceMonitor.describeDevice(id).uid
    }

    func isBuiltInSpeaker(_ id: AudioDeviceID) -> Bool {
        AudioDeviceMonitor.describeDevice(id).isBuiltInSpeaker
    }

    func readMute(on id: AudioDeviceID) -> UInt32? {
        var property = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(id, &property) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    func canSetMute(on id: AudioDeviceID) -> Bool {
        isSettable(kAudioDevicePropertyMute, on: id)
    }

    func setMute(_ value: UInt32, on id: AudioDeviceID) -> Bool {
        var mutableValue = value
        return withUnsafePointer(to: &mutableValue) {
            write(
                $0, size: UInt32(MemoryLayout<UInt32>.size), selector: kAudioDevicePropertyMute,
                on: id)
        }
    }

    func readVolume(on id: AudioDeviceID) -> Float? {
        var property = address(virtualMainVolume)
        guard AudioObjectHasProperty(id, &property) else { return nil }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    func canSetVolume(on id: AudioDeviceID) -> Bool {
        isSettable(virtualMainVolume, on: id)
    }

    func setVolume(_ value: Float, on id: AudioDeviceID) -> Bool {
        var mutableValue = value
        return withUnsafePointer(to: &mutableValue) {
            write($0, size: UInt32(MemoryLayout<Float>.size), selector: virtualMainVolume, on: id)
        }
    }

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func isSettable(_ selector: AudioObjectPropertySelector, on id: AudioDeviceID) -> Bool {
        var property = address(selector)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &property, &settable) == noErr
            && settable.boolValue
    }

    private func write(
        _ value: UnsafeRawPointer, size: UInt32, selector: AudioObjectPropertySelector,
        on id: AudioDeviceID
    ) -> Bool {
        var property = address(selector)
        let status = AudioObjectSetPropertyData(id, &property, 0, nil, size, value)
        if status != noErr {
            logger.error(
                "Failed to update audio selector \(selector) on device \(id) (OSStatus \(status))")
        }
        return status == noErr
    }
}
