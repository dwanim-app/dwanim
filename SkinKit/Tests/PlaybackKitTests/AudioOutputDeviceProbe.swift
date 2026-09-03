import AVFoundation

// MARK: - AudioOutputDeviceProbe

/// Independent output-route probe, shared by every real-playback test that
/// needs a device guard.
///
/// ## Why an INDEPENDENT probe (skip-mask guard, do not regress)
/// The old guard was "skip unless the player's render clock advanced" — but a
/// frozen clock is ALSO the exact symptom of the bug class the format-change
/// fix exists to prevent (engine stopped and never restarted, or a half-rewired
/// graph whose `engine.start()` throws and is swallowed). With that guard, a
/// regression turned every runtime assertion into a green SKIP: verified by
/// mutation, deleting `startEngineIfNeeded()` from `play()` left the whole
/// PlaybackKit suite passing with 0 failures.
///
/// This probe answers "does this machine have a usable output route?" with a
/// THROWAWAY engine that shares nothing with the player under test: if the
/// throwaway starts, an output device exists, and a player whose clock then
/// fails to advance is a real failure — not a skippable environment problem.
/// On a truly headless machine (CI) the throwaway fails to start and callers
/// still skip correctly.
enum AudioOutputDeviceProbe {

    /// True when a minimal `AVAudioEngine` with a plain player node can start,
    /// proving an audio output route exists on this machine.
    static func hasOutputDevice() -> Bool {
        let probe = AVAudioEngine()
        let source = AVAudioPlayerNode()
        probe.attach(source)
        probe.connect(source, to: probe.mainMixerNode, format: nil)
        defer { probe.stop() }
        return (try? probe.start()) != nil
    }
}
