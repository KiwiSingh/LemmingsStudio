import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let lemmingsProject = UTType(exportedAs: "com.magmavance.lemmingsstudio.project", conformingTo: .package)
}

struct LemmingsProject: Codable, Sendable {
    var version: Int?
    var name: String
    var tempo: Double
    var bpm: Double?
    var beatsPerBar: Int
    var lengthBars: Int
    var keyRoot: Int?
    var keyName: String?
    var scaleName: String?
    var tracks: [VisionTrack]
    var visionHostedAudioUnit: VisionHostedAudioUnitState?
    var stepSequencer: VisionStepSequencerState?
    var returnBuses: [VisionReturnBus]?
    var masterVolume: Float?
    var masterMuted: Bool?
    var spatialScene: VisionSpatialScene?
    var semanticGraph: VisionSemanticProjectGraph? = nil
    var memory: VisionProjectMemoryState? = nil
    var takeFolders: [VisionTakeFolder]? = nil
    var recordingSettings: VisionRecordingSettings? = nil
    var automationLanes: [VisionAutomationLane]? = nil
    var stockFXRack: VisionStockFXRackState? = nil

    var effectiveTempo: Double { bpm ?? tempo }
    var totalBeats: Double { Double(max(1, beatsPerBar * lengthBars)) }

    static let empty = LemmingsProject(
        version: 2,
        name: "Untitled",
        tempo: 124,
        bpm: 124,
        beatsPerBar: 4,
        lengthBars: 32,
        keyRoot: 0,
        keyName: "C",
        scaleName: "Major",
        tracks: [VisionTrack(name: "Instrument 1", kind: "Instrument", clips: [], audioClips: [])],
        visionHostedAudioUnit: nil,
        stepSequencer: VisionStepSequencerState.defaultPattern,
        returnBuses: VisionReturnBus.defaults,
        masterVolume: 1,
        masterMuted: false,
        spatialScene: VisionSpatialScene.default,
        semanticGraph: nil,
        memory: nil,
        takeFolders: [],
        recordingSettings: VisionRecordingSettings(),
        automationLanes: [],
        stockFXRack: .defaults
    )

    static func decode(_ data: Data) throws -> LemmingsProject {
        try JSONDecoder().decode(LemmingsProject.self, from: data)
    }
}

struct VisionTrack: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    /// Stable automation routing identity. Optional so older projects decode cleanly.
    var automationID: UUID? = nil
    var name: String
    var kind: String
    var clips: [VisionMIDIClip]
    var audioClips: [VisionAudioClip]
    var volume: Float?
    var pan: Float?
    var mute: Bool?
    var solo: Bool?
    var sends: [String: Float]?
    var outputBusId: String?
    /// Per-track stock insert rack. Nil decodes as the neutral/default rack for backward compatibility.
    var stockFXRack: VisionStockFXRackState? = nil

    enum CodingKeys: String, CodingKey { case automationID, name, kind, clips, audioClips, volume, pan, mute, solo, sends, outputBusId, stockFXRack }
}

struct VisionMIDIClip: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var startBeat: Double
    var lengthBeats: Double
    /// Length of the underlying MIDI pattern. When the visible clip is extended beyond
    /// this duration, playback and Arrangement preview repeat the source pattern.
    var loopLengthBeats: Double? = nil
    var notes: [VisionNote]?
    var midiEvents: [VisionMIDIEvent]?
}

struct VisionAudioClip: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var startBeat: Double
    var lengthBeats: Double
    var sourcePath: String?
    var sourceOffsetBeats: Double?
    var sourceBPM: Double? = nil
    var sourceKey: String? = nil
    var autoStretchEnabled: Bool? = nil
    var playbackRate: Double? = nil
}

struct VisionNote: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var note: Int
    var startBeat: Double
    var lengthBeats: Double
    var velocity: Int

    enum CodingKeys: String, CodingKey { case note, startBeat, lengthBeats, velocity }
}


struct VisionHostedAudioUnitState: Codable, Sendable {
    var componentType: UInt32
    var componentSubType: UInt32
    var componentManufacturer: UInt32
    var name: String
    var kind: VisionAudioUnitKind
    var stateBase64: String
}


struct VisionReturnBus: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var volume: Float
    var pan: Float
    var mute: Bool
    var solo: Bool
    var effectKind: String?
    var effectMix: Float?

    static let defaults: [VisionReturnBus] = [
        .init(id: "return-a", name: "Return A", volume: 0.85, pan: 0, mute: false, solo: false, effectKind: "Delay", effectMix: 28),
        .init(id: "return-b", name: "Return B", volume: 0.80, pan: 0, mute: false, solo: false, effectKind: "Reverb", effectMix: 32)
    ]
}


struct VisionMIDIEvent: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var beat: Double
    var kind: String
    var data1: Int
    var data2: Int

    enum CodingKeys: String, CodingKey { case beat, kind, data1, data2 }
}

struct VisionStepSequencerState: Codable, Sendable {
    var enabled: Bool
    var stepCount: Int
    var stepsPerBeat: Int
    var swing: Double
    var layers: [VisionSequencerLayer]

    static let defaultPattern = VisionStepSequencerState(
        enabled: true,
        stepCount: 16,
        stepsPerBeat: 4,
        swing: 0,
        layers: [
            .init(name: "Kick", midiNote: 36, sourcePath: nil, volume: 1, pan: 0, hits: [true,false,false,false,true,false,false,false,true,false,false,false,true,false,false,false]),
            .init(name: "Snare", midiNote: 38, sourcePath: nil, volume: 0.9, pan: 0, hits: [false,false,false,false,true,false,false,false,false,false,false,false,true,false,false,false]),
            .init(name: "Hat", midiNote: 42, sourcePath: nil, volume: 0.65, pan: 0.12, hits: [false,false,true,false,false,false,true,false,false,false,true,false,false,false,true,false]),
            .init(name: "Perc", midiNote: 46, sourcePath: nil, volume: 0.7, pan: -0.15, hits: Array(repeating: false, count: 16))
        ]
    )
}

struct VisionSequencerLayer: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var midiNote: Int
    var sourcePath: String?
    var volume: Float
    var pan: Float
    var hits: [Bool]

    enum CodingKeys: String, CodingKey { case name, midiNote, sourcePath, volume, pan, hits }
}


struct VisionTake: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var sourcePath: String
    var createdAt: Date = Date()
    var rating: Int = 0
    var notes: String = ""
}

struct VisionTakeFolder: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var trackID: UUID?
    var takes: [VisionTake]
    var selectedTakeID: UUID?
    var isComping: Bool = false
    var compRegions: [VisionCompRegion] = []
    var consolidatedCompPath: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, trackID, takes, selectedTakeID, isComping, compRegions, consolidatedCompPath
    }

    init(id: UUID = UUID(), name: String, trackID: UUID?, takes: [VisionTake], selectedTakeID: UUID?, isComping: Bool = false, compRegions: [VisionCompRegion] = [], consolidatedCompPath: String? = nil) {
        self.id = id
        self.name = name
        self.trackID = trackID
        self.takes = takes
        self.selectedTakeID = selectedTakeID
        self.isComping = isComping
        self.compRegions = compRegions
        self.consolidatedCompPath = consolidatedCompPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        trackID = try c.decodeIfPresent(UUID.self, forKey: .trackID)
        takes = try c.decodeIfPresent([VisionTake].self, forKey: .takes) ?? []
        selectedTakeID = try c.decodeIfPresent(UUID.self, forKey: .selectedTakeID)
        isComping = try c.decodeIfPresent(Bool.self, forKey: .isComping) ?? false
        compRegions = try c.decodeIfPresent([VisionCompRegion].self, forKey: .compRegions) ?? []
        consolidatedCompPath = try c.decodeIfPresent(String.self, forKey: .consolidatedCompPath)
    }
}
