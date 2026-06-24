import SwiftUI

// MARK: - DwanimBackdrop

/// The colourful backdrop that sits BEHIND the glass player bar so the
/// translucent materials have something to blur — without it the
/// `.regularMaterial` / `.ultraThinMaterial` panels read as flat grey.
///
/// A deep indigo -> teal diagonal gradient with two soft gold glows (warm
/// accents), filling whatever space it is given. The harness hosts this behind
/// `DefaultPlayerView` (see `DwanimPlayerScene`).
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
        .ignoresSafeArea()
    }
}
