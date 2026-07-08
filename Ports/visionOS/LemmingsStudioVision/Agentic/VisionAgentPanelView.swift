import SwiftUI

struct VisionAgentPanelView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Agent").font(.largeTitle.bold())
                    Text("One agentic tool layer, multiple inference backends. Claude is the default for the stable minimal build.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Run Agent", systemImage: "wand.and.stars") { model.runSelectedAgent() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedAgentProvider == .macBridge)
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Provider", selection: $model.selectedAgentProvider) {
                        ForEach(VisionAgentProviderKind.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(model.selectedAgentProvider.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    providerSettings
                }
                .padding(16)
                .lemmingsGlass(cornerRadius: 18)
            }

            TextEditor(text: $model.agentPrompt)
                .font(.system(.body, design: .rounded))
                .frame(minHeight: 120)
                .padding(8)
                .lemmingsGlass(cornerRadius: 18)

            Text(model.agentStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let plan = model.lastAgentPlan {
                Divider()
                Text(plan.summary).font(.headline)
                ForEach(plan.toolCalls) { call in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(call.tool).font(.headline.monospaced())
                        ForEach(call.arguments.keys.sorted(), id: \.self) { key in
                            Text("\(key): \(call.arguments[key] ?? "")")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .lemmingsGlass(cornerRadius: 16)
                }
                HStack {
                    Label("Requires confirmation", systemImage: "hand.raised")
                    Spacer()
                    Button("Reject", role: .destructive) { model.rejectMLXToolPlan() }
                    Button("Confirm & Apply", systemImage: "checkmark.circle") { model.executeConfirmedMLXToolPlan() }
                        .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .padding(28)
        .background(VisionThemeBackground(theme: model.visualTheme))
        .onAppear {
            model.ensureSpatialScene()
            model.loadClaudeCredentialState()
        }
    }

    @ViewBuilder
    private var providerSettings: some View {
        @Bindable var model = model
        switch model.selectedAgentProvider {
        case .claude:
            SecureField("Anthropic API key", text: $model.claudeAPIKeyDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Claude model", text: $model.claudeModel)
                    .textFieldStyle(.roundedBorder)
                Stepper("Max \(model.claudeMaxTokens) tokens", value: $model.claudeMaxTokens, in: 256...8192, step: 256)
                Button("Save Key", systemImage: "key.fill") { model.saveClaudeAPIKey() }
            }
        case .localMLX:
            Picker("Model", selection: $model.selectedMLXModel) {
                ForEach(VisionMLXModelPreset.allCases) { preset in Text(preset.rawValue).tag(preset) }
            }
            .pickerStyle(.menu)
            Text(model.selectedMLXModel.recommendedUse).font(.caption).foregroundStyle(.secondary)
            Text("Local MLX remains the experimental full-fat build path.")
                .font(.caption).foregroundStyle(.secondary)
        case .macBridge:
            ContentUnavailableView(
                "Mac AI Bridge — Coming Soon",
                systemImage: "desktopcomputer.and.arrow.down",
                description: Text("The visionOS provider seam is reserved for Ollama and other Mac-hosted models, but no macOS build changes are included yet.")
            )
        }
    }
}
