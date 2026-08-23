import PlayerCore
import SwiftUI

// MARK: - DefaultPlayerView

/// The app's own face when no `.wsz` skin is loaded: a frosted-glass music player
/// that opens 3-UP — the now-playing dock-bar on top, the graphic EQUALIZER below
/// it, and the PLAYLIST queue last — all visible by default.
///
/// Layout (top -> bottom, single 580-wide glass column):
///   1. now-playing row: [ emblem tile ] [ title + seek bar + spectrum ] [ transport ]
///   2. EQUALIZER (`EqualizerPanel`): ON/OFF + preamp + 10 vertical band sliders
///   3. PLAYLIST (`PlaylistPanel`): the scrollable queue (mounts once non-empty)
///
/// Sections 2 and 3 each have a collapse affordance (a control-column icon plus a
/// gear-menu item) but DEFAULT to shown; collapsing one shrinks the window back via
/// the dynamic-height path (the scene measures its rendered height and the App layer
/// resizes the window).
///
/// It binds to two observable sources, by design:
/// - `PlayerCore` for transport state (`isPlaying`, `currentTrack`) and actions
///   (including `seek(to:)`, which the seek bar drives).
/// - `PlayerViewModel` for the live clock (`currentTime` / `duration`) and
///   spectrum `levels`, which `PlayerCore` does not publish as observable
///   properties.
///
/// The thin gold bar under the title is an interactive `ProgressTrack`: click
/// anywhere to seek, drag the gold playhead to scrub. The live display fraction
/// is mapped from `currentTime / duration` via the pure `SeekMath` helper, and
/// drag-end maps the cursor fraction back to a seek time through the same helper,
/// landing on `core.seek(to:)`. The bar is inert (no knob, no seek) until a
/// seekable track is loaded (`duration` finite and `> 0`).
///
/// Text rule: the title slot shows the LIVE track title; with nothing loaded it
/// shows a quiet "dwanim it". The word "Dwennimmen" never appears — the heritage
/// element is the icon bitmap in `EmblemTile` (the same PNG as the app icon), as
/// imagery only.
///
/// The transport row also carries a right-edge controls column: a chevron that
/// toggles the expandable queue (`PlaylistPanel`, P2-1) and a gear/overflow
/// `Menu` (P2-2) for "Open Audio…" / "Open Skin…" and a queue toggle. The open
/// actions are plumbed in as closures (`onOpenAudio` / `onOpenSkin`) so the app
/// can route them to the same `AudioSession` calls the File menu uses without
/// `DwanimItUI` ever importing AppKit.
///
/// Transport calls `PlayerCore` directly (`previous()` / `togglePlayPause()` /
/// `next()`). It intentionally does NOT route through `PlayerControl.apply`:
/// that lives in the `PlayerControl` target which depends on `SkinRender` (the
/// `.wsz` control enum), and pulling it in would drag `SkinRender`/`SkinKit`
/// into `DwanimItUI`. The constraint here is that `DwanimItUI` imports SwiftUI +
/// `PlayerCore` only, and these direct calls have identical semantics to the
/// `.previous` / `.next` cases of `PlayerControl.apply`.
public struct DefaultPlayerView: View {

    /// Transport state + actions. `@Bindable` so SwiftUI observes `isPlaying` /
    /// `currentTrack` changes and re-renders the play/pause glyph and title.
    @Bindable private var core: PlayerCore
    /// Live clock + spectrum levels, driven by the host's main-thread timer/tap.
    @Bindable private var model: PlayerViewModel

    /// App-layer action: present the "Open Audio…" panel. Plumbed as a closure so
    /// `DwanimItUI` never imports AppKit — the app wires this to the SAME call the
    /// File ▸ Open Audio… menu uses (`session.presentOpenPanel()`).
    private let onOpenAudio: (() -> Void)?
    /// App-layer action: present the "Open Skin…" panel. Same one-source-of-truth
    /// rule as `onOpenAudio` (`session.presentOpenSkinPanel()`).
    private let onOpenSkin: (() -> Void)?

    /// App-layer action: present the "Add Songs…" panel, which APPENDS the picked
    /// audio files to the queue (never replaces). Plumbed as a closure so `DwanimItUI`
    /// stays AppKit-free; the gear menu hides the item when it is nil (the headless
    /// harness), exactly like `onOpenAudio` (`session.presentAddFilesPanel()`).
    private let onAddFiles: (() -> Void)?
    /// App-layer action: present the "Add Folder…" panel, which APPENDS a folder's
    /// audio files to the queue (`session.presentAddFolderPanel()`). Same
    /// nil-hides-the-item rule as `onAddFiles`.
    private let onAddFolder: (() -> Void)?
    /// App-layer hook: RE-PERSIST the live queue after an in-UI edit — a
    /// context-menu Remove in `PlaylistPanel` or the gear "Clear Queue". Wired to
    /// `session.persistCurrentPlaylist()`; nil in the headless harness (edits then
    /// simply don't persist). Forwarded into `PlaylistPanel(core:onPlaylistEdited:)`.
    private let onPlaylistEdited: (() -> Void)?

    /// The definite compact width of the dock-bar panel (excluding the scene's
    /// gradient margin). A fixed width — not a min/ideal/max range — so the
    /// scene's `fittingSize` is compact and the window opens hugging the panel
    /// rather than stretching to a flexible maximum. ~580 reads as a balanced
    /// dock-bar (the progress bar + spectrum are well proportioned).
    static let compactWidth: CGFloat = 580

    /// The glass panel's rounded-rect corner radius. Tuned to sit close to the
    /// macOS hidden-title-bar window's own corner radius (~10–12pt) so that, with
    /// the scene adding ZERO surrounding margin (fix-5), only a hairline of the
    /// gradient backdrop shows in the four corner slivers — the glass + window read
    /// as a single solid rounded window rather than a rounded panel floating inside
    /// a square gradient frame.
    static let panelCornerRadius: CGFloat = 12

    /// Whether the queue list is shown below the now-playing row. EXPANDED by
    /// default (the 3-up default face shows MAIN + EQUALIZER + PLAYLIST at once);
    /// the disclosure chevron / gear item still collapse it, and collapsing
    /// shrinks the window back. The `&& !core.playlist.isEmpty` mount guard means
    /// an empty queue still shows nothing until tracks load.
    @State private var isQueueExpanded = true

    /// Whether the equalizer panel is shown below the now-playing row. EXPANDED by
    /// default so the default face opens 3-up. Unlike the queue it has no
    /// "non-empty" gate — the EQ always exists — so it is visible from launch; the
    /// gear "Hide Equalizer" item (and the EQ disclosure) collapse it, shrinking
    /// the window back via the same dynamic-height path.
    @State private var isEQExpanded = true

    public init(
        core: PlayerCore,
        model: PlayerViewModel,
        onOpenAudio: (() -> Void)? = nil,
        onOpenSkin: (() -> Void)? = nil,
        onAddFiles: (() -> Void)? = nil,
        onAddFolder: (() -> Void)? = nil,
        onPlaylistEdited: (() -> Void)? = nil
    ) {
        self._core = Bindable(core)
        self._model = Bindable(model)
        self.onOpenAudio = onOpenAudio
        self.onOpenSkin = onOpenSkin
        self.onAddFiles = onAddFiles
        self.onAddFolder = onAddFolder
        self.onPlaylistEdited = onPlaylistEdited
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // The collapsed now-playing layout — unchanged from before.
            HStack(spacing: 16) {
                EmblemTile(side: 60)

                VStack(alignment: .leading, spacing: 8) {
                    Text(titleText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    ProgressTrack(
                        fraction: SeekMath.fraction(
                            currentTime: model.currentTime,
                            duration: model.duration
                        ),
                        duration: model.duration,
                        onSeek: { time in core.seek(to: time) }
                    )

                    SpectrumBars(levels: model.levels)
                        .frame(height: 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                transport
            }

            // 3-up section 2: the EQUALIZER, shown by default (no non-empty gate —
            // the EQ always exists). Binds to the SAME `core.equalizer` the classic
            // EQ drives. Sits above the queue: closely tied to the now-playing
            // controls above it, with the (potentially long) queue last.
            if isEQExpanded {
                Divider()
                    .overlay(DwanimItTheme.glassStroke)
                    .padding(.top, 12)

                EqualizerPanel(core: core)
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            // 3-up section 3: the expandable queue (P2-1), now EXPANDED by default
            // (mounts only once non-empty). It fills the lower area and lets the
            // window grow taller.
            if isQueueExpanded && !core.playlist.isEmpty {
                Divider()
                    .overlay(DwanimItTheme.glassStroke)
                    .padding(.top, 12)

                PlaylistPanel(core: core, onPlaylistEdited: onPlaylistEdited)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .padding(16)
        // P2-3 / P2-5 (width cap, redo): pin the bar to a DEFINITE compact width so
        // it opens as a balanced dock-bar instead of stretching wide. A definite
        // width (rather than min/ideal/max) is what makes the scene's `fittingSize`
        // compact: under `.windowResizability(.contentSize)`, a flexible
        // `maxWidth` frame resolves its fitting size to the MAX (the window opened
        // ~780pt wide), whereas a fixed width opens exactly here. At
        // `Self.compactWidth` the progress bar + spectrum read proportioned. Height
        // stays content-driven (the queue grows the window taller, P2-1).
        .frame(width: Self.compactWidth)
        .background {
            // The glass panel: a translucent material in a rounded rect with a
            // subtle white-ish stroke. The colourful backdrop lives behind the
            // hosting view (the harness window) so this material has something
            // to blur. Corner radius `Self.panelCornerRadius` ≈ the macOS window
            // corner so, with ZERO surrounding margin (fix-5), only a hairline of
            // gradient peeks through the four corner slivers — the glass + window
            // read as one solid rounded window, not a panel floating in a frame.
            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                        .stroke(DwanimItTheme.glassStroke, lineWidth: 1)
                }
        }
        // Clip the expanded queue to the panel's rounded-rect so a long list
        // never spills past the glass edge.
        .clipShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
        // fix-5: NO outer padding. The glass panel reaches the window edge so the
        // window hugs the panel with no surrounding gradient strip (the scene adds
        // zero margin). The gradient backdrop fills the whole window behind the
        // glass; it shows only in the rounded-corner slivers.
    }

    // MARK: - Transport row

    private var transport: some View {
        HStack(spacing: 12) {
            TransportButton(
                systemName: "backward.fill",
                isPrimary: false,
                diameter: 40,
                label: "Previous track"
            ) {
                core.previous()
            }

            TransportButton(
                systemName: core.isPlaying ? "pause.fill" : "play.fill",
                isPrimary: true,
                diameter: 52,
                label: core.isPlaying ? "Pause" : "Play"
            ) {
                core.togglePlayPause()
            }

            TransportButton(
                systemName: "forward.fill",
                isPrimary: false,
                diameter: 40,
                label: "Next track"
            ) {
                core.next()
            }

            controlsColumn
        }
    }

    // MARK: - Queue + overflow controls

    /// The unobtrusive right-edge column: the always-visible Add button, then the
    /// EQ / queue disclosure chevrons above the gear/overflow menu. Sits at the
    /// right of the transport row so the transport buttons stay centred-left as
    /// before.
    private var controlsColumn: some View {
        VStack(spacing: 8) {
            addButton
            eqDisclosure
            queueDisclosure
            gearMenu
        }
    }

    /// An always-visible "+" that APPENDS songs to the queue (routes to the same
    /// `onAddFiles` closure as the gear-menu "Add Songs…"). Shown only when that
    /// closure is wired (hidden in the headless harness, like the gear item). This
    /// is the visible affordance to add music even when the queue is EMPTY — the
    /// `PlaylistPanel` unmounts on an empty queue, so without this the first-run
    /// user has no obvious way to add tracks. Deliberately NOT an empty-state panel
    /// (which would fight the compact-empty-window design).
    @ViewBuilder
    private var addButton: some View {
        if onAddFiles != nil {
            Button {
                onAddFiles?()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add songs")
            .accessibilityLabel(Text("Add songs"))
        }
    }

    /// The slider-icon toggle for the equalizer section. Always enabled (the EQ
    /// always exists, unlike the queue which gates on non-empty). Tints gold when
    /// the EQ is open so its state reads at a glance.
    private var eqDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isEQExpanded.toggle()
            }
        } label: {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEQExpanded ? AnyShapeStyle(DwanimItTheme.goldGradient) : AnyShapeStyle(.white.opacity(0.7)))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isEQExpanded ? "Hide equalizer" : "Show equalizer")
        .accessibilityLabel(Text(isEQExpanded ? "Hide equalizer" : "Show equalizer"))
    }

    /// The chevron that toggles the queue list. Disabled (dimmed) when the
    /// playlist is empty — there is nothing to expand. Rotates to point up when
    /// open.
    private var queueDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isQueueExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(isQueueExpanded ? 0 : 180))
                .foregroundStyle(.white.opacity(core.playlist.isEmpty ? 0.25 : 0.7))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(core.playlist.isEmpty)
        .help(isQueueExpanded ? "Hide queue" : "Show queue")
        .accessibilityLabel(Text(isQueueExpanded ? "Hide queue" : "Show queue"))
    }

    /// The gear/overflow menu (P2-2): the discoverable home for "Open Audio…" /
    /// "Open Skin…", the queue-editing actions ("Add Songs…" / "Add Folder…" —
    /// which APPEND — and a destructive "Clear Queue"), the queue-REORDERING group
    /// ("Sort by Title" / "Sort by Filename" / "Reverse" / "Randomize", each
    /// disabled with ≤1 track), and the EQ / queue show-hide toggles that mirror the
    /// disclosures. Each open / add item runs the
    /// app-supplied closure (the SAME call as the File menu); when no closure is
    /// wired (e.g. the headless harness) that item is hidden so it is never a dead
    /// control. "Clear Queue" is always present but disabled on an empty queue.
    private var gearMenu: some View {
        Menu {
            if let onOpenAudio {
                Button("Open Audio…", systemImage: "music.note") { onOpenAudio() }
            }
            if let onOpenSkin {
                Button("Open Skin…", systemImage: "paintbrush") { onOpenSkin() }
            }
            if onOpenAudio != nil || onOpenSkin != nil {
                Divider()
            }
            // Queue edits: "Add Songs…" / "Add Folder…" APPEND to the queue (never
            // replace), and "Clear Queue" empties it. The two Add items are hidden
            // when their closure is nil (the headless harness), exactly like the
            // Open items above; Clear Queue is always present but disabled on an
            // empty queue, and re-persists the (now empty) queue via
            // `onPlaylistEdited`.
            if let onAddFiles {
                Button("Add Songs…", systemImage: "plus") { onAddFiles() }
            }
            if let onAddFolder {
                Button("Add Folder…", systemImage: "folder.badge.plus") { onAddFolder() }
            }
            Button("Clear Queue", systemImage: "trash", role: .destructive) {
                core.removeAll()
                onPlaylistEdited?()
            }
            .disabled(core.playlist.isEmpty)
            Divider()
            // Queue REORDERING: sort / reverse / randomize the live queue in place.
            // Each keeps selection-follows-track + playback untouched (PlayerCore
            // does the reorder) and re-persists via `onPlaylistEdited`, the same
            // pattern as Clear Queue. Disabled with 0 or 1 track — nothing to reorder.
            Button("Sort by Title", systemImage: "textformat.abc") {
                core.sortByTitle()
                onPlaylistEdited?()
            }
            .disabled(core.playlist.count <= 1)
            Button("Sort by Filename", systemImage: "doc.text") {
                core.sortByFilename()
                onPlaylistEdited?()
            }
            .disabled(core.playlist.count <= 1)
            Button("Reverse", systemImage: "arrow.up.arrow.down") {
                core.reverse()
                onPlaylistEdited?()
            }
            .disabled(core.playlist.count <= 1)
            Button("Randomize", systemImage: "shuffle") {
                core.randomize()
                onPlaylistEdited?()
            }
            .disabled(core.playlist.count <= 1)
            Divider()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isEQExpanded.toggle()
                }
            } label: {
                Label(isEQExpanded ? "Hide Equalizer" : "Show Equalizer", systemImage: "slider.vertical.3")
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isQueueExpanded.toggle()
                }
            } label: {
                Label(isQueueExpanded ? "Hide Queue" : "Show Queue", systemImage: "list.bullet")
            }
            .disabled(core.playlist.isEmpty)
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More options")
        .accessibilityLabel(Text("More options"))
    }

    // MARK: - Title

    /// The live track title, or the quiet app name "dwanim it" when nothing is
    /// loaded (or the track carries no title). NEVER the word "Dwennimmen".
    private var titleText: String {
        let title = core.currentTrack?.title
        if let title, !title.isEmpty {
            return title
        }
        return "dwanim it"
    }
}
