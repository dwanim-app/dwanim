import SwiftUI

// MARK: - CadenceVisualizer

/// The hero "LCD" visualiser well: a recessed rounded panel (`theme.lcd` fill,
/// inner hairline) holding a full-bleed row of spectrum bars driven by the live
/// `levels` (each `0...1`) from `PlayerViewModel`.
///
/// Phase-1 scope: it REUSES the existing spectrum `levels` and restyles the bars to
/// the theme accent (a vertical gradient from the accent at 95% alpha down to 34%),
/// matching the design's bar fill. The design's bar physics — the `k^1.7` frequency
/// curve, peak-hold decay, and the idle drifting-sine animation — are deferred to a
/// later phase; here a faint floor keeps an idle (all-zero) row reading as a quiet
/// baseline rather than a blank well.
struct CadenceVisualizer: View {

    let theme: AppearanceTheme
    /// The live spectrum bar levels, each clamped to `0...1` at draw time.
    let levels: [Float]

    /// The well's fixed height (design: 118 px).
    private let wellHeight: CGFloat = 118
    /// Inner padding around the bars inside the well (design: 8 px).
    private let wellPadding: CGFloat = 8
    /// A faint baseline fraction so an idle row is never a dead blank.
    private let floor: CGFloat = 0.02

    var body: some View {
        bars
            .padding(wellPadding)
            .frame(height: wellHeight)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.lcd)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }

    private var bars: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    let fraction = max(floor, min(CGFloat(level), 1))
                    RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [theme.accent.opacity(0.95), theme.accent.opacity(0.34)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: max(1, height * fraction))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
