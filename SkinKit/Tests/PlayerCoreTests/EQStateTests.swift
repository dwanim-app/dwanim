import Foundation
import XCTest
@testable import PlayerCore

// MARK: - EQStateTests

/// Tests for `EQState`, the pure 10-band graphic-equalizer state. Every clamping
/// rule, default, bounds-check, and `Equatable` case is asserted in memory — the
/// type owns no engine, so it is fully unit-testable in isolation.
final class EQStateTests: XCTestCase {

    // MARK: - Defaults (flat + disabled)

    func testDefaultIsFlatAndDisabled() {
        let eq = EQState()
        XCTAssertFalse(eq.enabled, "a fresh equalizer is disabled")
        XCTAssertEqual(eq.preamp, 0, "preamp defaults to flat (0 dB)")
        XCTAssertEqual(
            eq.bands,
            [Double](repeating: 0, count: 10),
            "all 10 bands default to flat (0 dB)"
        )
    }

    func testBandCountIsTen() {
        XCTAssertEqual(EQState.bandCount, 10)
        XCTAssertEqual(EQState().bands.count, 10)
    }

    func testGainRangeIsClassicTwelve() {
        XCTAssertEqual(EQState.gainRange.lowerBound, -12)
        XCTAssertEqual(EQState.gainRange.upperBound, 12)
    }

    // MARK: - Preamp clamping

    func testSetPreampClampsHigh() {
        var eq = EQState()
        eq.setPreamp(100)
        XCTAssertEqual(eq.preamp, 12, "preamp above +12 clamps to +12")
    }

    func testSetPreampClampsLow() {
        var eq = EQState()
        eq.setPreamp(-100)
        XCTAssertEqual(eq.preamp, -12, "preamp below -12 clamps to -12")
    }

    func testSetPreampInRangePassesThrough() {
        var eq = EQState()
        eq.setPreamp(6.5)
        XCTAssertEqual(eq.preamp, 6.5)
    }

    func testSetPreampNonFiniteIsIgnored() {
        var eq = EQState()
        eq.setPreamp(3)
        eq.setPreamp(.nan)
        XCTAssertEqual(eq.preamp, 3, "NaN preamp is a no-op")
        eq.setPreamp(.infinity)
        XCTAssertEqual(eq.preamp, 3, "infinite preamp is a no-op")
    }

    // MARK: - Band clamping

    func testSetBandClampsHigh() {
        var eq = EQState()
        eq.setBand(0, dB: 50)
        XCTAssertEqual(eq.bands[0], 12, "band gain above +12 clamps to +12")
    }

    func testSetBandClampsLow() {
        var eq = EQState()
        eq.setBand(9, dB: -50)
        XCTAssertEqual(eq.bands[9], -12, "band gain below -12 clamps to -12")
    }

    func testSetBandInRangePassesThrough() {
        var eq = EQState()
        eq.setBand(4, dB: -7.25)
        XCTAssertEqual(eq.bands[4], -7.25)
    }

    func testSetBandOnlyAffectsTargetBand() {
        var eq = EQState()
        eq.setBand(3, dB: 9)
        for index in 0..<EQState.bandCount where index != 3 {
            XCTAssertEqual(eq.bands[index], 0, "untouched band \(index) stays flat")
        }
        XCTAssertEqual(eq.bands[3], 9)
    }

    // MARK: - Band index bounds

    func testSetBandNegativeIndexIsNoOp() {
        var eq = EQState()
        eq.setBand(-1, dB: 10)
        XCTAssertEqual(
            eq.bands,
            [Double](repeating: 0, count: 10),
            "a negative index is a guarded no-op"
        )
    }

    func testSetBandTooLargeIndexIsNoOp() {
        var eq = EQState()
        eq.setBand(10, dB: 10) // valid indices are 0...9
        XCTAssertEqual(
            eq.bands,
            [Double](repeating: 0, count: 10),
            "an out-of-range high index is a guarded no-op"
        )
        XCTAssertEqual(eq.bands.count, 10, "array size is never grown")
    }

    func testSetBandNonFiniteIsIgnored() {
        var eq = EQState()
        eq.setBand(2, dB: 5)
        eq.setBand(2, dB: .nan)
        XCTAssertEqual(eq.bands[2], 5, "NaN band gain is a no-op")
    }

    // MARK: - Memberwise init clamps and resizes

    func testInitClampsAndResizes() {
        let eq = EQState(enabled: true, preamp: 99, bands: [50, -99, 3])
        XCTAssertTrue(eq.enabled)
        XCTAssertEqual(eq.preamp, 12, "init clamps preamp")
        XCTAssertEqual(eq.bands.count, 10, "init pads a short bands array to 10")
        XCTAssertEqual(eq.bands[0], 12, "init clamps band gains high")
        XCTAssertEqual(eq.bands[1], -12, "init clamps band gains low")
        XCTAssertEqual(eq.bands[2], 3)
        XCTAssertEqual(eq.bands[9], 0, "padded tail bands are flat")
    }

    func testInitTruncatesLongBandsArray() {
        let eq = EQState(
            enabled: false,
            preamp: 0,
            bands: [Double](repeating: 4, count: 20)
        )
        XCTAssertEqual(eq.bands.count, 10, "init truncates an over-long bands array")
    }

    // MARK: - Equatable

    func testEquatable() {
        var a = EQState()
        var b = EQState()
        XCTAssertEqual(a, b, "two fresh equalizers are equal")

        a.setBand(0, dB: 6)
        XCTAssertNotEqual(a, b, "differing band gains are unequal")

        b.setBand(0, dB: 6)
        XCTAssertEqual(a, b, "matching band gains are equal again")

        a.enabled = true
        XCTAssertNotEqual(a, b, "differing enabled flags are unequal")
    }
}
