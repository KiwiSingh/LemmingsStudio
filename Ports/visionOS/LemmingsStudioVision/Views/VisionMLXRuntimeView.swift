import SwiftUI

struct VisionMLXRuntimeView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Local MLX Runtime", systemImage: "brain.head.profile")
                        .font(.largeTitle.bold())
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(model.mlxRuntime.readinessSummary).font(.callout.monospaced())
                        Text(model.mlxRuntime.phase.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                }

                GroupBox("Runtime") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Model", selection: $model.mlxRuntime.selectedModel) {
                            ForEach(VisionMLXModelPreset.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Slider(value: $model.mlxRuntime.memoryBudgetGB, in: 3...32, step: 1)
                        Text("Memory budget target: \(Int(model.mlxRuntime.memoryBudgetGB)) GB").font(.caption.monospaced())
                        Stepper("Max output tokens: \(model.mlxRuntime.maxOutputTokens)", value: $model.mlxRuntime.maxOutputTokens, in: 128...2048, step: 128)
                        Toggle("Unload model after each generation", isOn: $model.mlxRuntime.autoUnloadAfterGeneration)
                        HStack {
                            Button("Load Model", systemImage: "square.and.arrow.down") { model.loadSelectedMLXModel() }
                            Button("Unload", systemImage: "eject") { model.unloadMLXModel() }
                            Button("Cancel", systemImage: "stop.circle") { model.cancelMLXWork() }
                        }
                    }.padding(.vertical, 6)
                }

                GroupBox("Agent Request") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $model.agentPrompt).frame(minHeight: 110)
                        HStack {
                            Button("Run Local Agent", systemImage: "sparkles") { model.runLocalMLXAgent() }
                                .buttonStyle(.borderedProminent)
                            Button("Dry Run Context", systemImage: "doc.text.magnifyingglass") { model.mlxRuntimeDryRun() }
                        }
                        Text(model.agentStatus).font(.callout).textSelection(.enabled)
                    }.padding(.vertical, 6)
                }

                if let plan = model.lastAgentPlan {
                    GroupBox("Proposed Tool Plan") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(plan.summary)
                            ForEach(plan.toolCalls) { call in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(call.tool).font(.headline.monospaced())
                                    Text(call.arguments.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " • ")).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Button("Confirm & Execute", systemImage: "checkmark.shield") { model.executeConfirmedMLXToolPlan() }
                                    .buttonStyle(.borderedProminent)
                                Button("Reject", role: .destructive) { model.rejectMLXToolPlan() }
                            }
                        }.padding(.vertical, 6)
                    }
                }

                GroupBox("Agent Lanes") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(VisionMLXAgentLane.allCases) { lane in
                            Button {
                                if model.mlxRuntime.enabledLanes.contains(lane) { model.mlxRuntime.enabledLanes.remove(lane) }
                                else { model.mlxRuntime.enabledLanes.insert(lane) }
                            } label: {
                                HStack {
                                    Image(systemName: model.mlxRuntime.enabledLanes.contains(lane) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading) {
                                        Text(lane.rawValue).font(.headline)
                                        Text(lane.defaultToolScope.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                }.padding().lemmingsGlass(cornerRadius: 18)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 6)
                }

                GroupBox("Context & Safety") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Include Semantic Project Graph", isOn: $model.mlxRuntime.allowProjectGraphContext)
                        Toggle("Attach current streamed plugin-editor frame when available", isOn: $model.mlxRuntime.allowVisionScreenshots)
                        Toggle("Require confirmation before tool execution", isOn: $model.mlxRuntime.requireConfirmationForTools)
                        Text(model.mlxRuntime.lastDryRunSummary).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if let error = model.mlxRuntime.lastError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    }.padding(.vertical, 6)
                }

                GroupBox("Last Raw Response") {
                    Text(model.mlxRuntime.lastResponse).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(24)
        }.background(VisionThemeBackground(theme: model.visualTheme))
    }
}
