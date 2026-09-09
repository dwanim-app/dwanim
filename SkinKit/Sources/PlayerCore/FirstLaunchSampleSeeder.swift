import Foundation

// MARK: - BundledTrack

/// A track whose file lives INSIDE the app bundle (the built-in sample): the
/// resource name its persisted `BundledTrackMarker` carries, plus the resource's
/// CURRENT location in the running app.
///
/// Pure Foundation, so the two questions the persistence layer asks about such a
/// row — "is this queue URL the bundled track?" and "what is the bundled track's
/// URL for this marker name?" — are answered here, under `swift test`, and the app
/// only supplies the locator (`Bundle.main`).
public struct BundledTrack: Equatable, Sendable {

    /// The name passed to `Bundle.url(forResource:withExtension:)`, and what a
    /// persisted marker names.
    public let resourceName: String

    /// The resource's location in the running app's bundle.
    public let url: URL

    public init(resourceName: String, url: URL) {
        self.resourceName = resourceName
        self.url = url
    }

    /// Find `resourceName.ext` in `bundle`. `nil` when it does not ship — every
    /// caller degrades (no seed, no Play Sample button, no crash).
    public static func locate(resourceName: String, extension ext: String, in bundle: Bundle) -> BundledTrack? {
        bundle.url(forResource: resourceName, withExtension: ext)
            .map { BundledTrack(resourceName: resourceName, url: $0) }
    }

    /// The persisted playlist entry for this row (see `BundledTrackMarker`).
    public var marker: Data { BundledTrackMarker.marker(forResource: resourceName) }

    /// Whether a queue URL is this track — canonical-path comparison, the same
    /// membership rule `PlayerCore.append` de-duplicates by.
    public func matches(_ candidate: URL) -> Bool {
        candidate.standardizedFileURL == url.standardizedFileURL
    }

    /// The `bundledResource` lookup for `BookmarkResolver.resolvePlaylist`: this
    /// track's current URL for its own resource name, `nil` for any other.
    public func resolve(resourceName name: String) -> URL? {
        name == resourceName ? url : nil
    }
}

// MARK: - Seeding seams

/// Whether a persisted queue key has EVER been written — the "not a first launch"
/// signal. Distinct from "the decoded playlist is empty": a user who cleared their
/// queue still has a key. The app's `BookmarkStore` conforms.
public protocol PersistedQueueProbe {
    var hasPersistedQueue: Bool { get }
}

/// The persisted "the sample has been seeded" flag. Once set, the sample never
/// reappears on its own. The app's `SampleSeedStore` conforms.
public protocol SampleSeedFlagStore: AnyObject {
    var hasSeeded: Bool { get set }
}

// MARK: - FirstLaunchSampleSeeder

/// F7 — the launch-time placement of the bundled sample into the queue, as ONE
/// decision the app asks for rather than logic it re-implements.
///
/// The first-launch signal is captured at construction — BEFORE the app restores
/// the persisted queue, because a stale-refresh or a dropped entry during that
/// restore writes the key and would otherwise turn a first launch into "not first".
/// `seedIfNeeded` then applies `SampleSeedPolicy` once the queue is known: on a
/// fresh install (no key ever, flag unset, resource shipping, nothing restored) it
/// appends the sample READY — selected so ▶ plays it, but not playing, the same rule
/// as a restored queue — and sets the flag so it never reseeds. In every other case
/// it touches neither the queue nor the flag.
///
/// The app persists the queue after a seed (so the row survives relaunch through
/// its marker); `seedIfNeeded` returns the seeded URL for that.
@MainActor
public final class FirstLaunchSampleSeeder {

    private let hadPersistedQueue: Bool
    private let seedFlag: SampleSeedFlagStore
    private let sample: BundledTrack?

    /// - Parameters:
    ///   - queueStore: read ONCE, now, for the first-launch signal.
    ///   - seedFlag: the persisted "already seeded" flag, read at seed time and set
    ///     when the sample is placed.
    ///   - sample: the bundled sample, or `nil` when the resource does not ship.
    public init(queueStore: PersistedQueueProbe, seedFlag: SampleSeedFlagStore, sample: BundledTrack?) {
        self.hadPersistedQueue = queueStore.hasPersistedQueue
        self.seedFlag = seedFlag
        self.sample = sample
    }

    /// Place the sample into `core` if this is the launch that should — see the
    /// type note. Returns the seeded URL, or `nil` when nothing was seeded.
    ///
    /// - Parameter track: how the app builds a `Track` for a file (title from the
    ///   file's own name stem); the seeder does not invent one.
    @discardableResult
    public func seedIfNeeded(into core: PlayerCore, track: (URL) -> Track) -> URL? {
        guard core.playlist.isEmpty, let sample,
              SampleSeedPolicy.shouldSeed(
                  hasPersistedQueue: hadPersistedQueue,
                  alreadySeeded: seedFlag.hasSeeded,
                  sampleAvailable: true
              )
        else { return nil }
        seedFlag.hasSeeded = true
        core.append([track(sample.url)])
        return sample.url
    }
}
