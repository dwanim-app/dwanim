import SwiftUI

// MARK: - CadenceMotion

/// The shared micro-interaction timings for the default (Cadence) face, kept in one
/// place so every control eases identically (M1 / M3). The prototype uses no
/// transitions at all; the handoff explicitly sanctions "adding a 120 ms ease"
/// (README:60), so hover/press flips animate over `hoverEase` and a theme swap
/// crossfades its colours over `themeCrossfade`.
enum CadenceMotion {

    /// The 120 ms hover/press colour ease (M1 / S-d). Applied via `.animation(_:value:)`
    /// keyed on the relevant hover/open flag so only that flip animates.
    static let hoverEase: Animation = .easeInOut(duration: 0.12)

    /// The gentle theme-switch colour crossfade (M3). The prototype applies skins
    /// instantly; a short crossfade is a nicety beyond spec, kept subtle so switching
    /// still reads as immediate. Keyed on the theme name so it fires only on a real
    /// theme change, never on the per-frame visualiser updates.
    static let themeCrossfade: Animation = .easeInOut(duration: 0.2)
}

// MARK: - CadencePressStyle

/// The shared press/active feedback for the transport + action buttons (M2 / S-d).
/// The handoff never quantifies a pressed style, so this is a tasteful default: a
/// slight scale-in and dim while held, eased over the same 120 ms as the hover
/// states, uniform across every control. It fully owns rendering (like `.plain`), so
/// it carries no default button chrome — the label's own hover fill / background is
/// preserved and merely scaled/dimmed on press.
struct CadencePressStyle: ButtonStyle {

    /// The scale while pressed (a barely-there inward push).
    var pressedScale: CGFloat = 0.97
    /// The opacity while pressed.
    var pressedOpacity: Double = 0.85

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(CadenceMotion.hoverEase, value: configuration.isPressed)
    }
}
