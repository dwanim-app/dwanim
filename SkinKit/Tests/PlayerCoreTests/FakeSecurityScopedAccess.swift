import Foundation
@testable import PlayerCore

// MARK: - FakeSecurityScopedAccess

/// A test double conforming to `SecurityScopedAccess` that maps `URL`s to canned
/// bookmark `Data` and back, so the pure stale/refresh/drop policy in
/// `BookmarkResolver` can be driven and asserted entirely in memory — no
/// `Security` framework involved.
///
/// Configure it by `register(...)`-ing each URL: its current bookmark bytes,
/// whether resolving should report **stale**, and whether resolving should
/// **throw** (simulating a vanished / again-sandboxed file). It keeps a call log
/// — `bookmarkDataCalls` (the URLs minted, in order) and `resolvedDataCount` and
/// `withAccessURLs` — so a test can assert that a refresh ACTUALLY re-minted a
/// bookmark (not just returned the same bytes).
///
/// Minting (`bookmarkData(for:)`) returns the URL's *current* registered bytes,
/// or, when re-minting a stale URL, fresh bytes distinct from the old ones (so a
/// test can prove the store changed). A URL marked `mintThrows` makes
/// `bookmarkData(for:)` throw.
final class FakeSecurityScopedAccess: SecurityScopedAccess {

    // MARK: - Canned entry

    private struct Entry {
        var data: Data
        var url: URL
        var isStale: Bool
        var resolveThrows: Bool
        var mintThrows: Bool
    }

    enum FakeError: Error { case vanished, cannotMint }

    /// Registered entries keyed by their bookmark bytes (resolve is bytes -> URL)
    /// and by URL (mint is URL -> bytes).
    private var byData: [Data: Entry] = [:]
    private var byURL: [URL: Entry] = [:]

    /// Monotonic counter so each freshly minted bookmark is distinguishable.
    private var mintSerial = 0

    // MARK: - Call log

    /// Every URL passed to `bookmarkData(for:)`, in order.
    private(set) var bookmarkDataCalls: [URL] = []
    /// Every `Data` passed to `resolveBookmark(_:)`, in order.
    private(set) var resolveCalls: [Data] = []
    /// Every URL passed to `withAccess(to:perform:)`, in order.
    private(set) var withAccessURLs: [URL] = []

    var bookmarkDataCallCount: Int { bookmarkDataCalls.count }

    // MARK: - Registration helpers

    /// Registers `url` with its canned bookmark `data`. Set `isStale` to make
    /// resolving report stale (so the resolver re-mints), `resolveThrows` to make
    /// resolving throw (a dropped entry), and `mintThrows` to make minting throw.
    func register(
        url: URL,
        data: Data,
        isStale: Bool = false,
        resolveThrows: Bool = false,
        mintThrows: Bool = false
    ) {
        let entry = Entry(
            data: data,
            url: url,
            isStale: isStale,
            resolveThrows: resolveThrows,
            mintThrows: mintThrows
        )
        byData[data] = entry
        byURL[url] = entry
    }

    /// Convenience: register `url` with bytes derived from its path, returning the
    /// bytes so a test can seed a `PersistedBookmarks`.
    @discardableResult
    func registerCanned(
        url: URL,
        isStale: Bool = false,
        resolveThrows: Bool = false,
        mintThrows: Bool = false
    ) -> Data {
        let data = Data("bookmark:\(url.path)".utf8)
        register(
            url: url,
            data: data,
            isStale: isStale,
            resolveThrows: resolveThrows,
            mintThrows: mintThrows
        )
        return data
    }

    // MARK: - SecurityScopedAccess

    func bookmarkData(for url: URL) throws -> Data {
        bookmarkDataCalls.append(url)
        guard let entry = byURL[url] else {
            // Unregistered URL: mint deterministic fresh bytes.
            mintSerial += 1
            return Data("minted:\(url.path):\(mintSerial)".utf8)
        }
        if entry.mintThrows { throw FakeError.cannotMint }
        // Re-mint produces FRESH, distinct bytes so a refresh is observable.
        mintSerial += 1
        let fresh = Data("refreshed:\(url.path):\(mintSerial)".utf8)
        var updated = entry
        updated.data = fresh
        updated.isStale = false // the freshly minted bookmark is no longer stale
        byURL[url] = updated
        byData[fresh] = updated
        return fresh
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        resolveCalls.append(data)
        guard let entry = byData[data] else { throw FakeError.vanished }
        if entry.resolveThrows { throw FakeError.vanished }
        return ResolvedBookmark(url: entry.url, isStale: entry.isStale)
    }

    func withAccess<T>(to url: URL, perform body: () throws -> T) rethrows -> T {
        withAccessURLs.append(url)
        return try body()
    }
}
