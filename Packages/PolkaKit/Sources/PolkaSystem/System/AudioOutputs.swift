import CoreAudio
import Foundation

/// The system's current output devices, including Bluetooth and virtual outputs.
public enum AudioOutputs {
    public struct Device: Identifiable, Equatable, Sendable {
        public let id: AudioDeviceID
        public let name: String
    }

    public struct Snapshot: Sendable {
        public let devices: [Device]
        public let selectedID: AudioDeviceID
    }

    public struct Failure: Error, Sendable {
        public let status: OSStatus
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    public static func snapshot() throws -> Snapshot {
        var listAddress = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size)
        guard status == noErr else { throw Failure(status: status) }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        if !ids.isEmpty {
            status = ids.withUnsafeMutableBytes { bytes in
                AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, bytes.baseAddress!)
            }
        }
        guard status == noErr else { throw Failure(status: status) }
        var defaultAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
        var selected: AudioDeviceID = 0
        var selectedSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        status = AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &selectedSize, &selected)
        guard status == noErr else { throw Failure(status: status) }

        let devices = ids.compactMap { id -> Device? in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var eligibleAddress = address(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioDevicePropertyScopeOutput)
            var eligible: UInt32 = 0
            var eligibleSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &eligibleAddress, 0, nil, &eligibleSize, &eligible) == noErr, eligible != 0 else { return nil }
            var nameAddress = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr,
                  let name else { return nil }
            return Device(id: id, name: name.takeRetainedValue() as String)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Snapshot(devices: devices, selectedID: selected)
    }

    public static func select(_ id: AudioDeviceID) throws {
        // Recheck hot-plugged devices rather than trusting a stale menu item.
        guard try snapshot().devices.contains(where: { $0.id == id }) else { throw Failure(status: kAudioHardwareBadDeviceError) }
        var output = id
        var outputAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(system, &outputAddress, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &output)
        guard status == noErr else { throw Failure(status: status) }
    }
}
