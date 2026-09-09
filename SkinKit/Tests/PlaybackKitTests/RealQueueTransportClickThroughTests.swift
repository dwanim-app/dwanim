import AppKit
import AVFoundation
import Foundation
import SwiftUI
import XCTest
import PlayerCore
@testable import DwanimItUI
@testable import PlaybackKit

// MARK: - Fixtures

/// The OPTIONAL override that points the acceptance tests at the owner's own
/// multi-format clips instead of the generated fixture set.
///
/// Those clips are out of tree by design — real music under CC BY / CC BY-SA /
/// PD terms, not fixtures to commit into an MIT repository — so the directory is
/// named by an ENVIRONMENT VARIABLE rather than written into the source.
///
/// It used to be the ONLY source, which meant the acceptance tests skipped on
/// every machine that did not have that directory, the daily CI included: a
/// skip is silent, so a permanently dead acceptance test went on reading like
/// the strongest evidence in the suite. The default source is now
/// `GeneratedClipLibrary`, which encodes an equivalent matrix at test time, and
/// this variable only SWAPS it for real music:
///
/// ```sh
/// DWANIM_REAL_CLIPS=~/Music/dwanim-test-clips swift test --filter RealQueue
/// ```
///
/// A variable that is set but does not name the expected clip set is a
/// FAILURE, not a skip — an override that cannot be honoured is a mistake worth
/// seeing, and there is no longer any reason to fall back quietly.
enum RealClipLibrary {

    /// The environment variable that points at the clip set.
    static let environmentKey = "DWANIM_REAL_CLIPS"

    /// Resolve the directory from an arbitrary environment dictionary. Pure, so
    /// the resolution rule itself is unit-testable (`RealClipLibraryTests`)
    /// without touching the process environment — which matters precisely
    /// because everything else in this file is allowed to skip.
    static func directory(in environment: [String: String]) -> URL? {
        guard let raw = environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return URL(
            fileURLWithPath: (raw as NSString).expandingTildeInPath,
            isDirectory: true
        )
    }

    /// The directory for this process, or `nil` when the variable is unset.
    static var directory: URL? { directory(in: ProcessInfo.processInfo.environment) }

    /// What to say when the variable is set but the directory does not hold the
    /// clip set. It names the variable and what belongs in it, so the message is
    /// an instruction rather than a shrug.
    static var misconfiguredOverrideReason: String {
        """
        \(environmentKey) is set but does not name the owner's multi-format clip \
        set (01_flac… through 08_aac-raw…, plus the N1–N3 negatives). Point it at \
        that directory, or unset it to run against the generated fixture set
        """
    }
}

/// One queue entry: the file, plus the format the ENGINE must report once that file
/// is loaded. The expected rate/channels are written out rather than read back from
/// the file, so a decoder that quietly resampled would be caught.
private struct Clip {
    let name: String
    let sampleRate: Double
    let channels: Int
    func url(in directory: URL) -> URL { directory.appendingPathComponent(name) }
}

/// Where one run's audio comes from: the generated fixture set by default, the
/// owner's downloaded clips when `DWANIM_REAL_CLIPS` overrides it.
///
/// Both sources present the SAME shape — eight rows crossing the same rate and
/// channel boundaries in the same order, plus one file that opens and renders
/// nothing — so every assertion in this file is written once and runs against
/// either.
private struct ClipSource {
    /// Named in the run's log so a reader can tell which set produced it.
    let label: String
    let directory: URL
    let queue: [Clip]
    /// The file the decoder OPENS and cannot read a frame from.
    let silent: URL
}

/// The override was set to a directory that does not hold the owner's clip set.
private struct MisconfiguredClipOverride: Error, CustomStringConvertible {
    let directory: URL
    var description: String {
        "\(RealClipLibrary.environmentKey) points at \(directory.path): "
        + RealClipLibrary.misconfiguredOverrideReason
    }
}

// MARK: - RealClipLibraryTests

/// The one part of this file that ALWAYS runs. It guards the fix for a test that
/// could only ever skip: if the resolution rule breaks, this goes red on any
/// machine, clips or no clips.
final class RealClipLibraryTests: XCTestCase {

    func testAnUnsetVariableResolvesToNoDirectory() {
        XCTAssertNil(RealClipLibrary.directory(in: [:]))
    }

    func testABlankVariableResolvesToNoDirectory() {
        XCTAssertNil(RealClipLibrary.directory(in: [RealClipLibrary.environmentKey: "   "]))
    }

    func testTheVariableNamesTheDirectory() {
        let resolved = RealClipLibrary.directory(in: [RealClipLibrary.environmentKey: "/music/clips"])
        XCTAssertEqual(resolved?.path, "/music/clips")
    }

    func testALeadingTildeIsExpanded() {
        let resolved = RealClipLibrary.directory(in: [RealClipLibrary.environmentKey: "~/clips"])
        XCTAssertEqual(resolved?.path, NSHomeDirectory() + "/clips")
        XCTAssertFalse(resolved?.path.contains("~") ?? true)
    }

    func testTheMisconfigurationMessageNamesTheVariableSoTheFailureIsActionable() {
        XCTAssertTrue(
            RealClipLibrary.misconfiguredOverrideReason.contains(RealClipLibrary.environmentKey)
        )
    }
}

// MARK: - RealQueueTransportClickThroughTests
//
// THE ACCEPTANCE TEST. Everything in it is real: real music files in eight
// container/codec combinations, the real `AVAudioEnginePlayer` (not a fake), a
// real `PlayerCore`, the real `CadenceTransport` hosted in a real `NSWindow`, and
// real synthesized `NSEvent` clicks on the real ▶▶ / ◀◀ / ▶ buttons.
//
// WHAT IT PROVES, per press: the selection moved by exactly one, the ENGINE
// actually loaded THAT file (its sample rate, channel count and duration all match
// the file on disk), playback is running, and the render clock ADVANCES. The last
// one is the load-bearing assertion — a half-wired `AVAudioEngine` graph reports
// "playing" with a frozen clock and silence, which is exactly the -10868
// (`kAudioUnitErr_FormatNotSupported`) failure the format-change fix exists to
// prevent. Walking the queue by hand takes that fix through the MANUAL-navigation
// path, where every step crosses a 44.1k<->48k and/or mono<->stereo boundary:
//
//   01 flac  44.1k stereo -> 02 wav 44.1k stereo -> 03 mp3 44.1k stereo
//   -> 04 aiff 48k stereo   (sample-rate change)
//   -> 05 aac  48k mono     (channel change)
//   -> 06 alac 44.1k mono   (sample-rate change)
//   -> 07 caf  48k mono     (sample-rate change)
//   -> 08 aac  44.1k stereo (sample rate AND channel change)
//
// ...then the WRAP steps with repeat on (▶▶ on the last track lands on the first,
// ◀◀ on the first lands on the last), then the whole queue backwards.
//
// WHERE THE AUDIO COMES FROM. By default the queue is ENCODED AT TEST TIME by
// `GeneratedClipLibrary` — real FLAC / WAVE / ADTS / AIFF / MPEG-4 / CAF files
// written by the system encoder from synthesized PCM — so a plain `swift test`
// runs this whole click-through with no setup at all. It used to run only when
// `DWANIM_REAL_CLIPS` named the owner's downloaded music, which meant the daily
// CI skipped the strongest test in the suite every night.
//
// `DWANIM_REAL_CLIPS` still works, and now means "use the owner's real music
// instead": same steps, same assertions, different bytes. Setting it to a
// directory that does not hold that set FAILS rather than skips — an override
// that cannot be honoured is a mistake, not an environment.
//
// The one legitimate skip left is `AudioOutputDeviceProbe`: a machine with no
// audio output route cannot observe playback at all. That probe is INDEPENDENT
// of the player under test on purpose (see its own doc): a frozen clock must
// fail, not skip.
//
// This test emits real audio for a few seconds, like the other real-playback tests
// in this target.
@MainActor
final class RealQueueTransportClickThroughTests: XCTestCase {

    /// The owner's queue, in the order the buttons walk it. Ordered so that five
    /// of the seven forward steps cross a sample-rate and/or channel-count
    /// boundary.
    private static let ownerQueue: [Clip] = [
        Clip(name: "01_flac_real_44k_stereo.flac", sampleRate: 44_100, channels: 2),
        Clip(name: "02_wav_real_44k_stereo.wav", sampleRate: 44_100, channels: 2),
        Clip(name: "03_mp3_real_44k_stereo.mp3", sampleRate: 44_100, channels: 2),
        Clip(name: "04_aiff_conv_48k_stereo.aiff", sampleRate: 48_000, channels: 2),
        Clip(name: "05_aac-m4a_conv_48k_mono.m4a", sampleRate: 48_000, channels: 1),
        Clip(name: "06_alac-m4a_conv_44k_mono.m4a", sampleRate: 44_100, channels: 1),
        Clip(name: "07_caf_conv_48k_mono.caf", sampleRate: 48_000, channels: 1),
        Clip(name: "08_aac-raw_conv_44k_stereo.aac", sampleRate: 44_100, channels: 2)
    ]

    /// The one file in the owner's set that OPENS and yet renders nothing: an
    /// Ogg-wrapped FLAC. `AVAudioFile` reports 44100 Hz / 2 ch / 100.5 s for an
    /// 8-second clip, `AVAudioEnginePlayer.load` succeeds, and the scheduled
    /// segment drains ~18 ms after `play()` without a frame reaching the output.
    /// The other two negatives (ogg-vorbis, opus) decode normally on this OS.
    ///
    /// `GeneratedClipLibrary.hollowClipName` is the hermetic equivalent, and is
    /// used even in override mode if this file is not beside the others — so no
    /// arrangement of the override can turn this test back into a skip.
    private static let ownerSilentClipName = "N3_flacInOgg_real_44k_stereo.flac.oga"

    /// The generated queue: the same eight crossings, encoded at test time.
    /// The expected rate/channels come from the generator's own matrix, so the
    /// two cannot drift apart.
    private static var generatedQueue: [Clip] {
        get throws {
            _ = try GeneratedClipLibrary.directory()
            return GeneratedClipLibrary.matrix.map {
                Clip(name: $0.name, sampleRate: $0.sampleRate, channels: $0.channels)
            }
        }
    }

    /// The owner's clips when the override names them, else the generated set.
    private static func resolveSource() throws -> ClipSource {
        if let owner = RealClipLibrary.directory {
            guard ownerQueue.allSatisfy({
                FileManager.default.fileExists(atPath: $0.url(in: owner).path)
            }) else { throw MisconfiguredClipOverride(directory: owner) }

            let ownerSilent = owner.appendingPathComponent(ownerSilentClipName)
            return ClipSource(
                label: "the owner's clips at \(owner.path)",
                directory: owner,
                queue: ownerQueue,
                silent: FileManager.default.fileExists(atPath: ownerSilent.path)
                    ? ownerSilent
                    : try GeneratedClipLibrary.hollowClip()
            )
        }

        let generated = try GeneratedClipLibrary.directory()
        return ClipSource(
            label: "generated fixtures at \(generated.path)",
            directory: generated,
            queue: try generatedQueue,
            silent: try GeneratedClipLibrary.hollowClip()
        )
    }

    // MARK: - Live objects

    /// The resolved source, established in `setUp` before the device guard.
    private var source: ClipSource!
    /// The queue this run walks — `source.queue`, hoisted for readability.
    private var queue: [Clip] { source.queue }
    private var clipDirectory: URL { source.directory }
    private var window: NSWindow!
    private var hosting: NSHostingView<CadenceTransport>!
    private var player: AVAudioEnginePlayer!
    private var core: PlayerCore!

    /// The ordered running commentary, printed at the end so the run can be read
    /// back step by step rather than only as a pass/fail.
    private var log: [String] = []

    /// Which clip set produced that commentary — printed with it, so a log can
    /// never be misread as coming from the other source.
    private var sourceLabel = "(unresolved)"

    // MARK: - Lifecycle

    override func setUp() async throws {
        // Resolving the source ENCODES the fixture set on first use; it never
        // skips, and a broken override or a failed encode is reported as an
        // error rather than swallowed.
        source = try Self.resolveSource()
        sourceLabel = source.label
        try XCTSkipUnless(
            AudioOutputDeviceProbe.hasOutputDevice(),
            "no audio output route on this machine — real playback cannot be observed"
        )
        _ = NSApplication.shared
        // MUTED, and muted BEFORE the core is built: this suite walks a whole
        // eight-format queue in real time, and it runs unattended from the
        // owner's daily 07:00 `swift test` job — at the default volume that is
        // half a minute of music out of the speakers every morning. `PlayerCore`
        // reads `engine.volume` here in its initializer and re-pushes it on
        // every load, so this one line keeps every track of every scenario
        // silent. Nothing this file asserts lives downstream of the mixer's
        // output volume — see `SilentRealPlayback`.
        player = SilentRealPlayback.makePlayer()
        core = PlayerCore(engine: player)
        core.load(queue.map { Track(url: $0.url(in: clipDirectory)) })

        hosting = NSHostingView(rootView: CadenceTransport(core: core, theme: .graphite))
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 60)
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting

        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [])
        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date(timeIntervalSinceNow: 3)
        repeat {
            window.makeKeyAndOrderFront(nil)
            pump(0.1)
        } while !window.isKeyWindow && Date() < deadline
        pump(0.2)
    }

    override func tearDown() async throws {
        core?.pause()
        window?.orderOut(nil)
        window?.close()
        window = nil
        hosting = nil
        core = nil
        player = nil
        source = nil
        if !log.isEmpty {
            print("=== FF/FB click-through over the multi-format queue — \(sourceLabel) ===")
            log.forEach { print($0) }
            log.removeAll()
        }
    }

    // MARK: - Event plumbing (the established in-process click model)

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
        pump(0.2)
    }

    // MARK: - Button geometry (mirrors CadenceTransport's own layout)

    private enum TransportButton: CaseIterable {
        case previous, playPause, stop, next
        var width: CGFloat { self == .playPause ? 44 : 32 }
    }

    private func center(of button: TransportButton) -> NSPoint {
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
        return NSPoint(x: x + button.width / 2, y: hosting.bounds.midY)
    }

    /// The Repeat pill's centre. The left zone is a fixed 176 pt box holding
    /// `HStack(spacing: 4)` of text pills; each pill is its text in the 11 pt
    /// system font plus 8 pt of padding a side. Under `swift test` the String
    /// Catalog is uncompiled, so the labels render as their English source keys.
    private func repeatPillCenter() -> NSPoint {
        func width(_ s: String, bold: Bool = false) -> CGFloat {
            let font = NSFont.systemFont(ofSize: 11, weight: bold ? .semibold : .regular)
            return ceil(NSAttributedString(string: s, attributes: [.font: font]).size().width) + 16
        }
        let shuffle = width("Shuffle")
        let repeatWidth = width(CadenceTransport.repeatLabelKey(for: core.repeatMode))
        return NSPoint(x: shuffle + 4 + repeatWidth / 2, y: hosting.bounds.midY)
    }

    private func clickButton(_ button: TransportButton) { click(at: center(of: button)) }
    private func clickRepeatPill() { click(at: repeatPillCenter()) }

    // MARK: - Per-step verification

    /// Spin the run loop until the player's render clock passes `threshold`.
    @discardableResult
    private func clockAdvances(past threshold: TimeInterval, within seconds: TimeInterval = 3.0) -> Bool {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while player.currentTime < threshold, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            pump(0.0)
        }
        return player.currentTime >= threshold
    }

    /// The full per-press assertion: the queue index is where it should be, the
    /// ENGINE holds that exact file (rate + channels + duration), playback is
    /// running, and the render clock really moves.
    private func verifyLanded(on index: Int, after step: String) {
        let clip = queue[index]
        XCTAssertEqual(core.currentIndex, index, "\(step): wrong queue index")
        XCTAssertEqual(core.currentTrack?.url.lastPathComponent, clip.name, "\(step): wrong track selected")

        // The engine's own view of what it loaded — proof the click reached the
        // real decoder, not just the model.
        XCTAssertEqual(player.sampleRateHz, clip.sampleRate, accuracy: 0.5,
                       "\(step): engine sample rate is not \(clip.name)'s")
        XCTAssertEqual(player.channelCount, clip.channels,
                       "\(step): engine channel count is not \(clip.name)'s")
        let onDisk = (try? AVAudioFile(forReading: clip.url(in: clipDirectory))).map {
            Double($0.length) / $0.processingFormat.sampleRate
        }
        if let onDisk {
            XCTAssertEqual(player.duration, onDisk, accuracy: 0.05,
                           "\(step): engine duration is not \(clip.name)'s")
        }

        XCTAssertTrue(core.isPlaying, "\(step): the model says playback is not running")

        // ...and it is doing all of that SILENTLY. Asserted per step rather than
        // once in `setUp` because the core re-pushes its volume to the engine on
        // every load: this is the check that a track change (or a format-change
        // re-wire) cannot quietly restore the default volume and turn the daily
        // 07:00 CI run into an alarm clock while every other assertion here
        // stays green.
        XCTAssertEqual(player.volume, 0, accuracy: 1e-6,
                       "\(step): the run must stay muted (see SilentRealPlayback)")

        let advanced = clockAdvances(past: 0.12)
        XCTAssertTrue(advanced,
                      "\(step): the render clock never advanced — silent playback "
                      + "(the -10868 half-wired-graph symptom) at a format change")

        log.append(String(
            format: "%@ -> [%d] %@  %.0f Hz / %dch  dur %.2fs  clock %.3fs  playing=%@",
            step, index, clip.name, player.sampleRateHz, player.channelCount,
            player.duration, player.currentTime, core.isPlaying ? "yes" : "no"
        ))
    }

    // MARK: - The run

    /// FORWARD with ▶▶ through all eight formats, WRAP with repeat on, then
    /// BACKWARD with ◀◀ all the way home.
    func testClickingForwardAndBackThroughTheRealMultiFormatQueueReallyPlaysEveryStep() throws {
        XCTAssertEqual(core.playlist.count, queue.count, "the whole queue loaded")

        // Start the first track with a REAL click on ▶ (not core.play()).
        XCTAssertFalse(core.isPlaying)
        clickButton(.playPause)
        verifyLanded(on: 0, after: "click ▶")

        // --- Forward: seven ▶▶ presses, 01 -> 08 -------------------------------
        for index in 1..<queue.count {
            let from = queue[index - 1]
            let to = queue[index]
            let boundary = (from.sampleRate == to.sampleRate ? "" : " [rate change]")
                + (from.channels == to.channels ? "" : " [channel change]")
            XCTAssertTrue(core.canGoNext, "▶▶ must be live mid-queue (at index \(index - 1))")
            clickButton(.next)
            verifyLanded(on: index, after: "click ▶▶ (\(index))\(boundary)")
        }

        // --- The end of the queue with repeat OFF ------------------------------
        // ▶▶ is DISABLED here, so the click must change nothing at all.
        XCTAssertEqual(core.repeatMode, .off)
        XCTAssertFalse(core.canGoNext, "▶▶ is dimmed on the last track with repeat off")
        let clockBefore = player.currentTime
        clickButton(.next)
        XCTAssertEqual(core.currentIndex, queue.count - 1, "a disabled ▶▶ does not move")
        XCTAssertTrue(core.isPlaying, "a disabled ▶▶ does not stop playback")
        XCTAssertGreaterThanOrEqual(player.currentTime, clockBefore, "playback carried on")
        log.append("click ▶▶ at the end with repeat OFF -> disabled: no move, still playing")

        // --- Turn repeat on by CLICKING the Repeat pill, then wrap forward -----
        clickRepeatPill()
        XCTAssertEqual(core.repeatMode, .all, "one press of Repeat reaches .all")
        XCTAssertTrue(core.canGoNext, "with repeat on, ▶▶ is live at the end")
        log.append("click Repeat pill -> repeatMode = .all")

        clickButton(.next)
        verifyLanded(on: 0, after: "click ▶▶ WRAP 08 -> 01")

        // --- Wrap backward: ◀◀ from the first track lands on the last ----------
        clickButton(.previous)
        verifyLanded(on: queue.count - 1, after: "click ◀◀ WRAP 01 -> 08")

        // --- Backward: seven ◀◀ presses, 08 -> 01 ------------------------------
        for index in stride(from: queue.count - 2, through: 0, by: -1) {
            let from = queue[index + 1]
            let to = queue[index]
            let boundary = (from.sampleRate == to.sampleRate ? "" : " [rate change]")
                + (from.channels == to.channels ? "" : " [channel change]")
            XCTAssertTrue(core.canGoPrevious, "◀◀ must be live (at index \(index + 1))")
            clickButton(.previous)
            verifyLanded(on: index, after: "click ◀◀ (\(queue.count - 1 - index))\(boundary)")
        }

        // --- Repeat .one wraps for EXPLICIT navigation too ---------------------
        // A second press of the pill reaches `.one`; ◀◀ from the first track must
        // still wrap to the last (auto-advance is what replays under `.one`).
        clickRepeatPill()
        XCTAssertEqual(core.repeatMode, .one, "a second press of Repeat reaches .one")
        log.append("click Repeat pill -> repeatMode = .one")

        clickButton(.previous)
        verifyLanded(on: queue.count - 1, after: "click ◀◀ WRAP under .one 01 -> 08")

        clickButton(.next)
        verifyLanded(on: 0, after: "click ▶▶ WRAP under .one 08 -> 01")

        // 1 play + 7 ▶▶ + 1 disabled note + 2 Repeat-pill notes + 4 wraps + 7 ◀◀.
        XCTAssertEqual(log.count, 22, "every step in the run was recorded")
    }

    // MARK: - ◀◀ over UNPLAYABLE files (the backward-recovery defect)

    /// The acceptance form of the `previous()` recovery-direction fix: real
    /// clicks, the real `AVAudioEnginePlayer`, real music — and real files the
    /// real decoder really refuses.
    ///
    /// Before the fix, `playCurrent`'s recovery walked FORWARD no matter which
    /// button started it, so a `◀◀` onto an unplayable file put the listener back
    /// on the track they had just left: one dead file made every track before it
    /// permanently unreachable with `◀◀` (`canGoPrevious` said `true` for every
    /// one of those inert presses). `▶▶` was never affected, so the model was
    /// silently asymmetric. This walks a queue whose 2nd and 4th rows cannot be
    /// opened at all, and asserts the walk gets home.
    ///
    /// THE DEAD ROWS ARE MADE HERE, not borrowed from the owner's clip set: every
    /// one of that set's three "negative" containers (ogg-vorbis, opus,
    /// flac-in-ogg) actually OPENS on this OS, so none of them exercises the
    /// throwing path. A file of zero bytes-worth of nothing does, and being
    /// generated it cannot quietly start decoding after an OS update.
    func testClickingBackThroughAQueueWithUnplayableFilesWalksHomeInsteadOfStalling() throws {
        let deadDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwanim-unplayable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: deadDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: deadDirectory) }

        // 0 flac · 1 DEAD · 2 wav · 3 DEAD · 4 aiff · 5 alac · 6 caf
        let live = [queue[0], queue[1], queue[3], queue[5], queue[6]]
        let urls = [
            live[0].url(in: clipDirectory), try GeneratedClipLibrary.deadFile("broken-a.mp3", in: deadDirectory),
            live[1].url(in: clipDirectory), try GeneratedClipLibrary.deadFile("broken-b.mp3", in: deadDirectory),
            live[2].url(in: clipDirectory), live[3].url(in: clipDirectory), live[4].url(in: clipDirectory)
        ]

        // The premise, verified against the REAL decoder rather than assumed.
        let probe = SilentRealPlayback.makePlayer()
        XCTAssertThrowsError(try probe.load(urls[1]), "row 1 must be undecodable")
        XCTAssertThrowsError(try probe.load(urls[3]), "row 3 must be undecodable")
        XCTAssertNoThrow(try probe.load(urls[0]), "the live rows must decode")

        core.load(urls.map { Track(url: $0) })
        core.repeatMode = .off
        pump(0.2)
        core.select(6)
        pump(0.3)
        XCTAssertEqual(core.currentIndex, 6, "parked on the last track")
        XCTAssertTrue(core.isPlaying)
        log.append("dead-file queue: parked on [6] \(urls[6].lastPathComponent)")

        // Five REAL ◀◀ presses. Rows 3 and 1 are the corpses: a press onto one
        // must step FURTHER BACK, never forward.
        var trail: [Int] = []
        for press in 1...5 {
            XCTAssertTrue(core.canGoPrevious, "press \(press): ◀◀ claims it can act")
            let before = core.currentIndex ?? -1
            clickButton(.previous)
            let after = core.currentIndex ?? -1
            trail.append(after)
            XCTAssertLessThanOrEqual(after, before, "press \(press): ◀◀ must never move FORWARD")
            log.append(String(
                format: "click ◀◀ over dead files (%d): [%d] -> [%d] %@  playing=%@",
                press, before, after, urls[after].lastPathComponent, core.isPlaying ? "yes" : "no"
            ))
        }

        XCTAssertEqual(trail, [5, 4, 2, 0, 0],
                       "6 -> 5 -> 4 -> (3 dead) 2 -> (1 dead) 0 -> restart 0")
        XCTAssertTrue(core.isPlaying, "the walk ended on a track that really plays")
        XCTAssertEqual(core.currentTrack?.url, urls[0])
        XCTAssertTrue(clockAdvances(past: 0.12), "and its render clock really advances")

        // ▶▶ over the same corpse still steps FORWARD — the direction fix was not
        // applied globally.
        clickButton(.next)
        XCTAssertEqual(core.currentIndex, 2, "▶▶ from 0 steps over the dead row 1 -> 2")
        log.append("click ▶▶ over the same dead row: [0] -> [2] \(urls[2].lastPathComponent)")
    }

    // MARK: - ◀◀ over a file that OPENS but renders nothing

    /// The other half of the unplayable-file story, and the one the synthetic
    /// dead files above cannot reach.
    ///
    /// `playCurrent`'s recovery walk only ever ran when `engine.load(_:)` THREW.
    /// The owner's `N3_flacInOgg_real_44k_stereo.flac.oga` does not throw — it
    /// OPENS (44100 Hz / 2 ch), claims 100.5 s for an 8-second clip, and then its
    /// scheduled segment drains ~18 ms after `play()` without rendering a frame.
    /// So it took the auto-advance path instead: `◀◀` onto it bounced the
    /// listener FORWARD to the track they had just left, making every row before
    /// it unreachable with `◀◀`, and under `.one` it parked them on silence for
    /// ever.
    ///
    /// Measured before the fix, over the owner's own queue: `◀◀` from row 10 gave
    /// the trail `[9, 8, 8, 8, 8]` — a hard stall — and `.one` gave
    /// `[7, 7, 7, 7, …]`.
    ///
    /// This test is about where the transport LANDS; the per-step format and
    /// render-clock evidence is the click-through test above. (Every scenario in
    /// this file now runs at volume 0 — see `setUp` — so that is no longer
    /// something this one test does differently.)
    func testClickingBackPastAFileThatOpensButRendersNothingStillWalksHome() throws {
        // Supplied by whichever source this run resolved to: the owner's
        // Ogg-wrapped FLAC, or the generated hollow CAF. Never absent, so this
        // test can no longer skip.
        let silent = source.silent

        // The premise, verified against the REAL decoder rather than assumed:
        // unlike a corrupt file, this one LOADS. That is the whole point.
        let probe = SilentRealPlayback.makePlayer()
        XCTAssertNoThrow(try probe.load(silent),
                         "the premise is a file the engine ACCEPTS")
        XCTAssertGreaterThan(probe.duration, 60,
                             "and one that claims far more audio than it holds")

        // 0 flac · 1 wav · 2 mp3 · 3 SILENT · 4 alac · 5 caf
        let live = [queue[0], queue[1], queue[2], queue[5], queue[6]]
        let urls = [
            live[0].url(in: clipDirectory), live[1].url(in: clipDirectory),
            live[2].url(in: clipDirectory), silent,
            live[3].url(in: clipDirectory), live[4].url(in: clipDirectory)
        ]

        core.load(urls.map { Track(url: $0) })
        core.repeatMode = .off
        core.select(5)
        pump(0.4)
        XCTAssertEqual(core.currentIndex, 5, "parked on the last track")
        log.append("silent-file queue: parked on [5] \(urls[5].lastPathComponent)")

        // Four REAL ◀◀ presses. The second lands on the silent row; the walk must
        // carry on BACKWARD rather than bouncing to the row it came from.
        var trail: [Int] = []
        for press in 1...4 {
            XCTAssertTrue(core.canGoPrevious, "press \(press): ◀◀ claims it can act")
            let before = core.currentIndex ?? -1
            clickButton(.previous)
            pump(0.4)                              // let the instant finish arrive
            let after = core.currentIndex ?? -1
            trail.append(after)
            XCTAssertLessThanOrEqual(after, before, "press \(press): ◀◀ must never move FORWARD")
            log.append(String(
                format: "click ◀◀ past the silent row (%d): [%d] -> [%d] %@  playing=%@",
                press, before, after, urls[after].lastPathComponent,
                core.isPlaying ? "yes" : "no"
            ))
        }

        XCTAssertEqual(trail, [4, 2, 1, 0],
                       "5 -> 4 -> (3 renders nothing) 2 -> 1 -> 0")
        XCTAssertEqual(core.currentTrack?.url, urls[0])
        XCTAssertTrue(core.isPlaying, "the walk ended on a track that really plays")
        XCTAssertTrue(clockAdvances(past: 0.12), "and its render clock really advances")

        // ▶▶ over the same row still steps FORWARD, in one press.
        clickButton(.next)
        pump(0.4)
        XCTAssertEqual(core.currentIndex, 1, "0 -> 1")
        clickButton(.next)
        pump(0.4)
        XCTAssertEqual(core.currentIndex, 2, "1 -> 2")
        clickButton(.next)
        pump(0.5)
        XCTAssertEqual(core.currentIndex, 4, "2 -> (3 renders nothing) -> 4, forward as ever")
        log.append("click ▶▶ over the silent row: [2] -> [4] \(urls[4].lastPathComponent)")

        // Under `.one` the silent row must not hold the listener either: it used
        // to replay silence for ever.
        core.repeatMode = .one
        core.select(4)
        pump(0.4)
        clickButton(.previous)
        pump(0.5)
        XCTAssertEqual(core.currentIndex, 2,
                       "under .one, ◀◀ onto the silent row walks BACK instead of sticking")
        XCTAssertTrue(core.isPlaying)
        log.append("under .one: click ◀◀ from [4] -> [2] (the silent row does not stick)")
    }
}
