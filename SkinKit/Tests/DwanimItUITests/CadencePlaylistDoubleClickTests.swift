import AppKit
import SwiftUI
import XCTest
import PlayerCore
@testable import DwanimItUI

// MARK: - RecordingPlaybackEngine

/// An in-memory `AudioPlaybackEngine` that records every `load` / `play`, so the
/// harness can assert WHICH track a UI gesture actually started (not just that
/// something happened).
final class RecordingPlaybackEngine: AudioPlaybackEngine {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var volume: Float = 1.0
    var pan: Float = 0.0
    var onPlaybackFinished: (@Sendable @MainActor () -> Void)?

    private(set) var loadedURLs: [URL] = []
    private(set) var playCount = 0

    func load(_ url: URL) throws { loadedURLs.append(url) }
    func play() { playCount += 1; isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }
    func seek(to time: TimeInterval) {}
}

// MARK: - CadencePlaylistDoubleClickTests
//
// In-process reproduction harness for the Cadence playlist's mouse contract:
//   - a SINGLE click on a row selects it and does NOT play;
//   - a DOUBLE click on a row plays THAT track (the
//     `.contextMenu(forSelectionType:primaryAction:)` hook on the `List`).
//
// It hosts the REAL `CadencePlaylist` (pure SwiftUI) in an `NSHostingView` inside
// a real `NSWindow`, walks the hosted hierarchy to the `NSTableView` SwiftUI's
// `List` is backed by on macOS (`SwiftUIOutlineListView`, an `NSOutlineView`), and
// drives SYNTHESIZED `NSEvent`s through the window's normal event path — no real
// mouse, no CGEvent posting, no accessibility permission.
//
// DISPATCH MODEL (established against a plain `NSTableView` first):
//   1. `NSTableView.mouseDown` only performs selection when its window is KEY,
//      and a window can only become key once the PROCESS is active. The test
//      runner starts with `.prohibited` activation, so `setUp` switches to
//      `.regular`, activates via `NSRunningApplication`, and pumps until the
//      window reports `isKeyWindow`. (The runner briefly appears in the Dock.)
//   2. The table's click tracking loop calls
//      `window.nextEvent(matching:…, inMode: .eventTracking)`, so the matching
//      mouse-UP is posted to `NSApp`'s queue BEFORE the mouse-DOWN is handed to
//      `window.sendEvent` — otherwise the tracking loop would block.
//   3. A double-click is a `clickCount: 1` down/up followed by a `clickCount: 2`
//      down/up at the same point; AppKit fires the table's double-action on the
//      second down, which is what SwiftUI's `primaryAction` is wired to.
@MainActor
final class CadencePlaylistDoubleClickTests: XCTestCase {

    private var window: NSWindow!
    private var hosting: NSHostingView<CadencePlaylist>!
    private var engine: RecordingPlaybackEngine!
    private var core: PlayerCore!

    private let trackCount = 4
    /// The row every test clicks (0-based); never the initially-current row 0, so
    /// "played the clicked row" is distinguishable from "played whatever was current".
    private let targetRow = 2

    // MARK: Lifecycle

    override func setUp() async throws {
        _ = NSApplication.shared
        engine = RecordingPlaybackEngine()
        core = PlayerCore(engine: engine)
        core.load((0..<trackCount).map {
            Track(url: URL(fileURLWithPath: "/tmp/dwanim-harness/track\($0).mp3"),
                  title: "Track \($0)", duration: 120)
        })
        let view = CadencePlaylist(
            core: core, theme: .graphite,
            onAddFiles: nil, onAddFolder: nil, onAddURLs: nil, onPlaylistEdited: nil
        )
        hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 300)
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting

        // Dispatch-model step 1: the process must be active for the window to be key.
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date(timeIntervalSinceNow: 3)
        repeat {
            window.makeKeyAndOrderFront(nil)
            pump(0.1)
        } while !window.isKeyWindow && Date() < deadline
        pump(0.2) // let SwiftUI lay out the List rows
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.close()
        window = nil
        hosting = nil
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

    private func findTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for sub in view.subviews {
            if let found = findTableView(in: sub) { return found }
        }
        return nil
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

    /// The List's backing table, with the harness preconditions pinned so a
    /// failure downstream is unambiguous (rows present, window key).
    private func table() throws -> NSTableView {
        let t = try XCTUnwrap(findTableView(in: hosting), "List must be backed by an NSTableView")
        XCTAssertEqual(t.numberOfRows, trackCount, "one row per track")
        XCTAssertTrue(window.isKeyWindow, "harness precondition: the window is key (process active)")
        return t
    }

    private func rowCenterInWindow(_ table: NSTableView, row: Int) -> NSPoint {
        let r = table.convert(table.rect(ofRow: row), to: nil)
        return NSPoint(x: r.midX, y: r.midY)
    }

    /// Dispatch-model step 2: queue the UP first, then hand the DOWN to the window.
    private func click(at p: NSPoint, clickCount: Int) {
        NSApp.postEvent(mouseEvent(.leftMouseUp, at: p, clickCount: clickCount), atStart: false)
        window.sendEvent(mouseEvent(.leftMouseDown, at: p, clickCount: clickCount))
        pump(0.1)
    }

    private func doubleClick(at p: NSPoint) {
        click(at: p, clickCount: 1)
        click(at: p, clickCount: 2)
        pump(0.2)
    }

    // MARK: Tests

    /// Control: a single click selects the row and must NOT start playback.
    func testSingleClick_selectsRow_doesNotPlay() throws {
        let t = try table()
        click(at: rowCenterInWindow(t, row: targetRow), clickCount: 1)

        XCTAssertEqual(t.selectedRowIndexes, IndexSet(integer: targetRow), "single click selects the clicked row")
        XCTAssertEqual(core.currentIndex, 0, "single click leaves the current track alone")
        XCTAssertFalse(core.isPlaying, "single click does not play")
        XCTAssertEqual(engine.playCount, 0, "engine.play never called on a single click")
        XCTAssertEqual(engine.loadedURLs, [], "engine.load never called on a single click")
    }

    /// The owner-reported contract: a double click plays THE CLICKED track.
    func testDoubleClick_playsClickedRow() throws {
        let t = try table()
        doubleClick(at: rowCenterInWindow(t, row: targetRow))

        XCTAssertEqual(t.selectedRowIndexes, IndexSet(integer: targetRow), "the clicked row is selected")
        XCTAssertEqual(core.currentIndex, targetRow, "double-click makes the clicked row current")
        XCTAssertTrue(core.isPlaying, "double-click starts playback")
        XCTAssertEqual(engine.loadedURLs.map(\.lastPathComponent), ["track\(targetRow).mp3"],
                       "the engine loaded exactly the clicked track")
        XCTAssertEqual(engine.playCount, 1, "engine.play called exactly once")
    }
}
