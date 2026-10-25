import CoreAudio
import Testing
import XCTest

@testable import Silentio

final class DeviceMuterTests: XCTestCase {
    @MainActor
    func testMutesAndRestoresOnlyItsOwnMuteChange() {
        let audio = FakeSpeakerAudioProperties()
        let muter = DeviceMuter(audio: audio)

        muter.muteBuiltInSpeakers(speakers)
        XCTAssertEqual(audio.mute, 1)
        XCTAssertEqual(audio.muteWrites, [1])

        muter.muteBuiltInSpeakers(speakers)
        XCTAssertEqual(audio.muteWrites, [1])

        muter.restoreBuiltInSpeakers()
        XCTAssertEqual(audio.mute, 0)
        XCTAssertEqual(audio.muteWrites, [1, 0])

        muter.restoreBuiltInSpeakers()
        XCTAssertEqual(audio.muteWrites, [1, 0])
    }

    @MainActor
    func testAlreadyMutedSpeakerIsNotChangedOrRestored() {
        let audio = FakeSpeakerAudioProperties()
        audio.mute = 1
        let muter = DeviceMuter(audio: audio)

        muter.muteBuiltInSpeakers(speakers)
        muter.restoreBuiltInSpeakers()

        XCTAssertTrue(audio.muteWrites.isEmpty)
        XCTAssertTrue(audio.volumeWrites.isEmpty)
    }

    @MainActor
    func testFallsBackToVolumeAndRestoresPreviousLevel() {
        let audio = FakeSpeakerAudioProperties()
        audio.mute = nil
        let muter = DeviceMuter(audio: audio)

        muter.muteBuiltInSpeakers(speakers)
        XCTAssertEqual(audio.volume, 0)
        XCTAssertEqual(audio.volumeWrites, [0])

        muter.restoreBuiltInSpeakers()
        XCTAssertEqual(audio.volume, 0.7)
        XCTAssertEqual(audio.volumeWrites, [0, 0.7])
    }

    @MainActor
    func testReappliesMuteWhenSystemRevertsIt() {
        let audio = FakeSpeakerAudioProperties()
        let muter = DeviceMuter(audio: audio)
        muter.muteBuiltInSpeakers(speakers)

        // macOS restores the saved speaker state while finishing the route change.
        audio.mute = 0
        muter.muteBuiltInSpeakers(speakers)
        XCTAssertEqual(audio.mute, 1)
        XCTAssertEqual(audio.muteWrites, [1, 1])

        muter.restoreBuiltInSpeakers()
        XCTAssertEqual(audio.mute, 0)
    }

    @MainActor
    func testDoesNotOverwriteUserMuteChange() {
        let audio = FakeSpeakerAudioProperties()
        let muter = DeviceMuter(audio: audio)
        muter.muteBuiltInSpeakers(speakers)

        audio.mute = 0
        muter.restoreBuiltInSpeakers()

        XCTAssertEqual(audio.muteWrites, [1])
    }

    @MainActor
    func testDoesNotOverwriteUserVolumeChange() {
        let audio = FakeSpeakerAudioProperties()
        audio.mute = nil
        let muter = DeviceMuter(audio: audio)
        muter.muteBuiltInSpeakers(speakers)

        audio.volume = 0.2
        muter.restoreBuiltInSpeakers()

        XCTAssertEqual(audio.volumeWrites, [0])
    }

    @MainActor
    func testDoesNotRestoreRecycledDeviceID() {
        let audio = FakeSpeakerAudioProperties()
        let muter = DeviceMuter(audio: audio)
        muter.muteBuiltInSpeakers(speakers)

        audio.uid = "DifferentDevice"
        muter.restoreBuiltInSpeakers()

        XCTAssertEqual(audio.muteWrites, [1])
    }

    @MainActor
    func testIgnoresNonSpeakerOutput() {
        let audio = FakeSpeakerAudioProperties()
        let muter = DeviceMuter(audio: audio)
        let headphones = AudioDevice(
            id: 2,
            name: "Headphones",
            uid: "BuiltInHeadphoneDevice",
            transportType: .builtIn,
            dataSource: nil
        )

        muter.muteBuiltInSpeakers(headphones)

        XCTAssertTrue(audio.muteWrites.isEmpty)
        XCTAssertTrue(audio.volumeWrites.isEmpty)
    }

    private var speakers: AudioDevice {
        AudioDevice(
            id: 1,
            name: "Internal Speakers",
            uid: "BuiltInSpeakerDevice",
            transportType: .builtIn,
            dataSource: nil
        )
    }
}

@MainActor
private final class FakeSpeakerAudioProperties: SpeakerAudioProperties {
    var uid = "BuiltInSpeakerDevice"
    var speakerActive = true
    var mute: UInt32? = 0
    var volume: Float? = 0.7
    var muteWritable = true
    var volumeWritable = true
    var writesSucceed = true
    private(set) var muteWrites: [UInt32] = []
    private(set) var volumeWrites: [Float] = []

    func deviceUID(_ id: AudioDeviceID) -> String { uid }
    func isBuiltInSpeaker(_ id: AudioDeviceID) -> Bool { speakerActive }
    func readMute(on id: AudioDeviceID) -> UInt32? { mute }
    func canSetMute(on id: AudioDeviceID) -> Bool { muteWritable }
    func readVolume(on id: AudioDeviceID) -> Float? { volume }
    func canSetVolume(on id: AudioDeviceID) -> Bool { volumeWritable }

    func setMute(_ value: UInt32, on id: AudioDeviceID) -> Bool {
        muteWrites.append(value)
        guard writesSucceed else { return false }
        mute = value
        return true
    }

    func setVolume(_ value: Float, on id: AudioDeviceID) -> Bool {
        volumeWrites.append(value)
        guard writesSucceed else { return false }
        volume = value
        return true
    }

}

@MainActor
struct SpeakerRestorationTests {
    private let speakers = AudioDevice(
        id: 1, name: "Speakers", uid: "BuiltInSpeakerDevice",
        transportType: .builtIn, dataSource: nil
    )

    @Test(arguments: [true, false])
    func sharedJackDoesNotRestoreHeadphones(useMute: Bool) {
        let audio = FakeSpeakerAudioProperties()
        if !useMute { audio.mute = nil }
        let muter = DeviceMuter(audio: audio)
        muter.muteBuiltInSpeakers(speakers)

        audio.speakerActive = false
        muter.restoreBuiltInSpeakers()
        #expect(audio.muteWrites == (useMute ? [1] : []))
        #expect(audio.volumeWrites == (useMute ? [] : [0]))

        audio.speakerActive = true
        muter.restoreBuiltInSpeakers()
        #expect(audio.muteWrites == (useMute ? [1, 0] : []))
        #expect(audio.volumeWrites == (useMute ? [] : [0, 0.7]))
    }

    @Test(arguments: [true, false])
    func failedReadsRetainRestorationState(useMute: Bool) {
        let audio = FakeSpeakerAudioProperties()
        if !useMute { audio.mute = nil }
        let muter = DeviceMuter(audio: audio)
        muter.muteBuiltInSpeakers(speakers)
        if useMute { audio.mute = nil } else { audio.volume = nil }
        muter.restoreBuiltInSpeakers()
        if useMute { audio.mute = 1 } else { audio.volume = 0 }
        muter.restoreBuiltInSpeakers()
        #expect(audio.muteWrites == (useMute ? [1, 0] : []))
        #expect(audio.volumeWrites == (useMute ? [] : [0, 0.7]))
    }

    @Test(arguments: [true, false])
    func failedRestorationCanBeRetried(useMute: Bool) {
        let audio = FakeSpeakerAudioProperties()
        if !useMute { audio.mute = nil }
        let muter = DeviceMuter(audio: audio)
        muter.muteBuiltInSpeakers(speakers)
        audio.writesSucceed = false
        muter.restoreBuiltInSpeakers()
        audio.writesSucceed = true
        muter.restoreBuiltInSpeakers()
        #expect(audio.muteWrites == (useMute ? [1, 0, 0] : []))
        #expect(audio.volumeWrites == (useMute ? [] : [0, 0.7, 0.7]))
    }

    @Test
    func readOnlyAlreadyMutedSpeakersAreNotChanged() {
        let audio = FakeSpeakerAudioProperties()
        audio.mute = 1
        audio.muteWritable = false
        let muter = DeviceMuter(audio: audio)
        muter.muteBuiltInSpeakers(speakers)
        muter.restoreBuiltInSpeakers()
        #expect(audio.muteWrites.isEmpty)
        #expect(audio.volumeWrites.isEmpty)
    }

    @Test(arguments: ["DifferentDevice", ""])
    func staleOrUnidentifiedDevicesAreNeverMuted(uid: String) {
        let audio = FakeSpeakerAudioProperties()
        let muter = DeviceMuter(audio: audio)
        let stale = AudioDevice(
            id: 1, name: "Speakers", uid: uid, transportType: .builtIn, dataSource: 0x6973_706B
        )
        muter.muteBuiltInSpeakers(stale)
        #expect(audio.muteWrites.isEmpty)
        #expect(audio.volumeWrites.isEmpty)
    }

    @Test
    func delayedMuteDoesNotChangeSharedJackHeadphones() {
        let audio = FakeSpeakerAudioProperties()
        audio.speakerActive = false
        DeviceMuter(audio: audio).muteBuiltInSpeakers(speakers)
        #expect(audio.muteWrites.isEmpty)
        #expect(audio.volumeWrites.isEmpty)
    }

    @Test
    func unsupportedSpeakerPropertiesDoNotCreateRestorationState() {
        let audio = FakeSpeakerAudioProperties()
        audio.muteWritable = false
        audio.volumeWritable = false
        let muter = DeviceMuter(audio: audio)
        muter.muteBuiltInSpeakers(speakers)
        muter.restoreBuiltInSpeakers()
        #expect(audio.muteWrites.isEmpty)
        #expect(audio.volumeWrites.isEmpty)
    }
}
