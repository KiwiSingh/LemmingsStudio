import Foundation

// MARK: - Parameter & automation contracts
//
// The spine that ties instruments, effects, the automation engine, MIDI
// learn, and the AI assistant together: anything with tweakable parameters
// conforms to `Automatable`, exposing a stable list of `ParamInfo` plus
// get/set by string id. Automation lanes, MIDI CCs, and the assistant all
// drive nodes through this one interface.

public struct ParamInfo: Identifiable, Hashable, Sendable {
    public let id: String        // stable key, e.g. "cutoff"
    public let name: String      // display, e.g. "Cutoff"
    public let min: Double
    public let max: Double
    public let unit: String      // "Hz", "dB", "%", "s", ""
    public let isLog: Bool       // log-mapped for UI (freqs)
    public init(_ id: String, _ name: String, _ min: Double, _ max: Double,
                unit: String = "", isLog: Bool = false) {
        self.id = id; self.name = name; self.min = min; self.max = max
        self.unit = unit; self.isLog = isLog
    }
    /// Map a 0...1 UI position to a value (log-aware).
    public func denormalize(_ t: Double) -> Double {
        let c = Swift.min(Swift.max(t, 0), 1)
        if isLog, min > 0 { return min * pow(max / min, c) }
        return min + (max - min) * c
    }
    public func normalize(_ v: Double) -> Double {
        if isLog, min > 0, v > 0 { return log(v / min) / log(max / min) }
        return (v - min) / (max - min)
    }
}

public protocol Automatable: AnyObject {
    var automatableParams: [ParamInfo] { get }
    func setParam(_ id: String, _ value: Double)
    func getParam(_ id: String) -> Double
}

public enum AutomationSpecialParam {
    public static let deviceOn = "__device_on__"
    public static let midiPitchBendPrefix = "__midi_pitch_bend_ch_"

    public static func midiPitchBend(channel: Int) -> String {
        midiPitchBendPrefix + String(max(0, min(15, channel)))
    }

    public static func pitchBendChannel(from paramID: String) -> Int? {
        guard paramID.hasPrefix(midiPitchBendPrefix) else { return nil }
        return Int(paramID.dropFirst(midiPitchBendPrefix.count))
    }
}

// MARK: - Automation lane model

public struct AutomationPoint: Hashable, Sendable {
    public var beat: Double
    public var value: Double      // in the param's natural units
    public init(beat: Double, value: Double) { self.beat = beat; self.value = value }
}

/// A breakpoint envelope for one parameter on one node of one track.
@Observable public final class AutomationLane: Identifiable {
    public let id = UUID()
    public var nodeID: String     // "instrument" or a device UUID string
    public var paramID: String
    public var points: [AutomationPoint]
    public var enabled = true

    public init(nodeID: String, paramID: String, points: [AutomationPoint] = []) {
        self.nodeID = nodeID; self.paramID = paramID
        self.points = points.sorted { $0.beat < $1.beat }
    }

    public func addPoint(beat: Double, value: Double) {
        points.append(AutomationPoint(beat: beat, value: value))
        points.sort { $0.beat < $1.beat }
    }

    /// Linear-interpolated value at a beat, or nil if the lane is empty.
    public func value(atBeat beat: Double) -> Double? {
        guard let first = points.first else { return nil }
        if beat <= first.beat { return first.value }
        guard let last = points.last else { return nil }
        if beat >= last.beat { return last.value }
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            if beat >= a.beat && beat <= b.beat {
                let span = b.beat - a.beat
                let t = span > 0 ? (beat - a.beat) / span : 0
                return a.value + (b.value - a.value) * t
            }
        }
        return last.value
    }
}

// MARK: - Analog synth conformance (kept out of Instruments.swift)

extension AnalogSynth: Automatable {
    public var automatableParams: [ParamInfo] {
        [
            ParamInfo("cutoff", "Cutoff", 60, 12000, unit: "Hz", isLog: true),
            ParamInfo("resonance", "Resonance", 0, 0.98),
            ParamInfo("attack", "Attack", 0.001, 2, unit: "s"),
            ParamInfo("decay", "Decay", 0.005, 2, unit: "s"),
            ParamInfo("sustain", "Sustain", 0, 1),
            ParamInfo("release", "Release", 0.01, 3, unit: "s"),
            ParamInfo("detuneCents", "Detune", 0, 30, unit: "ct"),
            ParamInfo("osc2Mix", "Osc2 Mix", 0, 1),
            ParamInfo("gain", "Gain", 0, 1),
        ]
    }
    public func setParam(_ id: String, _ v: Double) {
        switch id {
        case "cutoff":      preset.cutoff = v
        case "resonance":   preset.resonance = v
        case "attack":      preset.attack = v
        case "decay":       preset.decay = v
        case "sustain":     preset.sustain = v
        case "release":     preset.release = v
        case "detuneCents": preset.detuneCents = v
        case "osc2Mix":     preset.osc2Mix = Float(v)
        case "gain":        preset.gain = Float(v)
        default: break
        }
    }
    public func getParam(_ id: String) -> Double {
        switch id {
        case "cutoff":      return preset.cutoff
        case "resonance":   return preset.resonance
        case "attack":      return preset.attack
        case "decay":       return preset.decay
        case "sustain":     return preset.sustain
        case "release":     return preset.release
        case "detuneCents": return preset.detuneCents
        case "osc2Mix":     return Double(preset.osc2Mix)
        case "gain":        return Double(preset.gain)
        default: return 0
        }
    }
}
