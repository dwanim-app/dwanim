import Foundation
import XCTest
@testable import PlayerCore

// MARK: - BookmarkResolverTests

/// Tests the pure stale/refresh/drop policy in `BookmarkResolver` against a
/// `FakeSecurityScopedAccess`. Each test is written so it would FAIL if the
/// policy were wrong: a fresh resolve must NOT re-mint (asserted via the fake's
/// call log), a stale resolve MUST re-mint AND change the stored bytes, a
/// failing resolve MUST drop only that entry, and the playlist must preserve
/// order while dropping/ refreshing per entry.
final class BookmarkResolverTests: XCTestCase {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/music/\(name)")
    }

    // MARK: - Single slot: fresh

    func testResolveFreshReturnsURLAndLeavesStoreUnchangedWithNoReMint() {
        let access = FakeSecurityScopedAccess()
        let audio = url("song.mp3")
        let data = access.registerCanned(url: audio, isStale: false)
        var store = PersistedBookmarks()
        store.setBookmark(data, for: .lastAudio)

        let resolver = BookmarkResolver(access: access)
        let result = resolver.resolve(role: .lastAudio, in: store)

        XCTAssertEqual(result.url, audio, "a fresh bookmark resolves to its URL")
        XCTAssertEqual(result.store, store,
                       "a fresh (non-stale) resolve must leave the store byte-for-byte unchanged")
        XCTAssertEqual(access.bookmarkDataCallCount, 0,
                       "a fresh resolve must NOT re-mint a bookmark")
    }

    // MARK: - Single slot: stale -> refresh

    func testResolveStaleReMintsAndStoresNewBytes() {
        let access = FakeSecurityScopedAccess()
        let audio = url("song.mp3")
        let staleData = access.registerCanned(url: audio, isStale: true)
        var store = PersistedBookmarks()
        store.setBookmark(staleData, for: .lastAudio)

        let resolver = BookmarkResolver(access: access)
        let result = resolver.resolve(role: .lastAudio, in: store)

        XCTAssertEqual(result.url, audio, "a stale bookmark still resolves to its URL")
        XCTAssertEqual(access.bookmarkDataCalls, [audio],
                       "a stale resolve MUST re-mint a fresh bookmark for the recovered URL")
        let newBytes = result.store.bookmark(for: .lastAudio)
        XCTAssertNotNil(newBytes)
        XCTAssertNotEqual(newBytes, staleData,
                          "the store must now hold the NEW (refreshed) bytes, not the stale ones")
        XCTAssertNotEqual(result.store, store, "the store changed and should be persisted")
    }

    // MARK: - Single slot: missing / throwing -> drop

    func testResolveThrowingDropsOnlyThatRole() {
        let access = FakeSecurityScopedAccess()
        let audio = url("gone.mp3")
        let skin = url("keep.skin")
        let audioData = access.registerCanned(url: audio, resolveThrows: true)
        let skinData = access.registerCanned(url: skin, isStale: false)
        var store = PersistedBookmarks()
        store.setBookmark(audioData, for: .lastAudio)
        store.setBookmark(skinData, for: .lastSkin)

        let resolver = BookmarkResolver(access: access)
        let result = resolver.resolve(role: .lastAudio, in: store)

        XCTAssertNil(result.url, "a file that no longer resolves yields no URL")
        XCTAssertNil(result.store.bookmark(for: .lastAudio),
                     "the failing role must be DROPPED from the returned store")
        XCTAssertEqual(result.store.bookmark(for: .lastSkin), skinData,
                       "other roles must remain intact")
    }

    func testResolveEmptySlotReturnsNilUnchanged() {
        let access = FakeSecurityScopedAccess()
        let store = PersistedBookmarks()
        let resolver = BookmarkResolver(access: access)
        let result = resolver.resolve(role: .lastSkin, in: store)
        XCTAssertNil(result.url)
        XCTAssertEqual(result.store, store)
        XCTAssertEqual(access.bookmarkDataCallCount, 0)
    }

    func testResolveStaleButReMintThrowsDropsRoleButReturnsURL() {
        let access = FakeSecurityScopedAccess()
        let audio = url("flaky.mp3")
        // Resolves (stale) but re-minting throws -> drop the (still-stale) bytes.
        let data = access.registerCanned(url: audio, isStale: true, mintThrows: true)
        var store = PersistedBookmarks()
        store.setBookmark(data, for: .lastAudio)

        let resolver = BookmarkResolver(access: access)
        let result = resolver.resolve(role: .lastAudio, in: store)

        XCTAssertEqual(result.url, audio, "it did resolve, so the URL is usable this session")
        XCTAssertNil(result.store.bookmark(for: .lastAudio),
                     "a stale bookmark whose re-mint fails must be dropped, not kept stale")
    }

    // MARK: - Playlist: order + per-entry policy

    func testResolvePlaylistPreservesOrder() {
        let access = FakeSecurityScopedAccess()
        let a = access.registerCanned(url: url("a.mp3"))
        let b = access.registerCanned(url: url("b.mp3"))
        let c = access.registerCanned(url: url("c.mp3"))
        var store = PersistedBookmarks()
        store.setPlaylist([a, b, c])

        let resolver = BookmarkResolver(access: access)
        let result = resolver.resolvePlaylist(in: store)

        XCTAssertEqual(result.urls, [url("a.mp3"), url("b.mp3"), url("c.mp3")],
                       "order must be preserved across resolve")
        XCTAssertEqual(result.store, store, "all-fresh playlist leaves the store unchanged")
        XCTAssertEqual(access.bookmarkDataCallCount, 0, "no stale entries -> no re-mint")
    }

    func testResolvePlaylistDropsFailingMiddleEntryKeepingOrder() {
        let access = FakeSecurityScopedAccess()
        let a = access.registerCanned(url: url("a.mp3"))
        let b = access.registerCanned(url: url("b.mp3"), resolveThrows: true) // middle drops
        let c = access.registerCanned(url: url("c.mp3"))
        var store = PersistedBookmarks()
        store.setPlaylist([a, b, c])

        let resolver = BookmarkResolver(access: access)
        let result = resolver.resolvePlaylist(in: store)

        XCTAssertEqual(result.urls, [url("a.mp3"), url("c.mp3")],
                       "a failing middle entry is dropped without disturbing the others' order")
        XCTAssertEqual(result.store.playlist, [a, c],
                       "the persisted playlist drops only the failing entry's bytes")
    }

    func testResolvePlaylistRefreshesStaleEntryInPlace() {
        let access = FakeSecurityScopedAccess()
        let a = access.registerCanned(url: url("a.mp3"))
        let bStale = access.registerCanned(url: url("b.mp3"), isStale: true) // refreshes
        let c = access.registerCanned(url: url("c.mp3"))
        var store = PersistedBookmarks()
        store.setPlaylist([a, bStale, c])

        let resolver = BookmarkResolver(access: access)
        let result = resolver.resolvePlaylist(in: store)

        XCTAssertEqual(result.urls, [url("a.mp3"), url("b.mp3"), url("c.mp3")],
                       "a stale entry still contributes its URL, in order")
        XCTAssertEqual(access.bookmarkDataCalls, [url("b.mp3")],
                       "only the stale entry triggers a re-mint")
        XCTAssertEqual(result.store.playlist.count, 3)
        XCTAssertEqual(result.store.playlist[0], a, "fresh entries keep their bytes")
        XCTAssertNotEqual(result.store.playlist[1], bStale,
                          "the stale entry's bytes are refreshed in place")
        XCTAssertEqual(result.store.playlist[2], c)
    }

    // MARK: - Record a freshly opened URL

    func testRecordAddsRoleWithFakeBytes() throws {
        let access = FakeSecurityScopedAccess()
        let audio = url("fresh.mp3")
        let store = PersistedBookmarks()

        let resolver = BookmarkResolver(access: access)
        let updated = try resolver.record(url: audio, as: .lastAudio, in: store)

        XCTAssertEqual(access.bookmarkDataCalls, [audio], "record mints a bookmark for the URL")
        XCTAssertNotNil(updated.bookmark(for: .lastAudio),
                        "the store gains the role's freshly minted bytes")
    }

    func testRecordRethrowsAndLeavesStoreUnchangedOnMintFailure() {
        let access = FakeSecurityScopedAccess()
        let audio = url("denied.mp3")
        access.registerCanned(url: audio, mintThrows: true)
        let store = PersistedBookmarks()

        let resolver = BookmarkResolver(access: access)
        XCTAssertThrowsError(try resolver.record(url: audio, as: .lastAudio, in: store)) { _ in }
    }

    // MARK: - Access scope passthrough

    func testWithAccessRunsBodyAndReturnsValue() {
        let access = FakeSecurityScopedAccess()
        let audio = url("scoped.mp3")
        let resolver = BookmarkResolver(access: access)

        var ran = false
        let value = resolver.withAccess(to: audio) { () -> Int in
            ran = true
            return 42
        }

        XCTAssertTrue(ran, "withAccess must run the body")
        XCTAssertEqual(value, 42, "withAccess must return the body's value")
        XCTAssertEqual(access.withAccessURLs, [audio], "the access scope wraps the right URL")
    }
}
