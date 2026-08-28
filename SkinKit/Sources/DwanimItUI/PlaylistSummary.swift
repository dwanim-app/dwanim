import Foundation

// MARK: - PlaylistSummary

/// The pure copy seam for the playlist footer's "N songs, M minutes" summary — the
/// single place the song/minute grammar lives, so "1 songs, 1 minutes" (E2) can never
/// come back. `CadencePlaylist` calls `text(songCount:totalSeconds:)` and renders the
/// result verbatim; all counting math (the reduce over durations) stays at the call
/// site, and only the count→copy formatting lives here where it is unit-testable.
///
/// Grammar: English count nouns are singular only for exactly `1` ("1 song",
/// "1 minute"); `0` and everything ≥ 2 are plural. Minutes are `round(seconds / 60)`
/// with NO hour rollover — the handoff footer format is literally "N songs, M minutes",
/// so a long library reads "120 minutes", never "2 hours". A negative total (a stray
/// bad duration) clamps to `0` rather than producing "-1 minutes".
enum PlaylistSummary {

    /// The footer summary line for `songCount` tracks totalling `totalSeconds` seconds,
    /// e.g. `text(songCount: 1, totalSeconds: 60)` → `"1 song, 1 minute"`.
    static func text(songCount: Int, totalSeconds: Double) -> String {
        let minutes = Int((max(0, totalSeconds) / 60).rounded())
        return "\(pluralized(songCount, "song")), \(pluralized(minutes, "minute"))"
    }

    /// `"<n> <noun>"` with an `s` appended unless `n == 1` (English: only exactly one
    /// is singular; zero and plural counts both take the `s`).
    private static func pluralized(_ n: Int, _ singular: String) -> String {
        "\(n) \(singular)\(n == 1 ? "" : "s")"
    }
}
