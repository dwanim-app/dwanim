import AVFoundation
import XCTest
import PlayerCore
@testable import PlaybackKit

// MARK: - AudioTapOfflineRenderTests

/// Headless proof that a tap installed on the engine's main mixer receives live
/// PCM as audio flows, mirroring `AudioTapProviding`'s contract.
///
/// Real-time tap firing needs a hardware output device, so — exactly as
/// `OfflineRenderTests` does for the decode/graph path — we rebuild the same
/// graph the production engine uses (an `AVAudioPlayerNode` attached and
/// connected to `engine.mainMixerNode`) but in `.offline` manual-rendering
/// mode, install a tap on bus 0 of that mixer, and pull the whole file through
/// with `renderOffline(...)`.
///
/// Wiring the production `AVAudioEnginePlayer`'s *own* engine into manual
/// rendering is impractical (it owns a private engine with no offline hook), so
/// this is the "focused standalone offline-render on the same mainMixer graph"
/// the brief permits. The mono downmix is the production code path: the tap
/// block calls `AVAudioEnginePlayer.monoSamples(from:)`, the same routine the
/// real tap uses, so the downmix logic is exercised end to end.
final class AudioTapOfflineRenderTests: XCTestCase {

    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
    }

    func testTapReceivesNonSilentMonoSamplesDuringOfflineRender() throws {
        let sampleRate = 44_100.0
        let duration = 1.0
        // Stereo so the mono downmix (channel averaging) is genuinely exercised.
        let url = try SineWAVFactory.write(
            duration: duration,
            sampleRate: sampleRate,
            channels: 2
        )
        tempURLs.append(url)

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Accumulated by the tap block. Captured by reference via a small class
        // so the @Sendable-ish tap closure can mutate it without capture issues.
        let collector = TapCollector()
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: nil
        ) { buffer, _ in
            guard let mono = AVAudioEnginePlayer.monoSamples(from: buffer) else {
                return
            }
            collector.record(mono: mono, sampleRate: buffer.format.sampleRate)
        }

        let maxFrames: AVAudioFrameCount = 4_096
        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: maxFrames
        )
        try engine.start()

        player.scheduleFile(file, at: nil)
        player.play()

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: maxFrames
        ) else {
            return XCTFail("could not allocate render buffer")
        }

        while engine.manualRenderingSampleTime < file.length {
            let remaining = file.length - engine.manualRenderingSampleTime
            let toRender = min(
                AVAudioFrameCount(remaining),
                renderBuffer.frameCapacity
            )
            let status = try engine.renderOffline(toRender, to: renderBuffer)
            switch status {
            case .success:
                continue
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                return XCTFail("offline render reported an error")
            @unknown default:
                return XCTFail("unexpected render status")
            }
        }

        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()

        // (a) The tap actually fired.
        XCTAssertGreaterThan(
            collector.callbackCount,
            0,
            "tap should have fired at least once during the render"
        )
        // (b) It delivered a non-zero number of mono samples.
        XCTAssertGreaterThan(
            collector.totalSamples,
            0,
            "tap should have delivered mono samples"
        )
        // (c) The reported sample rate matches the source.
        XCTAssertEqual(
            collector.reportedSampleRate,
            sampleRate,
            accuracy: 0.5,
            "tap should report the mixer's sample rate"
        )
        // (d) The samples are non-silent (the sine has energy).
        XCTAssertGreaterThan(
            collector.peak,
            0,
            "downmixed mono samples should be non-silent for a sine tone"
        )
    }

    // MARK: - Collector

    /// Reference-typed sink so the tap closure can accumulate across calls.
    private final class TapCollector {
        private(set) var callbackCount = 0
        private(set) var totalSamples = 0
        private(set) var reportedSampleRate: Double = 0
        private(set) var peak: Float = 0

        func record(mono: [Float], sampleRate: Double) {
            callbackCount += 1
            totalSamples += mono.count
            reportedSampleRate = sampleRate
            for sample in mono {
                peak = max(peak, abs(sample))
            }
        }
    }
}
