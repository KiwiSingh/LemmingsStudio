import Foundation

// MARK: - DAW config import
//
// Best-effort import of MIDI controller mappings from installed DAWs. Ableton
// `.als` sets are gzipped XML, which we genuinely decompress and parse; Logic's
// controller-assignment store is a proprietary binary, so that path is a probe
// with an honest fallback. Neither DAW publishes a stable, documented mapping
// schema, so resolved targets are approximate and surfaced for the user to
// confirm — not silently trusted.

public struct DAWImportResult {
    public var mappings: [MIDIMapping] = []
    public var notes: [String] = []
}

public enum DAWConfigImporter {
    public static func importAll() -> DAWImportResult {
        var result = DAWImportResult()
        let ab = AbletonImporter.importMappings()
        result.mappings += ab.mappings; result.notes += ab.notes
        let lg = LogicImporter.importMappings()
        result.mappings += lg.mappings; result.notes += lg.notes
        if result.mappings.isEmpty && result.notes.isEmpty {
            result.notes.append("No Ableton or Logic configuration found to import.")
        }
        return result
    }
}

// MARK: - Ableton Live

public enum AbletonImporter {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Likely locations for the user's Live sets / library.
    static var searchRoots: [String] {
        [home + "/Music/Ableton",
         home + "/Documents/Ableton",
         home + "/Music/Ableton/User Library"]
    }

    public static func discoverRecentSets(limit: Int = 5) -> [URL] {
        let fm = FileManager.default
        var found: [(URL, Date)] = []
        for root in searchRoots {
            guard let en = fm.enumerator(at: URL(fileURLWithPath: root),
                                         includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for case let url as URL in en where url.pathExtension == "als" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                found.append((url, date))
            }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(limit).map { $0.0 }
    }

    public static func importMappings() -> DAWImportResult {
        var out = DAWImportResult()
        let sets = discoverRecentSets()
        guard let latest = sets.first else {
            out.notes.append("Ableton: no .als sets found in ~/Music/Ableton.")
            return out
        }
        guard let xml = gunzip(latest) else {
            out.notes.append("Ableton: found \(latest.lastPathComponent) but couldn't decompress it.")
            return out
        }
        out.mappings = parseMappings(xml: xml)
        out.notes.append("Ableton: parsed \(out.mappings.count) MIDI mapping(s) from \(latest.lastPathComponent). Targets are approximate — confirm before relying on them.")
        return out
    }

    /// Decompress a gzipped file via the system `gzip` (robust across versions).
    static func gunzip(_ url: URL) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        proc.arguments = ["-dc"]
        let inPipe = Pipe(), outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { try proc.run() } catch { return nil }
        inPipe.fileHandleForWriting.write(data)
        try? inPipe.fileHandleForWriting.close()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: outData, encoding: .utf8)
    }

    /// Heuristic XML scan for MIDI controller mappings. Ableton encodes mapped
    /// parameters with `<MidiControllerRange>` plus a controller index; the exact
    /// element names drift across Live versions, so we scan broadly.
    static func parseMappings(xml: String) -> [MIDIMapping] {
        #if canImport(FoundationXML) || os(macOS)
        guard let doc = try? XMLDocument(xmlString: xml, options: [.nodePreserveWhitespace]) else { return [] }
        var maps: [MIDIMapping] = []
        // Find nodes that carry a controller number alongside a target.
        let candidates = (try? doc.nodes(forXPath: "//*[contains(name(),'Midi') or contains(name(),'Controller')]")) ?? []
        var seen = Set<Int>()
        for node in candidates {
            guard let el = node as? XMLElement else { continue }
            // Look for a numeric controller/CC attribute or child <... Value="n"/>.
            let cc = intValue(el, attr: "Value")
                ?? intValue(firstChild(el, named: "ControllerNumber"), attr: "Value")
                ?? intValue(firstChild(el, named: "Cc"), attr: "Value")
            guard let ccNum = cc, ccNum >= 0, ccNum <= 127, !seen.contains(ccNum) else { continue }
            seen.insert(ccNum)
            let target = nearestTargetName(el)
            maps.append(MIDIMapping(cc: ccNum, channel: 0, trackName: nil,
                                    nodeID: "instrument", paramID: target ?? "cutoff",
                                    source: "Ableton"))
        }
        return maps
        #else
        return []
        #endif
    }

    private static func firstChild(_ el: XMLElement?, named: String) -> XMLElement? {
        el?.elements(forName: named).first
    }
    private static func intValue(_ el: XMLElement?, attr: String) -> Int? {
        guard let s = el?.attribute(forName: attr)?.stringValue else { return nil }
        return Int(s)
    }
    private static func nearestTargetName(_ el: XMLElement) -> String? {
        // Walk up looking for a parent element whose name hints at the parameter.
        var cur: XMLNode? = el
        for _ in 0..<5 {
            if let name = (cur as? XMLElement)?.name?.lowercased() {
                if name.contains("cutoff") { return "cutoff" }
                if name.contains("reson") { return "resonance" }
                if name.contains("volume") || name.contains("gain") { return "gain" }
            }
            cur = cur?.parent
        }
        return nil
    }
}

// MARK: - Logic Pro

public enum LogicImporter {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    public static func importMappings() -> DAWImportResult {
        var out = DAWImportResult()
        let candidates = [
            home + "/Library/Preferences/com.apple.logic.pro.cs",
            home + "/Music/Audio Music Apps/Control Surfaces/Controller Assignments.cs",
        ]
        let existing = candidates.filter { FileManager.default.fileExists(atPath: $0) }
        guard let path = existing.first else {
            out.notes.append("Logic: no controller-assignment file found.")
            return out
        }
        // The .cs store is a proprietary binary; try a plist read, else scan bytes
        // for CC-like values. This is intentionally conservative.
        if let dict = NSDictionary(contentsOfFile: path) {
            out.notes.append("Logic: read \(path) as a property list. Found \(dict.count) top-level keys.")
        } else if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            out.notes.append("Logic: \(URL(fileURLWithPath: path).lastPathComponent) is a binary store (\(data.count) bytes). Lemmings can't fully decode Logic's controller format; re-learn critical knobs via MIDI Learn.")
        }
        return out
    }
}
