import Foundation
import SwiftUI

struct ProjectDocument: Codable {
    var version: Int = 2
    var name: String
    var tempo: Double
    var bpm: Double?
    var beatsPerBar: Int
    var lengthBars: Int
    var keyRoot: Int
    var keyName: String?
    var scaleName: String
    var keySnapEnabled: Bool
    var tempoAutomationEnabled: Bool
    var tempoPoints: [TempoPointDoc]
    var tracks: [TrackDoc]
    var returnBuses: [ReturnBusDoc]?
    var sampleRate: Double?
    var bitDepth: String?
    var channelFormat: String?
    var groups: [TrackGroupDoc]?

    enum CodingKeys: String, CodingKey {
        case version, name, tempo, bpm, beatsPerBar, lengthBars, keyRoot, keyName, scaleName, keySnapEnabled
        case tempoAutomationEnabled, tempoPoints, tracks, returnBuses, sampleRate, bitDepth, channelFormat, groups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        tempo = try c.decodeIfPresent(Double.self, forKey: .tempo) ?? 124
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm)
        beatsPerBar = try c.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4
        lengthBars = try c.decodeIfPresent(Int.self, forKey: .lengthBars) ?? 32
        keyRoot = try c.decodeIfPresent(Int.self, forKey: .keyRoot) ?? 0
        keyName = try c.decodeIfPresent(String.self, forKey: .keyName)
        scaleName = try c.decodeIfPresent(String.self, forKey: .scaleName) ?? ScaleLibrary.major.name
        keySnapEnabled = try c.decodeIfPresent(Bool.self, forKey: .keySnapEnabled) ?? true
        tempoAutomationEnabled = try c.decodeIfPresent(Bool.self, forKey: .tempoAutomationEnabled) ?? false
        tempoPoints = try c.decodeIfPresent([TempoPointDoc].self, forKey: .tempoPoints) ?? []
        tracks = try c.decodeIfPresent([TrackDoc].self, forKey: .tracks) ?? []
        returnBuses = try c.decodeIfPresent([ReturnBusDoc].self, forKey: .returnBuses)
        sampleRate = try c.decodeIfPresent(Double.self, forKey: .sampleRate)
        bitDepth = try c.decodeIfPresent(String.self, forKey: .bitDepth)
        channelFormat = try c.decodeIfPresent(String.self, forKey: .channelFormat)
        groups = try c.decodeIfPresent([TrackGroupDoc].self, forKey: .groups)
    }

    init(project: Project) {
        name = project.name
        tempo = project.tempo
        bpm = project.tempo
        beatsPerBar = project.beatsPerBar
        lengthBars = project.lengthBars
        keyRoot = project.keyRoot
        keyName = project.key.displayName
        scaleName = project.scale.name
        keySnapEnabled = project.keySnapEnabled
        tempoAutomationEnabled = project.tempoAutomationEnabled
        tempoPoints = project.tempoPoints.map(TempoPointDoc.init)
        tracks = project.tracks.enumerated().map { TrackDoc(track: $0.element, index: $0.offset) }
        returnBuses = project.returnBuses.map(ReturnBusDoc.init)
        sampleRate = project.sampleRate
        bitDepth = project.bitDepth.rawValue
        channelFormat = project.channelFormat.rawValue
        groups = project.groups.map(TrackGroupDoc.init)
    }

    func encoded() throws -> Data {
        try JSONEncoder.pretty.encode(self)
    }

    static func decode(_ data: Data) throws -> ProjectDocument {
        try JSONDecoder().decode(ProjectDocument.self, from: data)
    }

    func makeProject() -> Project {
        let project = Project()
        project.name = name
        project.tempo = bpm ?? tempo
        project.beatsPerBar = beatsPerBar
        project.lengthBars = lengthBars
        project.keyRoot = PitchClass(keyRoot)
        project.scale = ScaleLibrary.all.first { $0.name == scaleName } ?? ScaleLibrary.major
        project.keySnapEnabled = keySnapEnabled
        project.tempoAutomationEnabled = tempoAutomationEnabled
        project.tempoPoints = tempoPoints.map { $0.make() }
        project.tracks = tracks.enumerated().map { $0.element.make(index: $0.offset) }
        if let returnBuses { project.returnBuses = returnBuses.map { $0.make() } }
        if let sampleRate { project.sampleRate = sampleRate }
        if let bitDepth { project.bitDepth = ProjectBitDepth(rawValue: bitDepth) ?? .float32 }
        if let channelFormat { project.channelFormat = ProjectChannelFormat(rawValue: channelFormat) ?? .stereo }
        if let groups { project.groups = groups.map { $0.make() } }
        return project
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

struct TempoPointDoc: Codable {
    var beat: Double
    var bpm: Double
    init(_ p: TempoPoint) { beat = p.beat; bpm = p.bpm }
    func make() -> TempoPoint { TempoPoint(beat: beat, bpm: bpm) }
}

struct TrackDoc: Codable {
    var name: String
    var kind: String
    var colorIndex: Int
    var clips: [ClipDoc]
    var audioClips: [AudioClipDoc]
    var devices: [DeviceDoc]
    var automationLanes: [AutomationLaneDoc]?
    var externalPluginSlots: [ExternalPluginSlotDoc]
    var pluginTargetID: String?
    var sequencerLayers: [SequencerLayerDoc]?
    var armed: Bool
    var inputMonitor: Bool
    var audioInputMonitorMode: String?
    var audioInputDeviceUID: String?
    var audioInputDeviceName: String?
    var audioInputChannelIndex: Int?
    var useStepSequencer: Bool
    var volume: Float
    var pan: Float
    var mute: Bool
    var solo: Bool
    var sends: [SendDoc]?
    var outputBusName: String?
    var outputMode: String?
    var outputChannelIndex: Int?
    var panMode: String?
    var stereoWidth: Float?
    var loopDragEnabled: Bool?
    var sequencerPrintSourceTrackID: UUID?
    var sequencerPrintTargetTrackID: UUID?

    init(track: Track, index: Int) {
        name = track.name
        kind = track.kind.rawValue
        colorIndex = index
        clips = track.clips.map(ClipDoc.init)
        audioClips = track.audioClips.map(AudioClipDoc.init)
        devices = track.devices.map(DeviceDoc.init)
        automationLanes = track.automationLanes.map(AutomationLaneDoc.init)
        externalPluginSlots = track.externalPluginSlots.map(ExternalPluginSlotDoc.init)
        pluginTargetID = track.pluginTargetID
        sequencerLayers = track.sequencerLayers.map(SequencerLayerDoc.init)
        armed = track.armed
        inputMonitor = track.inputMonitor
        audioInputMonitorMode = track.audioInputMonitorMode.rawValue
        audioInputDeviceUID = track.audioInputDeviceUID
        audioInputDeviceName = track.audioInputDeviceName
        audioInputChannelIndex = track.audioInputChannelIndex
        useStepSequencer = track.useStepSequencer
        volume = track.volume
        pan = track.pan
        mute = track.mute
        solo = track.solo
        sends = track.sends.map(SendDoc.init)
        outputBusName = track.outputBusName
        outputMode = track.outputMode.rawValue
        outputChannelIndex = track.outputChannelIndex
        panMode = track.panMode.rawValue
        stereoWidth = track.stereoWidth
        loopDragEnabled = track.loopDragEnabled
        sequencerPrintSourceTrackID = track.sequencerPrintSourceTrackID
        sequencerPrintTargetTrackID = track.sequencerPrintTargetTrackID
    }

    func make(index: Int) -> Track {
        let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .yellow]
        let track = Track(name: name, kind: InstrumentKind(rawValue: kind) ?? .analog, color: palette[(colorIndex >= 0 ? colorIndex : index) % palette.count])
        track.clips = clips.map { $0.make(color: track.color) }
        track.audioClips = audioClips.map { $0.make() }
        track.devices = devices.map { $0.make() }
        track.automationLanes = automationLanes?.map { $0.make() } ?? []
        track.externalPluginSlots = externalPluginSlots.map { $0.make() }
        track.pluginTargetID = pluginTargetID
        if let sequencerLayers { track.sequencerLayers = sequencerLayers.map { $0.make() } }
        track.armed = armed
        track.inputMonitor = inputMonitor
        track.audioInputMonitorMode = AudioInputMonitorMode(rawValue: audioInputMonitorMode ?? (inputMonitor ? "Auto" : "Off")) ?? (inputMonitor ? .auto : .off)
        track.audioInputDeviceUID = audioInputDeviceUID
        track.audioInputDeviceName = audioInputDeviceName ?? (audioInputDeviceUID == nil ? "System Default" : "Saved Input")
        track.audioInputChannelIndex = audioInputChannelIndex ?? 0
        track.useStepSequencer = useStepSequencer
        track.volume = volume
        track.pan = pan
        track.mute = mute
        track.solo = solo
        track.sends = sends?.map { $0.make() } ?? []
        track.outputBusName = outputBusName ?? "Master"
        track.outputMode = TrackOutputMode(rawValue: outputMode ?? "") ?? .master
        track.outputChannelIndex = outputChannelIndex ?? 1
        track.panMode = PanMode(rawValue: panMode ?? "") ?? .stereoBalance
        track.stereoWidth = stereoWidth ?? 1
        track.loopDragEnabled = loopDragEnabled ?? true
        track.sequencerPrintSourceTrackID = sequencerPrintSourceTrackID
        track.sequencerPrintTargetTrackID = sequencerPrintTargetTrackID
        return track
    }
}

struct SequencerLayerDoc: Codable {
    var name: String
    var source: String
    var note: Int
    var steps: [Bool]
    var velocity: Float
    var samplePath: String?
    var pluginTargetID: String?
    var octaveOffset: Int?
    var pan: Float?
    var volume: Float?

    init(_ layer: SequencerLayer) {
        name = layer.name
        source = layer.source.rawValue
        note = layer.note
        steps = layer.steps
        velocity = layer.velocity
        samplePath = layer.samplePath
        pluginTargetID = layer.pluginTargetID
        octaveOffset = layer.octaveOffset
        pan = layer.pan
        volume = layer.volume
    }

    func make() -> SequencerLayer {
        var layer = SequencerLayer(name: name,
                                   source: SequencerLayerSource(rawValue: source) ?? .builtIn,
                                   note: note,
                                   stepCount: max(steps.count, 16),
                                   velocity: velocity,
                                   samplePath: samplePath,
                                   pluginTargetID: pluginTargetID,
                                   octaveOffset: octaveOffset ?? 0,
                                   pan: pan ?? 0,
                                   volume: volume ?? 1)
        layer.steps = steps
        return layer
    }
}

struct ClipDoc: Codable {
    var name: String
    var startBeat: Double
    var lengthBeats: Double
    var notes: [ClipNoteDoc]
    var isActive: Bool?
    var loopEnabled: Bool?
    var loopLengthBeats: Double?
    init(_ clip: Clip) {
        name = clip.name
        startBeat = clip.startBeat
        lengthBeats = clip.lengthBeats
        notes = clip.notes.map(ClipNoteDoc.init)
        isActive = clip.isActive
        loopEnabled = clip.loopEnabled
        loopLengthBeats = clip.loopLengthBeats
    }
    func make(color: Color) -> Clip {
        let c = Clip(name: name, startBeat: startBeat, lengthBeats: lengthBeats, notes: notes.map { $0.make() }, color: color)
        c.isActive = isActive ?? true
        c.loopEnabled = loopEnabled ?? true
        c.loopLengthBeats = loopLengthBeats ?? lengthBeats
        return c
    }
}

struct ClipNoteDoc: Codable {
    var pitch: Int
    var start: Double
    var length: Double
    var velocity: Float
    init(_ n: ClipNote) { pitch = n.pitch; start = n.start; length = n.length; velocity = n.velocity }
    func make() -> ClipNote { ClipNote(pitch: pitch, start: start, length: length, velocity: velocity) }
}

struct AudioClipDoc: Codable {
    var startBeat: Double
    var samples: [Float]
    var sampleRate: Double
    var devices: [DeviceDoc]
    var externalPluginSlots: [ExternalPluginSlotDoc]
    var warpEnabled: Bool
    var warpMode: String?
    var originalTempo: Double
    var manualTempoOverride: Bool?
    var displayName: String?
    var sourceURL: String?
    var isActive: Bool?
    var lengthBeatsOverride: Double?
    var trimStartBeats: Double?
    var loopEnabled: Bool?
    var loopLengthBeats: Double?
    var gainDB: Double?
    var pitchSemitones: Int?
    var pitchCents: Double?

    init(_ clip: AudioClip) {
        startBeat = clip.startBeat
        samples = clip.samples
        sampleRate = clip.sampleRate
        devices = clip.devices.map(DeviceDoc.init)
        externalPluginSlots = clip.externalPluginSlots.map(ExternalPluginSlotDoc.init)
        warpEnabled = clip.warpEnabled
        warpMode = clip.warpMode.rawValue
        originalTempo = clip.originalTempo
        manualTempoOverride = clip.manualTempoOverride
        displayName = clip.displayName
        sourceURL = clip.sourceURL
        isActive = clip.isActive
        lengthBeatsOverride = clip.lengthBeatsOverride
        trimStartBeats = clip.trimStartBeats
        loopEnabled = clip.loopEnabled
        loopLengthBeats = clip.loopLengthBeats
        gainDB = clip.gainDB
        pitchSemitones = clip.pitchSemitones
        pitchCents = clip.pitchCents
    }
    func make() -> AudioClip {
        let clip = AudioClip(startBeat: startBeat, samples: samples, sampleRate: sampleRate)
        clip.devices = devices.map { $0.make() }
        clip.externalPluginSlots = externalPluginSlots.map { $0.make() }
        clip.warpEnabled = warpEnabled
        if let warpMode, let mode = WarpMode(rawValue: warpMode) { clip.warpMode = mode }
        clip.originalTempo = originalTempo
        clip.manualTempoOverride = manualTempoOverride ?? false
        clip.displayName = displayName ?? "Audio Clip"
        clip.sourceURL = sourceURL
        clip.isActive = isActive ?? true
        clip.lengthBeatsOverride = lengthBeatsOverride
        clip.trimStartBeats = trimStartBeats ?? 0
        clip.loopEnabled = loopEnabled ?? true
        clip.loopLengthBeats = loopLengthBeats ?? clip.arrangementLengthBeats(projectTempo: originalTempo)
        clip.gainDB = gainDB ?? 0
        clip.pitchSemitones = pitchSemitones ?? 0
        clip.pitchCents = pitchCents ?? 0
        return clip
    }
}

struct DeviceDoc: Codable {
    var kind: String
    var bypassed: Bool
    var mono: Bool
    var params: [String: Double]
    var sidechainEnabled: Bool?
    var sidechainInputTrackID: UUID?
    init(_ device: DeviceModel) {
        kind = device.kind.rawValue
        bypassed = device.bypassed
        mono = device.mono
        params = device.params
        sidechainEnabled = device.sidechainEnabled
        sidechainInputTrackID = device.sidechainInputTrackID
    }
    func make() -> DeviceModel {
        let d = DeviceModel(kind: DeviceKind(rawValue: kind) ?? .reverb, params: params)
        d.bypassed = bypassed
        d.mono = mono
        d.sidechainEnabled = sidechainEnabled ?? false
        d.sidechainInputTrackID = sidechainInputTrackID
        return d
    }
}

struct ExternalPluginSlotDoc: Codable {
    var pluginID: String
    var name: String
    var format: String
    var role: String
    var path: String?
    var hosted: Bool
    init(_ slot: ExternalPluginSlot) {
        pluginID = slot.pluginID
        name = slot.name
        format = slot.format.rawValue
        role = slot.role.rawValue
        path = slot.path
        hosted = slot.hosted
    }
    func make() -> ExternalPluginSlot {
        let plugin = DiscoveredPlugin(
            id: pluginID,
            name: name,
            manufacturer: "",
            isKnownSynth: role == PluginRole.instrument.rawValue,
            format: PluginFormat(rawValue: format) ?? .audioUnit,
            role: PluginRole(rawValue: role) ?? .unknown,
            path: path
        )
        return ExternalPluginSlot(plugin: plugin, hosted: hosted)
    }
}


struct SendDoc: Codable {
    var returnBusID: UUID
    var amount: Float
    var preFader: Bool
    init(_ send: SendSlot) { returnBusID = send.returnBusID; amount = send.amount; preFader = send.preFader }
    func make() -> SendSlot { SendSlot(returnBusID: returnBusID, amount: amount, preFader: preFader) }
}

struct ReturnBusDoc: Codable {
    var id: UUID
    var name: String
    var devices: [DeviceDoc]
    var volume: Float
    var pan: Float
    var mute: Bool
    init(_ bus: ReturnBus) { id = bus.id; name = bus.name; devices = bus.devices.map(DeviceDoc.init); volume = bus.volume; pan = bus.pan; mute = bus.mute }
    func make() -> ReturnBus {
        let bus = ReturnBus(id: id, name: name, devices: devices.map { $0.make() }, volume: volume, pan: pan, mute: mute)
        return bus
    }
}


struct AutomationPointDoc: Codable {
    var beat: Double
    var value: Double
    init(_ p: AutomationPoint) { beat = p.beat; value = p.value }
    func make() -> AutomationPoint { AutomationPoint(beat: beat, value: value) }
}

struct AutomationLaneDoc: Codable {
    var nodeID: String
    var paramID: String
    var points: [AutomationPointDoc]
    var enabled: Bool
    init(_ lane: AutomationLane) { nodeID = lane.nodeID; paramID = lane.paramID; points = lane.points.map(AutomationPointDoc.init); enabled = lane.enabled }
    func make() -> AutomationLane { let l = AutomationLane(nodeID: nodeID, paramID: paramID, points: points.map { $0.make() }); l.enabled = enabled; return l }
}

struct TrackGroupDoc: Codable {
    var name: String
    var trackIDs: [UUID]
    var devices: [DeviceDoc]
    var volume: Float
    var pan: Float
    var mute: Bool
    var solo: Bool
    var automationLanes: [AutomationLaneDoc]?
    init(_ group: TrackGroup) { name = group.name; trackIDs = group.trackIDs; devices = group.devices.map(DeviceDoc.init); volume = group.volume; pan = group.pan; mute = group.mute; solo = group.solo; automationLanes = group.automationLanes.map(AutomationLaneDoc.init) }
    func make() -> TrackGroup { TrackGroup(name: name, trackIDs: trackIDs, devices: devices.map { $0.make() }, volume: volume, pan: pan, mute: mute, solo: solo, automationLanes: automationLanes?.map { $0.make() } ?? []) }
}
