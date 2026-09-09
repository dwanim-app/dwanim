import SwiftUI

// MARK: - CadenceControlID

/// The default face's controls a test can LOCATE by name.
///
/// SwiftUI draws its buttons inside the hosting view — no `NSButton` per control,
/// and no accessibility children for an in-process client — so an in-process click
/// harness cannot ask AppKit where a button is (see the "Locating a SwiftUI button"
/// note in `CadenceTransportNextButtonTests`). Earlier harnesses recomputed each
/// button's position from the layout constants, which only works for a single
/// fixed-height row. The whole `DefaultPlayerView` (title bar + hero + queue + EQ)
/// stacks text of locale- and font-dependent height, so its controls instead REPORT
/// their own laid-out frames through a `CadenceControlProbe` when one is supplied.
enum CadenceControlID: Hashable {
    case previous, playPause, stop, next
    case eqOn
    case eqPreset(EQPreset)
    case eqPreamp
    case eqBand(Int)
    /// The hero well while it shows the spectrum (a queue with content).
    case visualizerWell
    /// The hero well while it shows the empty-queue call to action.
    case emptyWell
    case ctaAddFiles, ctaAddFolder, ctaPlaySample
    /// The now-playing title `Text` (F4) — located so its rendered pixels can be
    /// read; it is not a control.
    case nowTitle
}

// MARK: - CadenceControlProbe

/// A TEST-SUPPORT seam: collects the on-screen frame of every control that opts in
/// via `.cadenceControl(_:probe:)`, in SwiftUI's global coordinate space (the
/// hosting view's bounds, origin top-left, y down).
///
/// Production passes `nil` everywhere, and with a `nil` probe the modifier is a
/// no-op that adds nothing to the view tree — so the shipping face carries no
/// geometry readers and no per-control state. Only `DwanimItUITests` (via
/// `@testable import`) ever constructs one. Internal on purpose: it is not API.
///
/// A frame is REMOVED when its control leaves the tree (the CTA buttons vanish the
/// moment a track lands; the visualizer well appears in their place), so "is this
/// control on screen right now?" is answered by `frame(of:) == nil`.
@MainActor
final class CadenceControlProbe {

    private var frames: [CadenceControlID: CGRect] = [:]

    init() {}

    /// The last laid-out frame of `id`, or `nil` when it is not in the tree.
    func frame(of id: CadenceControlID) -> CGRect? { frames[id] }

    /// Every control currently on screen.
    var visible: Set<CadenceControlID> { Set(frames.keys) }

    func record(_ id: CadenceControlID, frame: CGRect) { frames[id] = frame }
    func forget(_ id: CadenceControlID) { frames[id] = nil }
}

// MARK: - View.cadenceControl

extension View {
    /// Report this view's laid-out frame to `probe` under `id`. With a `nil`
    /// probe (production) this returns the view unchanged.
    @ViewBuilder
    func cadenceControl(_ id: CadenceControlID, probe: CadenceControlProbe?) -> some View {
        if let probe {
            background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { probe.record(id, frame: frame) }
                        .onChange(of: frame) { _, new in probe.record(id, frame: new) }
                        .onDisappear { probe.forget(id) }
                }
            )
        } else {
            self
        }
    }
}
