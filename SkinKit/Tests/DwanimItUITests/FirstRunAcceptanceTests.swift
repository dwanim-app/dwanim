import AppKit
import SwiftUI
import XCTest
import PlayerCore
@testable import DwanimItUI

// MARK: - FirstRunAcceptanceTests
//
// THE ACCEPTANCE HARNESS for App Review's 2.1(a) rejection of build 6: "the Play
// button and other adjustment buttons were unresponsive". On a fresh install the
// queue is EMPTY, and a reviewer with no music files saw a "live" player whose
// every control was dead: Play returned silently, ◀◀/▶▶ sat at a styling-like
// 0.5 opacity, ■ did nothing, the whole EQ bank was `.disabled` because EQ
// defaults off, the spectrum well animated as if playing, and the title read as
// the app's name.
//
// This file cold-starts the REAL default face (`DefaultPlayerView` — title bar +
// hero + queue + EQ, the same view `DwanimItPlayerScene` hosts) over a real
// `PlayerCore` on an inert recording engine with an EMPTY queue, in a real
// `NSWindow` with the process activated, and drives SYNTHESIZED `NSEvent`s
// through the window's normal event path — the established in-process click
// model (see `CadenceTransportNextButtonTests`). Nothing is faked at the view
// layer: every "the button works" assertion below is a real click on the real
// button.
//
// Controls are located through `CadenceControlProbe` (each opted-in control
// reports its own laid-out frame), because the full face stacks locale- and
// font-dependent text and cannot be positioned from layout constants the way
// the single-row transport harnesses are.
//
// Each test pins one of the seven approved fixes:
//   F1 the hero well is an unmissable call to action (Add Files… / Add Folder… /
//      Play Sample) while the queue is empty;
//   F2 Play on an empty queue invokes the add-files flow;
//   F3 no fake idle animation with nothing loaded (the loaded-but-paused drift
//      is kept, and measured as the control);
//   F4 the title line says "Nothing loaded" (asserted on the RENDERED pixels, not
//      just the pure mapping) and the clocks show dashes;
//   F5 the EQ bank is never dead — a slider or preset turns the equalizer on;
//   F6 disabled skips — and ■, which has nothing to halt — are unmistakably
//      disabled (≤ 0.3 opacity) and never reach the model;
//   plus the after-add case: once a track lands the face comes alive.
@MainActor
final class FirstRunAcceptanceTests: XCTestCase {

    private var window: NSWindow!
    private var hosting: NSHostingView<DefaultPlayerView>!
    private var engine: TransportRecordingEngine!
    private var core: PlayerCore!
    private var model: PlayerViewModel!
    private var probe: CadenceControlProbe!

    /// The app-tier handlers the face is wired to, counted.
    private var addFilesCalls = 0
    private var addFolderCalls = 0
    private var playSampleCalls = 0

    // MARK: Lifecycle

    override func setUp() async throws {
        _ = NSApplication.shared
        engine = TransportRecordingEngine()
        core = PlayerCore(engine: engine)
        model = PlayerViewModel()
        probe = CadenceControlProbe()
        addFilesCalls = 0
        addFolderCalls = 0
        playSampleCalls = 0
        host(withSample: true)
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.close()
        window = nil
        hosting = nil
    }

    /// Cold-start the real face over the current (empty) core, EXACTLY as the app
    /// wires it: the footer/CTA add handlers and the core's empty-queue Play seam all
    /// route to the same app-tier "add files" flow.
    private func host(withSample: Bool) {
        window?.orderOut(nil)
        window?.close()
        // A fresh probe per host: the old tree's frames must not outlive it.
        probe = CadenceControlProbe()

        core.onPlayWithEmptyQueue = { [unowned self] in addFilesCalls += 1 }
        let view = DefaultPlayerView(
            core: core,
            model: model,
            appearance: AppearanceStore(),
            onAddFiles: { [unowned self] in addFilesCalls += 1 },
            onAddFolder: { [unowned self] in addFolderCalls += 1 },
            onPlaySample: withSample ? { [unowned self] in playSampleCalls += 1 } : nil,
            probe: probe
        )
        hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(
            x: 0, y: 0,
            width: DefaultPlayerView.compactWidth,
            height: fitting.height > 100 ? fitting.height : 760
        )
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting

        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date(timeIntervalSinceNow: 3)
        repeat {
            window.makeKeyAndOrderFront(nil)
            pump(0.1)
        } while !window.isKeyWindow && Date() < deadline
        pump(0.3) // let SwiftUI lay the whole face out and the probe fill
    }

    private static func track(_ index: Int) -> Track {
        Track(url: URL(fileURLWithPath: "/tmp/dwanim-first-run-harness/track\(index).mp3"),
              title: "Someone - Track \(index)", duration: 120)
    }

    // MARK: Event plumbing (the established in-process click model)

    private func pump(_ seconds: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        repeat {
            while let event = NSApp.nextEvent(
                matching: .any, until: Date(timeIntervalSinceNow: 0.01),
                inMode: .default, dequeue: true
            ) {
                NSApp.sendEvent(event)
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
    }

    private func mouseEvent(_ type: NSEvent.EventType, at p: NSPoint) -> NSEvent {
        guard let e = NSEvent.mouseEvent(
            with: type, location: p, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ) else { fatalError("NSEvent.mouseEvent returned nil for \(type)") }
        return e
    }

    /// Queue the UP first, then hand the DOWN to the window (so a control that
    /// runs its own tracking loop cannot block), then drain.
    private func click(at p: NSPoint) {
        NSApp.postEvent(mouseEvent(.leftMouseUp, at: p), atStart: false)
        window.sendEvent(mouseEvent(.leftMouseDown, at: p))
        pump(0.25)
    }

    // MARK: Locating a control through the probe

    /// The control's frame in SwiftUI's global space (origin top-left of the
    /// hosting view, y down), or a failure naming what is missing.
    private func frame(of id: CadenceControlID, file: StaticString = #filePath, line: UInt = #line) throws -> CGRect {
        try XCTUnwrap(probe.frame(of: id), "\(id) is not on screen", file: file, line: line)
    }

    /// A SwiftUI-global point converted to WINDOW coordinates for `NSEvent`.
    ///
    /// MEASURED: inside an `NSWindow`, SwiftUI's `.global` space is the WINDOW's
    /// frame, origin top-left, title bar included (the hero well reported y = 82 =
    /// 28 pt of title bar + 40 pt of Cadence title bar + 14 pt of hero padding).
    /// `NSEvent` locations are window-base coordinates, origin bottom-left, so
    /// only the y axis flips.
    private func windowPoint(_ p: CGPoint) -> NSPoint {
        NSPoint(x: p.x, y: window.frame.height - p.y)
    }

    /// A SwiftUI-global rect moved into the HOSTING view's bitmap space (top-down
    /// rows, origin at the content view's top-left — i.e. below the title bar).
    private func bitmapRect(_ global: CGRect) -> CGRect {
        global.offsetBy(dx: 0, dy: -(window.frame.height - hosting.bounds.height))
    }

    /// Real-click the centre of a control.
    private func clickControl(_ id: CadenceControlID, file: StaticString = #filePath, line: UInt = #line) throws {
        let f = try frame(of: id, file: file, line: line)
        click(at: windowPoint(CGPoint(x: f.midX, y: f.midY)))
    }

    /// Real-click a control at a fraction of its own height (0 = top edge).
    private func clickControl(_ id: CadenceControlID, atHeightFraction fraction: CGFloat) throws {
        let f = try frame(of: id)
        click(at: windowPoint(CGPoint(x: f.midX, y: f.minY + f.height * fraction)))
    }

    // MARK: Pixels

    /// Render the live view (the real SwiftUI draw) into a bitmap.
    private func capture() -> NSBitmapImageRep {
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else {
            fatalError("the hosting view produced no bitmap to draw into")
        }
        hosting.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    private func scale(_ rep: NSBitmapImageRep) -> CGFloat {
        CGFloat(rep.pixelsWide) / hosting.bounds.width
    }

    /// The raw RGBA bytes of a rect (SwiftUI global space) — bitmap rows are
    /// top-down, matching SwiftUI's y-down frames.
    private func pixels(_ rep: NSBitmapImageRep, in rect: CGRect) -> [UInt8] {
        let s = scale(rep)
        var out: [UInt8] = []
        for y in Int(rect.minY * s)..<Int(rect.maxY * s) {
            for x in Int(rect.minX * s)..<Int(rect.maxX * s) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                      let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                out += [UInt8(c.redComponent * 255), UInt8(c.greenComponent * 255),
                        UInt8(c.blueComponent * 255), UInt8(c.alphaComponent * 255)]
            }
        }
        return out
    }

    /// Mean alpha-weighted luminance over a rect (SwiftUI global space).
    private func meanLuma(_ rep: NSBitmapImageRep, _ rect: CGRect) -> Double {
        let s = scale(rep)
        var total = 0.0
        var samples = 0
        for y in Int(rect.minY * s)..<Int(rect.maxY * s) {
            for x in Int(rect.minX * s)..<Int(rect.maxX * s) {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                      let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let a = Double(c.alphaComponent)
                total += a * (0.299 * Double(c.redComponent)
                              + 0.587 * Double(c.greenComponent)
                              + 0.114 * Double(c.blueComponent))
                samples += 1
            }
        }
        return samples == 0 ? 0 : total / Double(samples)
    }

    /// How many bytes differ between two captures of `rect`, taken `apart` seconds
    /// apart. Zero means the region is STILL.
    private func motion(in id: CadenceControlID, apart: TimeInterval) throws -> Int {
        let rect = bitmapRect(try frame(of: id)).insetBy(dx: 8, dy: 8)
        let a = pixels(capture(), in: rect)
        pump(apart)
        let b = pixels(capture(), in: rect)
        XCTAssertEqual(a.count, b.count, "the two captures cover the same region")
        return zip(a, b).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
    }

    // MARK: - Harness fidelity

    /// The probe-located Play button is the REAL Play button: with a queue loaded
    /// a click on it starts playback (and the same click paused it again). Without
    /// this every "the click did X" assertion below could be a click on nothing.
    func testHarnessFidelity_probeLocatedPlayButtonDrivesRealPlayback() throws {
        core.load([Self.track(0), Self.track(1)])
        pump(0.3)
        try clickControl(.playPause)
        XCTAssertTrue(core.isPlaying, "a real click on the probe-located ▶ starts playback")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track0.mp3"])
        try clickControl(.playPause)
        XCTAssertFalse(core.isPlaying, "…and on ⏸ pauses it")
        XCTAssertEqual(addFilesCalls, 0, "a loaded queue never opens the add-files flow")
    }

    /// A click on dead space (the hairline gap just above the transport row)
    /// changes nothing — the harness does not fire the nearest control.
    func testHarnessFidelity_clickOnDeadSpaceDoesNothing() throws {
        core.load([Self.track(0), Self.track(1)])
        pump(0.3)
        let play = try frame(of: .playPause)
        let previous = try frame(of: .previous)
        click(at: windowPoint(CGPoint(x: previous.minX - 24, y: play.midY)))
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertEqual(engine.loadedURLs, [])
        XCTAssertEqual(addFilesCalls + addFolderCalls + playSampleCalls, 0)
    }

    // MARK: - F2: Play on an empty queue opens the add-files flow

    func testColdStart_playOnEmptyQueueInvokesTheAddFilesHandler() throws {
        XCTAssertTrue(core.playlist.isEmpty, "precondition: a fresh install has nothing loaded")

        try clickControl(.playPause)

        XCTAssertEqual(addFilesCalls, 1, "Play with nothing loaded asks for files instead of doing nothing")
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.playCount, 0, "the engine is never poked")
        XCTAssertEqual(engine.loadedURLs, [])
    }

    // MARK: - F6: the skips are inert AND unmistakably disabled; ■ is harmless

    func testColdStart_skipsAreDisabledAndVisiblyDimmed() throws {
        XCTAssertFalse(core.canGoNext)
        XCTAssertFalse(core.canGoPrevious)

        try clickControl(.previous)
        try clickControl(.next)
        XCTAssertNil(core.currentIndex)
        XCTAssertEqual(engine.stopCount + engine.playCount + engine.loadedURLs.count, 0,
                       "a disabled skip never reaches the model")
        XCTAssertEqual(addFilesCalls, 0, "only Play opens the add-files flow")

        // The disabled look must not read as styling: at most 0.3 of the live glyph.
        XCTAssertLessThanOrEqual(TransportIconButton.disabledOpacity, 0.3,
                                 "a disabled skip is dimmed to ≤ 0.3, not the old 0.5")
        // The glyph sits on the glass panel, so measure its ink ABOVE the panel:
        // the same-sized dead space just left of ◀◀ is the background reference.
        func nextInk() throws -> Double {
            let next = bitmapRect(try frame(of: .next))
            let reference = bitmapRect(try frame(of: .previous)).offsetBy(dx: -40, dy: 0)
            let rep = capture()
            return meanLuma(rep, next) - meanLuma(rep, reference)
        }
        let dim = try nextInk()
        core.load([Self.track(0), Self.track(1)])
        pump(0.4)
        XCTAssertTrue(core.canGoNext, "control: with a queue the SAME button is live")
        let live = try nextInk()
        XCTAssertGreaterThan(live, 0.02, "sanity: the live ▶▶ glyph draws visible ink above the panel")
        XCTAssertLessThanOrEqual(dim / live, 0.38,
                                 "the disabled ▶▶ renders at ≤ ~0.3 of its live ink (measured \(dim / live))")
    }

    /// ■ with nothing loaded is not a live-looking button that changes nothing: it
    /// is DISABLED (the click never reaches the model) and drawn with the same
    /// unmistakable dim the skips use — and the moment a track lands the SAME
    /// button is live and really halts playback.
    func testColdStart_stopIsDisabledAndVisiblyDimmedUntilATrackIsLoaded() throws {
        XCTAssertNil(core.currentTrack, "precondition: nothing loaded")

        try clickControl(.stop)
        XCTAssertEqual(engine.seekTimes, [], "a disabled ■ issues no rewind")
        XCTAssertEqual(engine.pauseCount, 0)
        XCTAssertEqual(addFilesCalls + addFolderCalls + playSampleCalls, 0, "and opens nothing")

        // Ink above the panel, like the skips test: the dead space left of ◀◀ is
        // the background reference.
        func stopInk() throws -> Double {
            let stop = bitmapRect(try frame(of: .stop))
            let reference = bitmapRect(try frame(of: .previous)).offsetBy(dx: -40, dy: 0)
            let rep = capture()
            return meanLuma(rep, stop) - meanLuma(rep, reference)
        }
        let dim = try stopInk()

        core.load([Self.track(0), Self.track(1)])
        pump(0.4)
        let live = try stopInk()
        XCTAssertGreaterThan(live, 0.02, "sanity: the live ■ glyph draws visible ink above the panel")
        XCTAssertLessThanOrEqual(dim / live, 0.38,
                                 "the disabled ■ renders at ≤ ~0.3 of its live ink (measured \(dim / live))")

        // Control: with a track it is the real ■ — play, then click it.
        try clickControl(.playPause)
        XCTAssertTrue(core.isPlaying)
        try clickControl(.stop)
        XCTAssertFalse(core.isPlaying, "■ halts playback once there is something to halt")
        XCTAssertEqual(engine.seekTimes, [0], "…and rewinds to 0")
        XCTAssertEqual(engine.pauseCount, 1)
    }

    // MARK: - F5: the EQ bank is never a dead block

    func testColdStart_clickingAnEQSliderTurnsTheEqualizerOn() throws {
        XCTAssertFalse(core.equalizer.enabled, "precondition: EQ defaults off")

        // A click near the TOP of the 60 Hz band: +dB.
        try clickControl(.eqBand(0), atHeightFraction: 0.1)

        XCTAssertTrue(core.equalizer.enabled, "touching a slider turns the equalizer ON")
        XCTAssertGreaterThan(core.equalizer.bands[0], 6, "…and the band took the click")
    }

    func testColdStart_clickingThePreampSliderTurnsTheEqualizerOn() throws {
        try clickControl(.eqPreamp, atHeightFraction: 0.9)
        XCTAssertTrue(core.equalizer.enabled)
        XCTAssertLessThan(core.equalizer.preamp, -6)
    }

    func testColdStart_choosingAPresetAppliesItAndTurnsTheEqualizerOn() throws {
        XCTAssertFalse(core.equalizer.enabled)

        try clickControl(.eqPreset(.rock))

        XCTAssertTrue(core.equalizer.enabled, "choosing a preset turns the equalizer ON")
        XCTAssertEqual(core.equalizer.bands, EQPreset.rock.bands, "…with the Rock curve applied")
    }

    func testColdStart_theOnCheckboxStillToggles() throws {
        try clickControl(.eqOn)
        XCTAssertTrue(core.equalizer.enabled)
        try clickControl(.eqOn)
        XCTAssertFalse(core.equalizer.enabled)
        // Turning it off again does NOT make the bank dead: a slider brings it back.
        try clickControl(.eqBand(9), atHeightFraction: 0.1)
        XCTAssertTrue(core.equalizer.enabled)
    }

    // MARK: - F1: the hero well is the call to action

    func testColdStart_heroShowsTheCallToActionWithWorkingButtons() throws {
        XCTAssertNotNil(probe.frame(of: .emptyWell), "the hero well shows the empty-queue call to action")
        XCTAssertNil(probe.frame(of: .visualizerWell), "…and NOT the spectrum visualizer")

        let well = try frame(of: .emptyWell)
        for id in [CadenceControlID.ctaAddFiles, .ctaAddFolder, .ctaPlaySample] {
            let f = try frame(of: id)
            XCTAssertTrue(well.contains(f), "\(id) sits inside the hero well, not below the transport")
            XCTAssertGreaterThanOrEqual(f.height, 24, "\(id) is a real button, not an 11 pt link")
        }

        try clickControl(.ctaAddFiles)
        XCTAssertEqual(addFilesCalls, 1, "Add Files… fires the SAME add-files handler the footer uses")
        try clickControl(.ctaAddFolder)
        XCTAssertEqual(addFolderCalls, 1, "Add Folder… fires the add-folder handler")
        try clickControl(.ctaPlaySample)
        XCTAssertEqual(playSampleCalls, 1, "Play Sample fires the sample handler")
        XCTAssertEqual(engine.playCount, 0, "the handlers, not the harness, own playback")
    }

    func testColdStart_playSampleIsHiddenWhenTheResourceIsMissing() throws {
        host(withSample: false)
        XCTAssertNotNil(probe.frame(of: .ctaAddFiles), "the other two buttons remain")
        XCTAssertNotNil(probe.frame(of: .ctaAddFolder))
        XCTAssertNil(probe.frame(of: .ctaPlaySample), "no sample resource, no Play Sample button")
    }

    // MARK: - F3: no fake idle animation with nothing loaded

    func testColdStart_theHeroWellIsStillUntilATrackIsLoaded() throws {
        let stillness = try motion(in: .emptyWell, apart: 0.5)
        XCTAssertEqual(stillness, 0, "with nothing loaded the hero well must not animate")

        // CONTROL: load a track and leave it PAUSED — the spectrum well's idle drift
        // is kept for that state, so the same measurement must now see motion.
        core.load([Self.track(0)])
        pump(0.4)
        XCTAssertNotNil(probe.frame(of: .visualizerWell), "a loaded queue brings the visualizer back")
        let drift = try motion(in: .visualizerWell, apart: 0.5)
        XCTAssertGreaterThan(drift, 0, "control: the loaded-but-paused well still breathes")
    }

    // MARK: - F4: an honest title line and blank clocks

    func testColdStart_titleLineSaysNothingLoadedAndClocksShowDashes() throws {
        XCTAssertEqual(DefaultPlayerView.nowPlaying(for: core.currentTrack), .nothingLoaded,
                       "an empty queue is an explicit state, not the app's name")
        XCTAssertEqual(DefaultPlayerView.nowPlaying(for: Track(url: URL(fileURLWithPath: "/a.mp3"), title: "")),
                       .nothingLoaded)
        XCTAssertEqual(DefaultPlayerView.nowPlaying(for: Self.track(3)),
                       .track(title: "Track 3", artist: "Someone"))

        XCTAssertEqual(CadenceSeekBar.timeLabel(0, hasTrack: false), "—")
        XCTAssertEqual(CadenceSeekBar.timeLabel(0, hasTrack: false, remaining: true), "—",
                       "no fake −0:00 remaining")
        XCTAssertEqual(CadenceSeekBar.timeLabel(65, hasTrack: true), "1:05")
        XCTAssertEqual(CadenceSeekBar.timeLabel(65, hasTrack: true, remaining: true), "−1:05")

        // The state is LOCALIZED (catalog content — runtime resolution is proven
        // under xcodebuild, see LocalizationBundleTests).
        let catalog = try loadCatalog()
        for (key, expected) in [
            "Nothing loaded": ["en": "Nothing loaded", "zh-Hant": "尚未載入", "ja": "何も読み込まれていません"]
        ] {
            for (lang, value) in expected {
                XCTAssertEqual(try catalogValue(catalog, key: key, lang: lang), value, "\(key)/\(lang)")
            }
        }
    }

    /// MUTANT-KILLER (M4b: `case .nothingLoaded: return Text(verbatim: "dwanim it")`).
    /// The pure `nowPlaying(for:)` mapping above is only half the line — the view
    /// still has to RENDER the state, and that two-line switch is exactly where App
    /// Review saw the app's name. SwiftUI exposes no text to an in-process AX walk,
    /// so this reads the PIXELS of the probe-located title: the empty-queue render
    /// must be byte-identical to a real track titled "Nothing loaded" (the same
    /// `Text` styling, the string the catalog key resolves to under `swift test`)
    /// and must differ from a real track titled "dwanim it".
    func testColdStart_theRenderedTitleIsNothingLoadedNotTheAppName() throws {
        func titlePixels(over rect: CGRect) -> [UInt8] { pixels(capture(), in: bitmapRect(rect)) }
        let empty = try frame(of: .nowTitle)
        XCTAssertGreaterThan(empty.width, 40, "sanity: the title line lays out with real text")

        // Reference A: the SAME string as a real track title, in the same style.
        core.load([Track(url: URL(fileURLWithPath: "/tmp/dwanim-first-run-harness/nothing.mp3"),
                         title: "Nothing loaded", duration: 120)])
        pump(0.4)
        let asTrack = try frame(of: .nowTitle)
        XCTAssertEqual(asTrack.origin, empty.origin, "the title line does not jump when a track lands")
        XCTAssertEqual(asTrack.size, empty.size, "…and the same string lays out to the same size")

        // Reference B: the app's name as a real track title, in the same style.
        core.load([Track(url: URL(fileURLWithPath: "/tmp/dwanim-first-run-harness/brand.mp3"),
                         title: "dwanim it", duration: 120)])
        pump(0.4)
        let asBrand = try frame(of: .nowTitle)
        XCTAssertEqual(asBrand.origin, empty.origin)
        let union = empty.union(asBrand)
        let brandPixels = titlePixels(over: union)

        core.load([])
        pump(0.4)
        XCTAssertNil(core.currentTrack, "back to the cold-start state")
        XCTAssertEqual(try frame(of: .nowTitle), empty, "the empty state lays out exactly as before")
        let emptyPixels = titlePixels(over: union)

        core.load([Track(url: URL(fileURLWithPath: "/tmp/dwanim-first-run-harness/nothing.mp3"),
                         title: "Nothing loaded", duration: 120)])
        pump(0.4)
        let nothingPixels = titlePixels(over: union)

        func differingBytes(_ a: [UInt8], _ b: [UInt8]) -> Int {
            zip(a, b).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
        }
        XCTAssertEqual(emptyPixels.count, nothingPixels.count)
        XCTAssertEqual(emptyPixels.count, brandPixels.count)
        XCTAssertEqual(differingBytes(emptyPixels, nothingPixels), 0,
                       "the empty queue renders the localized \"Nothing loaded\" state in the title style")
        XCTAssertGreaterThan(differingBytes(emptyPixels, brandPixels), 0,
                             "…and never the app's name, which App Review read as a playing track")
    }

    // MARK: - After adding a track the face comes alive

    func testAfterAddingATrack_theCallToActionYieldsToALivePlayer() throws {
        try clickControl(.ctaAddFiles)
        XCTAssertEqual(addFilesCalls, 1)

        // What the add-files flow does once the panel returns.
        core.append([Self.track(0), Self.track(1)])
        pump(0.4)

        XCTAssertNil(probe.frame(of: .emptyWell), "the call to action is gone")
        XCTAssertNil(probe.frame(of: .ctaPlaySample))
        XCTAssertNotNil(probe.frame(of: .visualizerWell), "the spectrum well is back")
        XCTAssertEqual(DefaultPlayerView.nowPlaying(for: core.currentTrack),
                       .track(title: "Track 0", artist: "Someone"))
        XCTAssertTrue(core.canGoNext, "▶▶ is live on a two-track queue")

        try clickControl(.playPause)
        XCTAssertTrue(core.isPlaying, "Play now plays")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track0.mp3"])
        XCTAssertEqual(addFilesCalls, 1, "…and no longer opens the add-files flow")

        try clickControl(.next)
        XCTAssertEqual(core.currentIndex, 1, "▶▶ advances")
    }

    // MARK: Catalog helpers

    private func loadCatalog() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    private func catalogValue(_ strings: [String: Any], key: String, lang: String) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "catalog missing key: \(key)")
        let loc = try XCTUnwrap((entry["localizations"] as? [String: Any])?[lang] as? [String: Any],
                                "\(key) missing \(lang)")
        let unit = try XCTUnwrap(loc["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }
}
