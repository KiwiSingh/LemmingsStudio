import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Splice MCP integration

/// A sound returned by the Splice MCP server. The MCP response shape is not
/// guaranteed to be a stable public Swift model, so this type keeps a raw copy
/// while exposing the fields Lemmings needs in the sample browser.
public struct SpliceSample: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let bpm: Int?
    public let key: String?
    public let previewURL: URL?
    public let pageURL: URL?
    public let downloadURL: URL?
    public let localFileURL: URL?
    public let artworkURL: URL?
    public let waveformURL: URL?
    public let packName: String?
    public let creatorName: String?
    public let instrument: String?
    public let soundType: String?
    public let durationSeconds: Double?
    public let tags: [String]
    public let raw: [String: String]

    public init(id: String,
                name: String,
                bpm: Int? = nil,
                key: String? = nil,
                previewURL: URL? = nil,
                pageURL: URL? = nil,
                downloadURL: URL? = nil,
                localFileURL: URL? = nil,
                artworkURL: URL? = nil,
                waveformURL: URL? = nil,
                packName: String? = nil,
                creatorName: String? = nil,
                instrument: String? = nil,
                soundType: String? = nil,
                durationSeconds: Double? = nil,
                tags: [String] = [],
                raw: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.bpm = bpm
        self.key = key
        self.previewURL = previewURL
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.localFileURL = localFileURL
        self.artworkURL = artworkURL
        self.waveformURL = waveformURL
        self.packName = packName
        self.creatorName = creatorName
        self.instrument = instrument
        self.soundType = soundType
        self.durationSeconds = durationSeconds
        self.tags = tags
        self.raw = raw
    }

    public var subtitle: String {
        [packName, creatorName, soundType, instrument].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    public var durationText: String? {
        guard let durationSeconds else { return nil }
        let total = max(0, Int(durationSeconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public var hiddenAssetUUID: String? {
        Self.validAssetUUID(raw["asset_uuid"])
            ?? Self.validAssetUUID(raw["asset_id"])
            ?? Self.validAssetUUID(raw["uuid"])
            ?? Self.validAssetUUID(id)
            ?? Self.firstUndashedAssetUUID(in: id)
            ?? raw.values.compactMap { Self.firstAssetUUID(in: $0) ?? Self.firstUndashedAssetUUID(in: $0) }.first
            ?? [pageURL, previewURL, downloadURL].compactMap { url in
                guard let url else { return nil }
                return Self.assetUUID(fromSpliceURL: url)
            }.first
    }

    public var withHiddenAssetUUIDFromPageURL: SpliceSample {
        guard raw["asset_uuid"] == nil, let uuid = hiddenAssetUUID else { return self }
        var next = raw
        next["asset_uuid"] = uuid
        if next["page_url"] == nil, let pageURL { next["page_url"] = pageURL.absoluteString }
        return SpliceSample(id: uuid, name: name, bpm: bpm, key: key, previewURL: previewURL, pageURL: pageURL, downloadURL: downloadURL, localFileURL: localFileURL, artworkURL: artworkURL, waveformURL: waveformURL, packName: packName, creatorName: creatorName, instrument: instrument, soundType: soundType, durationSeconds: durationSeconds, tags: tags, raw: next)
    }

    /// Returns a copy with a discovered preview-audio URL attached (used when the
    /// Web Preview page exposes a playable stream we can hand to AVPlayer).
    public func withPreviewURL(_ url: URL) -> SpliceSample {
        var next = raw
        next["preview_url"] = url.absoluteString
        return SpliceSample(id: id, name: name, bpm: bpm, key: key, previewURL: url, pageURL: pageURL, downloadURL: downloadURL, localFileURL: localFileURL, artworkURL: artworkURL, waveformURL: waveformURL, packName: packName, creatorName: creatorName, instrument: instrument, soundType: soundType, durationSeconds: durationSeconds, tags: tags, raw: next)
    }

    public static func assetUUID(fromSpliceURL url: URL) -> String? {
        let absolute = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        guard let host = url.host?.lowercased(), host.contains("splice.com") else {
            return firstAssetUUID(in: absolute) ?? firstUndashedAssetUUID(in: absolute)
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                let key = item.name.lowercased()
                guard key.contains("uuid") || key.contains("asset") || key == "id" || key.contains("sound") || key.contains("sample") else { continue }
                if let value = item.value, let uuid = validAssetUUID(value) ?? firstAssetUUID(in: value) ?? firstUndashedAssetUUID(in: value) {
                    return uuid
                }
            }
        }
        let parts = url.pathComponents.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }.filter { !$0.isEmpty }
        for marker in ["sample", "samples", "sound", "sounds"] {
            if let i = parts.firstIndex(where: { $0.lowercased() == marker }), parts.indices.contains(i + 1) {
                let next = parts[i + 1]
                if let uuid = validAssetUUID(next) ?? firstAssetUUID(in: next) ?? firstUndashedAssetUUID(in: next) { return uuid }
            }
        }
        return firstAssetUUID(in: absolute) ?? firstUndashedAssetUUID(in: absolute)
    }

    /// Web Preview loads Splice's own pages in a WKWebView. Those pages often
    /// do not navigate to a UUID-bearing URL, but the DOM/JSON-LD/script payload
    /// can still contain the asset id. This helper intentionally extracts only
    /// identifiers; it does not fetch, decode, or expose preview audio.
    public static func assetUUID(fromSplicePageHTML html: String, preferredPageURL: URL? = nil) -> String? {
        let decoded = html.removingPercentEncoding ?? html
        if let preferredPageURL, let uuid = assetUUID(fromSpliceURL: preferredPageURL) { return uuid }

        let highSignalPatterns = [
            #"(?i)(?:asset[_-]?uuid|asset[_-]?id|sample[_-]?uuid|sample[_-]?id|sound[_-]?uuid|sound[_-]?id|uuid|id)\s*[:=]\s*[\"']?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"#,
            #"(?i)(?:asset[_-]?uuid|asset[_-]?id|sample[_-]?uuid|sample[_-]?id|sound[_-]?uuid|sound[_-]?id|uuid|id)\s*[:=]\s*[\"']?([0-9a-f]{32})"#,
            #"(?i)/(?:sample|samples|sound|sounds)/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:/|[?&"'<>]|$)"#,
            #"(?i)/(?:sample|samples|sound|sounds)/([0-9a-f]{32})(?:/|[?&"'<>]|$)"#
        ]
        for pattern in highSignalPatterns {
            if let uuid = firstCapturedUUID(in: decoded, pattern: pattern) { return uuid }
        }

        // Do not use a random UUID-like token as a last resort here. Splice's
        // web app embeds unrelated build/session/cache UUIDs; treating those as
        // asset UUIDs can make the official download tool respond with the
        // wonderfully helpful “download failed; please try again”. Only promote
        // UUIDs found in high-signal asset/sample/sound fields or URL paths.
        return nil
    }


    private static func firstCapturedUUID(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else { return nil }
        let captured = ns.substring(with: match.range(at: 1))
        return validAssetUUID(captured) ?? firstAssetUUID(in: captured) ?? firstUndashedAssetUUID(in: captured)
    }

    /// Best-effort extraction of a *playable* preview-audio URL from a Splice
    /// page's HTML (og:audio, <audio>/<source> tags, or a preview/stream URL in
    /// embedded JSON). Splice usually gates preview audio, so this often returns
    /// nil — in that case the caller keeps the WebView. When it does find a real
    /// media URL we can play it natively via AVPlayer instead of the browser.
    public static func previewAudioURL(fromSplicePageHTML html: String) -> URL? {
        let patterns = [
            #"(?i)<meta[^>]+property=[\"']og:audio(?::secure_url)?[\"'][^>]+content=[\"']([^\"']+)[\"']"#,
            #"(?i)<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:audio[\"']"#,
            #"(?i)<audio[^>]+src=[\"']([^\"']+)[\"']"#,
            #"(?i)<source[^>]+src=[\"']([^\"']+\.(?:mp3|ogg|m4a|wav)[^\"']*)[\"']"#,
            #"(?i)[\"'](?:preview_url|previewUrl|audio_url|audioUrl|stream_url|streamUrl|mp3|hls_url)[\"']\s*:\s*[\"']([^\"']+)[\"']"#,
            #"(?i)(https?://[^\s\"'<>]+\.(?:mp3|ogg|m4a|wav)(?:\?[^\s\"'<>]*)?)"#
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = html as NSString
            guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { continue }
            var raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'<>"))
            raw = raw.replacingOccurrences(of: "&amp;", with: "&")
            guard !raw.hasPrefix("blob:"), !raw.hasPrefix("data:") else { continue }
            if let u = URL(string: raw), ["http", "https"].contains(u.scheme?.lowercased() ?? "") { return u }
        }
        return nil
    }

    private static func validAssetUUID(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " `\"'/?#&="))
        if trimmed.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil {
            return trimmed.lowercased()
        }
        return firstUndashedAssetUUID(in: trimmed)
    }

    private static func firstAssetUUID(in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#) else { return nil }
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range).lowercased()
    }

    private static func firstUndashedAssetUUID(in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])"#) else { return nil }
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return undashedHexToUUID(ns.substring(with: match.range))
    }

    private static func undashedHexToUUID(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: " `\"'/?#&="))
        guard cleaned.range(of: #"^[0-9a-fA-F]{32}$"#, options: .regularExpression) != nil else { return nil }
        let lower = cleaned.lowercased()
        let chars = Array(lower)
        func part(_ start: Int, _ end: Int) -> String { String(chars[start..<end]) }
        return "\(part(0, 8))-\(part(8, 12))-\(part(12, 16))-\(part(16, 20))-\(part(20, 32))"
    }
}


public struct SpliceAccountSnapshot: Hashable, Sendable {
    public let toolName: String?
    public let creditsText: String?
    public let downloadsText: String?
    public let planText: String?
    public let statusText: String

    public init(toolName: String? = nil, creditsText: String? = nil, downloadsText: String? = nil, planText: String? = nil, statusText: String) {
        self.toolName = toolName
        self.creditsText = creditsText
        self.downloadsText = downloadsText
        self.planText = planText
        self.statusText = statusText
    }

    public var displayText: String {
        var parts: [String] = []
        if let creditsText, !creditsText.isEmpty { parts.append(creditsText) }
        if let downloadsText, !downloadsText.isEmpty { parts.append(downloadsText) }
        if let planText, !planText.isEmpty { parts.append(planText) }
        if parts.isEmpty { parts.append(statusText) }
        return parts.joined(separator: " • ")
    }
}

public protocol SpliceProviding {
    func connect() async throws -> [MCPTool]
    func search(query: String, limit: Int) async throws -> [SpliceSample]
    func download(_ sample: SpliceSample, to directory: URL) async throws -> URL
    func accountSnapshot() async throws -> SpliceAccountSnapshot
}

public enum SpliceError: LocalizedError, Sendable {
    case invalidEndpoint
    case authRequired(String, URL?)
    case noSearchTool([String])
    case noDownloadTool([String])
    case badResponse(String)
    case downloadUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The Splice MCP URL is invalid."
        case .authRequired(let message, _):
            return message
        case .noSearchTool(let tools):
            return "Connected to MCP, but no Splice search tool was found. Tools: \(tools.joined(separator: ", "))"
        case .noDownloadTool(let tools):
            return "Connected to MCP, but no Splice download tool was found. Tools: \(tools.joined(separator: ", "))"
        case .badResponse(let message):
            return message
        case .downloadUnavailable(let message):
            return message
        }
    }
}

public struct MCPTool: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let inputSchema: [String: AnySendable]

    public var propertyNames: [String] {
        guard let props = inputSchema["properties"]?.dictionary else { return [] }
        return props.keys.sorted()
    }
}

/// Tiny wrapper for JSON-ish dictionaries that need to be stored on Sendable
/// Swift structs without pulling in a full dynamic JSON package.
public enum AnySendable: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([AnySendable])
    case dictionary([String: AnySendable])
    case null

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var dictionary: [String: AnySendable]? { if case .dictionary(let d) = self { return d }; return nil }

    public static func wrap(_ value: Any?) -> AnySendable {
        switch value {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let n as NSNumber: return .number(n.doubleValue)
        case let a as [Any]: return .array(a.map { wrap($0) })
        case let d as [String: Any]: return .dictionary(d.mapValues { wrap($0) })
        default: return .null
        }
    }

    public func unwrap() -> Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .array(let a): return a.map { $0.unwrap() }
        case .dictionary(let d): return d.mapValues { $0.unwrap() }
        case .null: return NSNull()
        }
    }
}

public enum SpliceOfficialMCP {
    public static let endpoint = URL(string: "https://mcp.splice.com/mcp")!
    public static let authorizationServer = URL(string: "https://mcp.splice.com")!
    public static let protectedResourceMetadata = URL(string: "https://mcp.splice.com/.well-known/oauth-protected-resource/mcp")!
    public static let authorizationServerMetadata = URL(string: "https://mcp.splice.com/.well-known/oauth-authorization-server")!
    public static let openIDConfiguration = URL(string: "https://mcp.splice.com/.well-known/openid-configuration")!
    public static let docs = URL(string: "https://support.splice.com/en/articles/14442749-getting-started-with-the-splice-mcp-server-beta")!
    public static let landing = URL(string: "https://splice.com/tools/mcp-server")!
    public static let defaultScope = "openid profile email offline_access"
    public static let cursorConfig = """
    {
      "mcpServers": {
        "splice": {
          "type": "streamable-http",
          "url": "https://mcp.splice.com/mcp"
        }
      }
    }
    """
}

public final class SpliceClient: SpliceProviding, @unchecked Sendable {
    public var endpoint: URL
    public var bearerToken: String

    private let mcp: MCPHTTPClient
    private var cachedTools: [MCPTool] = []

    public init(endpoint: URL = SpliceOfficialMCP.endpoint,
                bearerToken: String = "") {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.mcp = MCPHTTPClient(endpoint: endpoint, bearerToken: bearerToken)
    }

    @discardableResult
    public func connect() async throws -> [MCPTool] {
        mcp.endpoint = endpoint
        mcp.bearerToken = bearerToken
        try await mcp.initializeIfNeeded()
        cachedTools = try await mcp.listTools()
        return cachedTools
    }

    public func search(query: String, limit: Int = 12) async throws -> [SpliceSample] {
        try await search(query: query, limit: limit, type: nil, bpmMin: nil, bpmMax: nil)
    }

    /// `type` should be "loop" or "oneshot" (Splice's `describe_a_sound` enum); nil = no filter.
    public func search(query: String, limit: Int = 12, type: String?, bpmMin: Int?, bpmMax: Int?) async throws -> [SpliceSample] {
        let tools = try await tools()
        guard let tool = Self.bestSearchTool(in: tools) else {
            throw SpliceError.noSearchTool(tools.map(\.name))
        }
        let args = Self.arguments(for: tool, query: query, sample: nil, directory: nil, limit: limit, type: type, bpmMin: bpmMin, bpmMax: bpmMax)
        let result = try await mcp.callTool(name: tool.name, arguments: args)
        let samples = Self.samples(fromToolResult: result)
        if samples.isEmpty {
            throw SpliceError.badResponse("Splice returned no parseable samples for ‘\(query)’. Raw response: \(Self.shortText(from: result))")
        }
        return samples
    }

    public func accountSnapshot() async throws -> SpliceAccountSnapshot {
        let tools = try await tools()
        guard let tool = Self.bestAccountTool(in: tools) else {
            return SpliceAccountSnapshot(statusText: "Splice MCP did not advertise an account/credits tool. Downloads can still use credits when the official download tool is available.")
        }
        do {
            let result = try await mcp.callTool(name: tool.name, arguments: [:])
            return Self.accountSnapshot(fromToolResult: result, toolName: tool.name)
        } catch {
            return SpliceAccountSnapshot(toolName: tool.name, statusText: "Account/credits probe unavailable: \(error.localizedDescription)")
        }
    }

    public func download(_ sample: SpliceSample, to directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // If a direct file URL came back from search, use it immediately.
        if let local = sample.localFileURL, FileManager.default.fileExists(atPath: local.path) { return local }
        if let url = sample.downloadURL ?? sample.previewURL, url.isFileURL { return url }
        if let direct = sample.downloadURL, ["http", "https"].contains(direct.scheme?.lowercased() ?? "") {
            return try await downloadHTTPFile(from: direct, namedLike: sample.name, to: directory)
        }

        let tools = try await tools()
        guard let tool = Self.bestDownloadTool(in: tools) else {
            if let page = sample.pageURL { throw SpliceError.downloadUnavailable("No MCP download tool was advertised. Open the sample page instead: \(page.absoluteString)") }
            throw SpliceError.noDownloadTool(tools.map(\.name))
        }

        // Do not call an official download/license tool with a page URL stuffed
        // into `asset_uuid`. If the browser card does not already contain a real
        // UUID, re-query the official MCP search/details path and keep the UUID
        // hidden in raw metadata for licensing/fetch only.
        let sampleForDownload: SpliceSample
        if Self.toolRequiresAssetUUID(tool), Self.assetUUID(in: sample) == nil {
            sampleForDownload = try await resolveAssetUUID(for: sample) ?? sample
            guard Self.assetUUID(in: sampleForDownload) != nil else {
                throw SpliceError.downloadUnavailable("Splice returned this as a page-only result. I could not resolve a hidden asset UUID from the official MCP response yet, so LemmingsStudio will not send a fake asset_uuid to the download tool.")
            }
        } else {
            sampleForDownload = sample
        }

        let args = Self.arguments(for: tool, query: nil, sample: sampleForDownload, directory: directory, limit: nil)
        if Self.toolRequiresAssetUUID(tool), !args.keys.contains(where: { ["asset_uuid", "assetuuid", "uuid", "asset_id", "assetid", "id"].contains($0.lowercased()) }) {
            throw SpliceError.downloadUnavailable("Splice's download tool requires an asset UUID, but the search result did not expose one.")
        }
        let result = try await mcp.callTool(name: tool.name, arguments: args)
        if let file = try await downloadedFile(from: result, namedLike: sample.name, to: directory) { return file }

        // A common failure mode is a UUID harvested from Splice's WebView DOM
        // that looks valid but is not the actual sample asset id. When the
        // official download tool returns a plain failure string, force an
        // official MCP search/details re-resolution and retry once with that
        // hidden UUID instead of looping on the same bad identifier.
        if Self.isExplicitDownloadFailure(result), let resolved = try await resolveAssetUUID(for: sample), Self.assetUUID(in: resolved) != Self.assetUUID(in: sampleForDownload) {
            let retryArgs = Self.arguments(for: tool, query: nil, sample: resolved, directory: directory, limit: nil)
            let retry = try await mcp.callTool(name: tool.name, arguments: retryArgs)
            if let file = try await downloadedFile(from: retry, namedLike: sample.name, to: directory) { return file }
            throw SpliceError.downloadUnavailable("Splice's official download tool still failed after re-resolving the asset through MCP search. Raw response: \(Self.shortText(from: retry))")
        }

        if Self.isExplicitDownloadFailure(result) {
            throw SpliceError.downloadUnavailable("Splice's official download tool said: \(Self.shortText(from: result)). Try again, check Splice credits/login, or use Web Preview / Splice Sounds as the fallback.")
        }

        throw SpliceError.badResponse("The Splice download tool ran, but no local file path or downloadable URL was returned. Raw response: \(Self.shortText(from: result))")
    }

    private func downloadedFile(from result: Any, namedLike name: String, to directory: URL) async throws -> URL? {
        if let local = Self.localFileURL(fromToolResult: result) { return local }
        if let remote = Self.remoteDownloadURL(fromToolResult: result) {
            return try await downloadHTTPFile(from: remote, namedLike: name, to: directory)
        }
        return nil
    }

    private func resolveAssetUUID(for sample: SpliceSample) async throws -> SpliceSample? {
        let tools = try await tools()
        guard let searchTool = Self.bestSearchTool(in: tools) else { return nil }
        let queries = [
            sample.pageURL?.absoluteString,
            "\(sample.name) \(sample.bpm.map { "\($0) bpm" } ?? "") \(sample.key ?? "")",
            sample.name
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        for query in Array(NSOrderedSet(array: queries).compactMap { $0 as? String }).prefix(3) {
            let args = Self.arguments(for: searchTool, query: query, sample: nil, directory: nil, limit: 10)
            let result = try await mcp.callTool(name: searchTool.name, arguments: args)
            let candidates = Self.samples(fromToolResult: result).filter { Self.assetUUID(in: $0) != nil }
            if let exact = candidates.first(where: { candidate in
                candidate.pageURL == sample.pageURL || candidate.name.caseInsensitiveCompare(sample.name) == .orderedSame
            }) { return Self.merging(sample, hiddenAssetFrom: exact) }
            if let close = candidates.first(where: { candidate in
                candidate.name.lowercased().contains(sample.name.lowercased()) || sample.name.lowercased().contains(candidate.name.lowercased())
            }) { return Self.merging(sample, hiddenAssetFrom: close) }
            if let first = candidates.first { return Self.merging(sample, hiddenAssetFrom: first) }
        }
        return nil
    }

    private func tools() async throws -> [MCPTool] {
        if cachedTools.isEmpty { return try await connect() }
        return cachedTools
    }

    private func downloadHTTPFile(from url: URL, namedLike name: String, to directory: URL) async throws -> URL {
        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SpliceError.downloadUnavailable("Download failed with HTTP \(http.statusCode).")
        }
        let ext = url.pathExtension.isEmpty ? "wav" : url.pathExtension
        let safeName = name.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
        let dst = directory.appendingPathComponent(safeName).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: dst.path) { try? FileManager.default.removeItem(at: dst) }
        try FileManager.default.moveItem(at: tmp, to: dst)
        return dst
    }
}

// MARK: - Tool picking / argument mapping

extension SpliceClient {
    private static func bestSearchTool(in tools: [MCPTool]) -> MCPTool? {
        let ranked = tools.map { tool -> (MCPTool, Int) in
            let hay = (tool.name + " " + tool.description).lowercased()
            var score = 0
            if hay.contains("search") { score += 10 }
            if hay.contains("sample") || hay.contains("sound") { score += 7 }
            if hay.contains("catalog") { score += 4 }
            if hay.contains("find") || hay.contains("describe") { score += 3 }
            if hay.contains("download") { score -= 8 }
            if hay.contains("stack") { score -= 2 }
            return (tool, score)
        }.sorted { $0.1 > $1.1 }
        return ranked.first(where: { $0.1 > 0 })?.0
    }

    private static func bestAccountTool(in tools: [MCPTool]) -> MCPTool? {
        let ranked = tools.map { tool -> (MCPTool, Int) in
            let hay = (tool.name + " " + tool.description).lowercased()
            var score = 0
            if hay.contains("credit") || hay.contains("balance") { score += 14 }
            if hay.contains("account") || hay.contains("subscription") || hay.contains("plan") { score += 10 }
            if hay.contains("quota") || hay.contains("usage") || hay.contains("limit") { score += 8 }
            if hay == "me" || hay.contains(" user") || hay.contains("profile") { score += 4 }
            if hay.contains("search") || hay.contains("download") || hay.contains("sample") || hay.contains("stack") { score -= 10 }
            if hasRequiredInputs(tool) { score -= 8 }
            return (tool, score)
        }.sorted { $0.1 > $1.1 }
        return ranked.first(where: { $0.1 > 0 })?.0
    }

    private static func hasRequiredInputs(_ tool: MCPTool) -> Bool {
        guard let required = tool.inputSchema["required"] else { return false }
        if case .array(let values) = required { return !values.isEmpty }
        return false
    }

    private static func bestDownloadTool(in tools: [MCPTool]) -> MCPTool? {
        let ranked = tools.map { tool -> (MCPTool, Int) in
            let hay = (tool.name + " " + tool.description).lowercased()
            var score = 0
            if hay.contains("download") { score += 12 }
            if hay.contains("asset") || hay.contains("sample") || hay.contains("sound") { score += 5 }
            if hay.contains("save") { score += 3 }
            if hay.contains("search") { score -= 8 }
            return (tool, score)
        }.sorted { $0.1 > $1.1 }
        return ranked.first(where: { $0.1 > 0 })?.0
    }

    private static func arguments(for tool: MCPTool, query: String?, sample: SpliceSample?, directory: URL?, limit: Int?) -> [String: Any] {
        arguments(for: tool, query: query, sample: sample, directory: directory, limit: limit, type: nil, bpmMin: nil, bpmMax: nil)
    }

    private static func arguments(for tool: MCPTool, query: String?, sample: SpliceSample?, directory: URL?, limit: Int?, type: String?, bpmMin: Int?, bpmMax: Int?) -> [String: Any] {
        let props = tool.inputSchema["properties"]?.dictionary ?? [:]
        var args: [String: Any] = [:]
        let propertyKeys = Array(props.keys)
        let keys = propertyKeys.map { $0.lowercased() }
        func actual(_ names: [String]) -> String? {
            for name in names {
                if let i = keys.firstIndex(of: name.lowercased()) { return propertyKeys[i] }
            }
            return nil
        }

        if let query, let k = actual(["query", "q", "prompt", "description", "search", "searchQuery", "search_query", "text"]) {
            args[k] = query
        } else if let query { args["query"] = query }

        if let limit, let k = actual(["limit", "count", "numResults", "num_results", "maxResults", "max_results"]) {
            args[k] = limit
        }

        // Loop / one-shot filter. Splice's describe_a_sound exposes `type` with the
        // enum {loop, oneshot}; only send a value the schema actually advertises so
        // we never break the call on servers with a different shape.
        if let type, !type.isEmpty, let k = actual(["type", "sample_type", "sampleType", "sound_type", "soundType", "kind", "asset_type"]) {
            args[k] = type
        }
        if let bpmMin, let k = actual(["bpm_min", "bpmMin", "min_bpm", "minBpm"]) { args[k] = bpmMin }
        if let bpmMax, let k = actual(["bpm_max", "bpmMax", "max_bpm", "maxBpm"]) { args[k] = bpmMax }

        if let sample {
            let assetID = assetUUID(in: sample)
            if let assetID, let k = actual(["asset_uuid", "assetUUID", "uuid", "assetId", "asset_id", "sampleId", "sample_id", "soundId", "sound_id", "id"]) {
                args[k] = assetID
            }
            if let k = actual(["name", "title", "filename"]) { args[k] = sample.name }
            // Page links are not asset UUIDs. Only pass them to explicit URL/page
            // fields; never to asset_url/assetUrl, because Splice's download
            // schema may validate that field as an asset identifier.
            if let page = sample.pageURL, let k = actual(["pageUrl", "page_url", "samplePageUrl", "sample_page_url", "url"]) { args[k] = page.absoluteString }
        }
        if let directory, let k = actual(["download_path", "downloadPath", "path", "directory", "downloadDirectory", "download_directory", "output", "outputDir", "output_dir"]) {
            args[k] = directory.path
        }
        return args
    }

    private static func assetUUID(in sample: SpliceSample) -> String? {
        sample.hiddenAssetUUID
    }

    private static func merging(_ sample: SpliceSample, hiddenAssetFrom resolved: SpliceSample) -> SpliceSample {
        var raw = sample.raw
        if let uuid = assetUUID(in: resolved) { raw["asset_uuid"] = uuid }
        if raw["page_url"] == nil, let page = resolved.pageURL { raw["page_url"] = page.absoluteString }
        return SpliceSample(id: raw["asset_uuid"] ?? sample.id,
                            name: sample.name,
                            bpm: sample.bpm ?? resolved.bpm,
                            key: sample.key ?? resolved.key,
                            previewURL: sample.previewURL ?? resolved.previewURL,
                            pageURL: sample.pageURL ?? resolved.pageURL,
                            downloadURL: sample.downloadURL ?? resolved.downloadURL,
                            localFileURL: sample.localFileURL ?? resolved.localFileURL,
                            artworkURL: sample.artworkURL ?? resolved.artworkURL,
                            waveformURL: sample.waveformURL ?? resolved.waveformURL,
                            packName: sample.packName ?? resolved.packName,
                            creatorName: sample.creatorName ?? resolved.creatorName,
                            instrument: sample.instrument ?? resolved.instrument,
                            soundType: sample.soundType ?? resolved.soundType,
                            durationSeconds: sample.durationSeconds ?? resolved.durationSeconds,
                            tags: sample.tags.isEmpty ? resolved.tags : sample.tags,
                            raw: raw)
    }

    private static func requiredPropertyNames(_ tool: MCPTool) -> [String] {
        guard let required = tool.inputSchema["required"] else { return [] }
        if case .array(let values) = required {
            return values.compactMap { value in
                if case .string(let s) = value { return s }
                return nil
            }
        }
        return []
    }

    private static func toolRequiresAssetUUID(_ tool: MCPTool) -> Bool {
        requiredPropertyNames(tool).contains { name in
            let key = name.lowercased()
            return key == "asset_uuid" || key == "assetuuid" || key == "uuid" || key == "asset_id" || key == "assetid"
        }
    }

    private static func accountSnapshot(fromToolResult result: Any, toolName: String) -> SpliceAccountSnapshot {
        var flattened: [String: String] = [:]
        flattenAccountResult(result, prefix: "", into: &flattened)

        func firstValue(keys wanted: [String]) -> String? {
            for (key, value) in flattened {
                let lower = key.lowercased()
                guard !isSensitiveAccountKey(lower), !value.isEmpty else { continue }
                if wanted.contains(where: { lower.contains($0) }) { return value }
            }
            return nil
        }

        let credits = firstValue(keys: ["credits_remaining", "remaining_credits", "credit_balance", "credits", "balance"]).map { "Credits: \($0)" }
        let downloadsRemaining = firstValue(keys: ["downloads_remaining", "remaining_downloads", "daily_remaining", "download_quota_remaining", "remaining"])
        let downloadsLimit = firstValue(keys: ["download_limit", "daily_limit", "limit"])
        let downloadsUsed = firstValue(keys: ["downloads_used", "used_downloads", "used"])
        let downloads: String? = {
            if let downloadsRemaining, let downloadsLimit { return "Downloads left today: \(downloadsRemaining)/\(downloadsLimit)" }
            if let downloadsRemaining { return "Downloads left today: \(downloadsRemaining)" }
            if let downloadsUsed, let downloadsLimit { return "Downloads today: \(downloadsUsed)/\(downloadsLimit)" }
            return nil
        }()
        let plan = firstValue(keys: ["plan", "subscription", "tier", "product"]).map { "Plan: \($0)" }

        let status: String
        if credits == nil && downloads == nil && plan == nil {
            status = "Account tool ‘\(toolName)’ did not expose credits/download quota in a non-sensitive field."
        } else {
            status = "Account summary loaded without exposing email or username."
        }
        return SpliceAccountSnapshot(toolName: toolName, creditsText: credits, downloadsText: downloads, planText: plan, statusText: status)
    }

    private static func flattenAccountResult(_ value: Any, prefix: String, into out: inout [String: String]) {
        switch value {
        case let dict as [String: Any]:
            for (key, child) in dict {
                let next = prefix.isEmpty ? key : "\(prefix).\(key)"
                flattenAccountResult(child, prefix: next, into: &out)
            }
        case let array as [Any]:
            for (index, child) in array.enumerated() {
                flattenAccountResult(child, prefix: "\(prefix)[\(index)]", into: &out)
            }
        case let number as NSNumber:
            out[prefix] = number.stringValue
        case let string as String:
            out[prefix] = string
        case let bool as Bool:
            out[prefix] = bool ? "yes" : "no"
        default:
            break
        }
    }

    private static func isSensitiveAccountKey(_ key: String) -> Bool {
        key.contains("email") || key.contains("username") || key.contains("user_name") || key.contains("display_name") || key.contains("full_name") || key.hasSuffix(".name") || key == "name"
    }
}

// MARK: - MCP HTTP client

public final class MCPHTTPClient: @unchecked Sendable {
    public var endpoint: URL
    public var bearerToken: String

    private let session = URLSession(configuration: .default)
    private var nextID = 1
    private var initialized = false
    private var sessionID: String?

    public init(endpoint: URL, bearerToken: String = "") {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
    }

    public func initializeIfNeeded() async throws {
        if initialized { return }
        _ = try await request(method: "initialize", params: [
            "protocolVersion": "2025-03-26",
            "capabilities": ["tools": [:]],
            "clientInfo": ["name": "LemmingsStudio", "version": "1.0"]
        ])
        try? await notification(method: "notifications/initialized", params: [:])
        initialized = true
    }

    public func listTools() async throws -> [MCPTool] {
        try await initializeIfNeeded()
        let result = try await request(method: "tools/list", params: [:])
        guard let dict = result as? [String: Any], let rawTools = dict["tools"] as? [[String: Any]] else { return [] }
        return rawTools.compactMap { raw in
            guard let name = raw["name"] as? String else { return nil }
            let desc = raw["description"] as? String ?? ""
            let schema = AnySendable.wrap(raw["inputSchema"]).dictionary ?? [:]
            return MCPTool(name: name, description: desc, inputSchema: schema)
        }
    }

    public func callTool(name: String, arguments: [String: Any]) async throws -> Any {
        try await initializeIfNeeded()
        return try await request(method: "tools/call", params: ["name": name, "arguments": arguments])
    }

    private func notification(method: String, params: [String: Any]) async throws {
        var envelope: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if !params.isEmpty { envelope["params"] = params }
        _ = try await post(envelope: envelope)
    }

    private func request(method: String, params: [String: Any]) async throws -> Any {
        let id = nextID
        nextID += 1
        var envelope: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if !params.isEmpty { envelope["params"] = params }
        let root = try await post(envelope: envelope)
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "MCP error"
            let lower = message.lowercased()
            if lower.contains("login") || lower.contains("auth") || lower.contains("unauthorized") || lower.contains("session") {
                throw SpliceError.authRequired("Splice MCP says the browser/session login is not valid for this download yet: \(message)", SpliceOfficialMCP.landing)
            }
            if lower.contains("credit") || lower.contains("quota") || lower.contains("license") || lower.contains("subscription") {
                throw SpliceError.downloadUnavailable("Splice MCP rejected the license/download request: \(message). This can happen when the MCP session is stale even if your account has credits; reconnect the official MCP login, then retry.")
            }
            throw SpliceError.badResponse(message)
        }
        if let result = root["result"] { return result }
        return root
    }

    private func post(envelope: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("2025-03-26", forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { req.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if !bearerToken.isEmpty { req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        req.timeoutInterval = 60

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SpliceError.badResponse("No HTTP response from MCP server.") }
        if let sid = Self.header("mcp-session-id", in: http) ?? Self.header("Mcp-Session-Id", in: http) { sessionID = sid }
        if http.statusCode == 401 || http.statusCode == 403 {
            let login = Self.authURL(from: http, body: data, endpoint: endpoint) ?? SpliceOfficialMCP.landing
            throw SpliceError.authRequired("Splice MCP needs browser login through the official remote MCP flow. Open Splice login, finish the browser sign-in, then retry. HTTP \(http.statusCode).", login)
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw SpliceError.badResponse("MCP HTTP \(http.statusCode): \(text)")
        }
        guard let obj = Self.parseMCPResponse(data: data) else {
            throw SpliceError.badResponse("Could not parse MCP response: \(String(data: data, encoding: .utf8) ?? "")")
        }
        return obj
    }

    private static func header(_ key: String, in http: HTTPURLResponse) -> String? {
        for (k, v) in http.allHeaderFields {
            if String(describing: k).lowercased() == key.lowercased() { return String(describing: v) }
        }
        return nil
    }

    private static func authURL(from http: HTTPURLResponse, body data: Data, endpoint: URL) -> URL? {
        let headerCandidates = ["location", "link", "www-authenticate", "WWW-Authenticate"]
        for key in headerCandidates {
            if let raw = header(key, in: http), let url = firstURL(in: raw) { return url }
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["authorization_url", "authorizationUrl", "auth_url", "authUrl", "login_url", "loginUrl", "url"] {
                if let raw = json[key] as? String, let url = URL(string: raw) { return url }
            }
            // Splice's remote MCP currently answers browser-login probes with
            // OAuth 2.0 protected-resource metadata, for example:
            // { "resource": "https://mcp.splice.com/mcp", "authorization_servers": ["https://mcp.splice.com"], ... }
            // That is not itself a login URL; it tells the MCP host where to discover
            // the authorization server metadata. Send the app to the authorization
            // server for discovery instead of falling back to a generic landing page.
            if let servers = json["authorization_servers"] as? [String],
               let raw = servers.first,
               let url = URL(string: raw) { return url }
            if let resource = json["resource"] as? String,
               resource == endpoint.absoluteString { return SpliceOfficialMCP.authorizationServer }
            if let error = json["error"] as? [String: Any] {
                for key in ["authorization_url", "authorizationUrl", "auth_url", "authUrl", "login_url", "loginUrl", "url"] {
                    if let raw = error[key] as? String, let url = URL(string: raw) { return url }
                }
                if let servers = error["authorization_servers"] as? [String],
                   let raw = servers.first,
                   let url = URL(string: raw) { return url }
            }
        }
        return SpliceOfficialMCP.authorizationServer
    }

    private static func firstURL(in text: String) -> URL? {
        let pattern = #"https?://[^\s<>\"]+"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var raw = ns.substring(with: match.range)
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\",;'<>))"))
        return URL(string: raw)
    }

    private static func parseMCPResponse(data: Data) -> [String: Any]? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { continue }
            if let data = payload.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
        }
        return nil
    }
}

// MARK: - Response parsing

extension SpliceClient {
    private static func samples(fromToolResult result: Any) -> [SpliceSample] {
        var parsed: [SpliceSample] = []
        collectSamples(result, into: &parsed)
        if parsed.isEmpty {
            for text in textBlocks(from: result) {
                parsed.append(contentsOf: samples(fromText: text))
            }
        }
        var seen = Set<String>()
        return parsed.filter { seen.insert($0.id).inserted }
    }

    private static func collectSamples(_ value: Any, into samples: inout [SpliceSample]) {
        if let dict = value as? [String: Any] {
            if let sample = sample(from: dict) { samples.append(sample) }
            for child in dict.values { collectSamples(child, into: &samples) }
        } else if let array = value as? [Any] {
            for child in array { collectSamples(child, into: &samples) }
        }
    }

    private static func sample(from dict: [String: Any]) -> SpliceSample? {
        let name = string(dict, ["name", "title", "displayName", "display_name", "filename", "fileName"])
        let id = string(dict, ["id", "assetId", "asset_id", "sampleId", "sample_id", "soundId", "sound_id", "uuid"])
            ?? name
        guard let name, let id else { return nil }
        let bpm = int(dict, ["bpm", "tempo"])
        let key = string(dict, ["key", "musicalKey", "musical_key"])
        let preview = url(dict, ["previewURL", "previewUrl", "preview_url", "audioPreviewUrl", "audio_preview_url", "preview", "audio", "audio_url", "mp3", "ogg", "stream_url", "streamUrl"])
        let page = url(dict, ["url", "pageURL", "pageUrl", "page_url", "permalink", "splice_url", "spliceUrl", "web_url", "webUrl"])
        let download = url(dict, ["downloadURL", "downloadUrl", "download_url", "fileURL", "fileUrl", "file_url", "download", "asset_url", "assetUrl"])
        let local = url(dict, ["path", "filePath", "file_path", "localPath", "local_path"])
        let artwork = url(dict, ["artworkURL", "artworkUrl", "artwork_url", "imageURL", "imageUrl", "image_url", "coverURL", "coverUrl", "cover_url", "thumbnail", "thumbnail_url", "thumbnailUrl"])
        let waveform = url(dict, ["waveformURL", "waveformUrl", "waveform_url", "waveform", "waveform_image", "waveformImage"] )
        let tags = stringArray(dict, ["tags", "labels", "genres", "instruments", "categories", "descriptors"])
        let pack = string(dict, ["pack", "packName", "pack_name", "collection", "collectionName", "samplePack", "sample_pack"])
        let creator = string(dict, ["creator", "creatorName", "creator_name", "artist", "author", "vendor", "label"])
        let instrument = string(dict, ["instrument", "instrumentName", "instrument_name", "category"])
        let type = string(dict, ["type", "soundType", "sound_type", "assetType", "asset_type", "kind"])
        let duration = double(dict, ["duration", "durationSeconds", "duration_seconds", "length", "seconds"])
        var raw = dict.compactMapValues { value -> String? in
            if let s = value as? String { return s }
            if let n = value as? NSNumber { return n.stringValue }
            return nil
        }
        // Hide the raw UUID from the user-facing card, but preserve it for the
        // official MCP download/license tool. Some MCP responses use `uuid`,
        // `assetId`, or nested-ish string fields instead of `asset_uuid`.
        if raw["asset_uuid"] == nil {
            let rawUUID = string(dict, ["asset_uuid", "assetUUID", "assetId", "asset_id", "uuid", "id", "sampleId", "sample_id", "soundId", "sound_id"])
            if let uuid = validAssetUUID(rawUUID)
                ?? firstUndashedAssetUUID(in: rawUUID ?? "")
                ?? raw.values.compactMap({ firstAssetUUID(in: $0) ?? firstUndashedAssetUUID(in: $0) }).first
                ?? [page, preview, download].compactMap({ url in
                    guard let url else { return nil }
                    return assetUUID(fromSplicePageURL: url)
                }).first {
                raw["asset_uuid"] = uuid
            }
        }
        return SpliceSample(id: id, name: name, bpm: bpm, key: key, previewURL: preview,
                            pageURL: page, downloadURL: download, localFileURL: local,
                            artworkURL: artwork, waveformURL: waveform, packName: pack,
                            creatorName: creator, instrument: instrument, soundType: type,
                            durationSeconds: duration, tags: tags, raw: raw)
    }

    private static func samples(fromText text: String) -> [SpliceSample] {
        if let json = balancedJSON(in: text), let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            return samples(fromToolResult: obj)
        }

        let markdownSamples = samplesFromMarkdownSummary(text)
        if !markdownSamples.isEmpty { return markdownSamples }

        var out: [SpliceSample] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = cleanedMarkdownLine(rawLine)
            guard !line.isEmpty else { continue }
            // Do not turn metadata-only lines into fake samples. Older builds showed
            // rows named “BPM: 128 | Duration…” and separate rows named “Link: …”,
            // which made the browser look like a debug dump and disabled preview.
            if isSpliceMetadataLine(line) { continue }
            if line.count > 3, line.range(of: "sample|loop|kick|snare|hat|bass|vocal|fx|build|drop|lead|perc|808", options: [.regularExpression, .caseInsensitive]) != nil {
                let page = firstSpliceTextURL(in: line)
                let name = stripURLs(line)
                var raw: [String: String] = [:]
                if let page {
                    raw["page_url"] = page.absoluteString
                    if let uuid = SpliceSample.assetUUID(fromSpliceURL: page) { raw["asset_uuid"] = uuid }
                }
                let identity = raw["asset_uuid"] ?? page?.absoluteString ?? "text-\(out.count)-\(abs(line.hashValue))"
                out.append(SpliceSample(id: identity, name: name.isEmpty ? "Splice sample" : name, pageURL: page, tags: [], raw: raw))
            }
        }
        return out
    }

    private struct MarkdownSampleDraft {
        var name: String?
        var assetUUID: String?
        var bpm: Int?
        var key: String?
        var duration: Double?
        var type: String?
        var pack: String?
        var creator: String?
        var instrument: String?
        var page: URL?
        var preview: URL?
        var download: URL?
        var tags: [String] = []

        var hasContent: Bool {
            name != nil || assetUUID != nil || bpm != nil || key != nil || duration != nil || type != nil || pack != nil || creator != nil || instrument != nil || page != nil || preview != nil || download != nil || !tags.isEmpty
        }

        var hasRealSample: Bool {
            if let name, !name.isEmpty { return true }
            if let assetUUID, !assetUUID.isEmpty { return true }
            return page != nil || preview != nil || download != nil
        }

        func makeSample(index: Int) -> SpliceSample? {
            guard hasRealSample else { return nil }
            let fallbackType = type?.capitalized ?? "Sample"
            let fallbackTempo = bpm.map { " \($0) BPM" } ?? ""
            let fallbackPack = pack.map { " · \($0)" } ?? ""
            let displayName = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? "Splice \(fallbackType)\(fallbackTempo)\(fallbackPack)"
            let identity = assetUUID ?? page?.absoluteString ?? preview?.absoluteString ?? download?.absoluteString ?? "markdown-\(index)-\(displayName)"
            var raw: [String: String] = [:]
            if let assetUUID { raw["asset_uuid"] = assetUUID }
            if let page { raw["page_url"] = page.absoluteString }
            if let preview { raw["preview_url"] = preview.absoluteString }
            if let download { raw["download_url"] = download.absoluteString }
            return SpliceSample(id: identity,
                                name: displayName,
                                bpm: bpm,
                                key: key,
                                previewURL: preview,
                                pageURL: page,
                                downloadURL: download,
                                packName: pack,
                                creatorName: creator,
                                instrument: instrument,
                                soundType: type,
                                durationSeconds: duration,
                                tags: Array(NSOrderedSet(array: tags).compactMap { $0 as? String }),
                                raw: raw)
        }
    }

    private static func samplesFromMarkdownSummary(_ text: String) -> [SpliceSample] {
        var drafts: [MarkdownSampleDraft] = []
        var current = MarkdownSampleDraft()

        func flush() {
            if current.hasRealSample { drafts.append(current) }
            current = MarkdownSampleDraft()
        }

        for raw in text.components(separatedBy: .newlines) {
            let line = cleanedMarkdownLine(raw)
            if line.isEmpty { continue }
            let lower = line.lowercased()
            if isSpliceHeaderOrNoiseLine(line) { continue }

            // Splice's remote MCP often returns markdown like:
            // ### 1. Kick.wav
            // Pack: Foo by Bar · loop
            // BPM: 128 | Duration: 0:15 | Type: loop
            // Tags: drums, build
            // Asset UUID: ...
            // Link: https://splice.com/sounds/sample/...
            // Keep all of those as one card. Only a new numbered heading starts
            // the next sample; metadata rows should never become their own card.
            if isMarkdownSampleHeading(line) {
                if current.hasRealSample { flush() }
                current.name = sampleNameFromHeading(line)
                continue
            }

            if current.hasRealSample || isLineLikelySampleMetadata(line) {
                parseMetadataLine(line, into: &current)
                continue
            }

            // Fallback for non-standard MCP prose: only turn a line into a sample
            // when it actually looks like a sample, not a section title.
            if lower.range(of: #"\.(wav|aif|aiff|mp3|m4a|flac|ogg)\b|\b(kick|snare|hat|loop|sample|vocal|fx|build|drop|808|bass)\b"#, options: .regularExpression) != nil {
                current.name = stripURLs(line)
            }
        }
        flush()

        return drafts.enumerated().compactMap { index, draft in draft.makeSample(index: index) }
    }

    private static func parseMetadataLine(_ line: String, into draft: inout MarkdownSampleDraft) {
        let normalized = line.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = normalized.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for part in parts.isEmpty ? [normalized] : parts {
            parseMetadataPart(part, into: &draft)
        }
    }

    private static func parseMetadataPart(_ part: String, into draft: inout MarkdownSampleDraft) {
        let cleaned = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let lower = cleaned.lowercased()

        if let url = firstSpliceTextURL(in: cleaned) {
            if lower.contains("preview") || lower.contains("stream") || lower.contains("audio") { draft.preview = url }
            else if lower.contains("download") || lower.contains("file") { draft.download = url }
            else { draft.page = url }

            // Splice page URLs often contain the asset identifier in the path:
            // /sounds/sample/<32-hex-or-uuid>/<slug>. Keep that as hidden
            // metadata for official MCP preview/download calls, but never show it
            // in the browser card.
            if draft.assetUUID == nil, let uuid = assetUUID(fromSplicePageURL: url) {
                draft.assetUUID = uuid
            }
        }

        let value: (String) -> String? = { label in
            let pattern = "(?i)^" + NSRegularExpression.escapedPattern(for: label) + "\\s*[:：]\\s*(.+)$"
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            let ns = cleaned as NSString
            guard let m = re.firstMatch(in: cleaned, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
            return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let v = value("asset uuid") ?? value("asset id") ?? value("uuid") ?? value("id") {
            if let uuid = validAssetUUID(v) ?? firstAssetUUID(in: v) ?? firstUndashedAssetUUID(in: v) {
                draft.assetUUID = uuid
            } else if let url = firstSpliceTextURL(in: v) {
                // Some Splice MCP replies label a page URL as "Asset UUID".
                // Do not pass that URL into an asset_uuid argument; the MCP
                // schema requires a real UUID and rejects page links. Instead,
                // parse the hidden asset UUID from the page URL when Splice
                // includes it in /sounds/sample/<asset>/<slug>.
                draft.page = url
                if let uuid = assetUUID(fromSplicePageURL: url) { draft.assetUUID = uuid }
            }
            return
        }
        if let v = value("name") ?? value("title") ?? value("sample") ?? value("sound") { draft.name = stripURLs(v); return }
        if let v = value("pack") ?? value("collection") {
            let noURL = stripURLs(v)
            let parts = noURL.components(separatedBy: " by ")
            draft.pack = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            if parts.count > 1 { draft.creator = parts.dropFirst().joined(separator: " by ").trimmingCharacters(in: .whitespacesAndNewlines) }
            return
        }
        if let v = value("creator") ?? value("artist") ?? value("label") ?? value("vendor") { draft.creator = stripURLs(v); return }
        if let v = value("instrument") { draft.instrument = stripURLs(v); return }
        if let v = value("type") ?? value("sound type") ?? value("kind") { draft.type = stripURLs(v).lowercased(); return }
        if let v = value("key") { draft.key = stripURLs(v); return }
        if let v = value("tags") ?? value("genre") ?? value("genres") {
            draft.tags.append(contentsOf: splitTags(stripURLs(v)))
            return
        }
        if let v = value("bpm") ?? value("tempo") {
            draft.bpm = Int(v.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression))
            return
        }
        if let v = value("duration") ?? value("length") {
            draft.duration = durationSeconds(from: v)
            return
        }

        // Compact subtitle rows from Splice MCP often look like
        // "Sample Tools by Cr2 · loop" or "Audentity Records · loop".
        if draft.pack == nil && !cleaned.contains(":") && (lower.contains(" · ") || lower.contains(" by ")) {
            let segments = cleaned.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if let first = segments.first {
                let byParts = first.components(separatedBy: " by ")
                draft.pack = byParts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                if byParts.count > 1 { draft.creator = byParts.dropFirst().joined(separator: " by ").trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            if segments.count > 1 { draft.type = segments[1].lowercased() }
            return
        }

        if draft.name == nil && !isSpliceMetadataLine(cleaned) && cleaned.range(of: "splice.com", options: .caseInsensitive) == nil {
            draft.name = stripURLs(cleaned)
        }
    }

    private static func cleanedMarkdownLine(_ raw: String) -> String {
        // IMPORTANT: strip the bold/italic markers (** / __) BEFORE removing a
        // leading bullet. Splice's results put each field as `**Label:** value`.
        // If we strip a single leading bullet first, `**Asset UUID:**` loses only
        // one `*`, then `**`-removal leaves a stray leading `*` ("*Asset UUID:"),
        // which breaks the anchored `^asset uuid:` matcher — so the asset UUID was
        // never parsed and every download failed with "can't fetch the UUID".
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[-*•]+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sampleNameFromHeading(_ line: String) -> String {
        line.replacingOccurrences(of: #"^\d+[.)]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMarkdownSampleHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^\d+[.)]\s+.+\.(wav|aif|aiff|mp3|m4a|flac|ogg)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || trimmed.range(of: #"^\d+[.)]\s+.+"#, options: .regularExpression) != nil && trimmed.lowercased().contains("sample") == false
    }

    private static func isLineLikelySampleMetadata(_ line: String) -> Bool {
        let lower = line.lowercased()
        return isSpliceMetadataLine(line)
            || lower.contains(" · loop")
            || lower.contains(" · one-shot")
            || lower.contains(" by ")
            || lower.contains("asset uuid")
            || lower.contains("splice.com/sounds/sample")
    }

    private static func isSpliceHeaderOrNoiseLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("search results")
            || lower.hasPrefix("results for")
            || lower.hasPrefix("here are")
            || lower == "samples"
            || lower == "search results"
    }

    private static func splitTags(_ text: String) -> [String] {
        text.replacingOccurrences(of: "#", with: "")
            .components(separatedBy: CharacterSet(charactersIn: ",/|·"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count < 32 }
    }

    private static func stripURLs(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r-–—|"))
    }

    private static func isSpliceMetadataLine(_ line: String) -> Bool {
        line.lowercased().range(of: #"^(asset uuid|asset id|uuid|id|bpm|tempo|duration|length|type|pack|creator|label|artist|instrument|key|link|url|preview|download|tags|genre|genres)\s*:"#, options: .regularExpression) != nil
    }


    private static func firstSpliceTextURL(in text: String) -> URL? {
        let pattern = #"https?://[^\s<>\"]+"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var raw = ns.substring(with: match.range)
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\",;'<>))"))
        return URL(string: raw)
    }


    private static func firstCapturedUUID(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else { return nil }
        let captured = ns.substring(with: match.range(at: 1))
        return validAssetUUID(captured) ?? firstAssetUUID(in: captured) ?? firstUndashedAssetUUID(in: captured)
    }

    private static func validAssetUUID(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " `\"'"))
        if trimmed.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil {
            return trimmed.lowercased()
        }
        return undashedHexToUUID(trimmed)
    }

    private static func firstAssetUUID(in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#) else { return nil }
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range).lowercased()
    }

    private static func firstUndashedAssetUUID(in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])"#) else { return nil }
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return undashedHexToUUID(ns.substring(with: match.range))
    }

    private static func undashedHexToUUID(_ text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: " `\"'/"))
        guard cleaned.range(of: #"^[0-9a-fA-F]{32}$"#, options: .regularExpression) != nil else { return nil }
        let lower = cleaned.lowercased()
        let chars = Array(lower)
        func part(_ start: Int, _ end: Int) -> String { String(chars[start..<end]) }
        return "\(part(0, 8))-\(part(8, 12))-\(part(12, 16))-\(part(16, 20))-\(part(20, 32))"
    }

    private static func assetUUID(fromSplicePageURL url: URL) -> String? {
        SpliceSample.assetUUID(fromSpliceURL: url)
    }

    private static func durationSeconds(from text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
            if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        }
        let numeric = cleaned.replacingOccurrences(of: #"[^0-9.]"#, with: "", options: .regularExpression)
        return Double(numeric)
    }

    private static func textBlocks(from value: Any) -> [String] {
        var out: [String] = []
        func walk(_ v: Any) {
            if let d = v as? [String: Any] {
                if (d["type"] as? String) == "text", let text = d["text"] as? String { out.append(text) }
                for child in d.values { walk(child) }
            } else if let a = v as? [Any] { a.forEach { walk($0) } }
            else if let s = v as? String { out.append(s) }
        }
        walk(value)
        return out
    }

    private static func localFileURL(fromToolResult result: Any) -> URL? {
        for candidate in urls(from: result) where candidate.isFileURL || candidate.scheme == nil {
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func remoteDownloadURL(fromToolResult result: Any) -> URL? {
        let candidates = urls(from: result).filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        // Prefer an actual file/presigned URL over a splice.com sample *page* link.
        // download_asset returns a presigned URL (often S3/CloudFront) embedded in a
        // sentence like "Here is your download link: https://… (expires in 1 hour)".
        if let presigned = candidates.first(where: { isLikelyDownloadURL($0) }) { return presigned }
        if let nonPage = candidates.first(where: { ($0.host?.lowercased().contains("splice.com") ?? false) == false }) { return nonPage }
        return candidates.first
    }

    /// Heuristic: does this URL look like a fetchable audio file / presigned link
    /// rather than a human-facing sample page?
    private static func isLikelyDownloadURL(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        if s.contains("x-amz-") || s.contains("amazonaws.com") || s.contains("cloudfront")
            || s.contains("googleapis") || s.contains("/download") || s.contains("response-content-disposition") {
            return true
        }
        let ext = url.pathExtension.lowercased()
        return ["wav", "mp3", "aif", "aiff", "flac", "ogg", "m4a", "zip"].contains(ext)
    }

    private static func isExplicitDownloadFailure(_ result: Any) -> Bool {
        let lower = shortText(from: result).lowercased()
        return lower.contains("download failed")
            || lower.contains("failed to download")
            || lower.contains("could not download")
            || lower.contains("unable to download")
            || lower.contains("please try again")
            || lower.contains("license failed")
            || lower.contains("licensing failed")
    }

    private static func urls(from value: Any) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()
        func push(_ u: URL) { if seen.insert(u.absoluteString).inserted { out.append(u) } }

        func addRaw(_ s: String) {
            let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\"'<>"))
            guard !trimmed.isEmpty else { return }
            // Whole-string case: a bare path or a bare URL with no surrounding prose.
            if trimmed.hasPrefix("/"), !trimmed.contains(" ") { push(URL(fileURLWithPath: trimmed)); return }
            if !trimmed.contains(" "), let u = URL(string: trimmed), u.scheme != nil { push(u) }
        }

        func extractEmbedded(_ s: String) {
            // 1) Markdown links: [label](https://…)
            if let re = try? NSRegularExpression(pattern: #"\((https?://[^)\s]+)\)"#) {
                let ns = s as NSString
                for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                    if let u = URL(string: ns.substring(with: m.range(at: 1))) { push(u) }
                }
            }
            // 2) Any bare http(s) URLs sitting inside a sentence. NSDataDetector is
            //    the most robust way to peel a URL out of prose (handles trailing
            //    punctuation, parentheses, etc.) — this is what makes presigned
            //    download_asset links actually resolve.
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                let ns = s as NSString
                for m in detector.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                    if let u = m.url, ["http", "https"].contains(u.scheme?.lowercased() ?? "") { push(u) }
                }
            }
        }

        func walk(_ v: Any) {
            if let s = v as? String { addRaw(s); extractEmbedded(s) }
            else if let d = v as? [String: Any] { d.values.forEach { walk($0) } }
            else if let a = v as? [Any] { a.forEach { walk($0) } }
        }
        walk(value)
        return out
    }

    private static func shortText(from result: Any) -> String {
        let text = textBlocks(from: result).joined(separator: " ")
        return text.count > 500 ? String(text.prefix(500)) + "…" : text
    }

    private static func string(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let s = dict[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private static func int(_ dict: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let i = dict[key] as? Int { return i }
            if let d = dict[key] as? Double { return Int(d.rounded()) }
            if let s = dict[key] as? String, let i = Int(s) { return i }
        }
        return nil
    }

    private static func double(_ dict: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            if let d = dict[key] as? Double { return d }
            if let i = dict[key] as? Int { return Double(i) }
            if let n = dict[key] as? NSNumber { return n.doubleValue }
            if let s = dict[key] as? String, let d = Double(s) { return d }
        }
        return nil
    }

    private static func url(_ dict: [String: Any], _ keys: [String]) -> URL? {
        for key in keys {
            if let s = dict[key] as? String {
                if s.hasPrefix("/") { return URL(fileURLWithPath: s) }
                if let u = URL(string: s) { return u }
            }
        }
        return nil
    }

    private static func stringArray(_ dict: [String: Any], _ keys: [String]) -> [String] {
        for key in keys {
            if let a = dict[key] as? [String] { return a }
            if let a = dict[key] as? [Any] { return a.compactMap { $0 as? String } }
            if let s = dict[key] as? String { return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        }
        return []
    }

    private static func balancedJSON(in text: String) -> String? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let open = text[start]
        let close: Character = open == "{" ? "}" : "]"
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < text.endIndex {
            let c = text[i]
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == open { depth += 1 }
                if c == close { depth -= 1; if depth == 0 { return String(text[start...i]) } }
            }
            i = text.index(after: i)
        }
        return nil
    }
}
