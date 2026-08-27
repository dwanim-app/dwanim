import PlayerCore
import SwiftUI

// MARK: - CadencePlaylist

/// The playlist block: a column header (`# / Title / Time / ×`), the scrollable
/// track table, and a footer ("N songs, M minutes · Add files…"), with a drag-over
/// "Add to library" overlay.
///
/// ## Interaction model (preserved from the previous default face)
/// The table is a native `List(selection:)` — the ONLY pure-SwiftUI way to get
/// ⌘/⇧ multi-select (DwanimItUI imports SwiftUI + PlayerCore only, never AppKit).
/// It keeps every capability the old gear menu + disclosure UI used to hold:
/// - single-click selects, ⌘/⇧-click multi-selects (native);
/// - double-click plays (the `contextMenu(…, primaryAction:)` hook — a `TapGesture`
///   would swallow the selection click, so double-click lives on the container);
/// - Delete removes the selection, Return plays the first selected row;
/// - a right-click context menu: **Play / Remove / Select All / Select None** plus
///   the queue-management actions that used to live in the gear menu —
///   **Sort by Title / Sort by Filename / Reverse / Randomize / Clear Queue**.
/// Every edit re-persists via `onPlaylistEdited` (the App wires it to
/// `persistCurrentPlaylist()`; nil in the headless harness).
///
/// The native selection highlight is the system accent (blue) and is not
/// recolourable from pure SwiftUI (confirmed previously); the Cadence selected /
/// hover / now-playing fills below read through when the list is not key-focused.
struct CadencePlaylist: View {

    @Bindable var core: PlayerCore
    let theme: AppearanceTheme
    /// Present the "Add files…" panel (the footer link + context menu). Nil in the
    /// headless harness.
    let onAddFiles: (() -> Void)?
    /// Present the "Add Folder…" panel (context menu). This is the surviving home for
    /// the old gear-menu "Add Folder…" so that capability is not lost with the gear
    /// menu gone. Nil in the headless harness.
    let onAddFolder: (() -> Void)?
    /// Route dropped file URLs into the library (wired to the same session drop
    /// handler the window-level drop uses). Nil in the headless harness — then the
    /// overlay still appears but the drop is a no-op here.
    let onAddURLs: (([URL]) -> Void)?
    /// Re-persist the live queue after an in-UI edit.
    let onPlaylistEdited: (() -> Void)?

    @State private var selection = Set<Int>()
    @State private var hovered: Int?
    @State private var isDropTargeted = false

    /// Grid column widths matching the design (`30px 1fr 60px 26px`).
    private let indexWidth: CGFloat = 30
    private let timeWidth: CGFloat = 60
    private let removeWidth: CGFloat = 26
    private let rowHeight: CGFloat = 30
    private let maxListHeight: CGFloat = 236

    var body: some View {
        VStack(spacing: 0) {
            header
            if !core.playlist.isEmpty {
                list
            }
            footer
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Rectangle().fill(AppearanceTheme.hairline).frame(height: 0.5)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty, let onAddURLs else { return false }
            onAddURLs(files)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                dropOverlay
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: indexWidth, alignment: .center)
            Text("Title").frame(maxWidth: .infinity, alignment: .leading)
            Text("Time").frame(width: timeWidth, alignment: .trailing)
            Color.clear.frame(width: removeWidth)
        }
        .font(.system(size: 11))
        .foregroundStyle(AppearanceTheme.secondary)
        .frame(height: 26)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)
        }
    }

    // MARK: List

    private var list: some View {
        List(selection: $selection) {
            ForEach(Array(core.playlist.enumerated()), id: \.offset) { index, track in
                row(index: index, track: track)
                    .tag(index)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(rowBackground(index: index))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, rowHeight)
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
            Button("Select All") { selection = Set(core.playlist.indices) }
            Button("Select None") { selection.removeAll() }
                .disabled(selection.isEmpty)
            Divider()
            // The old gear-menu "Add" items rehomed here (hidden when their closure is
            // nil, as in the harness) so no capability is lost with the gear menu gone.
            if let onAddFiles {
                Button("Add Songs…", systemImage: "plus") { onAddFiles() }
            }
            if let onAddFolder {
                Button("Add Folder…", systemImage: "folder.badge.plus") { onAddFolder() }
            }
            if onAddFiles != nil || onAddFolder != nil {
                Divider()
            }
            Button("Sort by Title", systemImage: "textformat.abc") {
                core.sortByTitle(); onPlaylistEdited?()
            }
            .disabled(core.playlist.count <= 1)
            Button("Sort by Filename", systemImage: "doc.text") {
                core.sortByFilename(); onPlaylistEdited?()
            }
            .disabled(core.playlist.count <= 1)
            Button("Reverse", systemImage: "arrow.up.arrow.down") {
                core.reverse(); onPlaylistEdited?()
            }
            .disabled(core.playlist.count <= 1)
            Button("Randomize", systemImage: "shuffle") {
                core.randomize(); onPlaylistEdited?()
            }
            .disabled(core.playlist.count <= 1)
            Divider()
            Button("Clear Queue", systemImage: "trash", role: .destructive) {
                core.removeAll(); selection.removeAll(); onPlaylistEdited?()
            }
            .disabled(core.playlist.isEmpty)
        } primaryAction: { items in
            if let first = items.sorted().first { core.select(first) }
        }
        .onDeleteCommand { removeSelected(selection) }
        .onKeyPress(.return) {
            guard let first = selection.sorted().first else { return .ignored }
            core.select(first)
            return .handled
        }
        // Clear the selection on STRUCTURAL changes only (add / remove / reorder),
        // keyed on the track URLs rather than the whole `playlist` value: an async
        // `setDuration` write-back mutates `playlist` in place to fill the Time
        // column, and keying on the full value would wipe the user's selection every
        // time a duration lands while a queue of files resolves. The URL list changes
        // on add/remove/reorder (when the index-based selection genuinely goes stale)
        // but not on a duration fill-in, so the selection now survives the resolve.
        .onChange(of: core.playlist.map(\.url)) { selection.removeAll() }
        .frame(height: listHeight)
    }

    private var listHeight: CGFloat {
        let count = CGFloat(core.playlist.count)
        guard count > 0 else { return 0 }
        return min(count * rowHeight + 8, maxListHeight)
    }

    // MARK: Row

    private func row(index: Int, track: Track) -> some View {
        let parts = Self.rowParts(title: track.title, index: index)
        return HStack(spacing: 0) {
            // Index / now-playing glyph.
            Group {
                if index == core.currentIndex, core.isPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.accent)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(index == core.currentIndex ? theme.accent : AppearanceTheme.tertiary)
                }
            }
            .frame(width: indexWidth, alignment: .center)

            // Title + inline artist.
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(parts.title)
                    .font(.system(size: 13))
                    .foregroundStyle(AppearanceTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let artist = parts.artist {
                    Text(artist)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppearanceTheme.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Time. `TrackTime.format` renders "—" until the async metadata read
            // fills `track.duration` in (nil / non-finite / ≤ 0 → "—").
            Text(TrackTime.format(track.duration))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(AppearanceTheme.secondary)
                .frame(width: timeWidth, alignment: .trailing)

            // Remove.
            RemoveButton {
                core.remove(at: IndexSet(integer: index))
                selection.removeAll()
                onPlaylistEdited?()
            }
            .frame(width: removeWidth)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(index + 1). \(parts.title)"))
        .accessibilityAction { core.select(index) }
    }

    @ViewBuilder
    private func rowBackground(index: Int) -> some View {
        let isSelected = selection.contains(index) || index == core.currentIndex
        let fill: Color = isSelected ? AppearanceTheme.selectedFill
            : (hovered == index ? AppearanceTheme.hoverFill : .clear)
        Rectangle()
            .fill(fill)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppearanceTheme.rowHairline).frame(height: 0.5)
            }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footerLabel)
                .font(.system(size: 11))
                .foregroundStyle(AppearanceTheme.secondary)
            Text("·").foregroundStyle(Color(hex: 0x5f5f64))
            Button {
                onAddFiles?()
            } label: {
                Text("Add files…")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(onAddFiles == nil)
        }
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            Rectangle().fill(AppearanceTheme.hairline).frame(height: 0.5)
        }
    }

    private var footerLabel: String {
        let count = core.playlist.count
        let totalSeconds = core.playlist.reduce(0.0) { $0 + ($1.duration ?? 0) }
        let minutes = Int((totalSeconds / 60).rounded())
        return "\(count) songs, \(minutes) minutes"
    }

    // MARK: Drop overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(rgba: 12, 14, 15, 0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.accent, lineWidth: 2)
            )
            .overlay(
                Text("Add to library")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
            )
            .padding(4)
            .allowsHitTesting(false)
    }

    // MARK: Edits

    private func removeSelected(_ items: Set<Int>) {
        guard !items.isEmpty else { return }
        core.remove(at: IndexSet(items))
        selection.removeAll()
        onPlaylistEdited?()
    }

    // MARK: Title / artist split

    /// The row's display `(title, artist?)`: the `"Track N"` fallback for a blank
    /// stored title stays HERE, then the shared `TrackTitle` seam does the inline
    /// `Artist - Title` split (matching the design's inline-artist element). The core
    /// `Track` carries no artist field, so the artist is a display-only derivation.
    private static func rowParts(title: String?, index: Int) -> (title: String, artist: String?) {
        guard let raw = title, !raw.isEmpty else {
            return ("Track \(index + 1)", nil)
        }
        return TrackTitle.split(raw)
    }
}

// MARK: - RemoveButton

/// The trailing `×` remove affordance for a row: idle grey, brightening on hover.
/// A `Button` (not a tap gesture) so it captures only its own hit area and leaves
/// the `List` row's selection click intact.
private struct RemoveButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(hovering ? Color(hex: 0xe8e8ea) : AppearanceTheme.removeGlyph)
                .frame(width: 26, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text("Remove from queue"))
    }
}
