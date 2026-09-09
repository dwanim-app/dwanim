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
        "Rock": ["en": "Rock", "ja": "ロック", "zh-Hant": "搖滾"],
        // The 3-state Repeat pill: ONE visible word (the pill shows the same
        // string in every state — the repeat-one "1" is an overlaid badge, not a
        // longer label, because a state-dependent width re-flowed the toggle row
        // and overflowed its 176 pt zone in Japanese) plus one accessibility
        // label per state, which is where the three states are actually SAID.
        // They are listed here (rather than only in a content-only test) so the
        // xcodebuild half of this file proves they RESOLVE at runtime too — a
        // SwiftUI literal inside the package silently falls back to English if it
        // ever loses its `bundle: .module`.
        //
        // The Japanese state labels use the vocabulary a Japanese music player
        // actually uses — 全曲リピート / 1曲リピート / リピートオフ — rather than
        // the earlier "リピート: 全曲" calque of the English word order.
        "Repeat": ["en": "Repeat", "ja": "リピート", "zh-Hant": "重複播放"],
        "Repeat all": ["en": "Repeat all", "ja": "全曲リピート", "zh-Hant": "重複播放：全部"],
        "Repeat off": ["en": "Repeat off", "ja": "リピートオフ", "zh-Hant": "重複播放：關閉"],
        "Repeat one": ["en": "Repeat one", "ja": "1曲リピート", "zh-Hant": "重複播放：單曲"]
    ]

    /// The repeat labels must be DISTINCT in every locale, in both directions:
    /// three accessibility labels that collapsed to one string would leave a
    /// VoiceOver user unable to tell `.all` from `.one`, and a translation that
    /// duplicated another key's value would be a silent copy-paste error. Asserted
    /// on catalog CONTENT, so it holds under `swift test` as well as xcodebuild.
    func testRepeatStateLabelsAreDistinctInEveryLocale() throws {
        let stateKeys = ["Repeat off", "Repeat all", "Repeat one"]
        for lang in ["en", "ja", "zh-Hant"] {
            let values = stateKeys.map { key -> String in
                Self.expected[key]?[lang] ?? ""
            }
            XCTAssertFalse(values.contains(""), "missing a repeat-state label for \(lang)")
            XCTAssertEqual(Set(values).count, stateKeys.count,
                           "the three repeat-state labels collapse in \(lang): \(values)")
        }

        // ...and the VISIBLE pill text is deliberately the same in all three
        // states, so no locale's row width can depend on the repeat mode. What
        // tells ALL from ONE on screen is the badge
        // (`CadenceTransport.repeatBadge(for:)`), measured in
        // `CadenceTransportRepeatAppearanceTests`; the catalog's job here is only
        // to keep that one word short enough for the 176 pt zone, which
        // `CadenceTransportRepeatWidthTests` measures per locale.
        XCTAssertNil(Self.expected["Repeat 1"],
                     "the per-state pill string is gone: the ONE state is a badge, not a label")
    }

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
