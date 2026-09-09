import Foundation
import XCTest
@testable import PlayerCore

// MARK: - FirstLaunchSampleSeederTests
//
// F7 — the launch-time seed of the bundled sample, as a PlayerCore-tier type so
// the WHOLE decision (not just the pure `SampleSeedPolicy` predicate) is pinned by
// `swift test`. The app used to make this decision inline in `AudioSession`, where
// no package test could reach it: inverting the first-launch argument, or dropping
// the "flag = true" line, changed nothing in the suite. Now the app hands the
// seeder its stores and its core and asks once; every branch below is a mutant
// that used to survive by construction.

@MainActor
final class FirstLaunchSampleSeederTests: XCTestCase {

    private final class QueueProbe: PersistedQueueProbe {
        var hasPersistedQueue: Bool
        init(hasPersistedQueue: Bool) { self.hasPersistedQueue = hasPersistedQueue }
    }

    private final class SeedFlag: SampleSeedFlagStore {
        var hasSeeded: Bool { didSet { writes.append(hasSeeded) } }
        /// Every write, so "the flag was left alone" is `writes == []`.
        private(set) var writes: [Bool] = []
        init(hasSeeded: Bool) { self.hasSeeded = hasSeeded }
    }

    private let sample = BundledTrack(
        resourceName: "dwanim it - Sample",
        url: URL(fileURLWithPath: "/Applications/Dwanim It.app/Contents/Resources/dwanim it - Sample.m4a")
    )

    private var engine: FakePlaybackEngine!
    private var core: PlayerCore!

    override func setUp() async throws {
        engine = FakePlaybackEngine()
        core = PlayerCore(engine: engine)
    }

    private func track(_ url: URL) -> Track {
        Track(url: url, title: url.deletingPathExtension().lastPathComponent)
    }

    private func seeder(
        hasPersistedQueue: Bool, alreadySeeded: Bool, sample: BundledTrack?
    ) -> (FirstLaunchSampleSeeder, SeedFlag) {
        let flag = SeedFlag(hasSeeded: alreadySeeded)
        let seeder = FirstLaunchSampleSeeder(
            queueStore: QueueProbe(hasPersistedQueue: hasPersistedQueue),
            seedFlag: flag,
            sample: sample
        )
        return (seeder, flag)
    }

    // MARK: A fresh install seeds exactly once, READY

    func testAFreshInstallSeedsTheSampleReadyNotPlayingAndSetsTheFlag() {
        let (seeder, flag) = seeder(hasPersistedQueue: false, alreadySeeded: false, sample: sample)

        let seeded = seeder.seedIfNeeded(into: core, track: track)

        XCTAssertEqual(seeded, sample.url, "the seeded URL comes back so the app can persist it")
        XCTAssertEqual(core.playlist.map(\.url), [sample.url])
        XCTAssertEqual(core.currentIndex, 0, "the sample is selected, so ▶ plays it")
        XCTAssertFalse(core.isPlaying, "READY, not playing — the same rule as a restored queue")
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertEqual(engine.loadedURLs, [], "nothing is even loaded into the engine yet")
        XCTAssertTrue(flag.hasSeeded, "the persisted flag is set so the sample never reseeds")
    }

    func testTheSameLaunchNeverSeedsTwice() {
        let (seeder, _) = seeder(hasPersistedQueue: false, alreadySeeded: false, sample: sample)
        _ = seeder.seedIfNeeded(into: core, track: track)

        XCTAssertNil(seeder.seedIfNeeded(into: core, track: track))
        XCTAssertEqual(core.playlist.count, 1)
    }

    func testTheNextLaunchSeesTheFlagAndDoesNotReseedARemovedSample() {
        // Launch 1 seeds; the user removes the sample and the queue persists empty.
        let flag = SeedFlag(hasSeeded: false)
        let probe = QueueProbe(hasPersistedQueue: false)
        _ = FirstLaunchSampleSeeder(queueStore: probe, seedFlag: flag, sample: sample)
            .seedIfNeeded(into: core, track: track)
        XCTAssertTrue(flag.hasSeeded)
        core.remove(at: [0])
        probe.hasPersistedQueue = true

        // Launch 2 (and a launch 3 with the key somehow gone again): still no seed.
        let relaunch = PlayerCore(engine: FakePlaybackEngine())
        XCTAssertNil(FirstLaunchSampleSeeder(queueStore: probe, seedFlag: flag, sample: sample)
            .seedIfNeeded(into: relaunch, track: track))
        probe.hasPersistedQueue = false
        XCTAssertNil(FirstLaunchSampleSeeder(queueStore: probe, seedFlag: flag, sample: sample)
            .seedIfNeeded(into: relaunch, track: track), "the flag alone is enough to stop a reseed")
        XCTAssertTrue(relaunch.playlist.isEmpty)
    }

    // MARK: Not a first launch

    func testAPersistedKeyHoldingAnEmptyQueueIsNotAFirstLaunch() {
        // A user who cleared their own queue: the key exists, the queue is empty.
        let (seeder, flag) = seeder(hasPersistedQueue: true, alreadySeeded: false, sample: sample)

        XCTAssertNil(seeder.seedIfNeeded(into: core, track: track))
        XCTAssertTrue(core.playlist.isEmpty, "their empty queue stays empty")
        XCTAssertFalse(flag.hasSeeded, "and the flag is left alone: nothing was seeded")
        XCTAssertEqual(flag.writes, [])
    }

    func testAnAlreadySeededFlagNeverSeeds() {
        let (seeder, flag) = seeder(hasPersistedQueue: false, alreadySeeded: true, sample: sample)

        XCTAssertNil(seeder.seedIfNeeded(into: core, track: track))
        XCTAssertTrue(core.playlist.isEmpty)
        XCTAssertEqual(flag.writes, [])
    }

    func testARestoredQueueIsNeverDisplacedOrJoinedByTheSample() {
        // Belt and braces: even if the first-launch probe says "fresh", a queue
        // that the restore populated is the user's — leave it, and leave the flag.
        let (seeder, flag) = seeder(hasPersistedQueue: false, alreadySeeded: false, sample: sample)
        let mine = track(URL(fileURLWithPath: "/Users/me/Music/mine.mp3"))
        core.load([mine])

        XCTAssertNil(seeder.seedIfNeeded(into: core, track: track))
        XCTAssertEqual(core.playlist.map(\.url), [mine.url])
        XCTAssertFalse(flag.hasSeeded)
    }

    // MARK: The resource does not ship

    func testAMissingResourceSeedsNothingAndLeavesTheFlagUnsetForALaterBuildThatShipsIt() {
        let (seeder, flag) = seeder(hasPersistedQueue: false, alreadySeeded: false, sample: nil)

        XCTAssertNil(seeder.seedIfNeeded(into: core, track: track))
        XCTAssertTrue(core.playlist.isEmpty)
        XCTAssertFalse(flag.hasSeeded)
        XCTAssertEqual(flag.writes, [])
    }

    // MARK: Ordering: the first-launch signal is read BEFORE the restore can write the key

    func testTheFirstLaunchSignalIsCapturedAtConstructionNotAtSeedTime() {
        let flag = SeedFlag(hasSeeded: false)
        let probe = QueueProbe(hasPersistedQueue: false)
        let seeder = FirstLaunchSampleSeeder(queueStore: probe, seedFlag: flag, sample: sample)

        // The launch restore runs between construction and the seed and (on a
        // stale-refresh or drop) writes the key — that must not turn a first
        // launch into "not first".
        probe.hasPersistedQueue = true

        XCTAssertEqual(seeder.seedIfNeeded(into: core, track: track), sample.url)
        XCTAssertTrue(flag.hasSeeded)
    }

    func testAKeyPresentAtConstructionIsNotAFirstLaunchEvenIfItVanishesLater() {
        let flag = SeedFlag(hasSeeded: false)
        let probe = QueueProbe(hasPersistedQueue: true)
        let seeder = FirstLaunchSampleSeeder(queueStore: probe, seedFlag: flag, sample: sample)
        probe.hasPersistedQueue = false

        XCTAssertNil(seeder.seedIfNeeded(into: core, track: track))
        XCTAssertFalse(flag.hasSeeded)
    }
}

// MARK: - BundledTrackTests

final class BundledTrackTests: XCTestCase {

    private let url = URL(fileURLWithPath: "/tmp/Some.app/Contents/Resources/dwanim it - Sample.m4a")
    private lazy var sample = BundledTrack(resourceName: "dwanim it - Sample", url: url)

    func testTheMarkerNamesTheResourceNotThePath() {
        XCTAssertEqual(BundledTrackMarker.resourceName(in: sample.marker), "dwanim it - Sample")
        XCTAssertFalse(String(decoding: sample.marker, as: UTF8.self).contains("/tmp/Some.app"),
                       "a marker must survive the bundle moving, so it never carries the path")
    }

    func testMatchingIsByCanonicalFileURL() {
        XCTAssertTrue(sample.matches(url))
        XCTAssertTrue(sample.matches(URL(fileURLWithPath: "/tmp/Some.app/Contents/Resources/../Resources/dwanim it - Sample.m4a")))
        XCTAssertFalse(sample.matches(URL(fileURLWithPath: "/tmp/Some.app/Contents/Resources/other.m4a")))
        XCTAssertFalse(sample.matches(URL(fileURLWithPath: "/Users/me/Music/dwanim it - Sample.m4a")),
                       "a user's own file with the same name is NOT the bundled sample")
    }

    func testTheBundledLookupAnswersOnlyForItsOwnResourceName() {
        XCTAssertEqual(sample.resolve(resourceName: "dwanim it - Sample"), url)
        XCTAssertNil(sample.resolve(resourceName: "Some Other Track"))
    }

    func testLocateFindsAShippedResourceAndIsNilWhenItDoesNotShip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwanim-bundled-track-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Ships.m4a")
        try Data([0]).write(to: file)
        let bundle = try XCTUnwrap(Bundle(url: dir))

        let found = try XCTUnwrap(BundledTrack.locate(resourceName: "Ships", extension: "m4a", in: bundle))
        XCTAssertEqual(found.resourceName, "Ships")
        XCTAssertEqual(found.url.standardizedFileURL.resolvingSymlinksInPath(),
                       file.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertNil(BundledTrack.locate(resourceName: "Missing", extension: "m4a", in: bundle),
                     "a resource that does not ship degrades to nil, never a crash")
    }
}
