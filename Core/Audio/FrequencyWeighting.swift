import Foundation

/// Standard acoustic frequency weighting standards according to IEC 61672-1.
public enum FrequencyWeighting: String, CaseIterable, Identifiable, Codable, Sendable {
    case z = "Z"
    case a = "A"
    case c = "C"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .z: return "Z — Flat / Unweighted"
        case .a: return "A — Human Hearing (dBA)"
        case .c: return "C — Low Frequency / Peak (dBC)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .z: return "Z-Weighting"
        case .a: return "A-Weighting"
        case .c: return "C-Weighting"
        }
    }

    public var unitSymbol: String {
        switch self {
        case .z: return "dBZ"
        case .a: return "dBA"
        case .c: return "dBC"
        }
    }

    public var descriptionText: String {
        switch self {
        case .z:
            return "Zero weighting provides a flat frequency response (10 Hz – 20 kHz) without any spectral filtering."
        case .a:
            return "A-weighting follows the frequency sensitivity of human hearing (IEC 61672-1), de-emphasizing low and very high frequencies. Standard for general environmental and occupational noise monitoring."
        case .c:
            return "C-weighting retains low-frequency acoustic energy (IEC 61672-1), falling off gently below 31.5 Hz and above 8 kHz. Standard for peak noise, engines, machinery, and loud industrial environments."
        }
    }

    /// Theoretical IEC 61672-1 frequency response in dB at a given frequency.
    public func theoreticalResponseDB(frequency: Double) -> Double {
        guard frequency > 0 else { return -120 }
        switch self {
        case .z:
            return 0.0
        case .c:
            let f2 = frequency * frequency
            let f1_2 = 20.598997 * 20.598997
            let f4_2 = 12194.217 * 12194.217
            let num = f4_2 * f2
            let den = (f2 + f1_2) * (f2 + f4_2)
            guard den > 0 else { return -120 }
            return 20.0 * log10(num / den) + 0.0619
        case .a:
            let f2 = frequency * frequency
            let f4 = f2 * f2
            let f1_2 = 20.598997 * 20.598997
            let f2_2 = 107.65265 * 107.65265
            let f3_2 = 737.86223 * 737.86223
            let f4_2 = 12194.217 * 12194.217
            let num = f4_2 * f4
            let den = (f2 + f1_2) * sqrt((f2 + f2_2) * (f2 + f3_2)) * (f2 + f4_2)
            guard den > 0 else { return -120 }
            return 20.0 * log10(num / den) + 1.9997
        }
    }
}

/// A second-order IIR biquad section implemented using Transposed Direct Form II.
public struct BiquadSection: Sendable {
    public var b0: Double
    public var b1: Double
    public var b2: Double
    public var a1: Double
    public var a2: Double

    // State registers for Transposed Direct Form II
    private var s1: Double = 0.0
    private var s2: Double = 0.0

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    public mutating func reset() {
        s1 = 0.0
        s2 = 0.0
    }

    @inline(__always)
    public mutating func processSample(_ x: Double) -> Double {
        let y = b0 * x + s1
        s1 = b1 * x - a1 * y + s2
        s2 = b2 * x - a2 * y
        return y
    }

    /// Evaluates the frequency magnitude response |H(e^(j*omega))| at a given frequency.
    public func magnitudeResponse(frequency: Double, sampleRate: Double) -> Double {
        guard sampleRate > 0 else { return 1.0 }
        let omega = 2.0 * Double.pi * frequency / sampleRate
        let cosw = cos(omega)
        let cos2w = cos(2.0 * omega)
        let sinw = sin(omega)
        let sin2w = sin(2.0 * omega)

        let numReal = b0 + b1 * cosw + b2 * cos2w
        let numImag = -(b1 * sinw + b2 * sin2w)
        let denReal = 1.0 + a1 * cosw + a2 * cos2w
        let denImag = -(a1 * sinw + a2 * sin2w)

        let numMag2 = numReal * numReal + numImag * numImag
        let denMag2 = denReal * denReal + denImag * denImag
        guard denMag2 > 1e-15 else { return 1.0 }
        return sqrt(numMag2 / denMag2)
    }
}

/// Digital filter engine implementing continuous-time IEC 61672-1 A, C, and Z weighting
/// using cascaded biquads via the bilinear transform, normalized to 0 dB at 1000 Hz.
public final class FrequencyWeightingFilter {
    private var sections: [BiquadSection] = []
    private var scratch: [Float] = []
    public private(set) var weighting: FrequencyWeighting = .z
    public private(set) var sampleRate: Double = 48000.0

    public init(weighting: FrequencyWeighting = .z, sampleRate: Double = 48000.0) {
        configure(weighting: weighting, sampleRate: sampleRate)
    }

    /// Reconfigures filter if weighting or sample rate has changed.
    public func configure(weighting: FrequencyWeighting, sampleRate: Double) {
        guard weighting != self.weighting || sampleRate != self.sampleRate || sections.isEmpty else { return }
        self.weighting = weighting
        self.sampleRate = sampleRate
        rebuildSections()
    }

    /// Resets the internal delay state registers (clears transient history).
    public func reset() {
        for i in 0..<sections.count {
            sections[i].reset()
        }
    }

    private func rebuildSections() {
        guard sampleRate > 0 else {
            sections = []
            return
        }
        switch weighting {
        case .z:
            sections = []
        case .c:
            sections = Self.designCSections(sampleRate: sampleRate)
        case .a:
            sections = Self.designASections(sampleRate: sampleRate)
        }
    }

    /// Processes PCM samples through the active weighting filter.
    /// Passes the filtered buffer directly to the closure without memory allocations.
    /// If weighting is Z, passes the original samples without overhead.
    public func withFilteredSamples<R>(
        from samples: UnsafeBufferPointer<Float>,
        _ body: (UnsafeBufferPointer<Float>) throws -> R
    ) rethrows -> R {
        guard weighting != .z, !sections.isEmpty, !samples.isEmpty else {
            return try body(samples)
        }

        let count = samples.count
        if scratch.count < count {
            scratch = [Float](repeating: 0, count: count)
        }

        // First section processes input samples and outputs to scratch
        for i in 0..<count {
            scratch[i] = Float(sections[0].processSample(Double(samples[i])))
        }

        // Subsequent cascaded sections filter scratch in-place
        for s in 1..<sections.count {
            for i in 0..<count {
                scratch[i] = Float(sections[s].processSample(Double(scratch[i])))
            }
        }

        return try scratch.withUnsafeBufferPointer { buffer in
            let slice = UnsafeBufferPointer(start: buffer.baseAddress, count: count)
            return try body(slice)
        }
    }

    /// Convenient helper for array processing.
    public func filter(samples: [Float]) -> [Float] {
        samples.withUnsafeBufferPointer { ptr in
            withFilteredSamples(from: ptr) { Array($0) }
        }
    }

    // MARK: - Filter Design Mathematics

    /// Designs two cascaded biquads for IEC 61672-1 C-weighting.
    public static func designCSections(sampleRate: Double) -> [BiquadSection] {
        let f1 = 20.598997
        let f4 = 12194.217
        let w1 = 2.0 * Double.pi * f1
        let w4 = 2.0 * Double.pi * f4
        let c = 2.0 * sampleRate

        // High-pass section: zeros at 0, repeated pole at w1
        let p1 = (c - w1) / (c + w1)
        let g1 = pow(c / (c + w1), 2)
        var s1 = BiquadSection(b0: g1, b1: -2.0 * g1, b2: g1, a1: -2.0 * p1, a2: p1 * p1)

        // Low-pass section: zeros at infinity, repeated pole at w4
        let p4 = (c - w4) / (c + w4)
        let g4 = pow(w4 / (c + w4), 2)
        let s2 = BiquadSection(b0: g4, b1: 2.0 * g4, b2: g4, a1: -2.0 * p4, a2: p4 * p4)

        // Normalize response at 1000 Hz to exactly 1.0 (0.00 dB)
        let mag1000 = s1.magnitudeResponse(frequency: 1000.0, sampleRate: sampleRate) *
                      s2.magnitudeResponse(frequency: 1000.0, sampleRate: sampleRate)
        if mag1000 > 1e-6 {
            let norm = 1.0 / mag1000
            s1.b0 *= norm
            s1.b1 *= norm
            s1.b2 *= norm
        }

        return [s1, s2]
    }

    /// Designs three cascaded biquads for IEC 61672-1 A-weighting.
    public static func designASections(sampleRate: Double) -> [BiquadSection] {
        let f1 = 20.598997
        let f2 = 107.65265
        let f3 = 737.86223
        let f4 = 12194.217

        let w1 = 2.0 * Double.pi * f1
        let w2 = 2.0 * Double.pi * f2
        let w3 = 2.0 * Double.pi * f3
        let w4 = 2.0 * Double.pi * f4
        let c = 2.0 * sampleRate

        // Section 1: High-pass (repeated pole at w1, zeros at 0)
        let p1 = (c - w1) / (c + w1)
        let g1 = pow(c / (c + w1), 2)
        var s1 = BiquadSection(b0: g1, b1: -2.0 * g1, b2: g1, a1: -2.0 * p1, a2: p1 * p1)

        // Section 2: Low-pass (repeated pole at w4, zeros at infinity)
        let p4 = (c - w4) / (c + w4)
        let g4 = pow(w4 / (c + w4), 2)
        let s2 = BiquadSection(b0: g4, b1: 2.0 * g4, b2: g4, a1: -2.0 * p4, a2: p4 * p4)

        // Section 3: Mid-band shaping (poles at w2, w3, zeros at 0)
        let d3 = (c + w2) * (c + w3)
        let g3 = (c * c) / d3
        let a1_3 = (-2.0 * c * c + 2.0 * w2 * w3) / d3
        let a2_3 = ((c - w2) * (c - w3)) / d3
        let s3 = BiquadSection(b0: g3, b1: -2.0 * g3, b2: g3, a1: a1_3, a2: a2_3)

        // Normalize response at 1000 Hz to exactly 1.0 (0.00 dB)
        let mag1000 = s1.magnitudeResponse(frequency: 1000.0, sampleRate: sampleRate) *
                      s2.magnitudeResponse(frequency: 1000.0, sampleRate: sampleRate) *
                      s3.magnitudeResponse(frequency: 1000.0, sampleRate: sampleRate)
        if mag1000 > 1e-6 {
            let norm = 1.0 / mag1000
            s1.b0 *= norm
            s1.b1 *= norm
            s1.b2 *= norm
        }

        return [s1, s2, s3]
    }
}
