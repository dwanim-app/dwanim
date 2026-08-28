import Foundation
import PlayerCore

// MARK: - EQPreset

/// The four named graphic-EQ presets the default UI's Flat / Rock / Vocal / Bass
/// segmented control offers, each a fixed array of `EQState.bandCount` per-band
/// gains in dB (low frequency first). Pure data + a `bands` lookup — no View, no
/// engine — so the preset -> gains mapping is unit-testable in isolation, mirroring
/// how `EQSliderMath` keeps the slider math out of the View.
///
/// Selecting a preset applies its `bands` to every band via `PlayerCore.setEQBand`,
/// which drives both the visible slider positions (they read `core.equalizer.bands`)
/// and the playing audio (once EQ is on). The preamp is NOT part of a preset.
///
/// The gain curves are the classic Winamp-style arrays documented in the README;
/// every value already sits within `EQState.gainRange` (`-12...+12 dB`).
enum EQPreset: String, CaseIterable {
    case flat = "Flat"
    case rock = "Rock"
    case vocal = "Vocal"
    case bass = "Bass"

    /// The per-band gains in dB (low frequency first), exactly `EQState.bandCount`
    /// values, each within `EQState.gainRange`.
    var bands: [Double] {
        switch self {
        case .flat:  return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .rock:  return [5, 4, 2, 0, -1, 1, 3, 4, 4, 3]
        case .vocal: return [-3, -1, 1, 3, 4, 4, 2, 1, 0, -1]
        case .bass:  return [8, 7, 4, 1, 0, 0, 0, -1, -1, -1]
        }
    }

    /// The LOCALIZED, display-only label the segmented control renders (`Text(preset
    /// .displayName)` in `CadenceEQDrawer`). Kept STRICTLY SEPARATE from `rawValue`,
    /// which is the enum's stable identity/serialization: `rawValue` never localizes,
    /// so the derived-highlight and any persisted band arrays are untouched. Each case
    /// resolves through `Bundle.module`'s String Catalog (its source value equals the
    /// English `rawValue`, so under the uncompiled-catalog `swift test` path the display
    /// name falls back to the identity; production/xcodebuild resolves the ja/zh-Hant).
    var displayName: String {
        switch self {
        case .flat:  return String(localized: "Flat", bundle: .module, comment: "EQ preset: flat response")
        case .rock:  return String(localized: "Rock", bundle: .module, comment: "EQ preset: rock")
        case .vocal: return String(localized: "Vocal", bundle: .module, comment: "EQ preset: vocal")
        case .bass:  return String(localized: "Bass", bundle: .module, comment: "EQ preset: bass boost")
        }
    }
}
