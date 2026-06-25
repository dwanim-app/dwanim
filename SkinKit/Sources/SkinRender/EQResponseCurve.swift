import Foundation
import SkinKit

// MARK: - EQResponseCurve
//
// The PURE helper that turns the ten EQ band gains into the classic band-response
// CURVE: a polyline of per-column y positions spanning `EQWindowLayout.graphFrame`.
// It needs NO graphics framework and NO `PlayerCore` dependency — raw `[Double]`
// gains (dB) in, `[Int]` window-space y out — the same clean seam
// `EQWindowComposer` already uses (the platform shell unpacks `EQState` into raw
// values). `EQWindowComposer` consumes this to plot the curve over the graph area.
//
// Convention (mirrored from `EQWindowLayout.thumbTopY`): higher gain ⇒ smaller y
// (higher on screen). Inside the graph rectangle, +12 dB pins the curve to the
// graph's TOP row, -12 dB to its BOTTOM row, 0 dB to the centre. The ten bands are
// spread EVENLY across the graph width — band 0 at the left column, band 9 at the
// right column — and the curve interpolates LINEARLY between adjacent band columns,
// clamping at the ends.

public enum EQResponseCurve {

    /// Number of frequency bands the classic graphic equalizer plots.
    private static let bandCount = 10

    /// The dB range the graph maps, identical to the slider travel
    /// (`EQWindowLayout.gainMin/MaxDB`).
    private static let gainMaxDB = EQWindowLayout.gainMaxDB
    private static let gainMinDB = EQWindowLayout.gainMinDB

    // MARK: - Per-column polyline

    /// The response-curve y position for EACH x column across the graph, i.e. one
    /// entry per x in `[graphFrame.x, graphFrame.x + graphFrame.width)`, returned in
    /// left-to-right column order. The returned y values are WINDOW-space rows
    /// (top-left origin), every one inside the graph's `[top, bottom]` rows.
    ///
    /// The ten bands are placed at evenly-spaced graph columns (band 0 = left edge,
    /// band 9 = right edge). Between two adjacent band columns the gain is
    /// interpolated linearly, then mapped to a row with the same +12→top / −12→bottom
    /// scaling the sliders use. Columns left of band 0 / right of band 9 clamp to the
    /// nearest band (flat extension), so the curve never leaves the graph.
    ///
    /// - Parameter bandGains: per-band gains in dB. Any length is tolerated: only
    ///   the first ten entries shape the curve; a short array treats the missing
    ///   high bands as flat (0 dB); a non-finite gain is sanitised (NaN → flat,
    ///   ±inf → the respective clamp end).
    public static func yPositions(forBandGains bandGains: [Double]) -> [Int] {
        let width = EQWindowLayout.graphFrame.width
        guard width > 0 else { return [] }

        // Sanitised gains for exactly the ten bands (missing → 0 dB / flat).
        let gains = (0..<bandCount).map { index -> Double in
            index < bandGains.count ? sanitise(bandGains[index]) : 0
        }

        // Each band's graph column (band 0 → 0, band 9 → width-1).
        let bandColumns = (0..<bandCount).map { graphColumn(forBandIndex: $0) }

        return (0..<width).map { column in
            graphY(forGain: interpolatedGain(atColumn: column, gains: gains, bandColumns: bandColumns))
        }
    }

    // MARK: - Building blocks

    /// The graph column (0-based, left to right) a band index lands on. Band 0 maps
    /// to the left column (0) and the last band to the right column (`width - 1`);
    /// the rest are spread evenly between. A degenerate 1-column graph maps every
    /// band to column 0.
    public static func graphColumn(forBandIndex index: Int) -> Int {
        let width = EQWindowLayout.graphFrame.width
        guard width > 1, bandCount > 1 else { return 0 }
        // Even spread across the full span [0, width-1].
        let clampedIndex = Swift.min(Swift.max(index, 0), bandCount - 1)
        let fraction = Double(clampedIndex) / Double(bandCount - 1)
        let column = (fraction * Double(width - 1)).rounded()
        return Int(column)
    }

    /// The WINDOW-space graph row for a `gain` in dB, mirroring
    /// `EQWindowLayout.thumbTopY`: `+12` ⇒ the graph's TOP row (`graphFrame.y`),
    /// `-12` ⇒ its BOTTOM row (`graphFrame.y + height - 1`), `0` ⇒ the centre row.
    /// Clamped to the dB range and to the graph rows; `NaN` falls back to the centre.
    public static func graphY(forGain gain: Double) -> Int {
        let topY = EQWindowLayout.graphFrame.y
        let bottomY = EQWindowLayout.graphFrame.y + EQWindowLayout.graphFrame.height - 1

        // A degenerate (<=1px) graph collapses to its single row.
        guard bottomY > topY else { return topY }

        let clampedGain = sanitise(gain)
        // fraction 0 at max boost (top), 1 at max cut (bottom).
        let fraction = (gainMaxDB - clampedGain) / (gainMaxDB - gainMinDB)
        let y = Double(topY) + fraction * Double(bottomY - topY)
        let rounded = Int(y.rounded())
        return Swift.min(Swift.max(rounded, topY), bottomY)
    }

    // MARK: - Private

    /// The gain (dB) at a graph `column`, linearly interpolated between the two
    /// bands whose columns bracket it; clamped to the first / last band outside the
    /// band span. `gains` and `bandColumns` are the ten sanitised gains and their
    /// (monotonically increasing) graph columns.
    private static func interpolatedGain(
        atColumn column: Int,
        gains: [Double],
        bandColumns: [Int]
    ) -> Double {
        // Left of the first band column → clamp to band 0; right of the last →
        // clamp to the last band.
        if column <= bandColumns[0] { return gains[0] }
        if column >= bandColumns[bandCount - 1] { return gains[bandCount - 1] }

        // Find the band segment [left, right] that brackets the column, then lerp.
        for segment in 0..<(bandCount - 1) {
            let leftColumn = bandColumns[segment]
            let rightColumn = bandColumns[segment + 1]
            if column >= leftColumn && column <= rightColumn {
                let span = rightColumn - leftColumn
                // Adjacent bands can share a column on a very narrow graph; then the
                // segment is degenerate and the left gain stands in (no divide-by-0).
                guard span > 0 else { return gains[segment] }
                let t = Double(column - leftColumn) / Double(span)
                return gains[segment] + t * (gains[segment + 1] - gains[segment])
            }
        }
        // Unreachable for a monotone column table, but stay total.
        return gains[bandCount - 1]
    }

    /// Sanitise a raw dB gain into the `[-12, +12]` range, mapping `NaN` to flat
    /// (`0`) — the same policy `EQWindowLayout.thumbTopY` uses, so the curve and the
    /// thumbs agree on bad input.
    private static func sanitise(_ gain: Double) -> Double {
        gain.isNaN ? 0 : Swift.min(Swift.max(gain, gainMinDB), gainMaxDB)
    }
}
