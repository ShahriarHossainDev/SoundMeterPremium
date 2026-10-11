import AVFoundation
import Foundation

@MainActor
final class SpectrumViewModel: ObservableObject {
    @Published private(set) var bars = [Float](repeating: 0, count: 48)
    @Published private(set) var dominantFrequency = 0.0
    @Published var errorMessage: String?
    private let engine = AVAudioEngine()
    private let analyzer = SpectrumAnalyzer()

    func start() {
        Task {
            let session = AVAudioSession.sharedInstance()
            let allowed: Bool
            if session.recordPermission == .granted { allowed = true }
            else { allowed = await withCheckedContinuation { continuation in session.requestRecordPermission { continuation.resume(returning: $0) } } }
            guard allowed else { errorMessage = "Microphone access is required for spectrum analysis."; return }
            do {
                try session.setCategory(.record, mode: .measurement)
                try session.setActive(true)
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                input.removeTap(onBus: 0)
                input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                    guard let channel = buffer.floatChannelData?[0] else { return }
                    let count = Int(buffer.frameLength)
                    let samples = Array(UnsafeBufferPointer(start: channel, count: count))
                    guard let frame = self?.analyzer.analyze(samples: samples, sampleRate: format.sampleRate) else { return }
                    Task { @MainActor in
                        self?.bars = frame.magnitudes
                        self?.dominantFrequency = frame.dominantFrequency
                    }
                }
                engine.prepare(); try engine.start()
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func stop() { if engine.isRunning { engine.stop() }; engine.inputNode.removeTap(onBus: 0); try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    deinit { engine.inputNode.removeTap(onBus: 0) }
}
