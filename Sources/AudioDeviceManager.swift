import CoreAudio
import Darwin

struct AudioDevice: Equatable {
    let id: AudioObjectID
    let name: String

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
    }
}

struct AudioDeviceUseState {
    let isRunningSomewhere: Bool
    let isHoggedByAnotherProcess: Bool
}

final class AudioDeviceManager {
    private let systemObjectID = AudioObjectID(UInt32(kAudioObjectSystemObject))
    private let unknownObjectID = AudioObjectID(UInt32(kAudioObjectUnknown))

    func inputDevices(includeVirtual: Bool) -> [AudioDevice] {
        devices(for: kAudioDevicePropertyScopeInput, includeVirtual: includeVirtual)
    }

    func outputDevices(includeVirtual: Bool) -> [AudioDevice] {
        devices(for: kAudioDevicePropertyScopeOutput, includeVirtual: includeVirtual)
    }

    func defaultInputDevice() -> AudioDevice? {
        defaultDevice(for: kAudioHardwarePropertyDefaultInputDevice)
    }

    func defaultOutputDevice() -> AudioDevice? {
        defaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
    }

    func setDefaultInputDevice(_ device: AudioDevice) {
        setDefaultDevice(device, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    func setDefaultOutputDevice(_ device: AudioDevice) {
        setDefaultDevice(device, selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    func outputVolume() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        return readOutputVolume(deviceID: device.id)
    }

    func defaultInputDeviceUseState() -> AudioDeviceUseState? {
        guard let device = defaultInputDevice() else { return nil }
        return deviceUseState(device.id)
    }

    private func devices(for scope: AudioObjectPropertyScope, includeVirtual: Bool) -> [AudioDevice] {
        let deviceIDs = allDeviceIDs()
        let devices = deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard deviceIsAlive(deviceID) else { return nil }
            guard !deviceIsHidden(deviceID) else { return nil }
            guard deviceHasStreams(deviceID, scope: scope) else { return nil }
            guard let name = deviceName(deviceID) else { return nil }
            if shouldAlwaysHideDevice(named: name, deviceID: deviceID) {
                return nil
            }
            if !includeVirtual, deviceIsVirtualOrAggregate(deviceID, name: name) {
                return nil
            }
            return AudioDevice(id: deviceID, name: name)
        }
        return devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        let status2 = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs)
        guard status2 == noErr else { return [] }

        return deviceIDs
    }

    private func deviceHasStreams(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr else { return false }
        return dataSize > 0
    }

    private func deviceIsAlive(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return true }

        var isAlive: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isAlive)
        guard status == noErr else { return true }

        return isAlive != 0
    }

    private func deviceIsHidden(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIsHidden,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isHidden: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isHidden)
        guard status == noErr else { return false }

        return isHidden != 0
    }

    private func deviceName(_ deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        guard status == noErr, deviceID != unknownObjectID else { return nil }
        return name as String
    }

    private func deviceIsVirtualOrAggregate(_ deviceID: AudioObjectID, name: String) -> Bool {
        guard let transport = deviceTransportType(deviceID) else { return false }

        switch transport {
        case kAudioDeviceTransportTypeVirtual,
             kAudioDeviceTransportTypeAggregate,
             kAudioDeviceTransportTypeAutoAggregate:
            return true
        default:
            return false
        }
    }

    private func shouldAlwaysHideDevice(named name: String, deviceID: AudioObjectID) -> Bool {
        if name.hasPrefix("CADefaultDeviceAggregate") {
            return true
        }
        guard let transport = deviceTransportType(deviceID) else { return false }
        return transport == kAudioDeviceTransportTypeAutoAggregate
    }

    private func deviceTransportType(_ deviceID: AudioObjectID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var transport: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &transport)
        guard status == noErr else { return nil }

        return transport
    }

    private func defaultDevice(for selector: AudioObjectPropertySelector) -> AudioDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(0)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceID)
        guard status == noErr else { return nil }
        guard let name = deviceName(deviceID) else { return nil }
        return AudioDevice(id: deviceID, name: name)
    }

    private func setDefaultDevice(_ device: AudioDevice, selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = device.id
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectSetPropertyData(systemObjectID, &address, 0, nil, dataSize, &deviceID)
    }

    private func readOutputVolume(deviceID: AudioObjectID) -> Float? {
        if let master = readVolumeScalar(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return master
        }

        let left = readVolumeScalar(deviceID: deviceID, element: 1)
        let right = readVolumeScalar(deviceID: deviceID, element: 2)

        switch (left, right) {
        case let (l?, r?):
            return (l + r) / 2.0
        case let (l?, nil):
            return l
        case let (nil, r?):
            return r
        default:
            return nil
        }
    }

    private func readVolumeScalar(deviceID: AudioObjectID, element: AudioObjectPropertyElement) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var volume = Float32(0)
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)
        guard status == noErr else { return nil }

        return volume
    }

    private func deviceUseState(_ deviceID: AudioObjectID) -> AudioDeviceUseState {
        let isRunning = deviceIsRunningSomewhere(deviceID) ?? false
        let hogPID = deviceHogModePID(deviceID)
        let isHogged = hogPID != nil && hogPID != -1 && hogPID != getpid()
        return AudioDeviceUseState(isRunningSomewhere: isRunning, isHoggedByAnotherProcess: isHogged)
    }

    private func deviceIsRunningSomewhere(_ deviceID: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &isRunning)
        guard status == noErr else { return nil }
        return isRunning != 0
    }

    private func deviceHogModePID(_ deviceID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var pid: pid_t = -1
        var dataSize = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &pid)
        guard status == noErr else { return nil }
        return pid
    }
}
