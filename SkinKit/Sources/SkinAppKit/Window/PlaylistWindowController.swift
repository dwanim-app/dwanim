import AppKit
import Foundation
import Observation
import PlayerControl
import PlayerCore
import SkinKit
import SkinRender

// The playlist window controller (one primary type per file, §12): it owns the
// view, the core, the scroll position, the selected row, and teardown, and turns
// view-space mouse events into pure-helper row hits + PlayerCore actions.
//
// Lifted from the SkinHarness executable into the reusable SkinAppKit tier (no
// logic change) so BOTH the dev harness AND the real app target can host it. The
// CLI mode entry (arg parsing + skin/audio load + the process-lifetime hold)
// stays in the harness, which now CONSTRUCTS this controller via
// `showPlaylistWindow`.

// MARK: - Controller

/// Owns the playlist window: the view, the core, the scroll position, the
/// selected row, and teardown. The list is static (no playback timer needed for
/// the list view); scroll and click events drive a redraw.
///
/// Interaction:
///   * SINGLE click in the interior SELECTS that row — a plain click REPLACES the
///     selection with that row, a cmd-click TOGGLES the row in/out of the
///     multi-selection (`selectedRows`, distinct from the now-playing
///     `core.currentIndex`); every selected row is highlighted with the skin's
///     `selectedBackground`.
///   * DOUBLE click PLAYS that track (`core.select`, which sets the current index
///     and plays it) — it becomes the now-playing row, drawn in `currentText`.
///   * The BOTTOM BAR's baked buttons are live (hit rects from the pure
///     `PlaylistBarLayout`): ADD / REM / SEL / MISC / LIST OPTS pop up a native
///     menu anchored at the button; the mini transport routes previous / play /
///     pause / stop / next through `PlayerControl` (the main window's mapping)
///     and eject to the host's add-files hook.
///   * Wheel scroll accumulates the fractional `scrollingDeltaY` into a residual
///     and emits a whole-row step only when it crosses one `rowHeight`, so a
///     trackpad / momentum stream does not over-scroll. The step is clamped by the
///     pure `PlaylistLayout.visibleRows`.
///   * A click on the title-bar CLOSE button closes just this window; the rest
///     of the title bar is the window-drag band (the window is borderless).
///   * Any other click outside the interior / on chrome is a no-op.
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
public final class PlaylistWindowController: SkinWindowController {
    private let core: PlayerCore
    private weak var view: PlaylistContentView?
    /// The skin, kept so a drag-resize can RE-COMPOSE the frame at the new size.
    private let skin: Skin
    /// PRESENTATION scale: points per skin pixel (possibly fractional — e.g. 1.5).
    /// Used for the view-point <-> skin-point hit-test mapping and the resize
    /// view-size -> skin-size inverse.
    private let scale: Double
    /// INTEGER nearest-neighbor factor the composed bitmap is rendered at, derived
    /// from `scale` by the pure `PresentationScale` (integer scale -> itself;
    /// fractional 1.5 -> the 2x-backing device factor 3).
    private let bitmapScale: Int
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
    /// The rows the user has SELECTED, distinct from the now-playing
    /// `core.currentIndex`. Empty until the user clicks a row. A plain click
    /// replaces the set with the clicked row; cmd-click toggles membership; the
    /// SEL menu drives all/none/invert; the REM menu consumes the set. Pruned
    /// to valid indices whenever the playlist changes (see `observeCore`).
    private var selectedRows: Set<Int> = []

    // MARK: - Host hooks (panels live in the App layer)
    //
    // The bar's file-flavored actions need panels (NSOpenPanel / NSSavePanel)
    // and sandbox bookkeeping, which live in the HOST (the app's AudioSession)
    // — exactly like the main window's eject. Each hook defaults to `nil`
    // (harness mode): its menu item is then disabled, so nothing half-works.

    /// ADD > "Add File(s)…" and the mini-transport EJECT: open the host's
    /// add-files panel (append to the queue).
    public var onAddFiles: (() -> Void)?
    /// ADD > "Add Directory…": open the host's add-folder panel.
    public var onAddFolder: (() -> Void)?
    /// LIST OPTS > "Open List…": open the host's `.m3u` open panel (replaces
    /// the playlist).
    public var onOpenList: (() -> Void)?
    /// LIST OPTS > "Save List…": open the host's `.m3u` save panel.
    public var onSaveList: (() -> Void)?
    /// Fired after any model mutation initiated FROM THIS WINDOW (remove /
    /// crop / clear / sort / reverse / randomize), so the host can re-persist
    /// its playlist bookmarks. `nil` (harness) skips persistence.
    public var onPlaylistEdited: (() -> Void)?

    public init(
        core: PlayerCore,
        skin: Skin,
        scale: Double,
        skinWidth: Int,
        skinHeight: Int,
        terminatesAppOnClose: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        self.core = core
        self.skin = skin
        self.scale = scale
        self.bitmapScale = PresentationScale.bitmapScale(forPresentationScale: scale)
        self.skinWidth = skinWidth
        self.skinHeight = skinHeight
        super.init(terminatesAppOnClose: terminatesAppOnClose, onClose: onClose)
    }

    public func attach(view: PlaylistContentView) {
        self.view = view
        view.tracksProvider = { [weak self] in self?.core.playlist ?? [] }
        view.currentIndexProvider = { [weak self] in self?.core.currentIndex }
        view.selectedIndicesProvider = { [weak self] in self?.selectedRows ?? [] }
        view.scrollRowProvider = { [weak self] in self?.scrollRow ?? 0 }
        view.onScroll = { [weak self] rawDeltaY in self?.scrollBy(rawDeltaY: rawDeltaY) }
        view.routeClicks(
            onSingleClick: { [weak self] x, y, h, modifiers in
                self?.handleSingleClick(viewX: x, viewY: y, viewHeight: h, modifiers: modifiers)
            },
            onDoubleClick: { [weak self] x, y, h in self?.handleDoubleClick(viewX: x, viewY: y, viewHeight: h) }
        )
        // Title-bar drag gate (the window is borderless, so the skin's title bar
        // is the drag handle): a press in the title-bar band that is NOT on the
        // close button moves the window. The pure
        // `PlaylistWindowComposer.hitsTitleBarDragArea` carries the geometry; the
        // LIVE `skinWidth` keeps both the band's right edge and the close
        // carve-out glued to the corner across a resize.
        view.shouldDragWindow = { [weak self] viewX, viewY, viewHeight in
            guard let self else { return false }
            let point = ControlHitTest.skinPoint(
                viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: self.scale
            )
            return PlaylistWindowComposer.hitsTitleBarDragArea(
                skinX: point.x, skinY: point.y, canvasWidth: self.skinWidth
            )
        }
        // Follow the live core: redraw when core.currentIndex OR core.playlist
        // changes so the highlight moves on an AUTOMATIC advance and the list
        // follows edits made anywhere (the host's add-files panel, another
        // window) — not only on a click here.
        observeCore()
    }

    /// Redraw the list whenever the now-playing track OR the playlist itself
    /// changes, so the highlighted row follows an AUTOMATIC advance (end-of-track
    /// auto-advance, or next/previous pressed on the MAIN window) and the rows
    /// follow playlist edits (append from the host's add panel, remove/sort from
    /// this window's menus). The list owns no redraw timer, so without this it
    /// would go stale until the user scrolls/clicks. A playlist change also
    /// RE-CLAMPS the scroll (a shrunken list must not strand blank rows) and
    /// PRUNES the selection to valid indices. Uses `@Observable` tracking
    /// (one-shot; re-armed after each change) and self-cancels when the
    /// controller deallocs — the `weak self` simply stops re-arming.
    private func observeCore() {
        withObservationTracking {
            _ = core.currentIndex
            _ = core.playlist
        } onChange: { [weak self] in
            // onChange is delivered synchronously as the value is about to change;
            // hop to the main actor so we read the SETTLED state (at draw time),
            // touch AppKit safely, and re-arm tracking. Re-capture `self` weakly in
            // the hop so it is not a cross-closure captured var (Swift-6 clean).
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.selectedRows = self.selectedRows.filter(self.core.playlist.indices.contains)
                    self.applyScroll(rowDelta: 0)
                    self.view?.needsDisplay = true
                    self.observeCore()
                }
            }
        }
    }

    // MARK: - Interior height (for the layout helpers)

    /// The interior pixel height, re-derived from the composed-frame size — the
    /// single geometry source the drawing also uses, so hit-test and draw never
    /// drift.
    private var interiorHeight: Int {
        PlaylistWindowComposer.interiorRect(width: skinWidth, height: skinHeight, skin: skin).h
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
        let interior = PlaylistWindowComposer.interiorRect(width: skinWidth, height: skinHeight, skin: self.skin)
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

    /// Single click: the title-bar CLOSE button closes just this window (the
    /// window is borderless — the skin's baked close glyph is the close
    /// affordance; `window.close()` routes through `windowWillClose` → `onClose`,
    /// the same path as a programmatic host close). Next, the BOTTOM BAR's baked
    /// buttons (menus + mini transport) win over row hit-testing. Otherwise
    /// select the clicked row (no playback change): a plain click REPLACES the
    /// selection, a cmd-click TOGGLES that row. A click that resolves to nothing
    /// (chrome / gap below the list) is a no-op.
    private func handleSingleClick(
        viewX: Double, viewY: Double, viewHeight: Double, modifiers: ClickModifiers
    ) {
        let point = ControlHitTest.skinPoint(
            viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
        )
        if PlaylistWindowComposer.hitsCloseButton(
            skinX: point.x, skinY: point.y, canvasWidth: skinWidth
        ) {
            view?.window?.close()
            return
        }
        if let control = PlaylistBarLayout.control(
            atX: point.x, y: point.y, canvasWidth: skinWidth, canvasHeight: skinHeight
        ) {
            handleBarControl(control)
            return
        }
        guard let row = rowAtViewPoint(viewX: viewX, viewY: viewY, viewHeight: viewHeight) else {
            return
        }
        if modifiers.command {
            // Cmd-click: toggle the row in/out of the multi-selection.
            selectedRows.formSymmetricDifference([row])
        } else {
            guard selectedRows != [row] else { return }
            selectedRows = [row]
        }
        view?.needsDisplay = true
    }

    /// Double click: play the clicked row. `core.select` sets the current index and
    /// starts that track, so it becomes the now-playing row; we also mark it
    /// selected so the highlight and the now-playing color agree. A bar button is
    /// re-dispatched as another single activation FIRST (so rapidly clicking a
    /// mini-transport button — e.g. next-next — fires once per press instead of
    /// losing the second). A click resolving to no row is a no-op.
    private func handleDoubleClick(viewX: Double, viewY: Double, viewHeight: Double) {
        let point = ControlHitTest.skinPoint(
            viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
        )
        if let control = PlaylistBarLayout.control(
            atX: point.x, y: point.y, canvasWidth: skinWidth, canvasHeight: skinHeight
        ) {
            handleBarControl(control)
            return
        }
        guard let row = rowAtViewPoint(viewX: viewX, viewY: viewY, viewHeight: viewHeight) else {
            return
        }
        selectedRows = [row]
        core.select(row)
        view?.needsDisplay = true
    }

    // MARK: - Bottom bar (menus + mini transport)

    /// Route a hit bar control: menu buttons pop up their native menu anchored
    /// at the button; the mini transport fires the matching transport action
    /// through `PlayerControl.apply` — the SAME control→core mapping the main
    /// window's transport uses (so mini-stop is the classic stop: pause + seek
    /// to 0) — and eject opens the host's add-files panel.
    private func handleBarControl(_ control: PlaylistBarLayout.Control) {
        switch control {
        case .addMenu:
            popUpMenu(makeAddMenu(), at: control)
        case .removeMenu:
            popUpMenu(makeRemoveMenu(), at: control)
        case .selectionMenu:
            popUpMenu(makeSelectionMenu(), at: control)
        case .miscMenu:
            popUpMenu(makeMiscMenu(), at: control)
        case .listMenu:
            popUpMenu(makeListMenu(), at: control)
        case .miniPrevious:
            PlayerControl.apply(.previous, to: core)
        case .miniPlay:
            PlayerControl.apply(.play, to: core)
        case .miniPause:
            PlayerControl.apply(.pause, to: core)
        case .miniStop:
            PlayerControl.apply(.stop, to: core)
        case .miniNext:
            PlayerControl.apply(.next, to: core)
        case .miniEject:
            onAddFiles?()
        }
    }

    /// Pop up `menu` anchored at `control`'s hit rect: the rect's TOP-left is
    /// mapped skin→view via the same forward map the drawing uses
    /// (`ControlHitTest.viewPoint`, at the live scale/size), so the menu opens
    /// at the button across any resize. AppKit opens downward and auto-flips
    /// upward near the screen bottom — where the playlist bar always is — which
    /// reproduces the classic pop-up-above feel. `popUp` is synchronous (it runs
    /// its own tracking loop until dismissal); no pressed state is latched here,
    /// so the swallowed mouse-up is harmless.
    private func popUpMenu(_ menu: NSMenu, at control: PlaylistBarLayout.Control) {
        guard let view else { return }
        let rect = PlaylistBarLayout.rect(
            for: control, canvasWidth: skinWidth, canvasHeight: skinHeight
        )
        let anchor = ControlHitTest.viewPoint(
            skinX: rect.x, skinY: rect.y,
            viewHeight: Double(view.bounds.height), scale: scale
        )
        menu.popUp(positioning: nil, at: NSPoint(x: anchor.x, y: anchor.y), in: view)
    }

    // MARK: - Menu construction
    //
    // Native NSMenus for the five bar buttons, rebuilt fresh on each pop-up so
    // the enabled states reflect the LIVE selection / playlist / host hooks.
    // Items are enabled explicitly (`autoenablesItems = false`); an item whose
    // host hook is absent (harness mode) or whose precondition fails (e.g.
    // "Remove Selected" with an empty selection) is disabled, matching the
    // classic behavior. NO brand words appear in any item title (§12).

    /// ADD menu: append files / a directory. "Add URL…" is deliberately OMITTED —
    /// the app sandbox ships with NO network entitlement, so a remote stream
    /// could never play; the classic third item is left out rather than shown dead.
    private func makeAddMenu() -> NSMenu {
        let menu = makeBarMenu()
        addItem(to: menu, title: String(localized: "Add File(s)…", bundle: .module), enabled: onAddFiles != nil) { [weak self] in
            self?.onAddFiles?()
        }
        addItem(to: menu, title: String(localized: "Add Directory…", bundle: .module), enabled: onAddFolder != nil) { [weak self] in
            self?.onAddFolder?()
        }
        return menu
    }

    /// REM menu: remove the selection, crop TO the selection, or clear the list.
    private func makeRemoveMenu() -> NSMenu {
        let menu = makeBarMenu()
        let hasSelection = !selectedRows.isEmpty
        let hasTracks = !core.playlist.isEmpty
        addItem(to: menu, title: String(localized: "Remove Selected", bundle: .module), enabled: hasSelection) { [weak self] in
            self?.removeSelectedRows()
        }
        addItem(to: menu, title: String(localized: "Crop Selected", bundle: .module), enabled: hasSelection) { [weak self] in
            self?.cropToSelectedRows()
        }
        addItem(to: menu, title: String(localized: "Remove All", bundle: .module), enabled: hasTracks) { [weak self] in
            self?.removeAllRows()
        }
        return menu
    }

    /// SEL menu: select all / none / invert.
    private func makeSelectionMenu() -> NSMenu {
        let menu = makeBarMenu()
        let hasTracks = !core.playlist.isEmpty
        addItem(to: menu, title: String(localized: "Select All", bundle: .module), enabled: hasTracks) { [weak self] in
            self?.replaceSelection(with: Set(self?.core.playlist.indices ?? 0..<0))
        }
        addItem(to: menu, title: String(localized: "Select None", bundle: .module), enabled: !selectedRows.isEmpty) { [weak self] in
            self?.replaceSelection(with: [])
        }
        addItem(to: menu, title: String(localized: "Invert Selection", bundle: .module), enabled: hasTracks) { [weak self] in
            guard let self else { return }
            self.replaceSelection(with: Set(self.core.playlist.indices).symmetricDifference(self.selectedRows))
        }
        return menu
    }

    /// MISC menu: sort / reverse / randomize. ("File info…" is DEFERRED — no
    /// metadata pane exists yet.) All reorders keep playback running and the
    /// core recomputes `currentIndex` to follow the playing track.
    private func makeMiscMenu() -> NSMenu {
        let menu = makeBarMenu()
        let canReorder = core.playlist.count > 1
        addItem(to: menu, title: String(localized: "Sort List by Title", bundle: .module), enabled: canReorder) { [weak self] in
            self?.reorder { $0.sortByTitle() }
        }
        addItem(to: menu, title: String(localized: "Sort List by Filename", bundle: .module), enabled: canReorder) { [weak self] in
            self?.reorder { $0.sortByFilename() }
        }
        addItem(to: menu, title: String(localized: "Reverse List", bundle: .module), enabled: canReorder) { [weak self] in
            self?.reorder { $0.reverse() }
        }
        addItem(to: menu, title: String(localized: "Randomize List", bundle: .module), enabled: canReorder) { [weak self] in
            self?.reorder { $0.randomize() }
        }
        return menu
    }

    /// LIST OPTS menu: new (clear) / open / save `.m3u`.
    private func makeListMenu() -> NSMenu {
        let menu = makeBarMenu()
        addItem(to: menu, title: String(localized: "New List", bundle: .module), enabled: !core.playlist.isEmpty) { [weak self] in
            self?.removeAllRows()
        }
        addItem(to: menu, title: String(localized: "Open List…", bundle: .module), enabled: onOpenList != nil) { [weak self] in
            self?.onOpenList?()
        }
        addItem(
            to: menu, title: String(localized: "Save List…", bundle: .module),
            enabled: onSaveList != nil && !core.playlist.isEmpty
        ) { [weak self] in
            self?.onSaveList?()
        }
        return menu
    }

    /// An empty bar menu with explicit enabling (`autoenablesItems = false`, so
    /// `isEnabled` set per item sticks).
    private func makeBarMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    /// Append one closure-backed item: the closure rides in `representedObject`
    /// (boxed — see `MenuAction`) and `performMenuAction` runs it on selection.
    /// The controller (an NSObject via `SkinWindowController`) is the target.
    private func addItem(
        to menu: NSMenu, title: String, enabled: Bool, action: @escaping @MainActor () -> Void
    ) {
        let item = NSMenuItem(
            title: title, action: #selector(performMenuAction(_:)), keyEquivalent: ""
        )
        item.target = self
        item.isEnabled = enabled
        item.representedObject = MenuAction(action)
        menu.addItem(item)
    }

    /// Run the boxed closure carried by a bar-menu item. NSMenu fires this on
    /// the main thread (the menu tracking loop), matching this controller's
    /// `@MainActor` isolation.
    @objc private func performMenuAction(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.run()
    }

    /// A reference box for a `@MainActor` menu-item closure, so it can ride in
    /// `NSMenuItem.representedObject`.
    private final class MenuAction {
        let run: @MainActor () -> Void
        init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    }

    // MARK: - Menu actions (model mutations)

    /// REM > Remove Selected: drop the selected rows from the core (which
    /// shifts/stops the now-playing selection per its edit rules), clear the
    /// consumed selection, then re-clamp scroll + redraw + notify the host.
    private func removeSelectedRows() {
        guard !selectedRows.isEmpty else { return }
        core.remove(at: IndexSet(selectedRows))
        selectedRows = []
        finishEdit()
    }

    /// REM > Crop Selected: keep ONLY the selected rows. The survivors are the
    /// whole new list, so the selection becomes all rows (they remain exactly
    /// the rows the user had selected).
    private func cropToSelectedRows() {
        guard !selectedRows.isEmpty else { return }
        core.crop(to: IndexSet(selectedRows))
        selectedRows = Set(core.playlist.indices)
        finishEdit()
    }

    /// REM > Remove All / LIST OPTS > New List: clear the queue.
    private func removeAllRows() {
        core.removeAll()
        selectedRows = []
        finishEdit()
    }

    /// MISC reorders: run the core mutation, then DROP the selection — the row
    /// indices no longer point at the tracks the user picked (the core follows
    /// only the PLAYING track through a reorder; per-row selection identity is
    /// not tracked). Classic parity for selection-across-reorder is deferred.
    private func reorder(_ mutate: (PlayerCore) -> Void) {
        mutate(core)
        selectedRows = []
        finishEdit()
    }

    /// Shared tail of every model mutation from this window: re-clamp the
    /// scroll to the (possibly shorter) list, redraw, and let the host
    /// re-persist its playlist bookmarks.
    private func finishEdit() {
        applyScroll(rowDelta: 0)
        view?.needsDisplay = true
        onPlaylistEdited?()
    }

    /// Replace the selection (the SEL menu's all / none / invert).
    private func replaceSelection(with rows: Set<Int>) {
        selectedRows = rows
        view?.needsDisplay = true
    }

    // MARK: - Resize (recompose at the new size + re-layout)

    /// On a drag-resize, recompute the skin-space window size from the view's
    /// current (scaled) bounds, recompose the frame at that size, swap it into the
    /// view, and re-clamp the scroll so more/fewer rows show. The pure layers handle
    /// arbitrary sizes; this is the wiring that re-renders the view at its bounds.
    ///
    /// Selection / scroll / now-playing all persist: `selectedRows` and
    /// `core.currentIndex` are untouched, and `scrollRow` is re-clamped via the same
    /// `PlaylistLayout` the draw path uses, so a row pinned at the bottom stays
    /// valid when the interior grows or shrinks.
    public func windowDidResize(_ notification: Notification) {
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
            // Integer nearest-neighbor bitmap; the view's point-sized bounds place
            // it 1:1 in device pixels at a fractional presentation scale.
            scaled = try scaledImage(image, scale: bitmapScale)
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
