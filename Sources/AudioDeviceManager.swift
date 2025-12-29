import CoreAudio

struct AudioDevice: Equatable {
    let id: AudioObjectID
    let name: String
}

final class AudioDeviceManager {
    func inputDevices() -> [AudioDevice] {
        []
    }

    func outputDevices() -> [AudioDevice] {
        []
    }

    func defaultInputDevice() -> AudioDevice? {
        nil
    }

    func defaultOutputDevice() -> AudioDevice? {
        nil
    }

    func setDefaultInputDevice(_ device: AudioDevice) {
    }

    func setDefaultOutputDevice(_ device: AudioDevice) {
    }

    func outputVolume() -> Float? {
        nil
    }
}
