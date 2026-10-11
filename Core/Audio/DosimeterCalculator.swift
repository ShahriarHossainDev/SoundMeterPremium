import Foundation

/// Occupational noise dosimeter standards.
public struct DosimeterStandard: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let criterionLevel: Double       // Lc in dB (e.g., 85.0 for NIOSH, 90.0 for OSHA)
    public let exchangeRate: Double         // Q in dB (e.g., 3.0 for NIOSH, 5.0 for OSHA)
    public let defaultThreshold: Double     // Lt in dB (e.g., 80.0 for NIOSH, 80.0/90.0 for OSHA)
    public let criterionDurationHours: Double // Tc in hours (standard 8.0 hours)

    public static let niosh = DosimeterStandard(
        id: "niosh",
        name: "NIOSH",
        criterionLevel: 85.0,
        exchangeRate: 3.0,
        defaultThreshold: 80.0,
        criterionDurationHours: 8.0
    )

    public static let oshaHC = DosimeterStandard(
        id: "osha_hc",
        name: "OSHA (HC)",
        criterionLevel: 90.0,
        exchangeRate: 5.0,
        defaultThreshold: 80.0,
        criterionDurationHours: 8.0
    )

    public static let oshaPEL = DosimeterStandard(
        id: "osha_pel",
        name: "OSHA (PEL)",
        criterionLevel: 90.0,
        exchangeRate: 5.0,
        defaultThreshold: 90.0,
        criterionDurationHours: 8.0
    )

    public static let acgih = DosimeterStandard(
        id: "acgih",
        name: "ACGIH / EU",
        criterionLevel: 85.0,
        exchangeRate: 3.0,
        defaultThreshold: 80.0,
        criterionDurationHours: 8.0
    )

    public static let allStandards: [DosimeterStandard] = [.niosh, .oshaHC, .oshaPEL, .acgih]
}

/// Represents an individual exposure threshold step (e.g., 85 dB, 88 dB) with progress statistics.
public struct ExposureThresholdItem: Identifiable, Equatable {
    public var id: Double { level }
    public let level: Double
    public var elapsedSeconds: Double
    public var maxDurationSeconds: Double

    public var percentage: Double {
        guard maxDurationSeconds > 0 else { return 0.0 }
        return min(100.0, max(0.0, (elapsedSeconds / maxDurationSeconds) * 100.0))
    }

    public var maxDurationFormatted: String {
        let hours = maxDurationSeconds / 3600.0
        if hours >= 1.0 {
            if hours == floor(hours) {
                let hInt = Int(hours)
                return "MAX: \(hInt) \(hInt == 1 ? "hour" : "hours")"
            } else {
                return String(format: "MAX: %.1f hours", hours)
            }
        } else {
            let mins = Int(maxDurationSeconds / 60.0)
            return "MAX: \(mins) mins"
        }
    }

    public var elapsedFormatted: String {
        let total = Int(elapsedSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

/// Dedicated, testable calculation engine for cumulative noise dose and occupational metrics.
public final class DosimeterCalculator {

    public private(set) var standard: DosimeterStandard
    public var threshold: Double
    public var exchangeRate: Double
    public var criterionLevel: Double

    public private(set) var accumulatedDose: Double = 0.0
    public private(set) var elapsedDuration: Double = 0.0
    public private(set) var thresholdItems: [ExposureThresholdItem] = []

    public init(
        standard: DosimeterStandard = .niosh,
        threshold: Double? = nil,
        exchangeRate: Double? = nil
    ) {
        self.standard = standard
        self.threshold = threshold ?? standard.defaultThreshold
        self.exchangeRate = exchangeRate ?? standard.exchangeRate
        self.criterionLevel = standard.criterionLevel
        rebuildThresholdItems()
    }

    /// Updates the selected standard and re-initializes configuration defaults.
    public func setStandard(_ newStandard: DosimeterStandard) {
        self.standard = newStandard
        self.threshold = newStandard.defaultThreshold
        self.exchangeRate = newStandard.exchangeRate
        self.criterionLevel = newStandard.criterionLevel
        rebuildThresholdItems()
    }

    /// Resets all accumulated exposure, dose, and timers to initial state (0.0).
    public func reset() {
        accumulatedDose = 0.0
        elapsedDuration = 0.0
        for i in 0..<thresholdItems.count {
            thresholdItems[i].elapsedSeconds = 0.0
        }
    }

    /// Ingests a sound measurement sample.
    /// - Parameters:
    ///   - levelDB: Instantaneous sound level in dBA SPL.
    ///   - durationSeconds: Buffer duration represented by the sample (typically ~0.04 - 0.25s).
    public func processSample(levelDB: Double, durationSeconds: Double) {
        guard durationSeconds > 0, levelDB.isFinite else { return }

        elapsedDuration += durationSeconds

        // Accumulate dose if level is at or above threshold
        if levelDB >= threshold {
            let tcSeconds = standard.criterionDurationHours * 3600.0
            // Allowed time at this level: Tn = Tc / (2 ^ ((L - Lc) / Q))
            // Incremental dose: dD = 100 * (dt / Tn)
            let exponent = (levelDB - criterionLevel) / exchangeRate
            let incrementalDose = 100.0 * (durationSeconds / tcSeconds) * pow(2.0, exponent)
            accumulatedDose += incrementalDose
        }

        // Update each threshold step's elapsed exposure time
        for i in 0..<thresholdItems.count {
            if levelDB >= thresholdItems[i].level {
                thresholdItems[i].elapsedSeconds += durationSeconds
            }
        }
    }

    /// Time-Weighted Average (TWA) in dB for an 8-hour workday.
    /// TWA = Lc + (Q / log10(2)) * log10(D / 100)
    public var twa: Double {
        guard accumulatedDose > 0.0 else { return 0.0 }
        let logRatio = log10(accumulatedDose / 100.0)
        let factor = exchangeRate / log10(2.0)
        let computed = criterionLevel + (factor * logRatio)
        return max(0.0, computed)
    }

    /// Projected 8-hour dose percentage based on current measurement rate.
    public var projectedDose: Double {
        guard elapsedDuration > 0.0 else { return 0.0 }
        let tcSeconds = standard.criterionDurationHours * 3600.0
        let projection = accumulatedDose * (tcSeconds / elapsedDuration)
        return max(0.0, projection)
    }

    /// Calculates the maximum permissible duration in seconds for a specific sound level.
    public func maximumDuration(forLevel level: Double) -> Double {
        let tcSeconds = standard.criterionDurationHours * 3600.0
        let exponent = (level - criterionLevel) / exchangeRate
        return tcSeconds / pow(2.0, exponent)
    }

    /// Rebuilds threshold step items based on standard, criterion level, and exchange rate.
    public func rebuildThresholdItems() {
        let base = criterionLevel
        let q = exchangeRate
        // Generate steps from criterion level upwards in increments of Q (e.g. 85, 88, 91, 94, 97, 100, 103 for NIOSH)
        var levels: [Double] = []
        for step in 0...6 {
            levels.append(base + Double(step) * q)
        }

        self.thresholdItems = levels.map { lvl in
            let maxSec = maximumDuration(forLevel: lvl)
            return ExposureThresholdItem(
                level: lvl,
                elapsedSeconds: 0.0,
                maxDurationSeconds: maxSec
            )
        }
    }
}
