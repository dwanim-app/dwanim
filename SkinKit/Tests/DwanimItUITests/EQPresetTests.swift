import PlayerCore
import XCTest

@testable import DwanimItUI

// MARK: - EQPresetTests

/// Tests for `EQPreset`, the pure preset-name -> 10-band gain mapping the default
/// EQ's Flat / Rock / Vocal / Bass segmented control applies. The enum touches no
/// View and no engine (just data + a `bands` lookup), so the README curves and the
/// invariants (`EQState.bandCount` values, each within `EQState.gainRange`) are
/// asserted in memory — the `EQSliderMath` analogue for presets.
final class EQPresetTests: XCTestCase {

    // MARK: - Exact README curves

    func testFlatBands() {
        XCTAssertEqual(EQPreset.flat.bands, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                       "Flat is a perfect pass-through: every band 0 dB")
    }

    func testRockBands() {
        XCTAssertEqual(EQPreset.rock.bands, [5, 4, 2, 0, -1, 1, 3, 4, 4, 3],
                       "Rock matches the README array")
    }

    func testVocalBands() {
        XCTAssertEqual(EQPreset.vocal.bands, [-3, -1, 1, 3, 4, 4, 2, 1, 0, -1],
                       "Vocal matches the README array")
    }

    func testBassBands() {
        XCTAssertEqual(EQPreset.bass.bands, [8, 7, 4, 1, 0, 0, 0, -1, -1, -1],
                       "Bass matches the README array")
    }

    // MARK: - Invariants

    func testEveryPresetHasBandCountGains() {
        for preset in EQPreset.allCases {
            XCTAssertEqual(preset.bands.count, EQState.bandCount,
                           "\(preset.rawValue) must supply exactly one gain per band")
        }
    }

    func testEveryGainWithinRange() {
        for preset in EQPreset.allCases {
            for gain in preset.bands {
                XCTAssertTrue(EQState.gainRange.contains(gain),
                              "\(preset.rawValue) gain \(gain) must be within \(EQState.gainRange)")
            }
        }
    }

    // MARK: - Display labels + order

    func testDisplayLabelsAndOrder() {
        XCTAssertEqual(EQPreset.allCases.map(\.rawValue), ["Flat", "Rock", "Vocal", "Bass"],
                       "The segmented control renders Flat / Rock / Vocal / Bass in that order")
    }

    // MARK: - Localized display name is split from the stable identity

    /// The localized `displayName` must NOT disturb `rawValue`, which is the enum's
    /// identity (used for `CaseIterable` order + any serialization). Under the
    /// uncompiled-catalog `swift test` path the localized name resolves to its English
    /// source, which equals the identity — so display and identity coincide in English,
    /// proving the split rewires the render site without changing the identity. The
    /// native ja/zh-Hant forms are proven in the catalog + under xcodebuild.
    func testDisplayNameFallsBackToEnglishSourceAndKeepsIdentity() {
        for preset in EQPreset.allCases {
            XCTAssertEqual(preset.displayName, preset.rawValue,
                           "\(preset) displayName should equal its English identity under swift test")
        }
    }
}
