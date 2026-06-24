import SwiftUI

// MARK: - EmblemTile

/// The glass tile on the left of the player bar that holds the `DwennimmenMark`.
/// A rounded translucent panel (ultra-thin material) with a subtle white-ish
/// stroke and an inner gold glow, the gold ram's-horns mark stroked on top, and
/// the small gold dot at the top centre.
///
/// This is the ONLY heritage element and it appears as imagery only — there is
/// no "Dwennimmen" text anywhere in the running UI.
struct EmblemTile: View {

    /// The tile's side length in points.
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                        .stroke(DwanimTheme.glassStrokeStrong, lineWidth: 1)
                }
                .overlay {
                    // A soft gold inner glow so the gold mark sits in warm light.
                    RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [DwanimTheme.goldDeep.opacity(0.22), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: side * 0.6
                            )
                        )
                }

            // The mark: gold-filled horns + a separate filled gold dot, inset so
            // it breathes inside the tile.
            ZStack {
                DwennimmenMark()
                    .stroke(
                        DwanimTheme.goldGradient,
                        style: StrokeStyle(lineWidth: side * 0.05, lineCap: .round, lineJoin: .round)
                    )
                dot
            }
            .padding(side * 0.18)
            .shadow(color: DwanimTheme.goldDeep.opacity(0.5), radius: side * 0.04)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    // MARK: - Dot

    /// The small gold dot at the top centre of the mark, positioned in the same
    /// 100x100 design space the horns use so it stays aligned at any tile size.
    private var dot: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let transform = DwennimmenMark.fitTransform(into: rect)
            let center = DwennimmenMark.dotCenter.applying(transform)
            let radius = DwennimmenMark.dotRadius * transform.a
            Circle()
                .fill(DwanimTheme.goldGradient)
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
        }
    }
}
