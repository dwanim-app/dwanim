import PlayerCore
import SwiftUI

// MARK: - CadenceTransport

/// The hero transport row: three left-aligned toggles (Shuffle / Repeat / EQ), the
/// centred playback cluster (◀◀ / play-pause / ■ / ▶▶), and the right-aligned
/// speaker glyph + volume slider.
///
/// Wiring to `PlayerCore`:
/// - Shuffle → `core.isShuffle` (bool toggle).
/// - Repeat → a 2-state toggle on `core.repeatMode`: off ↔ `.one` (repeat the SAME
///   track). One press flips it; it highlights only while on. The on-finished
///   replay is `PlayerCore.handlePlaybackFinished` (`.one` reloads the same track),
///   the SAME path the classic skin's repeat drives, so a finished track actually
///   replays. `.all` is unused in the default UI (a classic-only mode).
/// - Shuffle and Repeat are MUTUALLY EXCLUSIVE: enabling one disables the other
///   (turning Shuffle on sets `repeatMode = .off`; turning Repeat on sets
///   `isShuffle = false`), so at most one of the two is lit at any time.
/// - EQ → toggles `core.setEQEnabled` (grey ↔ active), kept in sync with the EQ
///   drawer's On checkbox: both read/drive the same `core.equalizer.enabled`. The
///   drawer is always visible (no collapse), so this button only enables/disables.
/// - ◀◀ / ▶▶ → `core.previous()` / `core.next()`.
/// - play-pause → `core.togglePlayPause()`.
/// - ■ (stop) → pause + seek to 0 (`PlayerCore.stop()` is private; this reproduces
///   its user-visible effect: playback halts and the position resets).
/// - volume → `core.volume` / `core.setVolume(_:)`.
struct CadenceTransport: View {

    @Bindable var core: PlayerCore
    let theme: AppearanceTheme

    var body: some View {
        HStack(spacing: 12) {
            // Left zone — the toggles (fixed 176 pt so the centre cluster stays
            // centred within the row).
            HStack(spacing: 4) {
                TransportToggle(
                    title: "Shuffle",
                    isActive: core.isShuffle,
                    bold: false,
                    theme: theme
                ) {
                    core.isShuffle.toggle()
                    // MUTUALLY EXCLUSIVE with Repeat: turning Shuffle ON turns
                    // Repeat off, so at most one is lit at a time.
                    if core.isShuffle { core.repeatMode = .off }
                }

                TransportToggle(
                    title: "Repeat",
                    isActive: core.repeatMode == .one,
                    bold: false,
                    theme: theme
                ) {
                    // 2-state off <-> .one, and MUTUALLY EXCLUSIVE with Shuffle:
                    // turning Repeat ON turns Shuffle off.
                    let turningOn = core.repeatMode != .one
                    core.repeatMode = turningOn ? .one : .off
                    if turningOn { core.isShuffle = false }
                }

                TransportToggle(
                    title: "EQ",
                    isActive: core.equalizer.enabled,
                    bold: true,
                    theme: theme
                ) { core.setEQEnabled(!core.equalizer.enabled) }
            }
            .frame(width: 176, alignment: .leading)

            // Centre cluster.
            HStack(spacing: 6) {
                TransportIconButton(systemName: "backward.fill", label: "Previous track") {
                    core.previous()
                }
                PlayButton(isPlaying: core.isPlaying) {
                    core.togglePlayPause()
                }
                TransportIconButton(systemName: "stop.fill", label: "Stop") {
                    core.pause()
                    core.seek(to: 0)
                }
                TransportIconButton(systemName: "forward.fill", label: "Next track") {
                    core.next()
                }
            }
            .frame(maxWidth: .infinity)

            // Right zone — speaker glyph + volume slider (fixed 176 pt, right).
            HStack(spacing: 7) {
                speakerGlyph
                CadenceVolumeSlider(
                    value: core.volume,
                    onChange: { core.setVolume($0) }
                )
                .frame(width: 84)
            }
            .frame(width: 176, alignment: .trailing)
        }
    }

    /// The static two-bar speaker glyph (decorative), 2×5 and 2×9 pt bars.
    private var speakerGlyph: some View {
        HStack(alignment: .center, spacing: 1.5) {
            Capsule().fill(AppearanceTheme.secondary).frame(width: 2, height: 5)
            Capsule().fill(AppearanceTheme.secondary).frame(width: 2, height: 9)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - TransportToggle

/// A Shuffle / Repeat / EQ toggle pill: 24 pt tall, 11 pt text. Inactive is muted
/// text on transparent (hover raises a faint fill); active is white text on the
/// theme accent at 34% alpha.
private struct TransportToggle: View {
    let title: String
    let isActive: Bool
    let bold: Bool
    let theme: AppearanceTheme
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: bold ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.white : AppearanceTheme.idleToggle)
                .frame(height: 24)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(background)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var background: Color {
        if isActive { return theme.accent.opacity(0.34) }
        return hovering ? Color.white.opacity(0.07) : .clear
    }
}

// MARK: - TransportIconButton

/// A secondary transport button (◀◀ / ■ / ▶▶): 32×28 pt, quiet glyph that brightens
/// on hover.
private struct TransportIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Color.white : AppearanceTheme.idleTransport)
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? Color.white.opacity(0.09) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(label))
    }
}

// MARK: - PlayButton

/// The primary play/pause button: 44×34 pt, a translucent panel with an inset
/// edge; the glyph swaps play.fill ↔ pause.fill from the live transport state.
private struct PlayButton: View {
    let isPlaying: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppearanceTheme.primaryText)
                .frame(width: 44, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.16 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppearanceTheme.windowEdge, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(isPlaying ? "Pause" : "Play"))
    }
}

// MARK: - CadenceVolumeSlider

/// A thin horizontal volume slider: a 3 pt rail with a filled portion and a round
/// knob. CLICK or DRAG sets the volume in `0...1` continuously.
private struct CadenceVolumeSlider: View {
    /// The live volume in `0...1`.
    let value: Float
    /// Called with a new `0...1` volume on click / drag.
    let onChange: (Float) -> Void

    private let knobDiameter: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let f = CGFloat(min(max(value, 0), 1))
            let knobTravel = max(0, width - knobDiameter)
            let knobX = knobDiameter / 2 + knobTravel * f

            ZStack(alignment: .leading) {
                Capsule().fill(AppearanceTheme.railFill).frame(height: 3)
                Capsule().fill(AppearanceTheme.volumeFill)
                    .frame(width: max(0, width * f), height: 3)
                Circle()
                    .fill(AppearanceTheme.volumeKnob)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
                    .position(x: knobX, y: geometry.size.height / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    onChange(Float(Self.fraction(forX: g.location.x, width: width, knobDiameter: knobDiameter)))
                }
            )
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel(Text("Volume"))
        .accessibilityValue(Text("\(Int((min(max(value, 0), 1)) * 100)) percent"))
    }

    /// The `0...1` volume for a cursor `x`, mapped through the SAME knob-travel inset
    /// the knob renders with (its centre travels `knobDiameter/2 … width−knobDiameter/2`,
    /// not the full width), so the knob sits under the pointer at both extremes —
    /// mirroring the seek bar's self-consistent mapping. A width at/under the knob
    /// diameter (zero travel) reads as 0.
    private static func fraction(forX x: CGFloat, width: CGFloat, knobDiameter: CGFloat) -> Double {
        let knobTravel = max(0, width - knobDiameter)
        guard knobTravel > 0 else { return 0 }
        return min(max(Double((x - knobDiameter / 2) / knobTravel), 0), 1)
    }
}
