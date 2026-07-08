import Foundation

struct VisionSemanticProjectGraph: Codable, Sendable {
    var schemaVersion: Int = 1
    var generatedAt: Date = Date()
    var projectName: String
    var tempo: Double
    var keyName: String?
    var scaleName: String?
    var nodes: [VisionSemanticNode]
    var edges: [VisionSemanticEdge]
    var tags: [String]
}

enum VisionSemanticNodeKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case project, track, midiClip, audioClip, stepSequencer, sequencerLayer, mixer, returnBus, masterBus, plugin, backend, spatialObject, automation, agentContext, memoryEvent, memoryPreference
    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized }
    var symbol: String {
        switch self {
        case .project: return "doc.richtext"
        case .track: return "rectangle.stack"
        case .midiClip: return "pianokeys"
        case .audioClip: return "waveform"
        case .stepSequencer: return "square.grid.4x3.fill"
        case .sequencerLayer: return "circle.grid.cross"
        case .mixer: return "slider.horizontal.3"
        case .returnBus: return "arrow.triangle.branch"
        case .masterBus: return "speaker.wave.3"
        case .plugin: return "puzzlepiece.extension"
        case .backend: return "externaldrive.connected.to.line.below"
        case .spatialObject: return "cube.transparent"
        case .automation: return "point.topleft.down.curvedto.point.bottomright.up"
        case .agentContext: return "brain.head.profile"
        case .memoryEvent: return "brain.filled.head.profile"
        case .memoryPreference: return "heart.text.square"
        }
    }
}

struct VisionSemanticNode: Codable, Identifiable, Sendable, Hashable {
    var id: UUID = UUID()
    var stableKey: String
    var kind: VisionSemanticNodeKind
    var name: String
    var role: String?
    var tags: [String]
    var properties: [String: String]
}

enum VisionSemanticEdgeKind: String, Codable, Sendable { case contains, routesTo, sendsTo, controls, hostedBy, spatializes, candidateFor, remembers, prefers }

struct VisionSemanticEdge: Codable, Identifiable, Sendable, Hashable {
    var id: UUID = UUID()
    var sourceKey: String
    var targetKey: String
    var kind: VisionSemanticEdgeKind
    var label: String?
}

struct VisionSemanticGraphSummary: Sendable {
    var nodeCount: Int
    var edgeCount: Int
    var trackCount: Int
    var clipCount: Int
    var backendCount: Int
    var oneLine: String { "\(nodeCount) nodes • \(edgeCount) edges • \(trackCount) tracks • \(clipCount) clips • \(backendCount) backends" }
}

enum VisionSemanticProjectGraphBuilder {
    static func build(from project: LemmingsProject, compatibility: VisionCompatibilityLabState? = nil) -> VisionSemanticProjectGraph {
        var nodes: [VisionSemanticNode] = []
        var edges: [VisionSemanticEdge] = []
        nodes.append(.init(stableKey: "project", kind: .project, name: project.name, role: "Song Session", tags: compact([project.keyName, project.scaleName, "visionOS", "semantic-graph"]), properties: ["tempo": String(project.effectiveTempo), "beatsPerBar": "\(project.beatsPerBar)", "lengthBars": "\(project.lengthBars)"]))
        nodes.append(.init(stableKey: "mixer", kind: .mixer, name: "Mixer", role: "Routing", tags: ["mixer", "routing"], properties: [:]))
        nodes.append(.init(stableKey: "master", kind: .masterBus, name: "Master", role: "Main Output", tags: ["master", "output"], properties: ["volume": String(project.masterVolume ?? 1)]))
        edges += [.init(sourceKey: "project", targetKey: "mixer", kind: .contains, label: nil), .init(sourceKey: "mixer", targetKey: "master", kind: .contains, label: nil)]
        for bus in project.returnBuses ?? [] {
            let key = "return:\(bus.id)"
            nodes.append(.init(stableKey: key, kind: .returnBus, name: bus.name, role: bus.effectKind ?? "Return", tags: compact(["return", bus.effectKind]), properties: ["volume": String(bus.volume), "pan": String(bus.pan)]))
            edges.append(.init(sourceKey: "mixer", targetKey: key, kind: .contains, label: "return"))
            edges.append(.init(sourceKey: key, targetKey: "master", kind: .routesTo, label: "master"))
        }
        for (index, track) in project.tracks.enumerated() {
            let trackKey = "track:\(track.id.uuidString)"
            nodes.append(.init(id: track.id, stableKey: trackKey, kind: .track, name: track.name, role: role(track.name, fallback: track.kind), tags: compact([track.kind, role(track.name, fallback: track.kind)]), properties: ["index": "\(index)", "volume": String(track.volume ?? 1), "pan": String(track.pan ?? 0)]))
            edges.append(.init(sourceKey: "project", targetKey: trackKey, kind: .contains, label: "track"))
            edges.append(.init(sourceKey: trackKey, targetKey: track.outputBusId == nil || track.outputBusId == "master" ? "master" : "return:\(track.outputBusId ?? "master")", kind: .routesTo, label: track.outputBusId ?? "master"))
            for (bus, amount) in track.sends ?? [:] where amount > 0 { edges.append(.init(sourceKey: trackKey, targetKey: "return:\(bus)", kind: .sendsTo, label: String(amount))) }
            for clip in track.clips {
                let key = "midi:\(clip.id.uuidString)"
                nodes.append(.init(id: clip.id, stableKey: key, kind: .midiClip, name: clip.name, role: "MIDI Region", tags: ["midi", "clip"], properties: ["startBeat": String(clip.startBeat), "lengthBeats": String(clip.lengthBeats), "events": "\(clip.notes?.count ?? clip.midiEvents?.count ?? 0)"]))
                edges.append(.init(sourceKey: trackKey, targetKey: key, kind: .contains, label: "midi"))
            }
            for clip in track.audioClips {
                let key = "audio:\(clip.id.uuidString)"
                nodes.append(.init(id: clip.id, stableKey: key, kind: .audioClip, name: clip.name, role: role(clip.name, fallback: "Audio Sample"), tags: compact(["audio", "sample", role(clip.name, fallback: "Audio Sample")]), properties: ["startBeat": String(clip.startBeat), "lengthBeats": String(clip.lengthBeats), "sourcePath": clip.sourcePath ?? "unknown"]))
                edges.append(.init(sourceKey: trackKey, targetKey: key, kind: .contains, label: "audio"))
            }
        }
        if let sequencer = project.stepSequencer {
            nodes.append(.init(stableKey: "step-sequencer", kind: .stepSequencer, name: "Step Sequencer", role: "Pattern", tags: ["sequencer"], properties: ["steps": "\(sequencer.stepCount)", "swing": String(sequencer.swing)]))
            edges.append(.init(sourceKey: "project", targetKey: "step-sequencer", kind: .contains, label: "pattern"))
            for layer in sequencer.layers {
                let key = "sequencer-layer:\(layer.id.uuidString)"
                nodes.append(.init(id: layer.id, stableKey: key, kind: .sequencerLayer, name: layer.name, role: role(layer.name, fallback: "Drum Lane"), tags: ["drum", "sequencer"], properties: ["midiNote": "\(layer.midiNote)", "hits": "\(layer.hits.filter { $0 }.count)"]))
                edges.append(.init(sourceKey: "step-sequencer", targetKey: key, kind: .contains, label: "lane"))
            }
        }
        if let hosted = project.visionHostedAudioUnit {
            let key = "auv3:\(hosted.componentManufacturer)-\(hosted.componentType)-\(hosted.componentSubType)"
            nodes.append(.init(stableKey: key, kind: .plugin, name: hosted.name, role: hosted.kind.rawValue, tags: ["auv3", "native"], properties: ["componentType": "\(hosted.componentType)"]))
            edges.append(.init(sourceKey: "project", targetKey: key, kind: .hostedBy, label: "native AUv3"))
        }
        if let scene = project.spatialScene {
            for object in scene.objects {
                let key = "spatial:\(object.id.uuidString)"
                nodes.append(.init(id: object.id, stableKey: key, kind: .spatialObject, name: object.name, role: object.kind.rawValue, tags: ["spatial"], properties: ["x": String(object.transform.position.x), "y": String(object.transform.position.y), "z": String(object.transform.position.z)]))
                edges.append(.init(sourceKey: "project", targetKey: key, kind: .spatializes, label: object.kind.rawValue))
            }
        }
        if let memory = project.memory, memory.includeInSemanticGraph {
            nodes.append(.init(stableKey: "memory", kind: .agentContext, name: "Living Project Memory", role: "Project Memory", tags: ["memory", "ai-context"], properties: ["events": "\(memory.events.count)", "preferences": "\(memory.preferences.count)", "summary": memory.summary]))
            edges.append(.init(sourceKey: "project", targetKey: "memory", kind: .contains, label: "living memory"))
            for event in memory.events.prefix(24) {
                let key = "memory-event:\(event.id.uuidString)"
                nodes.append(.init(id: event.id, stableKey: key, kind: .memoryEvent, name: event.title, role: event.kind.rawValue, tags: ["memory"] + event.tags, properties: ["detail": event.detail, "pinned": "\(event.isPinned)", "confidence": String(format: "%.2f", event.confidence)]))
                edges.append(.init(sourceKey: "memory", targetKey: key, kind: .remembers, label: event.kind.rawValue))
                for related in event.relatedSemanticNodeIDs {
                    edges.append(.init(sourceKey: key, targetKey: "related:\(related.uuidString)", kind: .controls, label: "related object"))
                }
            }
            for preference in memory.preferences.prefix(16) {
                let key = "memory-preference:\(preference.id.uuidString)"
                nodes.append(.init(id: preference.id, stableKey: key, kind: .memoryPreference, name: preference.key, role: "Learned Preference", tags: ["memory", "preference"], properties: ["value": preference.value, "evidence": "\(preference.evidenceCount)"]))
                edges.append(.init(sourceKey: "memory", targetKey: key, kind: .prefers, label: preference.key))
            }
        }
        if let compatibility {
            for candidate in compatibility.candidates {
                let key = "compat:\(candidate.id.uuidString)"
                nodes.append(.init(id: candidate.id, stableKey: key, kind: .backend, name: candidate.displayName, role: candidate.kind.rawValue, tags: ["compatibility", candidate.preferredBackend.rawValue], properties: ["backend": candidate.preferredBackend.rawValue, "risk": candidate.requiresSideloading ? "sideload" : "safe", "path": candidate.pathHint]))
                edges.append(.init(sourceKey: "project", targetKey: key, kind: .candidateFor, label: candidate.preferredBackend.rawValue))
            }
        }
        return .init(projectName: project.name, tempo: project.effectiveTempo, keyName: project.keyName, scaleName: project.scaleName, nodes: nodes, edges: edges, tags: Array(Set(nodes.flatMap(\.tags))).sorted())
    }

    static func summary(for graph: VisionSemanticProjectGraph) -> VisionSemanticGraphSummary {
        .init(nodeCount: graph.nodes.count, edgeCount: graph.edges.count, trackCount: graph.nodes.filter { $0.kind == .track }.count, clipCount: graph.nodes.filter { $0.kind == .midiClip || $0.kind == .audioClip }.count, backendCount: graph.nodes.filter { $0.kind == .backend }.count)
    }

    private static func compact(_ values: [String?]) -> [String] { Array(Set(values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted() }
    private static func role(_ name: String, fallback: String) -> String {
        let lower = name.lowercased()
        if lower.contains("kick") { return "Kick" }
        if lower.contains("snare") { return "Snare" }
        if lower.contains("hat") { return "Hi-Hat" }
        if lower.contains("bass") { return "Bass" }
        if lower.contains("vocal") || lower.contains("vox") { return "Vocal" }
        if lower.contains("lead") { return "Lead" }
        if lower.contains("pad") { return "Pad" }
        if lower.contains("fx") { return "FX" }
        return fallback
    }
}

@MainActor
extension VisionStudioModel {
    func rebuildSemanticGraph() {
        project.semanticGraph = VisionSemanticProjectGraphBuilder.build(from: project, compatibility: compatibilityLab)
        statusMessage = "Semantic graph rebuilt: \(semanticGraphSummary().oneLine)"
    }
    func currentSemanticGraph() -> VisionSemanticProjectGraph { project.semanticGraph ?? VisionSemanticProjectGraphBuilder.build(from: project, compatibility: compatibilityLab) }
    func semanticGraphSummary() -> VisionSemanticGraphSummary { VisionSemanticProjectGraphBuilder.summary(for: currentSemanticGraph()) }
    func semanticContextPreview(maxNodes: Int = 48) -> String {
        let graph = currentSemanticGraph()
        let lines = graph.nodes.prefix(maxNodes).map { "• \($0.kind.title): \($0.name)" + ($0.role.map { " — \($0)" } ?? "") }
        return (["# Semantic Context", "Project: \(graph.projectName)", "Tempo: \(graph.tempo) BPM", "Key: \(graph.keyName ?? "?") \(graph.scaleName ?? "")", "", memoryContextForAgents(), ""] + lines).joined(separator: "\n")
    }
}
