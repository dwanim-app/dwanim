import Foundation

// MARK: - BookmarkRole

/// The single-slot roles a security-scoped bookmark can fill: the last audio
/// file the user opened and the last skin they applied. The ordered playlist is
/// stored separately (see `PersistedBookmarks.playlist`) because it is a list,
/// not a slot.
///
/// `String`-backed so the `Codable` representation is a stable, human-readable
/// key rather than an ordinal that would shift if a case were inserted.
public enum BookmarkRole: String, Codable, Sendable, CaseIterable {
    /// The last single audio file the user opened.
    case lastAudio
    /// The last skin the user applied.
    case lastSkin
}

// MARK: - PersistedBookmarks

/// The pure, `Codable` value that persists tagged security-scoped bookmark bytes
/// across launches: a small map of single `BookmarkRole` slots plus an ordered
/// list for the playlist's queued files.
///
/// ## Why a value type with pure mutators (no I/O)
/// This type only *holds* bytes; it never reads or writes a file, never touches
/// `UserDefaults`, and never resolves a bookmark. The app layer (#6) encodes it
/// (it round-trips through JSON) into its container/`UserDefaults` and decodes it
/// at launch; `BookmarkResolver` turns its bytes back into `URL`s via an injected
/// `SecurityScopedAccess`. Keeping it a plain `Codable`/`Equatable`/`Sendable`
/// value makes the store trivially testable and safe to pass across actors.
///
/// The `Data` payloads are opaque security-scoped bookmark bytes; this type
/// makes no claim about their format and only stores/replaces/drops them.
public struct PersistedBookmarks: Codable, Equatable, Sendable {

    // MARK: - Stored state

    /// Bytes for each single-slot role, keyed by `BookmarkRole`. A role with no
    /// stored bookmark is simply absent from the map.
    public private(set) var roles: [BookmarkRole: Data]

    /// The queued playlist files' bookmark bytes, **in playback order**. Order is
    /// meaningful, so this is an array rather than a set or a keyed map.
    public private(set) var playlist: [Data]

    // MARK: - Init

    /// Creates a store. Defaults to empty (no roles, empty playlist).
    public init(roles: [BookmarkRole: Data] = [:], playlist: [Data] = []) {
        self.roles = roles
        self.playlist = playlist
    }

    // MARK: - Single-slot mutators

    /// Sets (or replaces) the bytes for `role`. Pure: returns nothing, mutates in
    /// place on a value, so callers work with copies.
    public mutating func setBookmark(_ data: Data, for role: BookmarkRole) {
        roles[role] = data
    }

    /// The stored bytes for `role`, or `nil` when the slot is empty.
    public func bookmark(for role: BookmarkRole) -> Data? {
        roles[role]
    }

    /// Removes any bytes stored for `role`. A no-op when the slot is already
    /// empty.
    public mutating func clearBookmark(for role: BookmarkRole) {
        roles[role] = nil
    }

    // MARK: - Playlist mutators

    /// Replaces the entire ordered playlist with `data`, preserving the given
    /// order.
    public mutating func setPlaylist(_ data: [Data]) {
        playlist = data
    }

    /// Removes all playlist entries, leaving the single-slot roles untouched.
    public mutating func clearPlaylist() {
        playlist = []
    }
}
