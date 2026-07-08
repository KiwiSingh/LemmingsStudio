import Foundation

#if canImport(MLXVLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace) && canImport(Tokenizers)
import MLXVLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

actor VisionMLXLocalRuntime {
    static let shared = VisionMLXLocalRuntime()
    private var container: ModelContainer?
    private var loadedRepository: String?

    func load(repository: String, bundledDirectoryName: String?) async throws {
        if loadedRepository == repository, container != nil { return }

        let next: ModelContainer
        if let bundledDirectoryName,
           let bundledURL = Self.bundledModelURL(directoryName: bundledDirectoryName) {
            next = try await VLMModelFactory.shared.loadContainer(
                from: bundledURL,
                using: #huggingFaceTokenizerLoader()
            )
        } else {
            let configuration = ModelConfiguration(id: repository)
            next = try await VLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration
            )
        }
        try Task.checkCancellation()
        container = next
        loadedRepository = repository
    }

    private static func bundledModelURL(directoryName: String) -> URL? {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true) else { return nil }
        let candidate = root.appendingPathComponent(directoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: candidate.appendingPathComponent("config.json").path) else { return nil }
        return candidate
    }

    func generate(prompt: String, imageURLs: [URL], maxTokens: Int = 512) async throws -> String {
        guard let container else { throw VisionMLXLocalRuntimeError.modelNotLoaded }
        let parameters = GenerateParameters(maxTokens: max(32, min(2048, maxTokens)), repetitionPenalty: nil)
        let stream = try await container.perform { context in
            let userInput = imageURLs.isEmpty
                ? UserInput(prompt: prompt)
                : UserInput(prompt: prompt, images: imageURLs.map { .url($0) })
            let prepared = try await context.processor.prepare(input: userInput)
            return try MLXLMCommon.generate(input: prepared, parameters: parameters, context: context)
        }
        var text = ""
        for try await event in stream {
            try Task.checkCancellation()
            if case .chunk(let chunk) = event { text += chunk }
        }
        return text
    }

    func unload() {
        container = nil
        loadedRepository = nil
    }
}
#else
actor VisionMLXLocalRuntime {
    static let shared = VisionMLXLocalRuntime()
    func load(repository: String, bundledDirectoryName: String?) async throws { throw VisionMLXLocalRuntimeError.packageNotLinked }
    func generate(prompt: String, imageURLs: [URL], maxTokens: Int = 512) async throws -> String { throw VisionMLXLocalRuntimeError.packageNotLinked }
    func unload() {}
}
#endif

enum VisionMLXLocalRuntimeError: LocalizedError {
    case packageNotLinked
    case modelNotLoaded
    case noRepository
    var errorDescription: String? {
        switch self {
        case .packageNotLinked: return "MLX Swift LM is not linked into this build profile. Generate the Xcode project with the package-enabled project.yml and resolve packages in Xcode."
        case .modelNotLoaded: return "Load an MLX model before generating."
        case .noRepository: return "No MLX repository is configured for the selected preset."
        }
    }
}

extension VisionStudioModel {
    func loadSelectedMLXModel() {
        guard let install = mlxRuntime.modelInstalls.first(where: { $0.preset == mlxRuntime.selectedModel }) else {
            mlxRuntime.lastError = VisionMLXLocalRuntimeError.noRepository.localizedDescription
            return
        }
        mlxRuntime.phase = .resolving
        mlxRuntime.lastError = nil
        mlxRuntime.lastDryRunSummary = "Resolving \(install.repository)…"
        mlxLoadTask?.cancel()
        mlxLoadTask = Task {
            do {
                self.mlxRuntime.phase = .loading
                try await VisionMLXLocalRuntime.shared.load(
                    repository: install.repository,
                    bundledDirectoryName: install.preset.bundledDirectoryName
                )
                if let index = self.mlxRuntime.modelInstalls.firstIndex(where: { $0.preset == self.mlxRuntime.selectedModel }) {
                    self.mlxRuntime.modelInstalls[index].isInstalled = true
                }
                self.mlxRuntime.activeRepository = install.repository
                self.mlxRuntime.phase = .ready
                let bundled = install.preset.bundledDirectoryName.flatMap { name in
                    Bundle.main.resourceURL?
                        .appendingPathComponent("Models", isDirectory: true)
                        .appendingPathComponent(name, isDirectory: true)
                }
                let source = bundled.map { FileManager.default.fileExists(atPath: $0.path) } == true ? "bundled offline assets" : "runtime cache/network"
                self.mlxRuntime.lastDryRunSummary = "Loaded \(install.repository) from \(source) for local MLX VLM inference."
                self.statusMessage = "MLX model ready"
            } catch is CancellationError {
                self.mlxRuntime.phase = .cancelled
                self.statusMessage = "MLX model load cancelled"
            } catch {
                self.mlxRuntime.phase = .failed
                self.mlxRuntime.lastError = error.localizedDescription
                self.mlxRuntime.lastDryRunSummary = error.localizedDescription
                self.statusMessage = "MLX model load failed"
            }
            self.mlxLoadTask = nil
        }
    }

    func runLocalMLXAgent() {
        guard mlxRuntime.phase == .ready || mlxRuntime.phase == .awaitingConfirmation else {
            statusMessage = "Load the selected MLX model first."
            return
        }
        mlxRuntime.phase = .preparingContext
        mlxRuntime.lastRunStartedAt = Date()
        mlxRuntime.lastError = nil

        let graphText = mlxRuntime.allowProjectGraphContext ? semanticContextPreview(maxNodes: 72) : "Semantic project graph context disabled."
        let memoryText = memoryContextForAgents()
        let allowed = allowedMLXTools.sorted()
        let prompt = """
        You are the local LemmingsStudio visionOS production agent. Be concrete, technically honest, and project-aware.

        USER REQUEST:
        \(agentPrompt)

        PROJECT CONTEXT:
        \(graphText)

        LIVING PROJECT MEMORY:
        \(memoryText)

        ALLOWED TOOLS ONLY:
        \(allowed.joined(separator: ", "))

        Return useful production advice followed by exactly one machine-readable plan inside <tool_plan> tags using this JSON schema:
        {"summary":"brief intent","toolCalls":[{"tool":"allowedToolName","arguments":{"key":"value"}}]}

        Rules:
        - Never claim a DAW edit happened until a tool call has been confirmed and executed.
        - Use only allowed tool names.
        - Omit tool calls when advice alone is appropriate.
        - Keep numeric values conservative and within normal DAW ranges.
        - When a screenshot is attached, reason about only visible UI and do not invent hidden parameter states.
        """

        let screenshotURLs = mlxRuntime.allowVisionScreenshots ? mlxScreenshotContextURLs() : []
        agentStatus = "Running local MLX inference…"
        mlxRuntime.phase = .generating

        let selectedModel = mlxRuntime.selectedModel
        let maxTokens = mlxRuntime.maxOutputTokens
        let requiresConfirmation = mlxRuntime.requireConfirmationForTools
        mlxGenerationTask?.cancel()
        mlxGenerationTask = Task {
            do {
                let response = try await VisionMLXLocalRuntime.shared.generate(prompt: prompt, imageURLs: screenshotURLs, maxTokens: maxTokens)
                let plan = VisionMLXToolPlanParser().parse(response: response, model: selectedModel, allowedTools: self.allowedMLXTools, requiresConfirmation: requiresConfirmation)
                self.mlxRuntime.lastResponse = response
                self.mlxRuntime.lastRunFinishedAt = Date()
                self.lastAgentPlan = plan.toolCalls.isEmpty ? nil : plan
                self.agentStatus = plan.summary
                self.mlxRuntime.phase = plan.toolCalls.isEmpty ? .ready : .awaitingConfirmation
                self.statusMessage = plan.toolCalls.isEmpty ? "MLX response ready" : "MLX tool plan awaiting confirmation"
                if self.mlxRuntime.autoUnloadAfterGeneration {
                    await VisionMLXLocalRuntime.shared.unload()
                    self.mlxRuntime.activeRepository = nil
                    if self.lastAgentPlan == nil { self.mlxRuntime.phase = .idle }
                }
            } catch is CancellationError {
                self.mlxRuntime.phase = .cancelled
                self.agentStatus = "MLX generation cancelled"
            } catch {
                self.mlxRuntime.phase = .failed
                self.mlxRuntime.lastError = error.localizedDescription
                self.agentStatus = error.localizedDescription
                self.statusMessage = "MLX inference failed"
            }
            self.mlxGenerationTask = nil
        }
    }

    func cancelMLXWork() {
        mlxLoadTask?.cancel()
        mlxGenerationTask?.cancel()
        mlxLoadTask = nil
        mlxGenerationTask = nil
        mlxRuntime.phase = .cancelled
        statusMessage = "MLX work cancelled."
    }

    func unloadMLXModel() {
        cancelMLXWork()
        Task {
            await VisionMLXLocalRuntime.shared.unload()
            await MainActor.run {
                self.mlxRuntime.activeRepository = nil
                self.mlxRuntime.phase = .idle
                self.statusMessage = "MLX model released from memory"
            }
        }
    }

    private func mlxScreenshotContextURLs() -> [URL] {
        guard let data = desktopBridge.editorJPEGData else { return [] }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LemmingsStudio-MLX", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("plugin-editor.jpg")
        do { try data.write(to: url, options: .atomic); return [url] } catch { return [] }
    }
}
