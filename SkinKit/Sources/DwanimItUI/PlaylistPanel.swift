import PlayerCore
import SwiftUI

// MARK: - PlaylistPanel

/// The expandable queue list that fills the area below the now-playing row when
/// the disclosure in `DefaultPlayerView` is open. A `List(selection:)` over
/// `core.playlist`, one row per track, with a Finder / Music-style edit model:
///
/// - SINGLE-click SELECTS a row; ⌘-click / ⇧-click extend the selection (the
///   native `List(selection:)` multi-select — we cannot read the modifier keys
///   ourselves here, and must not: `DwanimItUI` imports only SwiftUI + `PlayerCore`,
///   never AppKit, so `List(selection:)` is the ONLY way to get ⌘/⇧ multi-select).
/// - DOUBLE-click PLAYS the row (`core.select(index)`, which selects AND plays,
///   bounds-checked in `PlayerCore`). This is delivered by the `primaryAction:`
///   of `contextMenu(forSelectionType:menu:primaryAction:)` — the macOS-native
///   primary-interaction hook, which fires on a double-click of the selection.
///   Do NOT reach for a `TapGesture(count: 2)` on the row instead: attaching ANY
///   tap gesture to a `List` row — even via `.simultaneousGesture` — intercepts
///   the click that commits `List(selection:)`, so single-click select silently
///   stops working (the binding stays empty, no selection highlight renders, and
///   `.onDeleteCommand` becomes a no-op). Confirmed at runtime; `primaryAction:`
///   does not have that problem.
/// - RIGHT-click shows a context menu with **Remove** (removes the selected
///   row(s)) and **Play** (plays the first of them). SwiftUI auto-selects a
///   right-clicked row that was not already selected, so a plain right-click acts
///   on that one row.
///
/// SELECTION is drawn by the NATIVE `List` highlight, in the standard system BLUE.
/// The panel does NOT paint a selection pill of its own: the native highlight DOES
/// render over the frosted glass, and whenever the list holds keyboard focus it WINS
/// over any `.listRowBackground(…)` beneath it — so a hand-drawn pill only made
/// selection flip between two colours depending on focus (confirmed at runtime).
/// `.tint(…)` on the `List` was tried and does NOT recolour that highlight (also
/// confirmed at runtime — don't re-attempt it); the highlight follows the system /
/// app accent, so the only lever is the app-wide AccentColor asset, which we
/// deliberately do not set. Blue selection is accepted (a backlog item, not a defect).
///
/// The currently-playing row (`index == core.currentIndex`) stays VISUALLY
/// DISTINCT from that: it carries the gold play glyph plus a subtle white backing
/// (the one thing `rowBackground` still draws), which reads clearly against the
/// blue, so a row that is BOTH selected and playing reads as both — blue native
/// selection, white now-playing pill, gold ▶ glyph.
///
/// This adds NO new `PlayerCore` API: `select` / `remove(at:)` / `removeAll`
/// already exist. Edits call the app-supplied `onPlaylistEdited` closure so the
/// live queue is re-persisted (the App wires it to `persistCurrentPlaylist()`);
/// it is nil in the headless harness, where edits simply don't persist.
///
/// `@Bindable` so SwiftUI re-renders the highlight when `currentIndex` changes
/// (e.g. the track advances) and the list when `playlist` changes. The caller
/// (`DefaultPlayerView`) is responsible for only mounting this when the queue is
/// expanded AND non-empty, and for clipping it to the panel's rounded-rect.
struct PlaylistPanel: View {

    @Bindable var core: PlayerCore

    /// App-layer hook: RE-PERSIST the live queue after an in-UI edit (a
    /// context-menu Remove here). Wired to `session.persistCurrentPlaylist()`;
    /// nil in the headless harness (edits then simply don't persist).
    let onPlaylistEdited: (() -> Void)?

    /// The set of SELECTED row indices (row identity = the enumerated offset,
    /// matching the `ForEach`'s `id: \.offset`). Bound to `List(selection:)` so
    /// single-click selects and ⌘/⇧-click multi-selects natively. Cleared after a
    /// removal so no stale indices linger over the renumbered queue.
    @State private var selection = Set<Int>()

    init(core: PlayerCore, onPlaylistEdited: (() -> Void)? = nil) {
        self._core = Bindable(core)
        self.onPlaylistEdited = onPlaylistEdited
    }

    /// Caps how tall the list can grow before it scrolls, so a long queue does
    /// not push the window arbitrarily tall. Short queues stay compact (the list
    /// sizes to its content under this ceiling).
    private let maxListHeight: CGFloat = 220

    /// Height of one queue row, used to give the panel a DEFINITE ideal height so
    /// the window actually GROWS when the queue expands — see `listHeight`.
    ///
    /// The rendered row height is now EXACT BY CONSTRUCTION: `row(index:track:)`
    /// pins its content with `.frame(height: rowHeight)`, so every row is exactly
    /// this tall regardless of its title/padding and `listHeight`'s window-growth
    /// formula is exact — no fragile "content stays under 28pt" invariant. The value
    /// is ALSO fed to `.environment(\.defaultMinListRowHeight, …)` on the `List`
    /// below as a belt-and-suspenders FLOOR (insurance only; the `.frame` already
    /// fixes the height). If you deliberately want taller rows, bump this constant:
    /// the row frame, the floor, and the height math all key off it together.
    private static let rowHeight: CGFloat = 28
    /// Inter-row spacing. A `List` stacks its rows CONTIGUOUSLY (no `LazyVStack`
    /// gap), so this is 0 — kept as a named constant so `listHeight`'s formula
    /// still reads clearly.
    private static let rowSpacing: CGFloat = 0
    /// A small allowance for the `List`'s own top/bottom content inset, so the last
    /// row is never clipped by the definite frame height below the cap. `8` is an
    /// empirical value for that inset (confirmed by runtime eyeballing), not a
    /// derived constant.
    private static let listVerticalPadding: CGFloat = 8

    /// A DEFINITE height for the list: the content's natural height (rows + spacing
    /// + padding), CLAMPED to `maxListHeight`. Part of the fix-5 dynamic-height fix.
    ///
    /// A bare scrolling container has NO intrinsic/ideal height — it is vertically
    /// greedy but resolves to ~0 under the scene's `.fixedSize(vertical: true)`, so
    /// the expanded VStack would NOT get taller and the scene's measured rendered
    /// height (which `DwanimItPlayerScene` reports up to drive the window resize)
    /// would not change. Giving the panel a definite, content-derived height makes
    /// the expanded scene measurably taller, so the window grows when the queue
    /// expands and shrinks back when it collapses; once the content exceeds
    /// `maxListHeight` the height pins at the cap and the `List` scrolls the overflow.
    private var listHeight: CGFloat {
        let count = CGFloat(core.playlist.count)
        guard count > 0 else { return 0 }
        let content = count * Self.rowHeight
            + max(0, count - 1) * Self.rowSpacing
            + Self.listVerticalPadding
        return min(content, maxListHeight)
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(core.playlist.enumerated()), id: \.offset) { index, track in
                row(index: index, track: track)
                    // `.tag(index)` binds this row to the selection set (the same
                    // Int identity as the `id: \.offset`).
                    .tag(index)
            }
        }
        .listStyle(.plain)
        // Hide the List's opaque backing so the frosted-glass panel shows through.
        .scrollContentBackground(.hidden)
        // NOTE: no `.tint(…)` here on purpose. It was tried to recolour the native
        // selection highlight gold and does NOT work (confirmed at runtime — the
        // highlight follows the system / app accent, not a view-level tint). The
        // system-blue selection is accepted; changing it would need the app-wide
        // AccentColor asset, deliberately not done.

        // Belt-and-suspenders FLOOR for the row height. The row content is already
        // pinned to `rowHeight` by `.frame(height:)` in `row(index:track:)` (so
        // `listHeight` is exact); this floor is just insurance against a row ever
        // resolving shorter.
        .environment(\.defaultMinListRowHeight, Self.rowHeight)
        // Finder / Music-style right-click menu over the selection. `items` is the
        // set the click acts on — SwiftUI auto-selects a right-clicked row that was
        // not already selected, so a plain right-click targets that one row.
        //
        // `primaryAction:` is the DOUBLE-CLICK hook (macOS 13+; our floor is 14) and
        // is why no row carries a tap gesture — see `row(index:track:)`. It plays the
        // first (topmost) row of the double-clicked selection, the same semantics as
        // the "Play" item below.
        .contextMenu(forSelectionType: Int.self) { items in
            Button("Play", systemImage: "play.fill") {
                if let first = items.sorted().first { core.select(first) }
            }
            .disabled(items.isEmpty)

            Button("Remove", systemImage: "trash", role: .destructive) {
                removeSelected(items)
            }
            .disabled(items.isEmpty)

            Divider()

            // Select All / None: parity with the classic SEL menu for the
            // multi-select model. "All" selects every current row index; "None"
            // clears (disabled when the selection is already empty).
            Button("Select All") { selection = Set(core.playlist.indices) }
            Button("Select None") { selection.removeAll() }
                .disabled(selection.isEmpty)
        } primaryAction: { items in
            // DOUBLE-click: play the first (topmost) row of the double-clicked set.
            if let first = items.sorted().first { core.select(first) }
        }
        // A: keyboard delete removes the selected row(s) via the SAME path as the
        // context-menu Remove (clears selection + re-persists via `onPlaylistEdited`).
        .onDeleteCommand { removeSelected(selection) }
        // A: Return plays the FIRST selected row from the keyboard. Ignored (so the
        // key falls through) when nothing is selected.
        .onKeyPress(.return) {
            guard let i = selection.sorted().first else { return .ignored }
            core.select(i)
            return .handled
        }
        // C: the selection set is keyed by the enumerated OFFSET, so any change to
        // the queue array — append / remove / and crucially SORT / REVERSE /
        // RANDOMIZE from the gear menu — renumbers the rows and would leave stale
        // indices painting pills over the wrong tracks. Clearing the selection on
        // every `playlist` change keeps the offset-keyed selection honest (`Track`
        // is `Equatable`, so `onChange(of:)` compiles); clearing on a harmless
        // append is acceptable.
        .onChange(of: core.playlist) { selection.removeAll() }
        // DEFINITE height (clamped to the cap) so the window grows with the queue;
        // past the cap the List scrolls the overflow.
        .frame(height: listHeight)
    }

    // MARK: - Row

    /// One queue row: the `PlaylistRow` visual plus its per-row `List` styling.
    /// The row carries NO click gestures of its own: single-click selection is
    /// handled natively by `List(selection:)` and double-click-to-play by the
    /// `primaryAction:` of the `.contextMenu(forSelectionType:)` on the `List`
    /// itself (see `body`). A `TapGesture` here would break the former —
    /// `.simultaneousGesture` does NOT coexist with a `List` row's selection click,
    /// it swallows it (confirmed at runtime), which is why the double-click lives
    /// on the container instead.
    private func row(index: Int, track: Track) -> some View {
        PlaylistRow(
            index: index,
            title: rowTitle(for: track, at: index),
            isCurrent: index == core.currentIndex,
            isSelected: selection.contains(index)
        )
        // B: pin the row content to EXACTLY `rowHeight` so a rendered row is that
        // tall regardless of content, making `listHeight`'s window-growth math exact
        // (the `defaultMinListRowHeight` floor below is then just insurance).
        .frame(height: Self.rowHeight)
        // Hit-test the row's FULL pinned rect (not just the glyph + text ink), so a
        // click anywhere in the row — including the empty run past a short title —
        // lands on the row. Purely a hit-shape declaration: unlike a gesture, it does
        // not consume the click, so `List(selection:)` still commits the selection.
        .contentShape(Rectangle())
        // G: VoiceOver activation. Double-click-to-play is delivered by the List's
        // `contextMenu(…, primaryAction:)` and is invisible to assistive tech, so
        // expose an explicit accessibility action that plays the row (`core.select`
        // selects + plays).
        .accessibilityAction { core.select(index) }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        // Draw the NOW-PLAYING backing only. Selection is the native `List`
        // highlight (system blue, not recolourable from here — see the type
        // comment) — a hand-drawn selection pill here would be covered by that
        // highlight whenever the list has keyboard focus.
        .listRowBackground(rowBackground(index: index))
    }

    /// The NOW-PLAYING backing for a row, drawn as an inset pill so it reads clearly
    /// against the glass. Deliberately says nothing about selection: that is the
    /// native highlight's job. A row that is both selected and playing therefore
    /// shows the blue native selection WITH this white backing and the gold play
    /// glyph in `PlaylistRow` on top, so the two states never conflate.
    @ViewBuilder
    private func rowBackground(index: Int) -> some View {
        if index == core.currentIndex {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.12))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
        } else {
            Color.clear
        }
    }

    // MARK: - Edits

    /// Remove the rows at `items` from the queue, clear the selection (so no stale
    /// index lingers over the renumbered list), and re-persist via `onPlaylistEdited`.
    /// `PlayerCore.remove(at:)` already fixes up `currentIndex` / `loadedIndex`
    /// (shifting the followed track, or stopping + relanding when the current row
    /// itself is removed), so this only has to hand it the index set.
    private func removeSelected(_ items: Set<Int>) {
        guard !items.isEmpty else { return }
        core.remove(at: IndexSet(items))
        selection.removeAll()
        onPlaylistEdited?()
    }

    // MARK: - Row title

    /// The track's title, already set to the file stem by the loader when no tag
    /// title exists. Falls back once more to a 1-based track number so a row is
    /// never blank.
    private func rowTitle(for track: Track, at index: Int) -> String {
        if let title = track.title, !title.isEmpty {
            return title
        }
        return "Track \(index + 1)"
    }
}

// MARK: - PlaylistRow

/// One row's VISUAL: a leading glyph (the gold play mark for the now-playing row,
/// a quiet track-number otherwise) and the title. The row is NO LONGER a button
/// and carries NO trailing play control — single-click selection, double-click
/// play, and right-click Remove are all driven by the enclosing `List` in
/// `PlaylistPanel` (which leaves the native selection highlight in the system blue,
/// draws the now-playing backing, pins the row to `PlaylistPanel.rowHeight`, and
/// threads selection state in for VoiceOver).
private struct PlaylistRow: View {

    let index: Int
    let title: String
    let isCurrent: Bool
    /// Whether this row is in the current selection — surfaced to VoiceOver as the
    /// `.isSelected` trait so assistive tech reads selected rows correctly.
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            leadingGlyph
                .frame(width: 18, alignment: .center)

            Text(title)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular, design: .rounded))
                .foregroundStyle(.white.opacity(isCurrent ? 0.98 : 0.78))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // G: lead the label with the 1-based queue position (the visible track
        // number the combined children otherwise drop), keeping the "Now playing:"
        // prefix for the current row.
        .accessibilityLabel(Text(isCurrent ? "Now playing: \(index + 1). \(title)" : "\(index + 1). \(title)"))
        // G: reflect selection to VoiceOver.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if isCurrent {
            Image(systemName: "play.fill")
                .font(.system(size: 11))
                .foregroundStyle(DwanimItTheme.goldGradient)
        } else {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
