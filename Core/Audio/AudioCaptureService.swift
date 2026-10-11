import AVFoundation

enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access is disabled. Allow access in Settings to measure sound."
        case .inputUnavailable:
            return "The microphone input is unavailable on this device."
        }
    }
}

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private let filter = FrequencyWeightingFilter()
    private var running = false
    private var currentSampleRate: Double = 48000.0

    /// Frequency weighting filter applied to captured audio buffers.
    var weighting: FrequencyWeighting = .z {
        didSet {
            filter.configure(weighting: weighting, sampleRate: currentSampleRate)
        }
    }

    /// Level in dBFS and the duration represented by the buffer.
    var onLevel: ((Double, Double) -> Void)?

    func start() async throws {
        guard !running else { return }

        let allowed: Bool
        if #available(iOS 17.0, *) {
            if AVAudioApplication.shared.recordPermission == .granted {
                allowed = true
            } else {
                allowed = await AVAudioApplication.requestRecordPermission()
            }
        } else {
            if audioSession.recordPermission == .granted {
                allowed = true
            } else {
                allowed = await withCheckedContinuation { continuation in
                    audioSession.requestRecordPermission { continuation.resume(returning: $0) }
                }
            }
        }
        guard allowed else { throw AudioCaptureError.permissionDenied }

        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
        } catch {
            try audioSession.setCategory(.record, mode: .measurement, options: [.mixWithOthers])
        }
        try audioSession.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw AudioCaptureError.inputUnavailable
        }

        currentSampleRate = format.sampleRate
        filter.configure(weighting: weighting, sampleRate: currentSampleRate)
        filter.reset()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            self.filter.withFilteredSamples(from: samples) { filtered in
                let level = SoundLevelCalculator.dbfs(samples: filtered)
                self.onLevel?(level, Double(buffer.frameLength) / format.sampleRate)
            }
        }

        engine.prepare()
        do {
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        running = false
        filter.reset()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }
}
