import Foundation

struct SemanticProjectGraph: Codable, Sendable {
    var schemaVersion: Int = 1
    var generatedAt: Date = Date()
    var projectName: String
    var tempo: Double
    var keyName: String?
    var scaleName: String
    var nodes: [SemanticProjectNode]
    var edges: [SemanticProjectEdge]
    var tags: [String]
    var summary: String { "\(nodes.count) nodes • \(edges.count) edges" }
}

enum SemanticProjectNodeKind: String, Codable, Sendable { case project, track, midiClip, audioClip, device, pluginSlot, automationLane, returnBus, masterBus, sequencerLayer, hostMode, agentContext }
struct SemanticProjectNode: Codable, Identifiable, Sendable, Hashable { var id = UUID(); var stableKey: String; var kind: SemanticProjectNodeKind; var name: String; var role: String?; var tags: [String]; var properties: [String: String] }
enum SemanticProjectEdgeKind: String, Codable, Sendable { case contains, routesTo, sendsTo, controls, hostedBy, renderedBy, generatedFrom }
struct SemanticProjectEdge: Codable, Identifiable, Sendable, Hashable { var id = UUID(); var sourceKey: String; var targetKey: String; var kind: SemanticProjectEdgeKind; var label: String? }

enum SemanticProjectGraphBuilder {
    static func build(from document: ProjectDocument) -> SemanticProjectGraph {
        var nodes: [SemanticProjectNode] = []
        var edges: [SemanticProjectEdge] = []
        nodes.append(.init(stableKey: "project", kind: .project, name: document.name, role: "Song Session", tags: compact([document.keyName, document.scaleName, "macOS", "semantic-graph"]), properties: ["tempo": String(document.bpm ?? document.tempo), "beatsPerBar": "\(document.beatsPerBar)", "lengthBars": "\(document.lengthBars)"]))
        nodes.append(.init(stableKey: "master", kind: .masterBus, name: "Master", role: "Main Output", tags: ["master", "output"], properties: [:]))
        edges.append(.init(sourceKey: "project", targetKey: "master", kind: .contains, label: "output"))
        for bus in document.returnBuses ?? [] {
            let key = "return:\(bus.id.uuidString)"
            nodes.append(.init(stableKey: key, kind: .returnBus, name: bus.name, role: "Return Bus", tags: ["return", "bus"], properties: ["volume": String(bus.volume), "pan": String(bus.pan)]))
            edges.append(.init(sourceKey: "project", targetKey: key, kind: .contains, label: "return"))
            edges.append(.init(sourceKey: key, targetKey: "master", kind: .routesTo, label: "master"))
        }
        for (trackIndex, track) in document.tracks.enumerated() {
            let trackKey = "track:\(trackIndex):\(track.name)"
            nodes.append(.init(stableKey: trackKey, kind: .track, name: track.name, role: role(track.name, fallback: track.kind), tags: compact([track.kind, role(track.name, fallback: track.kind), track.outputBusName]), properties: ["index": "\(trackIndex)", "volume": String(track.volume), "pan": String(track.pan), "output": track.outputBusName ?? "Master"] ))
            edges.append(.init(sourceKey: "project", targetKey: trackKey, kind: .contains, label: "track"))
            edges.append(.init(sourceKey: trackKey, targetKey: "master", kind: .routesTo, label: track.outputBusName ?? "Master"))
            for clip in track.clips {
                let key = "midi:\(trackIndex):\(clip.name):\(clip.startBeat)"
                nodes.append(.init(stableKey: key, kind: .midiClip, name: clip.name, role: "MIDI Region", tags: ["midi", "clip"], properties: ["startBeat": String(clip.startBeat), "lengthBeats": String(clip.lengthBeats), "notes": "\(clip.notes.count)"]))
                edges.append(.init(sourceKey: trackKey, targetKey: key, kind: .contains, label: "midi"))
            }
            for clip in track.audioClips {
                let key = "audio:\(trackIndex):\(clip.displayName ?? "Audio"):\(clip.startBeat)"
                nodes.append(.init(stableKey: key, kind: .audioClip, name: clip.displayName ?? "Audio Clip", role: role(clip.displayName ?? clip.sourceURL ?? "", fallback: "Audio Sample"), tags: ["audio", "sample"], properties: ["startBeat": String(clip.startBeat), "lengthBeats": String(clip.lengthBeatsOverride ?? 4.0), "sourceURL": clip.sourceURL ?? "unknown"]))
                edges.append(.init(sourceKey: trackKey, targetKey: key, kind: .contains, label: "audio"))
            }
            for (deviceIndex, device) in track.devices.enumerated() {
                let key = "device:\(trackIndex):\(deviceIndex):\(device.kind)"
                nodes.append(.init(stableKey: key, kind: .device, name: device.kind, role: "Stock Device", tags: ["device", device.kind], properties: ["bypassed": "\(device.bypassed)", "params": "\(device.params.count)"]))
                edges.append(.init(sourceKey: trackKey, targetKey: key, kind: .contains, label: "device"))
            }
            for (slotIndex, slot) in track.externalPluginSlots.enumerated() {
                let key = "plugin-slot:\(trackIndex):\(slotIndex):\(slot.pluginID)"
                nodes.append(.init(stableKey: key, kind: .pluginSlot, name: slot.name, role: slot.format, tags: ["plugin", slot.format, slot.role], properties: ["pluginID": slot.pluginID, "hosted": "\(slot.hosted)"]))
                edges.append(.init(sourceKey: trackKey, targetKey: key, kind: .hostedBy, label: slot.format))
            }
            for lane in track.automationLanes ?? [] {
                let key = "automation:\(trackIndex):\(lane.nodeID):\(lane.paramID)"
                nodes.append(.init(stableKey: key, kind: .automationLane, name: lane.paramID, role: "Automation", tags: ["automation"], properties: ["nodeID": lane.nodeID, "points": "\(lane.points.count)"]))
                edges.append(.init(sourceKey: trackKey, targetKey: key, kind: .controls, label: lane.paramID))
            }
            for layer in track.sequencerLayers ?? [] {
                let key = "sequencer:\(trackIndex):\(layer.name)"
                nodes.append(.init(stableKey: key, kind: .sequencerLayer, name: layer.name, role: "Step Sequencer Lane", tags: ["sequencer", "drum"], properties: ["note": "\(layer.note)", "hits": "\(layer.steps.filter { $0 }.count)"]))
                edges.append(.init(sourceKey: trackKey, targetKey: key, kind: .contains, label: "lane"))
            }
        }
        nodes.append(.init(stableKey: "host-mode", kind: .hostMode, name: "Integrated Mac Companion Host Mode", role: "Desktop Plugin Backend", tags: ["macOS", "companion", "host-mode"], properties: ["bonjour": "_lemmings-plugin._tcp", "buildfix": "260"]))
        edges.append(.init(sourceKey: "project", targetKey: "host-mode", kind: .contains, label: "backend"))
        return .init(projectName: document.name, tempo: document.bpm ?? document.tempo, keyName: document.keyName, scaleName: document.scaleName, nodes: nodes, edges: edges, tags: Array(Set(nodes.flatMap(\.tags))).sorted())
    }

    static func agentContext(from document: ProjectDocument, maxNodes: Int = 48) -> String {
        let graph = build(from: document)
        let lines = graph.nodes.prefix(maxNodes).map { "• \($0.kind.rawValue): \($0.name)" + ($0.role.map { " — \($0)" } ?? "") }
        return (["# LemmingsStudio Semantic Context", "Project: \(graph.projectName)", "Tempo: \(graph.tempo) BPM", "Key: \(graph.keyName ?? "?") \(graph.scaleName)", graph.summary, ""] + lines).joined(separator: "\n")
    }

    private static func compact(_ values: [String?]) -> [String] { Array(Set(values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted() }
    private static func role(_ name: String, fallback: String) -> String { let l = name.lowercased(); if l.contains("kick") { return "Kick" }; if l.contains("snare") { return "Snare" }; if l.contains("hat") { return "Hi-Hat" }; if l.contains("bass") { return "Bass" }; if l.contains("vocal") || l.contains("vox") { return "Vocal" }; if l.contains("lead") { return "Lead" }; if l.contains("pad") { return "Pad" }; if l.contains("fx") { return "FX" }; return fallback }
}
