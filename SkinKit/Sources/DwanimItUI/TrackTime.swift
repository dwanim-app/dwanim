import Foundation

// MARK: - TrackTime

/// The playlist **Time column** formatter — the single pure seam each row's
/// duration is routed through in `CadencePlaylist`.
///
/// Deliberately distinct from `CadenceTime` (the seek labels): the seek clock
/// reads "0:00" when nothing is loaded, but a playlist row whose length is not
/// yet known must read an em dash "—", so a still-resolving or unreadable file is
/// visibly different from a genuine zero-length one. The stored `Track.duration`
/// is `nil` until an async metadata read fills it in, hence the optional input.
enum TrackTime {

    /// Format `seconds` for the playlist Time column:
    /// - `nil`, non-finite, or `<= 0` → `"—"` (length unknown / not yet loaded);
    /// - `< 3600` → `"m:ss"` (e.g. `3:07`);
    /// - `>= 3600` → `"h:mm:ss"` (e.g. `1:02:05`).
    ///
    /// A fractional value is truncated toward zero (`187.9` → `3:07`), matching a
    /// whole-second display.
    static func format(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        let ss = secs < 10 ? "0\(secs)" : "\(secs)"
        if hours > 0 {
            let mm = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(mm):\(ss)"
        }
        return "\(minutes):\(ss)"
    }
}
