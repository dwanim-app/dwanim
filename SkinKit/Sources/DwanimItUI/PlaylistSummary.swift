import Foundation

// MARK: - PlaylistSummary

/// The pure copy seam for the playlist footer's "N songs, M minutes" summary. The
/// singular/plural grammar that fixes "1 songs, 1 minutes" (E2) now lives in the
/// String Catalog's PLURAL VARIATIONS rather than in hand-rolled Swift, so the same
/// seam reads naturally in en (one/other), ja and zh-Hant (other-only). `CadencePlaylist`
/// calls `text(songCount:totalSeconds:)` and renders the result verbatim; the counting
/// math (the reduce over durations) stays at the call site, and only the count→copy
/// formatting lives here.
///
/// ## Where the grammar resolves
/// `text` composes two `String(localized:bundle:.module)` lookups — the pluralized
/// song count and the pluralized minute count — joined by a neutral ", " separator.
/// The plural rules are compiled by `xcstringstool` under **xcodebuild** (production),
/// where "1 song, 1 minute" resolves correctly. The open-source SwiftPM build
/// (`swift test`) copies the catalog verbatim WITHOUT compiling it, so that path falls
/// back to each key's source format ("%lld songs" / "%lld minutes") and cannot apply
/// the `one` form — exactly why `PlaylistSummaryTests` asserts the plural (`other`)
/// cases at runtime and the singular grammar via catalog CONTENT instead. The join is
/// a plain separator rather than its own catalog entry: a "%@, %@" key has no word
/// character for xcstringstool to derive a Swift symbol from, and ", " reads cleanly in
/// en/ja/zh-Hant. Minutes are `round(seconds / 60)` with NO hour rollover (the handoff
/// footer is minutes-only), clamped ≥ 0.
enum PlaylistSummary {

    /// The footer minute count: `round(totalSeconds / 60)`, clamped to `≥ 0` (a stray
    /// negative duration never yields "-1 minutes"), with NO hour rollover — a two-hour
    /// library reads "120 minutes", not "2 hours". Pure + exact: the number the plural
    /// catalog then pluralizes.
    static func minutes(totalSeconds: Double) -> Int {
        Int((max(0, totalSeconds) / 60).rounded())
    }

    /// The footer summary line for `songCount` tracks totalling `totalSeconds` seconds,
    /// e.g. `text(songCount: 1, totalSeconds: 60)` → `"1 song, 1 minute"` in a compiled
    /// (production) build. The plural grammar is the catalog's job (see the type doc);
    /// this only wires the two counts and the locale-aware join.
    static func text(songCount: Int, totalSeconds: Double) -> String {
        let songs = String(localized: "\(songCount) songs", bundle: .module,
                           comment: "Playlist footer: number of songs (plural)")
        let mins = String(localized: "\(minutes(totalSeconds: totalSeconds)) minutes", bundle: .module,
                         comment: "Playlist footer: number of minutes (plural)")
        return "\(songs), \(mins)"
    }
}
