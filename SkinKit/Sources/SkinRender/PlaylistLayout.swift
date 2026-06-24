import Foundation

// MARK: - PlaylistLayout
//
// Pure, platform-neutral visible-rows arithmetic for the classic playlist
// (PLEDIT) track list. It needs NO graphics framework: given a track count, a
// requested scroll position, the pixel height of the interior, and the per-row
// pixel height, it answers "which rows are visible, and clamped so you can never
// scroll past the ends".
//
// The harness shell draws PLATFORM text (CoreText) for the visible rows; this
// helper only tells it WHICH rows to draw and how far to scroll, so the scroll
// math has one tested home instead of living loose in the AppKit shell. The
// model mirrors the classic playlist: rows are a fixed height, the list scrolls
// by whole rows, and the last visible row may be only partially on-screen (it is
// still reported as visible so the shell clips it to the interior).

public enum PlaylistLayout {

    // MARK: - Visible-row layout

    /// The result of laying out the visible window over the track list.
    public struct Visible: Equatable {
        /// Index of the first visible row (inclusive). `0` when fewer tracks than
        /// fit, or when scrolled to the top.
        public let firstVisible: Int
        /// Index one past the last visible row (exclusive), so the visible range
        /// is the half-open `firstVisible..<lastVisible`. Equal to `firstVisible`
        /// only for an empty list (no rows to draw).
        public let lastVisible: Int
        /// The clamped scroll position actually used, in WHOLE rows from the top.
        /// Equal to `firstVisible`; surfaced explicitly so the shell can store the
        /// clamped value back (e.g. after a wheel event scrolled past the end).
        public let scrollRow: Int

        public init(firstVisible: Int, lastVisible: Int, scrollRow: Int) {
            self.firstVisible = firstVisible
            self.lastVisible = lastVisible
            self.scrollRow = scrollRow
        }

        /// The number of rows in the visible range (>= 0).
        public var count: Int { lastVisible - firstVisible }
    }

    /// Lay out the visible rows of a track list.
    ///
    /// - Parameters:
    ///   - trackCount: total rows in the list (clamped at 0; negative is treated
    ///     as empty).
    ///   - scrollRow: requested scroll position in WHOLE rows from the top. It is
    ///     clamped into `0...maxScroll` so the list can never scroll past either
    ///     end (a negative request clamps to 0; a too-large request clamps so the
    ///     last row sits at the bottom of the interior).
    ///   - interiorHeight: pixel height of the interior the list draws into. A
    ///     non-positive height yields no visible rows.
    ///   - rowHeight: pixel height of one row. A non-positive row height yields no
    ///     visible rows (avoids divide-by-zero / infinite layout).
    ///
    /// The number of rows that FIT is `interiorHeight / rowHeight` rounded UP, so
    /// a partially visible last row still counts as visible (the shell clips it to
    /// the interior). The visible range is then `scrollRow ..< min(scrollRow +
    /// fit, trackCount)`.
    public static func visibleRows(
        trackCount: Int,
        scrollRow: Int,
        interiorHeight: Int,
        rowHeight: Int
    ) -> Visible {
        let tracks = max(0, trackCount)

        // Degenerate geometry -> nothing is visible, but still report a clamped
        // scroll of 0 so the shell stores a sane value.
        guard interiorHeight > 0, rowHeight > 0, tracks > 0 else {
            return Visible(firstVisible: 0, lastVisible: 0, scrollRow: 0)
        }

        let fit = rowsThatFit(interiorHeight: interiorHeight, rowHeight: rowHeight)
        let maxScroll = maxScrollRow(trackCount: tracks, interiorHeight: interiorHeight, rowHeight: rowHeight)
        let clamped = min(max(scrollRow, 0), maxScroll)
        let last = min(clamped + fit, tracks)
        return Visible(firstVisible: clamped, lastVisible: last, scrollRow: clamped)
    }

    // MARK: - Row hit (interior y -> absolute track index)

    /// The absolute track index under a point INSIDE the interior, or `nil` when
    /// the point is not on a filled row.
    ///
    /// - Parameters:
    ///   - atInteriorY: y measured from the interior TOP (0 at the top edge,
    ///     increasing DOWNWARD), in the same pixel space rows are laid out in.
    ///     A negative y (above the top edge) is `nil`.
    ///   - trackCount: total rows in the list (clamped at 0; negative is empty).
    ///   - scrollRow: requested scroll position in WHOLE rows; clamped EXACTLY as
    ///     `visibleRows` clamps it, so a row hit lines up with what is drawn.
    ///   - interiorHeight: pixel height of the interior. Non-positive -> `nil`.
    ///   - rowHeight: pixel height of one row. Non-positive -> `nil`.
    ///
    /// The index is `clampedScroll + atInteriorY / rowHeight`. It returns `nil`
    /// when `atInteriorY` is outside the interior (`< 0` or `>= interiorHeight`,
    /// half-open) or when the computed index is past the last visible track (the
    /// empty gap below the last row when fewer tracks than fit, or any row index
    /// `>= trackCount`). A y inside a PARTIALLY visible last row still hits it, so
    /// this stays consistent with `visibleRows` reporting that partial row.
    public static func row(
        atInteriorY: Int,
        trackCount: Int,
        scrollRow: Int,
        interiorHeight: Int,
        rowHeight: Int
    ) -> Int? {
        let tracks = max(0, trackCount)
        // Degenerate geometry / empty list / a y outside the interior is not a row.
        guard interiorHeight > 0, rowHeight > 0, tracks > 0 else { return nil }
        guard atInteriorY >= 0, atInteriorY < interiorHeight else { return nil }

        // Use the SAME visible-row layout the shell draws with, so the clamp and
        // the visible window line up exactly (no drift between draw and hit-test).
        let layout = visibleRows(
            trackCount: tracks,
            scrollRow: scrollRow,
            interiorHeight: interiorHeight,
            rowHeight: rowHeight
        )
        guard layout.count > 0 else { return nil }

        let index = layout.firstVisible + atInteriorY / rowHeight
        // Past the last visible track (empty gap below a short list, or any index
        // at/after the visible window's end) is not a row.
        guard index < layout.lastVisible else { return nil }
        return index
    }

    /// The number of rows that fit in `interiorHeight` at `rowHeight`, rounding UP
    /// so a partially visible last row still counts. At least 1 when both inputs
    /// are positive (a row that does not fully fit is still drawn and clipped);
    /// 0 for non-positive inputs.
    public static func rowsThatFit(interiorHeight: Int, rowHeight: Int) -> Int {
        guard interiorHeight > 0, rowHeight > 0 else { return 0 }
        return (interiorHeight + rowHeight - 1) / rowHeight
    }

    /// The largest valid `scrollRow`: the scroll position that puts the LAST track
    /// at the bottom of the interior without leaving blank rows below it. Uses the
    /// number of WHOLE rows that fit (floor), so the clamp leaves the list filled
    /// rather than over-scrolled by the partial last row. Returns 0 when all
    /// tracks fit (no scrolling possible) or for degenerate geometry.
    public static func maxScrollRow(
        trackCount: Int,
        interiorHeight: Int,
        rowHeight: Int
    ) -> Int {
        let tracks = max(0, trackCount)
        guard interiorHeight > 0, rowHeight > 0, tracks > 0 else { return 0 }
        // Whole rows that fully fit (floor). The last reachable top row is the one
        // that still leaves `wholeFit` rows of content below-and-including it.
        let wholeFit = interiorHeight / rowHeight
        return max(0, tracks - wholeFit)
    }
}
