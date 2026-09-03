import Foundation

// MARK: - PlaylistSelection

/// The pure seam that carries the Cadence playlist's INDEX-based `List`
/// selection across a structural change of the queue.
///
/// The table's selection is a `Set<Int>` of row indices (the native
/// `List(selection:)` tags), so it goes stale the moment rows shift. The view
/// observes the queue's track URLs (`core.playlist.map(\.url)`) and, on change,
/// hands the old and new lists here:
///
/// - a pure **reorder** — same tracks, new positions (drag-to-reorder, Sort,
///   Reverse, Randomize) — remaps each selected row to its track's NEW index, so
///   the highlight FOLLOWS THE TRACKS exactly like `PlayerCore.currentIndex`
///   follows the playing one;
/// - any other structural change (add / remove / replace) yields an empty set,
///   preserving the clear-on-change rule the view had before drag-reorder
///   existed (the edit paths also clear explicitly, so this only backstops).
///
/// Matching is by URL, occurrence-aware: two rows for the same file (a loaded
/// `.m3u` can repeat an entry) map to the matching occurrence in the new order,
/// so two selected rows never collapse into one. Out-of-range indices are dropped.
enum PlaylistSelection {

    /// The selection to show after the queue's URLs went from `old` to `new`.
    static func following(_ selection: Set<Int>, from old: [URL], to new: [URL]) -> Set<Int> {
        guard !selection.isEmpty, isReorder(old, new) else { return [] }

        var newPositions: [URL: [Int]] = [:]
        for (index, url) in new.enumerated() {
            newPositions[url, default: []].append(index)
        }

        var occurrence: [URL: Int] = [:]
        var followed = Set<Int>()
        for (index, url) in old.enumerated() {
            let nth = occurrence[url, default: 0]
            occurrence[url] = nth + 1
            guard selection.contains(index),
                  let positions = newPositions[url], nth < positions.count else { continue }
            followed.insert(positions[nth])
        }
        return followed
    }

    /// `true` when `new` holds exactly the same URLs as `old` (as a multiset),
    /// i.e. the change was a pure reorder rather than an add / remove / replace.
    private static func isReorder(_ old: [URL], _ new: [URL]) -> Bool {
        guard old.count == new.count else { return false }
        return counts(old) == counts(new)
    }

    private static func counts(_ urls: [URL]) -> [URL: Int] {
        urls.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }
}
