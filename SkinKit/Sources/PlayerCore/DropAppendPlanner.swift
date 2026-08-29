import Foundation

// MARK: - DropAppendPlanner
//
// The PURE, side-effect-free ordering seam for a drag-and-drop ADD. The host
// layer (`AudioSession`) classifies the dropped URLs (`DropRouter`) and does the
// I/O the classification implies — reading each `.m3u` into its listed tracks and
// enumerating each dropped FOLDER's audio files — then hands the three ordered
// source lists here. The planner simply concatenates them into the single ordered
// list to append, so the drop's combine-order lives in one readable, unit-testable
// place (mirroring `M3UPlaylist`'s "host does the I/O, the pure type does the
// logic" split).
//
// De-duplication is NOT done here: it is centralised on `PlayerCore.append`, so a
// track already in the queue is skipped no matter which add path produced it.
public enum DropAppendPlanner {

    /// Combine the three expanded drop sources into the ordered list to append:
    /// `.m3u`-expanded playlist tracks first, then each dropped folder's audio,
    /// then the loose dropped audio files. Order is preserved within and across
    /// the buckets, so the result is deterministic. An all-empty input yields an
    /// empty plan (the caller treats that as a no-op).
    public static func appendOrder(
        playlistTracks: [URL],
        folderAudio: [URL],
        looseAudio: [URL]
    ) -> [URL] {
        playlistTracks + folderAudio + looseAudio
    }
}
