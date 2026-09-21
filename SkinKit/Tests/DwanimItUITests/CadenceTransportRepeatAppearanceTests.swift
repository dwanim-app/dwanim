import AppKit
import SwiftUI
import XCTest
import GUIFocusHarness
import PlayerCore
@testable import DwanimItUI

// MARK: - CadenceTransportRepeatAppearanceTests
//
// The APPEARANCE half of the transport work. `CadenceTransportRepeatCycleTests`
// proves the three Repeat states and the disabled skips BEHAVE correctly; nothing
// there proves they LOOK different, and that is most of what the owner asked for:
//
//   A. "give each state a distinct, legible visual ... plus a distinct
//      accessibility label";
//   C. "SwiftUI `.disabled` plus a visibly reduced opacity ... a disabled control
//      must not swallow hover/press affordances".
//
// Without this file the whole visual layer is free: ONE could drop its badge and
// become indistinguishable from ALL, `.all` could render unlit, the disabled `▶▶`
// could render at full brightness, and the suite would stay green. Three mutants
// that used to pass and now fail are listed against the tests that catch them.
//
// Note the direction of the width assertions here: ALL and ONE deliberately light
// pills of the SAME extent (that is the layout fix — see
// `CadenceTransportRepeatWidthTests`), and what separates them is ink in the
// pill's trailing badge corner, not its width.
//
// ## How "looks different" is measured
// The view is hosted in a real window and RENDERED (`cacheDisplay(in:to:)` into a
// bitmap), then the pixels are read back. That is a genuine render of the shipping
// SwiftUI view — the same path the runtime screenshots exercise — and it needs no
// private SwiftUI class names, so it cannot rot into a false green when AppKit's
// internal view classes are renamed.
//
// Two measurements are used:
//   * `litColumns(_:)` — the horizontal extent of the accent-filled pill, found
//     by scanning columns for ink coverage. A pill's WIDTH is set by its text, so
//     this measures the rendered label without ever reading the label back.
//   * `meanLuma(_:_:)` — average ink over a rect, for "is this control dimmed?"
//     and "is this pill lit?".
//
// Under `swift test` the String Catalog is copied verbatim (never compiled), so
// `Text("Repeat", bundle: .module)` renders its English source key; the expected
// widths below are derived from that same string in the same 11 pt font rather
// than hard-coded.
@MainActor
final class CadenceTransportRepeatAppearanceTests: XCTestCase {

    private var window: NSWindow!
    private var hosting: NSHostingView<CadenceTransport>!
    private var engine: TransportRecordingEngine!
    private var core: PlayerCore!

    private let trackCount = 4

    // MARK: Lifecycle

    override func setUp() async throws {
        _ = NSApplication.shared
        engine = TransportRecordingEngine()
        core = PlayerCore(engine: engine)
        core.load((0..<trackCount).map {
            Track(url: URL(fileURLWithPath: "/tmp/dwanim-appearance-harness/track\($0).mp3"),
                  title: "Track \($0)", duration: 120)
        })

        hosting = NSHostingView(rootView: CadenceTransport(core: core, theme: .graphite))
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 60)
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting

        // Dispatch-model step 1, through the ONE shared seam: this process must
        // own a KEY window or no synthesized click can land. `establishFocus`
        // takes the front — and CANNOT skip: gating here would make every test
        // in the class conditional on the environment, including the many below
        // that never synthesize an event. The gate lives at the point of use,
        // in `click`, and re-observes the front on both sides of it.
        GUIFocusHarness.establishFocus(window, harness: "CadenceTransportRepeatAppearanceTests")
        pump(0.2)
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.close()
        window = nil
        hosting = nil
    }

    // MARK: Event plumbing (the established in-process click model)

    private func pump(_ seconds: TimeInterval) {
        GUIFocusHarness.pump(seconds)
    }

    /// Queue the UP first, then hand the DOWN to the window — inside the shared
    /// gate, which re-observes the front immediately before the event and again
    /// after it has been drained. A front missing on either side SKIPS the test
    /// instead of letting an inert click be reported as a product bug.
    private func click(at p: NSPoint, file: StaticString = #filePath, line: UInt = #line) throws {
        func event(_ type: NSEvent.EventType) -> NSEvent {
            guard let e = NSEvent.mouseEvent(
                with: type, location: p, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { fatalError("NSEvent.mouseEvent returned nil for \(type)") }
            return e
        }
        try GUIFocusHarness.synthesize(
            in: window, harness: "CadenceTransportRepeatAppearanceTests", file: file, line: line
        ) {
            NSApp.postEvent(event(.leftMouseUp), atStart: false)
            window.sendEvent(event(.leftMouseDown))
            pump(0.25)
        }
    }

    /// Put the view into `mode` and let the render settle.
    private func render(_ mode: RepeatMode) {
        core.repeatMode = mode
        pump(0.3)
    }

    // MARK: Pixel measurement

    /// Render the live view into a bitmap. This is the real SwiftUI draw, not a
    /// re-implementation of it.
    private func capture() -> NSBitmapImageRep {
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else {
            fatalError("the hosting view produced no bitmap to draw into")
        }
        hosting.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    /// Pixels per point, so the assertions can stay in layout points on any
    /// backing scale.
    private func scale(_ rep: NSBitmapImageRep) -> CGFloat {
        CGFloat(rep.pixelsWide) / hosting.bounds.width
    }

    /// Mean ink (alpha-weighted luminance) over a rect given in POINTS. `0` is
    /// "nothing drawn here".
    private func meanLuma(_ rep: NSBitmapImageRep, _ rect: NSRect) -> Double {
        let s = scale(rep)
        var total = 0.0
        var samples = 0
        for x in Int(rect.minX * s)..<Int(rect.maxX * s) {
            for y in Int(rect.minY * s)..<Int(rect.maxY * s) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { continue }
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let a = Double(c.alphaComponent)
                total += a * (0.299 * Double(c.redComponent)
                              + 0.587 * Double(c.greenComponent)
                              + 0.114 * Double(c.blueComponent))
                samples += 1
            }
        }
        return samples == 0 ? 0 : total / Double(samples)
    }

    /// The fraction of a column's pixels (over the 24 pt pill band) that carry
    /// ink. A LIT pill fills that band edge to edge, so its columns come back at
    /// ~1.0; an unlit pill draws only glyph strokes, so even a column through a
    /// letter's stem covers well under half the band. The 0.6 threshold sits in
    /// that gap.
    private func coverage(_ rep: NSBitmapImageRep, column: CGFloat) -> Double {
        let s = scale(rep)
        var inked = 0
        var samples = 0
        for y in Int(5 * s)..<Int(29 * s) {
            for x in Int(column * s)..<Int((column + 1) * s) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { continue }
                samples += 1
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.15 {
                    inked += 1
                }
            }
        }
        return samples == 0 ? 0 : Double(inked) / Double(samples)
    }

    /// The x range (in POINTS) spanned by the LIT pill in the left toggle zone.
    ///
    /// Because a pill sizes to its TEXT, this measures the rendered label's width
    /// without ever reading the label back — which is what proves `.all` and
    /// `.one` light a pill of exactly the same extent (the no-re-flow fix), and
    /// that `.off` lights none at all.
    /// `testUnlitPillsProduceNoLitColumns` is the scan's own control: with
    /// nothing lit it must report nothing.
    private func litColumns(_ rep: NSBitmapImageRep) -> ClosedRange<CGFloat>? {
        var first: CGFloat?
        var last: CGFloat?
        for column in stride(from: CGFloat(0), to: 176, by: 1) where coverage(rep, column: column) > 0.6 {
            if first == nil { first = column }
            last = column
        }
        guard let first, let last else { return nil }
        return first...(last + 1)
    }

    // MARK: Derived geometry (the same three inputs the view lays out from)

    /// A pill's laid-out width: its text in the SAME 11 pt system font the view
    /// uses, plus `.padding(.horizontal, 8)` a side.
    private func pillWidth(_ text: String, bold: Bool = false) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: bold ? .semibold : .regular)
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width) + 16
    }

    private var shuffleWidth: CGFloat { pillWidth("Shuffle") }
    private var repeatWordWidth: CGFloat { pillWidth("Repeat") }
    private var repeatPillX: CGFloat { shuffleWidth + 4 }
    /// The EQ pill sits immediately after the Repeat pill — and, because the
    /// Repeat pill's width no longer depends on its mode, at the SAME x in all
    /// three states. That is what `testTheToggleRowDoesNotReflowAcrossTheRepeatCycle`
    /// proves by clicking it.
    private var eqPillX: CGFloat { repeatPillX + repeatWordWidth + 4 }
    private var eqPillWidth: CGFloat { pillWidth("EQ", bold: true) }

    /// The top-trailing corner of the Repeat pill, where the repeat-one "1" is
    /// stamped (`TransportToggle.badgeGlyph`): the last 8 pt of the pill — its
    /// own horizontal padding, empty by construction — over the top half of the
    /// 24 pt band.
    private var repeatBadgeRect: NSRect {
        NSRect(x: repeatPillX + repeatWordWidth - 8, y: 5, width: 8, height: 12)
    }

    /// The centre-cluster button rects, mirroring `CadenceTransport`'s layout.
    private enum TransportButton: CaseIterable {
        case previous, playPause, stop, next
        var width: CGFloat { self == .playPause ? 44 : 32 }
    }

    private func rect(of button: TransportButton) -> NSRect {
        let sideZone: CGFloat = 176
        let zoneSpacing: CGFloat = 12
        let clusterSpacing: CGFloat = 6
        let centreBoxX = sideZone + zoneSpacing
        let centreBoxWidth = hosting.bounds.width - 2 * (sideZone + zoneSpacing)
        let widths = TransportButton.allCases.map(\.width)
        let clusterWidth = widths.reduce(0, +) + clusterSpacing * CGFloat(widths.count - 1)
        var x = centreBoxX + (centreBoxWidth - clusterWidth) / 2
        for candidate in TransportButton.allCases {
            if candidate == button { break }
            x += candidate.width + clusterSpacing
        }
        let height: CGFloat = button == .playPause ? 34 : 28
        return NSRect(x: x, y: (hosting.bounds.height - height) / 2, width: button.width, height: height)
    }

    // MARK: - A. The three states are VISIBLY three

    /// The scan's own control: with repeat off and shuffle off, NO pill is lit,
    /// so the measurement that the other tests rely on reports nothing. Without
    /// this, a scan that always found ink would make the width tests meaningless.
    func testUnlitPillsProduceNoLitColumns() {
        render(.off)
        XCTAssertFalse(core.isShuffle)
        XCTAssertNil(litColumns(capture()),
                     "nothing in the left zone is lit while Shuffle, Repeat and EQ are all off")
    }

    /// MUTANT-KILLER (M11: `repeatLabel` collapsed so `.all` and `.one` render
    /// indistinguishably). The two on-states light a pill of exactly the SAME
    /// extent — that is the layout fix, and it is asserted here so nobody
    /// "restores" the distinction by lengthening the label again — while the ink
    /// inside the pill's trailing badge corner differs, which is what still
    /// tells a sighted listener `.all` from `.one`.
    ///
    /// Before the fix this test's predecessor asserted the opposite (a WIDER
    /// pill in `.one`); in Japanese that extra width pushed the row 4 pt past
    /// its 176 pt zone and shrank every label in it. See
    /// `CadenceTransportRepeatWidthTests` for the measured locale × state table.
    func testBothOnStatesLightAnIdenticalPillAndOnlyTheBadgeDiffers() {
        render(.all)
        let allCapture = capture()
        guard let allRun = litColumns(allCapture) else {
            return XCTFail("the .all state must light the Repeat pill")
        }
        render(.one)
        let oneCapture = capture()
        guard let oneRun = litColumns(oneCapture) else {
            return XCTFail("the .one state must light the Repeat pill")
        }

        XCTAssertEqual(allRun.lowerBound, repeatPillX, accuracy: 1.5,
                       "both states light the SAME pill, at the Repeat pill's x")
        XCTAssertEqual(oneRun.lowerBound, repeatPillX, accuracy: 1.5)

        let allWidth = allRun.upperBound - allRun.lowerBound
        let oneWidth = oneRun.upperBound - oneRun.lowerBound
        XCTAssertEqual(allWidth, repeatWordWidth, accuracy: 1.5,
                       #".all renders the "Repeat" label"#)
        XCTAssertEqual(oneWidth, allWidth, accuracy: 1.0,
                       "the pill must measure the same in both on-states — a "
                       + "state-dependent width re-flows the whole toggle row")

        // ...and yet the two are still visibly different, in the corner the
        // classic face stamps its own "1" into.
        let allBadge = meanLuma(allCapture, repeatBadgeRect)
        let oneBadge = meanLuma(oneCapture, repeatBadgeRect)
        XCTAssertGreaterThan(oneBadge, allBadge,
                             "the .one state must stamp a visible badge in the "
                             + "pill's trailing corner")
        XCTAssertGreaterThan(oneBadge - allBadge, 0.01,
                             "and the stamp must be more than a rounding wobble")
    }

    /// The no-re-flow requirement proved through real CLICKS rather than a
    /// measurement: ONE point, computed once, is clicked in each of the three
    /// repeat states, and it must land on the EQ pill every time.
    ///
    /// That is only true if the Repeat pill's width — and therefore everything
    /// to its right — is the same in off, all and one. When the ONE state
    /// rendered a longer label, this x fell inside the Repeat pill instead, and
    /// the click cycled repeat rather than toggling EQ.
    func testTheToggleRowDoesNotReflowAcrossTheRepeatCycle() throws {
        let eqCentre = NSPoint(x: eqPillX + eqPillWidth / 2, y: hosting.bounds.midY)

        for mode in [RepeatMode.off, .all, .one] {
            render(mode)
            let repeatBefore = core.repeatMode
            let eqBefore = core.equalizer.enabled

            try click(at: eqCentre)

            XCTAssertEqual(core.equalizer.enabled, !eqBefore,
                           "\(mode): the EQ pill must sit at the same x in every "
                           + "repeat state — this click missed it")
            XCTAssertEqual(core.repeatMode, repeatBefore,
                           "\(mode): and the click must NOT have landed on the Repeat pill")
        }
    }

    /// MUTANT-KILLER (M12c: the Repeat pill's `isActive` narrowed to
    /// `== .one`). `.all` must render LIT — a reachable mode that looks
    /// unreachable is the original bug's twin.
    func testBothOnStatesRenderLitAndOffRendersUnlit() {
        let pill = NSRect(x: repeatPillX, y: 5, width: repeatWordWidth, height: 24)

        render(.off)
        let off = meanLuma(capture(), pill)
        render(.all)
        let all = meanLuma(capture(), pill)
        render(.one)
        let one = meanLuma(capture(), pill)

        XCTAssertGreaterThan(all, off * 2,
                             ".all must be visibly LIT, not rendered like .off")
        XCTAssertGreaterThan(one, off * 2, ".one must be visibly lit too")
        XCTAssertEqual(all, one, accuracy: max(all, one) * 0.25,
                       "both on-states use the same lit treatment — the label is identical "
                       + "in both, and only the badge tells them apart")
    }

    // MARK: - A. The per-state accessibility label

    /// MUTANT-KILLER (M10, partially — see the note): the three states announce
    /// three DIFFERENT things, and none of them is merely the visible text. The
    /// `.off`/`.all` pair is the load-bearing one: they share a visible label, so
    /// without a per-state announcement VoiceOver could not tell them apart at
    /// all.
    ///
    /// - Note: The hosted view's accessibility tree is not reachable in-process
    ///   (an `NSHostingView` reports no accessibility children here), so this
    ///   pins the value the button is BUILT with and the choice it announces,
    ///   not the `.accessibilityLabel` modifier's own line.
    func testEachRepeatStateAnnouncesItsOwnLabel() {
        let announced = [RepeatMode.off, .all, .one].map { mode -> Text in
            core.repeatMode = mode
            return CadenceTransport.repeatToggle(core: core, theme: .graphite).announcedText
        }

        XCTAssertNotEqual(announced[0], announced[1], "OFF and ALL must not announce the same thing")
        XCTAssertNotEqual(announced[1], announced[2], "ALL and ONE must not announce the same thing")
        XCTAssertNotEqual(announced[0], announced[2], "OFF and ONE must not announce the same thing")

        for (mode, text) in zip([RepeatMode.off, .all, .one], announced) {
            XCTAssertEqual(text, CadenceTransport.repeatAccessibilityLabel(for: mode),
                           "\(mode) announces its own catalog string")
            XCTAssertNotEqual(text, CadenceTransport.repeatLabel(for: mode),
                              "\(mode)'s announcement is the state-carrying string, not the terse pill text")
        }
    }

    /// The Repeat pill is actually CONSTRUCTED with the per-state accessibility
    /// text (rather than leaving `accessibilityText` nil and falling back to the
    /// visible label), for every one of the three states.
    func testTheRepeatPillCarriesAnAccessibilityTextInEveryState() {
        for mode in [RepeatMode.off, .all, .one] {
            core.repeatMode = mode
            let toggle = CadenceTransport.repeatToggle(core: core, theme: .graphite)
            XCTAssertNotNil(toggle.accessibilityText,
                            "\(mode): the Repeat pill supplies its own accessibility label")
            XCTAssertEqual(toggle.accessibilityText, CadenceTransport.repeatAccessibilityLabel(for: mode))
            XCTAssertEqual(toggle.label, CadenceTransport.repeatLabel(for: mode))
            XCTAssertEqual(toggle.isActive, mode != .off, "\(mode): lit in both on-states")
        }
    }

    /// The fallback is real, not dead code: a pill with no accessibility text of
    /// its own (Shuffle, EQ) announces its visible label.
    func testATogglesWithoutItsOwnAccessibilityTextAnnouncesItsVisibleLabel() {
        let plain = TransportToggle(
            label: Text(verbatim: "EQ"), isActive: false, bold: true, theme: .graphite
        ) {}
        XCTAssertEqual(plain.announcedText, plain.label)
    }

    // MARK: - C. The disabled state LOOKS disabled

    /// MUTANT-KILLER (M12a: `.opacity(isEnabled ? 1 : disabledOpacity)` deleted).
    /// Parked on the last track with repeat off, the rendered `▶▶` really is
    /// dimmer — by the documented factor — while its neighbour `■`, which is
    /// live whenever a track is loaded (as one is here), is untouched. That neighbour is the control: it proves the
    /// change came from the disabled state and not from the whole row being
    /// re-rendered differently.
    func testTheDisabledNextButtonRendersDimmedAndItsLiveNeighbourDoesNot() {
        core.select(trackCount - 1)
        render(.off)
        XCTAssertFalse(core.canGoNext, "precondition: ▶▶ cannot act here")
        let dimmed = capture()
        let nextDim = meanLuma(dimmed, rect(of: .next))
        let stopDim = meanLuma(dimmed, rect(of: .stop))

        render(.all)
        XCTAssertTrue(core.canGoNext, "the SAME button, now live")
        let live = capture()
        let nextLive = meanLuma(live, rect(of: .next))
        let stopLive = meanLuma(live, rect(of: .stop))

        XCTAssertGreaterThan(nextLive, 0, "sanity: the ▶▶ glyph draws something")
        XCTAssertLessThan(nextDim, nextLive * 0.8, "a disabled ▶▶ must be VISIBLY dimmer")
        XCTAssertEqual(nextDim / nextLive, TransportIconButton.disabledOpacity, accuracy: 0.08,
                       "and dimmed by the documented factor")
        XCTAssertEqual(stopDim, stopLive, accuracy: 0.001,
                       "■ is live with a track loaded and must render identically in both passes")
    }

    /// The empty queue dims BOTH skips at once — the other disabled case the
    /// owner named, measured rather than assumed.
    func testAnEmptyQueueRendersBothSkipsDimmed() {
        core.select(1)
        render(.off)
        let full = capture()
        let nextLive = meanLuma(full, rect(of: .next))
        let previousLive = meanLuma(full, rect(of: .previous))

        core.load([])
        pump(0.3)
        XCTAssertFalse(core.canGoNext)
        XCTAssertFalse(core.canGoPrevious)
        let empty = capture()

        XCTAssertLessThan(meanLuma(empty, rect(of: .next)), nextLive * 0.8, "▶▶ dims")
        XCTAssertLessThan(meanLuma(empty, rect(of: .previous)), previousLive * 0.8, "◀◀ dims")
    }

    /// MUTANT-KILLER (M12b: `showsHover` reduced to plain `hovering`). A disabled
    /// button must not brighten or fill under the pointer — "looks live but is
    /// inert" is the whole complaint.
    ///
    /// - Note: SwiftUI's `onHover` reads the LIVE cursor, not a synthesized
    ///   event's location (verified: neither a posted `.mouseMoved` nor a direct
    ///   `mouseEntered:` to the tracking area's owner moves the rendered pixels),
    ///   so the hover STATE cannot be driven in-process. What is pinned here is
    ///   the gate the styling reads. The rendered-with-the-pointer-over-it case
    ///   is covered by a runtime screenshot instead.
    func testHoverStylingIsGatedOnTheButtonBeingAbleToAct() {
        XCTAssertTrue(TransportIconButton.showsHoverStyling(hovering: true, isEnabled: true),
                      "a live button brightens under the pointer")
        XCTAssertFalse(TransportIconButton.showsHoverStyling(hovering: true, isEnabled: false),
                       "a DISABLED button must not brighten under the pointer")
        XCTAssertFalse(TransportIconButton.showsHoverStyling(hovering: false, isEnabled: true))
        XCTAssertFalse(TransportIconButton.showsHoverStyling(hovering: false, isEnabled: false))
    }
}
