import Foundation
import PlayerCore

// MARK: - BookmarkStore
//
// The app-layer persistence sink for PlayerCore's pure `PersistedBookmarks`
// value. `PersistedBookmarks` only *holds* the security-scoped bookmark bytes
// (and stays Foundation-only / Codable); this type is the I/O that PlayerCore
// deliberately does not own — it JSON-encodes the value into the app's
// sandbox container via `UserDefaults` and decodes it back at launch.
//
// ## Why UserDefaults (the app container) and not a loose file
// Under the sandbox, `UserDefaults.standard` is backed by a plist inside
// `~/Library/Containers/app.dwanim.Dwanim/…` — the same container the sandbox
// proof checks for. It is the simplest durable, per-app, atomic store for a
// small blob like this, with no extra file-coordination or path plumbing. The
// payload is one JSON `Data` under a single stable key.
//
// load() never throws: a missing key (first launch) or corrupt bytes (older /
// truncated payload) both yield an empty `PersistedBookmarks`, so the app
// always boots into a clean, usable state and simply re-records on next open.
final class BookmarkStore {

    /// The stable UserDefaults key the encoded `PersistedBookmarks` JSON lives
    /// under. Namespaced to this concern so it cannot collide with any future
    /// preference key.
    private static let defaultsKey = "app.dwanim.persistedBookmarks.v1"

    private let defaults: UserDefaults

    /// - Parameter defaults: the backing store; defaults to `.standard` (the
    ///   sandbox container's plist). Injectable so a test can pass a throwaway
    ///   suite, though no package tests touch this app-layer type.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Load

    /// Decode the persisted bookmarks. Returns an empty value when the key is
    /// absent (first launch) or the stored bytes fail to decode (corrupt /
    /// stale schema) — never throws, so launch is always recoverable.
    func load() -> PersistedBookmarks {
        guard let data = defaults.data(forKey: BookmarkStore.defaultsKey) else {
            return PersistedBookmarks()
        }
        guard let decoded = try? JSONDecoder().decode(PersistedBookmarks.self, from: data) else {
            return PersistedBookmarks()
        }
        return decoded
    }

    // MARK: Save

    /// JSON-encode and persist `bookmarks`. A failure to encode (not expected
    /// for this all-`Data`/`Codable` value) is swallowed: the prior persisted
    /// state is left intact and the in-memory session keeps working.
    func save(_ bookmarks: PersistedBookmarks) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: BookmarkStore.defaultsKey)
    }
}
