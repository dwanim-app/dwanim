import Foundation

// MARK: - LogFrequencyBands

/// A pure mapping from continuous frequency to a bar index on a
/// **logarithmic** frequency scale, plus the band edges used to group FFT
/// magnitude bins into bars.
///
/// The audible range is modeled as `[20 Hz, sampleRate / 2]` (Nyquist).
/// Bar `b` covers `[edges[b], edges[b + 1])`, with edges spaced evenly in
/// log-frequency:
///
/// ```
/// edges[b] = minFreq * (maxFreq / minFreq) ^ (b / barCount)
/// ```
///
/// Because the spacing is logarithmic, low bars span a narrow Hz range (few
/// FFT bins each) and high bars span a wide Hz range (many bins each), which
/// matches how listeners perceive pitch and gives the classic spectrum look.
struct LogFrequencyBands {

    // MARK: - Constants

    /// Low end of the modeled audible range. Below this, energy clamps to bar 0.
    static let minFrequency = 20.0

    // MARK: - Stored properties

    let barCount: Int
    let sampleRate: Double

    /// `barCount + 1` band boundaries in Hz, ascending, spanning
    /// `[minFrequency, sampleRate / 2]`.
    let edges: [Double]

    private let minFrequency: Double
    private let maxFrequency: Double
    private let logSpan: Double

    // MARK: - Init

    init(barCount: Int, sampleRate: Double) {
        let bars = max(1, barCount)
        let lo = LogFrequencyBands.minFrequency
        // Guard tiny/odd sample rates so `hi > lo` always holds.
        let hi = max(lo * 2, sampleRate / 2)

        self.barCount = bars
        self.sampleRate = sampleRate
        self.minFrequency = lo
        self.maxFrequency = hi
        self.logSpan = log(hi / lo)

        self.edges = (0...bars).map { b in
            lo * pow(hi / lo, Double(b) / Double(bars))
        }
    }

    // MARK: - Mapping

    /// The bar index a given frequency falls into, clamped to `0..<barCount`.
    func bar(forFrequency frequency: Double) -> Int {
        guard frequency > minFrequency else { return 0 }
        guard frequency < maxFrequency else { return barCount - 1 }
        let position = log(frequency / minFrequency) / logSpan
        let index = Int(position * Double(barCount))
        return min(max(index, 0), barCount - 1)
    }
}
