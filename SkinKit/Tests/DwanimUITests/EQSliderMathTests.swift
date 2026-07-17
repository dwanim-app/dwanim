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
}
