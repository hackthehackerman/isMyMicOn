import AVFoundation

final class InputMeter {
    var onLevelUpdate: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let meterQueue = DispatchQueue(label: "InputMeter.queue")
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var isTapInstalled = false
    private var latestLevel: Float = 0

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: inputFormat.channelCount,
            interleaved: false
        )

        input.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        isTapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            return
        }

        startTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        engine.stop()
        stopTimer()

        meterQueue.async { [weak self] in
            self?.latestLevel = 0
            self?.onLevelUpdate?(0)
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else { return }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sum += sample * sample
            }
        }

        let mean = sum / Float(frameLength * channelCount)
        let rms = sqrt(mean)
        let clamped = min(1, max(0, rms))

        meterQueue.async { [weak self] in
            self?.latestLevel = clamped
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: meterQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 15.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.onLevelUpdate?(self.latestLevel)
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
}
