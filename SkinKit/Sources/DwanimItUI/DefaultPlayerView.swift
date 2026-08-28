import PlayerCore
import SwiftUI

// MARK: - DefaultPlayerView

/// The app's own face when no `.wsz` skin is loaded: a high-fidelity recreation of
/// the "Cadence" deck — a 560-wide frosted-glass column that stacks a title bar, a
/// hero block (spectrum visualiser + now-playing + seek + transport), the playlist
/// table, and an always-visible 10-band equaliser section (greyed when EQ is off).
///
/// ## Theme layer
/// Every colour reads from the current `AppearanceTheme` (via the injected
/// `AppearanceStore`), so switching the theme in the title-bar Appearance popover
/// retints the whole deck instantly. This is a SEPARATE vocabulary from
/// `DwanimItTheme` (the app icon's gold), which is left untouched.
///
/// ## Bindings (unchanged from before)
/// - `PlayerCore` — transport state + actions, the playlist, volume, shuffle/repeat,
///   and the equaliser (`core.equalizer`).
/// - `PlayerViewModel` — the live clock (`currentTime` / `duration`) and spectrum
///   `levels`, which `PlayerCore` does not publish observably.
///
/// ## AppKit-free
/// `DwanimItUI` still imports only SwiftUI + `PlayerCore`. App-layer file panels and
/// drop routing stay behind closures (`onAddFiles` / `onAddFolder` / `onPlaylistEdited`
/// / `onAddURLs`). Menu-bar commands (Open Audio ⌘O, Open Skin ⌘⇧O, Open/Save
/// Playlist) remain the App layer's job — the previous in-view gear menu is gone, and
/// its queue-management actions now live in the playlist's right-click context menu.
public struct DefaultPlayerView: View {

    @Bindable private var core: PlayerCore
    @Bindable private var model: PlayerViewModel
    private var appearance: AppearanceStore

    /// APPEND picked audio files to the queue (the footer "Add files…" + the
    /// playlist context menu). Nil in the headless harness.
    private let onAddFiles: (() -> Void)?
    /// APPEND a folder's audio (playlist context menu). Nil in the headless harness.
    private let onAddFolder: (() -> Void)?
    /// Re-persist the live queue after an in-UI edit.
    private let onPlaylistEdited: (() -> Void)?
    /// Route dropped file URLs into the library (the playlist drop overlay). Nil in
    /// the headless harness.
    private let onAddURLs: (([URL]) -> Void)?
    /// App-tier "Open Theme…" action for the Appearance popover: present the
    /// colour-theme file panel + return its text. Nil in the headless harness (the
    /// popover's Open Theme… row is then disabled). Forwarded to
    /// `CadenceAppearanceButton`.
    private let onOpenAppearanceFile: OpenAppearanceFileAction?
    /// App-tier "Open Skin…" action for the Appearance popover: open the classic
    /// `.wsz` skin picker (File ▸ Open Skin… ⌘⇧O). Fire-and-forget — loading a `.wsz`
    /// swaps the whole face. A no-op `{}` in the headless harness. Forwarded to
    /// `CadenceAppearanceButton`.
    private let onOpenSkin: () -> Void

    /// The fixed panel width (design: 560 px). A definite width keeps the scene's
    /// fitting size compact so the window hugs the panel (see `DwanimItPlayerScene`).
    static let compactWidth: CGFloat = 560
    /// The panel corner radius (design: 11 px).
    static let panelCornerRadius: CGFloat = 11
    /// The hero block's vertical column gap (design §1b: 12 px between the visualiser,
    /// now-playing, seek, and transport rows). One constant so every hero gap matches.
    static let heroColumnGap: CGFloat = 12

    public init(
        core: PlayerCore,
        model: PlayerViewModel,
        appearance: AppearanceStore,
        onAddFiles: (() -> Void)? = nil,
        onAddFolder: (() -> Void)? = nil,
        onPlaylistEdited: (() -> Void)? = nil,
        onAddURLs: (([URL]) -> Void)? = nil,
        onOpenAppearanceFile: OpenAppearanceFileAction? = nil,
        onOpenSkin: @escaping () -> Void = {}
    ) {
        self._core = Bindable(core)
        self._model = Bindable(model)
        self.appearance = appearance
        self.onAddFiles = onAddFiles
        self.onAddFolder = onAddFolder
        self.onPlaylistEdited = onPlaylistEdited
        self.onAddURLs = onAddURLs
        self.onOpenAppearanceFile = onOpenAppearanceFile
        self.onOpenSkin = onOpenSkin
    }

    private var theme: AppearanceTheme { appearance.current }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            hero
            CadencePlaylist(
                core: core,
                theme: theme,
                onAddFiles: onAddFiles,
                onAddFolder: onAddFolder,
                onAddURLs: onAddURLs,
                onPlaylistEdited: onPlaylistEdited
            )
            // EQ section is ALWAYS visible (no collapse). When EQ is off it greys
            // out in place (see CadenceEQDrawer); the transport EQ button and the
            // drawer's On checkbox both toggle `core.equalizer.enabled`.
            CadenceEQDrawer(core: core, theme: theme)
        }
        .frame(width: Self.compactWidth)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(theme.panel)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                .stroke(AppearanceTheme.windowEdge, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
        // M3 — a gentle colour crossfade when the theme changes (keyed on the theme
        // name, so it fires only on a real swap, never on the per-frame visualiser
        // updates). The prototype applies skins instantly; this stays subtle enough to
        // still read as immediate.
        .animation(CadenceMotion.themeCrossfade, value: theme.name)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        // No centered app-name / track-title label: the hero now-playing row already
        // carries the live title/artist, so the title bar keeps only the native window
        // controls (left, drawn by macOS) and the Appearance button (right). The centre
        // is an intentional empty spacer, preserving the row height and left/right
        // balance.
        HStack {
            Spacer()
            CadenceAppearanceButton(
                store: appearance,
                onOpenAppearanceFile: onOpenAppearanceFile,
                openSkin: onOpenSkin
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppearanceTheme.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Self.heroColumnGap) {
            CadenceVisualizer(theme: theme, levels: model.levels, playing: core.isPlaying)

            VStack(spacing: Self.heroColumnGap) {
                nowPlaying
                CadenceSeekBar(
                    theme: theme,
                    currentTime: model.currentTime,
                    duration: model.duration,
                    onSeek: { core.seek(to: $0) }
                )
            }

            CadenceTransport(core: core, theme: theme)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var nowPlaying: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(nowTitle)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.25)
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if let artist = nowArtist {
                Text(artist)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppearanceTheme.nowPlayingArtist)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // E3 — the artist lays out at its (short) ideal width first, so a
                    // very long title truncates and yields the row instead of starving
                    // the artist to nothing.
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The now-playing `(title, artist)` pair, split via the shared `TrackTitle` seam
    /// (the same split the playlist rows use). The quiet "dwanim it" fallback for an
    /// empty queue stays HERE at the call site — only the `Artist - Title` split logic
    /// is shared; `Track` carries no artist field, so the artist is display-only.
    private var nowParts: (title: String, artist: String?) {
        guard let raw = core.currentTrack?.title, !raw.isEmpty else { return ("dwanim it", nil) }
        return TrackTitle.split(raw)
    }

    /// The live now-playing title (the quiet "dwanim it" when nothing is loaded).
    private var nowTitle: String { nowParts.title }

    /// The now-playing artist half (nil unless the title follows `Artist - Title`).
    private var nowArtist: String? { nowParts.artist }
}
