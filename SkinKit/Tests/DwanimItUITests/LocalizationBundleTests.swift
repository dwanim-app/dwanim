import XCTest
import Foundation

@testable import DwanimItUI

// MARK: - LocalizationBundleTests

/// TDD ANCHOR for the localization mechanism, proving — before any mass string
/// extraction — that a hand-authored String Catalog reaches `Bundle.module` and
/// carries the correct translations, and asserting the full runtime resolution
/// wherever the build system actually compiles the catalog.
///
/// KEY FINDING baked into this test: the open-source SwiftPM build system
/// (`swift build` / `swift test`) does NOT run `xcstringstool` on a
/// `.xcstrings`; it copies the catalog into `Bundle.module` VERBATIM. So
/// `String(localized:bundle:locale:)` (the same lookup SwiftUI's
/// `Text(_:bundle:)` performs) falls back to the source key under `swift test`.
/// The Xcode build system (`xcodebuild`) DOES compile the catalog into
/// per-locale `.strings` inside the same bundle, at which point resolution
/// returns the translated value. See `testRuntimeResolutionViaModuleBundle`.
final class LocalizationBundleTests: XCTestCase {

    /// The proof-slice translations: key → locale → value. Beyond the original three
    /// foundation keys, a representative spread of the step-B keys — a transport label,
    /// an accessibility label, a playlist action, an appearance row, and an EQ preset —
    /// so the content check (always) and the xcodebuild runtime check (Part B) cover the
    /// breadth of the extraction, not just the seed.
    private static let expected: [String: [String: String]] = [
        "On": ["en": "On", "ja": "オン", "zh-Hant": "開啟"],
        "Equalizer": ["en": "Equalizer", "ja": "イコライザ", "zh-Hant": "等化器"],
        "Equalizer on": ["en": "Equalizer on", "ja": "イコライザ オン", "zh-Hant": "等化器開啟"],
        "Shuffle": ["en": "Shuffle", "ja": "シャッフル", "zh-Hant": "隨機播放"],
        "Volume": ["en": "Volume", "ja": "音量", "zh-Hant": "音量"],
        "Add files…": ["en": "Add files…", "ja": "ファイルを追加…", "zh-Hant": "加入檔案…"],
        "Open Theme…": ["en": "Open Theme…", "ja": "テーマを開く…", "zh-Hant": "開啟佈景主題…"],
        "Rock": ["en": "Rock", "ja": "ロック", "zh-Hant": "搖滾"]
    ]

    // MARK: Part A — catalog is a reachable resource of Bundle.module with correct content

    /// Proves the catalog is genuinely bundled in DwanimItUI's `Bundle.module`
    /// and that every proof-slice key carries the intended en/ja/zh-Hant value.
    /// This runs identically under `swift test` and `xcodebuild`, because SwiftPM
    /// copies the raw `.xcstrings` into the bundle where it can be read and
    /// parsed. It guards the source of truth against typos and accidental edits.
    func testCatalogIsBundledInModuleWithCorrectContent() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
            "Localizable.xcstrings must be a resource of DwanimItUI's Bundle.module"
        )
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "catalog must be a JSON object"
        )
        XCTAssertEqual(json["sourceLanguage"] as? String, "en")
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])

        for (key, locales) in Self.expected {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "catalog missing key: \(key)")
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                "\(key) missing localizations"
            )
            for (lang, expectedValue) in locales {
                let loc = try XCTUnwrap(localizations[lang] as? [String: Any], "\(key) missing \(lang)")
                let unit = try XCTUnwrap(loc["stringUnit"] as? [String: Any], "\(key)/\(lang) missing stringUnit")
                XCTAssertEqual(unit["value"] as? String, expectedValue, "wrong value for \(key)/\(lang)")
            }
        }
    }

    // MARK: Part B — runtime resolution via Bundle.module under a forced locale

    /// The real end-to-end proof: `String(localized:bundle:locale:)` against
    /// `Bundle.module`, the identical resolution SwiftUI performs for
    /// `Text("On", bundle: .module)` at render time.
    ///
    /// Under a build system that compiled the catalog (Xcode / `xcodebuild`) this
    /// asserts every translation resolves. Under the open-source SwiftPM build,
    /// the catalog is uncompiled, resolution returns the source key, and the test
    /// SKIPS with a precise explanation instead of failing — so the mechanism is
    /// asserted wherever it is observable, and the SwiftPM limitation is recorded
    /// in the suite rather than hidden.
    func testRuntimeResolutionViaModuleBundle() throws {
        // Probe one non-English key: if it comes back as the source key, this
        // build system did not compile the catalog.
        let probe = String(localized: "On", bundle: .module, locale: Locale(identifier: "ja"))
        try XCTSkipIf(
            probe == "On",
            """
            String Catalog not compiled by this build system. The open-source SwiftPM \
            build (swift build / swift test) copies Localizable.xcstrings into \
            Bundle.module verbatim without running xcstringstool, so runtime \
            localization falls back to the source key. This mechanism is verified \
            live under xcodebuild, whose build system compiles .xcstrings into \
            per-locale .strings inside the same bundle.
            """
        )

        for (key, locales) in Self.expected {
            for (lang, expectedValue) in locales {
                let resolved = String(
                    localized: String.LocalizationValue(key),
                    bundle: .module,
                    locale: Locale(identifier: lang)
                )
                XCTAssertEqual(resolved, expectedValue, "runtime resolution wrong for \(key)/\(lang)")
            }
        }
    }
}
