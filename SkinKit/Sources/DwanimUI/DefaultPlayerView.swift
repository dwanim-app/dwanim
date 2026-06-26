import PlayerCore
import SwiftUI

// MARK: - DefaultPlayerView

/// The app's own face when no `.wsz` skin is loaded: a wide, short frosted-glass
/// horizontal "dock-bar" music player.
///
/// Layout (left -> right):
///   [ Dwennimmen emblem tile ] [ title + thin progress + small spectrum ] [ transport ]
///
/// It binds to two observable sources, by design:
/// - `PlayerCore` for transport state (`isPlaying`, `currentTrack`) and actions.
/// - `PlayerViewModel` for the live clock (`progress`) and spectrum `levels`,
///   which `PlayerCore` does not publish as observable properties.
///
/// Text rule: the title slot shows the LIVE track title; with nothing loaded it
/// shows a quiet "Dwanim". The word "Dwennimmen" never appears — the heritage
/// element is the icon bitmap in `EmblemTile` (the same PNG as the app icon), as
/// imagery only.
///
/// The transport row also carries a right-edge controls column: a chevron that
/// toggles the expandable queue (`PlaylistPanel`, P2-1) and a gear/overflow
/// `Menu` (P2-2) for "Open Audio…" / "Open Skin…" and a queue toggle. The open
/// actions are plumbed in as closures (`onOpenAudio` / `onOpenSkin`) so the app
/// can route them to the same `AudioSession` calls the File menu uses without
/// `DwanimUI` ever importing AppKit.
///
/// Transport calls `PlayerCore` directly (`previous()` / `togglePlayPause()` /
/// `next()`). It intentionally does NOT route through `PlayerControl.apply`:
/// that lives in the `PlayerControl` target which depends on `SkinRender` (the
/// `.wsz` control enum), and pulling it in would drag `SkinRender`/`SkinKit`
/// into `DwanimUI`. The constraint here is that `DwanimUI` imports SwiftUI +
/// `PlayerCore` only, and these direct calls have identical semantics to the
/// `.previous` / `.next` cases of `PlayerControl.apply`.
public struct DefaultPlayerView: View {

    /// Transport state + actions. `@Bindable` so SwiftUI observes `isPlaying` /
    /// `currentTrack` changes and re-renders the play/pause glyph and title.
    @Bindable private var core: PlayerCore
    /// Live clock + spectrum levels, driven by the host's main-thread timer/tap.
    @Bindable private var model: PlayerViewModel

    /// App-layer action: present the "Open Audio…" panel. Plumbed as a closure so
    /// `DwanimUI` never imports AppKit — the app wires this to the SAME call the
    /// File ▸ Open Audio… menu uses (`session.presentOpenPanel()`).
    private let onOpenAudio: (() -> Void)?
    /// App-layer action: present the "Open Skin…" panel. Same one-source-of-truth
    /// rule as `onOpenAudio` (`session.presentOpenSkinPanel()`).
    private let onOpenSkin: (() -> Void)?

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

    /// Whether the queue list is shown below the now-playing row. Collapsed by
    /// default so the bar opens as the compact dock-bar; expanding it grows the
    /// window taller (the scene does not hard-cap height).
    @State private var isQueueExpanded = false

    public init(
        core: PlayerCore,
        model: PlayerViewModel,
        onOpenAudio: (() -> Void)? = nil,
        onOpenSkin: (() -> Void)? = nil
    ) {
        self._core = Bindable(core)
        self._model = Bindable(model)
        self.onOpenAudio = onOpenAudio
        self.onOpenSkin = onOpenSkin
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

                    ProgressTrack(progress: model.progress)

                    SpectrumBars(levels: model.levels)
                        .frame(height: 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                transport
            }

            // The expandable queue (P2-1): only when toggled open AND non-empty.
            // It fills the formerly-empty space and lets the window grow taller.
            if isQueueExpanded && !core.playlist.isEmpty {
                Divider()
                    .overlay(DwanimTheme.glassStroke)
                    .padding(.top, 12)

                PlaylistPanel(core: core)
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
                        .stroke(DwanimTheme.glassStroke, lineWidth: 1)
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

    /// The unobtrusive right-edge column: the queue disclosure chevron above the
    /// gear/overflow menu. Sits at the right of the transport row so the
    /// transport buttons stay centred-left as before.
    private var controlsColumn: some View {
        VStack(spacing: 8) {
            queueDisclosure
            gearMenu
        }
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
    /// "Open Skin…" and a queue toggle that mirrors the disclosure. Each open
    /// item runs the app-supplied closure (the SAME call as the File menu); when
    /// no closure is wired (e.g. the headless harness) the item is hidden so it
    /// is never a dead control.
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

    /// The live track title, or the quiet app name "Dwanim" when nothing is
    /// loaded (or the track carries no title). NEVER the word "Dwennimmen".
    private var titleText: String {
        let title = core.currentTrack?.title
        if let title, !title.isEmpty {
            return title
        }
        return "Dwanim"
    }
}
