import Foundation

/// Buildfix258: metadata-only binary header parsing for plug-in candidates.
///
/// This parser reads magic bytes and load-command/import names without executing
/// third-party code. It is designed for sideload/dev-mode Compatibility Lab work:
/// inspect first, plan second, smoke-test later.
struct VisionBinaryHeaderReport: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var pathHint: String
    var containerKind: String
    var architectures: [String]
    var minimumOSHints: [String]
    var linkedLibraryHints: [String]
    var importedSymbolHints: [String]
    var warnings: [String]

    var summary: String {
        let arch = architectures.isEmpty ? "unknown" : architectures.joined(separator: ", ")
        return "\(containerKind) • \(arch)"
    }
}

enum VisionBinaryHeaderParser {
    static func parse(url: URL) -> VisionBinaryHeaderReport {
        let executableURL = locateExecutableCandidate(in: url)
        guard let data = try? Data(contentsOf: executableURL, options: [.mappedIfSafe]) else {
            return .init(pathHint: url.path, containerKind: "unreadable", architectures: [], minimumOSHints: [], linkedLibraryHints: [], importedSymbolHints: [], warnings: ["Unable to read candidate binary without security-scoped access."])
        }

        var report = parseData(data, originalURL: url, executableURL: executableURL)
        report.linkedLibraryHints = Array(Set(report.linkedLibraryHints + scanASCIIHints(data: data, patterns: ["AppKit", "AudioToolbox", "AudioUnit", "CoreAudio", "VST3", "CLAP", "UIKit", "SwiftUI", "Metal", "AVFoundation", "Foundation"]))).sorted()
        report.importedSymbolHints = Array(Set(scanASCIIHints(data: data, patterns: ["NSView", "NSWindow", "AudioComponent", "AUAudioUnit", "VSTPluginMain", "GetPluginFactory", "clap_entry", "DllMain", "CreatePluginFactory"]))).sorted()
        if report.linkedLibraryHints.contains("AppKit") || report.importedSymbolHints.contains("NSView") || report.importedSymbolHints.contains("NSWindow") {
            report.warnings.append("Desktop UI dependency hint detected; prefer Mac Companion or streamed editor surface.")
        }
        if report.architectures.contains("x86_64") || report.architectures.contains("i386") {
            report.warnings.append("x86 desktop slice requires Mac Companion, Rosetta-class translation, or Wine+FEX chaos path.")
        }
        if report.architectures.contains("arm64") && report.containerKind.contains("PE") {
            report.warnings.append("Windows ARM64 candidate: best first Wine-on-visionOS smoke target once Wine ARM64 root exists.")
        }
        return report
    }

    private static func parseData(_ data: Data, originalURL: URL, executableURL: URL) -> VisionBinaryHeaderReport {
        guard data.count >= 4 else {
            return .init(pathHint: originalURL.path, containerKind: "too-small", architectures: [], minimumOSHints: [], linkedLibraryHints: [], importedSymbolHints: [], warnings: ["Binary is too small to parse."])
        }
        let magic = readUInt32(data, 0, littleEndian: false)
        let magicLE = readUInt32(data, 0, littleEndian: true)
        if magic == 0xCAFEBABE || magic == 0xCAFEBABF { return parseFatMachO(data, originalURL: originalURL, fat64: magic == 0xCAFEBABF) }
        if [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE].contains(magic) || [0xFEEDFACE, 0xFEEDFACF].contains(magicLE) {
            return parseThinMachO(data, originalURL: originalURL)
        }
        if data[0] == 0x4D && data[1] == 0x5A { return parsePE(data, originalURL: originalURL) }
        return .init(pathHint: originalURL.path, containerKind: "unknown", architectures: [], minimumOSHints: [], linkedLibraryHints: [], importedSymbolHints: [], warnings: ["Unknown binary magic for \(executableURL.lastPathComponent)."])
    }

    private static func parseFatMachO(_ data: Data, originalURL: URL, fat64: Bool) -> VisionBinaryHeaderReport {
        let count = Int(readUInt32(data, 4, littleEndian: false))
        let stride = fat64 ? 32 : 20
        var archs: [String] = []
        var warnings: [String] = []
        for i in 0..<min(count, 32) {
            let offset = 8 + i * stride
            guard offset + 8 <= data.count else { break }
            let cpu = readUInt32(data, offset, littleEndian: false)
            let subtype = readUInt32(data, offset + 4, littleEndian: false)
            archs.append(machArchitecture(cpu: cpu, subtype: subtype))
        }
        if archs.isEmpty { warnings.append("Fat Mach-O container found but no architecture records could be read.") }
        return .init(pathHint: originalURL.path, containerKind: fat64 ? "Mach-O universal/fat64" : "Mach-O universal/fat", architectures: Array(Set(archs)).sorted(), minimumOSHints: [], linkedLibraryHints: [], importedSymbolHints: [], warnings: warnings)
    }

    private static func parseThinMachO(_ data: Data, originalURL: URL) -> VisionBinaryHeaderReport {
        let magic = readUInt32(data, 0, littleEndian: true)
        let cpu = readUInt32(data, 4, littleEndian: true)
        let subtype = readUInt32(data, 8, littleEndian: true)
        let is64 = magic == 0xFEEDFACF || magic == 0xCFFAEDFE
        return .init(pathHint: originalURL.path, containerKind: is64 ? "Mach-O thin 64" : "Mach-O thin 32", architectures: [machArchitecture(cpu: cpu, subtype: subtype)], minimumOSHints: [], linkedLibraryHints: [], importedSymbolHints: [], warnings: [])
    }

    private static func parsePE(_ data: Data, originalURL: URL) -> VisionBinaryHeaderReport {
        guard data.count >= 0x40 else { return .init(pathHint: originalURL.path, containerKind: "PE/MZ truncated", architectures: [], minimumOSHints: [], linkedLibraryHints: [], importedSymbolHints: [], warnings: ["PE header truncated."]) }
        let peOffset = Int(readUInt32(data, 0x3C, littleEndian: true))
        guard peOffset + 6 < data.count, data[peOffset] == 0x50, data[peOffset+1] == 0x45 else {
            return .init(pathHint: originalURL.path, containerKind: "MZ without PE", architectures: [], minimumOSHints: [], linkedLibraryHints: [], importedSymbolHints: [], warnings: ["MZ header exists but PE signature was not found."])
        }
        let machine = readUInt16(data, peOffset + 4, littleEndian: true)
        return .init(pathHint: originalURL.path, containerKind: "PE/COFF", architectures: [peArchitecture(machine)], minimumOSHints: [], linkedLibraryHints: [], importedSymbolHints: [], warnings: [])
    }

    private static func locateExecutableCandidate(in url: URL) -> URL {
        let fm = FileManager.default
        let ext = url.pathExtension.lowercased()
        if ["component", "vst3", "clap", "appex"].contains(ext) {
            if let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any], let exe = plist["CFBundleExecutable"] as? String {
                let macOSPath = url.appendingPathComponent("Contents/MacOS/\(exe)")
                if fm.fileExists(atPath: macOSPath.path) { return macOSPath }
                let rootPath = url.appendingPathComponent(exe)
                if fm.fileExists(atPath: rootPath.path) { return rootPath }
            }
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if ["dylib", "so", "dll", ""].contains(fileURL.pathExtension.lowercased()), fm.isExecutableFile(atPath: fileURL.path) { return fileURL }
                }
            }
        }
        return url
    }

    private static func scanASCIIHints(data: Data, patterns: [String]) -> [String] {
        guard let text = String(data: data.prefix(2_000_000), encoding: .ascii) else { return [] }
        let lower = text.lowercased()
        return patterns.filter { lower.contains($0.lowercased()) }
    }

    private static func machArchitecture(cpu: UInt32, subtype: UInt32) -> String {
        switch cpu {
        case 0x0100000C: return "arm64"
        case 0x0000000C: return "arm"
        case 0x01000007: return "x86_64"
        case 0x00000007: return "i386"
        default: return "mach-cpu-\(String(cpu, radix: 16))-sub-\(String(subtype, radix: 16))"
        }
    }

    private static func peArchitecture(_ machine: UInt16) -> String {
        switch machine {
        case 0x8664: return "x86_64"
        case 0x014c: return "i386"
        case 0xAA64: return "arm64"
        case 0x01c0, 0x01c4: return "arm"
        default: return "pe-machine-\(String(machine, radix: 16))"
        }
    }

    private static func readUInt16(_ data: Data, _ offset: Int, littleEndian: Bool) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let value = data[offset..<offset+2].reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        return littleEndian ? UInt16(littleEndian: value.byteSwapped) : value
    }

    private static func readUInt32(_ data: Data, _ offset: Int, littleEndian: Bool) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let value = data[offset..<offset+4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return littleEndian ? UInt32(littleEndian: value.byteSwapped) : value
    }
}

extension VisionStudioModel {
    func parseBinaryHeaders(for candidate: VisionCompatibilityCandidate) {
        let report = VisionBinaryHeaderParser.parse(url: URL(fileURLWithPath: candidate.pathHint))
        compatibilityLab.binaryReports.insert(report, at: 0)
        compatibilityLab.status = "Parsed headers for \(candidate.displayName): \(report.summary)."
        let metadata = compatibilityLab.metadataReports.first { $0.pathHint == candidate.pathHint }
        let refreshedMetadata = metadata.map { old in
            VisionPluginMetadataReport(displayName: old.displayName, pathHint: old.pathHint, detectedKind: old.detectedKind, bundleIdentifier: old.bundleIdentifier, version: old.version, architectures: report.architectures.isEmpty ? old.architectures : report.architectures, importedFrameworkHints: Array(Set(old.importedFrameworkHints + report.linkedLibraryHints)).sorted(), desktopOnlySignals: old.desktopOnlySignals, notes: old.notes + report.warnings)
        }
        let plan = VisionPluginBackendRegistry.dryRunPlan(for: candidate, metadata: refreshedMetadata ?? metadata)
        compatibilityLab.backendPlans.insert(plan, at: 0)
    }
}
