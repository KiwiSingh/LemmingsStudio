import Foundation
import Security

enum VisionAgentProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude = "Claude API"
    case localMLX = "Local MLX"
    case macBridge = "Mac AI Bridge (Coming Soon)"

    var id: String { rawValue }
    var isAvailable: Bool { self != .macBridge }
    var summary: String {
        switch self {
        case .claude: return "Default minimal-build backend. Uses your own Anthropic API key and the shared LemmingsStudio agent/tool layer."
        case .localMLX: return "Experimental full-fat backend using bundled or cached MLX models on Vision Pro."
        case .macBridge: return "Future local-network bridge for Ollama and other Mac-hosted models. UI stub only in v1.0."
        }
    }
}

struct VisionAgentRequest: Sendable {
    var prompt: String
    var projectContext: String
    var memoryContext: String
    var allowedTools: [String]
}

struct VisionAgentResponse: Sendable {
    var provider: VisionAgentProviderKind
    var rawText: String
    var plan: VisionAgentToolPlan
}

protocol VisionAgentBackend: Sendable {
    var kind: VisionAgentProviderKind { get }
    func complete(_ request: VisionAgentRequest) async throws -> VisionAgentResponse
}

enum VisionAgentBackendError: LocalizedError {
    case unavailable(String)
    case missingCredential
    case malformedResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .missingCredential: return "Claude API key is missing. Add it in the AI Agent panel first."
        case .malformedResponse: return "The agent backend returned an unreadable response."
        case .http(let code, let message): return "Agent request failed (HTTP \(code)): \(message)"
        }
    }
}

enum VisionCredentialStore {
    private static let service = "com.magmavance.LemmingsStudioVision"

    static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct VisionMacBridgeAgentBackend: VisionAgentBackend {
    let kind: VisionAgentProviderKind = .macBridge
    func complete(_ request: VisionAgentRequest) async throws -> VisionAgentResponse {
        throw VisionAgentBackendError.unavailable("Mac AI Bridge is coming soon. The visionOS protocol seam is reserved, but no macOS companion changes are included in this release.")
    }
}

extension VisionStudioModel {
    func loadClaudeCredentialState() {
        claudeAPIKeyDraft = VisionCredentialStore.get(account: "anthropic-api-key") ?? ""
    }

    func saveClaudeAPIKey() {
        let trimmed = claudeAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                VisionCredentialStore.remove(account: "anthropic-api-key")
                agentStatus = "Claude API key removed"
            } else {
                try VisionCredentialStore.set(trimmed, account: "anthropic-api-key")
                agentStatus = "Claude API key stored in Keychain"
            }
            statusMessage = agentStatus
        } catch {
            agentStatus = "Could not store Claude key: \(error.localizedDescription)"
            statusMessage = agentStatus
        }
    }

    func runSelectedAgent() {
        switch selectedAgentProvider {
        case .localMLX:
            runLocalMLXAgent()
        case .macBridge:
            agentStatus = "Mac AI Bridge is coming soon. No macOS companion changes are included in this release."
            statusMessage = agentStatus
        case .claude:
            runClaudeAgent()
        }
    }

    private func runClaudeAgent() {
        guard let key = VisionCredentialStore.get(account: "anthropic-api-key"), !key.isEmpty else {
            agentStatus = "Add and save a Claude API key first."
            statusMessage = agentStatus
            return
        }
        agentStatus = "Asking Claude…"
        statusMessage = agentStatus
        let request = VisionAgentRequest(
            prompt: agentPrompt,
            projectContext: semanticContextPreview(maxNodes: 72),
            memoryContext: memoryContextForAgents(),
            allowedTools: allowedMLXTools.sorted()
        )
        let backend = VisionClaudeAgentBackend(apiKey: key, model: claudeModel, maxTokens: claudeMaxTokens)
        Task {
            do {
                let response = try await backend.complete(request)
                lastAgentPlan = response.plan.toolCalls.isEmpty ? nil : response.plan
                agentStatus = response.plan.summary
                statusMessage = response.plan.toolCalls.isEmpty ? "Claude response ready" : "Claude tool plan awaiting confirmation"
                addMemoryEvent(kind: .aiNote, title: "Claude agent response", detail: response.plan.summary, tags: ["claude", "agent"])
            } catch {
                agentStatus = error.localizedDescription
                statusMessage = "Claude request failed"
            }
        }
    }
}
