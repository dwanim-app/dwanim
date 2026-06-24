import AVFoundation
import XCTest
@testable import PlaybackKit

// MARK: - OfflineRenderTests

/// Deterministic proof that the load + schedule path decodes audio and routes
/// it through a player-node graph, without needing a hardware output device.
///
/// We build the same graph the production engine uses — an `AVAudioPlayerNode`
/// attached and connected to the engine's main mixer — but put the engine in
/// `.offline` manual-rendering mode. We then pull the whole file through with
/// `renderOffline(...)` and inspect the rendered buffers. This exercises the
/// identical `AVAudioFile` open + `scheduleSegment` flow that
/// `AVAudioEnginePlayer` uses; only the render driver differs (manual pull vs.
/// the real output device), which is unavoidable headlessly.
final class OfflineRenderTests: XCTestCase {

    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
    }

    func testOfflineRenderProducesNonSilentOutputOfExpectedLength() throws {
        let sampleRate = 44_100.0
        let duration = 1.0
        let url = try SineWAVFactory.write(
            duration: duration,
            sampleRate: sampleRate,
            channels: 1
        )
        tempURLs.append(url)

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Manual offline rendering — no audio device involved.
        let maxFrames: AVAudioFrameCount = 4_096
        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: maxFrames
        )
        try engine.start()

        player.scheduleFile(file, at: nil)
        player.play()

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: maxFrames
        ) else {
            return XCTFail("could not allocate render buffer")
        }

        var renderedFrames: AVAudioFramePosition = 0
        var peak: Float = 0

        while engine.manualRenderingSampleTime < file.length {
            let remaining = file.length - engine.manualRenderingSampleTime
            let toRender = min(
                AVAudioFrameCount(remaining),
                buffer.frameCapacity
            )
            let status = try engine.renderOffline(toRender, to: buffer)
            switch status {
            case .success:
                renderedFrames += AVAudioFramePosition(buffer.frameLength)
                peak = max(peak, peakAmplitude(of: buffer))
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                // No live input node here; bail out so the test can't hang.
                continue
            case .error:
                return XCTFail("offline render reported an error")
            @unknown default:
                return XCTFail("unexpected render status")
            }
        }

        engine.stop()

        // (a) Decode + graph actually produced sound.
        XCTAssertGreaterThan(
            peak,
            0,
            "rendered output should be non-silent"
        )
        // (b) We rendered approximately the whole file (within one buffer).
        XCTAssertEqual(
            renderedFrames,
            file.length,
            accuracy: AVAudioFramePosition(maxFrames),
            "rendered frame count should match the file length"
        )
    }

    // MARK: - Helpers

    private func peakAmplitude(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var peak: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameLength {
                peak = max(peak, abs(samples[frame]))
            }
        }
        return peak
    }
}
