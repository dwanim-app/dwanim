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
/// element is the gold mark in `EmblemTile`, as imagery only.
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

    public init(core: PlayerCore, model: PlayerViewModel) {
        self._core = Bindable(core)
        self._model = Bindable(model)
    }

    // MARK: - Body

    public var body: some View {
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
        .padding(16)
        .frame(minWidth: 420, maxWidth: .infinity)
        .background {
            // The glass panel: a translucent material in a rounded rect with a
            // subtle white-ish stroke. The colourful backdrop lives behind the
            // hosting view (the harness window) so this material has something
            // to blur.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(DwanimTheme.glassStroke, lineWidth: 1)
                }
        }
        .padding(12)
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
        }
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
