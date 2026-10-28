import Foundation
import AVFoundation

public enum AudioToMIDIMode: String, CaseIterable, Identifiable, Sendable {
    case melody = "Melody"
    case harmony = "Harmony"
    case drums = "Drums"

    public var id: String { rawValue }
}

private struct AudioToMIDIAnalysisResult: Sendable {
    var notes: [ClipNote]
    var lengthBeats: Double
}

private enum AudioToMIDITranscriber {
    static func transcribe(
        samples input: [Float],
        sampleRate inputRate: Double,
        tempo: Double,
        mode: AudioToMIDIMode
    ) -> AudioToMIDIAnalysisResult {
        guard !input.isEmpty, inputRate > 0 else {
            return AudioToMIDIAnalysisResult(notes: [], lengthBeats: 4)
        }

        let analysisRate = min(11_025.0, inputRate)
        let stride = max(1, Int((inputRate / analysisRate).rounded()))
        var samples: [Float] = []
        samples.reserveCapacity(input.count / stride + 1)

        var index = 0
        while index < input.count {
            samples.append(input[index])
            index += stride
        }

        let rate = inputRate / Double(stride)
        let seconds = Double(input.count) / inputRate
        let lengthBeats = max(0.25, seconds * tempo / 60.0)

        switch mode {
        case .melody:
            return AudioToMIDIAnalysisResult(
                notes: melodicNotes(samples, sampleRate: rate, tempo: tempo, addHarmony: false),
                lengthBeats: lengthBeats
            )
        case .harmony:
            return AudioToMIDIAnalysisResult(
                notes: melodicNotes(samples, sampleRate: rate, tempo: tempo, addHarmony: true),
                lengthBeats: lengthBeats
            )
        case .drums:
            return AudioToMIDIAnalysisResult(
                notes: drumNotes(samples, sampleRate: rate, tempo: tempo),
                lengthBeats: lengthBeats
            )
        }
    }

    private static func melodicNotes(
        _ samples: [Float],
        sampleRate: Double,
        tempo: Double,
        addHarmony: Bool
    ) -> [ClipNote] {
        let frameSize = 1024
        let hop = 256
        guard samples.count >= frameSize else { return [] }

        var pitches: [(beat: Double, pitch: Int, strength: Float)] = []
        var position = 0

        while position + frameSize <= samples.count {
            let frame = Array(samples[position..<(position + frameSize)])
            let rms = sqrt(
                frame.reduce(0.0) { $0 + Double($1 * $1) } / Double(frameSize)
            )

            if rms > 0.012,
               let frequency = estimateFrequency(frame, sampleRate: sampleRate) {
                let midi = Int((69.0 + 12.0 * log2(frequency / 440.0)).rounded())
                if (24...108).contains(midi) {
                    let seconds = Double(position) / sampleRate
                    let beat = seconds * tempo / 60.0
                    pitches.append((
                        beat: beat,
                        pitch: midi,
                        strength: Float(min(1, max(0.18, rms * 8)))
                    ))
                }
            }

            position += hop
        }

        guard !pitches.isEmpty else { return [] }

        let minimumLength = 0.125
        let joinWindow = Double(hop) / sampleRate * tempo / 60.0 * 1.8
        var notes: [ClipNote] = []
        var runStart = pitches[0].beat
        var runEnd = pitches[0].beat + joinWindow
        var runPitch = pitches[0].pitch
        var runStrength = pitches[0].strength
        var runCount: Float = 1

        func appendRun() {
            let length = max(minimumLength, runEnd - runStart)
            let velocity = max(0.18, min(1, runStrength / max(1, runCount)))
            notes.append(
                ClipNote(
                    pitch: runPitch,
                    start: runStart,
                    length: length,
                    velocity: velocity
                )
            )

            guard addHarmony else { return }
            notes.append(
                ClipNote(
                    pitch: min(127, runPitch + 4),
                    start: runStart,
                    length: length,
                    velocity: velocity * 0.74
                )
            )
            notes.append(
                ClipNote(
                    pitch: min(127, runPitch + 7),
                    start: runStart,
                    length: length,
                    velocity: velocity * 0.68
                )
            )
        }

        for point in pitches.dropFirst() {
            if abs(point.pitch - runPitch) <= 1,
               point.beat <= runEnd + joinWindow {
                runEnd = point.beat + joinWindow
                runStrength += point.strength
                runCount += 1
                if point.pitch != runPitch {
                    runPitch = Int(
                        (Double(runPitch) * 0.75 + Double(point.pitch) * 0.25).rounded()
                    )
                }
            } else {
                appendRun()
                runStart = point.beat
                runEnd = point.beat + joinWindow
                runPitch = point.pitch
                runStrength = point.strength
                runCount = 1
            }
        }

        appendRun()
        return notes
            .filter { $0.length >= minimumLength }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.pitch < $1.pitch
            }
    }

    private static func estimateFrequency(
        _ frame: [Float],
        sampleRate: Double
    ) -> Double? {
        let minFrequency = 55.0
        let maxFrequency = 1_760.0
        let minLag = max(2, Int(sampleRate / maxFrequency))
        let maxLag = min(frame.count / 2, Int(sampleRate / minFrequency))
        guard minLag < maxLag else { return nil }

        var bestLag = 0
        var bestCorrelation = 0.0

        for lag in minLag...maxLag {
            var correlation = 0.0
            var energyA = 0.0
            var energyB = 0.0
            let limit = frame.count - lag

            for index in 0..<limit {
                let a = Double(frame[index])
                let b = Double(frame[index + lag])
                correlation += a * b
                energyA += a * a
                energyB += b * b
            }

            let denominator = sqrt(energyA * energyB)
            guard denominator > 0 else { continue }
            let normalized = correlation / denominator

            if normalized > bestCorrelation {
                bestCorrelation = normalized
                bestLag = lag
            }
        }

        guard bestLag > 0, bestCorrelation > 0.46 else { return nil }
        return sampleRate / Double(bestLag)
    }

    private static func drumNotes(
        _ samples: [Float],
        sampleRate: Double,
        tempo: Double
    ) -> [ClipNote] {
        let frameSize = 512
        let hop = 128
        guard samples.count >= frameSize else { return [] }

        var energies: [Double] = []
        var zeroCrossings: [Double] = []
        var positions: [Int] = []
        var position = 0

        while position + frameSize <= samples.count {
            let frame = samples[position..<(position + frameSize)]
            let energy = sqrt(
                frame.reduce(0.0) { $0 + Double($1 * $1) } / Double(frameSize)
            )

            var crossings = 0
            var previous = frame.first ?? 0
            for value in frame.dropFirst() {
                if (previous < 0 && value >= 0) || (previous >= 0 && value < 0) {
                    crossings += 1
                }
                previous = value
            }

            energies.append(energy)
            zeroCrossings.append(Double(crossings) / Double(frameSize))
            positions.append(position)
            position += hop
        }

        guard energies.count > 3 else { return [] }

        let mean = energies.reduce(0, +) / Double(energies.count)
        let variance = energies.reduce(0) {
            $0 + pow($1 - mean, 2)
        } / Double(energies.count)
        let threshold = max(0.018, mean + sqrt(variance) * 1.35)

        var notes: [ClipNote] = []
        var lastBeat = -Double.greatestFiniteMagnitude

        for index in 1..<(energies.count - 1) {
            let energy = energies[index]
            guard energy >= threshold,
                  energy > energies[index - 1],
                  energy >= energies[index + 1] else {
                continue
            }

            let seconds = Double(positions[index]) / sampleRate
            let beat = seconds * tempo / 60.0
            guard beat - lastBeat >= 0.08 else { continue }
            lastBeat = beat

            let zcr = zeroCrossings[index]
            let note: Int
            if zcr < 0.055 {
                note = 36
            } else if zcr < 0.13 {
                note = 38
            } else {
                note = 42
            }

            let velocity = Float(
                min(
                    1,
                    max(
                        0.25,
                        (energy - mean) / max(0.001, threshold - mean) * 0.55 + 0.42
                    )
                )
            )

            notes.append(
                ClipNote(
                    pitch: note,
                    start: beat,
                    length: 0.12,
                    velocity: velocity
                )
            )
        }

        return notes
    }
}

@MainActor
extension AppState {
    func createMIDIFromAudio(
        _ audioClip: AudioClip,
        mode: AudioToMIDIMode,
        targetTrack explicitTarget: Track? = nil
    ) {
        let samples = audioClip.activeSamples
        let sampleRate = audioClip.activeSampleRate
        let tempo = project.tempo
        let sourceStart = audioClip.startBeat
        let displayName = audioClip.displayName

        guard !samples.isEmpty, sampleRate > 0 else {
            editStatus = "⚠️ Audio-to-MIDI failed: the clip has no readable audio."
            return
        }

        editStatus = "Analysing \(displayName) for \(mode.rawValue.lowercased())…"

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                AudioToMIDITranscriber.transcribe(
                    samples: samples,
                    sampleRate: sampleRate,
                    tempo: tempo,
                    mode: mode
                )
            }.value

            guard !result.notes.isEmpty else {
                editStatus =
                    "⚠️ No \(mode.rawValue.lowercased()) notes were detected in \(displayName)."
                return
            }

            let target: Track
            if let explicitTarget, explicitTarget.kind != .audio {
                target = explicitTarget
            } else {
                switch mode {
                case .drums:
                    target = Track(name: "\(displayName) Drums", kind: .drums, color: .orange)
                case .melody:
                    target = Track(name: "\(displayName) Melody", kind: .analog, color: .blue)
                case .harmony:
                    target = Track(name: "\(displayName) Harmony", kind: .analog, color: .purple)
                }
                project.tracks.append(target)
            }

            let length = max(Double(project.beatsPerBar), result.lengthBeats)
            let clip = Clip(
                name: "\(displayName) · \(mode.rawValue)",
                startBeat: sourceStart,
                lengthBeats: length,
                color: target.color
            )
            clip.notes = result.notes
            clip.sourceTempo = tempo
            target.clips.append(clip)

            selectedTrackID = target.id
            selectedClipID = clip.id
            selectedAudioClipID = nil
            selectedAudioClipTrackID = nil
            PianoRollState.shared.clipID = clip.id
            detailDeck = .clip
            workspace = .pianoRoll

            ensureArrangementLength(coversBeat: sourceStart + length)
            engine.rebuild()
            editStatus =
                "Created \(result.notes.count) \(mode.rawValue.lowercased()) MIDI notes from \(displayName)."

        }
    }
}
