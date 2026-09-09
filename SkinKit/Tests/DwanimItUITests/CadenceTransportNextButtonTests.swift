import AppKit
import SwiftUI
import XCTest
import PlayerCore
@testable import DwanimItUI

// MARK: - TransportRecordingEngine

/// An in-memory `AudioPlaybackEngine` that records every `load` / `play` / `stop`
/// / `pause` / `seek`, so the transport harness can assert exactly what a real
/// button click made the model do — not merely that "something" happened.
///
/// `finishCurrentTrack()` fires the engine's own end-of-track callback, which is
/// how the app reaches the owner's reported state (parked, stopped, on the LAST
/// queue track) without waiting for real audio.
final class TransportRecordingEngine: AudioPlaybackEngine {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var volume: Float = 1.0
    var pan: Float = 0.0
    var onPlaybackFinished: (@Sendable @MainActor () -> Void)?

    private(set) var loadedURLs: [URL] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var seekTimes: [TimeInterval] = []

    func load(_ url: URL) throws { loadedURLs.append(url) }
    func play() { playCount += 1; isPlaying = true }
    func pause() { isPlaying = false; pauseCount += 1 }
    func stop() { isPlaying = false; stopCount += 1 }
    func seek(to time: TimeInterval) { seekTimes.append(time) }

    /// Reset the recorded traffic so one test step can assert on its OWN effects.
    func resetLog() {
        loadedURLs = []
        playCount = 0
        pauseCount = 0
        stopCount = 0
        seekTimes = []
    }

    /// Simulate the engine reaching the end of the current track (the real
    /// `AVAudioPlayerNode` completion path), which is what drives `PlayerCore`
    /// into its end-of-queue resting state.
    @MainActor
    func finishCurrentTrack() {
        isPlaying = false
        onPlaybackFinished?()
    }
}

// MARK: - CadenceTransportNextButtonTests
//
// In-process reproduction harness for the OWNER-REPORTED symptom: "I pressed the
// fast-forward (▶▶) button and nothing happened."
//
// STATUS: the symptom is FIXED, and this file now pins the fix rather than the
// bug. Two changes moved the cases below:
//   - explicit `▶▶` / `◀◀` WRAP whenever repeat is on (`.all` AND `.one`), and
//     the Cadence Repeat pill is a 3-state cycle, so `.all` is reachable;
//   - `▶▶` / `◀◀` are DISABLED whenever a press could not act, so the button no
//     longer looks live while doing nothing. A disabled press reaches the model
//     not at all — the tell is `engine.stopCount == 0` where it used to be 1.
// The cycle itself, the wrap, and the disabled state get their own real-click
// coverage in `CadenceTransportRepeatCycleTests`.
//
// It hosts the REAL `CadenceTransport` (the same view `DefaultPlayerView` puts in
// the hero) in an `NSHostingView` inside a real `NSWindow`, locates each transport
// button from that view's own layout (see "Locating a SwiftUI button" below), and
// drives SYNTHESIZED `NSEvent`s through the window's normal event path. No real
// mouse, no CGEvent posting, no accessibility permission.
//
// DISPATCH MODEL (inherited from CadencePlaylistDoubleClickTests, which
// established it against a real `NSTableView`):
//   1. The PROCESS must be active for the window to become key, so `setUp`
//      switches to `.regular` activation and pumps until `isKeyWindow`.
//   2. The matching mouse-UP is posted to `NSApp`'s queue BEFORE the mouse-DOWN
//      is handed to `window.sendEvent`, so a control that runs its own tracking
//      loop cannot block. `pump` then drains the queue through `NSApp.sendEvent`.
//
// FIDELITY (two controls, because a harness that clicks nothing — or that fires
// a button from anywhere — would prove nothing about ▶▶):
//   - `testHarnessFidelity_playPreviousAndNextAllRespondToRealClicks` shows every
//     other transport button responds, each with its OWN distinct effect;
//   - `testHarnessFidelity_clickOnDeadSpaceDoesNothing` shows a click off the
//     buttons changes nothing.
@MainActor
final class CadenceTransportNextButtonTests: XCTestCase {

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
        pump(0.2) // let SwiftUI lay the transport row out
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.close()
        window = nil
        hosting = nil
    }

    private static func tracks(_ count: Int) -> [Track] {
        (0..<count).map {
            Track(url: URL(fileURLWithPath: "/tmp/dwanim-transport-harness/track\($0).mp3"),
                  title: "Track \($0)", duration: 120)
        }
    }

    /// Rebuild the hosted view over a playlist of `count` tracks (0 = empty queue).
    private func reload(trackCount count: Int) {
        core.load(Self.tracks(count))
        pump(0.2)
    }

    // MARK: Event plumbing

    /// Drain `NSApp`'s queue through `sendEvent` and spin the run loop for `seconds`.
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

    private func mouseEvent(_ type: NSEvent.EventType, at p: NSPoint, clickCount: Int) -> NSEvent {
        guard let e = NSEvent.mouseEvent(
            with: type, location: p, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: clickCount, pressure: 1
        ) else { fatalError("NSEvent.mouseEvent returned nil for \(type)") }
        return e
    }

    /// Queue the UP first, then hand the DOWN to the window (see DISPATCH MODEL).
    private func click(at p: NSPoint) {
        NSApp.postEvent(mouseEvent(.leftMouseUp, at: p, clickCount: 1), atStart: false)
        window.sendEvent(mouseEvent(.leftMouseDown, at: p, clickCount: 1))
        pump(0.25)
    }

    // MARK: Locating a SwiftUI button

    // WHY GEOMETRY AND NOT ACCESSIBILITY: SwiftUI draws its buttons inside the
    // hosting view (no `NSButton` per control, `hosting.subviews` is empty), and
    // in-process the hosting view publishes NO accessibility children — both
    // `accessibilityChildren()` and `accessibilityHitTest(_:)` return only the
    // `NSHostingView` itself, because SwiftUI builds its AX tree lazily for an
    // out-of-process AX client. So the buttons are located from
    // `CadenceTransport`'s own documented layout, and the FIDELITY test proves
    // the mapping: each computed point drives its OWN distinct transport action.

    /// The centre-cluster button order, left to right, as `CadenceTransport`
    /// builds it: ◀◀ (32 pt) / play-pause (44 pt) / ■ (32 pt) / ▶▶ (32 pt),
    /// `HStack(spacing: 6)`.
    private enum TransportButton: CaseIterable {
        case previous, playPause, stop, next
        var width: CGFloat { self == .playPause ? 44 : 32 }
    }

    /// `CadenceTransport` lays out `HStack(spacing: 12)` of: a fixed 176 pt left
    /// zone, the centre cluster at `maxWidth: .infinity`, and a fixed 176 pt
    /// right zone. So the centre cluster's box is the leftover width, and the
    /// cluster centres itself inside it.
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

    /// Real-click one transport button.
    private func clickButton(_ button: TransportButton) {
        click(at: center(of: button))
    }

    private func clickNext() { clickButton(.next) }
    private func clickPrevious() { clickButton(.previous) }

    // MARK: State setup helpers

    /// Drive the core into "playing track `index`".
    private func playTrack(_ index: Int) {
        core.select(index)
        XCTAssertTrue(core.isPlaying, "precondition: select(\(index)) starts playback")
        pump(0.05)
        engine.resetLog()
    }

    /// Drive the core into the OWNER'S state: the queue played to its natural end
    /// with the given repeat mode, leaving it parked + stopped on the LAST track.
    private func playToNaturalEnd(repeatMode: RepeatMode) {
        core.repeatMode = repeatMode
        core.select(core.playlist.count - 1)
        pump(0.05)
        engine.finishCurrentTrack()
        pump(0.05)
        engine.resetLog()
    }

    // MARK: - A. Harness fidelity

    /// The harness must be able to work the OTHER transport buttons through the
    /// same synthesized-click path; otherwise "▶▶ did nothing" would just be the
    /// harness failing to click anything at all.
    func testHarnessFidelity_playPreviousAndNextAllRespondToRealClicks() throws {
        // Play (the queue is loaded, index 0, not playing).
        XCTAssertFalse(core.isPlaying)
        clickButton(.playPause)
        XCTAssertTrue(core.isPlaying, "a real click on ▶ starts playback")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track0.mp3"])

        // Pause (the glyph — and so the a11y label — has flipped to Pause).
        clickButton(.playPause)
        XCTAssertFalse(core.isPlaying, "a real click on ⏸ pauses")
        XCTAssertEqual(engine.pauseCount, 1)

        // Next, from the middle of the list.
        playTrack(1)
        clickNext()
        XCTAssertEqual(core.currentIndex, 2, "a real click on ▶▶ advances one track")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track2.mp3"])

        // Previous.
        engine.resetLog()
        clickPrevious()
        XCTAssertEqual(core.currentIndex, 1, "a real click on ◀◀ steps back one track")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track1.mp3"])

        // Stop.
        engine.resetLog()
        clickButton(.stop)
        XCTAssertFalse(core.isPlaying, "a real click on ■ halts playback")
        XCTAssertEqual(engine.seekTimes, [0], "■ also rewinds to 0")
    }

    /// Negative control: a click on the DEAD SPACE just left of ◀◀ (inside the
    /// centre box, outside the button cluster) must do nothing. Without this, a
    /// harness that fired the nearest button from any point could make every
    /// "the click worked" assertion above meaningless.
    func testHarnessFidelity_clickOnDeadSpaceDoesNothing() {
        playTrack(1)
        let previous = center(of: .previous)
        click(at: NSPoint(x: previous.x - 32, y: previous.y))

        XCTAssertEqual(core.currentIndex, 1, "a click on empty space changes nothing")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs, [])
        XCTAssertEqual(engine.playCount, 0)
        XCTAssertEqual(engine.pauseCount, 0)
        XCTAssertEqual(engine.stopCount, 0)
    }

    // MARK: - B. The ▶▶ state matrix (every click below is a REAL click)

    /// (1) Playing, middle of the list → advances and plays the next track.
    func testNext_playingMidList_advancesAndPlays() throws {
        playTrack(1)
        clickNext()
        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track2.mp3"])
    }

    /// (2) Paused, middle of the list → advances and STARTS playing.
    func testNext_pausedMidList_advancesAndPlays() throws {
        playTrack(1)
        core.pause()
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertTrue(core.isPlaying, "▶▶ from a paused track starts the next one")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track2.mp3"])
    }

    /// (3) Stopped (the ■ button's pause+seek-0), middle of the list → advances.
    func testNext_stoppedMidList_advancesAndPlays() throws {
        playTrack(1)
        clickButton(.stop)
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, 2)
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track2.mp3"])
    }

    /// (4) PLAYING the LAST track, repeat off → ▶▶ is DISABLED, so the click is
    /// swallowed by the button and playback carries on.
    ///
    /// This case CHANGED. ▶▶ used to stop playback here — an effect, but an
    /// unexpected one from a "next" button, and the button gave no hint it was at
    /// the end of the queue. The owner chose to dim ▶▶ instead and leave stopping
    /// to ■. The model-level end-of-queue stop that `next()` still performs is
    /// covered by `PlayerCoreTests.testNextPastLastWithRepeatOffStops`.
    func testNext_playingLastTrack_repeatOff_isDisabledAndLeavesPlaybackAlone() throws {
        playTrack(trackCount - 1)
        XCTAssertFalse(core.canGoNext, "precondition: the model reports ▶▶ cannot act")

        clickNext()

        XCTAssertEqual(core.currentIndex, trackCount - 1, "the selection stays on the last track")
        XCTAssertTrue(core.isPlaying, "a disabled ▶▶ no longer stops playback")
        XCTAssertEqual(engine.stopCount, 0, "the press never reaches the model")
        XCTAssertEqual(engine.loadedURLs, [], "nothing new is loaded")
    }

    /// (5) THE OWNER'S EXACT STATE: the queue ran to its natural end with repeat
    /// OFF, so the app is parked + stopped on the last track. ▶▶ still produces no
    /// change — but it is now DIMMED, so the inertness is visible instead of
    /// mysterious, and the press does not even reach the model.
    ///
    /// The stopCount assertion is the difference: it used to be 1 (a redundant,
    /// invisible `stop()` on an already-stopped engine — the reported symptom).
    func testNext_stoppedAtLastTrackAfterNaturalEnd_repeatOff_isDisabledNotSilentlyInert() throws {
        playToNaturalEnd(repeatMode: .off)
        XCTAssertEqual(core.currentIndex, trackCount - 1, "precondition: parked on the last track")
        XCTAssertFalse(core.isPlaying, "precondition: stopped")
        XCTAssertFalse(core.canGoNext, "precondition: ▶▶ is dimmed here")

        let indexBefore = core.currentIndex
        clickNext()

        XCTAssertEqual(core.currentIndex, indexBefore, "▶▶ does not move the selection")
        XCTAssertFalse(core.isPlaying, "▶▶ does not start anything")
        XCTAssertEqual(engine.loadedURLs, [], "▶▶ loads nothing")
        XCTAssertEqual(engine.playCount, 0, "▶▶ plays nothing")
        XCTAssertEqual(engine.stopCount, 0, "no invisible no-op stop: the button is disabled")
    }

    /// (6) Same end-of-queue state but repeat `.all` → ▶▶ WRAPS to track 0.
    /// `.all` is now REACHABLE from the Cadence UI (the Repeat pill cycles
    /// off → all → one → off); the click-through-the-pill route is covered in
    /// `CadenceTransportRepeatCycleTests`.
    func testNext_stoppedAtLastTrack_repeatAll_wrapsToFirstTrack() throws {
        playToNaturalEnd(repeatMode: .all)
        // `.all` auto-advanced on finish, so re-park on the last track first.
        core.select(trackCount - 1)
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, 0, "▶▶ wraps with repeat .all")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track0.mp3"])
    }

    /// (7) Same end-of-queue state with repeat `.one`. This case CHANGED: `.one`
    /// used to be inert at the end (identical to `.off`), which is what made the
    /// Repeat button feel broken. Explicit `▶▶` now WRAPS under `.one` exactly as
    /// under `.all` — auto-advance is what still replays the same track.
    func testNext_stoppedAtLastTrack_repeatOne_wrapsToFirstTrack() throws {
        playToNaturalEnd(repeatMode: .one)
        // `.one` replayed the same track on finish; park it stopped again.
        core.pause()
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, 0, "▶▶ wraps with repeat one")
        XCTAssertTrue(core.isPlaying, "and the wrapped-to track plays")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track0.mp3"])
    }

    /// (8) Shuffle ON → ▶▶ jumps to some OTHER track and plays it, including from
    /// the last track (shuffle has no end-of-list stop).
    func testNext_shuffleOn_alwaysMovesToAnotherTrackAndPlays() throws {
        core.isShuffle = true
        playTrack(trackCount - 1)

        clickNext()
        XCTAssertNotEqual(core.currentIndex, trackCount - 1, "shuffle picks a different track")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs.count, 1)
    }

    /// (9) A SINGLE-track playlist with repeat off. Sequential: the only track is
    /// also the last. Shuffled: the strategy can only pick the current index. ▶▶
    /// cannot act either way — and it is now DIMMED to say so, where it used to
    /// look live while stopping (sequential) or doing nothing at all (shuffled).
    func testNext_singleTrackPlaylist_isDisabledInBothSequentialAndShuffle() throws {
        reload(trackCount: 1)
        playTrack(0)
        XCTAssertFalse(core.canGoNext, "sequential: nowhere to go on a 1-track queue")

        clickNext()
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertTrue(core.isPlaying, "a disabled ▶▶ no longer stops the only track")
        XCTAssertEqual(engine.stopCount, 0)

        core.isShuffle = true
        playTrack(0)
        XCTAssertFalse(core.canGoNext, "shuffle cannot leave a 1-track queue either")
        clickNext()
        XCTAssertEqual(core.currentIndex, 0)
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs, [], "no reload")
    }

    /// (10) EMPTY playlist → ▶▶ is DISABLED (it was a silent guarded no-op before;
    /// the guard in `next()` remains, but the press no longer reaches it).
    func testNext_emptyPlaylist_isNoOp() throws {
        reload(trackCount: 0)
        XCTAssertNil(core.currentIndex)
        engine.resetLog()

        clickNext()
        XCTAssertNil(core.currentIndex)
        XCTAssertFalse(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs, [])
        XCTAssertEqual(engine.stopCount, 0)
    }

    /// (11) Immediately after a drag-reorder that moved the CURRENT track: ▶▶ must
    /// advance to whatever now sits after it in the NEW order.
    func testNext_afterReorderMovingCurrentTrack_advancesInTheNewOrder() throws {
        playTrack(0) // track0 is current
        // Drag track0 down to the end: new order is 1, 2, 3, 0.
        core.move(fromOffsets: IndexSet(integer: 0), toOffset: trackCount)
        pump(0.1)
        XCTAssertEqual(core.currentIndex, trackCount - 1, "the selection follows the moved track")
        engine.resetLog()

        clickNext()
        // The moved track is now LAST, so with repeat off ▶▶ is dimmed: the press
        // does nothing and playback carries on.
        XCTAssertFalse(core.canGoNext, "the reorder parked the current track at the end")
        XCTAssertEqual(core.currentIndex, trackCount - 1)
        XCTAssertTrue(core.isPlaying, "a disabled ▶▶ leaves playback alone")
        XCTAssertEqual(engine.stopCount, 0)

        // And with the current track dragged to the MIDDLE it advances normally.
        core.move(fromOffsets: IndexSet(integer: trackCount - 1), toOffset: 1)
        pump(0.1)
        XCTAssertEqual(core.currentIndex, 1)
        engine.resetLog()
        clickNext()
        XCTAssertEqual(core.currentIndex, 2, "▶▶ advances in the reordered list")
        XCTAssertTrue(core.isPlaying)
    }

    /// (12) COLD START with a restored queue and nothing ever played. The launch
    /// path is `PlayerCore.load(_:)`, which SELECTS index 0 without playing, so
    /// `currentIndex` is NOT nil and ▶▶ is live: it skips straight to track 1 and
    /// starts playing it. (It does NOT play the shown track 0.)
    func testNext_freshLaunchRestoredQueueNothingPlayed_skipsTrackZeroAndPlaysTrackOne() throws {
        reload(trackCount: trackCount) // exactly what resolveLastAudioOnLaunch does
        XCTAssertEqual(core.currentIndex, 0, "load(_:) selects the first row without playing")
        XCTAssertFalse(core.isPlaying)
        engine.resetLog()

        clickNext()
        XCTAssertEqual(core.currentIndex, 1, "▶▶ works before anything has played")
        XCTAssertTrue(core.isPlaying)
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track1.mp3"],
                       "it starts track 1, skipping the displayed track 0")
    }
}
