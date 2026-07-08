import Foundation

/// Buildfix257 metadata-only scanner.
///
/// This scanner deliberately avoids dlopen/Bundle.load/Process execution. It is
/// safe to use as the first pass over .component/.vst3/.clap/.appex/.dll drops.
struct VisionPluginMetadataReport: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var displayName: String
    var pathHint: String
    var detectedKind: VisionCompatibilityCandidateKind
    var bundleIdentifier: String?
    var version: String?
    var architectures: [String]
    var importedFrameworkHints: [String]
    var desktopOnlySignals: [String]
    var notes: [String]

    var isProbablyDesktopOnly: Bool { !desktopOnlySignals.isEmpty }

    var shortSummary: String {
        let arch = architectures.isEmpty ? "unknown arch" : architectures.joined(separator: ", ")
        return "\(detectedKind.rawValue) • \(arch)"
    }
}

enum VisionPluginMetadataScanner {
    static func scan(url: URL) -> VisionPluginMetadataReport {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        let kind = detectKind(name: lower)
        let plist = readInfoPlist(near: url)
        let bundleIdentifier = plist?["CFBundleIdentifier"] as? String
        let version = (plist?["CFBundleShortVersionString"] as? String) ?? (plist?["CFBundleVersion"] as? String)
        let pathText = url.path.lowercased()

        var importedHints: [String] = []
        var desktopSignals: [String] = []
        var notes: [String] = []
        var archs: [String] = []

        if pathText.contains("appkit") || pathText.contains("nsview") { desktopSignals.append("AppKit/NSView hint in path") }
        if pathText.contains("vst3") { importedHints.append("VST3") }
        if pathText.contains("component") { importedHints.append("AudioComponent") }
        if pathText.contains("clap") { importedHints.append("CLAP") }
        if pathText.contains(".dll") { importedHints.append("PE/Windows DLL") }

        if let plist {
            let plistText = plist.map { "\($0.key)=\($0.value)" }.joined(separator: " ").lowercased()
            if plistText.contains("appkit") { desktopSignals.append("AppKit reference in Info.plist") }
            if plistText.contains("nsview") { desktopSignals.append("NSView reference in Info.plist") }
            if plistText.contains("audiounit") { importedHints.append("AudioUnit") }
            if plistText.contains("com.apple.audio-unit") { importedHints.append("AUv3 extension point") }
            if plistText.contains("com.apple.application") && kind != .auv3 { desktopSignals.append("macOS application-style bundle metadata") }
        }

        if lower.hasSuffix(".dll") || lower.contains("win") {
            archs.append("unknown-pe")
            notes.append("PE architecture parsing is staged for the next smoke-test patch; buildfix257 records this as metadata-only.")
        } else if kind == .auv3 {
            archs.append("arm64")
            notes.append("AUv3 candidate should prefer native visionOS Audio Unit discovery.")
        } else if kind == .macOSComponent || kind == .vst3Bundle || kind == .clapBundle {
            archs.append("unknown-macho")
            notes.append("Mach-O slice parsing is intentionally not executing code; wire real magic-byte parsing next.")
        }

        if kind == .macOSComponent || kind == .vst3Bundle || kind == .clapBundle {
            desktopSignals.append("Desktop plug-in bundle shape")
        }

        return .init(
            displayName: name,
            pathHint: url.path,
            detectedKind: kind,
            bundleIdentifier: bundleIdentifier,
            version: version,
            architectures: Array(Set(archs)).sorted(),
            importedFrameworkHints: Array(Set(importedHints)).sorted(),
            desktopOnlySignals: Array(Set(desktopSignals)).sorted(),
            notes: notes
        )
    }

    private static func detectKind(name lower: String) -> VisionCompatibilityCandidateKind {
        if lower.hasSuffix(".appex") || lower.contains("auv3") { return .auv3 }
        if lower.hasSuffix(".component") { return .macOSComponent }
        if lower.hasSuffix(".vst3") { return lower.contains("windows") || lower.contains("win") ? .windowsVST3 : .vst3Bundle }
        if lower.hasSuffix(".clap") { return .clapBundle }
        if lower.hasSuffix(".dll") { return .windowsDLL }
        return .unknown
    }

    private static func readInfoPlist(near url: URL) -> [String: Any]? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if url.hasDirectoryPath || ["component", "vst3", "clap", "appex"].contains(url.pathExtension.lowercased()) {
            candidates.append(url.appendingPathComponent("Contents/Info.plist"))
            candidates.append(url.appendingPathComponent("Info.plist"))
        }
        candidates.append(url.deletingLastPathComponent().appendingPathComponent("Info.plist"))

        for plistURL in candidates where fileManager.fileExists(atPath: plistURL.path) {
            if let data = try? Data(contentsOf: plistURL),
               let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
               let dict = object as? [String: Any] {
                return dict
            }
        }
        return nil
    }
}

extension VisionStudioModel {
    func scanCompatibilityMetadata(for candidate: VisionCompatibilityCandidate) {
        let report = VisionPluginMetadataScanner.scan(url: URL(fileURLWithPath: candidate.pathHint))
        compatibilityLab.metadataReports.insert(report, at: 0)
        let plan = VisionPluginBackendRegistry.dryRunPlan(for: candidate, metadata: report)
        compatibilityLab.backendPlans.insert(plan, at: 0)
        compatibilityLab.status = "Scanned metadata for \(candidate.displayName): \(report.shortSummary)."
    }

    func generateBackendPlan(for candidate: VisionCompatibilityCandidate) {
        let report = compatibilityLab.metadataReports.first { $0.pathHint == candidate.pathHint }
        let plan = VisionPluginBackendRegistry.dryRunPlan(for: candidate, metadata: report)
        compatibilityLab.backendPlans.insert(plan, at: 0)
        compatibilityLab.status = "Generated backend plan for \(candidate.displayName): \(plan.summary)."
    }
}
