import SwiftUI

// MARK: - ProgressTrack

/// A thin glass progress bar filled gold to `progress` (`0...1`). A faint
/// translucent capsule is the unfilled track; a gold capsule overlays it from
/// the leading edge to the progress fraction.
///
/// Display-only: it takes a clamped progress fraction and draws it. Seeking is
/// not wired here (the bar is non-interactive in this first default-skin pass);
/// the value comes from `PlayerViewModel.progress`.
struct ProgressTrack: View {

    /// Playback progress, expected in `0...1`; clamped defensively at draw time.
    let progress: Double

    /// The bar's thickness in points.
    private let thickness: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                Capsule(style: .continuous)
                    .fill(DwanimTheme.goldGradient)
                    .frame(width: max(0, width * fraction))
            }
            .frame(height: thickness)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: thickness)
        .accessibilityHidden(true)
    }
}
