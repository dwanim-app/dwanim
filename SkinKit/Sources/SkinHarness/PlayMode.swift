import Foundation
import PlaybackKit
import PlayerCore

// SkinHarness play mode: a dev-only path that wires the pure playback core to the
// concrete audio engine and exercises a single local file end to end. This lives
// in its own file (per the harness's "thin shell, small functions" convention);
// `main.swift` only dispatches here when `--play` is present.
//
// Usage: SkinHarness --play <path-to-audio>
//
// Flow: build a `PlayerCore` over the concrete engine, load the file as a
// one-item playlist, print the loaded duration, start playback, then drive the
// main run loop while polling the core's position roughly twice a second and
// printing a one-line progress readout. It exits cleanly (status 0) when the
// track finishes, and bails to stderr with status 1 if the file cannot be loaded
// or the engine cannot start (e.g. a headless context with no output device).
// A hard safety cap on the run loop guarantees the process can never hang.

// MARK: - Time formatting

/// Format a non-negative number of seconds as `MM:SS` (minutes are not capped at
/// two digits, so a long track still reads correctly). Non-finite or negative
/// inputs clamp to `00:00`.
func formatTimecode(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "00:00" }
    let total = Int(seconds.rounded(.down))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

// MARK: - Entry point

/// Run the play mode for `path` and never return: it drives the run loop and
/// exits the process itself (0 on a clean finish, 1 on a load/engine failure).
func runPlayMode(path: String) -> Never {
    let fileURL = URL(fileURLWithPath: path)

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        playFail("No file at \(path)")
    }

    let core = PlayerCore(engine: AVAudioEnginePlayer())
    core.load([Track(url: fileURL)])

    // `load` selects the track but does not open it in the engine, so the
    // duration is not known until playback actually loads the file. Start
    // playback, then read back the engine-reported duration.
    core.play()

    // If the core is not playing after a play() call, the track was either
    // unplayable (the engine threw on load and the core skipped past it) or the
    // audio engine could not start its output (no device). Either way there is
    // nothing to render — report and exit non-zero rather than spin the run loop.
    guard core.isPlaying else {
        playFail(
            "Could not start playback of \(path). The file may be unreadable, in "
                + "an unsupported format, or there is no available audio output "
                + "device in this context."
        )
    }

    let duration = core.duration
    print("Loaded \(path) (duration \(formatTimecode(duration)))")

    drivePlaybackRunLoop(core: core, duration: duration)
}

// MARK: - Run loop

/// Drive the main run loop while `core` plays, printing progress about twice a
/// second. Returns (via `exit(0)`) when the track finishes, and is bounded by a
/// hard cap of `duration` plus a few seconds of slack so it can never hang even
/// if the finish signal is missed.
private func drivePlaybackRunLoop(core: PlayerCore, duration: TimeInterval) -> Never {
    let pollInterval: TimeInterval = 0.5
    // Hard ceiling: never run longer than the track plus slack, even if the
    // finish signal never arrives. A non-finite/zero duration still gets a small
    // floor so the loop is always bounded.
    let slack: TimeInterval = 3
    let deadline = Date().addingTimeInterval(max(duration, 0) + slack)

    // The track was confirmed playing before this loop starts, so the first
    // `!isPlaying` we observe is a genuine finish (or an engine stop) — not a
    // not-yet-started state.
    let timer = Timer(timeInterval: pollInterval, repeats: true) { timer in
        let now = core.currentTime
        let total = core.duration
        print("\u{25B6} \(formatTimecode(now)) / \(formatTimecode(total))")

        if !core.isPlaying {
            // Natural end (or the engine stopped). Print a final full-position
            // line so the output ends at the track length, then exit cleanly.
            print("\u{25B6} \(formatTimecode(total)) / \(formatTimecode(total))")
            print("Finished.")
            timer.invalidate()
            exit(0)
        }

        if Date() >= deadline {
            // Safety cap tripped: stop the engine and exit cleanly. This guards
            // against a missed finish signal so the process can never hang.
            print("Reached the safety time cap; stopping.")
            timer.invalidate()
            exit(0)
        }
    }
    RunLoop.main.add(timer, forMode: .common)

    // Ctrl-C exits the process the usual way (the default SIGINT handler), which
    // is the documented manual-stop path.
    RunLoop.main.run()

    // RunLoop.main.run() only returns if every input source is removed, which
    // should not happen here. Treat it as a clean stop rather than hang.
    exit(0)
}

// MARK: - Failure handling

/// Print `message` to stderr and exit non-zero. Mirrors `main.swift`'s `fail`,
/// kept local so the play mode is self-contained.
private func playFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
