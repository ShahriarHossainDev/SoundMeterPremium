import Accelerate
import Foundation

struct SpectrumFrame {
    let magnitudes: [Float]
    let dominantFrequency: Double
}

/// Produces a compact, display-ready spectrum from a PCM buffer.
final class SpectrumAnalyzer {
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]

    init(fftSize: Int = 2048) {
        precondition(fftSize.isPowerOfTwo)
        self.fftSize = fftSize
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func analyze(samples: [Float], sampleRate: Double, displayBands: Int = 48) -> SpectrumFrame? {
        guard sampleRate > 0, samples.count >= fftSize else { return nil }
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
}

private extension Int { var isPowerOfTwo: Bool { self > 0 && (self & (self - 1)) == 0 } }
