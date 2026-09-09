import PlayerCore
import SwiftUI

// MARK: - CadenceEQDrawer

/// The always-visible 10-band graphic-equaliser section. It binds directly to
/// `PlayerCore.equalizer` — the SAME authoritative `EQState` the classic `.wsz` EQ
/// drives — so dragging here changes the playing audio immediately (once EQ is on).
///
/// This section never collapses/hides, and (F5) it is NEVER a dead block: the
/// presets and sliders stay fully interactive while EQ is off, and touching any of
/// them turns the equalizer ON — the rule lives in the model
/// (`PlayerCore.setEQBand` / `setEQPreamp`), not here. The only OFF cue is the
/// thumbs' grey `eqThumbOff` fill; nothing is dimmed or `.disabled`. The **On**
/// checkbox here and the transport **EQ** button both read/drive the same
/// `core.equalizer.enabled`, so either turns the section on/off explicitly.
///
/// Contents (design §1d):
/// - a header row ("Equalizer");
/// - an **On** checkbox (accent fill + white ✓) wired to `core.setEQEnabled`;
/// - a Flat / Rock / Vocal / Bass segmented control — selecting a preset APPLIES its
///   10-band gain array (via `core.setEQBand`, so the sliders visibly move to match)
///   AND highlights that tab; dragging any band manually clears the highlight. The
///   preset curves live in the pure, unit-tested `EQPreset`. Presets do NOT touch the
///   preamp; applying one turns EQ ON like any other adjustment (model rule);
/// - a **Pre** preamp slider wired to `core.setEQPreamp`;
/// - the 10 band sliders wired to `core.setEQBand(_:dB:)`.
///
/// The gain↔position mapping is the pure, unit-tested `EQSliderMath` (top = +12 dB,
/// bottom = −12 dB, centre = flat), so this view carries no gain math of its own.
struct CadenceEQDrawer: View {

    @Bindable var core: PlayerCore
    let theme: AppearanceTheme
    /// Test-support geometry probe (see `CadenceControlProbe`); `nil` in production.
    var probe: CadenceControlProbe? = nil

    /// The highlighted preset, DERIVED from the live `core.equalizer.bands` rather
    /// than stored: a preset is highlighted only while the bands EXACTLY match its
    /// gain array, else nothing is. Deriving (vs. an `@State` snapshot fixed at view
    /// creation) keeps the highlight honest even when the SHARED bands are changed
    /// elsewhere — e.g. the classic `.wsz` EQ moving the same `EQState` while this
    /// (persistent) default drawer is hidden behind a skin. A manual band drag moves
    /// the bands off every preset's array, so the highlight clears on its own; a fresh
    /// (all-zero) equalizer matches `.flat`, so Flat starts highlighted as before.
    private var activePreset: EQPreset? {
        EQPreset.allCases.first { $0.bands == core.equalizer.bands }
    }

    private static let bandLabels = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]
    private static let trackHeight: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Equalizer", bundle: .module)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppearanceTheme.secondary)
                .frame(height: 26)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 11) {
                headerControls
                sliders
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .top) {
            Rectangle().fill(AppearanceTheme.hairline).frame(height: 0.5)
        }
    }

    // MARK: Header (On checkbox + preset segmented control)

    private var headerControls: some View {
        HStack(spacing: 10) {
            Button {
                core.setEQEnabled(!core.equalizer.enabled)
            } label: {
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(core.equalizer.enabled ? theme.accent : AppearanceTheme.checkboxOffFill)
                            .frame(width: 13, height: 13)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                            )
                        if core.equalizer.enabled {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    Text("On", bundle: .module)
                        .font(.system(size: 12))
                        .foregroundStyle(AppearanceTheme.titleText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CadencePressStyle())
            .accessibilityLabel(Text("Equalizer on", bundle: .module))
            .accessibilityAddTraits(core.equalizer.enabled ? .isSelected : [])
            .cadenceControl(.eqOn, probe: probe)

            Spacer(minLength: 0)

            // F5 — the presets stay LIVE while EQ is off: choosing one applies its
            // curve through `core.setEQBand`, which turns the equalizer on.
            segmentedPresets
        }
    }

    private var segmentedPresets: some View {
        HStack(spacing: 2) {
            ForEach(EQPreset.allCases, id: \.self) { preset in
                let selected = activePreset == preset
                Button {
                    apply(preset)
                } label: {
                    // Display uses the LOCALIZED `displayName`; the segmented control's
                    // identity/highlight still derives from `bands` (see `activePreset`),
                    // never from this label — `rawValue` stays the untranslated identity.
                    Text(preset.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? AppearanceTheme.primaryText : AppearanceTheme.idleToggle)
                        .frame(height: 20)
                        .padding(.horizontal, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selected ? Color.white.opacity(0.14) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(CadencePressStyle())
                .cadenceControl(.eqPreset(preset), probe: probe)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.26))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppearanceTheme.hairline, lineWidth: 0.5)
                )
        )
    }

    // MARK: Sliders (Pre + 10 bands)

    private var sliders: some View {
        HStack(alignment: .top, spacing: 9) {
            // Preamp column, set apart by a right hairline.
            VStack(spacing: 6) {
                EQVerticalSlider(
                    gain: core.equalizer.preamp,
                    enabled: core.equalizer.enabled,
                    showCenterLine: false,
                    trackHeight: Self.trackHeight
                ) { core.setEQPreamp($0) }
                .cadenceControl(.eqPreamp, probe: probe)
                // "Pre" is a fixed-frame preamp abbreviation (data, not prose) — verbatim.
                Text(verbatim: "Pre")
                    .font(.system(size: 10))
                    .foregroundStyle(AppearanceTheme.secondary)
            }
            .padding(.trailing, 9)
            .overlay(alignment: .trailing) {
                Rectangle().fill(AppearanceTheme.hairline).frame(width: 0.5)
            }

            // 10 bands, spread evenly.
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<EQState.bandCount, id: \.self) { index in
                    VStack(spacing: 6) {
                        EQVerticalSlider(
                            gain: band(index),
                            enabled: core.equalizer.enabled,
                            showCenterLine: true,
                            trackHeight: Self.trackHeight
                        ) { newGain in
                            core.setEQBand(index, dB: newGain)
                        }
                        .cadenceControl(.eqBand(index), probe: probe)
                        // Hz band labels (60…16K) are frequency DATA — verbatim.
                        Text(verbatim: Self.bandLabels[index])
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppearanceTheme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        // F5 — NOT dimmed and NOT disabled while EQ is off. The thumbs' grey
        // `eqThumbOff` fill is the one subtle OFF cue; every slider stays
        // full-strength and hit-testable, and the first drag turns EQ on.
    }

    private func band(_ index: Int) -> Double {
        core.equalizer.bands.indices.contains(index) ? core.equalizer.bands[index] : 0
    }

    /// Apply `preset`: push every band gain through the SAME `core.setEQBand` call
    /// the sliders use (so the thumbs visibly move to match the curve). The tab
    /// highlight follows automatically — `activePreset` re-derives from the
    /// now-matching bands. The preamp is untouched; EQ turns ON through the model's
    /// interaction rule, exactly as a slider drag does.
    private func apply(_ preset: EQPreset) {
        let gains = preset.bands
        for index in 0..<EQState.bandCount where index < gains.count {
            core.setEQBand(index, dB: gains[index])
        }
    }
}

// MARK: - EQVerticalSlider

/// One vertical EQ slider: a recessed rail, an optional 0 dB centre line, and a
/// draggable white thumb (greyed when the EQ is off). Top = +12 dB, bottom = −12 dB.
/// A zero-distance drag means a plain CLICK jumps the thumb; the cursor→gain mapping
/// is the pure `EQSliderMath`, handed to `onChange` for the matching `PlayerCore`
/// setter.
private struct EQVerticalSlider: View {
    let gain: Double
    let enabled: Bool
    let showCenterLine: Bool
    let trackHeight: CGFloat
    let onChange: (Double) -> Void

    private let thumbHeight: CGFloat = 11
    private let columnWidth: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let fraction = EQSliderMath.fraction(forGain: gain)
            let travel = max(0, height - thumbHeight)
            let thumbCenterY = thumbHeight / 2 + travel * (1 - fraction)

            ZStack {
                // Recessed rail.
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 3)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            .frame(width: 3)
                    )

                // 0 dB centre line (bands only).
                if showCenterLine {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 0.5)
                        .position(x: columnWidth / 2, y: height / 2)
                }

                // The draggable thumb.
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(enabled ? AppearanceTheme.eqThumbOn : AppearanceTheme.eqThumbOff)
                    .frame(width: columnWidth - 4, height: thumbHeight)
                    // Handoff §1d: 0 0.5px 2px rgba(0,0,0,0.55) (≈ radius 2), matching
                    // the P7 volume-knob shadow fix.
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 0.5)
                    .position(x: columnWidth / 2, y: thumbCenterY)
            }
            .frame(width: columnWidth, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    onChange(EQSliderMath.gain(forY: Double(value.location.y), height: Double(height)))
                }
            )
        }
        .frame(width: columnWidth, height: trackHeight)
        .accessibilityElement()
        // Locale-aware dB read-out. The signed integer keeps its sign (negatives render
        // the locale's minus glyph, positive/zero take none — sign handling preserved),
        // and the "%lld decibels" catalog key localizes the unit word.
        .accessibilityValue(Text("\(Int(gain.rounded())) decibels", bundle: .module))
    }
}
