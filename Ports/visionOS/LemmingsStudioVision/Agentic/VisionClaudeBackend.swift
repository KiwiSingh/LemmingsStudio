import Foundation

struct VisionClaudeAgentBackend: VisionAgentBackend {
    let kind: VisionAgentProviderKind = .claude
    let apiKey: String
    let model: String
    let maxTokens: Int

    func complete(_ request: VisionAgentRequest) async throws -> VisionAgentResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VisionAgentBackendError.missingCredential
        }

        let system = """
        You are the LemmingsStudio visionOS production agent. Give concise, technically honest production guidance. You may propose DAW edits only through the supplied tool names. Never claim an edit happened until the user confirms and LemmingsStudio executes the tool plan.

        Return useful advice followed by exactly one machine-readable plan inside <tool_plan> tags using:
        {"summary":"brief intent","toolCalls":[{"tool":"allowedToolName","arguments":{"key":"value"}}]}
        Omit tool calls when advice alone is appropriate. Use only allowed tool names.
        """

        let userText = """
        USER REQUEST:
        \(request.prompt)

        PROJECT CONTEXT:
        \(request.projectContext)

        LIVING PROJECT MEMORY:
        \(request.memoryContext)

        ALLOWED TOOLS ONLY:
        \(request.allowedTools.joined(separator: ", "))
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": max(256, min(8192, maxTokens)),
            "system": system,
            "messages": [["role": "user", "content": userText]]
        ]
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown Claude API error"
            throw VisionAgentBackendError.http(code, message)
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [[String: Any]] else {
            throw VisionAgentBackendError.malformedResponse
        }
        let text = content.compactMap { item -> String? in
            guard (item["type"] as? String) == "text" else { return nil }
            return item["text"] as? String
        }.joined(separator: "\n")
        guard !text.isEmpty else { throw VisionAgentBackendError.malformedResponse }

        let parser = VisionMLXToolPlanParser()
        let plan = parser.parse(
            response: text,
            model: .custom,
            allowedTools: Set(request.allowedTools),
            requiresConfirmation: true
        )
        return VisionAgentResponse(provider: .claude, rawText: text, plan: plan)
    }
}
