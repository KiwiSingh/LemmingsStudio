import Foundation

// MARK: - Instrument protocol

/// A note event the sequencer feeds to instruments. Times are absolute frames.
public struct NoteEvent {
    public var note: Int        // MIDI number
    public var velocity: Float  // 0...1
    public var on: Bool
    public init(note: Int, velocity: Float, on: Bool) {
        self.note = note; self.velocity = velocity; self.on = on
    }
}

public protocol Instrument: AnyObject {
    var name: String { get }
    /// Render `frameCount` mono samples into `out`. Called on the audio thread.
    func render(into out: UnsafeMutablePointer<Float>, frames: Int)
    /// Optionally render stereo directly (hosted AU instruments). Return true if
    /// `left`/`right` were filled; default returns false so the engine renders
    /// mono via `render(into:)` and duplicates it across both channels.
    func renderStereo(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) -> Bool
    func noteOn(_ note: Int, velocity: Float)
    func noteOff(_ note: Int)
    func allNotesOff()

    /// Expressive MIDI hooks. Existing simple instruments can ignore these; hosted
    /// AUs receive real channelized MIDI for MPE-capable plug-ins.
    func noteOn(_ note: Int, velocity: Float, channel: Int)
    func noteOff(_ note: Int, channel: Int)
    func pitchBend(_ value: Float, channel: Int, rangeSemitones: Int)
    func pressure(_ value: Float, note: Int?, channel: Int)
    func timbre(_ value: Float, channel: Int)
}

public extension Instrument {
    func renderStereo(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) -> Bool { false }
    func noteOn(_ note: Int, velocity: Float, channel: Int) { noteOn(note, velocity: velocity) }
    func noteOff(_ note: Int, channel: Int) { noteOff(note) }
    func pitchBend(_ value: Float, channel: Int, rangeSemitones: Int) {}
    func pressure(_ value: Float, note: Int?, channel: Int) {}
    func timbre(_ value: Float, channel: Int) {}
}

// MARK: - Stock analog patch target support

/// Common surface the Sound Agent uses for every LemmingsStudio stock synth
/// that is ultimately driven by one or more AnalogSynth voices. This keeps the
/// built-in devices from being second-class compared with AU plug-ins: the
/// agent can apply the same ADSR/filter/oscillator recipe to Analog Synth,
/// Bass Synth/LemmingBass, Oscillatron, and the melodic voices inside Bhangra
/// Architect without routing through AU automation.
public protocol StockAnalogPatchable: AnyObject {
    var stockAnalogDisplayName: String { get }
    var stockAnalogParameters: [ParamInfo] { get }
    func applyStockAnalogPreset(_ preset: AnalogPreset)
    func setStockAnalogParam(_ id: String, _ value: Double)
    func getStockAnalogParam(_ id: String) -> Double
}

// MARK: - Analog subtractive synth

public final class AnalogSynth: Instrument, StockAnalogPatchable {
    public let name: String
    public var preset = AnalogPreset()

    private final class Voice {
        var note: Int = -1
        var osc1: Oscillator
        var osc2: Oscillator
        var env: ADSR
        var filter: SVFilter
        var velocity: Float = 1
        init(sr: Double) {
            osc1 = Oscillator(sampleRate: sr)
            osc2 = Oscillator(sampleRate: sr)
            env = ADSR(sampleRate: sr)
            filter = SVFilter(sampleRate: sr)
        }
    }

    private var voices: [Voice]
    private let sampleRate: Double
    private var globalPitchBend: Double = 0
    private var bendRangeSemitones: Int = 2

    public init(name: String = "Analog", sampleRate: Double, polyphony: Int = 16) {
        self.name = name
        self.sampleRate = sampleRate
        self.voices = (0..<polyphony).map { _ in Voice(sr: sampleRate) }
    }

    public func noteOn(_ note: Int, velocity: Float) {
        let voice = voices.first(where: { !$0.env.isActive }) ?? voices.min(by: { $0.note < $1.note })!
        voice.note = note
        voice.velocity = velocity
        voice.osc1.waveform = preset.osc1
        voice.osc2.waveform = preset.osc2
        voice.osc1.reset(); voice.osc2.reset()
        voice.env.attack = preset.attack
        voice.env.decay = preset.decay
        voice.env.sustain = preset.sustain
        voice.env.release = preset.release
        voice.filter.cutoff = preset.cutoff
        voice.filter.resonance = preset.resonance
        voice.filter.reset()
        voice.env.gateOn()
    }

    public func noteOff(_ note: Int) {
        for v in voices where v.note == note { v.env.gateOff() }
    }

    public func allNotesOff() { for v in voices { v.env.gateOff() } }

    public func pitchBend(_ value: Float, channel: Int, rangeSemitones: Int) {
        bendRangeSemitones = max(1, rangeSemitones)
        globalPitchBend = Double(max(-1, min(1, value))) * Double(bendRangeSemitones)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames { out[i] = 0 }
        let detune = pow(2.0, preset.detuneCents / 1200.0)
        for v in voices where v.env.isActive {
            let bendRatio = pow(2.0, globalPitchBend / 12.0)
            let f0 = MIDINote(v.note).frequency * bendRatio
            for i in 0..<frames {
                let a = v.osc1.next(frequency: f0)
                let b = v.osc2.next(frequency: f0 * detune) * preset.osc2Mix
                var s = (a + b) / (1 + preset.osc2Mix)
                s = v.filter.process(s)
                s *= v.env.next() * v.velocity * preset.gain
                out[i] += s
            }
        }
        // gentle soft-clip to keep the bus tame
        for i in 0..<frames { out[i] = tanhApprox(out[i]) }
    }

    @inline(__always) private func tanhApprox(_ x: Float) -> Float {
        let x2 = x * x
        return x * (27 + x2) / (27 + 9 * x2)
    }

    public var stockAnalogDisplayName: String { name }
    public var stockAnalogParameters: [ParamInfo] { automatableParams }
    public func applyStockAnalogPreset(_ preset: AnalogPreset) { self.preset = preset }
    public func setStockAnalogParam(_ id: String, _ value: Double) { setParam(id, value) }
    public func getStockAnalogParam(_ id: String) -> Double { getParam(id) }
}

public struct AnalogPreset {
    public var osc1: Waveform = .saw
    public var osc2: Waveform = .saw
    public var osc2Mix: Float = 0.5
    public var detuneCents: Double = 8
    public var cutoff: Double = 1800
    public var resonance: Double = 0.25
    public var attack: Double = 0.005
    public var decay: Double = 0.15
    public var sustain: Double = 0.7
    public var release: Double = 0.3
    public var gain: Float = 0.5
    public init() {}
}

// MARK: - Guitar (Karplus-Strong)

public final class GuitarInstrument: Instrument {
    public let name = "Acoustic/Electric Guitar"
    private var strings: [Int: KarplusStrong] = [:]
    private let sampleRate: Double
    public var brightness: Float = 0.996

    public init(sampleRate: Double) { self.sampleRate = sampleRate }

    public func noteOn(_ note: Int, velocity: Float) {
        let ks = KarplusStrong(sampleRate: sampleRate)
        ks.damping = brightness
        ks.pluck(frequency: MIDINote(note).frequency, velocity: max(0.2, velocity))
        strings[note] = ks
    }
    public func noteOff(_ note: Int) { strings[note]?.stop() }
    public func allNotesOff() { strings.values.forEach { $0.stop() } }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames { out[i] = 0 }
        for (note, ks) in strings {
            if !ks.isActive { strings[note] = nil; continue }
            for i in 0..<frames { out[i] += ks.next() * 0.6 }
        }
    }
}

// MARK: - Indian percussion (synthesized, no samples required)

/// Stroke vocabulary covers tabla, dhol, and dholak voicings. These are modal/membrane
/// syntheses — placeholders that sound usable but are meant to be swapped for
/// sampled multisamples later (see README "Swapping in real samples").
public enum IndianStroke: String, CaseIterable, Identifiable {
    case na, tin, dha, ge, ta, dholThump, dholSlap, tablaBass, dholOpen, dholBass, dholakBass, dholakNa
    public var id: String { rawValue }
}

public final class IndianPercussion: Instrument {
    public let name = "Indian Percussion"
    private let sampleRate: Double

    private final class Hit {
        var phases: [Double]
        var freqs: [Double]
        var amps: [Float]
        var decay: Float
        var env: Float = 1
        var noiseAmt: Float
        var noiseEnv: Float = 1
        var noiseDecay: Float
        init(freqs: [Double], amps: [Float], decay: Float, noiseAmt: Float, noiseDecay: Float) {
            self.freqs = freqs; self.amps = amps; self.decay = decay
            self.phases = Array(repeating: 0, count: freqs.count)
            self.noiseAmt = noiseAmt; self.noiseDecay = noiseDecay
        }
        var alive: Bool { env > 1e-4 || noiseEnv > 1e-4 }
    }

    private var hits: [Hit] = []
    public init(sampleRate: Double) { self.sampleRate = sampleRate }

    /// Map MIDI notes to strokes so a step sequencer / piano roll can drive it.
    public static func stroke(for note: Int) -> IndianStroke {
        if (60..<(60 + IndianStroke.allCases.count)).contains(note) { return IndianStroke.allCases[note - 60] }
        switch note { case 45: return .dholThump; case 47: return .dholSlap; case 64: return .ta; case 72: return .tin; case 76: return .na; default: return IndianStroke.allCases[((note % IndianStroke.allCases.count) + IndianStroke.allCases.count) % IndianStroke.allCases.count] }
    }

    public func trigger(_ stroke: IndianStroke, velocity: Float = 1) {
        let hit: Hit
        switch stroke {
        case .na:        hit = Hit(freqs: [880, 1320, 1760], amps: [1, 0.5, 0.3], decay: 0.9990, noiseAmt: 0.2, noiseDecay: 0.985)
        case .tin:       hit = Hit(freqs: [1046, 1568], amps: [1, 0.4], decay: 0.9993, noiseAmt: 0.15, noiseDecay: 0.99)
        case .dha:       hit = Hit(freqs: [196, 392, 880], amps: [1, 0.6, 0.4], decay: 0.9994, noiseAmt: 0.3, noiseDecay: 0.98)
        case .ge:        hit = Hit(freqs: [110, 165], amps: [1, 0.5], decay: 0.9990, noiseAmt: 0.1, noiseDecay: 0.97)
        case .ta:        hit = Hit(freqs: [740, 1100], amps: [1, 0.5], decay: 0.9985, noiseAmt: 0.4, noiseDecay: 0.97)
        case .dholThump: hit = Hit(freqs: [82, 120], amps: [1, 0.5], decay: 0.9992, noiseAmt: 0.2, noiseDecay: 0.96)
        case .dholSlap:  hit = Hit(freqs: [520, 900], amps: [0.7, 0.5], decay: 0.997, noiseAmt: 0.8, noiseDecay: 0.95)
        case .tablaBass: hit = Hit(freqs: [98, 147], amps: [1, 0.4], decay: 0.9995, noiseAmt: 0.15, noiseDecay: 0.97)
        case .dholOpen:  hit = Hit(freqs: [155, 310, 620], amps: [1, 0.55, 0.22], decay: 0.9996, noiseAmt: 0.18, noiseDecay: 0.975)
        case .dholBass:  hit = Hit(freqs: [64, 92, 128], amps: [1.0, 0.75, 0.35], decay: 0.9997, noiseAmt: 0.12, noiseDecay: 0.965)
        case .dholakBass: hit = Hit(freqs: [88, 132, 220], amps: [1.0, 0.52, 0.22], decay: 0.99945, noiseAmt: 0.10, noiseDecay: 0.972)
        case .dholakNa:  hit = Hit(freqs: [430, 860, 1290], amps: [0.9, 0.45, 0.22], decay: 0.9982, noiseAmt: 0.55, noiseDecay: 0.955)
        }
        for i in hit.amps.indices { hit.amps[i] *= velocity }
        hits.append(hit)
        if hits.count > 32 { hits.removeFirst() }
    }

    public func noteOn(_ note: Int, velocity: Float) { trigger(Self.stroke(for: note), velocity: velocity) }
    public func noteOff(_ note: Int) {}
    public func allNotesOff() { hits.removeAll() }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames { out[i] = 0 }
        for hit in hits where hit.alive {
            for i in 0..<frames {
                var s: Float = 0
                for k in hit.freqs.indices {
                    hit.phases[k] += hit.freqs[k] / sampleRate
                    if hit.phases[k] >= 1 { hit.phases[k] -= 1 }
                    s += Float(sin(2 * .pi * hit.phases[k])) * hit.amps[k]
                }
                s *= hit.env
                s += Float.random(in: -1...1) * hit.noiseAmt * hit.noiseEnv
                out[i] += s * 0.35
                hit.env *= hit.decay
                hit.noiseEnv *= hit.noiseDecay
            }
        }
        hits.removeAll { !$0.alive }
    }
}

// MARK: - Bhangra toolkit

/// Pre-built dhol grooves on top of IndianPercussion. Each pattern is a 16-step
/// grid of strokes (nil == rest). Drive these from the step sequencer.
public struct BhangraToolkit {
    public struct Groove: Identifiable {
        public let id = UUID()
        public let name: String
        public let bpm: Int
        public let steps: [IndianStroke?]   // length 16
    }

    public static let chaal = Groove(
        name: "Chaal (classic)", bpm: 100,
        steps: [.dholBass, nil, .dholSlap, .dholOpen,
                .dholThump, nil, .dholakNa, nil,
                .dholBass, nil, .dholSlap, .dholOpen,
                .dholakBass, .dholSlap, .dholakNa, nil])

    public static let dhamaal = Groove(
        name: "Dhamaal (energetic)", bpm: 120,
        steps: [.dholBass, .dholSlap, .dholOpen, .dholSlap,
                .dholakBass, .dholSlap, .dholBass, .dholakNa,
                .dholBass, .dholSlap, .dholOpen, .dholSlap,
                .dholakBass, .dholSlap, .dholSlap, .dholakNa])

    public static let kaharva = Groove(
        name: "Kaharva (8-beat)", bpm: 90,
        steps: [.dholakBass, nil, .dholakNa, .na, .tin, nil, .dholakNa, nil,
                .dholakBass, nil, .ge, .na, .tin, nil, .dholakNa, nil])

    public static let all = [chaal, dhamaal, kaharva]

    /// Full FL-style lane list for Bhangra Architect. Every stroke gets its own
    /// independent row, so toggling Kaharva/Dhamaal cells never disables a whole
    /// instrument lane.
    public static let layers: [SequencerLayer] = IndianStroke.allCases.enumerated().map { index, stroke in
        let label: String
        switch stroke {
        case .na: label = "Na / Chimta"
        case .tin: label = "Tin / Tumbi"
        case .dha: label = "Dha"
        case .ge: label = "Ge / Bass"
        case .ta: label = "Ta"
        case .dholThump: label = "Dhol Thump"
        case .dholSlap: label = "Dhol Slap"
        case .tablaBass: label = "Tabla Bass"
        case .dholOpen: label = "Dhol Open Ring"
        case .dholBass: label = "Dhol Bass Head"
        case .dholakBass: label = "Dholak Bayan"
        case .dholakNa: label = "Dholak Na"
        }
        return SequencerLayer(name: label, source: .builtIn, note: 60 + index)
    } + [
        SequencerLayer(name: "Tumbi Pluck", source: .synthesized, note: 84, velocity: 0.82),
        SequencerLayer(name: "Algoza Reed", source: .synthesized, note: 86, velocity: 0.70)
    ]
}

public final class BhangraArchitectInstrument: Instrument {
    public let name = "Bhangra Architect"
    private let percussion: IndianPercussion
    private let tumbi: AnalogSynth
    private let reed: AnalogSynth
    public init(sampleRate: Double) {
        percussion = IndianPercussion(sampleRate: sampleRate)
        tumbi = AnalogSynth(name: "Tumbi", sampleRate: sampleRate, polyphony: 6)
        tumbi.preset.osc1 = .square; tumbi.preset.osc2 = .saw; tumbi.preset.osc2Mix = 0.18
        tumbi.preset.cutoff = 4200; tumbi.preset.resonance = 0.22
        tumbi.preset.attack = 0.001; tumbi.preset.decay = 0.08; tumbi.preset.sustain = 0.25; tumbi.preset.release = 0.07; tumbi.preset.gain = 0.42
        reed = AnalogSynth(name: "Algoza Reed", sampleRate: sampleRate, polyphony: 4)
        reed.preset.osc1 = .saw; reed.preset.osc2 = .square; reed.preset.osc2Mix = 0.25; reed.preset.detuneCents = 7
        reed.preset.cutoff = 2500; reed.preset.resonance = 0.35; reed.preset.attack = 0.01; reed.preset.decay = 0.18; reed.preset.sustain = 0.55; reed.preset.release = 0.12; reed.preset.gain = 0.32
    }
    public func noteOn(_ note: Int, velocity: Float) {
        switch note { case 84: tumbi.noteOn(76, velocity: velocity); case 86: reed.noteOn(79, velocity: velocity); case 87...108: tumbi.noteOn(note, velocity: velocity); default: percussion.noteOn(note, velocity: velocity) }
    }
    public func noteOff(_ note: Int) { if note == 84 { tumbi.noteOff(76) } else if note == 86 { reed.noteOff(79) } else { tumbi.noteOff(note); reed.noteOff(note); percussion.noteOff(note) } }
    public func allNotesOff() { percussion.allNotesOff(); tumbi.allNotesOff(); reed.allNotesOff() }
    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        percussion.render(into: out, frames: frames)
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: frames); defer { buf.deallocate() }
        tumbi.render(into: buf, frames: frames); for i in 0..<frames { out[i] = tanh(out[i] + buf[i] * 0.9) }
        reed.render(into: buf, frames: frames); for i in 0..<frames { out[i] = tanh(out[i] + buf[i] * 0.65) }
    }
}

extension BhangraArchitectInstrument: StockAnalogPatchable {
    public var stockAnalogDisplayName: String { name }
    public var stockAnalogParameters: [ParamInfo] { tumbi.automatableParams }
    public func applyStockAnalogPreset(_ preset: AnalogPreset) {
        tumbi.preset = preset
        var reedPreset = preset
        reedPreset.cutoff = max(900, min(7000, preset.cutoff * 0.85))
        reedPreset.resonance = min(0.9, preset.resonance + 0.10)
        reedPreset.gain = max(0.18, min(0.5, preset.gain * 0.75))
        reed.preset = reedPreset
    }
    public func setStockAnalogParam(_ id: String, _ value: Double) {
        tumbi.setParam(id, value)
        reed.setParam(id, value)
    }
    public func getStockAnalogParam(_ id: String) -> Double { tumbi.getParam(id) }
}

// MARK: - Original beta instruments

public final class OscillatronInstrument: Instrument, Automatable {
    public let name = "Oscillatron"

    private final class Voice {
        var note: Int = -1
        var velocity: Float = 1
        var osc1: Oscillator
        var osc2: Oscillator
        var osc3: Oscillator
        var sub: Oscillator
        var env: ADSR
        var filter: SVFilter
        init(sampleRate: Double) {
            osc1 = Oscillator(sampleRate: sampleRate)
            osc2 = Oscillator(sampleRate: sampleRate)
            osc3 = Oscillator(sampleRate: sampleRate)
            sub = Oscillator(sampleRate: sampleRate)
            env = ADSR(sampleRate: sampleRate)
            filter = SVFilter(sampleRate: sampleRate)
        }
    }

    public struct Patch {
        public var osc1Level: Float = 0.95
        public var osc2Level: Float = 0.72
        public var osc3Level: Float = 0.48
        public var subLevel: Float = 0.20
        public var osc2DetuneCents: Double = 7
        public var osc3DetuneCents: Double = -12
        public var osc3Interval: Double = 7
        public var lemmingShape: Double = 0.42
        public var cutoff: Double = 3200
        public var resonance: Double = 0.24
        public var attack: Double = 0.004
        public var decay: Double = 0.14
        public var sustain: Double = 0.70
        public var release: Double = 0.18
        public var gain: Float = 0.48
        public init() {}
    }

    public var patch = Patch()
    private var voices: [Voice]
    private let sampleRate: Double
    private var shapePhase: Double = 0
    private var globalPitchBend: Double = 0
    private var bendRangeSemitones: Int = 2

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        voices = (0..<12).map { _ in Voice(sampleRate: sampleRate) }
    }

    public func noteOn(_ note: Int, velocity: Float) {
        let voice = voices.first(where: { !$0.env.isActive }) ?? voices.min(by: { $0.note < $1.note })!
        voice.note = note
        voice.velocity = velocity
        voice.osc1.waveform = .saw
        voice.osc2.waveform = .square
        voice.osc3.waveform = .triangle
        voice.sub.waveform = .sine
        voice.osc1.reset(); voice.osc2.reset(); voice.osc3.reset(); voice.sub.reset()
        voice.env.attack = patch.attack
        voice.env.decay = patch.decay
        voice.env.sustain = patch.sustain
        voice.env.release = patch.release
        voice.filter.cutoff = patch.cutoff
        voice.filter.resonance = patch.resonance
        voice.filter.mode = .lowpass
        voice.filter.reset()
        voice.env.gateOn()
    }

    public func noteOff(_ note: Int) {
        for v in voices where v.note == note { v.env.gateOff() }
    }

    public func allNotesOff() { voices.forEach { $0.env.gateOff() } }

    public func pitchBend(_ value: Float, channel: Int, rangeSemitones: Int) {
        bendRangeSemitones = max(1, rangeSemitones)
        globalPitchBend = Double(max(-1, min(1, value))) * Double(bendRangeSemitones)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames { out[i] = 0 }
        let bendRatio = pow(2.0, globalPitchBend / 12.0)
        let d2 = pow(2.0, patch.osc2DetuneCents / 1200.0)
        let d3 = pow(2.0, (patch.osc3Interval + patch.osc3DetuneCents / 100.0) / 12.0)
        let shapeAmt = Float(max(0, min(1, patch.lemmingShape)))
        for v in voices where v.env.isActive {
            let f0 = MIDINote(v.note).frequency * bendRatio
            for i in 0..<frames {
                shapePhase += 1.0 / max(1, sampleRate)
                let morph = Float(0.5 + 0.5 * sin(2 * .pi * 0.37 * shapePhase) * cos(2 * .pi * 0.23 * shapePhase))
                let osc1 = v.osc1.next(frequency: f0) * patch.osc1Level
                let osc2 = v.osc2.next(frequency: f0 * d2) * patch.osc2Level
                let osc3 = v.osc3.next(frequency: f0 * d3) * patch.osc3Level * (0.65 + 0.35 * morph)
                let sub = v.sub.next(frequency: max(8, f0 * 0.5)) * patch.subLevel
                let denom = max(0.1, patch.osc1Level + patch.osc2Level + patch.osc3Level + patch.subLevel)
                var s = (osc1 + osc2 + osc3 + sub) / denom
                // The "exotic lemming" curve: a moving, asymmetric fold/saturator that
                // makes the 3-osc preset sound like a device, not a bare two-osc patch.
                let foldDrive = 1.0 + shapeAmt * (1.8 + morph)
                s = tanh(s * foldDrive)
                s = v.filter.process(s)
                s *= v.env.next() * v.velocity * patch.gain
                out[i] += s
            }
        }
        for i in 0..<frames { out[i] = tanh(out[i]) }
    }

    public var automatableParams: [ParamInfo] {
        [
            ParamInfo("osc1Level", "Osc 1", 0, 1),
            ParamInfo("osc2Level", "Osc 2", 0, 1),
            ParamInfo("osc3Level", "Osc 3", 0, 1),
            ParamInfo("subLevel", "Sub", 0, 1),
            ParamInfo("osc2DetuneCents", "Osc 2 Detune", -30, 30, unit: "ct"),
            ParamInfo("osc3DetuneCents", "Osc 3 Detune", -30, 30, unit: "ct"),
            ParamInfo("osc3Interval", "Osc 3 Interval", -12, 12, unit: "st"),
            ParamInfo("lemmingShape", "Lemming Shape", 0, 1),
            ParamInfo("cutoff", "Cutoff", 60, 12000, unit: "Hz", isLog: true),
            ParamInfo("resonance", "Resonance", 0, 0.98),
            ParamInfo("attack", "Attack", 0.001, 2, unit: "s"),
            ParamInfo("decay", "Decay", 0.005, 2, unit: "s"),
            ParamInfo("sustain", "Sustain", 0, 1),
            ParamInfo("release", "Release", 0.01, 3, unit: "s"),
            ParamInfo("gain", "Gain", 0, 1)
        ]
    }

    public func setParam(_ id: String, _ value: Double) {
        switch id {
        case "osc1Level": patch.osc1Level = Float(value)
        case "osc2Level", "osc2Mix": patch.osc2Level = Float(value)
        case "osc3Level": patch.osc3Level = Float(value)
        case "subLevel": patch.subLevel = Float(value)
        case "osc2DetuneCents", "detuneCents": patch.osc2DetuneCents = value
        case "osc3DetuneCents": patch.osc3DetuneCents = value
        case "osc3Interval": patch.osc3Interval = value
        case "lemmingShape": patch.lemmingShape = value
        case "cutoff": patch.cutoff = value
        case "resonance": patch.resonance = value
        case "attack": patch.attack = value
        case "decay": patch.decay = value
        case "sustain": patch.sustain = value
        case "release": patch.release = value
        case "gain": patch.gain = Float(value)
        default: break
        }
    }

    public func getParam(_ id: String) -> Double {
        switch id {
        case "osc1Level": return Double(patch.osc1Level)
        case "osc2Level", "osc2Mix": return Double(patch.osc2Level)
        case "osc3Level": return Double(patch.osc3Level)
        case "subLevel": return Double(patch.subLevel)
        case "osc2DetuneCents", "detuneCents": return patch.osc2DetuneCents
        case "osc3DetuneCents": return patch.osc3DetuneCents
        case "osc3Interval": return patch.osc3Interval
        case "lemmingShape": return patch.lemmingShape
        case "cutoff": return patch.cutoff
        case "resonance": return patch.resonance
        case "attack": return patch.attack
        case "decay": return patch.decay
        case "sustain": return patch.sustain
        case "release": return patch.release
        case "gain": return Double(patch.gain)
        default: return 0
        }
    }
}

extension OscillatronInstrument: StockAnalogPatchable {
    public var stockAnalogDisplayName: String { name }
    public var stockAnalogParameters: [ParamInfo] { automatableParams }
    public func applyStockAnalogPreset(_ preset: AnalogPreset) {
        patch.osc1Level = 0.90
        patch.osc2Level = preset.osc2Mix
        patch.osc3Level = 0.48
        patch.osc2DetuneCents = preset.detuneCents
        patch.cutoff = preset.cutoff
        patch.resonance = preset.resonance
        patch.attack = preset.attack
        patch.decay = preset.decay
        patch.sustain = preset.sustain
        patch.release = preset.release
        patch.gain = preset.gain
    }
    public func setStockAnalogParam(_ id: String, _ value: Double) { setParam(id, value) }
    public func getStockAnalogParam(_ id: String) -> Double { getParam(id) }
}

public final class DubstepWranglerInstrument: Instrument {
    public let name = "Dubstep Wrangler"
    private let bass: AnalogSynth
    private var lfoPhase: Double = 0
    private let sampleRate: Double
    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        bass = AnalogSynth(name: "Dubstep Wrangler", sampleRate: sampleRate, polyphony: 6)
        bass.preset.osc1 = .square; bass.preset.osc2 = .saw; bass.preset.osc2Mix = 0.85
        bass.preset.detuneCents = -19; bass.preset.cutoff = 900; bass.preset.resonance = 0.48
        bass.preset.attack = 0.002; bass.preset.decay = 0.16; bass.preset.sustain = 0.72; bass.preset.release = 0.08; bass.preset.gain = 0.62
    }
    public func noteOn(_ note: Int, velocity: Float) { bass.noteOn(note, velocity: velocity) }
    public func noteOff(_ note: Int) { bass.noteOff(note) }
    public func allNotesOff() { bass.allNotesOff() }
    public func pitchBend(_ value: Float, channel: Int, rangeSemitones: Int) { bass.pitchBend(value, channel: channel, rangeSemitones: rangeSemitones) }
    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        bass.render(into: out, frames: frames)
        for i in 0..<frames {
            lfoPhase += 1.0 / max(1, sampleRate)
            let wobble = Float(0.45 + 0.55 * abs(sin(2 * .pi * 2.0 * lfoPhase)))
            out[i] = tanh(out[i] * (0.65 + wobble * 0.85))
        }
    }
}

extension DubstepWranglerInstrument: StockAnalogPatchable {
    public var stockAnalogDisplayName: String { name }
    public var stockAnalogParameters: [ParamInfo] { bass.automatableParams }
    public func applyStockAnalogPreset(_ preset: AnalogPreset) { bass.preset = preset }
    public func setStockAnalogParam(_ id: String, _ value: Double) { bass.setParam(id, value) }
    public func getStockAnalogParam(_ id: String) -> Double { bass.getParam(id) }
}

public final class LemmingBassInstrument: Instrument, Automatable {
    public let name = "LemmingBass"

    private final class Voice {
        var note: Int = -1
        var velocity: Float = 1
        var osc: Oscillator
        var sub: Oscillator
        var click: Float = 0
        var env: ADSR
        var filter: SVFilter
        init(sampleRate: Double) {
            osc = Oscillator(sampleRate: sampleRate)
            sub = Oscillator(sampleRate: sampleRate)
            env = ADSR(sampleRate: sampleRate)
            filter = SVFilter(sampleRate: sampleRate)
        }
    }

    public struct Patch {
        public var wave: Double = 0.35          // 0=sine, 1=square-ish blend
        public var sub: Float = 0.55
        public var cutoff: Double = 620
        public var resonance: Double = 0.38
        public var attack: Double = 0.0015
        public var decay: Double = 0.22
        public var sustain: Double = 0.78
        public var release: Double = 0.075
        public var punch: Double = 0.48
        public var drive: Double = 0.36
        public var gain: Float = 0.82
        public init() {}
    }

    public var patch = Patch()
    private var voice: Voice
    private let sampleRate: Double
    private var globalPitchBend: Double = 0
    private var bendRangeSemitones: Int = 2

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        voice = Voice(sampleRate: sampleRate)
    }

    public func noteOn(_ note: Int, velocity: Float) {
        voice.note = note
        voice.velocity = velocity
        voice.osc.waveform = .sine
        voice.sub.waveform = .sine
        voice.osc.reset(); voice.sub.reset()
        voice.click = Float(max(0, min(1, patch.punch))) * velocity
        voice.env.attack = patch.attack
        voice.env.decay = patch.decay
        voice.env.sustain = patch.sustain
        voice.env.release = patch.release
        voice.filter.cutoff = patch.cutoff
        voice.filter.resonance = patch.resonance
        voice.filter.mode = .lowpass
        voice.filter.reset()
        voice.env.gateOn()
    }

    public func noteOff(_ note: Int) { if voice.note == note { voice.env.gateOff() } }
    public func allNotesOff() { voice.env.gateOff() }

    public func pitchBend(_ value: Float, channel: Int, rangeSemitones: Int) {
        bendRangeSemitones = max(1, rangeSemitones)
        globalPitchBend = Double(max(-1, min(1, value))) * Double(bendRangeSemitones)
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames { out[i] = 0 }
        guard voice.env.isActive, voice.note >= 0 else { return }
        let bendRatio = pow(2.0, globalPitchBend / 12.0)
        let base = MIDINote(voice.note).frequency * bendRatio
        let squareBlend = Float(max(0, min(1, patch.wave)))
        let drive = Float(1.0 + max(0, min(1, patch.drive)) * 5.0)
        for i in 0..<frames {
            let sine = voice.osc.next(frequency: base)
            let shaped = tanh(sine * (1.0 + squareBlend * 8.0))
            let main = sine * (1 - squareBlend) + shaped * squareBlend
            let sub = voice.sub.next(frequency: max(8, base * 0.5)) * patch.sub
            var s = (main + sub) / (1.0 + patch.sub)
            if voice.click > 0.0001 {
                s += voice.click * 0.28
                voice.click *= 0.985
            }
            s = voice.filter.process(s)
            s = tanh(s * drive)
            s *= voice.env.next() * voice.velocity * patch.gain
            out[i] = s
        }
    }

    public var automatableParams: [ParamInfo] {
        [
            ParamInfo("wave", "Wave", 0, 1),
            ParamInfo("sub", "Sub", 0, 1),
            ParamInfo("cutoff", "Cutoff", 40, 5000, unit: "Hz", isLog: true),
            ParamInfo("resonance", "Resonance", 0, 0.98),
            ParamInfo("attack", "Attack", 0.001, 1, unit: "s"),
            ParamInfo("decay", "Decay", 0.005, 2, unit: "s"),
            ParamInfo("sustain", "Sustain", 0, 1),
            ParamInfo("release", "Release", 0.005, 2, unit: "s"),
            ParamInfo("punch", "Punch", 0, 1),
            ParamInfo("drive", "Drive", 0, 1),
            ParamInfo("gain", "Gain", 0, 1)
        ]
    }

    public func setParam(_ id: String, _ value: Double) {
        switch id {
        case "wave": patch.wave = value
        case "sub", "osc2Mix": patch.sub = Float(value)
        case "cutoff": patch.cutoff = value
        case "resonance": patch.resonance = value
        case "attack": patch.attack = value
        case "decay": patch.decay = value
        case "sustain": patch.sustain = value
        case "release": patch.release = value
        case "punch": patch.punch = value
        case "drive": patch.drive = value
        case "gain": patch.gain = Float(value)
        default: break
        }
    }

    public func getParam(_ id: String) -> Double {
        switch id {
        case "wave": return patch.wave
        case "sub", "osc2Mix": return Double(patch.sub)
        case "cutoff": return patch.cutoff
        case "resonance": return patch.resonance
        case "attack": return patch.attack
        case "decay": return patch.decay
        case "sustain": return patch.sustain
        case "release": return patch.release
        case "punch": return patch.punch
        case "drive": return patch.drive
        case "gain": return Double(patch.gain)
        default: return 0
        }
    }
}

extension LemmingBassInstrument: StockAnalogPatchable {
    public var stockAnalogDisplayName: String { name }
    public var stockAnalogParameters: [ParamInfo] { automatableParams }
    public func applyStockAnalogPreset(_ preset: AnalogPreset) {
        patch.cutoff = preset.cutoff
        patch.resonance = preset.resonance
        patch.attack = preset.attack
        patch.decay = preset.decay
        patch.sustain = preset.sustain
        patch.release = preset.release
        patch.sub = preset.osc2Mix
        patch.gain = preset.gain
    }
    public func setStockAnalogParam(_ id: String, _ value: Double) { setParam(id, value) }
    public func getStockAnalogParam(_ id: String) -> Double { getParam(id) }
}
