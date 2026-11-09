import AudioToolbox
import CoreAudio
import Foundation

/// Volume of the current output device, read from Core Audio and kept up to
/// date as it changes: volume keys, Control Center, another app, or a
/// Bluetooth speaker's own buttons all show up at once.
public enum OutputVolume {
    public struct Level: Equatable, Sendable {
        /// 0–100, as macOS shows it.
        public var percent: Int
        public var isMuted: Bool
    }

    /// The volume of the default output device, or `nil` when it has no
    /// volume of its own (some HDMI and USB outputs are fixed).
    public static func current() -> Level? {
        level(of: defaultDevice())
    }

    /// Every change of the output volume, mute or output device. Starts with
    /// the current level. Listening stops when the consuming task ends.
    public static func changes() -> AsyncStream<Level?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let watcher = Watcher(continuation: continuation)
            continuation.onTermination = { _ in watcher.stop() }
            watcher.start()
        }
    }

    // MARK: Core Audio

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static let defaultDeviceAddress = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    /// The volume macOS itself shows and the volume keys change. For a
    /// device with separate left and right volumes it reflects both.
    static let mainVolumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
    static let muteAddress = address(kAudioDevicePropertyMute)

    static func defaultDevice() -> AudioDeviceID {
        var address = defaultDeviceAddress
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device)
        return status == noErr ? device : AudioDeviceID(kAudioObjectUnknown)
    }

    static func level(of device: AudioDeviceID) -> Level? {
        guard device != kAudioObjectUnknown else { return nil }
        var volumeAddress = mainVolumeAddress
        guard AudioObjectHasProperty(device, &volumeAddress) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr, volume.isFinite
        else { return nil }

        var muted: UInt32 = 0
        var muteAddress = muteAddress
        if AudioObjectHasProperty(device, &muteAddress) {
            var muteSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &muteSize, &muted) != noErr { muted = 0 }
        }
        let percent = Int((min(max(volume, 0), 1) * 100).rounded())
        return Level(percent: percent, isMuted: muted != 0)
    }

    /// Follows the default output device and its volume and mute. All state
    /// lives on `queue`, which is also where Core Audio calls the listeners.
    private final class Watcher: @unchecked Sendable {
        private let queue = DispatchQueue(label: "Polka.OutputVolume")
        private let continuation: AsyncStream<Level?>.Continuation
        private var device = AudioDeviceID(kAudioObjectUnknown)
        private var deviceListeners: [AudioObjectPropertyAddress] = []
        private var systemListening = false
        private var stopped = false
        private var lastLevel: Level??

        private lazy var systemListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.followDefaultDevice()
        }
        private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.publish()
        }

        init(continuation: AsyncStream<Level?>.Continuation) {
            self.continuation = continuation
        }

        func start() {
            queue.async { [self] in
                guard !stopped else { return }
                var address = OutputVolume.defaultDeviceAddress
                systemListening = AudioObjectAddPropertyListenerBlock(OutputVolume.system, &address, queue, systemListener) == noErr
                followDefaultDevice()
            }
        }

        func stop() {
            queue.async { [self] in
                guard !stopped else { return }
                stopped = true
                removeDeviceListeners()
                if systemListening {
                    var address = OutputVolume.defaultDeviceAddress
                    AudioObjectRemovePropertyListenerBlock(OutputVolume.system, &address, queue, systemListener)
                    systemListening = false
                }
            }
        }

        private func followDefaultDevice() {
            guard !stopped else { return }
            let next = OutputVolume.defaultDevice()
            if next != device {
                removeDeviceListeners()
                device = next
                if device != kAudioObjectUnknown {
                    for candidate in [OutputVolume.mainVolumeAddress, OutputVolume.muteAddress] {
                        var address = candidate
                        guard AudioObjectHasProperty(device, &address),
                            AudioObjectAddPropertyListenerBlock(device, &address, queue, deviceListener) == noErr
                        else { continue }
                        deviceListeners.append(candidate)
                    }
                }
            }
            publish()
        }

        private func removeDeviceListeners() {
            for candidate in deviceListeners {
                var address = candidate
                AudioObjectRemovePropertyListenerBlock(device, &address, queue, deviceListener)
            }
            deviceListeners = []
        }

        private func publish() {
            guard !stopped else { return }
            let level = OutputVolume.level(of: device)
            // Volume keys fire several notifications per press; send each
            // value once.
            guard lastLevel != .some(level) else { return }
            lastLevel = .some(level)
            continuation.yield(level)
        }
    }
}
