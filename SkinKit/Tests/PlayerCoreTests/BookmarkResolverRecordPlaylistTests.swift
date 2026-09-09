import Foundation
import XCTest
@testable import PlayerCore

// MARK: - BookmarkResolverRecordPlaylistTests
//
// F7 — persisting the live queue, as resolver policy rather than app code: every
// user file becomes a security-scoped bookmark (minted inside its access bracket),
// the bundled sample becomes a `BundledTrackMarker` (never a bookmark to a path
// inside the bundle), and the single-slot `.lastAudio` follows the queue's head —
// or is CLEARED when the head is the sample or the queue is empty. The app used to
// do all of this inline in `AudioSession.recordPlaylist`, which no package test
// could reach; the marker-vs-bookmark and the `.lastAudio` rules below are the
// mutants that used to survive.

final class BookmarkResolverRecordPlaylistTests: XCTestCase {

    private var access: FakeSecurityScopedAccess!
    private var resolver: BookmarkResolver!

    private let sample = BundledTrack(
        resourceName: "dwanim it - Sample",
        url: URL(fileURLWithPath: "/Applications/Dwanim It.app/Contents/Resources/dwanim it - Sample.m4a")
    )
    private let mine = URL(fileURLWithPath: "/Users/me/Music/mine.mp3")
    private let yours = URL(fileURLWithPath: "/Users/me/Music/yours.flac")

    override func setUp() {
        access = FakeSecurityScopedAccess()
        resolver = BookmarkResolver(access: access)
    }

    private func markerName(_ data: Data) -> String? { BundledTrackMarker.resourceName(in: data) }

    /// The file the fake minted `data` for (the fake mints FRESH bytes per call,
    /// so what was written is checked by resolving it back, as the next launch does).
    private func fileFor(_ data: Data?) throws -> URL {
        try access.resolveBookmark(XCTUnwrap(data)).url
    }

    // MARK: The sample is a marker, the user's files are bookmarks

    func testUserFilesAreMintedInsideTheirAccessBracketAndPersistedInOrder() throws {
        access.registerCanned(url: mine)
        access.registerCanned(url: yours)

        let out = resolver.recordPlaylist([mine, yours], in: PersistedBookmarks(), bundledTrack: sample)

        XCTAssertEqual(out.playlist.count, 2)
        XCTAssertEqual(try fileFor(out.playlist[0]), mine)
        XCTAssertEqual(try fileFor(out.playlist[1]), yours)
        XCTAssertEqual(Set(access.withAccessURLs), [mine, yours],
                       "each mint runs inside the file's security-scoped bracket")
        XCTAssertEqual(try fileFor(out.bookmark(for: .lastAudio)), mine, "`.lastAudio` follows the head")
    }

    func testTheSampleIsPersistedAsAMarkerAndNeverMinted() throws {
        access.registerCanned(url: mine)
        access.registerCanned(url: sample.url) // even if minting it WOULD work…

        let out = resolver.recordPlaylist([mine, sample.url], in: PersistedBookmarks(), bundledTrack: sample)

        XCTAssertEqual(out.playlist.count, 2)
        XCTAssertEqual(try fileFor(out.playlist[0]), mine)
        XCTAssertEqual(markerName(out.playlist[1]), sample.resourceName, "…the sample row is a MARKER")
        XCTAssertFalse(access.bookmarkDataCalls.contains(sample.url),
                       "a bookmark into the bundle would only ever resolve stale, so it is never minted")
        XCTAssertFalse(access.withAccessURLs.contains(sample.url), "and never bracketed: the bundle needs no grant")
    }

    func testTheSampleKeepsItsSlotBetweenTheUsersFiles() {
        access.registerCanned(url: mine)
        access.registerCanned(url: yours)

        let out = resolver.recordPlaylist([mine, sample.url, yours], in: PersistedBookmarks(), bundledTrack: sample)

        XCTAssertEqual(out.playlist.map { markerName($0) ?? "bookmark" },
                       ["bookmark", sample.resourceName, "bookmark"])
    }

    func testWithoutABundledTrackTheSamePathIsJustAnotherFile() throws {
        // No sample ships in this build: a file at that path is a user's file.
        access.registerCanned(url: sample.url)

        let out = resolver.recordPlaylist([sample.url], in: PersistedBookmarks(), bundledTrack: nil)

        XCTAssertEqual(out.playlist.count, 1)
        XCTAssertNil(markerName(out.playlist[0]), "a bookmark, not a marker")
        XCTAssertEqual(try fileFor(out.playlist[0]), sample.url)
        XCTAssertEqual(try fileFor(out.bookmark(for: .lastAudio)), sample.url)
    }

    // MARK: `.lastAudio` coherence

    func testAHeadThatIsTheSampleClearsLastAudioInsteadOfPointingIntoTheBundle() {
        access.registerCanned(url: mine)
        var previous = PersistedBookmarks()
        previous.setBookmark(Data("stale-last-audio".utf8), for: .lastAudio)

        let out = resolver.recordPlaylist([sample.url, mine], in: previous, bundledTrack: sample)

        XCTAssertEqual(markerName(out.playlist[0]), sample.resourceName)
        XCTAssertNil(out.bookmark(for: .lastAudio),
                     "the sample is restored through its marker; a stale `.lastAudio` must not resurrect a different track")
    }

    func testAnEmptyQueueClearsLastAudioSoAClearedQueueStaysCleared() {
        var previous = PersistedBookmarks(playlist: [Data("old".utf8)])
        previous.setBookmark(Data("old-last".utf8), for: .lastAudio)
        previous.setBookmark(Data("skin".utf8), for: .lastSkin)

        let out = resolver.recordPlaylist([], in: previous, bundledTrack: sample)

        XCTAssertEqual(out.playlist, [])
        XCTAssertNil(out.bookmark(for: .lastAudio))
        XCTAssertEqual(out.bookmark(for: .lastSkin), Data("skin".utf8), "other roles are untouched")
    }

    func testAHeadWhoseMintFailsIsDroppedFromThePlaylistAndLeavesLastAudioAlone() throws {
        access.registerCanned(url: mine, mintThrows: true)
        access.registerCanned(url: yours)
        var previous = PersistedBookmarks()
        previous.setBookmark(Data("old-last".utf8), for: .lastAudio)

        let out = resolver.recordPlaylist([mine, yours], in: previous, bundledTrack: sample)

        XCTAssertEqual(out.playlist.count, 1, "the unmintable file just will not reopen next launch")
        XCTAssertEqual(try fileFor(out.playlist[0]), yours)
        XCTAssertEqual(out.bookmark(for: .lastAudio), Data("old-last".utf8),
                       "a failed head mint leaves the slot as it was (the established `record` contract)")
    }

    // MARK: Round trip: what `recordPlaylist` writes, `resolvePlaylist` reads back

    func testARecordedQueueWithTheSampleResolvesOnTheNextLaunchThroughTheBundleLookup() throws {
        access.registerCanned(url: mine)
        access.registerCanned(url: yours)
        let written = resolver.recordPlaylist([mine, sample.url, yours], in: PersistedBookmarks(), bundledTrack: sample)

        // The JSON hop the app's store performs.
        let reloaded = try JSONDecoder().decode(PersistedBookmarks.self, from: JSONEncoder().encode(written))
        // Next launch: the bundle moved (a new install location) — the lookup
        // answers with the sample's CURRENT url.
        let moved = BundledTrack(
            resourceName: sample.resourceName,
            url: URL(fileURLWithPath: "/Volumes/Elsewhere/Dwanim It.app/Contents/Resources/dwanim it - Sample.m4a")
        )
        let resolved = resolver.resolvePlaylist(in: reloaded) { moved.resolve(resourceName: $0) }

        XCTAssertEqual(resolved.urls, [mine, moved.url, yours])
        XCTAssertEqual(resolved.store, reloaded, "nothing to refresh: the marker is kept byte-identical")
        XCTAssertFalse(access.resolveCalls.contains(written.playlist[1]), "the marker never reaches resolveBookmark")
    }
}
