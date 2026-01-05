import AudioToolbox
import CoreAudio

final class InputMeter {
    var onLevelUpdate: ((Float) -> Void)?
    var onStartFailure: ((Error) -> Void)?

    private let meterQueue = DispatchQueue(label: "InputMeter.queue")
    private var timer: DispatchSourceTimer?
    private var isRunning = false

    private var deviceID = AudioObjectID(UInt32(kAudioObjectUnknown))
    private var queue: AudioQueueRef?
    private var buffers: [AudioQueueBufferRef] = []
    private var channelCount: Int = 1
    private var meterStates: [AudioQueueLevelMeterState] = []

    private var latestLevel: Float = 0
    private var smoothedLevel: Float = 0

    private let refreshRate: Double = 15
    private let attackTime: Double = 0.05
    private let releaseTime: Double = 0.3

    @discardableResult
    func start(deviceID: AudioObjectID) -> Bool {
        guard !isRunning else { return true }
        self.deviceID = deviceID
        resetLevels()

        guard startQueue(deviceID: deviceID) else { return false }

        isRunning = true
        startTimer()
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopTimer()
        stopQueue()
        resetLevels()
        meterQueue.async { [weak self] in
            self?.onLevelUpdate?(0)
        }
    }

    private func startQueue(deviceID: AudioObjectID) -> Bool {
        guard let streamFormat = deviceStreamFormat(deviceID: deviceID) else {
            return false
        }

        var format = streamFormat
        channelCount = max(1, Int(format.mChannelsPerFrame))
        meterStates = Array(repeating: AudioQueueLevelMeterState(mAveragePower: 0, mPeakPower: 0), count: channelCount)

        var newQueue: AudioQueueRef?
        let status = AudioQueueNewInput(
            &format,
            InputMeter.inputCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            nil,
            nil,
            0,
            &newQueue
        )
        guard status == noErr, let queue = newQueue else {
            onStartFailure?(NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil))
            return false
        }

        guard let deviceUID = deviceUIDString(deviceID: deviceID) else {
            AudioQueueDispose(queue, true)
            return false
        }

        var uid = deviceUID as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        let deviceStatus = AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &uid, uidSize)
        guard deviceStatus == noErr else {
            AudioQueueDispose(queue, true)
            return false
        }

        var meteringEnabled: UInt32 = 1
        let meteringSize = UInt32(MemoryLayout<UInt32>.size)
        let meteringStatus = AudioQueueSetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &meteringEnabled, meteringSize)
        guard meteringStatus == noErr else {
            AudioQueueDispose(queue, true)
            return false
        }

        let bufferCount = 3
        let bufferByteSize = bufferSize(for: format)
        buffers = []
        for _ in 0..<bufferCount {
            var bufferRef: AudioQueueBufferRef?
            let allocStatus = AudioQueueAllocateBuffer(queue, bufferByteSize, &bufferRef)
            guard allocStatus == noErr, let bufferRef else {
                AudioQueueDispose(queue, true)
                return false
            }
            buffers.append(bufferRef)
            AudioQueueEnqueueBuffer(queue, bufferRef, 0, nil)
        }

        let startStatus = AudioQueueStart(queue, nil)
        guard startStatus == noErr else {
            AudioQueueDispose(queue, true)
            return false
        }

        self.queue = queue
        return true
    }

    private func stopQueue() {
        guard let queue else { return }
        AudioQueueStop(queue, true)
        AudioQueueDispose(queue, true)
        self.queue = nil
        buffers = []
    }

    private func bufferSize(for format: AudioStreamBasicDescription) -> UInt32 {
        let framesPerBuffer: UInt32 = 1024
        let bytesPerFrame = max(1, format.mBytesPerFrame)
        return framesPerBuffer * bytesPerFrame
    }

    private func deviceUIDString(deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var uid: CFString = "" as CFString
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &uid)
        guard status == noErr else { return nil }
        return uid as String
    }

    private func deviceStreamFormat(deviceID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &format)
        guard status == noErr else { return nil }
        return format
    }

    private func readLevel() -> Float? {
        guard let queue else { return nil }
        guard !meterStates.isEmpty else { return nil }

        var dataSize = UInt32(MemoryLayout<AudioQueueLevelMeterState>.size * meterStates.count)
        let status = meterStates.withUnsafeMutableBufferPointer { bufferPointer -> OSStatus in
            guard let baseAddress = bufferPointer.baseAddress else { return -1 }
            return AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentLevelMeter, baseAddress, &dataSize)
        }
        guard status == noErr, dataSize > 0 else { return nil }

        let count = min(meterStates.count, Int(dataSize) / MemoryLayout<AudioQueueLevelMeterState>.size)
        let maxAverage = meterStates.prefix(count).map(\.mAveragePower).max() ?? 0
        return max(0, min(1, maxAverage))
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: meterQueue)
        let interval: DispatchTimeInterval = .milliseconds(66)
        timer.schedule(deadline: DispatchTime.now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.pollLevel()
        }
        timer.resume()
        self.timer = timer
    }

    private func pollLevel() {
        guard isRunning else { return }
        guard let current = readLevel() else {
            updateDisplayLevel(0)
            return
        }
        updateDisplayLevel(current)
    }

    private func updateDisplayLevel(_ current: Float) {
        let clamped = max(0, min(1, current))
        let dt = 1.0 / refreshRate
        let attackCoeff = 1 - exp(-dt / attackTime)
        let releaseCoeff = 1 - exp(-dt / releaseTime)
        let coeff = Double(clamped) > Double(smoothedLevel) ? attackCoeff : releaseCoeff

        smoothedLevel += (clamped - smoothedLevel) * Float(coeff)
        latestLevel = smoothedLevel
        onLevelUpdate?(smoothedLevel)
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func resetLevels() {
        latestLevel = 0
        smoothedLevel = 0
    }

    private static let inputCallback: AudioQueueInputCallback = { userData, queue, buffer, _, _, _ in
        guard let userData else { return }
        _ = Unmanaged<InputMeter>.fromOpaque(userData).takeUnretainedValue()
        AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
    }
}
