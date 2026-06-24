import XCTest
@testable import SpectrumKit

// MARK: - SpectrumAnalyzerTests

/// Behavioral tests for `SpectrumAnalyzer`, driven entirely by deterministic
/// synthetic signals (sines, sums of sines, silence). The single-tone test
/// mirrors the analyzer's log-frequency bin mapping via `LogFrequencyBands`,
/// so the expected bar is derived from the same math the production code uses
/// rather than hard-coded.
final class SpectrumAnalyzerTests: XCTestCase {

    // MARK: - Signal helpers

    /// Generates `count` samples of a unit-amplitude sine at `frequency` Hz.
    private func sine(
        frequency: Double,
        sampleRate: Double,
        count: Int,
        amplitude: Float = 1.0
    ) -> [Float] {
        (0..<count).map { n in
            amplitude * Float(sin(2.0 * Double.pi * frequency * Double(n) / sampleRate))
        }
    }

    /// Sum of two sines, each at half amplitude so the total stays in range.
    private func twoSines(
        _ f1: Double,
        _ f2: Double,
        sampleRate: Double,
        count: Int
    ) -> [Float] {
        let a = sine(frequency: f1, sampleRate: sampleRate, count: count, amplitude: 0.5)
        let b = sine(frequency: f2, sampleRate: sampleRate, count: count, amplitude: 0.5)
        return zip(a, b).map(+)
    }

    // MARK: - 1. Single tone -> correct bar

    func testSingleToneLandsInExpectedBar() {
        let sampleRate = 44_100.0
        let fftSize = 1024
        let barCount = 20
        let toneFrequency = 1_000.0

        let analyzer = SpectrumAnalyzer(barCount: barCount, fftSize: fftSize)
        let samples = sine(
            frequency: toneFrequency,
            sampleRate: sampleRate,
            count: fftSize
        )
        let bars = analyzer.process(samples, sampleRate: sampleRate)

        // Mirror the production log-bin mapping to know which bar the tone hits.
        let bands = LogFrequencyBands(barCount: barCount, sampleRate: sampleRate)
        let expectedBar = bands.bar(forFrequency: toneFrequency)

        let maxIndex = bars.indices.max(by: { bars[$0] < bars[$1] })!
        XCTAssertEqual(maxIndex, expectedBar,
                       "tone at \(toneFrequency) Hz should peak in bar \(expectedBar)")

        // The peak bar dominates. Immediate neighbors may carry some Hann
        // leakage, but bars two or more bands away must be clearly below.
        let peak = bars[expectedBar]
        XCTAssertGreaterThan(peak, 0.9, "full-scale tone should read near 1.0")
        for (i, level) in bars.enumerated() where abs(i - expectedBar) >= 2 {
            XCTAssertLessThan(level, peak * 0.5,
                              "distant bar \(i) (\(level)) should be well below peak \(peak)")
        }
    }

    // MARK: - 2. Two tones -> two peaks

    func testTwoTonesProduceTwoPeaks() {
        let sampleRate = 44_100.0
        let fftSize = 1024
        let barCount = 20
        let f1 = 500.0
        let f2 = 5_000.0

        let analyzer = SpectrumAnalyzer(barCount: barCount, fftSize: fftSize)
        let samples = twoSines(f1, f2, sampleRate: sampleRate, count: fftSize)
        let bars = analyzer.process(samples, sampleRate: sampleRate)

        let bands = LogFrequencyBands(barCount: barCount, sampleRate: sampleRate)
        let bar1 = bands.bar(forFrequency: f1)
        let bar2 = bands.bar(forFrequency: f2)
        XCTAssertNotEqual(bar1, bar2, "test tones must fall into different bars")

        // Both target bars should be prominent relative to a quiet middle bar.
        let quietBar = bars.enumerated()
            .filter { $0.offset != bar1 && $0.offset != bar2 }
            .min(by: { $0.element < $1.element })!
        XCTAssertGreaterThan(bars[bar1], quietBar.element + 0.2)
        XCTAssertGreaterThan(bars[bar2], quietBar.element + 0.2)
    }

    // MARK: - 3. Silence -> ~0

    func testSilenceProducesNearZeroBars() {
        let analyzer = SpectrumAnalyzer(barCount: 20, fftSize: 1024)
        let bars = analyzer.process(Array(repeating: 0, count: 1024),
                                    sampleRate: 44_100.0)
        for level in bars {
            XCTAssertLessThan(level, 0.001)
        }
    }

    // MARK: - 4. Output shape

    func testOutputShapeAndRange() {
        let barCount = 20
        let analyzer = SpectrumAnalyzer(barCount: barCount, fftSize: 512)
        let samples = sine(frequency: 1_000, sampleRate: 44_100, count: 512)
        let bars = analyzer.process(samples, sampleRate: 44_100)

        XCTAssertEqual(bars.count, barCount)
        for level in bars {
            XCTAssertGreaterThanOrEqual(level, 0)
            XCTAssertLessThanOrEqual(level, 1)
        }
    }

    // MARK: - 5. Peak-decay smoothing

    func testPeakDecayFallsGraduallyTowardZero() {
        let decay: Float = 0.85
        let analyzer = SpectrumAnalyzer(barCount: 20, fftSize: 1024, decay: decay)

        // Loud tone -> bars rise.
        let loud = sine(frequency: 1_000, sampleRate: 44_100, count: 1024)
        let rising = analyzer.process(loud, sampleRate: 44_100)
        let peakBar = rising.indices.max(by: { rising[$0] < rising[$1] })!
        XCTAssertGreaterThan(rising[peakBar], 0.3, "loud tone should drive a bar up")

        // Now feed silence repeatedly: the bar must fall gradually, not snap to 0.
        let silence = Array<Float>(repeating: 0, count: 1024)
        var previous = rising[peakBar]
        var levels: [Float] = [previous]
        for _ in 0..<5 {
            let bars = analyzer.process(silence, sampleRate: 44_100)
            let now = bars[peakBar]
            XCTAssertLessThan(now, previous, "bar should keep falling")
            XCTAssertGreaterThan(now, 0, "bar should not snap to zero immediately")
            // Decay rate matches the configured factor (within tolerance).
            XCTAssertEqual(now, previous * decay, accuracy: previous * decay * 0.001 + 1e-6)
            previous = now
            levels.append(now)
        }
        XCTAssertLessThan(levels.last!, levels.first!)
    }

    // MARK: - 6. Robustness

    func testShorterThanFFTSizeZeroPads() {
        let analyzer = SpectrumAnalyzer(barCount: 20, fftSize: 1024)
        let samples = sine(frequency: 1_000, sampleRate: 44_100, count: 300)
        let bars = analyzer.process(samples, sampleRate: 44_100)
        XCTAssertEqual(bars.count, 20)
        for level in bars {
            XCTAssertGreaterThanOrEqual(level, 0)
            XCTAssertLessThanOrEqual(level, 1)
        }
    }

    func testLongerThanFFTSizeUsesMostRecentWindow() {
        let analyzer = SpectrumAnalyzer(barCount: 20, fftSize: 512)
        let samples = sine(frequency: 1_000, sampleRate: 44_100, count: 4_000)
        let bars = analyzer.process(samples, sampleRate: 44_100)
        XCTAssertEqual(bars.count, 20)

        let bands = LogFrequencyBands(barCount: 20, sampleRate: 44_100)
        let expected = bands.bar(forFrequency: 1_000)
        let maxIndex = bars.indices.max(by: { bars[$0] < bars[$1] })!
        XCTAssertEqual(maxIndex, expected)
    }

    func testEmptyInputDoesNotCrash() {
        let analyzer = SpectrumAnalyzer(barCount: 20, fftSize: 512)
        let bars = analyzer.process([], sampleRate: 44_100)
        XCTAssertEqual(bars.count, 20)
        for level in bars {
            XCTAssertEqual(level, 0, accuracy: 1e-6)
        }
    }

    func testBarCountOfOne() {
        let analyzer = SpectrumAnalyzer(barCount: 1, fftSize: 512)
        let samples = sine(frequency: 1_000, sampleRate: 44_100, count: 512)
        let bars = analyzer.process(samples, sampleRate: 44_100)
        XCTAssertEqual(bars.count, 1)
        XCTAssertGreaterThan(bars[0], 0)
        XCTAssertLessThanOrEqual(bars[0], 1)
    }

    func testTypicalBarCountTwenty() {
        let analyzer = SpectrumAnalyzer(barCount: 20, fftSize: 512)
        let samples = sine(frequency: 1_000, sampleRate: 44_100, count: 512)
        let bars = analyzer.process(samples, sampleRate: 44_100)
        XCTAssertEqual(bars.count, 20)
    }
}
