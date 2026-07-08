import Foundation
import UIKit

struct VisionSpliceMCPTool: Identifiable, Codable, Sendable, Hashable {
    var id: String { name }
    var name: String
    var description: String
    var propertyNames: [String] = []
}

struct VisionSpliceSampleCandidate: Identifiable, Codable, Sendable, Hashable {
    var id: String
    var title: String
    var producer: String?
    var bpm: Double?
    var key: String?
    var tags: [String]
    var lengthBeats: Double
    var remoteURI: String
    var previewURI: String?
    var downloadURI: String?
    var pageURI: String?
    var localFilePath: String?
    var licenseSummary: String?
}

struct VisionSpliceToolCallDraft: Codable, Sendable, Hashable {
    var toolName: String
    var arguments: [String: String]
    var safetyNote: String
}

struct VisionSpliceMCPStatus: Codable, Sendable, Hashable {
    var endpoint: String = "https://mcp.splice.com/mcp"
    var connected: Bool = false
    var authenticated: Bool = false
    var sessionID: String? = nil
    var statusText: String = "Not connected"
    var tools: [VisionSpliceMCPTool] = []
    var lastSearchToolCall: VisionSpliceToolCallDraft? = nil
    var fetchOnDropEnabled: Bool = true
    var autoStretchEnabled: Bool = true
}

enum VisionSpliceMCPError: LocalizedError {
    case authenticationRequired(URL?)
    case noTool(String)
    case malformed(String)
    case downloadUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "Splice authentication is required. Sign in through the browser, then reconnect."
        case .noTool(let kind): return "Splice MCP did not advertise a usable \(kind) tool."
        case .malformed(let message), .downloadUnavailable(let message): return message
        }
    }
}

/// Official Streamable HTTP MCP client for visionOS.
/// No scraping, copied tokens, or private CDN endpoints are used.
struct VisionSpliceMCPClient: Sendable {
    var endpoint = URL(string: "https://mcp.splice.com/mcp")!

    func discoverTools(sessionID: String?) async throws -> VisionSpliceMCPStatus {
        let initialize = try await rpc(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": ["name": "LemmingsStudioVision", "version": "1.0.0-buildfix265"]
        ], sessionID: sessionID)
        let sid = initialize.sessionID ?? sessionID
        let listed = try await rpc(method: "tools/list", params: [:], sessionID: sid)
        return VisionSpliceMCPStatus(
            endpoint: endpoint.absoluteString,
            connected: true,
            authenticated: true,
            sessionID: listed.sessionID ?? sid,
            statusText: listed.tools.isEmpty ? "Connected; no tools advertised" : "Connected; discovered \(listed.tools.count) Splice MCP tools",
            tools: listed.tools,
            lastSearchToolCall: nil,
            fetchOnDropEnabled: true,
            autoStretchEnabled: true
        )
    }

    func search(query: String, bpm: Double, key: String?, scale: String?, sessionID: String?, tools: [VisionSpliceMCPTool], limit: Int = 24) async throws -> (samples: [VisionSpliceSampleCandidate], sessionID: String?) {
        guard let tool = Self.bestTool(in: tools, positive: ["search", "sample", "sound", "describe", "catalog"], negative: ["download", "stack"]) else {
            throw VisionSpliceMCPError.noTool("sample search")
        }
        var args: [String: Any] = [:]
        Self.setFirst(&args, names: tool.propertyNames, aliases: ["query", "q", "prompt", "description", "search", "search_query"], value: query)
        Self.setFirst(&args, names: tool.propertyNames, aliases: ["limit", "count", "num_results", "max_results"], value: limit)
        Self.setFirst(&args, names: tool.propertyNames, aliases: ["bpm", "tempo"], value: Int(bpm.rounded()))
        if let key { Self.setFirst(&args, names: tool.propertyNames, aliases: ["key", "musical_key"], value: key) }
        if let scale { Self.setFirst(&args, names: tool.propertyNames, aliases: ["scale", "mode"], value: scale) }
        if args.isEmpty { args["query"] = query }
        let response = try await rpc(method: "tools/call", params: ["name": tool.name, "arguments": args], sessionID: sessionID)
        let samples = Self.parseSamples(from: response.jsonObjects)
        guard !samples.isEmpty else { throw VisionSpliceMCPError.malformed("Splice returned no parseable samples for ‘\(query)’.") }
        return (samples, response.sessionID ?? sessionID)
    }

    func previewFile(for sample: VisionSpliceSampleCandidate, sessionID: String?) async throws -> URL {
        guard let text = sample.previewURI ?? sample.downloadURI, let url = URL(string: text) else {
            throw VisionSpliceMCPError.downloadUnavailable("This result did not expose a preview URL.")
        }
        return try await downloadHTTP(url, preferredName: sample.title, directory: FileManager.default.temporaryDirectory.appendingPathComponent("LemmingsStudio-Splice-Preview", isDirectory: true))
    }

    func download(sample: VisionSpliceSampleCandidate, to directory: URL, sessionID: String?, tools: [VisionSpliceMCPTool]) async throws -> (file: URL, sessionID: String?) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let direct = sample.downloadURI, let url = URL(string: direct), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return (try await downloadHTTP(url, preferredName: sample.title, directory: directory), sessionID)
        }
        guard let tool = Self.bestTool(in: tools, positive: ["download", "save", "sample", "sound", "asset"], negative: ["search"]) else {
            throw VisionSpliceMCPError.noTool("download")
        }
        var args: [String: Any] = [:]
        Self.setFirst(&args, names: tool.propertyNames, aliases: ["asset_uuid", "asset_id", "uuid", "sample_id", "sound_id", "id"], value: sample.id)
        Self.setFirst(&args, names: tool.propertyNames, aliases: ["name", "title", "filename"], value: sample.title)
        if let pageURI = sample.pageURI { Self.setFirst(&args, names: tool.propertyNames, aliases: ["url", "page_url", "sample_page_url"], value: pageURI) }
        let response = try await rpc(method: "tools/call", params: ["name": tool.name, "arguments": args], sessionID: sessionID)
        if let local = Self.findLocalFileURL(in: response.jsonObjects), FileManager.default.fileExists(atPath: local.path) {
            let dst = Self.uniqueDestination(in: directory, preferredName: sample.title, ext: local.pathExtension.isEmpty ? "wav" : local.pathExtension)
            try FileManager.default.copyItem(at: local, to: dst)
            return (dst, response.sessionID ?? sessionID)
        }
        if let remote = Self.findRemoteAudioURL(in: response.jsonObjects) {
            return (try await downloadHTTP(remote, preferredName: sample.title, directory: directory), response.sessionID ?? sessionID)
        }
        throw VisionSpliceMCPError.downloadUnavailable("The official Splice download tool completed but returned no usable file or downloadable audio URL.")
    }

    private func rpc(method: String, params: [String: Any], sessionID: String?) async throws -> MCPResponseSummary {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if let token = VisionCredentialStore.get(account: "splice-oauth-access-token"), !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": UUID().uuidString, "method": method, "params": params])
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 401 || http?.statusCode == 403 {
            throw VisionSpliceMCPError.authenticationRequired(nil)
        }
        guard let code = http?.statusCode, (200..<300).contains(code) else {
            throw VisionSpliceMCPError.malformed("Splice MCP HTTP \(http?.statusCode ?? -1)")
        }
        return MCPResponseSummary(sessionID: http?.value(forHTTPHeaderField: "Mcp-Session-Id"), data: data)
    }

    private static func bestTool(in tools: [VisionSpliceMCPTool], positive: [String], negative: [String]) -> VisionSpliceMCPTool? {
        tools.map { tool -> (VisionSpliceMCPTool, Int) in
            let hay = (tool.name + " " + tool.description).lowercased()
            let score = positive.reduce(0) { $0 + (hay.contains($1) ? 5 : 0) } - negative.reduce(0) { $0 + (hay.contains($1) ? 7 : 0) }
            return (tool, score)
        }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    private static func setFirst(_ args: inout [String: Any], names: [String], aliases: [String], value: Any) {
        let lookup = Dictionary(uniqueKeysWithValues: names.map { ($0.lowercased(), $0) })
        for alias in aliases where lookup[alias.lowercased()] != nil { args[lookup[alias.lowercased()]!] = value; return }
    }

    private func downloadHTTP(_ url: URL, preferredName: String, directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (temporary, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw VisionSpliceMCPError.downloadUnavailable("Audio download failed with HTTP \(http.statusCode).")
        }
        let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
        let dst = Self.uniqueDestination(in: directory, preferredName: preferredName, ext: ext)
        try FileManager.default.moveItem(at: temporary, to: dst)
        return dst
    }

    private static func uniqueDestination(in directory: URL, preferredName: String, ext: String) -> URL {
        let safe = preferredName.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
        var candidate = directory.appendingPathComponent(safe).appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(safe)-\(index)").appendingPathExtension(ext); index += 1
        }
        return candidate
    }

    private struct MCPResponseSummary: Sendable {
        var sessionID: String?
        var tools: [VisionSpliceMCPTool]
        var jsonObjects: [[String: AnySendableJSON]]

        init(sessionID: String?, data: Data) {
            self.sessionID = sessionID
            let payloads = Self.payloads(from: data)
            self.jsonObjects = payloads.compactMap { payload in
                guard let raw = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
                return raw.mapValues(AnySendableJSON.wrap)
            }
            self.tools = Self.parseTools(from: payloads)
        }

        private static func payloads(from data: Data) -> [Data] {
            let text = String(data: data, encoding: .utf8) ?? ""
            guard text.contains("data:") else { return [data] }
            return text.split(separator: "\n").compactMap { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("data:") else { return nil }
                return t.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8)
            }
        }

        private static func parseTools(from payloads: [Data]) -> [VisionSpliceMCPTool] {
            for payload in payloads {
                guard let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { continue }
                let result = root["result"] as? [String: Any]
                let list = (result?["tools"] as? [[String: Any]]) ?? []
                let tools = list.compactMap { item -> VisionSpliceMCPTool? in
                    guard let name = item["name"] as? String else { return nil }
                    let schema = item["inputSchema"] as? [String: Any]
                    let props = schema?["properties"] as? [String: Any]
                    return .init(name: name, description: item["description"] as? String ?? "Splice MCP tool", propertyNames: props.map { Array($0.keys) } ?? [])
                }
                if !tools.isEmpty { return tools }
            }
            return []
        }
    }

    private static func parseSamples(from roots: [[String: AnySendableJSON]]) -> [VisionSpliceSampleCandidate] {
        var dictionaries: [[String: AnySendableJSON]] = []
        roots.forEach { collectDictionaries(.object($0), into: &dictionaries) }
        var seen = Set<String>()
        return dictionaries.compactMap { d in
            let title = firstString(d, ["name", "title", "filename", "sample_name", "sound_name"])
            let id = firstString(d, ["asset_uuid", "asset_id", "uuid", "sample_id", "sound_id", "id"])
            guard let title, let id, !seen.contains(id) else { return nil }
            let urls = d.compactMapValues { $0.stringValue }.values.compactMap(URL.init(string:))
            let preview = firstString(d, ["preview_url", "previewUrl", "audio_url", "stream_url"]) ?? urls.first(where: isAudioURL)?.absoluteString
            let download = firstString(d, ["download_url", "downloadUrl", "asset_url"])
            let page = firstString(d, ["page_url", "pageUrl", "url"])
            let bpm = firstDouble(d, ["bpm", "tempo"])
            let key = firstString(d, ["key", "musical_key"])
            let duration = firstDouble(d, ["duration", "duration_seconds", "length_seconds"])
            let tags = firstStringArray(d, ["tags", "genres", "instruments"])
            let beats = bpm.flatMap { bpm in duration.map { max(0.25, $0 * bpm / 60.0) } } ?? 4
            seen.insert(id)
            return .init(id: id, title: title, producer: firstString(d, ["producer", "creator", "artist", "creator_name"]), bpm: bpm, key: key, tags: tags, lengthBeats: beats, remoteURI: page ?? preview ?? "splice://sample/\(id)", previewURI: preview, downloadURI: download, pageURI: page, localFilePath: nil, licenseSummary: "Downloaded through authenticated official Splice MCP")
        }
    }

    private static func collectDictionaries(_ value: AnySendableJSON, into output: inout [[String: AnySendableJSON]]) {
        switch value {
        case .object(let d): output.append(d); d.values.forEach { collectDictionaries($0, into: &output) }
        case .array(let a): a.forEach { collectDictionaries($0, into: &output) }
        case .string(let text):
            if let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) { collectDictionaries(.wrap(json), into: &output) }
        default: break
        }
    }

    private static func firstString(_ d: [String: AnySendableJSON], _ keys: [String]) -> String? {
        let lower = Dictionary(uniqueKeysWithValues: d.map { ($0.key.lowercased(), $0.value) })
        for key in keys { if let s = lower[key.lowercased()]?.stringValue, !s.isEmpty { return s } }
        return nil
    }
    private static func firstDouble(_ d: [String: AnySendableJSON], _ keys: [String]) -> Double? {
        let lower = Dictionary(uniqueKeysWithValues: d.map { ($0.key.lowercased(), $0.value) })
        for key in keys { if let n = lower[key.lowercased()]?.doubleValue { return n } }
        return nil
    }
    private static func firstStringArray(_ d: [String: AnySendableJSON], _ keys: [String]) -> [String] {
        let lower = Dictionary(uniqueKeysWithValues: d.map { ($0.key.lowercased(), $0.value) })
        for key in keys { if case .array(let values)? = lower[key.lowercased()] { return values.compactMap(\.stringValue) } }
        return []
    }
    private static func isAudioURL(_ url: URL) -> Bool { ["wav", "aif", "aiff", "mp3", "m4a", "ogg", "flac"].contains(url.pathExtension.lowercased()) }
    private static func findRemoteAudioURL(in roots: [[String: AnySendableJSON]]) -> URL? {
        var dicts: [[String: AnySendableJSON]] = []; roots.forEach { collectDictionaries(.object($0), into: &dicts) }
        return dicts.flatMap { $0.values.compactMap(\.stringValue) }.compactMap(URL.init(string:)).first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && isAudioURL($0) }
    }
    private static func findLocalFileURL(in roots: [[String: AnySendableJSON]]) -> URL? {
        var dicts: [[String: AnySendableJSON]] = []; roots.forEach { collectDictionaries(.object($0), into: &dicts) }
        for text in dicts.flatMap({ $0.values.compactMap(\.stringValue) }) {
            if text.hasPrefix("file://"), let url = URL(string: text) { return url }
            if text.hasPrefix("/") { return URL(fileURLWithPath: text) }
        }
        return nil
    }
}

enum AnySendableJSON: Sendable {
    case string(String), number(Double), bool(Bool), array([AnySendableJSON]), object([String: AnySendableJSON]), null
    static func wrap(_ value: Any) -> AnySendableJSON {
        if let s = value as? String { return .string(s) }
        if let b = value as? Bool { return .bool(b) }
        if let n = value as? NSNumber { return .number(n.doubleValue) }
        if let a = value as? [Any] { return .array(a.map(wrap)) }
        if let d = value as? [String: Any] { return .object(d.mapValues(wrap)) }
        return .null
    }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var doubleValue: Double? { if case .number(let n) = self { return n }; if case .string(let s) = self { return Double(s) }; return nil }
}

extension VisionStudioModel {
    func refreshSpliceMCPTools() {
        spliceMCP.statusText = "Connecting to official Splice MCP…"
        Task {
            do {
                let client = VisionSpliceMCPClient(endpoint: URL(string: spliceMCP.endpoint) ?? URL(string: "https://mcp.splice.com/mcp")!)
                var next = try await client.discoverTools(sessionID: spliceMCP.sessionID)
                next.fetchOnDropEnabled = spliceMCP.fetchOnDropEnabled
                next.autoStretchEnabled = spliceMCP.autoStretchEnabled
                spliceMCP = next
                statusMessage = spliceMCP.statusText
            } catch VisionSpliceMCPError.authenticationRequired(let url) {
                spliceMCP.connected = false; spliceMCP.authenticated = false
                spliceMCP.statusText = "Sign in to Splice, then reconnect"
                statusMessage = spliceMCP.statusText
                if let url { await UIApplication.shared.open(url) } else { self.beginSpliceLogin() }
            } catch {
                spliceMCP.connected = false
                spliceMCP.statusText = "Splice MCP unavailable: \(error.localizedDescription)"
                statusMessage = spliceMCP.statusText
            }
        }
    }

    func runSpliceSearch() {
        let tool = spliceMCP.tools.first { ($0.name + " " + $0.description).lowercased().contains("search") }?.name ?? "dynamic search tool"
        spliceMCP.lastSearchToolCall = .init(toolName: tool, arguments: ["query": spliceSearchQuery, "bpm": String(format: "%.0f", project.effectiveTempo), "key": project.keyName ?? "C", "scale": project.scaleName ?? "Major"], safetyNote: "Official authenticated Splice MCP call; no scraping or copied tokens.")
        spliceMCP.statusText = "Searching Splice…"
        Task {
            do {
                let client = VisionSpliceMCPClient(endpoint: URL(string: spliceMCP.endpoint)!)
                let result = try await client.search(query: spliceSearchQuery, bpm: project.effectiveTempo, key: project.keyName, scale: project.scaleName, sessionID: spliceMCP.sessionID, tools: spliceMCP.tools)
                spliceSearchResults = result.samples
                spliceMCP.sessionID = result.sessionID
                selectedSpliceSampleID = result.samples.first?.id
                spliceMCP.statusText = "Found \(result.samples.count) Splice sample(s)"
                statusMessage = spliceMCP.statusText
            } catch { spliceMCP.statusText = error.localizedDescription; statusMessage = spliceMCP.statusText }
        }
    }

    func selectedSpliceSample() -> VisionSpliceSampleCandidate? { spliceSearchResults.first { $0.id == selectedSpliceSampleID } ?? spliceSearchResults.first }

    func previewSelectedSpliceSample() {
        guard let sample = selectedSpliceSample() else { statusMessage = "No Splice sample selected"; return }
        spliceMCP.statusText = "Loading preview…"
        Task {
            do {
                let file = try await VisionSpliceMCPClient(endpoint: URL(string: spliceMCP.endpoint)!).previewFile(for: sample, sessionID: spliceMCP.sessionID)
                audioEngine.playOneShotSample(path: file.path, projectURL: nil, volume: 1, pan: 0)
                spliceMCP.statusText = "Previewing \(sample.title)"
            } catch { spliceMCP.statusText = "Preview failed: \(error.localizedDescription)" }
            statusMessage = spliceMCP.statusText
        }
    }

    func fetchSelectedSpliceSample(insertToArrangement: Bool = false, mapToSequencer: Bool = false) {
        guard let sample = selectedSpliceSample() else { statusMessage = "No Splice sample selected"; return }
        fetchSpliceSample(sample, targetTrackIndex: insertToArrangement ? nil : nil, sequencerLayerIndex: mapToSequencer ? -1 : nil, insertToArrangement: insertToArrangement)
    }

    func fetchSpliceSample(_ sample: VisionSpliceSampleCandidate, targetTrackIndex: Int? = nil, sequencerLayerIndex: Int? = nil, insertToArrangement: Bool = false) {
        if let local = sample.localFilePath {
            var ready = sample
            ready.localFilePath = local
            if insertToArrangement || targetTrackIndex != nil { importSampleCandidateToArrangement(ready, targetTrackIndex: targetTrackIndex) }
            if let layer = sequencerLayerIndex { importSampleCandidateToStepSequencer(ready, layerIndex: layer >= 0 ? layer : nil) }
            return
        }
        spliceMCP.statusText = "Downloading \(sample.title)…"
        Task {
            do {
                let directory = try spliceProjectSamplesDirectory()
                let client = VisionSpliceMCPClient(endpoint: URL(string: spliceMCP.endpoint)!)
                let result = try await client.download(sample: sample, to: directory, sessionID: spliceMCP.sessionID, tools: spliceMCP.tools)
                spliceMCP.sessionID = result.sessionID
                var ready = sample
                ready.localFilePath = relativeProjectPath(for: result.file)
                try persistSpliceMetadata(for: ready, audioFile: result.file)
                if let index = spliceSearchResults.firstIndex(where: { $0.id == ready.id }) { spliceSearchResults[index] = ready }
                if insertToArrangement || targetTrackIndex != nil { importSampleCandidateToArrangement(ready, targetTrackIndex: targetTrackIndex) }
                if let layer = sequencerLayerIndex { importSampleCandidateToStepSequencer(ready, layerIndex: layer >= 0 ? layer : nil) }
                spliceMCP.statusText = "Downloaded \(sample.title) into project samples"
                addMemoryEvent(kind: .arrangementDecision, title: "Imported Splice sample", detail: "\(sample.title) • \(sample.bpm.map { "\(Int($0)) BPM" } ?? "tempo unknown") • \(sample.key ?? "key unknown")", tags: ["splice", "sample", "import"])
            } catch { spliceMCP.statusText = "Splice download failed: \(error.localizedDescription)" }
            statusMessage = spliceMCP.statusText
        }
    }

    func spliceProjectSamplesDirectory() throws -> URL {
        let fm = FileManager.default
        let base: URL
        if let projectURL = currentProjectURL {
            base = VisionProjectPersistence.packageBaseURL(for: projectURL) ?? projectURL.deletingLastPathComponent()
        } else {
            base = fm.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("LemmingsStudio/Unsaved Project.lemmings-assets", isDirectory: true)
        }
        let dir = base.appendingPathComponent("Samples/Splice", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func relativeProjectPath(for file: URL) -> String {
        guard let projectURL = currentProjectURL else { return file.path }
        let base = VisionProjectPersistence.packageBaseURL(for: projectURL) ?? projectURL.deletingLastPathComponent()
        let parent = base.standardizedFileURL.path
        let full = file.standardizedFileURL.path
        guard full.hasPrefix(parent + "/") else { return full }
        return String(full.dropFirst(parent.count + 1))
    }

    func persistSpliceMetadata(for sample: VisionSpliceSampleCandidate, audioFile: URL) throws {
        let sidecar = audioFile.deletingPathExtension().appendingPathExtension("splice.json")
        let data = try JSONEncoder().encode(sample)
        try data.write(to: sidecar, options: .atomic)
    }
}
