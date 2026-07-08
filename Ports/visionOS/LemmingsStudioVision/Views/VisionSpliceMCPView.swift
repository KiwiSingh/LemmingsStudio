import SwiftUI

struct VisionSpliceMCPView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Splice MCP", systemImage: "waveform.badge.magnifyingglass")
                        .font(.title2.bold())
                    Text("Search, preview, license/download, store in-project, auto-fit, and map Splice sounds without leaving LemmingsStudio.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Fetch on Drop", isOn: $model.spliceMCP.fetchOnDropEnabled).toggleStyle(.switch)
                Toggle("Auto-stretch", isOn: $model.spliceMCP.autoStretchEnabled).toggleStyle(.switch)
                Button(model.spliceMCP.authenticated ? "Reconnect" : "Sign in to Splice", systemImage: "person.crop.circle.badge.checkmark") {
                    if model.spliceMCP.authenticated { model.refreshSpliceMCPTools() } else { model.beginSpliceLogin() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .lemmingsGlass()

            VStack(alignment: .leading, spacing: 12) {
                TextField("MCP endpoint", text: $model.spliceMCP.endpoint).textFieldStyle(.roundedBorder)
                HStack {
                    Label(model.spliceMCP.authenticated ? "Authenticated" : (model.spliceMCP.connected ? "Connected" : "Disconnected"), systemImage: model.spliceMCP.authenticated ? "checkmark.seal.fill" : "exclamationmark.triangle")
                    Spacer()
                    Text(model.spliceMCP.sessionID ?? "No MCP session").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text(model.spliceMCP.statusText).foregroundStyle(.secondary)
            }
            .padding()
            .lemmingsGlass()

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search Splice").font(.headline)
                    HStack {
                        TextField("e.g. dark lo-fi guitar loop around 80 BPM", text: $model.spliceSearchQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.runSpliceSearch() }
                        Button("Search", systemImage: "magnifyingglass") { model.runSpliceSearch() }
                            .buttonStyle(.borderedProminent)
                    }
                    if let draft = model.spliceMCP.lastSearchToolCall {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(draft.toolName).font(.headline.monospaced())
                            ForEach(draft.arguments.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack { Text(key).foregroundStyle(.secondary); Spacer(); Text(value).monospaced() }
                            }
                            Text(draft.safetyNote).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .lemmingsGlass(cornerRadius: 16)
                    }
                }
                .frame(maxWidth: 500)

                List(selection: $model.selectedSpliceSampleID) {
                    ForEach(model.spliceSearchResults) { sample in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(sample.title).font(.headline)
                                if sample.localFilePath != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                            HStack {
                                if let bpm = sample.bpm { Text(String(format: "%.0f BPM", bpm)) }
                                if let key = sample.key { Text(key) }
                                if let producer = sample.producer { Text(producer) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if !sample.tags.isEmpty { Text(sample.tags.prefix(6).joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary) }
                        }
                        .tag(sample.id)
                        .draggable(sample.id)
                    }
                }
                .overlay {
                    if model.spliceSearchResults.isEmpty {
                        ContentUnavailableView("Search the Splice catalog", systemImage: "waveform.badge.magnifyingglass", description: Text("Connect your Splice account, then describe the sound you need in plain language."))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .frame(minHeight: 300)

            HStack(spacing: 12) {
                Button("Preview", systemImage: "play.circle.fill") { model.previewSelectedSpliceSample() }
                Button("Download to Project", systemImage: "icloud.and.arrow.down") { model.fetchSelectedSpliceSample() }
                Button("Download + Arrangement", systemImage: "timeline.selection") { model.fetchSelectedSpliceSample(insertToArrangement: true) }
                    .buttonStyle(.borderedProminent)
                Button("Download + Sequencer", systemImage: "square.grid.4x3.fill") { model.fetchSelectedSpliceSample(mapToSequencer: true) }
                Spacer()
            }
            .disabled(model.spliceSearchResults.isEmpty)

            VStack(alignment: .leading, spacing: 8) {
                Text("Workflow status").font(.headline)
                Text("Official MCP authentication and tool discovery → natural-language catalog search → native preview → licensed download → project-local Samples/Splice storage + metadata sidecar → Arrangement insertion or Step Sequencer mapping. Auto-stretch uses source BPM metadata when available.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .lemmingsGlass()
        }
        .padding(24)
        .background(VisionThemeBackground(theme: model.visualTheme))
    }
}
