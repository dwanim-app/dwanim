import SwiftUI

// MARK: - AppIconView

/// The macOS app-icon face: a deterministic, FLATTENED rendering of the brand —
/// the gold `DwennimmenMark` on a dark rounded-rectangle plate. This is the brand
/// mark as **imagery only**: no text, no "Dwennimmen"/"Dwanim" word anywhere.
///
/// Why a separate view from `EmblemTile`: the running-UI tile uses
/// `.ultraThinMaterial` (a LIVE blur that reads against the scene behind it).
/// That is exactly wrong for an icon — a live blur renders non-deterministically
/// off-screen (`ImageRenderer`) and turns muddy at 16x16. `AppIconView` therefore
/// fills the plate with a SOLID gradient (no material, no blur), so the same
/// pixels come out every render at every size.
///
/// macOS icon proportions: unlike iOS, macOS does NOT auto-mask the icon to a
/// rounded rect — the rounded look must be baked into the PNG. So the canvas is
/// the full square, the rounded plate occupies most of it with a small margin,
/// and the area OUTSIDE the plate is transparent.
///
/// Crispness across sizes: the mark's stroke width and its inset margin are
/// expressed as fractions of the side length, so at 16px the mark is a bold,
/// recognizable pair of horns (not a blurry dot) and at 1024px it is a confident
/// stroke (not a hairline). The whole face is laid out in a fixed unit square and
/// scaled by `side`, so geometry is identical at every canonical size — only the
/// pixel resolution differs.
public struct AppIconView: View {

    /// The icon's side length in points. The render mode sets a logical frame of
    /// `side` and a renderer scale of 1 so the OUTPUT is exactly `side`x`side` px.
    public let side: CGFloat

    public init(side: CGFloat) {
        self.side = side
    }

    // MARK: - Proportions (fractions of the side length)

    /// Transparent margin from the canvas edge to the plate. macOS art sits inside
    /// the square with a little breathing room; the grid leaves room for the
    /// system's own drop shadow.
    private static let plateMarginFraction: CGFloat = 0.06
    /// Plate corner radius as a fraction of the side — the macOS "squircle-ish"
    /// rounded rectangle (continuous corners).
    private static let plateCornerFraction: CGFloat = 0.20
    /// Inset of the mark from the plate edge: a generous margin so the horns
    /// breathe inside the plate at every size.
    private static let markInsetFraction: CGFloat = 0.24
    /// Mark stroke width as a fraction of the side — wide enough to stay bold at
    /// 16px, fine enough not to clog at 1024px.
    private static let strokeFraction: CGFloat = 0.072

    // MARK: - View

    public var body: some View {
        let plateMargin = side * Self.plateMarginFraction
        let plateSide = side - plateMargin * 2
        let plateCorner = side * Self.plateCornerFraction
        let strokeWidth = side * Self.strokeFraction
        let markInset = side * Self.markInsetFraction

        // Optically centre the mark on its ACTUAL inked bounds, not the nominal
        // 100x100 box. `DwennimmenMark.fitTransform` (used by the mark stroke and
        // the dot) centres the nominal box, but the inked content (horns + dot)
        // sits in the upper part of that box, so box-centring leaves more empty
        // plate below the horns than above. Shift the whole mark by the inked
        // centroid offset, converted from design units into the mark frame's
        // points: the mark+dot ZStack is framed at `plateSide` (square), and
        // `fitTransform` fits the 100x100 design box as the largest centred square,
        // so one design unit maps to `plateSide / designSize` points here.
        let markScale = plateSide / DwennimmenMark.designSize
        let centring = DwennimmenMark.inkedCentringOffset
        let markOffset = CGSize(
            width: centring.width * markScale,
            height: centring.height * markScale
        )

        ZStack {
            // The plate: a SOLID dark gradient (deep indigo -> teal, the brand
            // backdrop), NOT a material. A thin gold edge stroke and a soft gold
            // inner glow give it depth without any live blur, so it reads warm at
            // every size and renders identically off-screen.
            RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                .fill(DwanimTheme.backdrop)
                .overlay {
                    RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [DwanimTheme.goldDeep.opacity(0.28), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: plateSide * 0.62
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: plateCorner, style: .continuous)
                        .strokeBorder(DwanimTheme.goldEdge, lineWidth: max(1, side * 0.006))
                }
                .frame(width: plateSide, height: plateSide)

            // The mark: gold horns + the separate gold dot, inset inside the plate
            // and shifted by `markOffset` so the inked content is OPTICALLY centred
            // on the plate (see `markOffset` above) rather than nominally box-centred.
            ZStack {
                DwennimmenMark()
                    .stroke(
                        DwanimTheme.goldGradient,
                        style: StrokeStyle(
                            lineWidth: strokeWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                dot
            }
            .frame(width: plateSide, height: plateSide)
            .offset(markOffset)
            .padding(markInset)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    // MARK: - Dot

    /// The small gold dot at the top centre of the mark, positioned in the same
    /// 100x100 design space the horns use so it stays aligned at any icon size.
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
