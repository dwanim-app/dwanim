import Foundation

// MARK: - ResolvedBookmark

/// The pure result of resolving a security-scoped bookmark's bytes back into a
/// location: the recovered `url` plus whether the system reported the bookmark
/// as **stale** (the file moved/changed enough that the bytes should be
/// re-minted, even though they still resolved this time).
///
/// This is a plain `Foundation`-only value so the resolve policy
/// (`BookmarkResolver`) can branch on `isStale` and the recovered `url` without
/// the core ever importing `Security`. The concrete platform implementation maps
/// the `Bool` out-parameter of `URL(resolvingBookmarkData:...:bookmarkDataIsStale:)`
/// into this struct.
public struct ResolvedBookmark: Sendable, Equatable {
    /// The file location recovered from the bookmark bytes.
    public let url: URL
    /// Whether the system flagged the bookmark as stale on resolve. When `true`,
    /// the bytes still resolved but the caller should re-mint a fresh bookmark
    /// from `url` and persist it, so the next launch keeps working.
    public let isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

// MARK: - SecurityScopedAccess

/// The platform seam for **security-scoped bookmarks**: minting persistable
/// bytes for a user-granted `URL`, resolving those bytes back into a `URL` on a
/// later launch, and running a body inside an access scope for that `URL`.
///
/// ## Why this is an abstract protocol (and lives here)
/// A sandboxed app cannot simply re-open a file by path across launches — the
/// sandbox only grants durable access through a *security-scoped bookmark*. The
/// real implementation calls `URL.bookmarkData(options: .withSecurityScope)`,
/// `URL(resolvingBookmarkData:options: .withSecurityScope ...)`, and brackets
/// file use with `start/stopAccessingSecurityScopedResource()`. All of that
/// lives in `Security`/`AppKit`-adjacent code in the app layer (#6).
///
/// `PlayerCore` must stay `Foundation`/`Observation`-only (§3.2 names it the home
/// of persistence *policy*, not of the platform calls). So this protocol is the
/// abstraction the pure resolve logic (`BookmarkResolver`) depends on, exactly
/// mirroring how `PlayerCore` depends on `AudioPlaybackEngine` while the
/// `AVFoundation`-backed engine lives in `PlaybackKit`. The protocol deliberately
/// HIDES the `.withSecurityScope` option, the stale out-parameter plumbing, and
/// the `start/stopAccessingSecurityScopedResource` bracket: callers in the core
/// see only `Data`, `URL`, and `ResolvedBookmark`, never a `Security` type.
///
/// ## Method shapes (and why each exists)
/// - `bookmarkData(for:)` — mint persistable bytes for a `URL` the user just
///   granted (via an open panel) OR re-mint when a resolve came back stale. It
///   `throws` because the OS can refuse (no entitlement, vanished file); the
///   resolve policy treats a throw on *minting* as a failure to record.
/// - `resolveBookmark(_:)` — turn stored bytes back into a `ResolvedBookmark`. It
///   `throws` when the bytes can no longer resolve (file deleted, volume gone,
///   access revoked); the resolve policy treats a throw as "drop this entry".
/// - `withAccess(to:perform:)` — run `body` while the security-scoped resource
///   is started, guaranteeing the matching stop even if `body` throws. The core
///   needs this so it can hand a resolved `URL` to the audio engine *inside* a
///   live access scope. It `rethrows` so a non-throwing `body` stays non-throwing
///   and a throwing `body`'s error propagates after the scope is torn down.
///
/// - Note: A real implementation is free to make `withAccess` a no-op scope for a
///   `URL` it did not resolve from a bookmark (e.g. during tests or for
///   already-accessible files); the protocol only promises that `body` runs and
///   its value/throw propagates.
public protocol SecurityScopedAccess: AnyObject {
    /// Mint security-scoped bookmark bytes for `url`. Throws if the system
    /// refuses (missing entitlement, vanished file). The bytes are opaque and
    /// meant to be persisted (e.g. in `PersistedBookmarks`).
    func bookmarkData(for url: URL) throws -> Data

    /// Resolve previously stored bookmark `data` back into a `ResolvedBookmark`.
    /// Throws when the bytes can no longer be resolved (deleted/moved-away file,
    /// revoked access), which the resolve policy treats as a drop.
    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark

    /// Run `body` while `url`'s security-scoped resource is started, tearing the
    /// scope down afterward even if `body` throws. `rethrows`, so the call is
    /// throwing only when `body` is.
    func withAccess<T>(to url: URL, perform body: () throws -> T) rethrows -> T
}
