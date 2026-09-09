import AppKit
import SwiftUI
import XCTest
import PlayerCore
@testable import DwanimItUI

// MARK: - TransportLayoutSpec

/// The transport row's layout numbers, PINNED here as literals.
///
/// These are deliberately NOT read from production. A guard whose budget is the
/// same symbol the code under test uses cannot catch the code widening that
/// symbol — `XCTAssertLessThanOrEqual(width, TransportToggleRow.zoneWidth)`
/// stays green no matter what `zoneWidth` becomes, so "widen the zone" defeats
/// every width assertion at once. The design says 176 pt side zones; that number
/// lives here, and `testTheSideZoneWidthMatchesTheDesign` is the one place the
/// two are compared.
enum TransportLayoutSpec {

    /// The fixed width of EACH side zone (left toggles, right volume).
    static let zoneWidth: CGFloat = 176

    /// The centre cluster's buttons, in layout order, with their fixed widths
    /// (`TransportIconButton` is 32 pt wide, `PlayButton` 44) and the 6 pt gap
    /// `CadenceTransport` lays them out with.
    static let clusterButtonWidths: [CGFloat] = [32, 44, 32, 32]
    static let clusterSpacing: CGFloat = 6

    /// The cluster's total width: 32 + 44 + 32 + 32 + 3 × 6 = 158 pt.
    static var clusterWidth: CGFloat {
        clusterButtonWidths.reduce(0, +) + clusterSpacing * CGFloat(clusterButtonWidths.count - 1)
    }

    /// How far LEFT of the cluster's centre the play/pause panel's centre sits.
    ///
    /// The play button is the second element, so its leading edge is 32 + 6 = 38 pt
    /// into the cluster and its centre 38 + 22 = 60 pt in, against a cluster
    /// half-width of 79 pt — 19 pt left of centre. This is what lets a measurement
    /// of the play panel (the only large filled rectangle the row draws) stand in
    /// for a measurement of the whole cluster.
    static var playCentreOffsetFromClusterCentre: CGFloat {
        let leadingEdge = clusterButtonWidths[0] + clusterSpacing
        return clusterWidth / 2 - (leadingEdge + clusterButtonWidths[1] / 2)
    }
}

// MARK: - CadenceTransportZoneLayoutTests

// THE CENTRING GUARD for the transport row.
//
// ## The defect this was written for
// `CadenceTransport` centres its playback cluster by giving the left and right
// zones the SAME fixed width — the cluster itself has no width, it takes the
// slack between them. The left zone read `TransportToggleRow.zoneWidth`; the
// right zone carried its own `176` literal. Two spellings of one number, with
// nothing asserting they agree.
//
// So changing the named constant moved ONE zone. A mutation run proved the cost:
// `zoneWidth = 200` left the whole 228-test UI target green while the transport
// cluster sat 12 pt off centre — and, because the repeat-pill width guard
// measured against that same symbol, it also handed the Japanese repeat pill
// (the overflow this whole change exists to fix) 24 pt of fake headroom.
//
// ## What is asserted
// 1. The design number is pinned independently of production (`TransportLayoutSpec`).
// 2. Both zones, AS THE APP BUILDS THEM, measure that number — so neither a
//    second literal nor a widened constant can survive.
// 3. The cluster is centred in the RENDERED row, measured off the pixels rather
//    than re-derived from the same constants the view uses. This is the
//    assertion that fails on geometry, not on a symbol: however the zones come
//    to disagree, the play panel lands somewhere other than the middle.
@MainActor
final class CadenceTransportZoneLayoutTests: XCTestCase {

    // MARK: - Fixtures

    private func makeCore() -> PlayerCore {
        let core = PlayerCore(engine: TransportRecordingEngine())
        core.load([
            Track(url: URL(fileURLWithPath: "/tmp/dwanim-zone/1.mp3"), title: "One", duration: 60),
            Track(url: URL(fileURLWithPath: "/tmp/dwanim-zone/2.mp3"), title: "Two", duration: 60)
        ])
        return core
    }

    /// A view's intrinsic width in POINTS, measured by hosting the real thing.
    private func width<V: View>(of view: V) -> CGFloat {
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.width
    }

    // MARK: - 1. The design number

    /// The pin. Production's constant must equal the design's 176 pt; the suite's
    /// width budgets are stated against `TransportLayoutSpec.zoneWidth`, so this
    /// is what stops the zone being widened to make an over-wide control "fit".
    func testTheSideZoneWidthMatchesTheDesign() {
        XCTAssertEqual(
            TransportToggleRow.zoneWidth, TransportLayoutSpec.zoneWidth,
            "the transport's side zones are a 176 pt design constant. Widening this is not a "
            + "fix for a control that overflows it — make the control narrower."
        )
    }

    // MARK: - 2. The two zones, as the app builds them

    /// Both side zones must measure the SAME, because that equality is the only
    /// thing centring the cluster. Measured off `CadenceTransport.leftZone` /
    /// `.rightZone`, which are the values `body` itself puts in the row.
    func testBothSideZonesMeasureTheSameWidth() {
        let core = makeCore()
        let left = width(of: CadenceTransport.leftZone(core: core, theme: .graphite))
        let right = width(of: CadenceTransport.rightZone(core: core))

        XCTAssertEqual(
            left, right, accuracy: 0.01,
            "the side zones measure \(left) pt and \(right) pt — unequal zones push the centre "
            + "cluster off centre by half the difference"
        )
        XCTAssertEqual(left, TransportLayoutSpec.zoneWidth, accuracy: 0.01,
                       "the left zone must be the design's \(TransportLayoutSpec.zoneWidth) pt")
        XCTAssertEqual(right, TransportLayoutSpec.zoneWidth, accuracy: 0.01,
                       "the right zone must be the design's \(TransportLayoutSpec.zoneWidth) pt")
    }

    /// The Repeat pill cycling must not move the zone boundary either: the left
    /// zone is fixed, so all three states measure the same framed width even
    /// though their CONTENT is what `CadenceTransportRepeatWidthTests` measures.
    func testTheLeftZoneWidthIsIndependentOfTheRepeatState() {
        let core = makeCore()
        var measured: [CGFloat] = []
        for mode in [RepeatMode.off, .all, .one] {
            core.repeatMode = mode
            measured.append(width(of: CadenceTransport.leftZone(core: core, theme: .graphite)))
        }
        for (mode, value) in zip([RepeatMode.off, .all, .one], measured) {
            XCTAssertEqual(value, TransportLayoutSpec.zoneWidth, accuracy: 0.01,
                           "\(mode): the left zone must stay pinned to the side-zone width")
        }
    }

    // MARK: - 3. The rendered geometry

    /// The centre cluster must be CENTRED in the row it renders into — asserted
    /// on pixels, at two different row widths, so a de-centred layout fails on
    /// geometry rather than on a constant.
    ///
    /// The probe is the play/pause panel: it is the only tall filled rectangle
    /// the row draws (34 pt against 9 pt text glyphs and a 12 pt volume knob), so
    /// it is unambiguous to find, and its offset from the cluster's centre is
    /// fixed by the cluster's own metrics (`TransportLayoutSpec`).
    func testTheCentreClusterIsCentredInTheRenderedRow() throws {
        for rowWidth in [CGFloat(560), CGFloat(640)] {
            let panel = try playPanelExtent(rowWidth: rowWidth)

            XCTAssertEqual(
                panel.width, TransportLayoutSpec.clusterButtonWidths[1], accuracy: 2,
                "the probe must be the 44 pt play panel, not some other ink "
                + "(found \(panel.width) pt at row width \(rowWidth))"
            )

            let clusterMidX = panel.midX + TransportLayoutSpec.playCentreOffsetFromClusterCentre
            XCTAssertEqual(
                clusterMidX, rowWidth / 2, accuracy: 1,
                "at a \(rowWidth) pt row the transport cluster's centre renders at "
                + String(format: "%.1f", clusterMidX)
                + " pt instead of \(rowWidth / 2) pt — the two side zones are not equally wide"
            )
        }
    }

    // MARK: - Pixel probing

    /// The play/pause panel's horizontal extent, in points, in a REAL render of
    /// `CadenceTransport` at `rowWidth`.
    private func playPanelExtent(rowWidth: CGFloat) throws -> (midX: CGFloat, width: CGFloat) {
        let heights = try inkColumnHeights(rowWidth: rowWidth)

        // The play panel is 34 pt tall; nothing else in the row is over ~17.
        let tallEnough = 25
        var runs: [(first: Int, last: Int)] = []
        var index = 0
        while index < heights.count {
            guard heights[index] >= tallEnough else { index += 1; continue }
            let first = index
            while index < heights.count && heights[index] >= tallEnough { index += 1 }
            runs.append((first, index - 1))
        }
        let run = try XCTUnwrap(runs.first, "no tall ink found — nothing rendered?")
        XCTAssertEqual(runs.count, 1, "expected exactly one tall filled panel, found \(runs.count)")

        let first = CGFloat(run.first)
        let last = CGFloat(run.last) + 1  // exclusive right edge
        return (midX: (first + last) / 2, width: last - first)
    }

    /// Per-column counts of non-transparent pixels in a 1× render of the real
    /// `CadenceTransport` laid out at `rowWidth`.
    private func inkColumnHeights(rowWidth: CGFloat) throws -> [Int] {
        let rowHeight: CGFloat = 60
        let renderer = ImageRenderer(
            content: CadenceTransport(core: makeCore(), theme: .graphite)
                .frame(width: rowWidth, height: rowHeight)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "ImageRenderer produced no image")
        XCTAssertEqual(image.width, Int(rowWidth), "the render must be 1 px per point")

        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return (0..<image.width).map { x in
            (0..<image.height).reduce(into: 0) { count, y in
                if pixels[y * bytesPerRow + x * 4 + 3] > 8 { count += 1 }
            }
        }
    }
}
