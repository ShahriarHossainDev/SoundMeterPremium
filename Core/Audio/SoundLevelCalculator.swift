import Foundation

/// Digital audio level calculations. These results are dBFS, not calibrated dB SPL.
enum SoundLevelCalculator {
    static func rms(_ samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for sample in samples {
            let x = Double(sample)
            sum += x * x
        }
        return sqrt(sum / Double(samples.count))
    }

    static func dbfs(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return -120 }
        return max(-120, min(0, 20 * log10(rms)))
    }

    static func dbfs(samples: UnsafeBufferPointer<Float>) -> Double {
        dbfs(rms: rms(samples))
    }

    /// Computes dBFS with a specified frequency weighting filter applied to the PCM samples.
    static func dbfs(
        samples: UnsafeBufferPointer<Float>,
        filter: FrequencyWeightingFilter
    ) -> Double {
        filter.withFilteredSamples(from: samples) { filtered in
            dbfs(samples: filtered)
        }
    }

    static func energyAverageDBFS(_ levels: [Double]) -> Double {
        guard !levels.isEmpty else { return -120 }
        let energy = levels.reduce(0.0) { $0 + pow(10, $1 / 10) } / Double(levels.count)
        guard energy > 0, energy.isFinite else { return -120 }
        return 10 * log10(energy)
    }
}
