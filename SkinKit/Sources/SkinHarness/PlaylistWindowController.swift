import AppKit
import Foundation
import PlayerCore
import SkinAppKit
import SkinKit
import SkinRender

// The playlist window controller (one primary type per file, §12): it owns the
// view, the core, the scroll position, the selected row, and teardown, and turns
// view-space mouse events into pure-helper row hits + PlayerCore actions. Split
// out of `PlaylistView.swift`.

// MARK: - Controller

/// Owns the playlist window: the view, the core, the scroll position, the
/// selected row, and teardown. The list is static (no playback timer needed for
/// the list view); scroll and click events drive a redraw.
///
/// Interaction:
///   * SINGLE click in the interior SELECTS that row (`selectedRow`, distinct from
///     the now-playing `core.currentIndex`); the row is highlighted with the
///     skin's `selectedBackground`.
///   * DOUBLE click PLAYS that track (`core.select`, which sets the current index
///     and plays it) — it becomes the now-playing row, drawn in `currentText`.
///   * Wheel scroll accumulates the fractional `scrollingDeltaY` into a residual
///     and emits a whole-row step only when it crosses one `rowHeight`, so a
///     trackpad / momentum stream does not over-scroll. The step is clamped by the
///     pure `PlaylistLayout.visibleRows`.
///   * A click outside the interior / on chrome is a no-op.
///
/// All state changes happen on the main thread (this is `@MainActor`) and trigger
/// a redraw.
///
/// It sits on `SkinAppKit.SkinWindowController` for the shared NSWindowDelegate +
/// NSApplicationDelegate teardown pair. The playlist window owns no animation
/// timer or audio tap, so it inherits the base's default no-op `tearDown()` —
/// matching its former `windowWillClose` that called only `NSApp.terminate`. It
/// adds `windowDidResize` (its own unique drag-resize/recompose path).
@MainActor
final class PlaylistWindowController: SkinWindowController {
    private let core: PlayerCore
    private weak var view: PlaylistContentView?
    /// The skin, kept so a drag-resize can RE-COMPOSE the frame at the new size.
    private let skin: Skin
    private let scale: Int
    /// The composed-frame UNSCALED dimensions, so the controller can re-derive the
    /// interior rect (the single geometry source) for click mapping. Mutable: a
    /// drag-resize recomputes them from the view bounds (clamped to the composer
    /// minimum) and recomposes the frame at the new size.
    private var skinWidth: Int
    private var skinHeight: Int

    private var scrollRow = 0
    /// Fractional residual of accumulated wheel deltas (skin-pixel units). When its
    /// magnitude crosses one row height we emit a whole-row scroll step and carry
    /// the remainder, so momentum scrolling advances smoothly by whole rows.
    private var scrollResidual = 0.0
    /// The row the user has SELECTED (single click), distinct from the now-playing
    /// `core.currentIndex`. `nil` until the user clicks a row.
    private var selectedRow: Int?

    init(core: PlayerCore, skin: Skin, scale: Int, skinWidth: Int, skinHeight: Int) {
        self.core = core
        self.skin = skin
        self.scale = scale
        self.skinWidth = skinWidth
        self.skinHeight = skinHeight
        super.init()
    }

    func attach(view: PlaylistContentView) {
        self.view = view
        view.tracksProvider = { [weak self] in self?.core.playlist ?? [] }
        view.currentIndexProvider = { [weak self] in self?.core.currentIndex }
        view.selectedIndexProvider = { [weak self] in self?.selectedRow }
        view.scrollRowProvider = { [weak self] in self?.scrollRow ?? 0 }
        view.onScroll = { [weak self] rawDeltaY in self?.scrollBy(rawDeltaY: rawDeltaY) }
        view.routeClicks(
            onSingleClick: { [weak self] x, y, h in self?.handleSingleClick(viewX: x, viewY: y, viewHeight: h) },
            onDoubleClick: { [weak self] x, y, h in self?.handleDoubleClick(viewX: x, viewY: y, viewHeight: h) }
        )
    }

    // MARK: - Interior height (for the layout helpers)

    /// The interior pixel height, re-derived from the composed-frame size — the
    /// single geometry source the drawing also uses, so hit-test and draw never
    /// drift.
    private var interiorHeight: Int {
        PlaylistWindowComposer.interiorRect(width: skinWidth, height: skinHeight).h
    }

    // MARK: - Scroll (cadence fix)

    /// Accumulate a raw (fractional) wheel delta and emit whole-row steps when the
    /// residual crosses one row height.
    ///
    /// `scrollingDeltaY > 0` is an upward scroll (content moves down, toward the
    /// TOP of the list), which DECREASES the scroll row — so a positive residual
    /// of one row height steps the list up by one row. We carry the remainder so a
    /// long momentum stream advances steadily rather than over-scrolling on each
    /// event the way a "min 1 row per event" rule did (the cadence bug).
    private func scrollBy(rawDeltaY: Double) {
        let rowHeight = Double(PlaylistTextStyle.rowHeight)
        guard rowHeight > 0 else { return }

        scrollResidual += rawDeltaY
        // How many whole rows the accumulated residual now represents (toward the
        // top is positive delta -> negative row delta). `trunc` keeps the sub-row
        // remainder for the next event.
        let wholeRows = (scrollResidual / rowHeight).rounded(.towardZero)
        guard wholeRows != 0 else { return }
        scrollResidual -= wholeRows * rowHeight

        let rowDelta = -Int(wholeRows)
        let moved = applyScroll(rowDelta: rowDelta)
        // If the clamp pinned us at an end (no movement), DROP the accumulated
        // residual. Otherwise a stale residual built up against the end would have
        // to be spent before a direction reversal could move the list — so the
        // first reverse event would feel dead. Zeroing here makes a reversal
        // respond on its very first event.
        if !moved {
            scrollResidual = 0
        }
    }

    /// Apply a whole-row delta, clamped by the pure helper, and redraw if it moved.
    /// Returns whether the clamped scroll position actually changed.
    @discardableResult
    private func applyScroll(rowDelta: Int) -> Bool {
        let layout = PlaylistLayout.visibleRows(
            trackCount: core.playlist.count,
            scrollRow: scrollRow + rowDelta,
            interiorHeight: interiorHeight,
            rowHeight: PlaylistTextStyle.rowHeight
        )
        guard layout.scrollRow != scrollRow else { return false }
        scrollRow = layout.scrollRow
        view?.needsDisplay = true
        return true
    }

    // MARK: - Clicks

    /// Map a view-space click to an absolute track index, or `nil` when the click
    /// is outside the interior / on chrome / in the empty gap below the last track.
    ///
    /// The point travels through the SAME flip/scale the list is drawn with:
    ///   1. `ControlHitTest.skinPoint` undoes the integer scale and flips the
    ///      view's bottom-left origin to the skin's top-left origin.
    ///   2. The interior rect (the geometry source the drawing also uses) gives the
    ///      interior's top-left and bounds; the click must fall inside it
    ///      horizontally, and its y is made interior-relative (`skinY - interior.y`).
    ///   3. The pure `PlaylistLayout.row(atInteriorY:...)` resolves the row,
    ///      clamping the scroll exactly as the draw path does.
    private func rowAtViewPoint(viewX: Double, viewY: Double, viewHeight: Double) -> Int? {
        let skin = ControlHitTest.skinPoint(
            viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
        )
        let interior = PlaylistWindowComposer.interiorRect(width: skinWidth, height: skinHeight)
        guard interior.w > 0, interior.h > 0 else { return nil }

        // Must land inside the interior horizontally (clicks on the side chrome are
        // not rows).
        guard skin.x >= interior.x, skin.x < interior.x + interior.w else { return nil }

        let interiorY = skin.y - interior.y
        return PlaylistLayout.row(
            atInteriorY: interiorY,
            trackCount: core.playlist.count,
            scrollRow: scrollRow,
            interiorHeight: interior.h,
            rowHeight: PlaylistTextStyle.rowHeight
        )
    }

    /// Single click: select the clicked row (no playback change). A click that
    /// resolves to no row (chrome / gap below the list) is a no-op.
    private func handleSingleClick(viewX: Double, viewY: Double, viewHeight: Double) {
        guard let row = rowAtViewPoint(viewX: viewX, viewY: viewY, viewHeight: viewHeight) else {
            return
        }
        guard row != selectedRow else { return }
        selectedRow = row
        view?.needsDisplay = true
    }

    /// Double click: play the clicked row. `core.select` sets the current index and
    /// starts that track, so it becomes the now-playing row; we also mark it
    /// selected so the highlight and the now-playing color agree. A click resolving
    /// to no row is a no-op.
    private func handleDoubleClick(viewX: Double, viewY: Double, viewHeight: Double) {
        guard let row = rowAtViewPoint(viewX: viewX, viewY: viewY, viewHeight: viewHeight) else {
            return
        }
        selectedRow = row
        core.select(row)
        view?.needsDisplay = true
    }

    // MARK: - Resize (recompose at the new size + re-layout)

    /// On a drag-resize, recompute the skin-space window size from the view's
    /// current (scaled) bounds, recompose the frame at that size, swap it into the
    /// view, and re-clamp the scroll so more/fewer rows show. The pure layers handle
    /// arbitrary sizes; this is the wiring that re-renders the view at its bounds.
    ///
    /// Selection / scroll / now-playing all persist: `selectedRow` and
    /// `core.currentIndex` are untouched, and `scrollRow` is re-clamped via the same
    /// `PlaylistLayout` the draw path uses, so a row pinned at the bottom stays
    /// valid when the interior grows or shrinks.
    func windowDidResize(_ notification: Notification) {
        guard let view else { return }
        recomposeForViewSize(view.bounds.size)
    }

    /// Re-derive the skin-space size from a scaled view size, recompose, re-layout.
    /// Skipped when nothing changed (same size) so an idle resize notification does
    /// no work.
    private func recomposeForViewSize(_ viewSize: CGSize) {
        let size = PlaylistWindowComposer.skinSize(
            fromViewWidth: Double(viewSize.width),
            viewHeight: Double(viewSize.height),
            scale: scale
        )
        guard size.width != skinWidth || size.height != skinHeight else { return }

        guard let frame = PlaylistWindowComposer.compose(skin, width: size.width, height: size.height),
              let image = CGImageConversion.makeImage(from: frame) else {
            return
        }
        let scaled: (image: CGImage, width: Int, height: Int)
        do {
            scaled = try scaledImage(image, scale: scale)
        } catch {
            return
        }

        // Compose returns the CLAMPED size; adopt the frame's actual dimensions so
        // hit-testing and the text layout share the new geometry exactly.
        skinWidth = frame.width
        skinHeight = frame.height

        // Re-clamp the scroll to the new interior so a position pinned near the
        // bottom does not strand blank rows after the interior changed height.
        let layout = PlaylistLayout.visibleRows(
            trackCount: core.playlist.count,
            scrollRow: scrollRow,
            interiorHeight: interiorHeight,
            rowHeight: PlaylistTextStyle.rowHeight
        )
        scrollRow = layout.scrollRow

        view?.updateFrame(image: scaled.image, skinWidth: frame.width, skinHeight: frame.height)
    }
}
