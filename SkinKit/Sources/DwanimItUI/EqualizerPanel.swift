import PlayerCore
import SwiftUI

// MARK: - EqualizerPanel

/// The default-skin graphic equalizer: an ON/OFF (bypass) toggle, a PREAMP
/// column, and the 10 frequency-band columns — every control a vertical,
/// draggable slider styled in the Dwennimmen theme (gold thumbs/fills on the
/// teal-indigo glass). It binds directly to `PlayerCore.equalizer`, the SAME
/// authoritative 10-band state the classic `.wsz` EQ window drives, so dragging a
/// band here changes the PLAYING audio immediately and the classic EQ (if open)
/// reflects it on its next redraw.
///
/// ## Shared-state binding (no new PlayerCore API)
/// Reads come from `core.equalizer` (`.enabled` / `.preamp` / `.bands[i]`), which
/// is an `@Observable` stored property on `PlayerCore`, so SwiftUI re-renders when
/// the track-load re-apply or the classic EQ mutate it. Writes go through the
/// clamping, finite-guarded setters `core.setEQEnabled` / `core.setEQPreamp` /
/// `core.setEQBand(_:dB:)` — the EXACT setters `EQController` uses — each of which
/// mirrors the new state to the engine (the `pushEqualizerToEngine` path). So both
/// faces drive one shared `EQState`; nothing here is stored UI state that could
/// diverge.
///
/// ## Why custom vertical sliders, not `Slider`
/// SwiftUI ships no native vertical `Slider`, and the classic EQ sliders are
/// vertical (top = boost, bottom = cut). Each column is a small draggable track
/// built on the same zero-distance `DragGesture` pattern as `ProgressTrack`, with
/// the gain math factored into the pure, unit-tested `EQSliderMath` (top = +12 dB,
/// bottom = −12 dB, centre = flat). The View carries no gain math of its own.
///
/// ## Default-disabled caveat
/// A fresh `EQState` is DISABLED (flat pass-through) — showing this panel does NOT
/// alter audio until the user flips the ON toggle, exactly like the classic EQ
/// (which also defaults off). The toggle is surfaced prominently at the top-left so
/// that affordance is obvious.
struct EqualizerPanel: View {

    @Bindable var core: PlayerCore

    /// Centre frequencies for the 10 bands, low -> high, used only for the column
    /// labels. The authoritative copy lives in `PlaybackKit/EQConfig.swift`
    /// (`centreFrequencies`), which `DwanimItUI` cannot import (it depends on
    /// `PlayerCore` only). This is a HAND-SYNCED duplicate for display: if the DSP
    /// band centres ever change, update this array to match — there is no
    /// compile-time link. Index `i` here labels `core.equalizer.bands[i]`.
    private static let bandFrequencies: [Int] = [
        60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000,
    ]

    /// The travel height (points) of every slider column's track. A definite
    /// height so the panel self-sizes under the scene's `.fixedSize(vertical:)`
    /// (a bare greedy view would resolve to ~0 and the window would not grow —
    /// the same trap `PlaylistPanel` documents).
    private static let trackHeight: CGFloat = 96

    /// A DEFINITE width for each slider column. Pinning every column (rather than
    /// letting them be `maxWidth: .infinity`-greedy) keeps the panel's IDEAL width
    /// FINITE: under the window's `.windowResizability(.contentMinSize)` a greedy
    /// horizontal child propagates an unbounded ideal width that the window opens
    /// at a platform default (~900pt) instead of hugging the 580 panel — the
    /// width analogue of the `PlaylistPanel` definite-height fix. 11 columns + the
    /// preamp divider fit inside the 580 panel's content box with margin to spare.
    private static let columnWidth: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .top, spacing: 6) {
                // Preamp column, slightly set apart from the bands by the divider.
                EQSliderColumn(
                    label: "PRE",
                    gain: core.equalizer.preamp,
                    trackHeight: Self.trackHeight,
                    enabled: core.equalizer.enabled
                ) { newGain in
                    core.setEQPreamp(newGain)
                }
                .frame(width: Self.columnWidth)

                Divider()
                    .frame(height: Self.trackHeight)
                    .overlay(DwanimItTheme.glassStroke)

                // The 10 frequency bands, low -> high.
                ForEach(0..<EQState.bandCount, id: \.self) { index in
                    EQSliderColumn(
                        label: Self.frequencyLabel(forBand: index),
                        gain: gain(forBand: index),
                        trackHeight: Self.trackHeight,
                        enabled: core.equalizer.enabled
                    ) { newGain in
                        core.setEQBand(index, dB: newGain)
                    }
                    .frame(width: Self.columnWidth)
                }
            }
            // Centre the hugging band row within the (wider) panel column. The row
            // hugs its definite-width columns rather than stretching, so the panel's
            // ideal width stays finite and the window hugs the 580 panel.
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Header (ON/OFF + title)

    /// The title and the ON/OFF (bypass) toggle. The toggle is the prominent
    /// affordance: a fresh EQ is disabled, so showing the panel alone does not
    /// change audio until it is turned on.
    private var header: some View {
        HStack(spacing: 12) {
            Text("EQUALIZER")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.55))

            Spacer()

            Toggle(isOn: enabledBinding) {
                Text(core.equalizer.enabled ? "ON" : "OFF")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .toggleStyle(.switch)
            .tint(DwanimItTheme.goldDeep)
            .fixedSize()
            .help(core.equalizer.enabled ? "Bypass the equalizer" : "Enable the equalizer")
            .accessibilityLabel(Text("Equalizer enabled"))
        }
    }

    /// A two-way binding onto `core.equalizer.enabled` that WRITES through the
    /// clamping setter (`setEQEnabled`) — so the toggle mirrors to the engine the
    /// same way every other control does — and READS the live shared state.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { core.equalizer.enabled },
            set: { core.setEQEnabled($0) }
        )
    }

    // MARK: - Band reads / labels

    /// The live gain for band `index`, read from the shared state. Out-of-range
    /// (never happens with the fixed 10-element array) reads as flat `0`.
    private func gain(forBand index: Int) -> Double {
        core.equalizer.bands.indices.contains(index) ? core.equalizer.bands[index] : 0
    }

    /// A compact frequency label for band `index` (e.g. "60", "1k", "16k").
    /// Hertz under 1000 show the raw number; 1000 and above show "Nk".
    private static func frequencyLabel(forBand index: Int) -> String {
        guard bandFrequencies.indices.contains(index) else { return "" }
        let hz = bandFrequencies[index]
        if hz >= 1000 {
            let k = hz / 1000
            return "\(k)k"
        }
        return "\(hz)"
    }
}

// MARK: - EQSliderColumn

/// One vertical EQ column: a frequency/PRE label, a draggable gold-on-glass track
/// (top = +12 dB boost, bottom = −12 dB cut), and a small 0 dB centre tick. The
/// gesture mirrors `ProgressTrack` (a zero-distance `DragGesture` so a plain CLICK
/// jumps the thumb and a drag scrubs it), and the cursor-y -> gain mapping is the
/// pure `EQSliderMath` (clamped to ±12 dB, finite-guarded). On every change it
/// calls `onChange` with the new gain, which the panel routes to the matching
/// `PlayerCore` setter — so the dragged column drives the real engine.
private struct EQSliderColumn: View {

    let label: String
    /// The live gain in dB for this column, from the shared `EQState`.
    let gain: Double
    /// The track's travel height in points (the band thumb spans this range).
    let trackHeight: CGFloat
    /// Whether the EQ is enabled; a disabled EQ dims the columns (still draggable,
    /// matching the classic EQ which lets you dial gains while bypassed).
    let enabled: Bool
    /// Called with a new gain in dB whenever the cursor moves the thumb.
    let onChange: (Double) -> Void

    /// Track width (the visual rail); the hit area is wider via `contentShape`.
    private let trackWidth: CGFloat = 6
    /// The draggable thumb's diameter.
    private let thumbDiameter: CGFloat = 12

    var body: some View {
        VStack(spacing: 6) {
            track
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .fixedSize()
        }
        .opacity(enabled ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityLabel(Text("\(label) band"))
        .accessibilityValue(Text("\(Int(gain.rounded())) decibels"))
    }

    private var track: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let fraction = EQSliderMath.fraction(forGain: gain)
            // y grows downward: fraction 1 (max gain) sits at the TOP (y small).
            let thumbTravel = max(0, height - thumbDiameter)
            let thumbY = thumbDiameter / 2 + thumbTravel * (1 - fraction)
            // The filled portion runs from the 0 dB centre to the thumb, so a boost
            // fills upward and a cut fills downward — reading like the classic EQ.
            let centerY = height / 2

            ZStack(alignment: .center) {
                // Unfilled rail.
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: trackWidth)

                // 0 dB centre tick.
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 14, height: 1)
                    .position(x: geometry.size.width / 2, y: centerY)

                // Gold fill from centre to the thumb.
                Capsule(style: .continuous)
                    .fill(DwanimItTheme.goldGradient)
                    .frame(width: trackWidth, height: max(0, abs(thumbY - centerY)))
                    .position(x: geometry.size.width / 2, y: (thumbY + centerY) / 2)

                // The draggable thumb.
                Circle()
                    .fill(DwanimItTheme.goldGradient)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .position(x: geometry.size.width / 2, y: thumbY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(height: height))
        }
        .frame(width: 22, height: trackHeight)
    }

    /// A zero-distance drag so a plain CLICK jumps the thumb to the cursor and a
    /// drag scrubs it continuously. The cursor y maps to a gain via the pure
    /// `EQSliderMath` (top = +12, bottom = −12, clamped + finite-guarded); the
    /// gain is handed to `onChange` which writes the matching `PlayerCore` setter.
    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let newGain = EQSliderMath.gain(forY: Double(value.location.y), height: Double(height))
                onChange(newGain)
            }
    }
}
