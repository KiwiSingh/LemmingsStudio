import Foundation
import Observation
import SwiftUI

// MARK: - Notes & clips

public struct ClipNote: Identifiable, Hashable {
    public internal(set) var id = UUID()
    public var pitch: Int        // MIDI number
    public var start: Double     // beats from clip start
    public var length: Double    // beats
    public var velocity: Float = 0.9
    public init(pitch: Int, start: Double, length: Double, velocity: Float = 0.9) {
        self.pitch = pitch; self.start = start; self.length = length; self.velocity = velocity
    }
}

@Observable public final class Clip: Identifiable {
    public internal(set) var id = UUID()
    public var name: String
    public var isActive: Bool = true
    public var startBeat: Double        // position on the arrangement timeline
    public var lengthBeats: Double
    public var loopEnabled: Bool = true
    public var loopLengthBeats: Double = 4
    public var swingAmount: Double = 0
    public var notes: [ClipNote]
    public var color: Color

    public init(name: String, startBeat: Double, lengthBeats: Double,
                notes: [ClipNote] = [], color: Color = .blue) {
        self.name = name; self.startBeat = startBeat; self.lengthBeats = lengthBeats
        self.notes = notes; self.color = color
    }
}

// MARK: - Step sequencer (FL-style)

public struct Step: Hashable, Codable {
    /// Back-compat primary flag/note. The beta sequencer now supports several
    /// row hits on the same time cell, so kick+hat+snare overlaps are legal.
    public var on: Bool = false
    public var note: Int = 60
    public var velocity: Float = 0.9
    public var hits: [Int] = []

    public var activeNotes: [Int] {
        if !hits.isEmpty { return hits }
        return on ? [note] : []
    }

    public func contains(_ midiNote: Int) -> Bool { activeNotes.contains(midiNote) }

    public mutating func set(_ midiNote: Int, enabled: Bool, velocity: Float = 0.9) {
        if enabled {
            if !hits.contains(midiNote) { hits.append(midiNote) }
            hits.sort()
        } else {
            hits.removeAll { $0 == midiNote }
        }
        on = !hits.isEmpty
        note = hits.first ?? midiNote
        self.velocity = velocity
    }

    public mutating func clear() {
        on = false
        hits.removeAll()
    }
}

@Observable public final class StepPattern {
    public var steps: [Step]
    public var stepCount: Int
    public var stepsPerBeat: Int   // 4 == sixteenth notes

    public init(stepCount: Int = 16, stepsPerBeat: Int = 4, defaultNote: Int = 60) {
        self.stepCount = stepCount
        self.stepsPerBeat = stepsPerBeat
        self.steps = (0..<stepCount).map { _ in Step(on: false, note: defaultNote, velocity: 0.9) }
    }

    public func clearAll() {
        for i in steps.indices { steps[i].clear() }
    }

    public func isOn(step index: Int, note: Int) -> Bool {
        guard steps.indices.contains(index) else { return false }
        return steps[index].contains(note)
    }

    /// FL-style lane toggle: this mutates only one lane/cell intersection.
    /// Other instruments on the same step remain untouched, and other steps
    /// in this lane remain untouched.
    public func setHit(step index: Int, note: Int, enabled: Bool, velocity: Float = 0.9) {
        guard steps.indices.contains(index) else { return }
        steps[index].set(note, enabled: enabled, velocity: velocity)
    }

    @discardableResult
    public func toggleHit(step index: Int, note: Int, velocity: Float = 0.9) -> Bool {
        let next = !isOn(step: index, note: note)
        setHit(step: index, note: note, enabled: next, velocity: velocity)
        return next
    }

    public func loadGroove(_ groove: BhangraToolkit.Groove) {
        clearAll()
        for (i, stroke) in groove.steps.enumerated() where i < steps.count {
            if let stroke = stroke {
                steps[i].set(60 + (IndianStroke.allCases.firstIndex(of: stroke) ?? 0), enabled: true)
            }
        }
    }

    public func loadDrumGroove(_ groove: [(DrumVoiceID, [Int])]) {
        clearAll()
        for (voice, row) in groove {
            for (i, on) in row.enumerated() where i < steps.count && on == 1 {
                steps[i].set(voice.midiNote, enabled: true)
            }
        }
    }

    public func notes(atStep index: Int) -> [Int] {
        guard steps.indices.contains(index) else { return [] }
        return steps[index].activeNotes
    }

    /// True when any lane/cell in the pattern is armed. The audio engine uses
    /// this as the hard source-of-truth after Clear: if the grid is empty, no
    /// live step or stale preview clip is allowed to make sound.
    public var hasAnyHits: Bool {
        steps.contains { !$0.activeNotes.isEmpty }
    }
}


// MARK: - Mixer routing: sends, returns, buses, groups

public struct SendSlot: Identifiable, Hashable, Sendable {
    public internal(set) var id = UUID()
    public var returnBusID: UUID
    public var amount: Float
    public var preFader: Bool
    public init(returnBusID: UUID, amount: Float = 0.0, preFader: Bool = false) {
        self.returnBusID = returnBusID
        self.amount = amount
        self.preFader = preFader
    }
}

@Observable public final class ReturnBus: Identifiable {
    public var id = UUID()
    public var name: String
    public var devices: [DeviceModel]
    public var volume: Float
    public var pan: Float
    public var mute: Bool
    public init(id: UUID = UUID(), name: String, devices: [DeviceModel] = [DeviceModel(kind: .reverb)], volume: Float = 0.8, pan: Float = 0, mute: Bool = false) {
        self.id = id; self.name = name; self.devices = devices; self.volume = volume; self.pan = pan; self.mute = mute
    }
}

@Observable public final class TrackGroup: Identifiable {
    public var id = UUID()
    public var name: String
    public var trackIDs: [UUID]
    public var devices: [DeviceModel]
    public var volume: Float
    public var pan: Float
    public var mute: Bool
    public var solo: Bool
    public var automationLanes: [AutomationLane]
    public init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [], devices: [DeviceModel] = [], volume: Float = 1, pan: Float = 0, mute: Bool = false, solo: Bool = false, automationLanes: [AutomationLane] = []) {
        self.id = id; self.name = name; self.trackIDs = trackIDs; self.devices = devices; self.volume = volume; self.pan = pan; self.mute = mute; self.solo = solo; self.automationLanes = automationLanes
    }

    public func lane(nodeID: String, paramID: String) -> AutomationLane {
        if let l = automationLanes.first(where: { $0.nodeID == nodeID && $0.paramID == paramID }) { return l }
        let l = AutomationLane(nodeID: nodeID, paramID: paramID)
        automationLanes.append(l)
        return l
    }
}

// MARK: - Track

public enum InstrumentKind: String, CaseIterable, Identifiable {
    case analog = "Analog Synth"
    case guitar = "Guitar"
    case drums = "Drum Machine"
    case indianPercussion = "Indian Percussion"
    case bhangraDhol = "Bhangra Dhol"
    case sequencer = "Sequencer"
    case bhangraArchitect = "Bhangra Architect"
    case guaracha2C = "2C"
    case bailaton = "Bailaton"
    case oscillatron = "Oscillatron"
    case lemmingBass = "LemmingBass"
    case dubstepWrangler = "Dubstep Wrangler"
    case audio = "Audio (Recorded)"
    public var id: String { rawValue }
    /// Tracks that produce sound from a synth/sampler/sequencer (vs. recorded audio).
    public var isInstrument: Bool { self != .audio }
    public var isStepEditable: Bool {
        switch self { case .drums, .indianPercussion, .bhangraDhol, .sequencer, .bhangraArchitect, .guaracha2C, .bailaton, .dubstepWrangler: return true; default: return false }
    }
}

public enum SequencerLayerSource: String, CaseIterable, Identifiable, Sendable {
    case splice = "Splice Sample"
    case builtIn = "Built-in Drum"
    case plugin = "Plug-in"
    case synthesized = "Synthesized"
    public var id: String { rawValue }
}

public struct SequencerLayer: Identifiable, Hashable, Sendable {
    public internal(set) var id = UUID()
    public var name: String
    public var source: SequencerLayerSource
    public var note: Int
    public var steps: [Bool]
    public var velocity: Float
    public var samplePath: String?
    public var pluginTargetID: String?
    /// Per-lane performance controls. `note` remains the lane/cell identity,
    /// while plug-in lanes can play the project root note plus this octave.
    public var octaveOffset: Int
    public var pan: Float
    public var volume: Float

    public init(name: String, source: SequencerLayerSource, note: Int, stepCount: Int = 16, velocity: Float = 0.9, samplePath: String? = nil, pluginTargetID: String? = nil, octaveOffset: Int = 0, pan: Float = 0, volume: Float = 1) {
        self.name = name
        self.source = source
        self.note = note
        self.steps = Array(repeating: false, count: stepCount)
        self.velocity = velocity
        self.samplePath = samplePath
        self.pluginTargetID = pluginTargetID
        self.octaveOffset = octaveOffset
        self.pan = pan
        self.volume = volume
    }

    public func playbackNote(project: Project) -> Int {
        if source == .plugin {
            return max(0, min(127, 60 + project.key.root + (octaveOffset * 12)))
        }

        // Drum-kit lanes use the MIDI note as a routing key into the built-in
        // DrumKit. Transposing Kick 36 by the lane octave turns it into an
        // unmapped/bass-like note and makes kits sound like every lane is a
        // synth bass. Keep built-in drum routing notes stable; octave controls
        // are meaningful for plug-in/synth lanes, not for drum voice IDs.
        if source == .builtIn, DrumVoiceID.from(midiNote: note) != nil {
            return max(0, min(127, note))
        }

        // One-shot sample lanes are also keyed by their lane note in the sample
        // layer instrument. Until real per-lane sample pitch shifting exists,
        // do not transpose the routing note or the sample layer will be missed.
        if source == .splice || samplePath != nil {
            return max(0, min(127, note))
        }

        return max(0, min(127, note + (octaveOffset * 12)))
    }

    public func playbackVelocity(baseVelocity: Float? = nil) -> Float {
        max(0, min(1, (baseVelocity ?? velocity) * volume))
    }

    /// User-facing lane name for the Step Sequencer. The sequencer uses MIDI
    /// notes internally for routing, but the UI should behave like a drum
    /// channel rack: Kick, Snare, Clap, Hat, sample/plugin name, etc.
    /// This also repairs older generated lanes named "Step 36" / "C4" by
    /// deriving a musical label from the layer source and note.
    public func displayName(project: Project? = nil) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let looksLikeRawNote = lower.hasPrefix("step ")
            || lower.range(of: #"^[a-g][#b]?[- ]?\d$"#, options: .regularExpression) != nil
            || lower.range(of: #"^midi ?\d+$"#, options: .regularExpression) != nil
            || lower.range(of: #"^note ?\d+$"#, options: .regularExpression) != nil

        if !trimmed.isEmpty && !looksLikeRawNote { return trimmed }

        switch source {
        case .plugin:
            if let pluginTargetID, !pluginTargetID.isEmpty { return pluginTargetID }
            if let project { return "Root Note · \(MIDINote(60 + project.key.root + (octaveOffset * 12)).name)" }
            return "Root Note"
        case .splice:
            if let samplePath, !samplePath.isEmpty {
                let base = URL(fileURLWithPath: samplePath).deletingPathExtension().lastPathComponent
                return base.isEmpty ? "Sample" : base
            }
            return "Sample"
        case .builtIn, .synthesized:
            if let voice = DrumVoiceID.from(midiNote: note) { return voice.label }
            return trimmed.isEmpty ? "Lane \(note)" : trimmed
        }
    }

    public static func friendlyName(for note: Int, source: SequencerLayerSource = .builtIn, project: Project? = nil) -> String {
        SequencerLayer(name: "", source: source, note: note).displayName(project: project)
    }

    public static func emptyKit() -> [SequencerLayer] {
        [
            SequencerLayer(name: "Kick", source: .builtIn, note: 36),
            SequencerLayer(name: "Snare / Clap", source: .builtIn, note: 38),
            SequencerLayer(name: "Dhol", source: .builtIn, note: 45),
            SequencerLayer(name: "Closed Hat", source: .builtIn, note: 42),
            SequencerLayer(name: "Perc", source: .splice, note: 64)
        ]
    }
}


public struct ExternalPluginSlot: Identifiable, Hashable, Sendable {
    public internal(set) var id = UUID()
    public var pluginID: String
    public var name: String
    public var format: PluginFormat
    public var role: PluginRole
    public var path: String?
    public var hosted: Bool

    /// Stable automation node id for third-party plug-ins. Do not use `id`,
    /// because that UUID is recreated when a project is loaded. Automation lanes
    /// saved in the project need a deterministic target.
    public var nodeID: String {
        let stable = pluginID.isEmpty ? name : pluginID
        return "external-plugin:" + stable.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    public init(plugin: DiscoveredPlugin, hosted: Bool) {
        self.pluginID = plugin.id
        self.name = plugin.name
        self.format = plugin.format
        self.role = plugin.role
        self.path = plugin.path
        self.hosted = hosted
    }
}


public enum AudioInputMonitorMode: String, Codable, CaseIterable, Identifiable {
    case monitorIn = "In"
    case auto = "Auto"
    case off = "Off"

    public var id: String { rawValue }

    public var shortLabel: String { rawValue }

    public var helpText: String {
        switch self {
        case .monitorIn:
            return "In: direct/hardware monitoring mode. Lemmings records input but does not route software loopback, avoiding voice echo."
        case .auto:
            return "Auto: record-armed input mode. Lemmings avoids software loopback during recording to prevent echo."
        case .off:
            return "Off: no input monitoring; recording still captures the selected input channel when armed."
        }
    }
}

@Observable public final class Track: Identifiable {
    public internal(set) var id = UUID()
    public var name: String
    public var kind: InstrumentKind
    public var clips: [Clip] = []
    public var stepPattern = StepPattern()
    public var useStepSequencer = false
    public var sequencerLayers: [SequencerLayer] = SequencerLayer.emptyKit()
    public var sequencerPrintTargetTrackID: UUID? = nil
    /// Originating Step Sequencer track for generated Arrangement print tracks.
    /// Used to silence stale prints when the same pattern is printed again.
    public var sequencerPrintSourceTrackID: UUID? = nil
    public var aiDevicePrompt: String = ""
    public var groupID: UUID? = nil
    public var outputBusName: String = "Master"
    public var outputMode: TrackOutputMode = .master
    public var outputChannelIndex: Int = 1
    public var panMode: PanMode = .stereoBalance
    public var stereoWidth: Float = 1.0
    public var sends: [SendSlot] = []
    public var loopDragEnabled: Bool = true

    // Device chain (Ableton-style insert effects) + parameter automation.
    public var devices: [DeviceModel] = []
    public var automationLanes: [AutomationLane] = []

    // Recording / live input (MIDI + audio).
    public var armed = false             // record-enabled
    public var inputMonitor = false      // legacy compatibility: true maps to Auto monitoring
    public var audioInputMonitorMode: AudioInputMonitorMode = .auto
    /// Optional CoreAudio input device UID for this audio-recording track.
    /// Empty/nil means “System Default”.
    public var audioInputDeviceUID: String? = nil
    public var audioInputDeviceName: String = "System Default"
    /// Zero-based hardware input channel used when this is an audio-recording track.
    /// The recorder still writes mono clips today, but the user can pick Input 1/2/etc.
    public var audioInputChannelIndex: Int = 0
    public var drumGenre: DrumGenre = .techHouse   // used when kind == .drums
    public var audioClips: [AudioClip] = []        // used when kind == .audio

    // Optional external instrument the sound-agent targets (Serum/Vital/AU…).
    public var pluginTargetID: String? = nil
    public var externalPluginSlots: [ExternalPluginSlot] = []

    // Freeze / bounce (CPU relief): when frozen, the engine plays `bounced`
    // (a pre-rendered stereo-summed mono capture that already includes devices).
    public var frozen = false
    public var bounced: AudioClip? = nil

    // Logic-style mixer state
    public var volume: Float = 0.8       // 0...1
    public var pan: Float = 0            // -1...1
    public var mute = false
    public var solo = false
    public var color: Color

    public init(name: String, kind: InstrumentKind, color: Color = .blue) {
        self.name = name; self.kind = kind; self.color = color
    }

    public func lane(nodeID: String, paramID: String) -> AutomationLane {
        if let l = automationLanes.first(where: { $0.nodeID == nodeID && $0.paramID == paramID }) { return l }
        let l = AutomationLane(nodeID: nodeID, paramID: paramID)
        automationLanes.append(l)
        return l
    }

    public func sequencerLayer(for note: Int) -> SequencerLayer? {
        sequencerLayers.first { $0.note == note }
    }
}

/// A recorded/bounced audio region: mono samples at the engine rate, with
/// optional Ableton-style warping to the project tempo.
/// NOTE: `@Observable` is REQUIRED here. Every other clip type is observable, and
/// without it SwiftUI is never told when `samples` / `lengthBeatsOverride` change —
/// so a finished recording keeps showing its empty 0.25-beat provisional state
/// ("twin blanks") until some *other* observed mutation (e.g. undo touching
/// track.audioClips) forces the arrangement to re-read the clip. Observability makes
/// the take's waveform and length appear the instant it's committed.
@Observable public final class AudioClip: Identifiable {
    public internal(set) var id = UUID()
    public var startBeat: Double
    public var isActive: Bool = true
    public var samples: [Float]
    public var sampleRate: Double
    public var displayName: String = "Audio Clip"
    public var sourceURL: String? = nil
    public var detectedTempo: Double? = nil
    /// True once the user has overridden the detected BPM in the clip inspector.
    public var manualTempoOverride: Bool = false
    public var loopEnabled: Bool = true
    public var loopLengthBeats: Double = 4
    /// User-edited arrangement length. Nil means use the natural audio length.
    /// This gives audio clips a DAW-style right-edge trim/extend handle without
    /// destructively slicing the sample buffer.
    public var lengthBeatsOverride: Double? = nil
    /// Non-destructive left-edge trim expressed in project beats.
    public var trimStartBeats: Double = 0
    public var swingAmount: Double = 0
    /// Clip gain in dB, independent of track/project volume. Rendered pre clip-FX.
    public var gainDB: Double = 0
    /// Coarse clip pitch offset in semitones. Combined with pitchCents at render time.
    public var pitchSemitones: Int = 0
    /// Fine clip pitch offset in cents. Combined with pitchSemitones at render time.
    public var pitchCents: Double = 0

    public var gainLinear: Float { Float(pow(10.0, gainDB / 20.0)) }
    public var pitchRatio: Double { pow(2.0, (Double(pitchSemitones) * 100.0 + pitchCents) / 1200.0) }

    // Clip-level insert effects. These are separate from track devices, so you
    // can drag FX directly onto an audio region the way you expect in a DAW.
    public var devices: [DeviceModel] = []
    public var externalPluginSlots: [ExternalPluginSlot] = []

    // Warp
    public var warpEnabled = false
    public var warpMode: WarpMode = .beat
    public var originalTempo: Double = 120        // clip's natural tempo (for beat-matching)
    public var warpedSamples: [Float]? = nil      // cached stretch to project tempo

    public init(startBeat: Double, samples: [Float], sampleRate: Double) {
        self.startBeat = startBeat; self.samples = samples; self.sampleRate = sampleRate
    }

    /// What the engine actually plays: the warped buffer if warping is on and cached.
    public var activeSamples: [Float] { (warpEnabled ? warpedSamples : nil) ?? samples }
    public var activeSampleRate: Double { sampleRate }

    public func naturalLengthBeats(projectTempo: Double) -> Double {
        let full = (Double(activeSamples.count) / activeSampleRate) * projectTempo / 60.0
        return max(0.25, full - trimStartBeats)
    }

    public func arrangementLengthBeats(projectTempo: Double) -> Double {
        max(0.25, lengthBeatsOverride ?? naturalLengthBeats(projectTempo: projectTempo))
    }
}



public enum TrackOutputMode: String, CaseIterable, Identifiable, Sendable {
    case master = "Master"
    case sendsOnly = "Sends Only"
    case bus = "Bus / Group"
    case external = "External / Multichannel"
    public var id: String { rawValue }
}

public enum PanMode: String, CaseIterable, Identifiable, Sendable {
    case stereoBalance = "Stereo Balance"
    case dualPan = "Dual Pan"
    case trueStereo = "True Stereo"
    public var id: String { rawValue }
}

public enum ProjectChannelFormat: String, CaseIterable, Identifiable, Sendable {
    case mono = "Mono"
    case stereo = "Stereo"
    case quad = "Quad"
    case fiveOne = "5.1"
    case sevenOne = "7.1"
    case custom = "Custom"
    public var id: String { rawValue }
    public var channelCount: Int {
        switch self { case .mono: return 1; case .stereo: return 2; case .quad: return 4; case .fiveOne: return 6; case .sevenOne: return 8; case .custom: return 16 }
    }
}

public enum ProjectBitDepth: String, CaseIterable, Identifiable, Sendable {
    case int16 = "16-bit PCM"
    case int24 = "24-bit PCM"
    case int32 = "32-bit PCM"
    case float32 = "32-bit Float"
    public var id: String { rawValue }
}

// MARK: - Project

@Observable public final class Project {
    // Original portable document is retained only for lossless unknown-field merging.
    public var documentSourceJSON: Data? = nil
    public var name = "Untitled"
    public var tempo: Double = 124
    public var swingAmount: Double = 0
    public var sampleRate: Double = 48000
    public var bitDepth: ProjectBitDepth = .float32
    public var channelFormat: ProjectChannelFormat = .stereo
    public var customChannelCount: Int = 16
    public var channelNames: [String] = ["L", "R", "C", "LFE", "Ls", "Rs", "Lb", "Rb"]
    public var beatsPerBar: Int = 4
    public var lengthBars: Int = 32
    public var tracks: [Track] = []
    public var returnBuses: [ReturnBus] = [ReturnBus(name: "A Reverb", devices: [DeviceModel(kind: .reverb)]), ReturnBus(name: "B Delay", devices: [DeviceModel(kind: .delay)])]
    public var groups: [TrackGroup] = []
    public var masterDevices: [DeviceModel] = [DeviceModel(kind: .limiter)]

    // Global key for snapping (the whole-song key-snap from feature #4)
    public var keyRoot: PitchClass = 0
    public var scale: Scale = ScaleLibrary.major
    public var keySnapEnabled = true

    public var key: MusicalKey { MusicalKey(root: keyRoot, scale: scale) }
    public var lengthBeats: Double { Double(lengthBars * beatsPerBar) }

    // Tempo automation (used when enabled; otherwise the constant `tempo` applies).
    public var tempoAutomationEnabled = false
    public var tempoPoints: [TempoPoint] = []

    public func snap(_ pitch: Int) -> Int {
        keySnapEnabled ? key.snap(MIDINote(pitch)).number : pitch
    }
}

// MARK: - Generative fill

/// Fills the remaining bars of a clip with a scale-constrained, motif-aware
/// continuation. Deterministic for a given seed so results are reproducible.
public struct GenerativeFill {
    public var seed: UInt64
    public init(seed: UInt64 = 0xC0FFEE) { self.seed = seed }

    public func fill(clip: Clip, project: Project, untilBeat: Double) -> [ClipNote] {
        var rng = SplitMix64(seed: seed)
        let key = project.key
        let scaleNotes = key.scale.notes(root: key.root, from: 48, to: 72)
        guard !scaleNotes.isEmpty else { return clip.notes }

        var result = clip.notes.sorted { $0.start < $1.start }
        var cursor = (result.last.map { $0.start + $0.length }) ?? 0
        // Build a small motif from existing material, else seed one.
        let motif: [Int] = result.isEmpty
            ? [0, 2, 1, 3].map { scaleNotes[min($0, scaleNotes.count - 1)].number }
            : Array(result.suffix(4).map { $0.pitch })

        var lastIndex = scaleNotes.firstIndex { $0.number == (motif.last ?? scaleNotes[0].number) }
            ?? scaleNotes.count / 2

        let durations: [Double] = [0.25, 0.5, 0.5, 1.0]
        while cursor < untilBeat {
            // On bar downbeats, lean toward chord tones (root/third/fifth of the key).
            let onDownbeat = cursor.truncatingRemainder(dividingBy: Double(project.beatsPerBar)) < 0.01
            let step: Int
            if onDownbeat {
                step = [0, 2, 4][Int(rng.next() % 3)] - 2  // bias toward stable tones
            } else {
                step = [-2, -1, 1, 2, 1, -1][Int(rng.next() % 6)]
            }
            lastIndex = max(0, min(scaleNotes.count - 1, lastIndex + step))
            let dur = durations[Int(rng.next() % UInt64(durations.count))]
            let pitch = project.snap(scaleNotes[lastIndex].number)
            result.append(ClipNote(pitch: pitch, start: cursor, length: dur,
                                   velocity: onDownbeat ? 0.95 : 0.75))
            cursor += dur
        }
        return result
    }
}

/// Tiny deterministic RNG so generative features are reproducible.
public struct SplitMix64 {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
