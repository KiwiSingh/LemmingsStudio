import Foundation

// MARK: - Effect contracts (TRUE STEREO)
//
// Effects process a stereo pair in place on the audio thread, after the
// instrument fills the track's L/R scratch. Each effect is genuinely stereo;
// a per-device `mono` toggle (applied by the engine, which pre-collapses L/R to
// a mono sum before the effect) turns any device into a mono device — useful for
// keeping bass/utility processing centered. Every effect is Automatable so lanes,
// MIDI, and the AI assistant can drive it.

public protocol AudioEffect: AnyObject, Automatable {
    var kind: DeviceKind { get }
    var bypassed: Bool { get set }
    func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int)
    func reset()
}

public enum DeviceKind: String, CaseIterable, Identifiable, Sendable {
    // Fully implemented core devices
    case reverb     = "Room Space"
    case delay      = "Tempo Delay"
    case autoFilter = "Motion Filter"
    case eqEight    = "Eight-Band EQ"
    case compressor = "Dynamics Compressor"
    case tune       = "Pitch Corrector"

    // DAW-stock-equivalent registry. Many begin as safe no-op/utility shells so the
    // browser, racks, automation, AI agents, and project files can target them now;
    // individual DSP engines can be deepened over time without changing project schema.
    case alignDelay = "Sample Align"
    case analog = "Subtractive Synth"
    case amp = "Drive Amp"
    case arpeggiator = "Pattern Arp"
    case audioEffectRack = "FX Rack"
    case autoPan = "Motion Pan"
    case bass = "Bass Synth"
    case beatRepeat = "Beat Stutter"
    case bouncyNotes = "Note Bounce"
    case cabinet = "Speaker Cabinet"
    case channelEQ = "Channel Shaper"
    case chord = "Chord Builder"
    case chorusEnsemble = "Chorus Ensemble"
    case collision = "Modal Mallet"
    case corpus = "Body Resonator"
    case cvInstrument = "CV Instrument Bridge"
    case cvTriggers = "CV Trigger Bridge"
    case drift = "Analog Drift"
    case drumBuss = "Drum Drive Bus"
    case drumRack = "Drum Matrix"
    case dsClap = "Synth Clap"
    case dsClang = "Synth Clang"
    case dsCymbal = "Synth Cymbal"
    case dsHH = "Synth Hat"
    case dsKick = "Synth Kick"
    case dsSnare = "Synth Snare"
    case dsTone = "Synth Tone"
    case dynamicTube = "Tube Drive"
    case echo = "Space Echo"
    case fxArchitect = "FX Architect"
    case electric = "Electric Keys"
    case emit = "Particle Synth"
    case envelopeFollower = "Envelope Tracker"
    case eqThree = "Three-Band EQ"
    case erosion = "Noise Erode"
    case externalAudioEffect = "External FX Bridge"
    case externalInstrument = "External Instrument Bridge"
    case filterDelay = "Filtered Delay"
    case gate = "Noise Gate"
    case glueCompressor = "Bus Compressor"
    case grainDelay = "Grain Echo"
    case granulator = "Grain Cloud"
    case hybridReverb = "Hybrid Space"
    case impulse = "Percussion Pads"
    case instrumentRack = "Instrument Layer Rack"
    case lfo = "LFO"
    case limiter = "Peak Limiter"
    case looper = "Loop Recorder"
    case meld = "Morph Synth"
    case midiEffectRack = "MIDI Rack"
    case multibandDynamics = "Multiband Processor"
    case noteLength = "Note Gate Length"
    case operatorSynth = "FM Matrix"
    case overdrive = "Drive"
    case pedal = "Stomp Box"
    case phaserFlanger = "Phase Flange"
    case pitch = "Pitch Tool"
    case poli = "Poly Synth"
    case random = "Note Randomizer"
    case redux = "Bit Crusher"
    case resonators = "Tuned Resonators"
    case roar = "Multi-Drive"
    case sampler = "Multisampler"
    case saturator = "Saturation"
    case scale = "Scale Mapper"
    case shaper = "Mod Shaper"
    case shifter = "Frequency Shifter"
    case simpler = "Simple Sampler"
    case spectralResonator = "Spectral Body"
    case spectralTime = "Spectral Freeze"
    case spectrum = "Spectrum Analyzer"
    case tension = "String Modeler"
    case treeTone = "Branch Tone"
    case tuner = "Pitch Tuner"
    case utility = "Gain Utility"
    case vectorDelay = "Vector Echo"
    case vectorFM = "Vector FM Synth"
    case vectorGrain = "Vector Grain Synth"
    case velocity = "Velocity Mapper"
    case vinylDistortion = "Record Distortion"
    case vocoder = "Voice Coder"
    case wavetable = "Table Synth"

    // Culture/genre devices unique to LemmingsStudio.
    case bhangraArchitect = "Bhangra Architect"
    case guaracha2C = "2C"
    case bailaton = "Bailaton"
    case oscillatron = "Oscillatron"
    case lemmingBass = "LemmingBass"
    case dubstepWrangler = "Dubstep Wrangler"

    public var id: String { rawValue }
    /// Devices that are inherently stereo (others are fine collapsed to mono).
    public var isNaturallyStereo: Bool {
        switch self { case .reverb, .delay, .echo, .hybridReverb, .chorusEnsemble, .vectorDelay, .spectralTime, .granulator, .fxArchitect: return true; default: return false }
    }
}

public enum DeviceRole: String, Sendable {
    case audioEffect = "Audio Effect"
    case midiEffect = "MIDI Effect"
    case instrument = "Instrument"
    case rack = "Rack"
    case bridge = "Bridge"
    case analyzer = "Analyzer"
    case generator = "Generator"
}

public struct DeviceBrowserSection: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let role: DeviceRole
    public let devices: [DeviceKind]
}

extension DeviceKind {
    /// Built-in instruments are represented in the rack for editing, saving,
    /// automation and MIDI Learn, but they are not audio insert effects. The
    /// audio engine routes these DeviceModel rows to the track source
    /// instrument instead of putting them in the post-instrument FX chain.
    public var isBuiltInTrackInstrument: Bool {
        switch self {
        case .analog, .bass, .bhangraArchitect, .collision, .drift, .drumRack, .dsClap, .dsClang, .dsCymbal, .dsHH, .dsKick, .dsSnare, .dsTone, .electric, .emit, .guaracha2C, .bailaton, .impulse, .lemmingBass, .meld, .operatorSynth, .oscillatron, .poli, .sampler, .simpler, .tension, .treeTone, .vectorFM, .vectorGrain, .wavetable, .dubstepWrangler:
            return true
        default:
            return false
        }
    }

    public var role: DeviceRole {
        switch self {
        case .arpeggiator, .bouncyNotes, .chord, .midiEffectRack, .noteLength, .pitch, .random, .scale, .tune, .velocity:
            return .midiEffect
        case .analog, .bass, .bhangraArchitect, .collision, .drift, .drumRack, .dsClap, .dsClang, .dsCymbal, .dsHH, .dsKick, .dsSnare, .dsTone, .electric, .emit, .guaracha2C, .bailaton, .impulse, .lemmingBass, .meld, .operatorSynth, .oscillatron, .poli, .sampler, .simpler, .tension, .treeTone, .vectorFM, .vectorGrain, .wavetable:
            return .instrument
        case .audioEffectRack, .instrumentRack:
            return .rack
        case .cvInstrument, .cvTriggers, .externalAudioEffect, .externalInstrument:
            return .bridge
        case .spectrum, .tuner, .envelopeFollower, .lfo:
            return .analyzer
        case .dubstepWrangler:
            return .generator
        default:
            return .audioEffect
        }
    }

    public var browserCategory: String {
        switch self {
        case .alignDelay, .utility: return "Audio Effects · Utility"
        case .autoPan, .chorusEnsemble, .phaserFlanger, .shifter: return "Audio Effects · Modulation"
        case .beatRepeat, .delay, .echo, .filterDelay, .grainDelay, .looper, .spectralTime, .vectorDelay: return "Audio Effects · Delay / Loop"
        case .cabinet, .corpus, .erosion, .redux, .resonators, .spectralResonator, .vocoder: return "Audio Effects · Texture / Resonance"
        case .amp, .drumBuss, .dynamicTube, .overdrive, .pedal, .roar, .saturator, .vinylDistortion: return "Audio Effects · Drive / Color"
        case .autoFilter, .channelEQ, .eqEight, .eqThree, .fxArchitect, .shaper: return "Audio Effects · Filter / EQ"
        case .compressor, .gate, .glueCompressor, .limiter, .multibandDynamics: return "Audio Effects · Dynamics"
        case .hybridReverb, .reverb: return "Audio Effects · Reverb"
        case .arpeggiator, .bouncyNotes, .chord, .noteLength, .pitch, .random, .scale, .tune, .velocity: return "MIDI Effects"
        case .analog, .bass, .bhangraArchitect, .collision, .drift, .drumRack, .electric, .emit, .guaracha2C, .bailaton, .impulse, .lemmingBass, .meld, .operatorSynth, .oscillatron, .poli, .sampler, .simpler, .tension, .treeTone, .vectorFM, .vectorGrain, .wavetable: return "Instruments"
        case .audioEffectRack, .instrumentRack, .midiEffectRack: return "Racks"
        case .cvInstrument, .cvTriggers, .externalAudioEffect, .externalInstrument: return "External / CV Bridges"
        case .envelopeFollower, .lfo, .spectrum, .tuner: return "Analyzers / Modulators"
        case .dsClap, .dsClang, .dsCymbal, .dsHH, .dsKick, .dsSnare, .dsTone: return "Drum Synths"
        case .dubstepWrangler: return "Generators"
        case .granulator: return "Audio Effects · Texture / Resonance"
        }
    }

    public var implementationStatus: String {
        switch self {
        case .audioEffectRack, .instrumentRack, .midiEffectRack:
            return "Rack shell"
        case .cvInstrument, .cvTriggers, .externalAudioEffect, .externalInstrument:
            return "Bridge target"
        case .spectrum, .tuner, .envelopeFollower, .lfo:
            return "Analyzer/control"
        default:
            return "Implemented"
        }
    }

    public static var categorizedBrowserSections: [DeviceBrowserSection] {
        let order = [
            "Audio Effects · Delay / Loop",
            "Audio Effects · Drive / Color",
            "Audio Effects · Dynamics",
            "Audio Effects · Filter / EQ",
            "Audio Effects · Modulation",
            "Audio Effects · Reverb",
            "Audio Effects · Texture / Resonance",
            "Audio Effects · Utility",
            "MIDI Effects",
            "Instruments",
            "Drum Synths",
            "Generators",
            "Racks",
            "Analyzers / Modulators",
            "External / CV Bridges"
        ]
        let grouped = Dictionary(grouping: DeviceKind.allCases, by: { $0.browserCategory })
        return order.compactMap { title in
            guard let devices = grouped[title] else { return nil }
            let sorted = devices.sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
            let role = sorted.first?.role ?? .audioEffect
            return DeviceBrowserSection(id: title, title: title, role: role, devices: sorted)
        }
    }
}


@Observable public final class DeviceModel: Identifiable {
    public let id = UUID()
    public var kind: DeviceKind
    public var bypassed = false
    public var mono = false              // engine pre-collapses to mono before this device
    public var sidechainEnabled = false
    public var sidechainInputTrackID: UUID? = nil
    public var params: [String: Double]
    public init(kind: DeviceKind, params: [String: Double] = [:]) {
        self.kind = kind
        self.params = params.isEmpty ? DeviceFactory.defaults(for: kind) : params
    }
    public var nodeID: String { id.uuidString }
}

public enum DeviceFactory {
    public static func defaults(for kind: DeviceKind) -> [String: Double] {
        if kind.isBuiltInTrackInstrument {
            return builtInInstrumentDefaults(for: kind)
        }
        let fx = make(kind)
        var d: [String: Double] = [:]
        for p in fx.automatableParams { d[p.id] = fx.getParam(p.id) }
        return d
    }

    public static func builtInInstrumentParams(for kind: DeviceKind) -> [ParamInfo] {
        switch kind {
        case .oscillatron:
            return [
                ParamInfo("osc1Level", "Osc 1", 0, 1),
                ParamInfo("osc2Level", "Osc 2", 0, 1),
                ParamInfo("osc3Level", "Osc 3", 0, 1),
                ParamInfo("subLevel", "Sub", 0, 1),
                ParamInfo("osc2DetuneCents", "Osc 2 Detune", -50, 50, unit: "cent"),
                ParamInfo("osc3DetuneCents", "Osc 3 Detune", -50, 50, unit: "cent"),
                ParamInfo("osc3Interval", "Osc 3 Interval", -12, 12, unit: "st"),
                ParamInfo("lemmingShape", "Lemming Shape", 0, 1),
                ParamInfo("cutoff", "Cutoff", 40, 12000, unit: "Hz", isLog: true),
                ParamInfo("resonance", "Resonance", 0, 0.98),
                ParamInfo("attack", "Attack", 0.001, 2, unit: "s"),
                ParamInfo("decay", "Decay", 0.005, 2, unit: "s"),
                ParamInfo("sustain", "Sustain", 0, 1),
                ParamInfo("release", "Release", 0.005, 4, unit: "s"),
                ParamInfo("gain", "Gain", 0, 1)
            ]
        case .lemmingBass, .bass:
            return [
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
        default:
            return AnalogSynth(name: kind.rawValue, sampleRate: 44100).automatableParams
        }
    }

    private static func builtInInstrumentDefaults(for kind: DeviceKind) -> [String: Double] {
        let params = builtInInstrumentParams(for: kind)
        var d: [String: Double] = [:]
        switch kind {
        case .oscillatron:
            d = [
                "osc1Level": 0.95, "osc2Level": 0.72, "osc3Level": 0.48, "subLevel": 0.20,
                "osc2DetuneCents": 7, "osc3DetuneCents": -12, "osc3Interval": 7,
                "lemmingShape": 0.42, "cutoff": 3200, "resonance": 0.24,
                "attack": 0.004, "decay": 0.14, "sustain": 0.70, "release": 0.18, "gain": 0.48
            ]
        case .lemmingBass, .bass:
            d = [
                "wave": 0.35, "sub": 0.55, "cutoff": 620, "resonance": 0.38,
                "attack": 0.0015, "decay": 0.22, "sustain": 0.78, "release": 0.075,
                "punch": 0.48, "drive": 0.36, "gain": 0.82
            ]
        default:
            let synth = AnalogSynth(name: kind.rawValue, sampleRate: 44100)
            for p in synth.automatableParams { d[p.id] = synth.getParam(p.id) }
        }
        for p in params where d[p.id] == nil { d[p.id] = p.min }
        return d
    }
    public static func make(_ kind: DeviceKind) -> AudioEffect {
        switch kind {
        case .reverb:     return ReverbEffect()
        case .delay:      return DelayEffect()
        case .autoFilter: return AutoFilterEffect()
        case .eqEight:    return EQEightEffect()
        case .compressor: return CompressorEffect()
        case .tune:       return TuneEffect()
        default:
            if let stock = StockDSPFactory.make(kind) { return stock }
            return GenericUtilityEffect(kind: kind)
        }
    }
    public static func make(from model: DeviceModel, sampleRate: Double) -> AudioEffect {
        let fx = make(model.kind)
        (fx as? SampleRateAware)?.setSampleRate(sampleRate)
        for (k, v) in model.params { fx.setParam(k, v) }
        fx.bypassed = model.bypassed
        return fx
    }
}

protocol SampleRateAware: AnyObject { func setSampleRate(_ sr: Double) }

/// Effects whose timing is expressed in musical beats need the current host tempo.
/// Stock devices such as Beat Stutter must follow Arrangement tempo instead of
/// assuming a fixed 120 BPM conversion.
protocol TempoAware: AnyObject { func setTempo(_ bpm: Double) }

public protocol SidechainAudioEffect: AnyObject {
    func processSidechain(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, sidechainL: UnsafePointer<Float>, sidechainR: UnsafePointer<Float>, frames: Int)
}

/// Safe placeholder/utility shell for devices whose UI/automation/AI contract exists
/// before their full DSP model is implemented. It is intentionally transparent, with
/// automatable Gain and Dry/Wet so drops, project save/load, racks, and AI plans work.
public final class GenericUtilityEffect: AudioEffect, SampleRateAware {
    public let kind: DeviceKind
    public var bypassed = false
    public var gain: Double = 1.0
    public var mix: Double = 1.0
    private var sampleRate: Double = 44100
    public init(kind: DeviceKind) { self.kind = kind }
    func setSampleRate(_ sr: Double) { sampleRate = sr }
    public func reset() {}
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let g = Float(gain)
        let wet = Float(mix)
        let dry = 1 - wet
        for i in 0..<frames {
            let l = left[i]
            let r = right[i]
            left[i] = l * dry + (l * g) * wet
            right[i] = r * dry + (r * g) * wet
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("gain", "Gain", 0, 2), ParamInfo("mix", "Dry/Wet", 0, 1)]
    }
    public func setParam(_ id: String, _ v: Double) { if id == "gain" { gain = v }; if id == "mix" { mix = v } }
    public func getParam(_ id: String) -> Double { id == "gain" ? gain : (id == "mix" ? mix : 0) }
}

// MARK: - Biquad (RBJ) used per channel in EQ

struct Biquad {
    enum Kind { case peaking, lowShelf, highShelf, lowpass, highpass }
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var z1 = 0.0, z2 = 0.0
    mutating func update(kind: Kind, freq: Double, q: Double, gainDB: Double, sr: Double) {
        let A = pow(10, gainDB / 40)
        let w0 = 2 * .pi * min(max(freq, 20), sr * 0.49) / sr
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * max(q, 0.05))
        var b0n = 1.0, b1n = 0.0, b2n = 0.0, a0 = 1.0, a1n = 0.0, a2n = 0.0
        switch kind {
        case .peaking:
            b0n = 1 + alpha*A; b1n = -2*cw; b2n = 1 - alpha*A
            a0 = 1 + alpha/A;  a1n = -2*cw; a2n = 1 - alpha/A
        case .lowShelf:
            let s = 2*sqrt(A)*alpha
            b0n = A*((A+1)-(A-1)*cw+s); b1n = 2*A*((A-1)-(A+1)*cw); b2n = A*((A+1)-(A-1)*cw-s)
            a0 = (A+1)+(A-1)*cw+s; a1n = -2*((A-1)+(A+1)*cw); a2n = (A+1)+(A-1)*cw-s
        case .highShelf:
            let s = 2*sqrt(A)*alpha
            b0n = A*((A+1)+(A-1)*cw+s); b1n = -2*A*((A-1)+(A+1)*cw); b2n = A*((A+1)+(A-1)*cw-s)
            a0 = (A+1)-(A-1)*cw+s; a1n = 2*((A-1)-(A+1)*cw); a2n = (A+1)-(A-1)*cw-s
        case .lowpass:
            b0n = (1-cw)/2; b1n = 1-cw; b2n = (1-cw)/2; a0 = 1+alpha; a1n = -2*cw; a2n = 1-alpha
        case .highpass:
            b0n = (1+cw)/2; b1n = -(1+cw); b2n = (1+cw)/2; a0 = 1+alpha; a1n = -2*cw; a2n = 1-alpha
        }
        b0 = b0n/a0; b1 = b1n/a0; b2 = b2n/a0; a1 = a1n/a0; a2 = a2n/a0
    }
    @inline(__always) mutating func process(_ x: Double) -> Double {
        let y = b0*x + z1; z1 = b1*x - a1*y + z2; z2 = b2*x - a2*y; return y
    }
    mutating func reset() { z1 = 0; z2 = 0 }
}

// MARK: - Stereo Freeverb

public final class ReverbEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.reverb
    public var bypassed = false
    private var sr = 44100.0
    public var roomSize = 0.7, damp = 0.4, mix = 0.3, width = 1.0

    private let combTune = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    private let apTune   = [556, 441, 341, 225]
    private let spread = 23   // Freeverb stereo spread (samples on the right)

    private struct Line { var buf: [Float]; var idx = 0; var store: Float = 0 }
    private var combL: [Line] = [], combR: [Line] = []
    private var apL: [Line] = [], apR: [Line] = []

    public init() { setSampleRate(sr) }
    func setSampleRate(_ s: Double) {
        sr = s; let scale = sr / 44100.0
        func mk(_ tunes: [Int], _ off: Int) -> [Line] {
            tunes.map { Line(buf: [Float](repeating: 0, count: max(1, Int(Double($0 + off) * scale)))) }
        }
        combL = mk(combTune, 0); combR = mk(combTune, spread)
        apL = mk(apTune, 0);    apR = mk(apTune, spread)
    }
    public func reset() {
        func clear(_ lines: inout [Line]) { for i in lines.indices { for j in lines[i].buf.indices { lines[i].buf[j] = 0 }; lines[i].store = 0 } }
        clear(&combL); clear(&combR); clear(&apL); clear(&apR)
    }
    @inline(__always) private func comb(_ l: inout Line, _ input: Float, _ fb: Float, _ d1: Float, _ d2: Float) -> Float {
        let y = l.buf[l.idx]; l.store = y * d2 + l.store * d1
        l.buf[l.idx] = input + l.store * fb; l.idx = (l.idx + 1) % l.buf.count; return y
    }
    @inline(__always) private func allpass(_ l: inout Line, _ x: Float) -> Float {
        let b = l.buf[l.idx]; let y = -x + b; l.buf[l.idx] = x + b * 0.5
        l.idx = (l.idx + 1) % l.buf.count; return y
    }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let fb = Float(0.28 + roomSize * 0.7), d1 = Float(damp), d2 = 1 - Float(damp)
        let wet = Float(mix), dry = 1 - Float(mix)
        for n in 0..<frames {
            let inL = left[n] * 0.015, inR = right[n] * 0.015
            var oL: Float = 0, oR: Float = 0
            for i in combL.indices { oL += comb(&combL[i], inL, fb, d1, d2) }
            for i in combR.indices { oR += comb(&combR[i], inR, fb, d1, d2) }
            for i in apL.indices { oL = allpass(&apL[i], oL) }
            for i in apR.indices { oR = allpass(&apR[i], oR) }
            let wL = oL * Float(width) + oR * Float(1 - width)
            let wR = oR * Float(width) + oL * Float(1 - width)
            left[n]  = left[n]  * dry + wL * wet
            right[n] = right[n] * dry + wR * wet
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("size","Size",0,1), ParamInfo("damp","Damp",0,1),
         ParamInfo("mix","Dry/Wet",0,1), ParamInfo("width","Width",0,1)]
    }
    public func setParam(_ id: String, _ v: Double) {
        switch id { case "size": roomSize=v; case "damp": damp=v; case "mix": mix=v; case "width": width=v; default: break }
    }
    public func getParam(_ id: String) -> Double {
        switch id { case "size": return roomSize; case "damp": return damp; case "mix": return mix; case "width": return width; default: return 0 }
    }
}

// MARK: - Stereo Delay (with ping-pong)

public final class DelayEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.delay
    public var bypassed = false
    private var sr = 44100.0
    private var bufL = [Float](repeating: 0, count: 96000)
    private var bufR = [Float](repeating: 0, count: 96000)
    private var wIdx = 0
    private var lpL: Float = 0, lpR: Float = 0
    public var timeMS = 375.0, feedback = 0.4, mix = 0.3, damp = 0.3, pingPong = 0.0

    public init() {}
    func setSampleRate(_ s: Double) { sr = s; let c = Int(sr*2); bufL = .init(repeating:0,count:c); bufR = .init(repeating:0,count:c) }
    public func reset() { for i in bufL.indices { bufL[i]=0; bufR[i]=0 }; wIdx=0; lpL=0; lpR=0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let d = max(1, Int(timeMS/1000.0*sr)), cap = bufL.count
        let fb = Float(feedback), wet = Float(mix), dry = 1-Float(mix), a = Float(damp), pp = Float(pingPong)
        for n in 0..<frames {
            let r = (wIdx - d + cap) % cap
            let dL = bufL[r], dR = bufR[r]
            lpL = dL*(1-a) + lpL*a; lpR = dR*(1-a) + lpR*a
            // ping-pong crosses feedback between channels
            bufL[wIdx] = left[n]  + (lpL*(1-pp) + lpR*pp) * fb
            bufR[wIdx] = right[n] + (lpR*(1-pp) + lpL*pp) * fb
            wIdx = (wIdx + 1) % cap
            left[n]  = left[n]  * dry + dL * wet
            right[n] = right[n] * dry + dR * wet
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("time","Time",10,2000,unit:"ms"), ParamInfo("feedback","Feedback",0,0.95),
         ParamInfo("damp","Damp",0,1), ParamInfo("pingpong","Ping-Pong",0,1), ParamInfo("mix","Dry/Wet",0,1)]
    }
    public func setParam(_ id: String, _ v: Double) {
        switch id { case "time": timeMS=v; case "feedback": feedback=v; case "damp": damp=v; case "pingpong": pingPong=v; case "mix": mix=v; default: break }
    }
    public func getParam(_ id: String) -> Double {
        switch id { case "time": return timeMS; case "feedback": return feedback; case "damp": return damp; case "pingpong": return pingPong; case "mix": return mix; default: return 0 }
    }
}

// MARK: - Auto Filter (per-channel SVF, summed envelope/LFO mod)

public final class AutoFilterEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.autoFilter
    public var bypassed = false
    private var sr = 44100.0
    private var fL: SVFilter, fR: SVFilter
    private var env: Float = 0
    private var lfoPhase = 0.0
    public var baseCutoff = 800.0, resonance = 0.4, envAmount = 2500.0, lfoAmount = 0.0, lfoRateHz = 2.0

    public init() { fL = SVFilter(sampleRate: sr); fR = SVFilter(sampleRate: sr) }
    func setSampleRate(_ s: Double) { sr = s; fL = SVFilter(sampleRate: s); fR = SVFilter(sampleRate: s) }
    public func reset() { fL.reset(); fR.reset(); env = 0; lfoPhase = 0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let atk: Float = 0.01, rel: Float = 0.0005
        for n in 0..<frames {
            let rect = (abs(left[n]) + abs(right[n])) * 0.5
            env += (rect > env ? atk : rel) * (rect - env)
            lfoPhase += lfoRateHz/sr; if lfoPhase >= 1 { lfoPhase -= 1 }
            let cutoff = min(max(baseCutoff + Double(env)*envAmount + sin(2 * .pi * lfoPhase)*lfoAmount, 40), sr*0.45)
            fL.cutoff = cutoff; fR.cutoff = cutoff; fL.resonance = resonance; fR.resonance = resonance
            left[n] = fL.process(left[n]); right[n] = fR.process(right[n])
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("cutoff","Cutoff",40,12000,unit:"Hz",isLog:true), ParamInfo("resonance","Resonance",0,0.98),
         ParamInfo("env","Env Amt",0,8000,unit:"Hz"), ParamInfo("lfoAmt","LFO Amt",0,6000,unit:"Hz"),
         ParamInfo("lfoRate","LFO Rate",0.05,16,unit:"Hz")]
    }
    public func setParam(_ id: String, _ v: Double) {
        switch id { case "cutoff": baseCutoff=v; case "resonance": resonance=v; case "env": envAmount=v; case "lfoAmt": lfoAmount=v; case "lfoRate": lfoRateHz=v; default: break }
    }
    public func getParam(_ id: String) -> Double {
        switch id { case "cutoff": return baseCutoff; case "resonance": return resonance; case "env": return envAmount; case "lfoAmt": return lfoAmount; case "lfoRate": return lfoRateHz; default: return 0 }
    }
}

// MARK: - EQ Eight (per-channel biquad banks)

public final class EQEightEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.eqEight
    public var bypassed = false
    private var sr = 44100.0
    struct Band { var freq: Double; var gain: Double; var q: Double; var kind: Biquad.Kind; var enabled: Bool }
    private var bands: [Band]
    private var bqL: [Biquad], bqR: [Biquad]
    public init() {
        let d: [(Double, Biquad.Kind)] = [(60,.highpass),(120,.lowShelf),(300,.peaking),(700,.peaking),(1500,.peaking),(3500,.peaking),(8000,.highShelf),(14000,.lowpass)]
        bands = d.map { Band(freq:$0.0, gain:0, q:0.9, kind:$0.1, enabled: $0.1 != .highpass && $0.1 != .lowpass) }
        bqL = Array(repeating: Biquad(), count: 8); bqR = Array(repeating: Biquad(), count: 8)
        recompute()
    }
    func setSampleRate(_ s: Double) { sr = s; recompute() }
    public func reset() { for i in 0..<8 { bqL[i].reset(); bqR[i].reset() } }
    private func recompute() { for i in 0..<8 { let b = bands[i]; bqL[i].update(kind:b.kind,freq:b.freq,q:b.q,gainDB:b.gain,sr:sr); bqR[i].update(kind:b.kind,freq:b.freq,q:b.q,gainDB:b.gain,sr:sr) } }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        for n in 0..<frames {
            var xl = Double(left[n]), xr = Double(right[n])
            for i in 0..<8 where bands[i].enabled { xl = bqL[i].process(xl); xr = bqR[i].process(xr) }
            left[n] = Float(xl); right[n] = Float(xr)
        }
    }
    public var automatableParams: [ParamInfo] {
        var p: [ParamInfo] = []
        for i in 0..<8 {
            p.append(ParamInfo("b\(i)_gain","B\(i+1) Gain",-18,18,unit:"dB"))
            p.append(ParamInfo("b\(i)_freq","B\(i+1) Freq",30,18000,unit:"Hz",isLog:true))
            p.append(ParamInfo("b\(i)_q","B\(i+1) Q",0.1,8))
        }
        return p
    }
    public func setParam(_ id: String, _ v: Double) {
        let parts = id.split(separator: "_"); guard parts.count==2, let idx = Int(parts[0].dropFirst()), idx<8 else { return }
        switch parts[1] { case "gain": bands[idx].gain=v; bands[idx].enabled = bands[idx].enabled || abs(v)>0.01; case "freq": bands[idx].freq=v; case "q": bands[idx].q=v; default: break }
        let b = bands[idx]; bqL[idx].update(kind:b.kind,freq:b.freq,q:b.q,gainDB:b.gain,sr:sr); bqR[idx].update(kind:b.kind,freq:b.freq,q:b.q,gainDB:b.gain,sr:sr)
    }
    public func getParam(_ id: String) -> Double {
        let parts = id.split(separator:"_"); guard parts.count==2, let idx=Int(parts[0].dropFirst()), idx<8 else { return 0 }
        switch parts[1] { case "gain": return bands[idx].gain; case "freq": return bands[idx].freq; case "q": return bands[idx].q; default: return 0 }
    }
}

// MARK: - Compressor (stereo-linked detector)

public final class CompressorEffect: AudioEffect, SampleRateAware, SidechainAudioEffect {
    public let kind = DeviceKind.compressor
    public var bypassed = false
    private var sr = 44100.0
    private var envDB = -60.0
    public var thresholdDB = -18.0, ratio = 4.0, attackMS = 10.0, releaseMS = 120.0, makeupDB = 0.0, kneeDB = 6.0
    public var sidechainMix = 1.0
    public init() {}
    func setSampleRate(_ s: Double) { sr = s }
    public func reset() { envDB = -60 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let atk = exp(-1.0/(attackMS/1000.0*sr)), rel = exp(-1.0/(releaseMS/1000.0*sr)), makeup = pow(10, makeupDB/20)
        for n in 0..<frames {
            let peak = max(abs(Double(left[n])), abs(Double(right[n])))
            let levelDB = 20*log10(max(peak,1e-6))
            let coef = levelDB > envDB ? atk : rel
            envDB = levelDB + coef*(envDB - levelDB)
            var gainDB = 0.0; let over = envDB - thresholdDB
            if over > kneeDB/2 { gainDB = thresholdDB + over/ratio - envDB }
            else if over > -kneeDB/2 { let x = over + kneeDB/2; gainDB = ((1/ratio - 1)*x*x)/(2*kneeDB) }
            let g = Float(pow(10, gainDB/20) * makeup)
            left[n] *= g; right[n] *= g
        }
    }
    public func processSidechain(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, sidechainL: UnsafePointer<Float>, sidechainR: UnsafePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let atk = exp(-1.0/(attackMS/1000.0*sr)), rel = exp(-1.0/(releaseMS/1000.0*sr)), makeup = pow(10, makeupDB/20)
        for n in 0..<frames {
            let detector = max(abs(Double(sidechainL[n])), abs(Double(sidechainR[n])))
            let program = max(abs(Double(left[n])), abs(Double(right[n])))
            let peak = max(program * (1.0 - sidechainMix), detector * sidechainMix)
            let levelDB = 20*log10(max(peak,1e-6))
            let coef = levelDB > envDB ? atk : rel
            envDB = levelDB + coef*(envDB - levelDB)
            var gainDB = 0.0; let over = envDB - thresholdDB
            if over > kneeDB/2 { gainDB = thresholdDB + over/ratio - envDB }
            else if over > -kneeDB/2 { let x = over + kneeDB/2; gainDB = ((1/ratio - 1)*x*x)/(2*kneeDB) }
            let g = Float(pow(10, gainDB/20) * makeup)
            left[n] *= g; right[n] *= g
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("threshold","Threshold",-48,0,unit:"dB"), ParamInfo("ratio","Ratio",1,20),
         ParamInfo("attack","Attack",0.1,100,unit:"ms"), ParamInfo("release","Release",5,1000,unit:"ms"),
         ParamInfo("makeup","Makeup",0,24,unit:"dB"), ParamInfo("sidechainMix","SC Mix",0,1)]
    }
    public func setParam(_ id: String, _ v: Double) {
        switch id { case "threshold": thresholdDB=v; case "ratio": ratio=v; case "attack": attackMS=v; case "release": releaseMS=v; case "makeup": makeupDB=v; case "sidechainMix": sidechainMix=v; default: break }
    }
    public func getParam(_ id: String) -> Double {
        switch id { case "threshold": return thresholdDB; case "ratio": return ratio; case "attack": return attackMS; case "release": return releaseMS; case "makeup": return makeupDB; case "sidechainMix": return sidechainMix; default: return 0 }
    }
}



// MARK: - Bus Compressor (glue-style stereo mix bus compressor)

/// A dedicated glue-style bus compressor, separate from the general Dynamics Compressor.
/// It uses a stereo-linked detector, soft knee, program-dependent auto makeup, optional
/// sidechain detector input, dry/wet parallel compression, gain-reduction range limiting,
/// and a gentle output drive stage for mix-bus "glue".
public final class GlueBusCompressorEffect: AudioEffect, SampleRateAware, SidechainAudioEffect {
    public let kind = DeviceKind.glueCompressor
    public var bypassed = false

    private var sr = 44100.0
    private var envDB = -90.0
    private var lastGainDB = 0.0

    public var thresholdDB = -14.0
    public var ratio = 2.0
    public var attackMS = 10.0
    public var releaseMS = 180.0
    public var makeupDB = 0.0
    public var kneeDB = 4.0
    public var mix = 1.0
    public var rangeDB = 12.0
    public var drive = 0.10
    public var autoMakeup = 1.0
    public var sidechainMix = 1.0

    public init() {}
    func setSampleRate(_ s: Double) { sr = max(8000, s) }
    public func reset() { envDB = -90; lastGainDB = 0 }

    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        processInternal(left, right, detectorL: UnsafePointer(left), detectorR: UnsafePointer(right), frames: frames, detectorBlend: 1.0)
    }

    public func processSidechain(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, sidechainL: UnsafePointer<Float>, sidechainR: UnsafePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        processInternal(left, right, detectorL: sidechainL, detectorR: sidechainR, frames: frames, detectorBlend: sidechainMix)
    }

    private func processInternal(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, detectorL: UnsafePointer<Float>, detectorR: UnsafePointer<Float>, frames: Int, detectorBlend: Double) {
        let attack = max(0.03, attackMS) / 1000.0
        let release = max(5.0, releaseMS) / 1000.0
        let atk = exp(-1.0 / (attack * sr))
        let rel = exp(-1.0 / (release * sr))
        let wet = Float(min(max(mix, 0), 1))
        let dry = 1 - wet
        let driveAmount = max(0.0, min(drive, 1.0))
        let satIn = 1.0 + driveAmount * 2.5
        let satNorm = tanh(satIn)

        for n in 0..<frames {
            let dryL = left[n]
            let dryR = right[n]

            let programPeak = max(abs(Double(dryL)), abs(Double(dryR)))
            let scPeak = max(abs(Double(detectorL[n])), abs(Double(detectorR[n])))
            let detectorPeak = max(1.0e-9, programPeak * (1.0 - detectorBlend) + scPeak * detectorBlend)
            let levelDB = 20.0 * log10(detectorPeak)

            let coef = levelDB > envDB ? atk : rel
            envDB = levelDB + coef * (envDB - levelDB)

            let gainDB = gainReductionDB(for: envDB)
            lastGainDB = gainDB
            let autoDB = autoMakeup >= 0.5 ? min(max(-gainDB * 0.45, 0), 9.0) : 0.0
            let linearGain = pow(10.0, (gainDB + makeupDB + autoDB) / 20.0)

            var wetL = Double(dryL) * linearGain
            var wetR = Double(dryR) * linearGain
            if driveAmount > 0.001 {
                wetL = tanh(wetL * satIn) / satNorm
                wetR = tanh(wetR * satIn) / satNorm
            }

            left[n] = dryL * dry + Float(wetL) * wet
            right[n] = dryR * dry + Float(wetR) * wet
        }
    }

    private func gainReductionDB(for levelDB: Double) -> Double {
        let r = max(1.0, ratio)
        let knee = max(0.0, kneeDB)
        let over = levelDB - thresholdDB
        var gr = 0.0
        if knee > 0 {
            if over <= -knee / 2 { gr = 0.0 }
            else if over >= knee / 2 { gr = over * (1.0 / r - 1.0) }
            else {
                let x = over + knee / 2
                gr = (1.0 / r - 1.0) * x * x / (2.0 * knee)
            }
        } else if over > 0 {
            gr = over * (1.0 / r - 1.0)
        }
        return max(gr, -max(0.1, rangeDB))
    }

    public var automatableParams: [ParamInfo] {
        [
            ParamInfo("threshold", "Threshold", -48, 0, unit: "dB"),
            ParamInfo("ratio", "Ratio", 1, 10),
            ParamInfo("attack", "Attack", 0.03, 100, unit: "ms", isLog: true),
            ParamInfo("release", "Release", 20, 1200, unit: "ms", isLog: true),
            ParamInfo("makeup", "Makeup", -12, 24, unit: "dB"),
            ParamInfo("knee", "Soft Knee", 0, 18, unit: "dB"),
            ParamInfo("range", "GR Range", 1, 30, unit: "dB"),
            ParamInfo("mix", "Dry/Wet", 0, 1),
            ParamInfo("drive", "Glue Drive", 0, 1),
            ParamInfo("autoMakeup", "Auto Makeup", 0, 1),
            ParamInfo("sidechainMix", "SC Detector", 0, 1)
        ]
    }

    public func setParam(_ id: String, _ v: Double) {
        switch id {
        case "threshold": thresholdDB = v
        case "ratio": ratio = v
        case "attack": attackMS = v
        case "release": releaseMS = v
        case "makeup": makeupDB = v
        case "knee": kneeDB = v
        case "range": rangeDB = v
        case "mix": mix = v
        case "drive": drive = v
        case "autoMakeup": autoMakeup = v
        case "sidechainMix": sidechainMix = v
        default: break
        }
    }

    public func getParam(_ id: String) -> Double {
        switch id {
        case "threshold": return thresholdDB
        case "ratio": return ratio
        case "attack": return attackMS
        case "release": return releaseMS
        case "makeup": return makeupDB
        case "knee": return kneeDB
        case "range": return rangeDB
        case "mix": return mix
        case "drive": return drive
        case "autoMakeup": return autoMakeup
        case "sidechainMix": return sidechainMix
        case "gainReduction": return lastGainDB
        default: return 0
        }
    }
}


// MARK: - Tune (lightweight pitch correction; operates on the mono sum)

public final class TuneEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.tune
    public var bypassed = false
    private var sr = 44100.0
    public var amount = 0.8, mode: Double = 2
    public var keyRoot = 0
    public var scaleMask: UInt16 = 0b101011010101
    private var window = [Float](repeating: 0, count: 2048)
    private var wpos = 0, ratio = 1.0, readPos = 0.0, lwrite = 0
    private var line = [Float](repeating: 0, count: 8192)
    public init() {}
    func setSampleRate(_ s: Double) { sr = s }
    public func reset() { ratio = 1; readPos = 0; lwrite = 0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let cap = line.count
        for n in 0..<frames {
            let mono = (left[n] + right[n]) * 0.5
            window[wpos] = mono; wpos = (wpos + 1) % window.count
            if wpos == 0 { updateRatio() }
            line[lwrite] = mono
            let speed = 1.0 + (ratio - 1.0) * amount * (0.3 + 0.7 * (mode/2))
            readPos += speed; if readPos >= Double(cap) { readPos -= Double(cap) }
            let i0 = Int(readPos) % cap, i1 = (i0 + 1) % cap, frac = Float(readPos - floor(readPos))
            let out = line[i0]*(1-frac) + line[i1]*frac
            left[n] = out; right[n] = out
            lwrite = (lwrite + 1) % cap
        }
    }
    private func updateRatio() {
        let N = window.count; var bestLag = 0; var bestCorr: Float = 0
        let minLag = Int(sr/1000), maxLag = Int(sr/60); var lag = minLag
        while lag < min(maxLag, N/2) {
            var c: Float = 0; var i = 0
            while i < N - lag { c += window[i]*window[i+lag]; i += 1 }
            if c > bestCorr { bestCorr = c; bestLag = lag }; lag += 1
        }
        guard bestLag > 0, bestCorr > 0.01 else { ratio = 1; return }
        let freq = sr/Double(bestLag), midi = 69 + 12*log2(freq/440)
        let target = nearestInKey(midi), tf = 440*pow(2,(target-69)/12)
        ratio = tf/freq; if !ratio.isFinite || ratio < 0.5 || ratio > 2 { ratio = 1 }
    }
    private func nearestInKey(_ midi: Double) -> Double {
        let r = midi.rounded()
        for d in [0,1,-1,2,-2,3,-3] { let c = Int(r)+d; let pc = ((c - keyRoot)%12 + 12)%12; if scaleMask & (1 << pc) != 0 { return Double(c) } }
        return r
    }
    public var automatableParams: [ParamInfo] { [ParamInfo("amount","Amount",0,1), ParamInfo("mode","Mode",0,2)] }
    public func setParam(_ id: String, _ v: Double) { switch id { case "amount": amount=v; case "mode": mode=v; default: break } }
    public func getParam(_ id: String) -> Double { switch id { case "amount": return amount; case "mode": return mode; default: return 0 } }
}
