import Foundation

// MARK: - BundledTrackMarker

/// The persisted form of a queue row whose file lives INSIDE the app bundle (the
/// built-in sample track).
///
/// ## Why a marker and not a bookmark
/// Every other queue row is persisted as security-scoped bookmark bytes, minted
/// for a file the user granted. A bundle-resident file needs no grant — but its
/// path changes with every app update and install location, so a bookmark to it
/// would resolve stale (or not at all) and the row would silently drop out of the
/// restored queue. Instead the row is stored as a small, recognisable payload that
/// names the bundled RESOURCE; on the next launch `BookmarkResolver.resolvePlaylist`
/// hands that name to an injected lookup (`Bundle.main.url(forResource:…)` in the
/// app) for the resource's CURRENT location. The marker sits in the same ordered
/// `PersistedBookmarks.playlist` array as the bookmarks, so the row keeps its slot
/// between the user's own files.
///
/// The payload is a fixed, versioned ASCII prefix followed by the resource name
/// (UTF-8). Real bookmark bytes are an opaque binary blob that never starts with
/// this prefix, so the two cannot be confused in either direction.
public enum BundledTrackMarker {

    /// The versioned prefix every marker starts with. Changing it orphans every
    /// existing store's bundled rows — `BundledTrackPersistenceTests` pins it.
    static let prefix = "dwanim.bundled-track.v1:"

    /// The persisted bytes for the bundled resource `name` (the file's name without
    /// its extension, as passed to `Bundle.url(forResource:withExtension:)`).
    public static func marker(forResource name: String) -> Data {
        Data((prefix + name).utf8)
    }

    /// The resource name a marker carries, or `nil` when `data` is not a marker
    /// (ordinary bookmark bytes, empty, or a marker with no name to look up).
    public static func resourceName(in data: Data) -> String? {
        let head = Data(prefix.utf8)
        guard data.count > head.count, data.prefix(head.count) == head else { return nil }
        guard let name = String(data: data.dropFirst(head.count), encoding: .utf8),
              !name.isEmpty else { return nil }
        return name
    }
}

// MARK: - SampleSeedPolicy

/// F7 — WHEN the built-in sample track is placed into the queue: exactly once, on
/// the first launch of a fresh install, and only when the resource ships.
///
/// - `hasPersistedQueue`: whether a persisted queue key has EVER been written.
///   Any existing store — even one holding an empty queue — means this is not a
///   first launch, and a user who emptied their own queue is never re-seeded.
/// - `alreadySeeded`: the persisted "sample seeded" flag; once set, the sample
///   never comes back on its own (the empty state's Play Sample button re-adds it
///   on demand).
/// - `sampleAvailable`: whether the bundled resource was found; a missing
///   resource degrades to "no seed" rather than a crash.
public enum SampleSeedPolicy {
    public static func shouldSeed(
        hasPersistedQueue: Bool, alreadySeeded: Bool, sampleAvailable: Bool
    ) -> Bool {
        sampleAvailable && !hasPersistedQueue && !alreadySeeded
    }
}
