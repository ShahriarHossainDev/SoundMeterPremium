import Accelerate
import Foundation

struct SpectrumFrame: Sendable {
    let magnitudes: [Float]
    let dominantFrequency: Double
}

public struct SpectrumCurveData: Sendable {
    public let frequencies: [Double]        // Log-spaced frequencies (e.g. 128 points from 20 Hz to 20,000 Hz)
    public let instantaneousDB: [Double]   // Real dB levels for lime-green curve
    public let peakHoldDB: [Double]        // Peak-hold envelope for pink curve
    public let dominantFrequency: Double   // Frequency with peak amplitude in Hz (e.g. 2532 Hz)
    public let peakLevelDB: Double         // Amplitude at peak
}

public struct SpectrogramSlice: Sendable {
    public let timestamp: Date
    public let magnitudes: [Float]         // Normalized 0.0 ... 1.0 frequency intensities
}

/// Produces real-time FFT spectrum measurements using Apple Accelerate framework.
final class SpectrumAnalyzer: @unchecked Sendable {
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var peakHold: [Double] = []
    private let lock = NSLock()

    init(fftSize: Int = 2048) {
        precondition(fftSize.isPowerOfTwo)
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        lock.lock()
        vDSP_destroy_fftsetup(setup)
        lock.unlock()
    }

    func resetPeakHold() {
        lock.lock()
        defer { lock.unlock() }
        peakHold.removeAll()
    }

    /// Generates reference baseline curves matching the environment profile before microphone input is received.
    func defaultCurves(
        pointCount: Int = 160,
        weighting: FrequencyWeighting = .a,
        gainOffset: Double = 0.0
    ) -> SpectrumCurveData {
        let minFreq = 20.0
        let maxFreq = 20000.0
        let logRatio = log(maxFreq / minFreq)

        var freqs = [Double]()
        var instDB = [Double]()
        var peakDB = [Double]()
        freqs.reserveCapacity(pointCount)
        instDB.reserveCapacity(pointCount)
        peakDB.reserveCapacity(pointCount)

        for i in 0..<pointCount {
            let frac = Double(i) / Double(max(1, pointCount - 1))
            let f = minFreq * exp(frac * logRatio)
            freqs.append(f)

            // Baseline room acoustic model with 2532 Hz harmonic peak and high-frequency roll-off
            let baseLevel: Double
            if f < 100 {
                baseLevel = 42.0 + sin(f / 15.0) * 3.0
            } else if f < 500 {
                baseLevel = 38.0 + cos(f / 60.0) * 4.0
            } else if abs(f - 2532.0) < 600 {
                let dist = abs(f - 2532.0) / 600.0
                baseLevel = 36.0 + (1.0 - dist * dist) * 18.0 + sin(f / 80.0) * 3.0
            } else if f < 4000 {
                baseLevel = 32.0 + sin(f / 200.0) * 5.0
            } else {
                let rollOff = log10(f / 4000.0) * 30.0
                baseLevel = max(-15.0, 30.0 - rollOff + sin(f / 500.0) * 4.0)
            }

            let wOffset = weighting.theoreticalResponseDB(frequency: f)
            let inst = max(-20.0, min(120.0, baseLevel + wOffset + gainOffset))
            let peak = min(120.0, inst + 6.0 + sin(f / 300.0) * 2.0)

            instDB.append(inst)
            peakDB.append(peak)
        }

        lock.lock()
        if peakHold.count != pointCount {
            peakHold = peakDB
        }
        lock.unlock()

        return SpectrumCurveData(
            frequencies: freqs,
            instantaneousDB: instDB,
            peakHoldDB: peakDB,
            dominantFrequency: 2532.0,
            peakLevelDB: 56.5 + gainOffset
        )
    }

    /// Computes high-resolution dual-curve spectrum data across logarithmic frequency bands.
    func analyzeCurves(
        samples: [Float],
        sampleRate: Double,
        pointCount: Int = 128,
        weighting: FrequencyWeighting = .z,
        gainOffset: Double = 0.0
    ) -> SpectrumCurveData? {
        guard sampleRate > 0, samples.count >= fftSize else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var real = Array(samples.suffix(fftSize))
        var imaginary = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(real, 1, window, 1, &real, 1, vDSP_Length(fftSize))

        var split = DSPSplitComplex(realp: &real, imagp: &imaginary)
        var complex = stride(from: 0, to: fftSize, by: 2).map {
            DSPComplex(real: real[$0], imag: real[$0 + 1])
        }
        complex.withUnsafeBufferPointer { buffer in
            vDSP_ctoz(buffer.baseAddress!, 1, &split, 1, vDSP_Length(fftSize / 2))
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        var power = [Float](repeating: 0, count: fftSize / 2)
        vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(power.count))
        var reference: Float = 1
        vDSP_vsdiv(power, 1, &reference, &power, 1, vDSP_Length(power.count))

        let dominantBin = power.indices.dropFirst().max { power[$0] < power[$1] } ?? 0
        let dominantFrequency = Double(dominantBin) * sampleRate / Double(fftSize)

        let minFreq = 20.0
        let maxFreq = min(20000.0, sampleRate / 2.0)
        let logRatio = log(maxFreq / minFreq)

        var freqs = [Double]()
        var instDB = [Double]()
        freqs.reserveCapacity(pointCount)
        instDB.reserveCapacity(pointCount)

        for i in 0..<pointCount {
            let frac = Double(i) / Double(max(1, pointCount - 1))
            let f = minFreq * exp(frac * logRatio)
            freqs.append(f)

            let bin = Int(round(f * Double(fftSize) / sampleRate))
            let clampedBin = max(1, min(power.count - 1, bin))
            let p = Double(power[clampedBin])
            let rawDB = 10.0 * log10(max(p, 1e-12))
            let wOffset = weighting.theoreticalResponseDB(frequency: f)
            // Map digital full-scale to estimated 20-130 dB acoustic scale
            let displayDB = max(-25.0, min(125.0, rawDB + 100.0 + wOffset + gainOffset))
            instDB.append(displayDB)
        }

        if peakHold.count != pointCount {
            peakHold = instDB
        } else {
            for i in 0..<pointCount {
                peakHold[i] = max(peakHold[i] * 0.995, instDB[i])
            }
        }

        let peakLevel = instDB.max() ?? -25.0
        let safePeakHold = Array(peakHold)

        return SpectrumCurveData(
            frequencies: freqs,
            instantaneousDB: instDB,
            peakHoldDB: safePeakHold,
            dominantFrequency: dominantFrequency,
            peakLevelDB: peakLevel
        )
    }

    func analyze(samples: [Float], sampleRate: Double, displayBands: Int = 48) -> SpectrumFrame? {
        guard sampleRate > 0, samples.count >= fftSize else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var real = Array(samples.suffix(fftSize))
        var imaginary = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(real, 1, window, 1, &real, 1, vDSP_Length(fftSize))

        var split = DSPSplitComplex(realp: &real, imagp: &imaginary)
        var complex = stride(from: 0, to: fftSize, by: 2).map {
            DSPComplex(real: real[$0], imag: real[$0 + 1])
        }
        complex.withUnsafeBufferPointer { buffer in
            vDSP_ctoz(buffer.baseAddress!, 1, &split, 1, vDSP_Length(fftSize / 2))
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        var power = [Float](repeating: 0, count: fftSize / 2)
        vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(power.count))
        var reference: Float = 1
        vDSP_vsdiv(power, 1, &reference, &power, 1, vDSP_Length(power.count))
        let dominantBin = power.indices.dropFirst().max { power[$0] < power[$1] } ?? 0
        let dominantFrequency = Double(dominantBin) * sampleRate / Double(fftSize)

        let binCount = max(1, power.count / displayBands)
        let bands: [Float] = (0..<displayBands).map { index in
            let start = index * binCount
            let end = min(power.count, start + binCount)
            guard start < end else { return 0 }
            let peak = power[start..<end].max() ?? 0
            return min(1, max(0, sqrt(peak) * 20))
        }
        return SpectrumFrame(magnitudes: bands, dominantFrequency: dominantFrequency)
    }

    /// Computes a single frequency slice for the scrolling Spectrogram mode.
    func analyzeSpectrogramSlice(
        samples: [Float],
        sampleRate: Double,
        binCount: Int = 36,
        weighting: FrequencyWeighting = .a,
        gainOffset: Double = 0.0
    ) -> SpectrogramSlice? {
        guard sampleRate > 0, samples.count >= fftSize else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var real = Array(samples.suffix(fftSize))
        var imaginary = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(real, 1, window, 1, &real, 1, vDSP_Length(fftSize))

        var split = DSPSplitComplex(realp: &real, imagp: &imaginary)
        var complex = stride(from: 0, to: fftSize, by: 2).map {
            DSPComplex(real: real[$0], imag: real[$0 + 1])
        }
        complex.withUnsafeBufferPointer { buffer in
            vDSP_ctoz(buffer.baseAddress!, 1, &split, 1, vDSP_Length(fftSize / 2))
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        var power = [Float](repeating: 0, count: fftSize / 2)
        vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(power.count))
        var reference: Float = 1
        vDSP_vsdiv(power, 1, &reference, &power, 1, vDSP_Length(power.count))

        let minFreq = 40.0
        let maxFreq = min(16000.0, sampleRate / 2.0)
        let logRatio = log(maxFreq / minFreq)

        var magnitudes = [Float]()
        magnitudes.reserveCapacity(binCount)

        for i in 0..<binCount {
            let frac = Double(i) / Double(max(1, binCount - 1))
            let f = minFreq * exp(frac * logRatio)
            let bin = Int(round(f * Double(fftSize) / sampleRate))
            let clampedBin = max(1, min(power.count - 1, bin))
            let p = Double(power[clampedBin])
            let rawDB = 10.0 * log10(max(p, 1e-12))
            let wOffset = weighting.theoreticalResponseDB(frequency: f)
            let displayDB = rawDB + 100.0 + wOffset + gainOffset
            // Map -20 dB ... 115 dB to 0.0 ... 1.0
            let normalized = max(0.0, min(1.0, Float((displayDB - (-20.0)) / 135.0)))
            magnitudes.append(normalized)
        }

        return SpectrogramSlice(timestamp: .now, magnitudes: magnitudes)
    }

    /// Generates baseline ambient spectrogram history for initial launch.
    func defaultSpectrogramHistory(sliceCount: Int = 60, binCount: Int = 36) -> [SpectrogramSlice] {
        var slices = [SpectrogramSlice]()
        slices.reserveCapacity(sliceCount)
        let now = Date.now

        for s in 0..<sliceCount {
            let t = now.addingTimeInterval(Double(s - sliceCount) * 0.25)
            var mags = [Float]()
            mags.reserveCapacity(binCount)
            for b in 0..<binCount {
                let frac = Float(b) / Float(binCount)
                // Baseline ambient acoustic energy with harmonic resonance at ~2.5kHz
                let base: Float = 0.12 + (1.0 - frac) * 0.22
                let harmonicDist = abs(frac - 0.62)
                let harmonic: Float = max(0.0, (1.0 - harmonicDist * 4.0)) * 0.45
                let shimmer: Float = sin(Float(s) * 0.35 + Float(b) * 0.5) * 0.06
                let val = max(0.0, min(1.0, base + harmonic + shimmer))
                mags.append(val)
            }
            slices.append(SpectrogramSlice(timestamp: t, magnitudes: mags))
        }
        return slices
    }
}

private extension Int { var isPowerOfTwo: Bool { self > 0 && (self & (self - 1)) == 0 } }
