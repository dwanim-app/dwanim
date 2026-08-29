import Foundation
import XCTest
@testable import PlayerCore

/// Tests for the pure `DropAppendPlanner` — the host layer classifies + expands a
/// drop (reads `.m3u` files, enumerates dropped folders' audio) and hands the
/// three ordered source lists here; the planner concatenates them into the single
/// ordered list to append. Pure (no I/O), so the drop's combine-order is unit
/// testable without touching the disk (mirrors `M3UPlaylist`'s pure-seam idiom).
final class DropAppendPlannerTests: XCTestCase {

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    /// A MIXED drop (a dropped folder's audio + loose dropped audio) yields BOTH
    /// buckets in the append list — folder audio first, then the loose files —
    /// so a dropped directory contributes its songs alongside dropped files.
    func testMixedFolderAndLooseAudioAreBothIncludedInOrder() {
        let combined = DropAppendPlanner.appendOrder(
            playlistTracks: [],
            folderAudio: [url("/lib/folder/one.mp3"), url("/lib/folder/two.mp3")],
            looseAudio: [url("/lib/loose.flac")]
        )
        XCTAssertEqual(combined, [
            url("/lib/folder/one.mp3"),
            url("/lib/folder/two.mp3"),
            url("/lib/loose.flac")
        ])
    }

    /// Full three-way order: expanded playlist tracks, then folder audio, then
    /// loose audio.
    func testAllThreeSourcesConcatenateInCanonicalOrder() {
        let combined = DropAppendPlanner.appendOrder(
            playlistTracks: [url("/p/a.mp3"), url("/p/b.mp3")],
            folderAudio: [url("/f/c.mp3")],
            looseAudio: [url("/d.mp3")]
        )
        XCTAssertEqual(combined, [
            url("/p/a.mp3"), url("/p/b.mp3"), url("/f/c.mp3"), url("/d.mp3")
        ])
    }

    /// A folder-only drop (no playlists, no loose files) still yields the folder's
    /// audio — the empty-vs-non-empty queue makes no difference at this seam.
    func testFolderOnlyDropYieldsFolderAudio() {
        let combined = DropAppendPlanner.appendOrder(
            playlistTracks: [],
            folderAudio: [url("/f/song.m4a")],
            looseAudio: []
        )
        XCTAssertEqual(combined, [url("/f/song.m4a")])
    }

    /// All buckets empty → an empty plan (the caller treats this as a no-op).
    func testEmptySourcesYieldEmptyPlan() {
        let combined = DropAppendPlanner.appendOrder(
            playlistTracks: [], folderAudio: [], looseAudio: []
        )
        XCTAssertTrue(combined.isEmpty)
    }
}
