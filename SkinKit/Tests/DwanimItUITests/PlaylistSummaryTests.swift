import Foundation
import XCTest

@testable import DwanimItUI

// MARK: - PlaylistSummaryTests

/// Tests for `PlaylistSummary`, the pure footer-copy seam. Since the localization
/// step, the singular/plural grammar that fixes "1 songs, 1 minutes" (E2) lives in
/// the String Catalog's PLURAL VARIATIONS rather than in Swift, so this suite splits
/// into three concerns:
///
/// 1. **Pure minutes math** (`minutes(totalSeconds:)`) — `round(sec/60)`, clamp ≥ 0,
///    no hour rollover. Exact and build-system-independent.
/// 2. **Composed runtime text** for the PLURAL cases (counts ≥ 2 and 0). English takes
///    the `other` form there, which is exactly what the uncompiled-catalog `swift test`
///    path yields, so these assert the real production output too.
/// 3. **Catalog content** for the singular grammar (the E2 fix) and the non-English
///    `other`-only forms — because the OSS SwiftPM build does NOT compile the catalog,
///    the `one` form is unobservable via the runtime path under `swift test` (it would
///    fall back to "1 songs"). Asserting the catalog CONTENT guards the grammar here;
///    `LocalizationBundleTests` + xcodebuild prove the live plural resolution.
final class PlaylistSummaryTests: XCTestCase {

    // MARK: 1 — Pure minutes math (exact, build-system-independent)

    func testMinutesRoundToNearest() {
        // 150 s → 2.5 min → rounds to 3 (round-half-away-from-zero, matching Math.round).
        XCTAssertEqual(PlaylistSummary.minutes(totalSeconds: 150), 3)
    }

    func testMinutesFiveMinutes() {
        XCTAssertEqual(PlaylistSummary.minutes(totalSeconds: 300), 5)
    }

    func testSubMinuteRoundsDownToZero() {
        // 20 s → 0.33 min → rounds to 0.
        XCTAssertEqual(PlaylistSummary.minutes(totalSeconds: 20), 0)
    }

    func testNegativeTotalClampsToZeroMinutes() {
        // A stray negative duration must not produce "-1 minutes".
        XCTAssertEqual(PlaylistSummary.minutes(totalSeconds: -30), 0)
    }

    func testNoHourRollover() {
        // Two hours of audio is "120 minutes", not "2 hours" — minutes-only by design.
        XCTAssertEqual(PlaylistSummary.minutes(totalSeconds: 7200), 120)
        XCTAssertEqual(PlaylistSummary.minutes(totalSeconds: 3660), 61)
    }

    // MARK: 2 — Composed text, plural (`other`) cases: swift-test output == production

    func testManySongsManyMinutes() {
        XCTAssertEqual(PlaylistSummary.text(songCount: 3, totalSeconds: 300), "3 songs, 5 minutes")
    }

    func testZeroSongsZeroMinutes() {
        // Zero takes the English plural, as before.
        XCTAssertEqual(PlaylistSummary.text(songCount: 0, totalSeconds: 0), "0 songs, 0 minutes")
    }

    func testLargeLibraryStaysInMinutes() {
        XCTAssertEqual(PlaylistSummary.text(songCount: 40, totalSeconds: 7200), "40 songs, 120 minutes")
    }

    func testSixtyOneMinutesStaysMinutes() {
        XCTAssertEqual(PlaylistSummary.text(songCount: 12, totalSeconds: 3660), "12 songs, 61 minutes")
    }

    // MARK: 3 — Catalog content guards the singular grammar (the E2 fix)

    func testCatalogEnglishSongPlurals() throws {
        let variations = try pluralVariations(key: "%lld songs", lang: "en")
        XCTAssertEqual(variations["one"], "%lld song", "the E2 fix: exactly one song is singular")
        XCTAssertEqual(variations["other"], "%lld songs")
    }

    func testCatalogEnglishMinutePlurals() throws {
        let variations = try pluralVariations(key: "%lld minutes", lang: "en")
        XCTAssertEqual(variations["one"], "%lld minute", "the E2 fix: exactly one minute is singular")
        XCTAssertEqual(variations["other"], "%lld minutes")
    }

    func testCatalogNonEnglishUsesOtherFormOnly() throws {
        // ja and zh-Hant have no separate singular — only the `other` form is authored.
        for (key, ja, zhHant) in [
            ("%lld songs", "%lld 曲", "%lld 首歌曲"),
            ("%lld minutes", "%lld 分", "%lld 分鐘")
        ] {
            let jaVar = try pluralVariations(key: key, lang: "ja")
            XCTAssertEqual(jaVar["other"], ja)
            XCTAssertNil(jaVar["one"], "\(key)/ja must not carry a separate singular")

            let zhVar = try pluralVariations(key: key, lang: "zh-Hant")
            XCTAssertEqual(zhVar["other"], zhHant)
            XCTAssertNil(zhVar["one"], "\(key)/zh-Hant must not carry a separate singular")
        }
    }

    // MARK: Helper — read a plural variation map (category -> value) from the catalog

    private func pluralVariations(key: String, lang: String) throws -> [String: String] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
            "Localizable.xcstrings must be a resource of Bundle.module"
        )
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "catalog missing key: \(key)")
        let locs = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let loc = try XCTUnwrap(locs[lang] as? [String: Any], "\(key) missing \(lang)")
        let variations = try XCTUnwrap(loc["variations"] as? [String: Any], "\(key)/\(lang) missing variations")
        let plural = try XCTUnwrap(variations["plural"] as? [String: Any], "\(key)/\(lang) missing plural")
        var result: [String: String] = [:]
        for (category, value) in plural {
            if let value = value as? [String: Any],
               let unit = value["stringUnit"] as? [String: Any],
               let string = unit["value"] as? String {
                result[category] = string
            }
        }
        return result
    }
}
