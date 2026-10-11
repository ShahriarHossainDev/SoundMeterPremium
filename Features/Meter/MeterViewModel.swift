import Foundation
import SwiftData

enum MeterState: Equatable {
    case idle, starting, measuring, paused, stopped, failed
}

@MainActor
final class MeterViewModel: ObservableObject {
    @Published private(set) var state: MeterState = .idle
    @Published private(set) var currentDBFS = -120.0
    @Published private(set) var averageDBFS = -120.0
    @Published private(set) var maximumDBFS = -120.0
    @Published private(set) var minimumDBFS = -120.0
    @Published private(set) var elapsed = 0.0
    @Published private(set) var graphSamples: [Double] = []
    @Published var errorMessage: String?
    @Published var weighting: FrequencyWeighting = .z {
        didSet {
            capture.weighting = weighting
            UserDefaults.standard.set(weighting.rawValue, forKey: "defaultWeighting")
            smoothedPower = nil
        }
    }

    var unitSymbol: String {
        weighting.unitSymbol
    }

    private let capture = AudioCaptureService()
    private var sessionStart: Date?
    private var pausedDuration = 0.0
    private var pauseStarted: Date?
    private var levels: [Double] = []
    private var timer: Timer?
    private var lastGraphUpdate = Date.distantPast
    private var smoothedPower: Double?
    private let noiseAlert = NoiseAlertManager()

    init() {
        let savedWeighting = UserDefaults.standard.string(forKey: "defaultWeighting") ?? "Z"
        let initialWeighting = FrequencyWeighting(rawValue: savedWeighting) ?? .z
        self.weighting = initialWeighting
        capture.weighting = initialWeighting

        capture.onLevel = { [weak self] level, duration in
            Task { @MainActor in self?.consume(level, duration: duration) }
        }
    }

    func setWeighting(_ newWeighting: FrequencyWeighting) {
        guard weighting != newWeighting else { return }
        weighting = newWeighting
    }

    func start() {
        guard state == .idle || state == .paused || state == .failed else { return }
        if UserDefaults.standard.bool(forKey: "noiseAlertEnabled") {
            noiseAlert.requestPermissionIfNeeded()
        }
        errorMessage = nil
        smoothedPower = nil
        capture.weighting = weighting
        state = .starting
        Task {
            do {
                try await capture.start()
                if sessionStart == nil { sessionStart = .now }
                if let pauseStarted {
                    pausedDuration += Date.now.timeIntervalSince(pauseStarted)
                    self.pauseStarted = nil
                }
                state = .measuring
                beginTimer()
            } catch {
                errorMessage = error.localizedDescription
                state = .failed
            }
        }
    }

    func pause() {
        guard state == .measuring else { return }
        capture.stop()
        timer?.invalidate()
        timer = nil
        pauseStarted = .now
        state = .paused
    }

    func stop() {
        guard state == .measuring || state == .paused else { return }
        capture.stop()
        timer?.invalidate()
        timer = nil
        if let pauseStarted {
            pausedDuration += Date.now.timeIntervalSince(pauseStarted)
            self.pauseStarted = nil
        }
        updateElapsed()
        state = .stopped
    }

    func reset() {
        capture.stop()
        timer?.invalidate()
        timer = nil
        state = .idle
        currentDBFS = -120
        averageDBFS = -120
        maximumDBFS = -120
        minimumDBFS = -120
        elapsed = 0
        graphSamples = []
        levels = []
        sessionStart = nil
        pausedDuration = 0
        pauseStarted = nil
        errorMessage = nil
        smoothedPower = nil
    }

    func save(context: ModelContext, title: String) {
        guard state == .stopped, !levels.isEmpty else { return }
        let now = Date.now
        let offset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
        let session = MeasurementSession(
            title: title.isEmpty ? "Sound Session" : title,
            startedAt: sessionStart ?? now,
            endedAt: now,
            duration: elapsed,
            averageDBFS: averageDBFS,
            maximumDBFS: maximumDBFS,
            minimumDBFS: minimumDBFS,
            weighting: weighting.rawValue,
            calibrationOffsetDB: offset
        )
        for (index, level) in graphSamples.enumerated() {
            session.samples.append(MeasurementSample(elapsedSeconds: Double(index), levelDBFS: level, session: session))
        }
        context.insert(session)
        do {
            try context.save()
            reset()
        } catch {
            errorMessage = "Could not save session: \(error.localizedDescription)"
        }
    }

    private func consume(_ level: Double, duration: Double) {
        guard state == .measuring, level.isFinite else { return }
        let response = UserDefaults.standard.string(forKey: "responseTime") ?? "Fast"
        let timeConstant: Double = response == "Slow" ? 0.5 : response == "Impulse" ? 0.05 : 0.2
        let inputPower = pow(10, level / 10)
        let alpha = exp(-max(duration, 0.001) / timeConstant)
        let filteredPower = (smoothedPower ?? inputPower) * alpha + inputPower * (1 - alpha)
        smoothedPower = filteredPower
        let offset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
        let displayedLevel = max(-120, min(30, 10 * log10(max(filteredPower, 1e-12)) + offset))
        currentDBFS = displayedLevel
        noiseAlert.evaluate(
            level: displayedLevel,
            threshold: UserDefaults.standard.object(forKey: "noiseAlertThreshold") as? Double ?? -12,
            enabled: UserDefaults.standard.bool(forKey: "noiseAlertEnabled")
        )
        levels.append(displayedLevel)
        averageDBFS = SoundLevelCalculator.energyAverageDBFS(levels)
        maximumDBFS = max(maximumDBFS, level)
        minimumDBFS = levels.count == 1 ? level : min(minimumDBFS, level)

        // Limit graph storage to the most recent 180 display samples.
        if Date.now.timeIntervalSince(lastGraphUpdate) >= 0.25 {
            graphSamples.append(level)
            if graphSamples.count > 180 { graphSamples.removeFirst() }
            lastGraphUpdate = .now
        }
    }

    private func beginTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateElapsed() }
        }
    }

    private func updateElapsed() {
        guard let sessionStart else { return }
        let activePause = pauseStarted.map { Date.now.timeIntervalSince($0) } ?? 0
        elapsed = max(0, Date.now.timeIntervalSince(sessionStart) - pausedDuration - activePause)
    }
}
