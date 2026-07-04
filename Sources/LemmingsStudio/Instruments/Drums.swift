import Foundation
import AVFoundation

// MARK: - Drum machine
//
// Fully synthesized drum voices (no samples) in the same spirit as the existing
// Indian percussion: analog/FM-style kick, snare, clap, hats, toms, plus a
// sub-bass 808. Genre "kits" retune the voices and ship default grooves for
// lo-fi, tech house, slap house, EDM, and breakbeat.

public enum DrumVoiceID: Int, CaseIterable, Identifiable, Sendable {
    case kick, sub808, snare, clap, rim, closedHat, openHat, tom, ride, crash
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .kick: return "Kick"; case .sub808: return "808 Sub"
        case .snare: return "Snare"; case .clap: return "Clap"; case .rim: return "Rim"
        case .closedHat: return "Closed Hat"; case .openHat: return "Open Hat"
        case .tom: return "Tom"; case .ride: return "Ride"; case .crash: return "Crash"
        }
    }
    /// General-MIDI-ish note mapping so external pads/clips line up.
    public var midiNote: Int {
        switch self {
        case .kick: return 36; case .sub808: return 35; case .snare: return 38
        case .clap: return 39; case .rim: return 37; case .closedHat: return 42
        case .openHat: return 46; case .tom: return 45; case .ride: return 51; case .crash: return 49
        }
    }
    public static func from(midiNote: Int) -> DrumVoiceID? {
        allCases.first { $0.midiNote == midiNote }
    }
}

public enum DrumGenre: String, CaseIterable, Identifiable, Sendable {
    case lofi = "Lo-Fi"
    case techHouse = "Tech House"
    case slapHouse = "Slap House"
    case edm = "EDM"
    case guaracha = "Guaracha"
    case reggaeton332 = "Reggaeton 3-3-2"
    case moombah = "Moombah"
    case moombahton = "Moombahton"
    case dembow = "Dembow"
    case breakbeat = "Breakbeat"
    case dubstep = "Dubstep"
    case rock = "Rock"
    case orchestral = "Orchestral"
    public var id: String { rawValue }
}

// MARK: - Voice parameters

public struct DrumVoiceParams {
    public var tune: Double = 1.0        // pitch multiplier
    public var decay: Double = 1.0       // length multiplier
    public var tone: Double = 1.0        // brightness multiplier
    public var drive: Float = 1.0        // saturation
    public var level: Float = 1.0
}

// MARK: - One-shot synth voice

final class DrumVoice {
    private let sr: Double
    private var t = 0.0           // seconds since trigger
    private var active = false
    private var id: DrumVoiceID = .kick
    private var p = DrumVoiceParams()
    private var vel: Float = 1.0
    private var phase = 0.0
    private var noiseLP: Float = 0
    private var bpState = (0.0, 0.0)
    private var rng: UInt64 = 0x9E3779B97F4A7C15

    init(sampleRate: Double) { self.sr = sampleRate }

    @inline(__always) private func noise() -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        // Bipolar, zero-centred noise. The previous 0...1 noise source left a
        // DC-biased broadband tail in hat/crash voices, heard as ugly white
        // noise after EDM/Tech House patterns ended.
        let unit = Double(rng >> 33) / Double((UInt64(1) << 31) - 1)
        return Float(unit * 2.0 - 1.0)
    }

    func trigger(_ id: DrumVoiceID, params: DrumVoiceParams, velocity: Float) {
        self.id = id; self.p = params; self.vel = velocity
        t = 0; phase = 0; active = true; noiseLP = 0; bpState = (0, 0)
    }
    func stop() { active = false; t = 0; phase = 0; noiseLP = 0; bpState = (0, 0) }
    var isActive: Bool { active }

    @inline(__always) private func env(_ tau: Double) -> Float { Float(exp(-t / (tau * p.decay))) }

    func render() -> Float {
        guard active else { return 0 }
        let dt = 1.0 / sr
        var s: Float = 0
        switch id {
        case .kick:
            let f0 = 52.0 * p.tune
            let pitchEnv = 1.0 + 6.0 * exp(-t / 0.012)        // click → body
            phase += 2 * .pi * f0 * pitchEnv * dt
            s = Float(sin(phase)) * env(0.16)
            s += noise() * env(0.004) * 0.6                    // beater click
        case .sub808:
            let f0 = 44.0 * p.tune
            phase += 2 * .pi * f0 * (1 + 2 * exp(-t / 0.03)) * dt
            s = Float(sin(phase)) * env(0.5)
            s = tanh(s * 1.6 * p.drive)
        case .snare:
            let body = Float(sin(2 * .pi * 190 * p.tune * t)) * env(0.09)
            let n = noise() * env(0.12)
            s = (body * 0.5 + n * 0.7)
        case .clap:
            // three short noise bursts
            let bursts = [0.0, 0.009, 0.018]
            var c: Float = 0
            for b in bursts where t >= b { c += noise() * Float(exp(-(t - b) / 0.012)) }
            c += noise() * env(0.12) * 0.5
            s = c * 0.6
        case .rim:
            s = (Float(sin(2 * .pi * 1700 * t)) + noise() * 0.5) * env(0.012)
        case .closedHat:
            noiseLP = noiseLP * 0.5 + noise() * 0.5
            s = (noise() - noiseLP) * env(0.025 * p.tone)      // high-passed noise
        case .openHat:
            noiseLP = noiseLP * 0.5 + noise() * 0.5
            s = (noise() - noiseLP) * env(0.35 * p.tone)
        case .tom:
            let f0 = 120.0 * p.tune
            phase += 2 * .pi * f0 * (1 + 1.5 * exp(-t / 0.04)) * dt
            s = Float(sin(phase)) * env(0.22)
        case .ride:
            var r: Float = 0
            for h in [1.0, 1.34, 1.71, 2.4] { r += Float(sin(2 * .pi * 520 * h * t)) }
            s = (r * 0.25 + noise() * 0.3) * env(0.5 * p.tone)
        case .crash:
            noiseLP = noiseLP * 0.3 + noise() * 0.7
            s = (noise() - noiseLP * 0.5) * env(0.8 * p.tone)
        }
        s = tanh(s * p.drive) * p.level * vel
        t += dt
        // Hard cap noisy cymbal/hat tails. Some beta kits were leaving a raw
        // broadband tail after the pattern ended, which sounded like random
        // white noise instead of a controlled one-shot decay.
        switch id {
        case .closedHat where t > 0.12 * p.decay * p.tone: active = false
        case .openHat where t > 0.38 * p.decay * p.tone: active = false
        case .ride where t > 0.55 * p.decay * p.tone: active = false
        case .crash where t > 0.65 * p.decay * p.tone: active = false
        default: break
        }
        if t > 1.25 || (env(0.35) < 1e-4 && t > 0.1) { active = false }
        return s
    }
}


// MARK: - Sample-layer drum kit

public final class SampleLayerDrumKit: Instrument {
    public let name: String
    private let base: DrumKit
    private let sampleRate: Double

    private struct SampleLayer {
        var note: Int
        var samples: [Float]
        var level: Float
    }
    private struct Voice {
        var samples: [Float]
        var index: Int
        var velocity: Float
    }

    private var layers: [Int: SampleLayer] = [:]
    private var voices: [Voice] = []
    private let maxVoices = 32

    public init(name: String, genre: DrumGenre, layers sequencerLayers: [SequencerLayer], sampleRate: Double) {
        self.name = name
        self.sampleRate = sampleRate
        self.base = DrumKit(name: name, genre: genre, sampleRate: sampleRate)
        for layer in sequencerLayers {
            guard let path = layer.samplePath, let samples = Self.loadMonoSample(path: path, targetSampleRate: sampleRate), !samples.isEmpty else { continue }
            layers[layer.note] = SampleLayer(note: layer.note, samples: samples, level: layer.velocity)
        }
    }

    private static func loadMonoSample(path: String, targetSampleRate: Double) -> [Float]? {
        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: buffer)
            guard let channels = buffer.floatChannelData else { return nil }
            let frames = Int(buffer.frameLength)
            let channelCount = max(1, Int(format.channelCount))
            var mono = [Float](repeating: 0, count: frames)
            for i in 0..<frames {
                var sum: Float = 0
                for ch in 0..<channelCount { sum += channels[ch][i] }
                mono[i] = sum / Float(channelCount)
            }
            // Lightweight beta path: if sample-rate differs, still play it as one-shot.
            // A later pass can replace this with high-quality resampling.
            return mono
        } catch {
            return nil
        }
    }

    public func noteOn(_ note: Int, velocity: Float) {
        if let layer = layers[note] {
            if voices.count >= maxVoices { voices.removeFirst() }
            voices.append(Voice(samples: layer.samples, index: 0, velocity: velocity * layer.level))
        } else {
            base.noteOn(note, velocity: velocity)
        }
    }

    public func noteOff(_ note: Int) { base.noteOff(note) }
    public func allNotesOff() { voices.removeAll(); base.allNotesOff() }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        base.render(into: out, frames: frames)
        guard !voices.isEmpty else { return }
        for i in 0..<frames {
            var s: Float = 0
            for v in voices.indices {
                if voices[v].index < voices[v].samples.count {
                    s += voices[v].samples[voices[v].index] * voices[v].velocity
                    voices[v].index += 1
                }
            }
            out[i] = tanh(out[i] + s)
        }
        voices.removeAll { $0.index >= $0.samples.count }
    }
}

// MARK: - Sample layers over any built-in instrument

/// Lets Step Sequencer slots replace *any* lane with a one-shot while keeping
/// the underlying built-in instrument available for the lanes that have not
/// been replaced. This is what makes Bhangra Architect / dhol / dholak rows
/// behave like a real sampler channel rack instead of a locked preset grid.
public final class SampleLayerHybridInstrument: Instrument {
    public let name: String
    private let base: Instrument
    private struct SampleLayer { var samples: [Float]; var level: Float }
    private struct Voice { var samples: [Float]; var index: Int; var velocity: Float }
    private var layers: [Int: SampleLayer] = [:]
    private var voices: [Voice] = []
    private let maxVoices = 48

    public init(name: String, base: Instrument, layers sequencerLayers: [SequencerLayer], sampleRate: Double) {
        self.name = name
        self.base = base
        for layer in sequencerLayers {
            guard let path = layer.samplePath,
                  let samples = Self.loadMonoSample(path: path),
                  !samples.isEmpty else { continue }
            layers[layer.note] = SampleLayer(samples: samples, level: layer.velocity)
        }
    }

    private static func loadMonoSample(path: String) -> [Float]? {
        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
            try file.read(into: buffer)
            guard let channels = buffer.floatChannelData else { return nil }
            let frames = Int(buffer.frameLength)
            let channelCount = max(1, Int(format.channelCount))
            var mono = [Float](repeating: 0, count: frames)
            for i in 0..<frames {
                var sum: Float = 0
                for ch in 0..<channelCount { sum += channels[ch][i] }
                mono[i] = sum / Float(channelCount)
            }
            return mono
        } catch { return nil }
    }

    public func noteOn(_ note: Int, velocity: Float) {
        if let layer = layers[note] {
            if voices.count >= maxVoices { voices.removeFirst() }
            voices.append(Voice(samples: layer.samples, index: 0, velocity: velocity * layer.level))
        } else {
            base.noteOn(note, velocity: velocity)
        }
    }

    public func noteOff(_ note: Int) { base.noteOff(note) }
    public func allNotesOff() { voices.removeAll(); base.allNotesOff() }
    public func pitchBend(_ value: Float, channel: Int, rangeSemitones: Int) { base.pitchBend(value, channel: channel, rangeSemitones: rangeSemitones) }
    public func pressure(_ value: Float, note: Int?, channel: Int) { base.pressure(value, note: note, channel: channel) }
    public func timbre(_ value: Float, channel: Int) { base.timbre(value, channel: channel) }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        base.render(into: out, frames: frames)
        guard !voices.isEmpty else { return }
        for i in 0..<frames {
            var s: Float = 0
            for v in voices.indices where voices[v].index < voices[v].samples.count {
                s += voices[v].samples[voices[v].index] * voices[v].velocity
                voices[v].index += 1
            }
            out[i] = tanh(out[i] + s)
        }
        voices.removeAll { $0.index >= $0.samples.count }
    }
}


// MARK: - Drum kit instrument

public final class DrumKit: Instrument, Automatable {
    public let name: String
    public var genre: DrumGenre { didSet { applyKit() } }

    private let sr: Double
    private let polyphony = 24
    private var voices: [DrumVoice]
    private var next = 0
    private var params: [DrumVoiceID: DrumVoiceParams] = [:]
    private var master: Float = 1.0

    public init(name: String = "Drums", genre: DrumGenre = .techHouse, sampleRate: Double) {
        self.name = name; self.sr = sampleRate; self.genre = genre
        self.voices = (0..<polyphony).map { _ in DrumVoice(sampleRate: sampleRate) }
        applyKit()
    }

    private func applyKit() { params = DrumKitLibrary.params(for: genre) }

    public func noteOn(_ note: Int, velocity: Float) {
        guard let v = DrumVoiceID.from(midiNote: note) else { return }
        hit(v, velocity: velocity)
    }
    public func hit(_ id: DrumVoiceID, velocity: Float) {
        let p = params[id] ?? DrumVoiceParams()
        voices[next].trigger(id, params: p, velocity: velocity)
        next = (next + 1) % voices.count
    }
    public func noteOff(_ note: Int) {}     // one-shots
    public func allNotesOff() {
        // Transport panic / Step Sequencer Clear must kill drum tails too.
        // Leaving one-shots alive here made a cleared pattern continue to sound
        // like the previously loaded kit until every synthetic tail decayed.
        for voice in voices { voice.stop() }
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames {
            var s: Float = 0
            for v in voices where v.isActive { s += v.render() }
            out[i] = tanh(s * 0.8) * master
        }
    }

    // Automatable: master + per-voice tune/decay/level via "voice_param" ids.
    public var automatableParams: [ParamInfo] {
        var p = [ParamInfo("master", "Master", 0, 1.5)]
        for v in DrumVoiceID.allCases {
            p.append(ParamInfo("\(v.rawValue)_tune", "\(v.label) Tune", 0.5, 2))
            p.append(ParamInfo("\(v.rawValue)_decay", "\(v.label) Decay", 0.2, 3))
            p.append(ParamInfo("\(v.rawValue)_level", "\(v.label) Level", 0, 1.5))
        }
        return p
    }
    public func setParam(_ id: String, _ v: Double) {
        if id == "master" { master = Float(v); return }
        let parts = id.split(separator: "_")
        guard parts.count == 2, let raw = Int(parts[0]), let vid = DrumVoiceID(rawValue: raw) else { return }
        var pr = params[vid] ?? DrumVoiceParams()
        switch parts[1] {
        case "tune": pr.tune = v; case "decay": pr.decay = v; case "level": pr.level = Float(v)
        default: break }
        params[vid] = pr
    }
    public func getParam(_ id: String) -> Double {
        if id == "master" { return Double(master) }
        let parts = id.split(separator: "_")
        guard parts.count == 2, let raw = Int(parts[0]), let vid = DrumVoiceID(rawValue: raw) else { return 0 }
        let pr = params[vid] ?? DrumVoiceParams()
        switch parts[1] {
        case "tune": return pr.tune; case "decay": return pr.decay; case "level": return Double(pr.level)
        default: return 0 }
    }
}

// MARK: - Kit library + grooves

public enum DrumKitLibrary {
    public static func params(for genre: DrumGenre) -> [DrumVoiceID: DrumVoiceParams] {
        var p: [DrumVoiceID: DrumVoiceParams] = [:]
        for v in DrumVoiceID.allCases { p[v] = DrumVoiceParams() }
        switch genre {
        case .lofi:
            p[.kick] = DrumVoiceParams(tune: 0.9, decay: 1.1, tone: 0.7, drive: 1.1, level: 0.9)
            p[.snare] = DrumVoiceParams(tune: 0.95, decay: 0.9, tone: 0.6, drive: 1.0, level: 0.7)
            p[.closedHat] = DrumVoiceParams(tune: 0.85, decay: 0.9, tone: 0.55, drive: 1.0, level: 0.5)
        case .techHouse:
            p[.kick] = DrumVoiceParams(tune: 1.0, decay: 0.85, tone: 1.0, drive: 1.3, level: 1.0)
            p[.clap] = DrumVoiceParams(tune: 1.0, decay: 1.0, tone: 1.1, drive: 1.0, level: 0.8)
            p[.closedHat] = DrumVoiceParams(tune: 1.1, decay: 0.38, tone: 0.72, drive: 0.9, level: 0.34)
            p[.openHat] = DrumVoiceParams(tune: 1.0, decay: 0.30, tone: 0.68, drive: 0.85, level: 0.28)
        case .slapHouse:
            p[.kick] = DrumVoiceParams(tune: 0.95, decay: 1.0, tone: 1.0, drive: 1.2, level: 1.0)
            p[.sub808] = DrumVoiceParams(tune: 1.0, decay: 1.4, tone: 1.0, drive: 1.4, level: 1.1)
            p[.clap] = DrumVoiceParams(tune: 1.05, decay: 1.0, tone: 1.2, drive: 1.0, level: 0.9)
        case .edm:
            p[.kick] = DrumVoiceParams(tune: 1.05, decay: 0.8, tone: 1.2, drive: 1.5, level: 1.1)
            p[.snare] = DrumVoiceParams(tune: 1.1, decay: 1.1, tone: 1.3, drive: 1.1, level: 1.0)
            p[.closedHat] = DrumVoiceParams(tune: 1.05, decay: 0.32, tone: 0.70, drive: 0.9, level: 0.30)
            p[.crash] = DrumVoiceParams(tune: 1.0, decay: 0.42, tone: 0.62, drive: 0.75, level: 0.24)
        case .guaracha:
            // Short, clicky club kick + rim/clap bounce + zap sub for modern guaracha.
            p[.kick] = DrumVoiceParams(tune: 1.08, decay: 0.52, tone: 1.55, drive: 1.75, level: 1.12)
            p[.sub808] = DrumVoiceParams(tune: 1.22, decay: 0.38, tone: 1.1, drive: 1.9, level: 0.85)
            p[.clap] = DrumVoiceParams(tune: 1.18, decay: 0.62, tone: 1.45, drive: 1.25, level: 0.92)
            p[.rim] = DrumVoiceParams(tune: 1.45, decay: 0.34, tone: 1.75, drive: 1.18, level: 0.84)
            p[.closedHat] = DrumVoiceParams(tune: 1.32, decay: 0.38, tone: 1.1, drive: 1.0, level: 0.46)
            p[.openHat] = DrumVoiceParams(tune: 1.2, decay: 0.32, tone: 1.05, drive: 0.95, level: 0.34)
        case .reggaeton332, .moombah, .moombahton, .dembow:
            p[.kick] = DrumVoiceParams(tune: 0.92, decay: 0.82, tone: 1.15, drive: 1.35, level: 1.08)
            p[.sub808] = DrumVoiceParams(tune: 0.78, decay: 1.15, tone: 0.9, drive: 1.65, level: 0.9)
            p[.snare] = DrumVoiceParams(tune: 1.06, decay: 0.75, tone: 1.22, drive: 1.1, level: 0.82)
            p[.clap] = DrumVoiceParams(tune: 1.02, decay: 0.82, tone: 1.2, drive: 1.0, level: 0.84)
            p[.rim] = DrumVoiceParams(tune: 1.1, decay: 0.5, tone: 1.35, drive: 1.0, level: 0.62)
            p[.closedHat] = DrumVoiceParams(tune: 1.0, decay: 0.72, tone: 1.15, drive: 1.0, level: 0.56)
        case .breakbeat:
            p[.kick] = DrumVoiceParams(tune: 1.0, decay: 0.9, tone: 1.1, drive: 1.2, level: 1.0)
            p[.snare] = DrumVoiceParams(tune: 1.0, decay: 1.0, tone: 1.2, drive: 1.3, level: 1.0)
            p[.closedHat] = DrumVoiceParams(tune: 1.0, decay: 0.8, tone: 1.1, drive: 1.0, level: 0.6)
        case .dubstep:
            p[.kick] = DrumVoiceParams(tune: 0.85, decay: 0.95, tone: 1.25, drive: 1.7, level: 1.05)
            p[.snare] = DrumVoiceParams(tune: 0.95, decay: 1.05, tone: 1.45, drive: 1.45, level: 1.1)
            p[.sub808] = DrumVoiceParams(tune: 0.62, decay: 1.65, tone: 0.82, drive: 2.1, level: 1.0)
            p[.closedHat] = DrumVoiceParams(tune: 1.1, decay: 0.36, tone: 0.7, drive: 0.9, level: 0.32)
            p[.rim] = DrumVoiceParams(tune: 0.85, decay: 0.42, tone: 1.2, drive: 1.25, level: 0.55)
        case .rock:
            p[.kick] = DrumVoiceParams(tune: 0.82, decay: 1.0, tone: 0.95, drive: 1.15, level: 1.0)
            p[.snare] = DrumVoiceParams(tune: 0.92, decay: 1.0, tone: 1.05, drive: 1.2, level: 0.98)
            p[.tom] = DrumVoiceParams(tune: 0.72, decay: 1.25, tone: 0.9, drive: 1.05, level: 0.85)
            p[.crash] = DrumVoiceParams(tune: 0.86, decay: 0.55, tone: 0.62, drive: 0.8, level: 0.34)
            p[.ride] = DrumVoiceParams(tune: 0.9, decay: 0.45, tone: 0.64, drive: 0.8, level: 0.3)
        case .orchestral:
            p[.kick] = DrumVoiceParams(tune: 0.62, decay: 1.65, tone: 0.78, drive: 0.95, level: 0.95)
            p[.snare] = DrumVoiceParams(tune: 1.2, decay: 0.8, tone: 1.05, drive: 0.9, level: 0.72)
            p[.tom] = DrumVoiceParams(tune: 0.55, decay: 1.45, tone: 0.74, drive: 0.85, level: 0.82)
            p[.crash] = DrumVoiceParams(tune: 0.72, decay: 0.75, tone: 0.58, drive: 0.7, level: 0.32)
            p[.ride] = DrumVoiceParams(tune: 0.78, decay: 0.62, tone: 0.62, drive: 0.75, level: 0.28)
        }
        return p
    }

    public static func kitLayers(for genre: DrumGenre) -> [SequencerLayer] {
        switch genre {
        case .techHouse:
            return [SequencerLayer(name: "Punch Kick", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "Layered Clap", source: .builtIn, note: DrumVoiceID.clap.midiNote), SequencerLayer(name: "Tight Closed Hat", source: .builtIn, note: DrumVoiceID.closedHat.midiNote), SequencerLayer(name: "Open Hat", source: .builtIn, note: DrumVoiceID.openHat.midiNote), SequencerLayer(name: "Rim Tick", source: .builtIn, note: DrumVoiceID.rim.midiNote)]
        case .guaracha:
            return [SequencerLayer(name: "Guaracha Knock Kick", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "Zap Bass Shot", source: .synthesized, note: DrumVoiceID.sub808.midiNote), SequencerLayer(name: "Dry Snap Clap", source: .builtIn, note: DrumVoiceID.clap.midiNote), SequencerLayer(name: "Wood Rim Bounce", source: .builtIn, note: DrumVoiceID.rim.midiNote), SequencerLayer(name: "Needle Hat", source: .builtIn, note: DrumVoiceID.closedHat.midiNote), SequencerLayer(name: "Short Open Hat", source: .builtIn, note: DrumVoiceID.openHat.midiNote)]
        case .reggaeton332, .moombah, .moombahton, .dembow:
            return [SequencerLayer(name: "Bailaton Kick", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "Sub Thump", source: .builtIn, note: DrumVoiceID.sub808.midiNote), SequencerLayer(name: "Dembow Snare", source: .builtIn, note: DrumVoiceID.snare.midiNote), SequencerLayer(name: "Palm Clap", source: .builtIn, note: DrumVoiceID.clap.midiNote), SequencerLayer(name: "Rim Accent", source: .builtIn, note: DrumVoiceID.rim.midiNote), SequencerLayer(name: "Shaker Hat", source: .builtIn, note: DrumVoiceID.closedHat.midiNote)]
        case .edm:
            return [SequencerLayer(name: "Big Kick", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "Snare", source: .builtIn, note: DrumVoiceID.snare.midiNote), SequencerLayer(name: "Closed Hat", source: .builtIn, note: DrumVoiceID.closedHat.midiNote), SequencerLayer(name: "Crash", source: .builtIn, note: DrumVoiceID.crash.midiNote), SequencerLayer(name: "Tom Fill", source: .builtIn, note: DrumVoiceID.tom.midiNote)]
        case .lofi:
            return [SequencerLayer(name: "Dusty Kick", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "Soft Snare", source: .builtIn, note: DrumVoiceID.snare.midiNote), SequencerLayer(name: "Loose Hat", source: .builtIn, note: DrumVoiceID.closedHat.midiNote), SequencerLayer(name: "Rim", source: .builtIn, note: DrumVoiceID.rim.midiNote)]
        case .slapHouse:
            return [SequencerLayer(name: "Sidechain Kick", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "808 Bass", source: .builtIn, note: DrumVoiceID.sub808.midiNote), SequencerLayer(name: "Clap", source: .builtIn, note: DrumVoiceID.clap.midiNote), SequencerLayer(name: "Open Hat", source: .builtIn, note: DrumVoiceID.openHat.midiNote)]
        case .breakbeat:
            return [SequencerLayer(name: "Break Kick", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "Cracked Snare", source: .builtIn, note: DrumVoiceID.snare.midiNote), SequencerLayer(name: "Hat Shuffle", source: .builtIn, note: DrumVoiceID.closedHat.midiNote), SequencerLayer(name: "Ride", source: .builtIn, note: DrumVoiceID.ride.midiNote)]
        case .dubstep:
            return [SequencerLayer(name: "Half-Time Kick", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "Riot Snare", source: .builtIn, note: DrumVoiceID.snare.midiNote), SequencerLayer(name: "Wobble Sub", source: .synthesized, note: DrumVoiceID.sub808.midiNote), SequencerLayer(name: "Tension Hat", source: .builtIn, note: DrumVoiceID.closedHat.midiNote), SequencerLayer(name: "Metal Rim", source: .builtIn, note: DrumVoiceID.rim.midiNote)]
        case .rock:
            return [SequencerLayer(name: "Rock Kick", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "Rock Snare", source: .builtIn, note: DrumVoiceID.snare.midiNote), SequencerLayer(name: "Closed Hat", source: .builtIn, note: DrumVoiceID.closedHat.midiNote), SequencerLayer(name: "Rack Tom", source: .builtIn, note: DrumVoiceID.tom.midiNote), SequencerLayer(name: "Crash", source: .builtIn, note: DrumVoiceID.crash.midiNote), SequencerLayer(name: "Ride", source: .builtIn, note: DrumVoiceID.ride.midiNote)]
        case .orchestral:
            return [SequencerLayer(name: "Gran Cassa", source: .builtIn, note: DrumVoiceID.kick.midiNote), SequencerLayer(name: "Concert Snare", source: .builtIn, note: DrumVoiceID.snare.midiNote), SequencerLayer(name: "Timpani Hit", source: .builtIn, note: DrumVoiceID.tom.midiNote), SequencerLayer(name: "Suspended Cymbal", source: .builtIn, note: DrumVoiceID.crash.midiNote), SequencerLayer(name: "Piatti / Crash", source: .builtIn, note: DrumVoiceID.ride.midiNote)]
        }
    }

    /// 16-step grooves (rows keyed by voice). 1 = hit. Returns [(voice, steps)].
    public static func groove(for genre: DrumGenre) -> [(DrumVoiceID, [Int])] {
        switch genre {
        case .lofi: return [
            (.kick,      [1,0,0,0, 0,0,1,0, 0,0,1,0, 0,0,0,0]),
            (.snare,     [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,1]),
            (.closedHat, [1,0,1,1, 1,0,1,0, 1,0,1,1, 1,0,1,0]),
        ]
        case .techHouse: return [
            (.kick,      [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0]),
            (.clap,      [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.closedHat, [0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0]),
            (.openHat,   [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,1,0]),
        ]
        case .slapHouse: return [
            (.kick,      [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0]),
            (.sub808,    [1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,1,0]),
            (.clap,      [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.openHat,   [0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0]),
        ]
        case .edm: return [
            (.kick,      [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0]),
            (.snare,     [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.closedHat, [1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1]),
            (.crash,     [1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0]),
        ]
        case .guaracha: return [
            (.kick,      [1,0,0,1, 1,0,1,0, 1,0,0,1, 1,0,1,0]),
            (.sub808,    [0,0,1,0, 0,0,1,0, 0,0,1,0, 0,0,1,0]),
            (.clap,      [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.rim,       [0,1,0,0, 0,0,1,0, 0,1,0,0, 0,0,1,1]),
            (.closedHat, [1,0,1,0, 1,1,0,1, 1,0,1,0, 1,1,0,1]),
            (.openHat,   [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,1,0]),
        ]
        case .reggaeton332: return [
            (.kick,      [1,0,0,1, 0,0,1,0, 0,1,0,0, 1,0,0,0]),
            (.snare,     [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.clap,      [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.closedHat, [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]),
        ]
        case .moombah: return [
            (.kick,      [1,0,0,0, 1,0,1,0, 1,0,0,0, 1,0,1,0]),
            (.snare,     [0,0,0,1, 0,0,0,0, 0,0,0,1, 0,0,0,0]),
            (.clap,      [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.rim,       [0,1,0,0, 0,0,1,0, 0,1,0,0, 0,0,1,0]),
            (.closedHat, [1,0,1,0, 1,1,1,0, 1,0,1,0, 1,1,1,0]),
        ]
        case .moombahton: return [
            (.kick,      [1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0]),
            (.sub808,    [1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,1,0]),
            (.snare,     [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.closedHat, [1,0,1,1, 1,0,1,0, 1,0,1,1, 1,0,1,0]),
        ]
        case .dembow: return [
            (.kick,      [1,0,0,1, 0,0,1,0, 1,0,0,1, 0,0,1,0]),
            (.snare,     [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.clap,      [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.rim,       [0,0,1,0, 0,0,0,1, 0,0,1,0, 0,0,0,1]),
            (.closedHat, [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0]),
        ]
        case .breakbeat: return [
            (.kick,      [1,0,0,0, 0,0,1,0, 0,0,1,0, 0,0,0,0]),
            (.snare,     [0,0,0,0, 1,0,0,1, 0,1,0,0, 1,0,0,0]),
            (.closedHat, [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,1]),
        ]
        case .dubstep: return [
            (.kick,      [1,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0,0]),
            (.snare,     [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.sub808,    [1,0,0,1, 0,0,1,0, 1,0,0,1, 0,1,0,0]),
            (.closedHat, [1,0,1,0, 0,0,1,0, 1,0,1,0, 0,1,1,0]),
            (.rim,       [0,0,0,1, 0,0,0,0, 0,0,0,1, 0,0,1,0]),
        ]
        case .rock: return [
            (.kick,      [1,0,0,0, 0,0,1,0, 1,0,0,0, 0,0,1,0]),
            (.snare,     [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0]),
            (.closedHat, [1,1,1,1, 1,1,1,1, 1,1,1,1, 1,1,1,1]),
            (.tom,       [0,0,0,0, 0,0,0,0, 0,0,1,0, 0,1,0,0]),
            (.crash,     [1,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0]),
        ]
        case .orchestral: return [
            (.kick,      [1,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0,0]),
            (.snare,     [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,1,0]),
            (.tom,       [1,0,0,0, 0,0,1,0, 1,0,0,0, 0,1,0,0]),
            (.crash,     [0,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0,0]),
            (.ride,      [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0]),
        ]
        }
    }
}
