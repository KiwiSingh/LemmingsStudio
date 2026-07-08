import Foundation

/// Buildfix257: shared visionOS plug-in backend seam.
///
/// This intentionally does not execute third-party plug-in code. It defines the
/// shape every backend must expose so native AUv3, Mac Companion, Wine ARM64,
/// Wine+FEX, and macOS component experiments can converge on one host surface.
protocol VisionPluginBackendAdapter: Sendable {
    var id: String { get }
    var displayName: String { get }
    var backend: VisionCompatibilityBackend { get }
    var supportsLocalExecution: Bool { get }
    var supportsEditorSurface: Bool { get }
    var supportsAudioReturn: Bool { get }
    var supportsParameterTree: Bool { get }

    func makeDryRunPlan(for candidate: VisionCompatibilityCandidate, metadata: VisionPluginMetadataReport?) -> VisionPluginBackendPlan
}

struct VisionPluginBackendPlan: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var backend: VisionCompatibilityBackend
    var candidateName: String
    var summary: String
    var commandPreview: String
    var blockedBy: [String]
    var nextStep: String
    var isExecutableToday: Bool
}

struct VisionPluginBackendCapabilities: Codable, Hashable, Sendable {
    var backend: VisionCompatibilityBackend
    var localExecution: Bool
    var editorSurface: Bool
    var audioReturn: Bool
    var parameterTree: Bool
    var notes: [String]

    static let defaults: [VisionPluginBackendCapabilities] = [
        .init(backend: .nativeAUv3, localExecution: true, editorSurface: true, audioReturn: true, parameterTree: true, notes: ["Preferred low-latency visionOS path.", "Requires a compatible AUv3 app extension."]),
        .init(backend: .macCompanion, localExecution: false, editorSurface: true, audioReturn: true, parameterTree: true, notes: ["Most reliable desktop plug-in parity path.", "Runs desktop AU/VST3/CLAP on the Mac and streams state to visionOS."]),
        .init(backend: .experimentalMacOSComponent, localExecution: false, editorSurface: false, audioReturn: false, parameterTree: false, notes: ["Metadata-only in buildfix257.", "Direct dyld loading is intentionally blocked until Mach-O/import checks pass."]),
        .init(backend: .experimentalWine, localExecution: false, editorSurface: false, audioReturn: false, parameterTree: false, notes: ["Metadata/dry-run only in buildfix257.", "First real smoke target should be Windows ARM64 plug-in shells."]),
        .init(backend: .experimentalWineFEX, localExecution: false, editorSurface: false, audioReturn: false, parameterTree: false, notes: ["Chaos path reserved.", "Needs a Darwin/visionOS FEX runtime ABI before real execution."])
    ]
}

enum VisionPluginBackendRegistry {
    static let capabilities = VisionPluginBackendCapabilities.defaults

    static func capability(for backend: VisionCompatibilityBackend) -> VisionPluginBackendCapabilities {
        capabilities.first { $0.backend == backend } ?? .init(backend: backend, localExecution: false, editorSurface: false, audioReturn: false, parameterTree: false, notes: ["No capability record registered."])
    }

    static func dryRunPlan(for candidate: VisionCompatibilityCandidate, metadata: VisionPluginMetadataReport?) -> VisionPluginBackendPlan {
        let caps = capability(for: candidate.preferredBackend)
        let blocked = blockers(for: candidate, metadata: metadata, capabilities: caps)
        let command: String
        switch candidate.preferredBackend {
        case .nativeAUv3:
            command = "AudioComponent discovery --extension \"\(candidate.displayName)\" --instantiate --connect VisionAudioEngine"
        case .macCompanion:
            command = "lemmings-companion plugin instantiate --name \"\(candidate.displayName)\" --stream editor,audio,parameters"
        case .experimentalMacOSComponent:
            command = "component-probe --bundle \"\(candidate.pathHint)\" --info-plist --macho --imports --entitlements --no-execute"
        case .experimentalWine:
            command = "wine64-arm64 vsthost-probe.exe --plugin \"\(candidate.pathHint)\" --metadata --no-audio --no-editor"
        case .experimentalWineFEX:
            command = "fex-visionos wine64 vsthost-probe.exe --plugin \"\(candidate.pathHint)\" --metadata --no-execute"
        }

        let next: String
        if blocked.isEmpty {
            next = "Promote this candidate to the first controlled smoke-test queue. Keep execution behind the sideload/dev-mode gate."
        } else {
            next = "Resolve blockers or route through Mac Companion while the local backend matures."
        }

        return .init(
            title: "Backend plan: \(candidate.displayName)",
            backend: candidate.preferredBackend,
            candidateName: candidate.displayName,
            summary: "\(candidate.kind.rawValue) → \(candidate.preferredBackend.rawValue)",
            commandPreview: command,
            blockedBy: blocked,
            nextStep: next,
            isExecutableToday: blocked.isEmpty && caps.localExecution
        )
    }

    private static func blockers(for candidate: VisionCompatibilityCandidate, metadata: VisionPluginMetadataReport?, capabilities: VisionPluginBackendCapabilities) -> [String] {
        var blockers: [String] = []
        if !capabilities.localExecution && candidate.preferredBackend != .macCompanion {
            blockers.append("Local execution disabled in buildfix257; metadata-only dry run required first.")
        }
        if candidate.requiresSideloading {
            blockers.append("Requires sideload/dev-mode runtime entitlements.")
        }
        if let metadata {
            if metadata.isProbablyDesktopOnly {
                blockers.append("Metadata suggests desktop-only assumptions: \(metadata.desktopOnlySignals.joined(separator: ", ")).")
            }
            if metadata.architectures.contains("x86_64") && candidate.preferredBackend != .macCompanion && candidate.preferredBackend != .experimentalWineFEX {
                blockers.append("x86_64 slice needs Mac Companion, Rosetta-class translation, or Wine+FEX chaos path.")
            }
            if metadata.architectures.isEmpty && candidate.kind != .auv3 {
                blockers.append("No Mach-O/PE architecture metadata detected yet.")
            }
        } else if candidate.kind != .auv3 {
            blockers.append("Run metadata scanner before backend execution.")
        }
        return blockers
    }
}
