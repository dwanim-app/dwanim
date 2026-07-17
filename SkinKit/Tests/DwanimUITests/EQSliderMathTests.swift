import PlayerCore
import XCTest

@testable import DwanimUI

// MARK: - EQSliderMathTests

/// Tests for `EQSliderMath`, the pure gain<->slider-position mapping the default
/// EQ's vertical band columns use. Every clamp, the top=+12 / bottom=−12
/// orientation, the y-flip (SwiftUI y grows downward), and the non-finite /
/// degenerate-height guards are asserted in memory — the enum touches no View, so
/// it is fully unit-testable in isolation (the `SeekMath` analogue for seeking).
final class EQSliderMathTests: XCTestCase {

    private let lo = EQState.gainRange.lowerBound  // -12
    private let hi = EQState.gainRange.upperBound  // +12

    // MARK: - fraction(forGain:)

    func testFractionFlatIsCentre() {
        XCTAssertEqual(EQSliderMath.fraction(forGain: 0), 0.5, accuracy: 1e-9,
                       "0 dB (flat) maps to the centre of the track")
    }

    func testFractionMaxGainIsTop() {
        XCTAssertEqual(EQSliderMath.fraction(forGain: hi), 1, accuracy: 1e-9,
                       "+12 dB (max boost) maps to the top of the track (fraction 1)")
    }

    func testFractionMinGainIsBottom() {
        XCTAssertEqual(EQSliderMath.fraction(forGain: lo), 0, accuracy: 1e-9,
                       "−12 dB (max cut) maps to the bottom of the track (fraction 0)")
    }

    func testFractionHalfwayBoost() {
        XCTAssertEqual(EQSliderMath.fraction(forGain: 6), 0.75, accuracy: 1e-9,
                       "+6 dB is three-quarters up the track")
    }

    func testFractionClampsAboveMax() {
        XCTAssertEqual(EQSliderMath.fraction(forGain: 100), 1, accuracy: 1e-9,
                       "a gain above +12 clamps to the top")
    }

    func testFractionClampsBelowMin() {
        XCTAssertEqual(EQSliderMath.fraction(forGain: -100), 0, accuracy: 1e-9,
                       "a gain below −12 clamps to the bottom")
    }

    func testFractionNonFiniteGainReadsCentre() {
        XCTAssertEqual(EQSliderMath.fraction(forGain: .nan), 0.5, accuracy: 1e-9,
                       "a NaN gain reads as flat (centre), never NaN")
        XCTAssertEqual(EQSliderMath.fraction(forGain: .infinity), 0.5, accuracy: 1e-9,
                       "an infinite gain reads as flat (centre), never infinite")
    }

    // MARK: - gain(forFraction:)

    func testGainForFractionFlat() {
        XCTAssertEqual(EQSliderMath.gain(forFraction: 0.5), 0, accuracy: 1e-9,
                       "the centre fraction is flat (0 dB)")
    }

    func testGainForFractionTopIsMax() {
        XCTAssertEqual(EQSliderMath.gain(forFraction: 1), hi, accuracy: 1e-9,
                       "the top fraction is max boost (+12 dB)")
    }

    func testGainForFractionBottomIsMin() {
        XCTAssertEqual(EQSliderMath.gain(forFraction: 0), lo, accuracy: 1e-9,
                       "the bottom fraction is max cut (−12 dB)")
    }

    func testGainForFractionClampsOutOfRange() {
        XCTAssertEqual(EQSliderMath.gain(forFraction: 2), hi, accuracy: 1e-9,
                       "a fraction above 1 clamps to max boost")
        XCTAssertEqual(EQSliderMath.gain(forFraction: -1), lo, accuracy: 1e-9,
                       "a fraction below 0 clamps to max cut")
    }

    func testGainForFractionNonFiniteReadsFlat() {
        XCTAssertEqual(EQSliderMath.gain(forFraction: .nan), 0, accuracy: 1e-9,
                       "a NaN fraction reads as flat (0 dB)")
    }

    // MARK: - gain(forY:height:) — the y-flip

    func testGainAtTopOfTrackIsMaxBoost() {
        // y == 0 is the TOP of the track (y grows downward) -> max gain.
        XCTAssertEqual(EQSliderMath.gain(forY: 0, height: 100), hi, accuracy: 1e-9,
                       "a cursor at the track top (y == 0) is max boost (+12)")
    }

    func testGainAtBottomOfTrackIsMaxCut() {
        XCTAssertEqual(EQSliderMath.gain(forY: 100, height: 100), lo, accuracy: 1e-9,
                       "a cursor at the track bottom (y == height) is max cut (−12)")
    }

    func testGainAtCentreOfTrackIsFlat() {
        XCTAssertEqual(EQSliderMath.gain(forY: 50, height: 100), 0, accuracy: 1e-9,
                       "a cursor at the track centre is flat (0 dB)")
    }

    func testGainClampsAboveTrackTop() {
        XCTAssertEqual(EQSliderMath.gain(forY: -20, height: 100), hi, accuracy: 1e-9,
                       "a cursor dragged above the track top clamps to max boost")
    }

    func testGainClampsBelowTrackBottom() {
        XCTAssertEqual(EQSliderMath.gain(forY: 200, height: 100), lo, accuracy: 1e-9,
                       "a cursor dragged below the track bottom clamps to max cut")
    }

    func testGainDegenerateHeightIsFlat() {
        XCTAssertEqual(EQSliderMath.gain(forY: 30, height: 0), 0, accuracy: 1e-9,
                       "a zero track height reads as flat (0 dB) rather than dividing")
        XCTAssertEqual(EQSliderMath.gain(forY: 30, height: -10), 0, accuracy: 1e-9,
                       "a negative track height reads as flat (0 dB)")
    }

    func testGainNonFiniteYIsFlat() {
        XCTAssertEqual(EQSliderMath.gain(forY: .nan, height: 100), 0, accuracy: 1e-9,
                       "a NaN cursor y reads as flat (0 dB), never NaN")
    }

    // MARK: - Round-trip (fraction <-> gain)

    func testFractionGainRoundTrip() {
        for dB in stride(from: -12.0, through: 12.0, by: 1.5) {
            let f = EQSliderMath.fraction(forGain: dB)
            let back = EQSliderMath.gain(forFraction: f)
            XCTAssertEqual(back, dB, accuracy: 1e-9,
                           "fraction(forGain:) and gain(forFraction:) round-trip for \(dB) dB")
        }
    }

    // MARK: - Full-travel DOWNWARD sweep (the default-skin analogue of the
    // classic EQ down-drag regression)
    //
    // The default (Dwennimmen) skin's `EqualizerPanel` is shown by default, so its
    // vertical band columns must ALSO follow the cursor across the whole travel on
    // a downward drag — top = +12, centre = 0, bottom = −12 — never plateauing at 0
    // dB. These sweep the cursor y down a track of the ACTUAL default-column height
    // (`EqualizerPanel` uses a 96 pt track) and assert the gains descend
    // monotonically through 0 to −12, plus the specific centre-and-below values the
    // "stuck at default" symptom describes.

    /// The default-skin band column's track height (points), matching
    /// `EqualizerPanel.trackHeight`.
    private let defaultTrackHeight = 96.0

    /// A cursor sweep DOWN a full-height track produces gains that decrease
    /// monotonically from +12 (top, y == 0) through 0 (centre) to −12 (bottom,
    /// y == height), passing through ~0 dB — never sticking at the centre on the way
    /// down.
    func testDefaultColumnDownwardSweepSpansPlusMinus12() {
        let h = defaultTrackHeight
        var gains: [Double] = []
        var previous = Double.infinity
        // y grows downward, so stepping y up is a physical DOWNWARD drag.
        for step in 0...96 {
            let y = Double(step) / 96.0 * h
            let gain = EQSliderMath.gain(forY: y, height: h)
            gains.append(gain)
            XCTAssertLessThanOrEqual(
                gain, previous + 1e-9,
                "gain must not increase on a downward drag (y \(y): \(gain) > \(previous))")
            previous = gain
        }
        XCTAssertEqual(gains.first ?? .nan, hi, accuracy: 1e-9, "top of the track is +12")
        XCTAssertEqual(gains.last ?? .nan, lo, accuracy: 1e-9,
                       "BOTTOM of the track is −12 (the down-drag reaches max cut)")
        XCTAssertTrue(gains.contains { abs($0) < 1e-6 }, "the sweep passes through 0 dB")
    }

    /// Every cursor y BELOW the centre of the default column is a CUT (< 0 dB) and
    /// each step down cuts further — the default skin's slider does not stick at 0
    /// on a downward drag.
    func testDefaultColumnBelowCentreCutsMonotonically() {
        let h = defaultTrackHeight
        let centreY = h / 2
        XCTAssertEqual(EQSliderMath.gain(forY: centreY, height: h), 0, accuracy: 1e-9,
                       "the track centre reads 0 dB")
        var previous = 0.0
        for step in 1...48 {
            let y = centreY + Double(step)   // below centre (larger y == lower on screen)
            let gain = EQSliderMath.gain(forY: y, height: h)
            XCTAssertLessThan(gain, previous + 1e-9,
                              "y \(y) below centre must cut below the row above it")
            XCTAssertLessThan(gain, 1e-9, "every y below centre is a cut (< 0 dB); y \(y) gave \(gain)")
            previous = gain
        }
        XCTAssertEqual(EQSliderMath.gain(forY: h, height: h), lo, accuracy: 1e-9,
                       "the bottom of the track reaches −12 dB")
    }
}
