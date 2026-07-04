import Foundation

// MARK: - Unified LLM backend
//
// One small surface the sound-agent and AI assistant share, so "the model the
// user selected" (Claude API key or local Ollama) drives every AI feature
// uniformly. Offline raises so callers can fall back to deterministic logic.

public enum LLMBackend: Sendable {
    case offline
    case claude(apiKey: String)
    case ollama(client: OllamaClient, model: String)

    public var isOffline: Bool { if case .offline = self { return true }; return false }
    public var label: String {
        switch self {
        case .offline: return "Offline"
        case .claude: return "Claude API"
        case .ollama(_, let m): return "Ollama (\(m))"
        }
    }
}

public enum LLMError: LocalizedError {
    case offline, badResponse(String)
    public var errorDescription: String? {
        switch self {
        case .offline: return "No AI backend selected."
        case .badResponse(let s): return "Model response error: \(s)"
        }
    }
}

public struct LLMClient {
    public var backend: LLMBackend
    public init(backend: LLMBackend) { self.backend = backend }

    /// Complete a prompt. `jsonOnly` nudges the backend toward a single JSON object.
    public func complete(system: String, user: String, jsonOnly: Bool) async throws -> String {
        switch backend {
        case .offline:
            throw LLMError.offline
        case .ollama(let client, let model):
            return jsonOnly
                ? try await client.generateJSON(model: model, system: system, prompt: user)
                : try await client.generate(model: model, system: system, prompt: user)
        case .claude(let apiKey):
            return try await claude(apiKey: apiKey, system: system, user: user, jsonOnly: jsonOnly)
        }
    }

    private func claude(apiKey: String, system: String, user: String, jsonOnly: Bool) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 180
        let sys = jsonOnly ? system + "\nReply with ONLY a single JSON object. No prose, no code fences." : system
        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1500,
            "system": sys,
            "messages": [["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String
        else { throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "unparseable") }
        return text
    }
}
