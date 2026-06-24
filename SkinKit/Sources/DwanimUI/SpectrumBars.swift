import SwiftUI

// MARK: - SpectrumBars

/// A small row of spectrum bars driven by `[Float]` levels (each `0...1`). Each
/// bar's height is its level fraction of the available height, gold-tinted and
/// rounded, with a faint floor so an idle (all-zero) row still reads as a quiet
/// baseline rather than a blank gap.
///
/// Pure presentation: it owns no analyzer and no timer; the harness feeds fresh
/// `levels` into the view-model each tick and SwiftUI re-lays-out the bars.
struct SpectrumBars: View {

    /// The bar levels, each clamped to `0...1` at draw time.
    let levels: [Float]

    /// Minimum visible bar height fraction so an idle row shows a baseline.
    private let floor: CGFloat = 0.08

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    let fraction = max(floor, min(CGFloat(level), 1))
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(DwanimTheme.goldGradient)
                        .frame(height: max(1, height * fraction))
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
