import AppKit
import SwiftUI
import XCTest
import PlayerCore
@testable import DwanimItUI

// MARK: - CadenceTransportRepeatWidthTests
//
// THE LAYOUT GUARD for the transport's left zone.
//
// ## The defect this was written for
// `CadenceTransport` centres its playback cluster by pinning the left and right
// zones to the same fixed width (176 pt — pinned in the test target as
// `TransportLayoutSpec.zoneWidth`, and checked against production's constant by
// `CadenceTransportZoneLayoutTests`, so the budget below cannot be widened by
// editing the code under test). The Repeat pill used to change its VISIBLE
// STRING with its state — "Repeat" in off/all, "Repeat 1" in one — so the row's
// intrinsic width depended on a mode the listener toggles. In Japanese that pushed the row from 171 pt to 180 pt,
// 4 pt past the zone: `minimumScaleFactor(0.8)` absorbed the overflow instead of
// clipping, so entering repeat-one silently SHRANK every label in the row and
// shoved the EQ pill towards the centre cluster. Nothing in the suite noticed,
// because nothing measured.
//
// ## What is measured, and why it is the real view
// `NSHostingView(rootView:).fittingSize` on the production `TransportToggleRow`
// built out of production `TransportToggle` pills — not a replica, and not a
// hand-rolled `NSAttributedString.size()` estimate that could agree with itself
// while disagreeing with SwiftUI.
//
// The one substitution is the LABEL TEXT. Under `swift test` SwiftPM copies
// `Localizable.xcstrings` into `Bundle.module` without compiling it (see
// `LocalizationBundleTests`), so a hosted `Text("Repeat", bundle: .module)` can
// only ever draw the English source key — there is no way to render a Japanese
// pill in this build system. So the test asks PRODUCTION which catalog key each
// state shows (`CadenceTransport.repeatLabelKey(for:)`), resolves that key
// against the catalog for each shipping locale, and feeds the result in as
// `Text(verbatim:)`. Nothing about the mapping is duplicated here: lengthen a
// catalog string, or make the key state-dependent again, and this test moves.
//
// `testTheEnglishRowMeasuresTheSameAsTheOneTheAppBuilds` is the tie-back that
// keeps the substitution honest — the row assembled here and the row
// `CadenceTransport` assembles from a live `PlayerCore` must measure identically
// in English, where the two can be compared.
@MainActor
final class CadenceTransportRepeatWidthTests: XCTestCase {

    /// The width budget: `TransportLayoutSpec.zoneWidth`, which is PINNED to the
    /// design's 176 pt in the test target rather than read from production.
    ///
    /// Measuring against `TransportToggleRow.zoneWidth` would have made this
    /// guard self-referential — widening the production constant would move the
    /// budget with it, so the forbidden shortcut ("make the zone bigger instead
    /// of the control smaller") would leave the suite green. The two are
    /// compared in exactly one place, `CadenceTransportZoneLayoutTests`.
    private static let budget = TransportLayoutSpec.zoneWidth

    /// The shipping locales, DERIVED from the catalog rather than hand-listed.
    ///
    /// A literal list here was a hole: Japanese is the only locale that ever came
    /// near the budget (it is the one that overflowed), so deleting `"ja"` from an
    /// array would have kept five of the six assertions and thrown away all of the
    /// value — silently, and with nothing else in the suite covering ja layout.
    /// Reading the languages out of `Localizable.xcstrings` means the DEFAULT is
    /// whatever the app actually ships, and a fourth locale is measured the day it
    /// is added. Deriving it does NOT by itself make dropping one impossible —
    /// `catalogLanguages.sorted().filter { $0 != "ja" }` would have been a green
    /// one-liner. What forbids that is
    /// `testTheGuardMeasuresEveryLocaleTheCatalogShips`, which compares the set
    /// this loop actually MEASURED against the catalog's.
    private static let catalogLanguages: Set<String> = {
        Set(
            catalog.values
                .compactMap { ($0 as? [String: Any])?["localizations"] as? [String: Any] }
                .flatMap(\.keys)
        )
    }()

    /// The same set in a stable order, for the report table.
    private static let locales: [String] = catalogLanguages.sorted()

    private static let modes: [RepeatMode] = [.off, .all, .one]

    // MARK: - Catalog access

    /// The catalog's `strings` map, parsed once from `Bundle.module`.
    private static let catalog: [String: Any] = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any]
        else { return [:] }
        return strings
    }()

    /// The translated value for `key` in `language`, as it will appear on screen
    /// once `xcstringstool` has compiled the catalog.
    private func localized(_ key: String, _ language: String) throws -> String {
        let entry = try XCTUnwrap(Self.catalog[key] as? [String: Any],
                                  "Localizable.xcstrings has no key \(key)")
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any],
                                          "\(key) has no localizations")
        let unit = try XCTUnwrap((localizations[language] as? [String: Any])?["stringUnit"]
                                    as? [String: Any],
                                 "\(key) has no \(language) translation")
        return try XCTUnwrap(unit["value"] as? String, "\(key)/\(language) has no value")
    }

    // MARK: - Building the REAL row at a given locale and repeat state

    /// The production left zone, with every label already resolved for
    /// `language` and the Repeat pill in `mode`.
    private func row(language: String, mode: RepeatMode) throws -> TransportToggleRow {
        TransportToggleRow(
            shuffle: TransportToggle(
                label: Text(verbatim: try localized("Shuffle", language)),
                isActive: false,
                bold: false,
                theme: .graphite
            ) {},
            repeatToggle: TransportToggle(
                label: Text(verbatim: try localized(
                    CadenceTransport.repeatLabelKey(for: mode), language
                )),
                accessibilityText: nil,
                badge: CadenceTransport.repeatBadge(for: mode),
                isActive: mode != .off,
                bold: false,
                theme: .graphite
            ) {},
            equalizer: TransportToggle(
                // Verbatim in production too — "EQ" is never translated.
                label: Text(verbatim: "EQ"),
                isActive: false,
                bold: true,
                theme: .graphite
            ) {}
        )
    }

    /// The row's intrinsic width in POINTS, measured by hosting it.
    private func width<V: View>(of view: V) -> CGFloat {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.width
    }

    /// Every (locale × state) width, in the order the report table wants them.
    private func widthTable() throws -> [(language: String, mode: RepeatMode, width: CGFloat)] {
        // A catalog that failed to parse would leave `locales` empty and every
        // loop below vacuously green. Fail loudly instead.
        XCTAssertFalse(Self.locales.isEmpty,
                       "no locales derived from Localizable.xcstrings — the guard would measure nothing")
        var rows: [(String, RepeatMode, CGFloat)] = []
        for language in Self.locales {
            for mode in Self.modes {
                rows.append((language, mode, width(of: try row(language: language, mode: mode))))
            }
        }
        return rows
    }

    // MARK: - The guard

    /// REQUIREMENT 1 — nothing overflows the zone.
    ///
    /// Every (locale × state) combination must fit inside the PINNED 176 pt
    /// budget. Overflow here does not clip (the pills carry
    /// `minimumScaleFactor`), which is exactly why it needs measuring: the
    /// symptom is every label in the row quietly shrinking, not a visible
    /// truncation.
    func testNoLocaleInAnyRepeatStateOverflowsTheToggleZone() throws {
        var report: [String] = []
        for entry in try widthTable() {
            report.append(String(format: "%-8@ %-4@ %6.2f pt",
                                 entry.language as NSString,
                                 String(describing: entry.mode) as NSString,
                                 entry.width))
            XCTAssertLessThanOrEqual(
                entry.width, Self.budget,
                "\(entry.language) / \(entry.mode): the toggle row measures "
                + String(format: "%.2f", entry.width)
                + " pt, past the \(Self.budget) pt zone"
            )
        }
        print("=== toggle-row width, locale × repeat state ===")
        report.forEach { print($0) }
    }

    /// The guard's COVERAGE, asserted rather than assumed.
    ///
    /// Two ways this suite could quietly stop guarding anything: the loop could
    /// lose the one locale that matters (Japanese has ~5 pt of headroom; English
    /// and 繁中 have 29 and 16, so they would never fail first), or the app could
    /// gain a locale nobody measured.
    ///
    /// Deriving `locales` from the catalog is NOT on its own enough to close the
    /// first — a one-line `.filter { $0 != "ja" }` on line 76 used to leave every
    /// assertion in this file green while ja went unmeasured. So the chain is
    /// asserted link by link, ending at the widths that were actually TAKEN:
    ///
    ///   catalog ships  ==  ["en", "ja", "zh-Hant"]          (the shipping set)
    ///   Set(locales)   ==  catalogLanguages                 (nothing filtered out)
    ///   measured langs ==  catalogLanguages, × all 3 modes  (nothing skipped)
    ///
    /// The last one is the one that cannot be routed around: it re-runs the real
    /// measurement loop and inspects what came back, so dropping a locale
    /// anywhere — from `locales`, or from inside `widthTable()` — fails here.
    func testTheGuardMeasuresEveryLocaleTheCatalogShips() throws {
        XCTAssertEqual(
            Self.catalogLanguages, ["en", "ja", "zh-Hant"],
            "dwanim it ships en / zh-Hant / ja. If that changed, the width guard must have "
            + "measured the new locale before this line was updated."
        )

        XCTAssertEqual(
            Set(Self.locales), Self.catalogLanguages,
            "the guard must MEASURE every locale the catalog ships — every loop in this "
            + "file iterates `locales`, so anything missing from it is unguarded"
        )

        // ...and the widths really were taken, for every locale in every state.
        // Asserted on the table the guard itself produces, so this holds however
        // the loop is written.
        let table = try widthTable()
        XCTAssertEqual(Set(table.map(\.language)), Self.catalogLanguages,
                       "every shipping locale must appear in the measured width table")
        for language in Self.locales {
            XCTAssertEqual(
                Set(table.filter { $0.language == language }.map(\.mode)), Set(Self.modes),
                "\(language) must be measured in all three repeat states"
            )
        }

        // Every string the row renders must exist in every one of them, or the
        // measurement for that locale would silently fall back to English.
        let keys = ["Shuffle"] + Self.modes.map { CadenceTransport.repeatLabelKey(for: $0) }
        for key in Set(keys) {
            for language in Self.locales {
                XCTAssertFalse(try localized(key, language).isEmpty,
                               "\(key) has an empty \(language) translation")
            }
        }
    }

    /// REQUIREMENT 2 — cycling the Repeat pill causes NO horizontal re-flow.
    ///
    /// Within a locale the row must measure the SAME in off, all and one, so
    /// `off → all → one → off` never moves the Shuffle / Repeat / EQ pills. This
    /// is the assertion that fails if someone re-lengthens the repeat-one string
    /// instead of using the badge.
    func testTheRowWidthDoesNotChangeAcrossTheRepeatCycle() throws {
        XCTAssertFalse(Self.locales.isEmpty,
                       "no locales derived from Localizable.xcstrings — this would assert nothing")
        for language in Self.locales {
            let widths = try Self.modes.map { width(of: try row(language: language, mode: $0)) }
            for (mode, measured) in zip(Self.modes, widths) {
                XCTAssertEqual(
                    measured, widths[0], accuracy: 0.01,
                    "\(language): the row is \(measured) pt in \(mode) but \(widths[0]) pt in off "
                    + "— switching repeat modes re-flows the row"
                )
            }
        }
    }

    /// The same property stated at the level that actually broke: the Repeat
    /// pill shows ONE string in every state, and the state is carried by the
    /// badge instead. Asserted on production's own mapping, so it holds for
    /// every locale at once.
    func testTheRepeatPillShowsTheSameStringInEveryStateAndBadgesTheOneState() {
        let keys = Self.modes.map { CadenceTransport.repeatLabelKey(for: $0) }
        XCTAssertEqual(Set(keys).count, 1,
                       "the Repeat pill's visible string must not depend on its state: \(keys)")

        XCTAssertFalse(CadenceTransport.repeatBadge(for: .off).isVisible)
        XCTAssertFalse(CadenceTransport.repeatBadge(for: .all).isVisible)
        XCTAssertTrue(CadenceTransport.repeatBadge(for: .one).isVisible,
                      "repeat-one is the state the badge marks")
        XCTAssertEqual(Set(Self.modes.map { CadenceTransport.repeatBadge(for: $0).glyph }).count, 1,
                       "the badge slot is declared identically in every state, so only "
                       + "its opacity changes and the pill never re-lays-out")
    }

    /// The substitution above is only trustworthy if a row built HERE measures
    /// like a row built by `CadenceTransport` from a live model. English is
    /// where the two are comparable (`swift test` renders source keys), so the
    /// tie-back is asserted there, in all three states.
    func testTheEnglishRowMeasuresTheSameAsTheOneTheAppBuilds() throws {
        let core = PlayerCore(engine: TransportRecordingEngine())
        for mode in Self.modes {
            core.repeatMode = mode
            let produced = width(of: CadenceTransport.toggleRow(core: core, theme: .graphite))
            let measured = width(of: try row(language: "en", mode: mode))
            XCTAssertEqual(produced, measured, accuracy: 0.01,
                           "\(mode): the measured row must be the row the app builds")
        }
    }

    /// The badge is an OVERLAY, and an overlay cannot change what it overlays.
    /// Proven directly rather than assumed: the same pill measures identically
    /// with the badge shown, hidden, and absent altogether.
    func testTheBadgeContributesNothingToThePillsWidth() {
        func pill(_ badge: TransportToggleBadge?) -> TransportToggle {
            TransportToggle(
                label: Text(verbatim: "リピート"),
                badge: badge,
                isActive: true,
                bold: false,
                theme: .graphite
            ) {}
        }
        let none = width(of: pill(nil))
        let hidden = width(of: pill(TransportToggleBadge(glyph: "1", isVisible: false)))
        let shown = width(of: pill(TransportToggleBadge(glyph: "1", isVisible: true)))
        XCTAssertEqual(hidden, none, accuracy: 0.01, "a hidden badge adds no width")
        XCTAssertEqual(shown, none, accuracy: 0.01, "a VISIBLE badge adds no width either")
    }
}
