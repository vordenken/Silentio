import CoreAudio
import Foundation

/// Model of an audio device.
nonisolated struct AudioDevice: Equatable, Sendable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let transportType: TransportType
    let dataSource: UInt32?

    /// The built-in headphone jack is a separate output and must not be treated
    /// as the built-in speakers. The transport type is unreliable on some Macs.
    static func isBuiltInSpeaker(uid: String, transportType: TransportType, dataSource: UInt32?)
        -> Bool
    {
        // On Macs with a shared built-in output, the data source changes while
        // the default AudioDeviceID and UID remain the same.
        if dataSource == 0x6864_706E { return false }  // 'hdpn'
        if uid == "BuiltInSpeakerDevice" { return true }
        return transportType == .builtIn && dataSource == 0x6973_706B  // 'ispk'
    }

    var isBuiltInSpeaker: Bool {
        Self.isBuiltInSpeaker(uid: uid, transportType: transportType, dataSource: dataSource)
    }

    enum TransportType: UInt32 {
        case unknown = 0
        case builtIn = 0x626C_746E  // 'bltn'
        case aggregate = 0x6772_7570  // 'grup'
        case virtual = 0x7669_7274  // 'virt'
        case pci = 0x7063_6920  // 'pci '
        case usb = 0x7573_6220  // 'usb '
        case fireWire = 0x3133_3934  // '1394'
        case bluetooth = 0x626C_7565  // 'blue'
        case bluetoothLE = 0x626C_6561  // 'blea'
        case airPlay = 0x6169_7270  // 'airp'
        case virtualSoundCard = 0x7673_6320  // 'vsc '
        case displayPort = 0x6470_7274  // 'dprt'
        case hdmi = 0x6864_6D69  // 'hdmi'
        case thunderbolt = 0x7468_756E  // 'thun'

        init(rawValue: UInt32) {
            switch rawValue {
            case 0x626C_746E: self = .builtIn
            case 0x6772_7570: self = .aggregate
            case 0x7669_7274: self = .virtual
            case 0x7063_6920: self = .pci
            case 0x7573_6220: self = .usb
            case 0x3133_3934: self = .fireWire
            case 0x626C_7565: self = .bluetooth
            case 0x626C_6561: self = .bluetoothLE
            case 0x6169_7270: self = .airPlay
            case 0x7673_6320: self = .virtualSoundCard
            case 0x6470_7274: self = .displayPort
            case 0x6864_6D69: self = .hdmi
            case 0x7468_756E: self = .thunderbolt
            default: self = .unknown
            }
        }
    }
}
