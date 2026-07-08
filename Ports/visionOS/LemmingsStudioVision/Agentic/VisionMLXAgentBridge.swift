import Foundation

enum VisionMLXModelPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case qwen25VL7B4Bit = "Qwen2.5-VL 7B 4-bit"
    case qwen25VL3B4Bit = "Qwen2.5-VL 3B 4-bit"
    case llama32Vision11B4Bit = "Llama 3.2 Vision 11B 4-bit"
    case internVL32B4Bit = "InternVL3 2B 4-bit"
    case custom = "Custom MLX endpoint"
    var id: String { rawValue }

    var bundledDirectoryName: String? {
        switch self {
        case .qwen25VL3B4Bit: return "qwen25-vl-3b-4bit"
        case .qwen25VL7B4Bit: return "qwen25-vl-7b-4bit"
        case .llama32Vision11B4Bit: return "llama32-vision-11b-4bit"
        case .internVL32B4Bit: return "internvl3-2b-4bit"
        case .custom: return nil
        }
    }

    var recommendedUse: String {
        switch self {
        case .qwen25VL7B4Bit:
            return "Best quality for multimodal project analysis and plugin-editor reasoning."
        case .qwen25VL3B4Bit:
            return "Balanced local vision-language reasoning with a smaller memory footprint."
        case .llama32Vision11B4Bit:
            return "Higher-capacity visual reasoning for capable Vision Pro hardware and Mac Host workflows."
        case .internVL32B4Bit:
            return "Compact multimodal option for lighter local analysis and tool planning."
        case .custom:
            return "Use a custom MLX-compatible model configuration supplied by the runtime layer."
        }
    }
}

struct VisionAgentToolPlan: Codable, Identifiable, Sendable {
    var id = UUID()
    var model: VisionMLXModelPreset
    var summary: String
    var toolCalls: [VisionAgentToolCall]
    var requiresConfirmation: Bool
}

struct VisionAgentToolCall: Codable, Identifiable, Sendable {
    var id = UUID()
    var tool: String
    var arguments: [String: String]
}

private struct VisionMLXToolEnvelope: Codable {
    var summary: String
    var toolCalls: [VisionAgentToolCall]
}

struct VisionMLXToolPlanParser: Sendable {
    func parse(response: String, model: VisionMLXModelPreset, allowedTools: Set<String>, requiresConfirmation: Bool) -> VisionAgentToolPlan {
        let candidates = jsonCandidates(in: response)
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(VisionMLXToolEnvelope.self, from: data) else { continue }
            let safeCalls = decoded.toolCalls.filter { allowedTools.contains($0.tool) }
            return VisionAgentToolPlan(model: model, summary: decoded.summary, toolCalls: safeCalls, requiresConfirmation: requiresConfirmation)
        }
        return VisionAgentToolPlan(model: model, summary: response.trimmingCharacters(in: .whitespacesAndNewlines), toolCalls: [], requiresConfirmation: requiresConfirmation)
    }

    private func jsonCandidates(in text: String) -> [String] {
        var values: [String] = []
        if let start = text.range(of: "<tool_plan>"), let end = text.range(of: "</tool_plan>", range: start.upperBound..<text.endIndex) {
            values.append(String(text[start.upperBound..<end.lowerBound]))
        }
        if let start = text.range(of: "```json"), let end = text.range(of: "```", range: start.upperBound..<text.endIndex) {
            values.append(String(text[start.upperBound..<end.lowerBound]))
        }
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last {
            values.append(String(text[first...last]))
        }
        return values
    }
}

extension VisionStudioModel {
    var allowedMLXTools: Set<String> {
        Set(mlxRuntime.enabledLanes.flatMap(\.defaultToolScope))
    }

    func executeConfirmedMLXToolPlan() {
        guard let plan = lastAgentPlan else { return }
        if selectedAgentProvider == .localMLX { mlxRuntime.phase = .executing }
        var executed = 0
        for call in plan.toolCalls where allowedMLXTools.contains(call.tool) {
            switch call.tool {
            case "duplicateSelectedClip":
                duplicateSelectedClip(); executed += 1
            case "moveSelectedClip":
                if let beat = Double(call.arguments["startBeat"] ?? "") { setSelectedClipStart(max(0, beat)); executed += 1 }
            case "setTrackVolume":
                if let index = Int(call.arguments["trackIndex"] ?? ""), let value = Float(call.arguments["value"] ?? "") { setTrackVolume(index: index, value: max(0, min(1.5, value))); executed += 1 }
            case "setTrackPan":
                if let index = Int(call.arguments["trackIndex"] ?? ""), let value = Float(call.arguments["value"] ?? "") { setTrackPan(index: index, value: max(-1, min(1, value))); executed += 1 }
            case "setDelayMix":
                if let value = Double(call.arguments["percent"] ?? "") { setDelayMix(max(0, min(100, value))); executed += 1 }
            case "setReverbMix":
                if let value = Double(call.arguments["percent"] ?? "") { setReverbMix(max(0, min(100, value))); executed += 1 }
            case "nudgeSpatialObject":
                let dx = Double(call.arguments["dx"] ?? "0") ?? 0
                let dy = Double(call.arguments["dy"] ?? "0") ?? 0
                let dz = Double(call.arguments["dz"] ?? "0") ?? 0
                nudgeSelectedSpatialObject(dx: dx, dy: dy, dz: dz); executed += 1
            case "searchSplice":
                if let query = call.arguments["query"], !query.isEmpty { spliceSearchQuery = query; runSpliceSearch(); executed += 1 }
            case "explainProjectState":
                executed += 1
            default:
                break
            }
        }
        addMemoryEvent(kind: .aiNote, title: "MLX tool plan executed", detail: "Executed \(executed) confirmed tool action(s).", tags: ["mlx", "tool-call"])
        if selectedAgentProvider == .localMLX { mlxRuntime.phase = .ready }
        agentStatus = "Executed \(executed) confirmed tool action(s)."
        statusMessage = agentStatus
        lastAgentPlan = nil
    }

    func rejectMLXToolPlan() {
        guard let plan = lastAgentPlan else { return }
        addMemoryEvent(kind: .rejection, title: "Rejected MLX tool plan", detail: plan.summary, tags: ["mlx", "rejected"])
        lastAgentPlan = nil
        if selectedAgentProvider == .localMLX { mlxRuntime.phase = .ready }
        agentStatus = "Tool plan rejected. No DAW edits applied."
    }
}
