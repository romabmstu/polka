import CoreAudio
import Foundation

/// Whether any sound is going to an output device right now.
public enum AudioActivity {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// `true` when some app is sending audio to an output device, `false`
    /// when none is, and `nil` when Core Audio would not say. Speakers,
    /// headphones, Bluetooth and AirPlay outputs all count; devices that only
    /// record do not.
    public static func isOutputRunning() -> Bool? {
        var listAddress = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty else { return nil }
        let status = ids.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return nil }

        var answered = false
        for id in ids {
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else {
                continue
            }
            var runningAddress = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &runningAddress, 0, nil, &runningSize, &running) == noErr else {
                continue
            }
            if running != 0 { return true }
            answered = true
        }
        return answered ? false : nil
    }
}
