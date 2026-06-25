import Foundation

// MARK: - BookmarkResolver

/// The single source of truth for **stale / refresh / drop** policy when turning
/// persisted security-scoped bookmark bytes back into usable `URL`s on launch,
/// and for recording a freshly user-opened `URL`.
///
/// ## Why this exists as a pure type
/// Resolving a bookmark has three outcomes the app must react to consistently:
/// it resolves cleanly, it resolves but is **stale** (the bytes must be
/// re-minted so the *next* launch still works), or it fails entirely (the file
/// is gone / access revoked, so the entry must be **dropped** rather than
/// retried forever). Spreading those branches across the app layer would scatter
/// the policy; instead this type owns it, takes the platform `SecurityScopedAccess`
/// and the `PersistedBookmarks` as *inputs*, performs **no I/O of its own**, and
/// returns the resolved location(s) together with the possibly-updated store the
/// caller should persist. That makes the whole policy unit-testable against a
/// `FakeSecurityScopedAccess`.
///
/// Every method returns a `(result, store)` pair: `store` is the input store
/// after any stale-refresh or drop, so the caller writes it back exactly when the
/// resolve actually changed something (compare with `==` to skip a no-op write).
public struct BookmarkResolver {

    // MARK: - Result types

    /// The outcome of resolving a single-slot role: the recovered `url` (or `nil`
    /// when the slot was empty or had to be dropped) and the `store` to persist.
    public struct RoleResolution: Equatable {
        /// The recovered location, or `nil` when the role was empty or dropped.
        public let url: URL?
        /// The store after any stale-refresh or drop; persist when it changed.
        public let store: PersistedBookmarks
    }

    /// The outcome of resolving the ordered playlist: the surviving `urls` in the
    /// original order (failed entries omitted) and the `store` to persist (with
    /// any stale entries re-minted and failed entries removed).
    public struct PlaylistResolution: Equatable {
        /// The recovered locations, in the original order, failures omitted.
        public let urls: [URL]
        /// The store after any refresh/drop; persist when it changed.
        public let store: PersistedBookmarks
    }

    // MARK: - Dependencies

    private let access: SecurityScopedAccess

    /// Creates a resolver over an injected platform `access`. The resolver holds
    /// no other state; the store is always passed in per call.
    public init(access: SecurityScopedAccess) {
        self.access = access
    }

    // MARK: - Single-slot resolve

    /// Resolves `role`'s bookmark from `store`, applying the stale/refresh/drop
    /// policy:
    /// - empty slot -> `url == nil`, store unchanged.
    /// - resolves, not stale -> returns the `url`, store **unchanged**, no
    ///   re-mint.
    /// - resolves but **stale** -> re-mints fresh bytes for the recovered `url`
    ///   via `access.bookmarkData(for:)` and returns a store holding the NEW
    ///   bytes for `role`. If the re-mint itself throws, the recovered `url` is
    ///   still returned but the slot is **dropped** (the old stale bytes are not
    ///   kept, since they will only resolve-stale again).
    /// - resolve **throws** (or bytes vanished) -> the slot is **dropped** from
    ///   the returned store; `url == nil`. Other roles and the playlist are
    ///   untouched.
    public func resolve(role: BookmarkRole, in store: PersistedBookmarks) -> RoleResolution {
        guard let data = store.bookmark(for: role) else {
            return RoleResolution(url: nil, store: store)
        }
        guard let resolved = try? access.resolveBookmark(data) else {
            var pruned = store
            pruned.clearBookmark(for: role)
            return RoleResolution(url: nil, store: pruned)
        }
        guard resolved.isStale else {
            return RoleResolution(url: resolved.url, store: store)
        }
        // Stale: still resolved, but re-mint so the next launch keeps working.
        guard let fresh = try? access.bookmarkData(for: resolved.url) else {
            var pruned = store
            pruned.clearBookmark(for: role)
            return RoleResolution(url: resolved.url, store: pruned)
        }
        var refreshed = store
        refreshed.setBookmark(fresh, for: role)
        return RoleResolution(url: resolved.url, store: refreshed)
    }

    // MARK: - Playlist resolve

    /// Resolves the ordered playlist from `store`, preserving order while
    /// applying the same per-entry policy: a clean entry passes through, a
    /// **stale** entry is re-minted in place (its bytes refreshed in the returned
    /// store) yet still contributes its `url`, and a **failing** entry (resolve
    /// throws, or its stale re-mint throws) is **dropped** without disturbing the
    /// surviving entries' order. The returned store's `playlist` is the surviving
    /// bytes in the same order (refreshed where stale).
    public func resolvePlaylist(in store: PersistedBookmarks) -> PlaylistResolution {
        var urls: [URL] = []
        var survivingData: [Data] = []
        for data in store.playlist {
            guard let resolved = try? access.resolveBookmark(data) else {
                continue // drop: failed to resolve, omit from order
            }
            guard resolved.isStale else {
                urls.append(resolved.url)
                survivingData.append(data)
                continue
            }
            // Stale: re-mint in place; if re-mint fails, drop the entry.
            guard let fresh = try? access.bookmarkData(for: resolved.url) else {
                continue
            }
            urls.append(resolved.url)
            survivingData.append(fresh)
        }
        var updated = store
        updated.setPlaylist(survivingData)
        return PlaylistResolution(urls: urls, store: updated)
    }

    // MARK: - Record a freshly opened URL

    /// Mints and stores a bookmark for a `url` the user just opened, for the
    /// single-slot `role`. Returns the store with `role` now holding the fresh
    /// bytes. If minting throws (no entitlement, vanished file), the store is
    /// returned **unchanged** and the error is rethrown so the caller can decide
    /// whether the open itself failed.
    public func record(url: URL, as role: BookmarkRole, in store: PersistedBookmarks) throws -> PersistedBookmarks {
        let data = try access.bookmarkData(for: url)
        var updated = store
        updated.setBookmark(data, for: role)
        return updated
    }

    // MARK: - Access scope passthrough

    /// Runs `body` inside `url`'s security-scoped access, delegating to the
    /// injected `access`. Exposed here so a caller holding a `BookmarkResolver`
    /// can bracket file use without separately retaining the access seam.
    public func withAccess<T>(to url: URL, perform body: () throws -> T) rethrows -> T {
        try access.withAccess(to: url, perform: body)
    }
}
