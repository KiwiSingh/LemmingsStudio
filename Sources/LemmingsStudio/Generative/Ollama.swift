import Foundation

// MARK: - Ollama integration
//
// A local, no-API-key backend for "describe a sound". It talks to a locally
// running Ollama daemon over its REST API (http://127.0.0.1:11434), can pull a
// model on demand with live progress, and — crucially — respects the model
// storage directory the user has configured (OLLAMA_MODELS), including a path
// on an external drive.
//
// Models offered are uncensored *and* multimodal (text + image), so the device
// won't refuse oddball sound descriptions, and the image hook is there for
// future "describe this from a picture" use. Tags are real entries from
// ollama.com/huihui_ai/qwen3-vl-abliterated (verified sizes: 2b/4b/8b/30b).

// MARK: Catalog

public struct OllamaModel: Identifiable, Hashable, Sendable {
    public var id: String { tag }
    public let tag: String
    public let label: String
    public let approxDownloadGB: Double
    public let minRAMGB: Double
    public let multimodal: Bool
    public let uncensored: Bool
}

public enum OllamaCatalog {
    /// All uncensored + multimodal (Qwen3-VL abliterated) — every size is
    /// "Text, Image" input on the Ollama registry.
    public static let all: [OllamaModel] = [
        OllamaModel(tag: "huihui_ai/qwen3-vl-abliterated:2b",
                    label: "Qwen3-VL 2B · uncensored · vision  (~1.9 GB)",
                    approxDownloadGB: 1.9, minRAMGB: 8,  multimodal: true, uncensored: true),
        OllamaModel(tag: "huihui_ai/qwen3-vl-abliterated:4b",
                    label: "Qwen3-VL 4B · uncensored · vision  (~3.3 GB)",
                    approxDownloadGB: 3.3, minRAMGB: 16, multimodal: true, uncensored: true),
        OllamaModel(tag: "huihui_ai/qwen3-vl-abliterated:8b",
                    label: "Qwen3-VL 8B · uncensored · vision  (~6.1 GB)",
                    approxDownloadGB: 6.1, minRAMGB: 24, multimodal: true, uncensored: true),
        OllamaModel(tag: "huihui_ai/qwen3-vl-abliterated:30b",
                    label: "Qwen3-VL 30B · uncensored · vision  (~20 GB)",
                    approxDownloadGB: 20,  minRAMGB: 48, multimodal: true, uncensored: true),
    ]

    /// Pick the largest model that fits *comfortably* next to the DAW + macOS.
    /// Heuristic: weights should stay under ~45% of unified memory, and never
    /// below a model's RAM floor. On an 8 GB Mac that's the 2B; 16 GB → 4B;
    /// 24 GB → 8B; 48 GB+ → 30B.
    public static func recommended(forRAMBytes ram: UInt64) -> OllamaModel {
        let gb = Double(ram) / 1_073_741_824.0
        let budget = gb * 0.45
        let affordable = all.filter { $0.minRAMGB <= gb && $0.approxDownloadGB <= budget }
        return affordable.max(by: { $0.approxDownloadGB < $1.approxDownloadGB }) ?? all[0]
    }

    public static var systemRAMBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }
    public static var recommendedForThisMac: OllamaModel { recommended(forRAMBytes: systemRAMBytes) }
}

/// Dedicated chat-tuned Ollama models. These are intentionally separate from the
/// multimodal/abliterated Sound Agent catalog so normal production Q&A gets a
/// conversational model with lower latency and cleaner prose.
public enum OllamaChatCatalog {
    public static let all: [OllamaModel] = [
        OllamaModel(tag: "qwen3:1.7b",
                    label: "Qwen3 1.7B · chat · lightweight",
                    approxDownloadGB: 1.4, minRAMGB: 6, multimodal: false, uncensored: false),
        OllamaModel(tag: "qwen3:4b",
                    label: "Qwen3 4B · chat · balanced",
                    approxDownloadGB: 2.6, minRAMGB: 8, multimodal: false, uncensored: false),
        OllamaModel(tag: "qwen3:8b",
                    label: "Qwen3 8B · chat · recommended",
                    approxDownloadGB: 5.2, minRAMGB: 16, multimodal: false, uncensored: false),
        OllamaModel(tag: "qwen3:14b",
                    label: "Qwen3 14B · chat · high quality",
                    approxDownloadGB: 9.3, minRAMGB: 32, multimodal: false, uncensored: false),
    ]

    public static func recommended(forRAMBytes ram: UInt64) -> OllamaModel {
        let gb = Double(ram) / 1_073_741_824.0
        if gb < 8 { return all[0] }
        if gb < 16 { return all[1] }
        if gb < 32 { return all[2] }
        return all[3]
    }

    public static var recommendedForThisMac: OllamaModel { recommended(forRAMBytes: ProcessInfo.processInfo.physicalMemory) }
}

// MARK: Errors / progress

public enum OllamaError: LocalizedError {
    case binaryNotFound
    case serverUnreachable
    case modelNotInstalled(String)
    case requestTimedOut(String)
    case pullFailed(String)
    case generateFailed(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:      return "Couldn't find the `ollama` binary. Install from ollama.com, or set its path in settings."
        case .serverUnreachable:   return "Couldn't reach the Ollama server on 127.0.0.1:11434."
        case .modelNotInstalled(let tag): return "The selected Ollama model `\(tag)` is not installed yet. Use Download model in the AI engine picker first, then ask again."
        case .requestTimedOut(let hint): return "The model did not respond in time. \(hint)"
        case .pullFailed(let s):   return "Model download failed: \(s)"
        case .generateFailed(let s): return "Generation failed: \(s)"
        }
    }
}

public struct PullProgress: Sendable {
    public var status: String        // e.g. "pulling manifest", "downloading"
    public var completed: Int64
    public var total: Int64
    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

// MARK: Client

public final class OllamaClient: @unchecked Sendable {

    public let host: URL
    /// Where models should live. Resolved at init; can be overridden by the UI.
    public var modelsDirectory: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 75
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    public init(host: URL = URL(string: "http://127.0.0.1:11434")!,
                modelsDirectory: String? = nil) {
        self.host = host
        self.modelsDirectory = modelsDirectory ?? OllamaClient.resolveModelsDirectory()
    }

    // MARK: Model-path resolution
    //
    // A Finder-launched app does NOT inherit the shell environment, so a plain
    // `export OLLAMA_MODELS=...` in .zshrc is invisible here. We therefore check,
    // in order: an explicit override, the process environment (works when run
    // via `swift run` or when set with `launchctl setenv`), `launchctl getenv`,
    // and finally the default ~/.ollama/models.

    public static func resolveModelsDirectory() -> String? {
        if let env = ProcessInfo.processInfo.environment["OLLAMA_MODELS"], !env.isEmpty {
            return (env as NSString).expandingTildeInPath
        }
        if let viaLaunchctl = launchctlGetenv("OLLAMA_MODELS"), !viaLaunchctl.isEmpty {
            return (viaLaunchctl as NSString).expandingTildeInPath
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dflt = home + "/.ollama/models"
        return dflt
    }

    private static func launchctlGetenv(_ key: String) -> String? {
        guard let out = try? runCapture("/bin/launchctl", ["getenv", key]) else { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Binary discovery

    public static func findBinary() -> String? {
        let candidates = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/bin/ollama",
            (FileManager.default.homeDirectoryForCurrentUser.path) + "/.ollama/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        // Last resort: ask the shell (works if launched from a terminal).
        if let which = try? Self.runCapture("/usr/bin/which", ["ollama"]) {
            let path = which.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    // MARK: Server lifecycle

    /// True if the daemon answers on the REST port.
    public func isServerRunning() async -> Bool {
        var req = URLRequest(url: host.appendingPathComponent("api/version"))
        req.timeoutInterval = 1.5
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    /// Ensure a server is up. If none is running, we start `ollama serve`
    /// ourselves with OLLAMA_MODELS pointed at the resolved directory — this is
    /// how the chosen (possibly external-drive) path is actually honoured for a
    /// GUI launch. Returns a human-readable note about what happened.
    @discardableResult
    public func ensureServer() async throws -> String {
        if await isServerRunning() {
            return "Using the Ollama server that's already running. New models download to *its* configured directory; to force \(modelsDirectory ?? "a custom path"), quit Ollama and let Lemmings start it, or run `launchctl setenv OLLAMA_MODELS <path>`."
        }
        guard let bin = Self.findBinary() else { throw OllamaError.binaryNotFound }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["serve"]
        var env = ProcessInfo.processInfo.environment
        if let dir = modelsDirectory {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            env["OLLAMA_MODELS"] = dir
        }
        proc.environment = env
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()

        // Poll for readiness (up to ~12s — cold starts touch the model dir).
        for _ in 0..<24 {
            if await isServerRunning() {
                return "Started Ollama with model directory: \(modelsDirectory ?? "default")."
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        throw OllamaError.serverUnreachable
    }

    // MARK: Installed models

    public func installedModels() async -> [String] {
        let req = URLRequest(url: host.appendingPathComponent("api/tags"))
        guard let (data, _) = try? await session.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    public func isInstalled(_ tag: String) async -> Bool {
        let installed = await installedModels()
        // Ollama may report "tag:latest"; match loosely.
        return installed.contains { $0 == tag || $0.hasPrefix(tag + ":") || tag.hasPrefix($0) }
    }

    // MARK: Pull (with streaming progress)

    /// Download a model. Streams NDJSON progress lines from /api/pull. Because
    /// `ensureServer()` started the daemon with our OLLAMA_MODELS, the bytes land
    /// in the resolved directory (external drive included).
    public func pull(_ tag: String, onProgress: @escaping @Sendable (PullProgress) -> Void) async throws {
        try await ensureServer()

        var req = URLRequest(url: host.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60 * 60
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": tag, "stream": true])

        let (bytes, response) = try await session.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw OllamaError.pullFailed("HTTP \(http.statusCode)")
        }

        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let err = obj["error"] as? String { throw OllamaError.pullFailed(err) }
            let status = obj["status"] as? String ?? ""
            let completed = (obj["completed"] as? Int64) ?? Int64((obj["completed"] as? Int) ?? 0)
            let total = (obj["total"] as? Int64) ?? Int64((obj["total"] as? Int) ?? 0)
            onProgress(PullProgress(status: status, completed: completed, total: total))
            if status == "success" { return }
        }
    }

    // MARK: Generate

    private func prepareModelForGeneration(_ model: String) async throws {
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedModel.isEmpty else { throw OllamaError.generateFailed("No Ollama model is selected. Pick a model in the AI engine picker and try again.") }
        try await ensureServer()

        // Do not silently pull from Chat/Agent generation. A first-run pull can
        // take many minutes and made the chatbot look like it never responded.
        // The AI engine picker already owns explicit download/progress UI.
        guard await isInstalled(selectedModel) else {
            throw OllamaError.modelNotInstalled(selectedModel)
        }
    }

    private static func isTransientGenerationError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return ns.code == NSURLErrorTimedOut ||
                ns.code == NSURLErrorCannotConnectToHost ||
                ns.code == NSURLErrorNetworkConnectionLost ||
                ns.code == NSURLErrorNotConnectedToInternet
        }
        let text = error.localizedDescription.lowercased()
        return text.contains("timed out") || text.contains("timeout") || text.contains("connection") || text.contains("server")
    }

    private func makeGenerateRequest(model: String,
                                     system: String,
                                     prompt: String,
                                     jsonOnly: Bool,
                                     temperature: Double,
                                     numPredict: Int,
                                     timeout: TimeInterval) throws -> URLRequest {
        var req = URLRequest(url: host.appendingPathComponent("api/generate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        var body: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "prompt": prompt,
            "system": system,
            "stream": false,
            "keep_alive": "10m",
            "options": [
                "temperature": temperature,
                // Keep generation bounded. JSON calls get more room because
                // device plans can legitimately be larger than chat replies.
                "num_predict": numPredict,
            ],
        ]
        if jsonOnly { body["format"] = "json" }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func makeChatRequest(model: String,
                                 system: String,
                                 prompt: String,
                                 temperature: Double,
                                 numPredict: Int,
                                 timeout: TimeInterval) throws -> URLRequest {
        var req = URLRequest(url: host.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = timeout
        let body: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt],
            ],
            "stream": false,
            "keep_alive": "10m",
            "options": [
                "temperature": temperature,
                "num_predict": numPredict,
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private func generateResponse(model: String,
                                  system: String,
                                  prompt: String,
                                  jsonOnly: Bool,
                                  temperature: Double,
                                  timeout: TimeInterval) async throws -> String {
        try await prepareModelForGeneration(model)

        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryNumPredict = jsonOnly ? 1200 : 700
        let req = try makeGenerateRequest(model: selectedModel,
                                          system: system,
                                          prompt: prompt,
                                          jsonOnly: jsonOnly,
                                          temperature: temperature,
                                          numPredict: primaryNumPredict,
                                          timeout: timeout)

        do {
            let first = try await withGenerationTimeout(seconds: timeout, hint: "Try again once the model is warm, or choose a smaller installed model in the AI engine picker.") {
                try await self.performGenerateRequest(req)
            }
            if !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jsonOnly {
                return first
            }

            // Some Qwen/Ollama runs return only an internal <think> block and
            // no final answer. buildfix196 stripped that to an apparent empty
            // response. Retry once with an explicit final-answer instruction so
            // the Chat tab recovers instead of showing a useless empty-result
            // warning. Keep the retry non-streaming and bounded.
            let retryPrompt = prompt + """

IMPORTANT: Your previous attempt produced no visible final answer. Reply now with a concise final answer only. Do not include <think> blocks, hidden reasoning, JSON, or markdown code fences.
"""
            let retryReq = try makeChatRequest(model: selectedModel,
                                               system: system + "\nReturn visible final text only. Do not emit <think> tags.",
                                               prompt: retryPrompt,
                                               temperature: min(temperature, 0.4),
                                               numPredict: 900,
                                               timeout: max(timeout, 180))
            let second = try await withGenerationTimeout(seconds: max(timeout, 180), hint: "The model produced no visible answer after a retry. Restart Ollama or choose a smaller installed model.") {
                try await self.performChatRequest(retryReq)
            }
            guard !second.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OllamaError.generateFailed("Ollama returned no visible answer after both /api/generate and /api/chat retries. Restart Ollama or choose a smaller/chat-tuned installed model.")
            }
            return second
        } catch {
            guard Self.isTransientGenerationError(error) else { throw error }

            // Ollama can be reachable before the runner/model is actually ready,
            // especially immediately after first launch or after a model pull.
            // Give the daemon a small grace period and retry once, but keep the
            // retry bounded so Chat never spins forever.
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            try await ensureServer()
            var retry = req
            retry.timeoutInterval = max(timeout, 180)
            return try await withGenerationTimeout(seconds: max(timeout, 180), hint: "Ollama stayed busy after a retry. Try a smaller model or restart Ollama from Settings.") {
                try await self.performGenerateRequest(retry)
            }
        }
    }

    private func withGenerationTimeout<T>(seconds: TimeInterval,
                                          hint: String,
                                          operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                let ns = UInt64(max(1, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw OllamaError.requestTimedOut(hint)
            }
            guard let value = try await group.next() else {
                throw OllamaError.requestTimedOut(hint)
            }
            group.cancelAll()
            return value
        }
    }

    private func cleanedModelText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Strip visible thinking. Some thinking models return only
        // <think>...</think>; buildfix196 surfaced that as an empty response.
        // Returning an empty string here is now intentional because
        // generateResponse(_:...) catches it and retries once with an explicit
        // visible-final-answer instruction.
        if let start = trimmed.range(of: "<think>"), let end = trimmed.range(of: "</think>", range: start.upperBound..<trimmed.endIndex) {
            let before = String(trimmed[..<start.lowerBound])
            let after = String(trimmed[end.upperBound...])
            let visible = (before + "\n" + after).trimmingCharacters(in: .whitespacesAndNewlines)
            if !visible.isEmpty { return visible }
            return ""
        }
        return trimmed
    }

    private func performGenerateRequest(_ req: URLRequest) async throws -> String {
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw OllamaError.generateFailed(msg)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OllamaError.generateFailed(String(data: data, encoding: .utf8) ?? "unparseable response")
        }
        if let err = root["error"] as? String, !err.isEmpty {
            throw OllamaError.generateFailed(err)
        }
        guard let text = root["response"] as? String else {
            throw OllamaError.generateFailed("no response field")
        }
        return cleanedModelText(text)
    }

    private func performChatRequest(_ req: URLRequest) async throws -> String {
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw OllamaError.generateFailed(msg)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OllamaError.generateFailed(String(data: data, encoding: .utf8) ?? "unparseable chat response")
        }
        if let err = root["error"] as? String, !err.isEmpty {
            throw OllamaError.generateFailed(err)
        }
        guard let message = root["message"] as? [String: Any], let text = message["content"] as? String else {
            throw OllamaError.generateFailed(String(data: data, encoding: .utf8) ?? "no chat message content")
        }
        return cleanedModelText(text)
    }

    /// Plain-text completion (no forced JSON) for the agent/assistant.
    public func generate(model: String, system: String, prompt: String) async throws -> String {
        try await generateResponse(model: model, system: system, prompt: prompt, jsonOnly: false, temperature: 0.7, timeout: 180)
    }

    /// Ask the model for a single JSON object. We pass `format: "json"` so even a
    /// small model is nudged toward valid JSON; the caller still rescues with a
    /// balanced-brace extractor.
    public func generateJSON(model: String, system: String, prompt: String) async throws -> String {
        try await generateResponse(model: model, system: system, prompt: prompt, jsonOnly: true, temperature: 0.6, timeout: 240)
    }

    // MARK: Process helper

    @discardableResult
    static func runCapture(_ path: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
