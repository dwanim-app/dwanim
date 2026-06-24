import Foundation
import Accelerate

// MARK: - SpectrumAnalyzer

/// Turns a stream of PCM audio samples into a small array of spectrum **bar
/// levels** (each `0...1`) suitable for a classic spectrum-analyzer display.
///
/// This type is pure DSP: it takes `[Float]` samples plus a sample rate and
/// returns bar levels. It owns no audio engine and no UI; a separate audio tap
/// is expected to mix to mono and feed `process(_:sampleRate:)` periodically.
///
/// ## Pipeline (per `process` call)
/// 1. **Frame**: take the most recent `fftSize` samples; if fewer arrive, the
///    front is zero-padded to `fftSize`.
/// 2. **Window**: multiply by a Hann window to reduce spectral leakage.
/// 3. **Real FFT** via `vDSP.FFT`, then per-bin magnitude.
/// 4. **Group** the `fftSize / 2` magnitude bins into `barCount` bars on a
///    log-frequency scale (`LogFrequencyBands`), taking the peak bin per band.
/// 5. **Normalize** each band magnitude to `0...1` on a dB scale against a
///    fixed reference (see `Normalization`).
/// 6. **Peak-decay smoothing** (stateful): `bar = max(newLevel, previous *
///    decay)` so bars jump up instantly and fall gradually.
///
/// ## Assumptions
/// - Input is **mono**. Interleaved/stereo must be mixed down before this call.
/// - Normalization is amplitude-based: a full-scale sine (amplitude 1.0) reads
///   near `1.0` in its bar and silence reads `0`. See `Normalization`.
public final class SpectrumAnalyzer {

    // MARK: - Configuration

    private let barCount: Int
    private let fftSize: Int
    private let decay: Float

    // MARK: - DSP collaborators

    private let window: HannWindow
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let log2Size: vDSP_Length

    // MARK: - State

    /// The previous frame's smoothed bar levels, carried across calls so
    /// peak-decay can hold and fade peaks. Empty until the first `process`.
    private var previousBars: [Float]

    // MARK: - Init

    /// - Parameters:
    ///   - barCount: number of output bars (e.g. ~20). Clamped to `>= 1`.
    ///   - fftSize: power-of-2 analysis window (e.g. 512 or 1024). Rounded up
    ///     to the next power of two if not already one.
    ///   - decay: peak-decay factor in `0...1`; higher falls slower. Default
    ///     `0.85`.
    public init(barCount: Int, fftSize: Int = 512, decay: Float = 0.85) {
        let bars = max(1, barCount)
        let size = SpectrumAnalyzer.nextPowerOfTwo(max(2, fftSize))

        self.barCount = bars
        self.fftSize = size
        self.decay = min(max(decay, 0), 1)
        self.window = HannWindow(length: size)
        self.log2Size = vDSP_Length(log2(Double(size)).rounded())
        self.fft = vDSP.FFT(log2n: log2Size, radix: .radix2, ofType: DSPSplitComplex.self)!
        self.previousBars = [Float](repeating: 0, count: bars)
    }

    // MARK: - Public API

    /// Feeds the latest PCM samples (mono) and returns `barCount` smoothed
    /// levels in `0...1`, grouped on a log-frequency scale. Stateful across
    /// calls (peak-decay smoothing).
    public func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        let frame = windowedFrame(from: samples)
        let magnitudes = magnitudeSpectrum(of: frame)
        let raw = groupIntoBars(magnitudes, sampleRate: sampleRate)
        return smooth(raw)
    }

    // MARK: - Pipeline steps

    /// Builds the `fftSize`-length frame (most recent samples, front zero-padded
    /// if short) and applies the Hann window.
    private func windowedFrame(from samples: [Float]) -> [Float] {
        var frame = [Float](repeating: 0, count: fftSize)
        if samples.count >= fftSize {
            let start = samples.count - fftSize
            frame.replaceSubrange(0..<fftSize, with: samples[start...])
        } else if !samples.isEmpty {
            // Zero-pad in front so the newest samples sit at the frame end.
            frame.replaceSubrange((fftSize - samples.count)..<fftSize, with: samples)
        }
        return window.applied(to: frame)
    }

    /// Runs a real FFT on `frame` and returns the magnitude of each of the
    /// `fftSize / 2` bins.
    private func magnitudeSpectrum(of frame: [Float]) -> [Float] {
        let halfCount = fftSize / 2

        var realIn = [Float](repeating: 0, count: halfCount)
        var imagIn = [Float](repeating: 0, count: halfCount)
        var realOut = [Float](repeating: 0, count: halfCount)
        var imagOut = [Float](repeating: 0, count: halfCount)

        var magnitudes = [Float](repeating: 0, count: halfCount)

        frame.withUnsafeBytes { framePtr in
            let interleaved = framePtr.bindMemory(to: DSPComplex.self)
            realIn.withUnsafeMutableBufferPointer { realInPtr in
                imagIn.withUnsafeMutableBufferPointer { imagInPtr in
                    var splitIn = DSPSplitComplex(realp: realInPtr.baseAddress!,
                                                  imagp: imagInPtr.baseAddress!)
                    // Pack the real frame into split-complex form (even -> real,
                    // odd -> imag) as required by the real-to-complex FFT.
                    vDSP_ctoz(interleaved.baseAddress!, 2, &splitIn, 1,
                              vDSP_Length(halfCount))

                    realOut.withUnsafeMutableBufferPointer { realOutPtr in
                        imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                            var splitOut = DSPSplitComplex(realp: realOutPtr.baseAddress!,
                                                           imagp: imagOutPtr.baseAddress!)
                            fft.forward(input: splitIn, output: &splitOut)
                            // |X[k]| from the split-complex output. vDSP's packed
                            // real FFT scales by 2; fold that into the reference.
                            vDSP.absolute(splitOut, result: &magnitudes)
                        }
                    }
                }
            }
        }
        return magnitudes
    }

    /// Groups magnitude bins into `barCount` bars on a log-frequency scale,
    /// normalizing each bar to `0...1`. Each bar takes the **peak** bin within
    /// its band so a tone never gets diluted by neighboring silent bins.
    private func groupIntoBars(_ magnitudes: [Float], sampleRate: Double) -> [Float] {
        let bands = LogFrequencyBands(barCount: barCount, sampleRate: sampleRate)
        let binWidth = sampleRate / Double(fftSize)

        var peaks = [Float](repeating: 0, count: barCount)
        // Bin 0 is DC; skip it. Iterate the positive-frequency bins.
        for bin in 1..<magnitudes.count {
            let frequency = Double(bin) * binWidth
            let bar = bands.bar(forFrequency: frequency)
            if magnitudes[bin] > peaks[bar] { peaks[bar] = magnitudes[bin] }
        }

        return peaks.map { Normalization.level(forMagnitude: $0, fftSize: fftSize) }
    }

    /// Applies stateful peak-decay smoothing and stores the result for the
    /// next call: `bar = max(new, previous * decay)`.
    private func smooth(_ raw: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: barCount)
        for i in 0..<barCount {
            result[i] = max(raw[i], previousBars[i] * decay)
        }
        previousBars = result
        return result
    }

    // MARK: - Helpers

    private static func nextPowerOfTwo(_ value: Int) -> Int {
        var power = 1
        while power < value { power <<= 1 }
        return power
    }
}
