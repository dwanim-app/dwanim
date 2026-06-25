import Foundation
import XCTest
@testable import PlayerCore

// MARK: - PersistedBookmarksTests

/// Tests the pure `PersistedBookmarks` value: its slot/playlist mutators and its
/// `Codable` round-trip (the app will encode it into its container/`UserDefaults`
/// and decode it at launch, so a lossy round-trip would silently lose the user's
/// remembered files).
final class PersistedBookmarksTests: XCTestCase {

    private func bytes(_ s: String) -> Data { Data(s.utf8) }

    // MARK: - Defaults

    func testDefaultIsEmpty() {
        let store = PersistedBookmarks()
        XCTAssertNil(store.bookmark(for: .lastAudio))
        XCTAssertNil(store.bookmark(for: .lastSkin))
        XCTAssertTrue(store.playlist.isEmpty)
    }

    // MARK: - Single-slot mutators

    func testSetAndReadRole() {
        var store = PersistedBookmarks()
        store.setBookmark(bytes("audio"), for: .lastAudio)
        XCTAssertEqual(store.bookmark(for: .lastAudio), bytes("audio"))
        XCTAssertNil(store.bookmark(for: .lastSkin), "other slot untouched")
    }

    func testSetReplacesExistingRole() {
        var store = PersistedBookmarks()
        store.setBookmark(bytes("old"), for: .lastSkin)
        store.setBookmark(bytes("new"), for: .lastSkin)
        XCTAssertEqual(store.bookmark(for: .lastSkin), bytes("new"))
    }

    func testClearRole() {
        var store = PersistedBookmarks()
        store.setBookmark(bytes("audio"), for: .lastAudio)
        store.clearBookmark(for: .lastAudio)
        XCTAssertNil(store.bookmark(for: .lastAudio))
    }

    // MARK: - Playlist mutators (order preserving)

    func testSetPlaylistPreservesOrder() {
        var store = PersistedBookmarks()
        let ordered = [bytes("a"), bytes("b"), bytes("c")]
        store.setPlaylist(ordered)
        XCTAssertEqual(store.playlist, ordered, "order is meaningful and preserved")
    }

    func testClearPlaylistLeavesRoles() {
        var store = PersistedBookmarks()
        store.setBookmark(bytes("skin"), for: .lastSkin)
        store.setPlaylist([bytes("a"), bytes("b")])
        store.clearPlaylist()
        XCTAssertTrue(store.playlist.isEmpty)
        XCTAssertEqual(store.bookmark(for: .lastSkin), bytes("skin"),
                       "clearing the playlist must not touch single-slot roles")
    }

    // MARK: - Codable round-trip

    func testCodableRoundTripEquality() throws {
        var store = PersistedBookmarks()
        store.setBookmark(bytes("audio-bytes"), for: .lastAudio)
        store.setBookmark(bytes("skin-bytes"), for: .lastSkin)
        store.setPlaylist([bytes("p0"), bytes("p1"), bytes("p2")])

        let encoded = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(PersistedBookmarks.self, from: encoded)

        XCTAssertEqual(decoded, store,
                       "encode -> decode must reproduce an equal store, including playlist order")
        XCTAssertEqual(decoded.playlist, store.playlist, "playlist order survives the round-trip")
    }

    func testEmptyCodableRoundTrip() throws {
        let store = PersistedBookmarks()
        let encoded = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(PersistedBookmarks.self, from: encoded)
        XCTAssertEqual(decoded, store)
    }
}
