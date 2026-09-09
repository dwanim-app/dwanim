import AppKit
import SwiftUI
import XCTest
import PlayerCore
@testable import DwanimItUI

// MARK: - CadenceTransportRepeatCycleTests
//
// Real-click coverage for the two transport changes the owner asked for:
//
//   A. the Repeat pill is a THREE-state cycle — OFF -> ALL -> ONE -> OFF — so
//      `.all` (the mode in which `▶▶` wraps) is reachable from the default UI at
//      last; it used to be a 2-state `off ↔ .one` flip.
//   C. `▶▶` / `◀◀` are DISABLED exactly when a press could do nothing, so a
//      control never looks live while being inert.
//
// It reuses the dispatch model established by `CadenceTransportNextButtonTests`
// (queue the mouse-UP before handing the mouse-DOWN to the window, then pump
// `NSApp`'s queue) and its `TransportRecordingEngine`, so every click below is a
// real synthesized `NSEvent` through the window's normal event path.
//
// LOCATING THE LEFT-ZONE PILLS. The centre cluster's buttons have fixed sizes, so
// `CadenceTransportNextButtonTests` derives their centres arithmetically. The
// Shuffle / Repeat / EQ pills instead size to their TEXT, so their centres are
// derived from the same three inputs the view uses: the rendered string, the
// 11 pt system font, and the 8 pt horizontal padding. `testPillGeometryFidelity…`
// is the guard on that derivation — it shows each computed point drives its OWN
// pill, and that a point just past the last pill drives nothing.
//
// Under `swift test` the String Catalog is copied verbatim (never compiled), so
// `Text("Repeat", bundle: .module)` renders the English source key. The pill
// measurements below are therefore deterministic in this target.
@MainActor
final class CadenceTransportRepeatCycleTests: XCTestCase {

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
        core.load(Self.tracks(trackCount))

        hosting = NSHostingView(rootView: CadenceTransport(core: core, theme: .graphite))
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 60)
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
        pump(0.2)
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.close()
        window = nil
        hosting = nil
    }

    private static func tracks(_ count: Int) -> [Track] {
        (0..<count).map {
            Track(url: URL(fileURLWithPath: "/tmp/dwanim-repeat-harness/track\($0).mp3"),
                  title: "Track \($0)", duration: 120)
        }
    }

    private func reload(trackCount count: Int) {
        core.load(Self.tracks(count))
        pump(0.2)
    }

    // MARK: Event plumbing (same model as CadenceTransportNextButtonTests)

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

    private func click(at p: NSPoint) {
        NSApp.postEvent(mouseEvent(.leftMouseUp, at: p), atStart: false)
        window.sendEvent(mouseEvent(.leftMouseDown, at: p))
        pump(0.25)
    }

    // MARK: Centre-cluster geometry (mirrors CadenceTransportNextButtonTests)

    private enum TransportButton: CaseIterable {
        case previous, playPause, stop, next
        var width: CGFloat { self == .playPause ? 44 : 32 }
    }

    private func center(of button: TransportButton) -> NSPoint {
        let rowWidth = hosting.bounds.width
        let sideZone: CGFloat = 176
        let zoneSpacing: CGFloat = 12
        let clusterSpacing: CGFloat = 6

        let centreBoxX = sideZone + zoneSpacing
        let centreBoxWidth = rowWidth - 2 * (sideZone + zoneSpacing)
        let widths = TransportButton.allCases.map(\.width)
        let clusterWidth = widths.reduce(0, +) + clusterSpacing * CGFloat(widths.count - 1)
        var x = centreBoxX + (centreBoxWidth - clusterWidth) / 2
        for candidate in TransportButton.allCases {
            if candidate == button { break }
            x += candidate.width + clusterSpacing
        }
        return NSPoint(x: x + button.width / 2, y: hosting.bounds.midY)
    }

    private func clickButton(_ button: TransportButton) { click(at: center(of: button)) }
    private func clickNext() { clickButton(.next) }
    private func clickPrevious() { clickButton(.previous) }

    // MARK: Left-zone pill geometry

    /// The three left-zone pills, in the order `CadenceTransport` builds them.
    private enum Pill { case shuffle, repeatMode, eq }

    /// The pill's rendered text under `swift test` (uncompiled catalog -> the
    /// English source key). The Repeat pill shows the SAME word in all three
    /// states — the repeat-one "1" is an overlaid badge that adds no width — so
    /// this geometry is state-independent and the pills never move.
    private func pillText(_ pill: Pill) -> String {
        switch pill {
        case .shuffle: return "Shuffle"
        case .repeatMode: return CadenceTransport.repeatLabelKey(for: core.repeatMode)
        case .eq: return "EQ"
        }
    }

    /// The pill's laid-out width: the text measured in the SAME 11 pt system font
    /// the view uses, plus `.padding(.horizontal, 8)` on both sides.
    private func pillWidth(_ pill: Pill) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: pill == .eq ? .semibold : .regular)
        let text = NSAttributedString(string: pillText(pill), attributes: [.font: font])
        return ceil(text.size().width) + 16
    }

    /// The pill's centre. The left zone is a fixed 176 pt box at the row's left
    /// edge holding `HStack(spacing: 4)`, left-aligned.
    private func center(of pill: Pill) -> NSPoint {
        let spacing: CGFloat = 4
        var x: CGFloat = 0
        for candidate in [Pill.shuffle, .repeatMode, .eq] {
            if candidate == pill { break }
            x += pillWidth(candidate) + spacing
        }
        return NSPoint(x: x + pillWidth(pill) / 2, y: hosting.bounds.midY)
    }

    /// The x just past the LAST pill's trailing edge — dead space still inside the
    /// 176 pt left zone, used as the negative control.
    private func deadSpaceAfterPills() -> NSPoint {
        let spacing: CGFloat = 4
        let used = pillWidth(.shuffle) + pillWidth(.repeatMode) + pillWidth(.eq) + 2 * spacing
        return NSPoint(x: used + 12, y: hosting.bounds.midY)
    }

    private func clickPill(_ pill: Pill) { click(at: center(of: pill)) }

    private func playTrack(_ index: Int) {
        core.select(index)
        pump(0.05)
        engine.resetLog()
    }

    // MARK: - A0. Pill geometry fidelity

    /// Without this, every "the Repeat pill cycled" assertion below could just be
    /// a harness clicking the wrong thing (or nothing). Each computed point must
    /// drive its OWN pill, and dead space must drive none.
    func testPillGeometryFidelity_eachComputedPointDrivesItsOwnPill() {
        // The three pills must fit the fixed 176 pt zone in the WIDEST state,
        // otherwise the derived centres would be meaningless.
        core.repeatMode = .one
        pump(0.1)
        let widest = pillWidth(.shuffle) + pillWidth(.repeatMode) + pillWidth(.eq) + 8
        XCTAssertLessThan(widest, 176, "the pills must fit the fixed left zone even in the ONE state")
        core.repeatMode = .off
        pump(0.1)

        // Shuffle.
        XCTAssertFalse(core.isShuffle)
        clickPill(.shuffle)
        XCTAssertTrue(core.isShuffle, "the computed Shuffle point drives the Shuffle pill")
        XCTAssertEqual(core.repeatMode, .off, "...and nothing else")
        clickPill(.shuffle)
        XCTAssertFalse(core.isShuffle)

        // EQ.
        XCTAssertFalse(core.equalizer.enabled)
        clickPill(.eq)
        XCTAssertTrue(core.equalizer.enabled, "the computed EQ point drives the EQ pill")
        XCTAssertFalse(core.isShuffle, "...and nothing else")
        clickPill(.eq)
        XCTAssertFalse(core.equalizer.enabled)

        // Repeat.
        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .all, "the computed Repeat point drives the Repeat pill")
        XCTAssertFalse(core.equalizer.enabled, "...and nothing else")
    }

    /// Negative control: dead space just past the pills, still inside the left
    /// zone, changes nothing.
    func testPillGeometryFidelity_clickPastTheLastPillDoesNothing() {
        click(at: deadSpaceAfterPills())
        XCTAssertFalse(core.isShuffle)
        XCTAssertEqual(core.repeatMode, .off)
        XCTAssertFalse(core.equalizer.enabled)
    }

    // MARK: - A. The three-state Repeat cycle

    /// The headline: successive REAL clicks walk OFF -> ALL -> ONE -> OFF, and a
    /// fourth press starts the cycle again. `.all` used to be unreachable here.
    func testRepeatPill_threeRealClicksWalkOffAllOneAndBackToOff() {
        XCTAssertEqual(core.repeatMode, .off, "precondition: repeat starts off")

        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .all, "1st press: off -> all")

        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .one, "2nd press: all -> one")

        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .off, "3rd press: one -> off")

        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .all, "4th press restarts the cycle")
    }

    /// Mutual exclusivity survives the widened cycle: entering ANY repeat-on state
    /// clears Shuffle, and turning Shuffle on clears repeat from either on-state.
    func testRepeatAndShuffleStayMutuallyExclusiveAcrossTheWholeCycle() {
        core.isShuffle = true
        pump(0.1)

        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .all)
        XCTAssertFalse(core.isShuffle, "entering .all clears Shuffle")

        core.isShuffle = true
        pump(0.1)
        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .one)
        XCTAssertFalse(core.isShuffle, "entering .one clears Shuffle")

        // Shuffle ON from the .one state clears repeat.
        core.repeatMode = .one
        pump(0.1)
        clickPill(.shuffle)
        XCTAssertTrue(core.isShuffle)
        XCTAssertEqual(core.repeatMode, .off, "turning Shuffle on clears repeat")

        // Leaving repeat (one -> off) must NOT re-enable Shuffle.
        core.isShuffle = false
        core.repeatMode = .one
        pump(0.1)
        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .off)
        XCTAssertFalse(core.isShuffle, "leaving repeat leaves Shuffle alone")
    }

    // MARK: - B. Explicit navigation wraps once repeat is reachable

    /// End to end through the UI: park on the LAST track, press Repeat once
    /// (reaching `.all`), then press `▶▶` — it wraps to the first track and plays
    /// it. This is the whole point of making `.all` reachable.
    func testRepeatAllReachedByClicking_thenNextWrapsToTheFirstTrack() {
        playTrack(trackCount - 1)

        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .all)
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, 0, "▶▶ wraps with repeat all")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track0.mp3"])
    }

    /// The same through `.one`, which is now also a wrapping mode for EXPLICIT
    /// navigation (auto-advance still replays — that is a PlayerCore test).
    func testRepeatOneReachedByClicking_thenNextWrapsAndPreviousWrapsBack() {
        playTrack(trackCount - 1)

        clickPill(.repeatMode) // off -> all
        clickPill(.repeatMode) // all -> one
        XCTAssertEqual(core.repeatMode, .one)
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, 0, "▶▶ wraps with repeat one")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track0.mp3"])

        engine.resetLog()
        clickPrevious()
        XCTAssertEqual(core.currentIndex, trackCount - 1, "◀◀ from the first track wraps to the last")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track3.mp3"])
    }

    // MARK: - C. The disabled state

    /// The owner's complaint, fixed: parked on the LAST track with repeat off,
    /// `▶▶` is DISABLED — a real click at its centre produces nothing at all, not
    /// even the invisible no-op `stop()` the enabled button used to issue.
    ///
    /// The control for "the harness clicked the right pixel" is the second half:
    /// one press of Repeat re-enables the very same coordinates.
    func testNextButtonIsDisabledAtTheEndOfTheQueueWithRepeatOffAndReEnabledByRepeat() {
        playTrack(trackCount - 1)
        XCTAssertFalse(core.canGoNext, "precondition: the model says ▶▶ cannot act")

        clickNext()
        XCTAssertEqual(core.currentIndex, trackCount - 1, "no move")
        XCTAssertTrue(core.isPlaying, "a DISABLED ▶▶ does not even stop playback")
        XCTAssertEqual(engine.loadedURLs, [], "nothing loaded")
        XCTAssertEqual(engine.stopCount, 0, "the no-op stop is gone — the press never reaches the model")
        XCTAssertEqual(engine.playCount, 0)

        // Same pixel, repeat on: now it acts.
        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .all)
        XCTAssertTrue(core.canGoNext)
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, 0, "the SAME coordinates now wrap — the button was disabled, not missed")
    }

    /// An EMPTY queue disables both skips: neither click does anything.
    func testBothSkipButtonsAreDisabledOnAnEmptyQueue() {
        reload(trackCount: 0)
        XCTAssertNil(core.currentIndex)
        XCTAssertFalse(core.canGoNext)
        XCTAssertFalse(core.canGoPrevious)
        engine.resetLog()

        clickNext()
        clickPrevious()

        XCTAssertNil(core.currentIndex)
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs, [])
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertEqual(engine.stopCount, 0)
    }

    /// `◀◀` stays ENABLED on the first track with repeat off, because the press
    /// restarts that track in place — the deliberate `.off` asymmetry. A real
    /// click proves it still reloads and plays.
    func testPreviousButtonStaysEnabledOnTheFirstTrackWithRepeatOff() {
        playTrack(0)
        XCTAssertTrue(core.canGoPrevious)

        clickPrevious()

        XCTAssertEqual(core.currentIndex, 0, "the selection stays on the first track")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track0.mp3"],
                       "◀◀ restarts track 0 — a real, visible action")
    }

    /// A SINGLE-track queue with repeat off: `▶▶` is dead, so it is dimmed rather
    /// than silently inert. Cycling Repeat on re-enables it (it restarts the only
    /// track).
    func testSingleTrackQueueDisablesNextUntilRepeatIsOn() {
        reload(trackCount: 1)
        playTrack(0)
        XCTAssertFalse(core.canGoNext)

        clickNext()
        XCTAssertEqual(engine.loadedURLs, [], "▶▶ is disabled on a 1-track queue with repeat off")
        XCTAssertEqual(engine.stopCount, 0)

        clickPill(.repeatMode)
        XCTAssertEqual(core.repeatMode, .all)
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track0.mp3"],
                       "with repeat on, ▶▶ restarts the only track")
    }

    /// Availability must follow a mid-session playlist EDIT: appending a row while
    /// parked on the last track re-enables `▶▶` without any other interaction.
    func testAppendingATrackReEnablesNextWhileParkedAtTheEnd() {
        playTrack(trackCount - 1)
        XCTAssertFalse(core.canGoNext)
        clickNext()
        XCTAssertEqual(engine.loadedURLs, [], "disabled before the append")

        core.append([Track(url: URL(fileURLWithPath: "/tmp/dwanim-repeat-harness/track9.mp3"),
                           title: "Track 9", duration: 120)])
        pump(0.2)
        XCTAssertTrue(core.canGoNext)
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, trackCount, "▶▶ reaches the newly appended row")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track9.mp3"])
    }

    /// Shuffle keeps `▶▶` live at the end of the queue (shuffle has no end-of-list
    /// stop), so the dimming must not fire there.
    func testShuffleKeepsNextEnabledAtTheEndOfTheQueue() {
        playTrack(trackCount - 1)
        XCTAssertFalse(core.canGoNext)

        clickPill(.shuffle)
        XCTAssertTrue(core.isShuffle)
        XCTAssertTrue(core.canGoNext)
        engine.resetLog()

        clickNext()
        XCTAssertNotEqual(core.currentIndex, trackCount - 1, "shuffle picks another track")
        XCTAssertEqual(engine.loadedURLs.count, 1)
    }
}
