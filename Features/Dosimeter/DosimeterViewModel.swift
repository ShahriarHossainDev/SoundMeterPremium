import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class DosimeterViewModel: ObservableObject {
    @Published private(set) var dose: Double = 0.0
    @Published private(set) var durationString: String = "00:00"
    @Published private(set) var instantaneousDB: Double = 0.0
    @Published private(set) var twaDB: Double = 0.0
    @Published private(set) var projectedDose: Double = 0.0
    @Published private(set) var thresholdItems: [ExposureThresholdItem] = []

    @Published var selectedStandard: DosimeterStandard {
        didSet {
            calculator.setStandard(selectedStandard)
            threshold = calculator.threshold
            exchangeRate = calculator.exchangeRate
            thresholdItems = calculator.thresholdItems
            UserDefaults.standard.set(selectedStandard.id, forKey: "dosimeterStandardID")
            UserDefaults.standard.set(calculator.threshold, forKey: "dosimeterThreshold")
        }
    }

    @Published var threshold: Double {
        didSet {
            calculator.threshold = threshold
            UserDefaults.standard.set(threshold, forKey: "dosimeterThreshold")
        }
    }

    @Published var exchangeRate: Double {
        didSet {
            calculator.exchangeRate = exchangeRate
            calculator.rebuildThresholdItems()
            thresholdItems = calculator.thresholdItems
        }
    }

    @Published private(set) var isMeasuring: Bool = false
    @Published var errorMessage: String?

    private let calculator: DosimeterCalculator
    private let capture = AudioCaptureService()
    private var smoothedInstantaneous: Double?

    init() {
        let savedStandardID = UserDefaults.standard.string(forKey: "dosimeterStandardID") ?? "niosh"
        let standard = DosimeterStandard.allStandards.first(where: { $0.id == savedStandardID }) ?? .niosh
        let calc = DosimeterCalculator(standard: standard)
        let savedThreshold = UserDefaults.standard.object(forKey: "dosimeterThreshold") as? Double ?? standard.defaultThreshold
        calc.threshold = savedThreshold

        self.calculator = calc
        self.selectedStandard = standard
        self.threshold = savedThreshold
        self.exchangeRate = calc.exchangeRate
        self.thresholdItems = calc.thresholdItems
        self.capture.weighting = .a // NIOSH and OSHA standards require A-weighting

        self.capture.onLevel = { [weak self] rawDBFS, duration in
            DispatchQueue.main.async {
                self?.handleSample(rawDBFS: rawDBFS, duration: duration)
            }
        }
    }

    deinit {
        capture.stop()
    }

    func reloadConfiguration() {
        let savedStandardID = UserDefaults.standard.string(forKey: "dosimeterStandardID") ?? "niosh"
        if let standard = DosimeterStandard.allStandards.first(where: { $0.id == savedStandardID }), standard != selectedStandard {
            selectedStandard = standard
        }
        let savedThreshold = UserDefaults.standard.object(forKey: "dosimeterThreshold") as? Double ?? selectedStandard.defaultThreshold
        if savedThreshold != threshold {
            threshold = savedThreshold
        }
    }

    func start() {
        guard !isMeasuring else { return }
        reloadConfiguration()
        errorMessage = nil
        capture.weighting = .a

        Task {
            do {
                try await capture.start()
                isMeasuring = true
            } catch {
                errorMessage = error.localizedDescription
                isMeasuring = false
            }
        }
    }

    func stop() {
        guard isMeasuring else { return }
        capture.stop()
        isMeasuring = false
    }

    func reset() {
        calculator.reset()
        smoothedInstantaneous = nil
        dose = 0.0
        durationString = "00:00"
        twaDB = 0.0
        projectedDose = 0.0
        thresholdItems = calculator.thresholdItems
    }

    private func handleSample(rawDBFS: Double, duration: Double) {
        guard isMeasuring, rawDBFS.isFinite else { return }

        // Convert digital dBFS to estimated dBA SPL using baseline offset + user microphone calibration
        let userOffset = UserDefaults.standard.double(forKey: "microphoneGainOffset")
        let estimatedSPL = max(25.0, min(135.0, rawDBFS + 100.0 + userOffset))

        // Exponential smoothing for instantaneous readout stability (~200ms time constant)
        let alpha = 0.25
        let smoothed = (smoothedInstantaneous ?? estimatedSPL) * (1 - alpha) + estimatedSPL * alpha
        smoothedInstantaneous = smoothed
        instantaneousDB = smoothed

        // Process exposure dose in calculation engine
        calculator.processSample(levelDB: estimatedSPL, durationSeconds: duration)

        // Publish live updates
        dose = calculator.accumulatedDose
        twaDB = calculator.twa
        projectedDose = calculator.projectedDose
        thresholdItems = calculator.thresholdItems
        durationString = formatDuration(calculator.elapsedDuration)
    }

    private func formatDuration(_ totalSeconds: Double) -> String {
        let total = Int(totalSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d:%02d", minutes, seconds)
        }
    }
}
