import AVFoundation
import Accelerate
import XCTest
import PlayerCore
@testable import PlaybackKit

// MARK: - EQOfflineDSPProofTests

/// The real-DSP proof: render a broadband multi-tone signal through an
/// `AVAudioEngine` graph that contains the PRODUCTION `AVAudioUnitEQ`
/// configuration (`EQConfig.configure` + `EQConfig.apply`), once with the EQ
/// flat and once with a single band boosted +12 dB, FFT both rendered outputs,
/// and assert the boosted render has measurably MORE energy in the boosted
/// band's frequency region while the rest of the spectrum is roughly unchanged.
///
/// Like `OfflineRenderTests`/`AudioTapOfflineRenderTests`, this rebuilds the
/// same `playerNode -> eq -> mainMixer` graph the production engine uses but in
/// `.offline` manual-rendering mode (the production engine owns a private engine
/// with no offline hook). Crucially it configures the EQ with the exact
/// production routines, so the test exercises the real band setup that ships,
/// not a test-only EQ.
///
/// All audio is synthesized in-memory by `SineWAVFactory` — no real or
/// copyrighted asset, nothing committed.
final class EQOfflineDSPProofTests: XCTestCase {

    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        tempURLs.removeAll()
    }

    // MARK: - The proof

    func testBoostingOneBandRaisesItsEnergyVersusFlat() throws {
        let sampleRate = 44_100.0
        let duration = 1.0

        // A tone at each classic band centre -> broadband energy across the
        // spectrum, so boosting one band must lift its tone specifically.
        let frequencies = EQConfig.centreFrequencies.map(Double.init)
        let url = try SineWAVFactory.writeMultiTone(
            frequencies: frequencies,
            duration: duration,
            sampleRate: sampleRate,
            channels: 1
        )
        tempURLs.append(url)

        // Boost band index 4 (1 kHz) — middle of the spectrum, well separated
        // from its neighbours (600 Hz and 3 kHz), so the FFT bin for 1 kHz lands
        // squarely in the boosted band and not in an adjacent one.
        let boostBandIndex = 4
        let boostFrequency = Double(EQConfig.centreFrequencies[boostBandIndex])

        // Flat: enabled, all gains 0 (a pass-through that still runs through the
        // real, un-bypassed parametric bands).
        let flatState = EQState(
            enabled: true,
            preamp: 0,
            bands: [Double](repeating: 0, count: EQState.bandCount)
        )
        // Boosted: same, but +12 dB on the target band.
        var boostBands = [Double](repeating: 0, count: EQState.bandCount)
        boostBands[boostBandIndex] = 12
        let boostState = EQState(enabled: true, preamp: 0, bands: boostBands)

        let flatSamples = try render(url: url, applying: flatState)
        let boostSamples = try render(url: url, applying: boostState)

        XCTAssertGreaterThan(flatSamples.count, 0, "flat render produced samples")
        XCTAssertEqual(
            boostSamples.count,
            flatSamples.count,
            "both renders cover the same number of frames"
        )

        // Energy at the boosted tone's frequency, both renders.
        let flatBoostEnergy = energy(in: flatSamples, near: boostFrequency, sampleRate: sampleRate)
        let boostBoostEnergy = energy(in: boostSamples, near: boostFrequency, sampleRate: sampleRate)

        XCTAssertGreaterThan(flatBoostEnergy, 0, "flat render has energy at the band tone")
        XCTAssertGreaterThan(boostBoostEnergy, 0, "boosted render has energy at the band tone")

        // The +12 dB boost is a ~4x amplitude rise (10^(12/20) ≈ 3.98), i.e. a
        // ~16x energy rise. Assert a clearly measurable gain with margin for the
        // band's finite Q and FFT leakage — well above the flat level.
        let energyRatioDB = 10 * log10(boostBoostEnergy / flatBoostEnergy)
        XCTAssertGreaterThan(
            energyRatioDB,
            6,
            "boosting band \(boostBandIndex) (+12 dB @ \(boostFrequency) Hz) must raise "
                + "that band's energy by clearly more than 6 dB vs flat "
                + "(measured \(String(format: "%.1f", energyRatioDB)) dB)"
        )

        // A far-away band's tone must be essentially unchanged: boosting one
        // band should not move 60 Hz. Use band 0 (60 Hz), the most distant.
        let controlFrequency = Double(EQConfig.centreFrequencies[0])
        let flatControl = energy(in: flatSamples, near: controlFrequency, sampleRate: sampleRate)
        let boostControl = energy(in: boostSamples, near: controlFrequency, sampleRate: sampleRate)
        XCTAssertGreaterThan(flatControl, 0, "flat render has energy at the control tone")

        let controlRatioDB = 10 * log10(boostControl / flatControl)
        XCTAssertLessThan(
            abs(controlRatioDB),
            3,
            "a distant control band (\(controlFrequency) Hz) should be roughly "
                + "unchanged by the boost (measured \(String(format: "%.1f", controlRatioDB)) dB)"
        )

        // And the boosted band's gain must dwarf any drift at the control band:
        // the effect is localized.
        XCTAssertGreaterThan(
            energyRatioDB - abs(controlRatioDB),
            4,
            "the boost at the target band must clearly exceed any control-band drift"
        )
    }

    // MARK: - Offline render through the production EQ graph

    /// Renders `url` through `playerNode -> eq -> mainMixer` in offline mode with
    /// `eq` configured exactly as production does and `state` applied, returning
    /// the full mono output captured from a tap on the main mixer (the same
    /// downmix the live tap uses).
    private func render(url: URL, applying state: EQState) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: EQConfig.centreFrequencies.count)
        engine.attach(player)
        engine.attach(eq)

        // Production band setup, then the production state mapping.
        EQConfig.configure(eq)
        EQConfig.apply(state, to: eq)

        // playerNode -> eq -> mainMixer, the production chain.
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)

        let collector = SampleCollector()
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            guard let mono = AVAudioEnginePlayer.monoSamples(from: buffer) else { return }
            collector.append(mono)
        }

        let maxFrames: AVAudioFrameCount = 4_096
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
        try engine.start()

        player.scheduleFile(file, at: nil)
        player.play()

        guard let renderBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: maxFrames
        ) else {
            throw ProofError.bufferAllocationFailed
        }

        while engine.manualRenderingSampleTime < file.length {
            let remaining = file.length - engine.manualRenderingSampleTime
            let toRender = min(AVAudioFrameCount(remaining), renderBuffer.frameCapacity)
            let status = try engine.renderOffline(toRender, to: renderBuffer)
            switch status {
            case .success, .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw ProofError.renderError
            @unknown default:
                throw ProofError.renderError
            }
        }

        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        return collector.samples
    }

    private enum ProofError: Error { case bufferAllocationFailed, renderError }

    // MARK: - Energy at a frequency (Goertzel)

    /// The signal energy at `frequency` measured with a Goertzel filter over the
    /// rendered samples — a direct, single-bin DFT magnitude that does not depend
    /// on the FFT framing of `SpectrumAnalyzer`, so the proof is self-contained
    /// and robust to the exact tone alignment. Returns magnitude-squared.
    private func energy(in samples: [Float], near frequency: Double, sampleRate: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let n = samples.count
        let k = (2.0 * Double.pi * frequency) / sampleRate
        let coeff = 2.0 * cos(k)
        var s0 = 0.0
        var s1 = 0.0
        var s2 = 0.0
        for sample in samples {
            s0 = Double(sample) + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        // |X|^2 from the Goertzel state.
        let real = s1 - s2 * cos(k)
        let imag = s2 * sin(k)
        let power = real * real + imag * imag
        // Normalize by length so renders of equal length compare directly.
        return power / Double(n * n)
    }

    // MARK: - Collector

    /// Reference-typed sink the tap closure accumulates the whole render into.
    private final class SampleCollector {
        private(set) var samples: [Float] = []
        func append(_ mono: [Float]) { samples.append(contentsOf: mono) }
    }
}
