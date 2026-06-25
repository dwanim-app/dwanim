import AppKit
import CoreGraphics
import Foundation
import PlaybackKit
import PlayerCore
import SkinKit
import SkinKitImageIO
import SkinRender

// SkinHarness EQ mode: a dev-only path that opens the classic equalizer (EQ)
// window for a skin and makes it INTERACTIVE — dragging a slider really changes
// the sound, because the slider drives the live `PlayerCore` equalizer, which
// mirrors to the real `AVAudioUnitEQ` in the engine (the DSP proven in the EQ
// engine increment). `main.swift` dispatches here when `--eq` is present.
//
// Usage:
//   SkinHarness --eq <skin.wsz> <audiofile> [<audiofile>...] [--scale N]
//
// Flow:
//   1. Load the skin (SkinLoader + ImageIOBitmapDecoder) and confirm the EQ face
//      composes (EQWindowComposer needs eqmain.bmp/background).
//   2. Build a PlayerCore over the concrete AVAudioEnginePlayer; load the given
//      audio files as a playlist and start playback so the EQ is audible.
//   3. Open an NSWindow hosting an EQ content view that draws
//      EQWindowComposer.compose(...) with the CURRENT PlayerCore.equalizer values,
//      scaled nearest-neighbor (same scale + flip pipeline as --interactive).
//   4. mouseDown / mouseDragged -> ControlHitTest.skinPoint (the SAME verified
//      flip used elsewhere) -> EQWindowLayout.slider(atSkinX:) picks the column ->
//      EQWindowLayout.thumbGain(forThumbTopY:) maps the skin-space y to a gain ->
//      PlayerCore.setEQPreamp / setEQBand drives the real AVAudioUnitEQ -> recompose
//      so the thumb follows the cursor AND the sound changes live.
//   5. A click on the ON button region toggles PlayerCore.setEQEnabled.
//
// DEFERRED (documented, not built here): the colored band-graph response CURVE
// line over the graph area; the AUTO button (no auto-preset flag is modelled —
// it is a no-op); the windowshade (rolled-up) variant and drag-resize (the EQ
// window is a fixed 275x116, unlike the resizable PLEDIT).
//
// NO text is drawn (the preset display is deferred), so there are no brand names.

// MARK: - Argument parsing

/// Parsed EQ-mode arguments: the skin path, one-or-more audio files, the zoom.
private struct EQArguments {
    var skinPath: String
    var audioPaths: [String]
    var scale: Int
}

private let eqUsage =
    "Usage: SkinHarness --eq <skin.wsz> <audiofile> [<audiofile>...] [--scale N]"

/// Parse the EQ-mode argument vector. `argv` is the full process argument list;
/// the `--eq` flag and everything after it is consumed here. The first non-option
/// positional is the skin path; the rest are audio files. `--scale N` may appear
/// anywhere after the flag.
private func parseEQArguments(_ argv: [String]) -> EQArguments {
    guard let flagIndex = argv.firstIndex(of: "--eq") else {
        eqFail("Internal: --eq dispatched without the flag present.")
    }

    var positionals: [String] = []
    var scale = 2

    var index = flagIndex + 1
    while index < argv.count {
        let arg = argv[index]
        switch arg {
        case "--scale":
            guard index + 1 < argv.count, let value = Int(argv[index + 1]), (1...16).contains(value) else {
                eqFail(
                    "--scale requires an integer in 1...16 (larger values overflow the "
                        + "scaled-image dimensions). \(eqUsage)"
                )
            }
            scale = value
            index += 2
        default:
            positionals.append(arg)
            index += 1
        }
    }

    guard let skinPath = positionals.first else {
        eqFail("Missing required skin path. \(eqUsage)")
    }
    let audioPaths = Array(positionals.dropFirst())
    guard !audioPaths.isEmpty else {
        eqFail("Missing required audio file(s). \(eqUsage)")
    }

    return EQArguments(skinPath: skinPath, audioPaths: audioPaths, scale: scale)
}

// MARK: - Live EQ content view

/// A content view that draws a `CGImage` with nearest-neighbor scaling (like the
/// main-window interactive view) but forwards mouse-down AND mouse-drag to a
/// controller so a slider can be dragged continuously.
///
/// Coordinate note: this is a default (NON-flipped) `NSView`, origin bottom-left,
/// y increasing UPWARD. The composed EQ image is top-left origin (y down). The
/// view forwards the raw view-space point (plus its own height); mapping it back
/// to skin space (undo scale + y-flip) is the pure `ControlHitTest.skinPoint(...)`
/// the controller drives — the view carries no coordinate math.
final class EQSkinView: NSView {
    private var image: CGImage

    /// Called on mouse-down AND on each mouse-drag, with the point in this view's
    /// coordinate space (non-flipped, bottom-left origin, scaled points) plus the
    /// view's height, so the controller can map it to skin space.
    var onMousePoint: ((_ viewX: Double, _ viewY: Double, _ viewHeight: Double, _ isDown: Bool) -> Void)?

    init(image: CGImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Swap the displayed image and request a redraw. Same pixel size each tick.
    func update(image: CGImage) {
        self.image = image
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        forward(event, isDown: true)
    }

    override func mouseDragged(with event: NSEvent) {
        forward(event, isDown: false)
    }

    private func forward(_ event: NSEvent, isDown: Bool) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        onMousePoint?(Double(viewPoint.x), Double(viewPoint.y), Double(bounds.height), isDown)
    }
}

// MARK: - Controller

/// Owns the live EQ window: the skin, the core, the view. It recomposes the EQ
/// face from the current `PlayerCore.equalizer` values and swaps the view's image
/// whenever a gesture changes the state, and routes mouse-down / drag to the
/// right slider (or the ON button).
///
/// The drag math is the payoff: a view-space point becomes a skin-space point via
/// the SAME verified flip as the main window (`ControlHitTest.skinPoint`); the
/// skin x picks the slider column (`EQWindowLayout.slider(atSkinX:)`); the skin y,
/// adjusted to the thumb's TOP-LEFT the same way the draw places it (cursor under
/// the thumb's vertical centre), is inverted to a gain
/// (`EQWindowLayout.thumbGain(forThumbTopY:)`); and that gain is pushed to
/// `PlayerCore`, which drives the real `AVAudioUnitEQ`.
private final class EQController: NSObject, NSWindowDelegate, NSApplicationDelegate {
    private let skin: Skin
    private let core: PlayerCore
    private let view: EQSkinView
    private let scale: Int

    /// The slider currently being dragged (set on a mouse-down that grabbed a
    /// slider), so a subsequent drag keeps adjusting THAT slider even if the
    /// cursor wanders horizontally off its column. `nil` when the gesture started
    /// on the ON button or empty face.
    private var draggingSlider: EQWindowLayout.EQSlider?

    init(skin: Skin, core: PlayerCore, view: EQSkinView, scale: Int) {
        self.skin = skin
        self.core = core
        self.view = view
        self.scale = scale
        super.init()

        view.onMousePoint = { [weak self] viewX, viewY, viewHeight, isDown in
            self?.handleMouse(viewX: viewX, viewY: viewY, viewHeight: viewHeight, isDown: isDown)
        }
    }

    /// Draw the first frame from the current state. (The EQ face only changes in
    /// response to a gesture, so there is no animation timer — unlike the main
    /// window's spectrum.)
    func start() {
        redraw()
    }

    // MARK: NSWindowDelegate / NSApplicationDelegate

    /// The window is closing — terminate so the run loop exits cleanly.
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Mouse -> DSP

    /// Map a view-space point to skin space (the SAME verified flip used by the
    /// main window) and act on it: a mouse-down on the ON button toggles enable; a
    /// mouse-down on a slider column begins a drag; a drag (or down) on a slider
    /// sets that slider's gain from the cursor y and pushes it to the engine.
    private func handleMouse(viewX: Double, viewY: Double, viewHeight: Double, isDown: Bool) {
        let point = ControlHitTest.skinPoint(
            viewX: viewX, viewY: viewY, viewHeight: viewHeight, scale: scale
        )

        if isDown {
            // A fresh gesture: first check the ON button, then a slider column.
            if hitsOnButton(skinX: point.x, skinY: point.y) {
                core.setEQEnabled(!core.equalizer.enabled)
                draggingSlider = nil
                redraw()
                return
            }
            draggingSlider = EQWindowLayout.slider(atSkinX: point.x)
        }

        // For a down or a drag, adjust the slider grabbed at mouse-down (if any).
        guard let slider = draggingSlider else { return }
        applyGain(to: slider, fromSkinY: point.y)
        redraw()
    }

    /// Whether a skin-space point lands on the ON button's footprint (its layout
    /// origin + the ON sprite size; falls back to the canonical 25x12 if the
    /// sprite is absent so the toggle still works on a sparse skin).
    private func hitsOnButton(skinX: Int, skinY: Int) -> Bool {
        let origin = EQWindowLayout.onButtonOrigin
        let size = SpriteCoordinates.equalizerWindow["eqmain.bmp"]?
            .first { $0.name == "onButtonOff" }
        let width = size?.width ?? 25
        let height = size?.height ?? 12
        return skinX >= origin.x && skinX < origin.x + width
            && skinY >= origin.y && skinY < origin.y + height
    }

    /// Convert a cursor skin-space y to a gain and push it to the engine for the
    /// given slider. The cursor sits at the thumb's VERTICAL CENTRE (matching how
    /// `thumbTopY` places the body), so the thumb top-left y is `skinY -
    /// thumbHeight/2`; `thumbGain(forThumbTopY:)` clamps that into ±12 dB. The
    /// resulting gain drives the real `AVAudioUnitEQ` through `PlayerCore`.
    private func applyGain(to slider: EQWindowLayout.EQSlider, fromSkinY skinY: Int) {
        let thumbTopY = skinY - EQWindowLayout.thumbHeight / 2
        let gain = EQWindowLayout.thumbGain(forThumbTopY: thumbTopY)
        switch slider {
        case .preamp:
            core.setEQPreamp(gain)
        case .band(let index):
            core.setEQBand(index, dB: gain)
        }
    }

    // MARK: Redraw

    /// Recompose the EQ face from the live `PlayerCore.equalizer` state and swap
    /// the view image. Pure compose (no text overlay — the preset display is
    /// deferred), bridged to a CGImage and nearest-neighbor scaled.
    private func redraw() {
        let eq = core.equalizer
        guard let composed = EQWindowComposer.compose(
            skin,
            enabled: eq.enabled,
            preamp: eq.preamp,
            bands: eq.bands
        ) else {
            return
        }
        guard let image = CGImageConversion.makeImage(from: composed) else { return }
        let scaled: (image: CGImage, width: Int, height: Int)
        do {
            scaled = try scaledImage(image, scale: scale)
        } catch {
            return
        }
        view.update(image: scaled.image)
    }
}

// Hold the controller for the process lifetime so it is not deallocated once the
// run loop starts (the run loop owns no strong reference to it).
private var liveEQController: EQController?

// MARK: - Entry point

/// Run the EQ mode and never return: load the skin + audio, open the EQ window,
/// start playback, and drive the main run loop (exits the process itself).
func runEQMode() -> Never {
    let arguments = parseEQArguments(CommandLine.arguments)

    // Load + compose the skin (fault checks mirror the other window paths).
    let skinURL = URL(fileURLWithPath: arguments.skinPath)
    let skinData: Data
    do {
        skinData = try Data(contentsOf: skinURL)
    } catch {
        eqFail("Could not read skin file at \(arguments.skinPath): \(error.localizedDescription)")
    }

    let skin: Skin
    do {
        skin = try SkinLoader.load(skinData, decoder: ImageIOBitmapDecoder())
    } catch {
        eqFail("Could not load skin at \(arguments.skinPath): \(error)")
    }

    // Confirm the EQ face composes (needs eqmain.bmp/background).
    guard EQWindowComposer.compose(skin, enabled: false, preamp: 0, bands: []) != nil else {
        eqFail(
            "Could not compose the EQ window for skin at \(arguments.skinPath): "
                + "no EQ-window background (eqmain.bmp/background)."
        )
    }

    // Build the core and load the audio files; each Track.title is the file's own
    // name stem (the user's file). Start playback so the EQ is audible.
    let tracks = arguments.audioPaths.map { path -> Track in
        let url = URL(fileURLWithPath: path)
        let stem = url.deletingPathExtension().lastPathComponent
        return Track(url: url, title: stem)
    }
    let engine = AVAudioEnginePlayer()
    let core = PlayerCore(engine: engine)
    core.load(tracks)
    // Enable the equalizer and start playback so a drag is immediately audible.
    core.setEQEnabled(true)
    core.play()

    openEQWindow(skin: skin, core: core, scale: arguments.scale)
}

/// Build and show the EQ window (a plain titled window — the EQ face is a fixed
/// 275x116 rectangle, so no region mask is needed), then start the redraw and run
/// the app. Never returns.
private func openEQWindow(skin: Skin, core: PlayerCore, scale: Int) -> Never {
    let eq = core.equalizer
    guard let base = EQWindowComposer.compose(
            skin, enabled: eq.enabled, preamp: eq.preamp, bands: eq.bands
          ),
          let image = CGImageConversion.makeImage(from: base) else {
        eqFail("Could not build an image from the composed EQ window.")
    }

    let scaled: (image: CGImage, width: Int, height: Int)
    do {
        scaled = try scaledImage(image, scale: scale)
    } catch {
        eqFail("Failed to render the EQ window: \(error)")
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let contentRect = NSRect(x: 0, y: 0, width: scaled.width, height: scaled.height)
    let contentView = EQSkinView(image: scaled.image, frame: contentRect)

    let controller = EQController(skin: skin, core: core, view: contentView, scale: scale)
    liveEQController = controller

    let window = NSWindow(
        contentRect: contentRect,
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "SkinHarness EQ"
    window.delegate = controller
    window.contentView = contentView
    window.center()
    window.makeKeyAndOrderFront(nil)

    app.delegate = controller
    controller.start()

    app.activate(ignoringOtherApps: true)
    app.run()

    // app.run() does not return in normal use; treat a return as a clean stop.
    exit(0)
}

// MARK: - Headless snapshot

// Headless EQ-window snapshot: compose the EQ face at a representative state (a
// curve dialed in + the equalizer ON) and write it to a PNG offscreen — NO
// NSWindow, no run loop, no audio — so the interactive face can be verified
// without opening the blocking window. It runs the SAME EQWindowComposer the live
// window draws, so the snapshot is faithful to what a user sees.
//
// Usage:
//   SkinHarness --eq-snapshot <skin.wsz> <out.png> [--scale N]

/// A representative non-flat curve so the snapshot shows the thumbs spread across
/// the track (a gentle "smile": boost the lows and highs, cut the mids), plus a
/// preamp lift. Exercises the gain→thumb-y placement across the full ±12 range.
private let snapshotBands: [Double] = [12, 8, 4, 0, -4, -4, 0, 4, 8, 12]
private let snapshotPreamp: Double = 6

func runEQSnapshotMode() -> Never {
    guard let flagIndex = CommandLine.arguments.firstIndex(of: "--eq-snapshot") else {
        eqFail("Internal: --eq-snapshot dispatched without the flag present.")
    }

    var positionals: [String] = []
    var scale = 2
    var index = flagIndex + 1
    while index < CommandLine.arguments.count {
        let arg = CommandLine.arguments[index]
        if arg == "--scale" {
            guard index + 1 < CommandLine.arguments.count,
                  let value = Int(CommandLine.arguments[index + 1]), (1...16).contains(value) else {
                eqFail("--scale requires an integer in 1...16.")
            }
            scale = value
            index += 2
        } else {
            positionals.append(arg)
            index += 1
        }
    }

    guard positionals.count >= 2 else {
        eqFail("Usage: SkinHarness --eq-snapshot <skin.wsz> <out.png> [--scale N]")
    }
    let skinPath = positionals[0]
    let outPath = positionals[1]

    let url = URL(fileURLWithPath: skinPath)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        eqFail("Could not read skin at \(skinPath): \(error.localizedDescription)")
    }
    let skin: Skin
    do {
        skin = try SkinLoader.load(data, decoder: ImageIOBitmapDecoder())
    } catch {
        eqFail("Could not load skin at \(skinPath): \(error)")
    }

    // Compose the EQ face with the equalizer ON and the representative curve — the
    // SAME composer the live window uses.
    guard let composed = EQWindowComposer.compose(
            skin, enabled: true, preamp: snapshotPreamp, bands: snapshotBands
          ),
          let image = CGImageConversion.makeImage(from: composed) else {
        eqFail("Could not compose the EQ window for \(skinPath) (no eqmain.bmp?).")
    }

    do {
        let scaled = try scaledImage(image, scale: scale)
        try writePNG(scaled.image, to: URL(fileURLWithPath: outPath))
        print("Wrote \(outPath) (\(scaled.width)x\(scaled.height) px)")
        exit(0)
    } catch {
        eqFail("Could not write the EQ snapshot PNG to \(outPath): \(error)")
    }
}

// MARK: - Failure handling

/// Print `message` to stderr and exit non-zero. Mirrors the other modes' `fail`,
/// kept local so the EQ mode is self-contained.
private func eqFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
