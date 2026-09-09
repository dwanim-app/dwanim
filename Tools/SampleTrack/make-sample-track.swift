#!/usr/bin/env swift
//
// make-sample-track.swift — generates the app's bundled sample track.
//
//   swift Tools/SampleTrack/make-sample-track.swift \
//       "App/DwanimIt/Resources/dwanim it - Sample.m4a"
//
// PROVENANCE. The piece is synthesized entirely by this script from the note
// list below — no recorded audio, no samples, no third-party material — so the
// generated file is original work shipped under the repository's MIT license.
// Everything is deterministic (no randomness, no wall clock), so re-running the
// script reproduces the same PCM; the committed .m4a is that PCM encoded by the
// system AAC encoder (`afconvert`, CBR) with the title / artist tags added by
// AVFoundation.
//
// THE MUSIC. ~20 s in C major at 96 BPM: eight bars of a soft pad (C – G – Am –
// F – C – G – F – C, root + fifth + third with a bass root an octave down, gentle
// attack/release, ±3 cent stereo detune for width), a plucked arpeggio riding the
// chord tones (fast attack, exponential decay, a light 3/8-beat echo panned
// opposite the dry note), and a 2.5 s fade at the end. Peaks are normalized to
// −1 dBFS. It is a real chord progression with a melody and envelopes, not a test
// tone, and it is deliberately mellow: it is the first thing a new user hears.
//
// OUTPUT. 44.1 kHz stereo AAC (.m4a), ~20 s, well under 400 KB, tagged
//   title  "Sample"      artist "dwanim it"
// The app displays the file's own stem ("dwanim it - Sample" → artist / title via
// the shared `Artist - Title` split), so the filename carries the same pair.

import AVFoundation
import Foundation

// MARK: - Arguments

let arguments = CommandLine.arguments.dropFirst()
guard let outputPath = arguments.first else {
    FileHandle.standardError.write(Data("usage: make-sample-track.swift <output.m4a>\n".utf8))
    exit(64)
}
let outputURL = URL(fileURLWithPath: outputPath)

// MARK: - Score

let sampleRate = 44_100.0
let bpm = 96.0
let beat = 60.0 / bpm                 // 0.625 s
let bar = 4 * beat                    // 2.5 s
let bars = 8
let totalSeconds = Double(bars) * bar // 20.0 s
let tailSeconds = 0.0                 // the last bar's fade ends exactly at 20 s

/// MIDI note number → Hz (A4 = 440).
func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

/// Chords as MIDI note sets: (bass, [pad voices], [arpeggio tones]).
/// C4 = 60. Pad voices sit around C4–G4; the arpeggio an octave up.
struct Chord {
    let bass: Double
    let pad: [Double]
    let arp: [Double]
}
let C  = Chord(bass: 36, pad: [60, 64, 67], arp: [72, 76, 79, 84])
let G  = Chord(bass: 43, pad: [59, 62, 67], arp: [74, 79, 83, 86])
let Am = Chord(bass: 45, pad: [60, 64, 69], arp: [72, 76, 81, 84])
let F  = Chord(bass: 41, pad: [60, 65, 69], arp: [72, 77, 81, 84])
let progression: [Chord] = [C, G, Am, F, C, G, F, C]

/// The arpeggio pattern per bar, in 8th notes (indices into `arp`); the final
/// bar holds a single resolving note so the piece lands rather than stops.
let arpPattern: [Int] = [0, 1, 2, 3, 2, 1, 0, 1]
let finalBarPattern: [Int?] = [0, nil, nil, nil, nil, nil, nil, nil]

// MARK: - Synthesis

let frameCount = Int(totalSeconds * sampleRate)
var left = [Double](repeating: 0, count: frameCount)
var right = [Double](repeating: 0, count: frameCount)

/// A soft pad partial set: fundamental + quiet 2nd/3rd harmonics.
@inline(__always) func padWave(_ phase: Double) -> Double {
    sin(phase) + 0.30 * sin(2 * phase) + 0.12 * sin(3 * phase)
}

/// A plucked, slightly hollow timbre (odd harmonics roll off fast).
@inline(__always) func pluckWave(_ phase: Double) -> Double {
    sin(phase) + 0.22 * sin(2 * phase) + 0.10 * sin(3 * phase) + 0.05 * sin(5 * phase)
}

/// Linear attack / linear release envelope for a sustained note.
func padEnvelope(t: Double, length: Double, attack: Double, release: Double) -> Double {
    guard t >= 0, t < length else { return 0 }
    let a = min(1, t / attack)
    let r = min(1, (length - t) / release)
    return min(a, r)
}

/// Fast attack, exponential decay for a pluck.
func pluckEnvelope(t: Double, decay: Double) -> Double {
    guard t >= 0 else { return 0 }
    let attack = min(1, t / 0.004)
    return attack * exp(-t / decay)
}

/// Mix one note into the buffers. `pan` in −1…1 (equal-power).
func render(freq: Double, start: Double, length: Double, gain: Double, pan: Double,
            wave: (Double) -> Double, envelope: (Double) -> Double, detuneCents: Double = 0) {
    let first = max(0, Int(start * sampleRate))
    let last = min(frameCount, Int((start + length) * sampleRate))
    guard first < last else { return }
    let angle = (pan + 1) * .pi / 4
    let gl = cos(angle), gr = sin(angle)
    let fL = freq * pow(2, -detuneCents / 1200)
    let fR = freq * pow(2, detuneCents / 1200)
    let wL = 2 * .pi * fL / sampleRate
    let wR = 2 * .pi * fR / sampleRate
    for i in first..<last {
        let t = Double(i - first) / sampleRate
        let e = envelope(t) * gain
        left[i] += e * gl * wave(wL * Double(i))
        right[i] += e * gr * wave(wR * Double(i))
    }
}

for (barIndex, chord) in progression.enumerated() {
    let barStart = Double(barIndex) * bar
    let isLast = barIndex == bars - 1

    // Bass root: a pure sine with a soft attack so it hums rather than thumps.
    render(freq: hz(chord.bass), start: barStart, length: bar, gain: 0.16, pan: 0,
           wave: { sin($0) },
           envelope: { padEnvelope(t: $0, length: bar, attack: 0.08, release: 0.35) })

    // Pad voices: slow attack, overlapping into the next bar for legato.
    for (voice, note) in chord.pad.enumerated() {
        let spread = (Double(voice) - 1) * 0.35
        render(freq: hz(note), start: barStart, length: bar + 0.25, gain: 0.075, pan: spread,
               wave: padWave,
               envelope: { padEnvelope(t: $0, length: bar + 0.25, attack: 0.45, release: 0.6) },
               detuneCents: 3)
    }

    // Arpeggio: 8th notes on the chord tones, alternating pan, with an echo.
    let pattern: [Int?] = isLast ? finalBarPattern : arpPattern.map { $0 }
    for (step, slot) in pattern.enumerated() {
        guard let tone = slot else { continue }
        let noteStart = barStart + Double(step) * beat / 2
        let freq = hz(chord.arp[tone])
        let pan = step.isMultiple(of: 2) ? -0.35 : 0.35
        let decay = isLast ? 1.6 : 0.42
        render(freq: freq, start: noteStart, length: isLast ? bar : 1.2, gain: 0.20, pan: pan,
               wave: pluckWave, envelope: { pluckEnvelope(t: $0, decay: decay) })
        // Echo: 3/8 of a beat later, quieter, on the opposite side.
        render(freq: freq, start: noteStart + beat * 0.375, length: 1.0, gain: 0.07, pan: -pan,
               wave: pluckWave, envelope: { pluckEnvelope(t: $0, decay: 0.35) })
    }
}

// Master: a 40 ms fade-in, a 2.5 s fade-out, then normalize to −1 dBFS.
let fadeIn = Int(0.04 * sampleRate)
let fadeOut = Int(2.5 * sampleRate)
for i in 0..<frameCount {
    var g = 1.0
    if i < fadeIn { g = Double(i) / Double(fadeIn) }
    if i >= frameCount - fadeOut {
        let k = Double(frameCount - i) / Double(fadeOut)
        g = min(g, k * k)
    }
    left[i] *= g
    right[i] *= g
}
let peak = max(left.map(abs).max() ?? 1, right.map(abs).max() ?? 1, 1e-9)
let target = pow(10, -1.0 / 20)
let norm = target / peak
for i in 0..<frameCount {
    left[i] *= norm
    right[i] *= norm
}

// MARK: - Write PCM (WAV), encode (AAC via afconvert), tag (AVFoundation)

let work = FileManager.default.temporaryDirectory
    .appendingPathComponent("dwanim-sample-track-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

let wavURL = work.appendingPathComponent("sample.wav")
let aacURL = work.appendingPathComponent("sample-untagged.m4a")

do {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    let file = try AVAudioFile(forWriting: wavURL, settings: settings)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                        frameCapacity: AVAudioFrameCount(frameCount)),
          let channels = buffer.floatChannelData else { fatalError("no PCM buffer") }
    buffer.frameLength = AVAudioFrameCount(frameCount)
    for i in 0..<frameCount {
        channels[0][i] = Float(left[i])
        channels[1][i] = Float(right[i])
    }
    try file.write(from: buffer)
} catch {
    FileHandle.standardError.write(Data("failed to write PCM: \(error)\n".utf8))
    exit(1)
}

// AAC, 44.1 kHz stereo, 112 kbps constant bit rate (deterministic, ~280 KB / 20 s).
let afconvert = Process()
afconvert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
afconvert.arguments = ["-f", "m4af", "-d", "aac", "-s", "0", "-b", "112000",
                       "-q", "127", wavURL.path, aacURL.path]
try! afconvert.run()
afconvert.waitUntilExit()
guard afconvert.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("afconvert failed (\(afconvert.terminationStatus))\n".utf8))
    exit(1)
}

// Tag by pass-through export (no re-encode), replacing any previous output.
try? FileManager.default.removeItem(at: outputURL)
try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)

func tag(_ key: AVMetadataKey, _ value: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.keySpace = .common
    item.key = key as NSString
    item.value = value as NSString
    return item
}

let asset = AVURLAsset(url: aacURL)
guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
    FileHandle.standardError.write(Data("no passthrough export session\n".utf8))
    exit(1)
}
export.outputURL = outputURL
export.outputFileType = .m4a
export.metadata = [
    tag(.commonKeyTitle, "Sample"),
    tag(.commonKeyArtist, "dwanim it"),
    tag(.commonKeyAlbumName, "dwanim it")
]
let done = DispatchSemaphore(value: 0)
export.exportAsynchronously { done.signal() }
done.wait()
guard export.status == .completed else {
    FileHandle.standardError.write(Data("export failed: \(String(describing: export.error))\n".utf8))
    exit(1)
}

let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
print("wrote \(outputURL.path): \(String(format: "%.1f", totalSeconds)) s, \(bytes) bytes")
