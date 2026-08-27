import Foundation

// MARK: - TrackTitle

/// The single, pure `"Artist - Title"` split shared by the default face's
/// now-playing line (`DefaultPlayerView`) and the playlist rows (`CadencePlaylist`).
/// A stored `Track` carries no artist field, so the artist is DERIVED, display-only,
/// from the filename convention `Artist - Title`.
///
/// The split is on the FIRST `" - "` separator: when BOTH halves are non-empty the
/// left half is the artist and the right half the title; otherwise the whole string
/// is the title and there is no artist (a leading / trailing / absent dash never
/// yields an empty half, and a string with several `" - "` runs splits only on the
/// first). Callers keep their own OUTER fallbacks — the now-playing line shows
/// "dwanim it" when nothing is loaded, a playlist row shows "Track N" when its stored
/// title is blank — those live at the call site; only the split itself lives here.
enum TrackTitle {

    /// Split `s` into `(title, artist?)` on the first `" - "` separator. Both halves
    /// non-empty → `(title: right, artist: left)`; otherwise `(title: s, artist: nil)`.
    static func split(_ s: String) -> (title: String, artist: String?) {
        guard let separator = s.range(of: " - ") else { return (s, nil) }
        let artist = String(s[s.startIndex..<separator.lowerBound])
        let title = String(s[separator.upperBound...])
        guard !artist.isEmpty, !title.isEmpty else { return (s, nil) }
        return (title, artist)
    }
}
