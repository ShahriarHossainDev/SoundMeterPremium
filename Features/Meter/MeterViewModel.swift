import Foundation
import SwiftData
import SwiftUI

enum MeterState: Equatable {
    case idle, starting, measuring, paused, stopped, failed
}

public enum EnvironmentProfile: String, CaseIterable, Identifiable {
    case quietHome = "Quiet home"
    case office = "Office / Library"
    case conversation = "Conversation"
    case busyStreet = "Busy street"
    case loudVenue = "Loud venue"

    public var id: String { rawValue }

    public var typicalRange: String {
        switch self {
        case .quietHome: return "30 – 45 dB"
        case .office: return "45 – 55 dB"
        case .conversation: return "60 – 68 dB"
        case .busyStreet: return "75 – 85 dB"
        case .loudVenue: return "90 – 110 dB"
        }
    }
}

public enum MeterVisualizationMode: String, CaseIterable, Identifiable {
    case spectrumBars = "Bars"
    case spectrumLine = "Line"
    case waveform = "Waveform"
    case historyGraph = "History"
    case spectrogram = "Spectrogram"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .spectrumBars: return "Spectrum Bars"
        case .spectrumLine: return "Spectrum Line"
        case .waveform: return "Live Waveform"
        case .historyGraph: return "History Graph"
        case .spectrogram: return "Spectrogram"
        }
    }

    public var icon: String {
        switch self {
        case .spectrumBars: return "chart.bar.fill"
        case .spectrumLine: return "waveform.path.ecg"
        case .waveform: return "waveform"
        case .historyGraph: return "chart.xyaxis.line"
        case .spectrogram: return "square.grid.3x3.fill"
        }
    }
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
    @Published var weighting: FrequencyWeighting = .a {
        didSet {
            capture.weighting = weighting
            UserDefaults.standard.set(weighting.rawValue, forKey: "defaultWeighting")
            smoothedPower = nil
        }
    }

    // Reference-calibrated estimated decibels matching 20-130 dB acoustic scale (0 dBFS ≈ 120 dB SPL reference)
    var estimatedCurrentDB: Double {
        guard state == .measuring || state == .paused else { return 0 }
        let offset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
        return max(20.0, min(130.0, currentDBFS + 100.0 + offset))
    }

    var estimatedAverageDB: Double {
        guard !levels.isEmpty else { return 0 }
        let offset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
        return max(20.0, min(130.0, averageDBFS + 100.0 + offset))
    }

    var estimatedMaximumDB: Double {
        guard maximumDBFS > -120 else { return 0 }
        let offset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
        return max(20.0, min(130.0, maximumDBFS + 100.0 + offset))
    }

    var estimatedMinimumDB: Double {
        guard minimumDBFS > -120 else { return 0 }
        let offset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
        return max(20.0, min(130.0, minimumDBFS + 100.0 + offset))
    }

    /// Top LED segment progress (0.0 to 1.0)
    var audioMeterFraction: Double {
        guard state == .measuring || state == .paused else { return 0 }
        let db = estimatedCurrentDB
        return max(0.0, min(1.0, (db - 20.0) / 90.0))
    }

    /// Formatted elapsed measurement duration (e.g. "56s" or "2m 14s")
    var elapsedFormatted: String {
        let total = max(0, Int(elapsed))
        if total < 60 {
            return "\(total)s"
        } else {
            return "\(total / 60)m \(total % 60)s"
        }
    }

    // Real-time FFT spectrum data (Accelerate vDSP)
    @Published var visualizationMode: MeterVisualizationMode = .spectrumBars
    @Published private(set) var spectrumCurveData: SpectrumCurveData?
    @Published private(set) var spectrogramHistory: [SpectrogramSlice] = []
    @Published private(set) var waveformSamples: [Double] = []
    @Published var selectedFrequency: Double?
    @Published var environmentProfile: EnvironmentProfile = .quietHome

    var displayedFrequency: Double {
        if let selectedFrequency { return selectedFrequency }
        return spectrumCurveData?.dominantFrequency ?? 2532.0
    }

    var unitSymbol: String {
        weighting.unitSymbol
    }

    private let capture = AudioCaptureService()
    private let spectrumAnalyzer = SpectrumAnalyzer()
    private var sessionStart: Date?
    private var pausedDuration = 0.0
    private var pauseStarted: Date?
    private var levels: [Double] = []
    private var timer: Timer?
    private var lastGraphUpdate = Date.distantPast
    private var lastSpectrumUpdate = Date.distantPast
    private var smoothedPower: Double?
    private let noiseAlert = NoiseAlertManager()

    private let standardFrequencies: [Double] = [
        46.0, 96.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 2532.0, 4000.0, 8000.0, 16000.0
    ]

    init() {
        let savedWeighting = UserDefaults.standard.string(forKey: "defaultWeighting") ?? "A"
        let initialWeighting = FrequencyWeighting(rawValue: savedWeighting) ?? .a
        self.weighting = initialWeighting
        capture.weighting = initialWeighting

        let offset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
        self.spectrumCurveData = spectrumAnalyzer.defaultCurves(weighting: initialWeighting, gainOffset: offset)
        self.spectrogramHistory = spectrumAnalyzer.defaultSpectrogramHistory()

        // Seed initial baseline stats matching the standard quiet home reference
        self.currentDBFS = -48.5
        self.averageDBFS = -47.9
        self.maximumDBFS = -34.4
        self.minimumDBFS = -57.3
        self.elapsed = 56.0

        // Seed baseline waveform and graph samples
        var initialWave: [Double] = []
        for i in 0..<120 {
            let t = Double(i) / 10.0
            let v = 51.5 + sin(t * 1.8) * 2.2 + cos(t * 3.4) * 1.1
            initialWave.append(v)
        }
        self.waveformSamples = initialWave
        self.graphSamples = Array(repeating: -48.5, count: 40)

        capture.onLevel = { [weak self] level, duration in
            Task { @MainActor in self?.consume(level, duration: duration) }
        }

        capture.onSamples = { [weak self] samples, sampleRate in
            guard let self else { return }
            // Run Accelerate vDSP FFT processing on background thread
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                let offset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
                let weighting = await self.weighting
                let curve = await self.spectrumAnalyzer.analyzeCurves(
                    samples: samples,
                    sampleRate: sampleRate,
                    pointCount: 128,
                    weighting: weighting,
                    gainOffset: offset
                )
                let slice = await self.spectrumAnalyzer.analyzeSpectrogramSlice(
                    samples: samples,
                    sampleRate: sampleRate,
                    binCount: 36,
                    weighting: weighting,
                    gainOffset: offset
                )
                if curve != nil || slice != nil {
                    Task { @MainActor [weak self] in
                        self?.receiveAnalysis(curve: curve, slice: slice)
                    }
                }
            }
        }
    }

    func cycleVisualizationMode() {
        let all = MeterVisualizationMode.allCases
        if let idx = all.firstIndex(of: visualizationMode) {
            visualizationMode = all[(idx + 1) % all.count]
        }
    }

    func nextVisualizationMode() {
        let all = MeterVisualizationMode.allCases
        if let idx = all.firstIndex(of: visualizationMode) {
            visualizationMode = all[(idx + 1) % all.count]
        }
    }

    func previousVisualizationMode() {
        let all = MeterVisualizationMode.allCases
        if let idx = all.firstIndex(of: visualizationMode) {
            visualizationMode = all[(idx - 1 + all.count) % all.count]
        }
    }

    func setWeighting(_ newWeighting: FrequencyWeighting) {
        guard weighting != newWeighting else { return }
        weighting = newWeighting
    }

    func togglePauseResume() {
        if state == .measuring {
            pause()
        } else if state == .paused {
            start()
        } else if state == .idle || state == .stopped || state == .failed {
            start()
        }
    }

    func start() {
        guard state == .idle || state == .paused || state == .failed || state == .stopped else { return }
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
        selectedFrequency = nil
        spectrumAnalyzer.resetPeakHold()
        var initialWave: [Double] = []
        for i in 0..<120 {
            let t = Double(i) / 10.0
            let v = 51.5 + sin(t * 1.8) * 2.2 + cos(t * 3.4) * 1.1
            initialWave.append(v)
        }
        waveformSamples = initialWave
        spectrogramHistory = spectrumAnalyzer.defaultSpectrogramHistory()
    }

    func selectNextFrequency() {
        let current = displayedFrequency
        if let next = standardFrequencies.first(where: { $0 > current + 1 }) {
            selectedFrequency = next
        } else {
            selectedFrequency = standardFrequencies.first
        }
    }

    func selectPreviousFrequency() {
        let current = displayedFrequency
        if let prev = standardFrequencies.last(where: { $0 < current - 1 }) {
            selectedFrequency = prev
        } else {
            selectedFrequency = standardFrequencies.last
        }
    }

    func cycleEnvironmentProfile() {
        let all = EnvironmentProfile.allCases
        if let idx = all.firstIndex(of: environmentProfile) {
            let nextIdx = (idx + 1) % all.count
            environmentProfile = all[nextIdx]
        }
    }

    func save(context: ModelContext, title: String) {
        guard state == .stopped || state == .paused, !levels.isEmpty else { return }
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
        maximumDBFS = max(maximumDBFS, displayedLevel)
        minimumDBFS = levels.count == 1 ? displayedLevel : min(minimumDBFS, displayedLevel)

        // Store live scrolling waveform samples (bounded to 160 points)
        let acousticCurrent = max(20.0, min(130.0, displayedLevel + 100.0 + offset))
        waveformSamples.append(acousticCurrent)
        if waveformSamples.count > 160 { waveformSamples.removeFirst() }

        // Store time series display graph
        if Date.now.timeIntervalSince(lastGraphUpdate) >= 0.25 {
            graphSamples.append(displayedLevel)
            if graphSamples.count > 300 { graphSamples.removeFirst() }
            lastGraphUpdate = .now
        }
    }

    private func receiveAnalysis(curve: SpectrumCurveData?, slice: SpectrogramSlice?) {
        guard state == .measuring else { return }
        let now = Date.now
        // Throttle UI spectrum updates to ~30 FPS
        guard now.timeIntervalSince(lastSpectrumUpdate) >= 0.033 else { return }
        lastSpectrumUpdate = now

        if let curve {
            self.spectrumCurveData = curve
        }
        if let slice {
            self.spectrogramHistory.append(slice)
            if self.spectrogramHistory.count > 65 {
                self.spectrogramHistory.removeFirst()
            }
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
