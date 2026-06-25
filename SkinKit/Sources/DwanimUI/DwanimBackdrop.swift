import SwiftUI

// MARK: - DwanimBackdrop

/// The colourful backdrop that sits BEHIND the glass player bar so the
/// translucent materials have something to blur — without it the
/// `.regularMaterial` / `.ultraThinMaterial` panels read as flat grey.
///
/// A deep indigo -> teal diagonal gradient with two soft gold glows (warm
/// accents). It fills exactly the space its parent gives it — used as a BOUNDED
/// `.background` of the panel-plus-margin in `DwanimPlayerScene`, NOT as a
/// full-bleed `.ignoresSafeArea()` fill. That bounded use is what gives the
/// scene a compact intrinsic size for `.windowResizability(.contentSize)` to
/// hug: a flexible gradient that ignored the safe area would expand to fill any
/// window, leaving the panel floating in a big empty expanse.
public struct DwanimBackdrop: View {

    public init() {}

    public var body: some View {
        ZStack {
            DwanimTheme.backdrop

            // Two soft gold glows for warmth and so the glass picks up colour.
            RadialGradient(
                colors: [DwanimTheme.goldDeep.opacity(0.35), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 320
            )
            RadialGradient(
                colors: [DwanimTheme.backdropTeal.opacity(0.6), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 360
            )
        }
    }
}
