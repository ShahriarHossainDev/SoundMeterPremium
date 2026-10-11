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
    private var interruptionObserver: Any?
    private var routeChangeObserver: Any?

    /// Frequency weighting filter applied to captured audio buffers.
    var weighting: FrequencyWeighting = .z {
        didSet {
            filter.configure(weighting: weighting, sampleRate: currentSampleRate)
        }
    }

    /// Level in dBFS and the duration represented by the buffer.
    var onLevel: ((Double, Double) -> Void)?

    /// Raw PCM samples and sample rate for live spectrum analysis.
    var onSamples: (([Float], Double) -> Void)?

    init() {
        setupSessionObservers()
    }

    private func setupSessionObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification: notification)
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification: notification)
        }
    }

    private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if running {
                engine.pause()
            }
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume), running {
                    try? engine.start()
                }
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(notification: Notification) {
        guard running else { return }
        // Verify engine is still functional following hardware route change
        if !engine.isRunning {
            try? engine.start()
        }
    }

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
            let frameCount = Int(buffer.frameLength)
            let samples = UnsafeBufferPointer(start: channel, count: frameCount)

            // Forward samples for real-time FFT spectrum analysis
            if let onSamples = self.onSamples {
                let sampleArray = Array(samples)
                onSamples(sampleArray, format.sampleRate)
            }

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
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }
}
