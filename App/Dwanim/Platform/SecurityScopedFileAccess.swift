import Foundation
import PlayerCore

// MARK: - SecurityScopedFileAccess
//
// The concrete, app-layer implementation of PlayerCore's `SecurityScopedAccess`
// seam. PlayerCore stays Foundation/Observation-only (§3.2: it owns persistence
// *policy*, never the platform calls); this type is where the actual
// security-scoped bookmark machinery lives, exactly mirroring how PlaybackKit's
// `AVAudioEnginePlayer` is the concrete side of the `AudioPlaybackEngine` seam.
//
// ## The sandbox contract this type satisfies
// A sandboxed app (entitlements: app-sandbox + files.user-selected.read-write +
// files.bookmarks.app-scope) may freely read a file the user just picked in an
// NSOpenPanel, but that grant evaporates when the app quits. To re-open the same
// file on a later launch the app must, *while still holding the panel grant*,
// mint a **security-scoped bookmark** (opaque bytes) and persist it. On the next
// launch it resolves those bytes back into a URL and brackets every file touch
// with `start/stopAccessingSecurityScopedResource()` — that bracket is what
// re-arms the sandbox grant for the resolved URL.
//
// This type is intentionally AppKit-free: it needs only Foundation (URL bookmark
// APIs) and the Security entitlements baked into the bundle. No `import Security`
// is required — the `.withSecurityScope` options on `URL` are Foundation surface.
//
// All three methods are documented against the protocol's stated contract
// (mint / resolve+stale / balanced-bracket).
final class SecurityScopedFileAccess: SecurityScopedAccess {

    // MARK: Mint

    /// Mint persistable security-scoped bookmark bytes for `url`.
    ///
    /// Calls `url.bookmarkData(options: .withSecurityScope, ...)`. The
    /// `.withSecurityScope` option is what makes the resulting bytes carry the
    /// sandbox grant; without it the bookmark would resolve but the resolved URL
    /// could not be `start`-accessed under the sandbox. The OS throws here if the
    /// entitlement is missing or the file has vanished — the resolve policy
    /// (`BookmarkResolver`) treats a throw on minting as "could not record".
    func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    // MARK: Resolve

    /// Resolve previously stored bookmark `data` back into a `ResolvedBookmark`.
    ///
    /// Calls `URL(resolvingBookmarkData:options:[.withSecurityScope], ...)`,
    /// mapping the `bookmarkDataIsStale` out-parameter into
    /// `ResolvedBookmark.isStale`. A throw (deleted/moved-away file, revoked
    /// access) is propagated; `BookmarkResolver` treats it as "drop this entry".
    /// A non-throwing resolve with `isStale == true` means the bytes still
    /// resolved but should be re-minted so the *next* launch keeps working.
    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    // MARK: Access bracket

    /// Run `body` inside `url`'s security-scoped access scope.
    ///
    /// Brackets `body` with a balanced
    /// `startAccessingSecurityScopedResource()` / `defer { stop… }` pair, so the
    /// scope is always torn down — even if `body` throws. This is what re-arms
    /// the sandbox grant for a URL recovered from a bookmark; for an already-
    /// accessible URL (e.g. one the user just picked in this same launch) the
    /// start call simply returns `false` and the matching stop is a harmless
    /// no-op, so the contract ("`body` always runs, value/throw propagates")
    /// holds either way.
    ///
    /// - Important: This is a *transient* bracket — it opens the scope, runs
    ///   `body`, and closes it. The app's playback-session lifetime (keeping the
    ///   scope open for the duration a file is playing) is managed one layer up
    ///   in the app (see `DwanimApp`'s session-scope handling), which calls
    ///   `start…` once on load and the matching `stop…` on replace/quit; this
    ///   method is used for the short, self-contained touches (e.g. minting on
    ///   open).
    func withAccess<T>(to url: URL, perform body: () throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            // Balance the start: only stop when we actually started a scope here.
            // `stopAccessing…` on a URL we did not start is documented as safe,
            // but pairing it with `didStart` keeps the bracket honest and avoids
            // decrementing a scope another owner holds.
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }
}
