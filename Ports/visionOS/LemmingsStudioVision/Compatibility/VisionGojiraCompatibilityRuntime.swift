import Foundation
import UniformTypeIdentifiers
import Darwin

enum VisionCompatibilityBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case nativeAUv3 = "Native AUv3"
    case macCompanion = "Integrated Mac Host Mode"
    case experimentalMacOSComponent = "Experimental macOS Component"
    case experimentalWine = "Experimental Wine"
    case experimentalWineFEX = "Experimental Wine + FEX"

    var id: String { rawValue }

    var glyph: String {
        switch self {
        case .nativeAUv3: return "puzzlepiece.extension"
        case .macCompanion: return "desktopcomputer.and.arrow.down"
        case .experimentalMacOSComponent: return "atom"
        case .experimentalWine: return "wineglass"
        case .experimentalWineFEX: return "flame"
        }
    }

    var stability: String {
        switch self {
        case .nativeAUv3: return "Ship path"
        case .macCompanion: return "Ship path"
        case .experimentalMacOSComponent: return "Sideload lab"
        case .experimentalWine: return "Sideload lab"
        case .experimentalWineFEX: return "Gojira lab"
        }
    }
}

enum VisionCompatibilityCandidateKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case auv3 = "AUv3 app extension"
    case macOSComponent = "macOS .component"
    case vst3Bundle = "VST3 bundle"
    case clapBundle = "CLAP bundle"
    case windowsDLL = "Windows DLL"
    case windowsVST3 = "Windows VST3"
    case unknown = "Unknown"

    var id: String { rawValue }
}

struct VisionCompatibilityCandidate: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var displayName: String
    var pathHint: String
    var kind: VisionCompatibilityCandidateKind
    var preferredBackend: VisionCompatibilityBackend
    var notes: [String]
    var canAttemptLocalLoad: Bool
    var requiresSideloading: Bool
}

struct VisionRuntimeExperiment: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var backend: VisionCompatibilityBackend
    var commandPreview: String
    var risk: String
    var nextStep: String
}

struct VisionCompatibilityLabState: Codable, Hashable, Sendable {
    var gojiraModeEnabled = true
    var preferLocalChaos = true
    var allowUnsignedRuntimeProbes = true
    var wineRootHint = "Documents/LemmingsStudio/Runtimes/wine-visionos"
    var fexRootHint = "Documents/LemmingsStudio/Runtimes/fex-darwin"
    var macComponentRootHint = "Documents/LemmingsStudio/PlugIns/Components"
    var selectedBackend: VisionCompatibilityBackend = .experimentalMacOSComponent
    var candidates: [VisionCompatibilityCandidate] = VisionCompatibilityLabState.defaultCandidates
    var experiments: [VisionRuntimeExperiment] = VisionCompatibilityLabState.defaultExperiments
    var metadataReports: [VisionPluginMetadataReport] = []
    var binaryReports: [VisionBinaryHeaderReport] = []
    var backendPlans: [VisionPluginBackendPlan] = []
    var backendCapabilities: [VisionPluginBackendCapabilities] = VisionPluginBackendCapabilities.defaults
    var wineReports: [VisionWineBringUpReport] = []
    var status = "Gojira Compatibility Lab armed. Sideload/dev-mode only."

    static let defaultCandidates: [VisionCompatibilityCandidate] = [
        .init(displayName: "Serum 2 AU/VST3 desktop bundle", pathHint: "Drop .component or .vst3 here", kind: .vst3Bundle, preferredBackend: .macCompanion, notes: ["Desktop plugin UI likely expects AppKit or JUCE desktop windows.", "Route to Integrated Mac Host Mode until a local loader can satisfy dylib, bundle, and windowing requirements."], canAttemptLocalLoad: false, requiresSideloading: false),
        .init(displayName: "AUv3 synth/effect", pathHint: "Installed AUv3 extension", kind: .auv3, preferredBackend: .nativeAUv3, notes: ["Preferred path for visionOS parity.", "No Wine/FEX/Carla needed when the plugin ships a compatible AUv3 extension."], canAttemptLocalLoad: true, requiresSideloading: false),
        .init(displayName: "Windows ARM64 VST3", pathHint: "PlugIns/VST3/*.vst3", kind: .windowsVST3, preferredBackend: .experimentalWine, notes: ["Best first Wine target because no x86 CPU translation should be required.", "Still needs Win32, COM, filesystem, realtime audio, and editor-surface shims."], canAttemptLocalLoad: true, requiresSideloading: true),
        .init(displayName: "Windows x64 VST3/DLL", pathHint: "PlugIns/VST3 or DLL", kind: .windowsDLL, preferredBackend: .experimentalWineFEX, notes: ["Requires Wine plus a Darwin/visionOS-capable x86-64 translation layer.", "Treat FEX as a research port, not a dependency of the shipping app."], canAttemptLocalLoad: true, requiresSideloading: true)
    ]

    static let defaultExperiments: [VisionRuntimeExperiment] = [
        .init(title: "Probe macOS Audio Unit component", backend: .experimentalMacOSComponent, commandPreview: "scan-component --bundle <Plugin.component> --dump Info.plist --classify mach-o --no-execute", risk: "Low: metadata-only scan. No plugin code execution.", nextStep: "Build a Mach-O and bundle compatibility report before attempting dyld loading."),
        .init(title: "Wine ARM64 smoke test", backend: .experimentalWine, commandPreview: "wine64-arm64 vsthost-probe.exe --list --plugin <Plugin.vst3>", risk: "Medium/High: requires bundled Wine runtime and sideload entitlements; may fail on mmap/JIT restrictions.", nextStep: "Start with Windows ARM64 plugin shells before x64 translation."),
        .init(title: "Wine + FEX x64 chaos probe", backend: .experimentalWineFEX, commandPreview: "fex-visionos wine64 vsthost-probe.exe --plugin <x64Plugin.vst3>", risk: "Very High: FEX expects Linux userspace; this is effectively a Darwin backend research spike.", nextStep: "Port loader/signal/syscall assumptions behind a narrow LemmingsRuntime ABI."),
        .init(title: "Editor surface shim", backend: .experimentalWine, commandPreview: "vsthost-probe --editor offscreen --surface metal-shared-texture", risk: "High: plugin editors assume HWND/AppKit/NSView style surfaces.", nextStep: "Make the plugin UI render into a shared texture or remote stream before exposing it spatially.")
    ]
}

extension VisionStudioModel {
    func addCompatibilityCandidate(from url: URL) {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        let kind: VisionCompatibilityCandidateKind
        let backend: VisionCompatibilityBackend
        let local: Bool
        let sideload: Bool
        var notes: [String] = []

        if lower.hasSuffix(".appex") || lower.contains("auv3") {
            kind = .auv3
            backend = .nativeAUv3
            local = true
            sideload = false
            notes.append("Looks like an AUv3-style candidate. Prefer the native Audio Unit host path.")
        } else if lower.hasSuffix(".component") {
            kind = .macOSComponent
            backend = .experimentalMacOSComponent
            local = true
            sideload = true
            notes.append("macOS Audio Unit component detected. First pass should inspect metadata and Mach-O slices without executing plugin code.")
            notes.append("If it depends on AppKit, Cocoa desktop windows, or unavailable host APIs, route it to Integrated Mac Host Mode.")
        } else if lower.hasSuffix(".vst3") {
            kind = .vst3Bundle
            backend = .experimentalWine
            local = true
            sideload = true
            notes.append("VST3 bundle detected. Local load requires a VST3 host shim plus either native binary compatibility or Wine for Windows builds.")
        } else if lower.hasSuffix(".clap") {
            kind = .clapBundle
            backend = .macCompanion
            local = false
            sideload = false
            notes.append("CLAP should remain a desktop companion target until the local ABI is defined.")
        } else if lower.hasSuffix(".dll") {
            kind = .windowsDLL
            backend = .experimentalWineFEX
            local = true
            sideload = true
            notes.append("Windows DLL detected. ARM64 DLLs can try Wine first; x64 DLLs require the FEX/Darwin research path.")
        } else {
            kind = .unknown
            backend = .macCompanion
            local = false
            sideload = false
            notes.append("Unknown plugin shape. Use metadata inspection before choosing a backend.")
        }

        let candidate = VisionCompatibilityCandidate(
            displayName: name,
            pathHint: url.path,
            kind: kind,
            preferredBackend: backend,
            notes: notes,
            canAttemptLocalLoad: local,
            requiresSideloading: sideload
        )
        compatibilityLab.candidates.insert(candidate, at: 0)
        compatibilityLab.selectedBackend = backend
        compatibilityLab.status = "Classified \(name) as \(kind.rawValue) → \(backend.rawValue)."
    }

    func runCompatibilityDryRun(for candidate: VisionCompatibilityCandidate) {
        let script = compatibilityDryRunScript(for: candidate)
        compatibilityLab.status = "Dry-run only: \(candidate.displayName) would use \(candidate.preferredBackend.rawValue)."
        compatibilityLab.experiments.insert(.init(title: "Dry-run: \(candidate.displayName)", backend: candidate.preferredBackend, commandPreview: script, risk: candidate.requiresSideloading ? "Sideload/dev-mode only. Do not enable for App Store builds." : "Safe path.", nextStep: candidate.canAttemptLocalLoad ? "Run metadata scanner, then generate a backend plan before executing anything." : "Route through Integrated Mac Host Mode until local runtime support lands."), at: 0)
        generateBackendPlan(for: candidate)
    }

    func compatibilityDryRunScript(for candidate: VisionCompatibilityCandidate) -> String {
        switch candidate.preferredBackend {
        case .nativeAUv3:
            return "AudioComponent discovery → instantiate AUv3 → connect to VisionAudioEngine"
        case .macCompanion:
            return "Integrated Mac Host Mode → enumerate desktop plugins → instantiate \(candidate.displayName) → stream params/audio/editor"
        case .experimentalMacOSComponent:
            return "component-probe --bundle \"\(candidate.pathHint)\" --metadata --macho-slices --imports --no-execute"
        case .experimentalWine:
            return "WINEPREFIX=\(compatibilityLab.wineRootHint)/prefix wine64-arm64 vsthost-probe.exe --plugin \"\(candidate.pathHint)\" --metadata"
        case .experimentalWineFEX:
            return "FEX_ROOT=\(compatibilityLab.fexRootHint) WINEPREFIX=\(compatibilityLab.wineRootHint)/prefix fex-visionos wine64 vsthost-probe.exe --plugin \"\(candidate.pathHint)\" --metadata"
        }
    }
}


extension VisionStudioModel {
    /// Executes the first real local Wine ARM64 process probe when a staged runtime is present.
    /// This is intentionally opt-in and sideload-only; missing runtimes fail without mutating the project.
    func runWineARM64SmokeTest(for candidate: VisionCompatibilityCandidate) {
        guard compatibilityLab.gojiraModeEnabled,
              candidate.preferredBackend == .experimentalWine else {
            compatibilityLab.status = "Wine ARM64 probe requires Gojira mode and an Experimental Wine candidate."
            return
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let wineRoot = resolveRuntimePath(compatibilityLab.wineRootHint, documents: documents)
        let candidates = [
            wineRoot.appendingPathComponent("bin/wine64-arm64"),
            wineRoot.appendingPathComponent("bin/wine64"),
            wineRoot.appendingPathComponent("wine64-arm64")
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            compatibilityLab.status = "Wine ARM64 runtime not found. Stage an executable at \(wineRoot.path)/bin/wine64-arm64 (or wine64) and retry."
            return
        }
        guard FileManager.default.fileExists(atPath: candidate.pathHint) else {
            compatibilityLab.status = "Plugin candidate is not accessible at \(candidate.pathHint). Import or stage it inside the app container first."
            return
        }

        let prefix = wineRoot.appendingPathComponent("prefix", isDirectory: true)
        try? FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let probe = wineRoot.appendingPathComponent("vsthost-probe.exe")
        guard FileManager.default.fileExists(atPath: probe.path) else {
            compatibilityLab.status = "vsthost-probe.exe is missing from \(wineRoot.path)."
            return
        }

        let args = [executable.path, probe.path, "--plugin", candidate.pathHint, "--metadata"]
        let environment = ["WINEPREFIX=\(prefix.path)"]
        Task.detached { [args, environment] in
            let result = PosixRuntimeProbe.run(executable: executable.path, arguments: args, environmentAdditions: environment)
            await MainActor.run {
                self.compatibilityLab.status = "Wine ARM64 probe exit=\(result.exitCode). \(result.summary)"
                self.compatibilityLab.experiments.insert(.init(
                    title: "Executed Wine ARM64 probe: \(candidate.displayName)",
                    backend: .experimentalWine,
                    commandPreview: args.joined(separator: " "),
                    risk: "Sideload-only process execution. Result code \(result.exitCode).",
                    nextStep: result.exitCode == 0 ? "Inspect probe output and proceed to editor/audio host shims." : "Inspect runtime loader, mmap/JIT, dylib, and Win32 failures before retrying."
                ), at: 0)
            }
        }
    }

    private func resolveRuntimePath(_ hint: String, documents: URL) -> URL {
        if hint.hasPrefix("/") { return URL(fileURLWithPath: hint, isDirectory: true) }
        var relative = hint
        if relative.hasPrefix("Documents/") { relative.removeFirst("Documents/".count) }
        return documents.appendingPathComponent(relative, isDirectory: true)
    }
}

private enum PosixRuntimeProbe {
    struct Result: Sendable { var exitCode: Int32; var summary: String }

    static func run(executable: String, arguments: [String], environmentAdditions: [String]) -> Result {
        var pid: pid_t = 0
        let argvStorage = arguments.map { strdup($0) }
        var argv = argvStorage + [nil]
        let envStrings = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" } + environmentAdditions
        let envStorage = envStrings.map { strdup($0) }
        var envp = envStorage + [nil]
        defer {
            argvStorage.forEach { free($0) }
            envStorage.forEach { free($0) }
        }
        let spawnCode = executable.withCString { path in
            argv.withUnsafeMutableBufferPointer { argvBuffer in
                envp.withUnsafeMutableBufferPointer { envBuffer in
                    posix_spawn(&pid, path, nil, nil, argvBuffer.baseAddress, envBuffer.baseAddress)
                }
            }
        }
        guard spawnCode == 0 else { return .init(exitCode: spawnCode, summary: "posix_spawn failed with errno \(spawnCode).") }
        var status: Int32 = 0
        guard waitpid(pid, &status, 0) == pid else { return .init(exitCode: -1, summary: "waitpid failed.") }
        let signal = status & 0x7f
        let code: Int32 = signal == 0 ? ((status >> 8) & 0xff) : (128 + signal)
        return .init(exitCode: code, summary: code == 0 ? "Probe completed successfully." : "Probe terminated with a non-zero status.")
    }
}
