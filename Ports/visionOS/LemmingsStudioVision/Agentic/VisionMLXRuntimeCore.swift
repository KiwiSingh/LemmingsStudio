import Foundation

enum VisionMLXRuntimeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case disabled = "Disabled"
    case localSwift = "Local MLX Swift"
    case localSidecar = "Local Sidecar"
    case macHostMode = "macOS Host Mode"
    case customEndpoint = "Custom Endpoint"
    var id: String { rawValue }
}

enum VisionMLXAgentLane: String, CaseIterable, Identifiable, Codable, Sendable {
    case arrangement = "Arrangement"
    case mixer = "Mixer"
    case plugin = "Plugin"
    case spatial = "Spatial"
    case splice = "Splice MCP"
    case compatibility = "Compatibility Lab"
    case learn = "Learn"
    var id: String { rawValue }

    var defaultToolScope: [String] {
        switch self {
        case .arrangement: return ["duplicateSelectedClip", "moveSelectedClip"]
        case .mixer: return ["setTrackVolume", "setTrackPan", "setDelayMix", "setReverbMix"]
        case .plugin: return ["setHostedPluginParameter", "capturePluginEditor"]
        case .spatial: return ["nudgeSpatialObject"]
        case .splice: return ["searchSplice"]
        case .compatibility: return ["scanCompatibilityCandidate"]
        case .learn: return ["explainProjectState"]
        }
    }
}

enum VisionMLXRunPhase: String, Codable, Sendable {
    case idle = "Idle"
    case resolving = "Resolving Model"
    case loading = "Loading Model"
    case ready = "Ready"
    case preparingContext = "Preparing Context"
    case generating = "Generating"
    case awaitingConfirmation = "Awaiting Confirmation"
    case executing = "Executing Tools"
    case cancelled = "Cancelled"
    case failed = "Failed"
}

struct VisionMLXModelInstall: Identifiable, Codable, Sendable {
    var id = UUID()
    var preset: VisionMLXModelPreset
    var repository: String
    var quantization: String
    var estimatedDiskGB: Double
    var estimatedMemoryGB: Double
    var isInstalled: Bool
    var localCachePath: String?
    var notes: String

    static let defaults: [VisionMLXModelInstall] = [
        .init(preset: .qwen25VL3B4Bit, repository: "mlx-community/Qwen2.5-VL-3B-Instruct-4bit", quantization: "4-bit", estimatedDiskGB: 3.2, estimatedMemoryGB: 5.0, isInstalled: false, notes: "Fast multimodal fallback."),
        .init(preset: .qwen25VL7B4Bit, repository: "mlx-community/Qwen2.5-VL-7B-Instruct-4bit", quantization: "4-bit", estimatedDiskGB: 6.0, estimatedMemoryGB: 9.0, isInstalled: false, notes: "Default project and plugin-editor reasoning target."),
        .init(preset: .llama32Vision11B4Bit, repository: "mlx-community/Llama-3.2-11B-Vision-Instruct-4bit", quantization: "4-bit", estimatedDiskGB: 8.5, estimatedMemoryGB: 13.0, isInstalled: false, notes: "Large alternate VLM target."),
        .init(preset: .internVL32B4Bit, repository: "mlx-community/InternVL3-2B-4bit", quantization: "4-bit", estimatedDiskGB: 1.61, estimatedMemoryGB: 3.0, isInstalled: false, notes: "Compact InternVL3 multimodal lane."),
    ]
}

struct VisionMLXRuntimeState: Codable, Sendable {
    var mode: VisionMLXRuntimeMode = .localSwift
    var selectedModel: VisionMLXModelPreset = .qwen25VL3B4Bit
    var modelInstalls: [VisionMLXModelInstall] = VisionMLXModelInstall.defaults
    var enabledLanes: Set<VisionMLXAgentLane> = [.arrangement, .mixer, .plugin, .spatial]
    var memoryBudgetGB: Double = 8
    var allowVisionScreenshots: Bool = true
    var allowProjectGraphContext: Bool = true
    var requireConfirmationForTools: Bool = true
    var autoUnloadAfterGeneration: Bool = false
    var maxOutputTokens: Int = 512
    var phase: VisionMLXRunPhase = .idle
    var activeRepository: String?
    var lastResponse: String = "No local response yet."
    var lastError: String?
    var lastDryRunSummary: String = "Runtime idle. No model loaded."
    var lastRunStartedAt: Date?
    var lastRunFinishedAt: Date?

    var readinessSummary: String {
        switch phase {
        case .ready, .awaitingConfirmation: return "Ready: \(selectedModel.rawValue)"
        case .loading, .resolving: return "\(phase.rawValue)…"
        case .failed: return "Failed"
        default:
            let install = modelInstalls.first { $0.preset == selectedModel }
            return install?.isInstalled == true ? "Cached: \(selectedModel.rawValue)" : "Not loaded"
        }
    }
}

struct VisionMLXRuntimeDryRun: Identifiable, Codable, Sendable {
    var id = UUID()
    var mode: VisionMLXRuntimeMode
    var model: VisionMLXModelPreset
    var lanes: [VisionMLXAgentLane]
    var semanticNodeCount: Int
    var toolScope: [String]
    var memoryEventCount: Int
    var memoryPreferenceCount: Int
    var summary: String
}

struct VisionMLXRuntimePlanner: Sendable {
    func makeDryRun(state: VisionMLXRuntimeState, semanticNodeCount: Int, memoryEventCount: Int = 0, memoryPreferenceCount: Int = 0) -> VisionMLXRuntimeDryRun {
        let lanes = VisionMLXAgentLane.allCases.filter { state.enabledLanes.contains($0) }
        let tools = Array(Set(lanes.flatMap(\.defaultToolScope))).sorted()
        let summary = "Prepared \(lanes.count) agent lanes, \(tools.count) allowed tools, \(semanticNodeCount) semantic nodes, \(memoryEventCount) memory events, \(memoryPreferenceCount) preferences, confirmation=\(state.requireConfirmationForTools ? "on" : "off")."
        return VisionMLXRuntimeDryRun(mode: state.mode, model: state.selectedModel, lanes: lanes, semanticNodeCount: semanticNodeCount, toolScope: tools, memoryEventCount: memoryEventCount, memoryPreferenceCount: memoryPreferenceCount, summary: summary)
    }
}

extension VisionStudioModel {
    func mlxRuntimeDryRun() {
        let snapshot = semanticGraphSummary()
        let dryRun = VisionMLXRuntimePlanner().makeDryRun(state: mlxRuntime, semanticNodeCount: snapshot.nodeCount, memoryEventCount: project.memory?.events.count ?? 0, memoryPreferenceCount: project.memory?.preferences.count ?? 0)
        mlxRuntime.lastDryRunSummary = dryRun.summary
        statusMessage = "MLX Runtime plan ready"
    }
}
