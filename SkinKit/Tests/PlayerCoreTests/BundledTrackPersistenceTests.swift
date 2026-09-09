import Foundation
import XCTest
@testable import PlayerCore

// MARK: - BundledTrackPersistenceTests
//
// F7 — the bundled sample track has to SURVIVE A RELAUNCH like any other queue
// row, but it cannot be persisted the way user files are. A security-scoped
// bookmark is minted for a file the user granted; the sample lives inside the
// app bundle, whose path changes with every update and install location, so a
// bookmark to it would resolve stale or fail and the row would silently vanish.
//
// So a bundle-resident row is persisted as a MARKER — a small, recognisable byte
// payload naming the bundled resource — stored in the same ordered playlist array
// as the bookmarks (order is what the queue is). `BookmarkResolver.resolvePlaylist`
// recognises a marker and asks an injected lookup for the resource's CURRENT URL,
// never handing it to the security-scoped resolver. A marker whose resource no
// longer ships is dropped like a vanished file, so the queue always loads.
final class BundledTrackPersistenceTests: XCTestCase {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/music/\(name)")
    }

    private let sampleName = "dwanim it - Sample"
    private var bundleURL: URL { URL(fileURLWithPath: "/Applications/dwanim it.app/Contents/Resources/dwanim it - Sample.m4a") }

    // MARK: - The marker codec

    func testMarkerRoundTripsTheResourceName() {
        let data = BundledTrackMarker.marker(forResource: sampleName)
        XCTAssertEqual(BundledTrackMarker.resourceName(in: data), sampleName)
    }

    func testMarkerIsNeverMistakenForBookmarkBytesAndViceVersa() {
        XCTAssertNil(BundledTrackMarker.resourceName(in: Data("bookmark:/music/a.mp3".utf8)))
        XCTAssertNil(BundledTrackMarker.resourceName(in: Data()))
        XCTAssertNil(BundledTrackMarker.resourceName(in: Data([0x00, 0x01, 0xFF])))
        // A marker with an EMPTY name is not a marker (nothing to look up).
        XCTAssertNil(BundledTrackMarker.resourceName(in: BundledTrackMarker.marker(forResource: "")))
    }

    func testMarkerIsStableAcrossProcessesSoAnOldStoreStillResolves() {
        // The literal bytes an earlier launch wrote. If the prefix ever changes,
        // every existing store's sample row silently disappears — pin it.
        let expected = Data("dwanim.bundled-track.v1:dwanim it - Sample".utf8)
        XCTAssertEqual(BundledTrackMarker.marker(forResource: sampleName), expected)
    }

    // MARK: - Resolving a playlist that holds a marker

    func testMarkerResolvesThroughTheBundledLookupAndKeepsItsPlaceInOrder() {
        let access = FakeSecurityScopedAccess()
        let a = access.registerCanned(url: url("a.mp3"))
        let b = access.registerCanned(url: url("b.mp3"))
        let marker = BundledTrackMarker.marker(forResource: sampleName)
        var store = PersistedBookmarks()
        store.setPlaylist([a, marker, b])

        let resolver = BookmarkResolver(access: access)
        let result = resolver.resolvePlaylist(in: store) { name in
            name == self.sampleName ? self.bundleURL : nil
        }

        XCTAssertEqual(result.urls, [url("a.mp3"), bundleURL, url("b.mp3")],
                       "the sample keeps its slot between the user's files")
        XCTAssertEqual(result.store, store, "a resolvable marker is kept verbatim (never re-minted)")
        XCTAssertEqual(access.resolveCalls, [a, b],
                       "the marker is never handed to the security-scoped resolver")
        XCTAssertEqual(access.bookmarkDataCallCount, 0)
    }

    func testMarkerForAResourceThatNoLongerShipsIsDroppedLikeAVanishedFile() {
        let access = FakeSecurityScopedAccess()
        let a = access.registerCanned(url: url("a.mp3"))
        let marker = BundledTrackMarker.marker(forResource: "retired-sample")
        var store = PersistedBookmarks()
        store.setPlaylist([marker, a])

        let result = BookmarkResolver(access: access).resolvePlaylist(in: store) { _ in nil }

        XCTAssertEqual(result.urls, [url("a.mp3")])
        XCTAssertEqual(result.store.playlist, [a], "the dead marker is pruned from the store")
    }

    func testWithoutABundledLookupAMarkerIsDroppedNotCrashedOn() {
        // The default lookup knows no resources: a marker is simply an entry that
        // cannot resolve. Nothing throws, nothing reaches the bookmark resolver.
        let access = FakeSecurityScopedAccess()
        let marker = BundledTrackMarker.marker(forResource: sampleName)
        var store = PersistedBookmarks()
        store.setPlaylist([marker])

        let result = BookmarkResolver(access: access).resolvePlaylist(in: store)

        XCTAssertEqual(result.urls, [])
        XCTAssertEqual(result.store.playlist, [])
        XCTAssertEqual(access.resolveCalls, [])
    }

    func testStaleAndFailingBookmarksAroundAMarkerAreStillHandledPerEntry() {
        let access = FakeSecurityScopedAccess()
        let stale = access.registerCanned(url: url("stale.mp3"), isStale: true)
        let gone = access.registerCanned(url: url("gone.mp3"), resolveThrows: true)
        let marker = BundledTrackMarker.marker(forResource: sampleName)
        var store = PersistedBookmarks()
        store.setPlaylist([stale, marker, gone])

        let result = BookmarkResolver(access: access).resolvePlaylist(in: store) { _ in self.bundleURL }

        XCTAssertEqual(result.urls, [url("stale.mp3"), bundleURL])
        XCTAssertEqual(result.store.playlist.count, 2, "stale re-minted, marker kept, gone dropped")
        XCTAssertNotEqual(result.store.playlist.first, stale, "the stale entry was re-minted")
        XCTAssertEqual(result.store.playlist.last, marker, "the marker is byte-identical")
    }

    // MARK: - The full relaunch round trip (persist -> JSON -> resolve)

    func testAPersistedMarkerSurvivesTheJSONRoundTripAndResolvesOnTheNextLaunch() throws {
        let access = FakeSecurityScopedAccess()
        let marker = BundledTrackMarker.marker(forResource: sampleName)
        var store = PersistedBookmarks()
        store.setPlaylist([marker])

        // What `BookmarkStore` does at quit / relaunch.
        let json = try JSONEncoder().encode(store)
        let reloaded = try JSONDecoder().decode(PersistedBookmarks.self, from: json)

        // Next launch: the app moved (a different install path) — a bookmark
        // would have broken; the marker asks for the CURRENT bundle URL.
        let moved = URL(fileURLWithPath: "/Volumes/Other/dwanim it.app/Contents/Resources/dwanim it - Sample.m4a")
        let result = BookmarkResolver(access: access).resolvePlaylist(in: reloaded) { name in
            name == self.sampleName ? moved : nil
        }
        XCTAssertEqual(result.urls, [moved])
    }
}

// MARK: - SampleSeedPolicyTests

/// F7 — WHEN the sample is seeded into the queue. Exactly once, on the very first
/// launch (no persisted queue has ever existed), and only if the resource actually
/// ships. A persisted "seeded" flag stops it coming back after the user removes it;
/// a user who cleared their own queue is likewise never re-seeded.
final class SampleSeedPolicyTests: XCTestCase {

    func testFirstLaunchWithTheResourcePresentSeeds() {
        XCTAssertTrue(SampleSeedPolicy.shouldSeed(
            hasPersistedQueue: false, alreadySeeded: false, sampleAvailable: true
        ))
    }

    func testAnExistingPersistedQueueMeansNotAFirstLaunch() {
        XCTAssertFalse(SampleSeedPolicy.shouldSeed(
            hasPersistedQueue: true, alreadySeeded: false, sampleAvailable: true
        ), "a user who has (or had) a queue is never seeded — even an empty one")
    }

    func testOnceSeededNeverAgain() {
        XCTAssertFalse(SampleSeedPolicy.shouldSeed(
            hasPersistedQueue: false, alreadySeeded: true, sampleAvailable: true
        ))
    }

    func testAMissingResourceNeverSeeds() {
        XCTAssertFalse(SampleSeedPolicy.shouldSeed(
            hasPersistedQueue: false, alreadySeeded: false, sampleAvailable: false
        ), "degrade gracefully: no resource, no seed, no crash")
    }
}
