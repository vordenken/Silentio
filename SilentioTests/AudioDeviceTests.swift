import CoreAudio
import XCTest

@testable import Silentio

final class AudioDeviceTests: XCTestCase {
    private func device(
        uid: String,
        transport: AudioDevice.TransportType = .builtIn,
        dataSource: UInt32? = nil,
        id: UInt32 = 1
    ) -> AudioDevice {
        AudioDevice(id: id, name: uid, uid: uid, transportType: transport, dataSource: dataSource)
    }

    func testSwitchToBuiltInSpeakersTriggersDisconnect() {
        let speakers = device(uid: "BuiltInSpeakerDevice")
        for uid in ["BuiltInHeadphoneDevice", "BluetoothHeadset", "USB-Headphones"] {
            XCTAssertEqual(
                AudioDeviceMonitor.deviceChange(from: device(uid: uid), to: speakers),
                .speakersActivated)
        }
    }

    func testSharedOutputDataSourceSwitchTriggersDisconnect() {
        let headphones = device(uid: "BuiltInOutput", dataSource: 0x6864_706E)
        let speakers = device(uid: "BuiltInOutput", dataSource: 0x6973_706B)
        XCTAssertEqual(
            AudioDeviceMonitor.deviceChange(from: headphones, to: speakers), .speakersActivated)
        XCTAssertEqual(
            AudioDeviceMonitor.deviceChange(from: speakers, to: headphones), .speakersDeactivated)
    }

    func testHeadphoneDataSourceOverridesSpeakerUID() {
        let headphones = device(uid: "BuiltInSpeakerDevice", dataSource: 0x6864_706E)
        XCTAssertFalse(headphones.isBuiltInSpeaker)
    }

    func testExternalSpeakerDataSourceIsNotInternal() {
        XCTAssertFalse(
            device(uid: "USB-Speakers", transport: .usb, dataSource: 0x6973_706B).isBuiltInSpeaker)
    }

    func testTransportTypesMatchCoreAudioConstants() {
        XCTAssertEqual(
            AudioDevice.TransportType(rawValue: kAudioDeviceTransportTypeBuiltIn), .builtIn)
        XCTAssertEqual(
            AudioDevice.TransportType(rawValue: kAudioDeviceTransportTypeBluetoothLE), .bluetoothLE)
        XCTAssertEqual(
            AudioDevice.TransportType(rawValue: kAudioDeviceTransportTypeAggregate), .aggregate)
        XCTAssertEqual(
            AudioDevice.TransportType(rawValue: kAudioDeviceTransportTypeFireWire), .fireWire)
        XCTAssertEqual(
            AudioDevice.TransportType(rawValue: kAudioDeviceTransportTypeDisplayPort), .displayPort)
        XCTAssertTrue(
            device(uid: "AppleHDAEngineOutput:1", dataSource: 0x6973_706B).isBuiltInSpeaker)
    }

    func testSwitchBetweenOtherOutputsIsReportedSeparately() {
        XCTAssertEqual(
            AudioDeviceMonitor.deviceChange(
                from: device(uid: "USB-Headphones"),
                to: device(uid: "BluetoothHeadset")
            ), .otherOutputChanged)
        let headphones = device(uid: "USB-Headphones")
        XCTAssertNil(AudioDeviceMonitor.deviceChange(from: headphones, to: headphones))
    }

    func testNoEventForSameSpeakerOutput() {
        let speaker = device(uid: "BuiltInSpeakerDevice")
        XCTAssertNil(AudioDeviceMonitor.deviceChange(from: speaker, to: speaker))
    }

    func testFirstRealChangeAfterStartupIsHandled() {
        var tracker = OutputTransitionTracker(initial: device(uid: "BuiltInHeadphoneDevice"))
        XCTAssertEqual(tracker.evaluate(device(uid: "BuiltInSpeakerDevice")), .speakersActivated)
    }

    func testUnknownStartupOutputIsOnlyUsedAsBaseline() {
        var tracker = OutputTransitionTracker()
        XCTAssertNil(tracker.evaluate(device(uid: "BuiltInHeadphoneDevice")))
        XCTAssertEqual(tracker.evaluate(device(uid: "BuiltInSpeakerDevice")), .speakersActivated)
    }
}
