import SwiftUI

// MARK: - Shared AI backend picker (used by Sound Agent and AI Producer)

struct AIBackendPicker: View {
    @Environment(AppState.self) private var app
    var showsOllamaModelPicker: Bool = true
    @AppStorage("ollamaModelTag") private var modelTag = ""
    @AppStorage("ollamaModelsDir") private var modelsDir = ""
    @State private var installed: Bool? = nil
    @State private var pull: PullProgress? = nil
    @State private var working = false
    @State private var note = ""

    var body: some View {
        @Bindable var appB = app
        VStack(alignment: .leading, spacing: 6) {
            Picker("AI engine", selection: $appB.aiBackend) {
                ForEach(AppState.AIBackendChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch app.aiBackend {
            case .claude:
                SecureField("Anthropic API key", text: $appB.claudeAPIKey)
                    .textFieldStyle(.roundedBorder)
                Text(app.claudeAPIKey.isEmpty ? "Paste a Claude API key to enable agentic AI and chat." : "Claude will drive Sound Agent, AI Producer, and Chat.")
                    .font(.caption2).foregroundStyle(.secondary)
            case .ollama:
                if showsOllamaModelPicker {
                    Picker("Agent model", selection: $modelTag) {
                        ForEach(OllamaCatalog.all) { Text($0.label).tag($0.tag) }
                    }
                    .onChange(of: modelTag) { _, _ in Task { await refresh() } }
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive")
                        TextField("Models directory", text: $modelsDir).textFieldStyle(.roundedBorder).font(.caption)
                    }
                    if installed == true {
                        Label("Agent model installed", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    } else if let p = pull {
                        ProgressView(value: p.fraction)
                        Text(p.status).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Button { Task { await download() } } label: { Label("Download agent model", systemImage: "arrow.down.circle") }
                            .disabled(working)
                    }
                } else {
                    Text("Chat uses its own chat-tuned Ollama model below. Agentic Sound/Producer models remain separate.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !note.isEmpty { Text(note).font(.caption2).foregroundStyle(.orange) }
        }
        .onAppear {
            if modelTag.isEmpty { modelTag = OllamaCatalog.recommendedForThisMac.tag }
            if modelsDir.isEmpty { modelsDir = OllamaClient.resolveModelsDirectory() ?? "" }
            if app.aiBackend == .ollama { Task { await refresh() } }
        }
    }

    private func client() -> OllamaClient { OllamaClient(modelsDirectory: modelsDir.isEmpty ? nil : modelsDir) }
    private func refresh() async {
        let yes = await client().isInstalled(modelTag)
        await MainActor.run { installed = yes }
    }
    private func download() async {
        await MainActor.run { working = true; note = ""; pull = PullProgress(status: "starting", completed: 0, total: 0) }
        do {
            try await client().pull(modelTag) { p in Task { @MainActor in self.pull = p } }
            await MainActor.run { installed = true; pull = nil }
        } catch {
            await MainActor.run { pull = nil; note = error.localizedDescription }
        }
        await MainActor.run { working = false }
    }
}


private struct OllamaChatModelPicker: View {
    @AppStorage("ollamaChatModelTag") private var modelTag = ""
    @AppStorage("ollamaModelsDir") private var modelsDir = ""
    @State private var installed: Bool?
    @State private var pull: PullProgress?
    @State private var working = false
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Chat model", selection: $modelTag) {
                ForEach(OllamaChatCatalog.all) { Text($0.label).tag($0.tag) }
            }
            .onChange(of: modelTag) { _, _ in Task { await refresh() } }

            if installed == true {
                Label("Chat model installed", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if let p = pull {
                ProgressView(value: p.fraction)
                Text(p.status).font(.caption2).foregroundStyle(.secondary)
            } else {
                Button { Task { await download() } } label: {
                    Label("Download chat model", systemImage: "arrow.down.circle")
                }.disabled(working)
            }
            if !note.isEmpty { Text(note).font(.caption2).foregroundStyle(.orange) }
        }
        .onAppear {
            if modelTag.isEmpty { modelTag = OllamaChatCatalog.recommendedForThisMac.tag }
            if modelsDir.isEmpty { modelsDir = OllamaClient.resolveModelsDirectory() ?? "" }
            Task { await refresh() }
        }
    }

    private func client() -> OllamaClient { OllamaClient(modelsDirectory: modelsDir.isEmpty ? nil : modelsDir) }
    private func refresh() async {
        let yes = await client().isInstalled(modelTag)
        await MainActor.run { installed = yes }
    }
    private func download() async {
        await MainActor.run { working = true; note = ""; pull = PullProgress(status: "starting", completed: 0, total: 0) }
        do {
            try await client().pull(modelTag) { p in Task { @MainActor in self.pull = p } }
            await MainActor.run { installed = true; pull = nil }
        } catch {
            await MainActor.run { pull = nil; note = error.localizedDescription }
        }
        await MainActor.run { working = false }
    }
}


private struct AssistantLogEntry: Identifiable {
    let id: Int
    let text: String
}


// MARK: - General chatbot

struct GeneralChatView: View {
    @Environment(AppState.self) private var app
    @State private var prompt = "I have tracks in C minor, E-flat major, and G minor. What key should I set the mashup to?"
    @State private var working = false
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chat").font(.headline).padding(.top, 8)
            Text("General production chat. Ask theory, mashup key, arrangement, mixing, workflow, or troubleshooting questions without editing the project.")
                .font(.caption).foregroundStyle(.secondary)

            AIBackendPicker(showsOllamaModelPicker: false)
            if app.aiBackend == .ollama { OllamaChatModelPicker() }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(app.generalChatLog) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.role)
                                .font(.caption.bold())
                                .foregroundStyle(entry.role == "You" ? Color.primary : Color.accentColor)
                            Text(entry.text)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary)
                                .textSelection(.enabled)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(entry.role == "You" ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(minHeight: 180)

            TextField("Ask a general question…", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .focused($promptFocused)
                .onChange(of: promptFocused) { _, focused in
                    UserDefaults.standard.set(focused, forKey: "LemmingsStudio.ProtectedTextEntryActive")
                }

            HStack {
                Button {
                    let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    prompt = ""
                    Task {
                        await MainActor.run { working = true }
                        await app.runGeneralChat(text)
                        await MainActor.run { working = false }
                    }
                } label: {
                    HStack {
                        if working { ProgressView().controlSize(.small) }
                        Label("Ask", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                .disabled(working || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.currentChatBackend().isOffline)

                if app.currentChatBackend().isOffline {
                    Text("Choose Ollama or enter a Claude API key.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .onDisappear { UserDefaults.standard.set(false, forKey: "LemmingsStudio.ProtectedTextEntryActive") }
    }
}

// MARK: - AI Producer (assistant chat)

struct AIAssistantView: View {
    @Environment(AppState.self) private var app
    @State private var prompt = "Add a 4-bar bassline to Sub Bass and automate the lead filter to open up over 8 bars"
    @State private var working = false

    private var recentAssistantLogEntries: [AssistantLogEntry] {
        app.assistantLog.suffix(40).enumerated().map { item in
            AssistantLogEntry(id: item.offset, text: item.element)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Producer").font(.headline).padding(.top, 8)
            Text("Edits MIDI, drums, devices, and automation across your project using the selected engine.")
                .font(.caption).foregroundStyle(.secondary)

            AIBackendPicker()

            TextField("Ask for an edit…", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...5)

            Button { Task { working = true; await app.runAssistant(prompt); working = false } } label: {
                HStack { if working { ProgressView().controlSize(.small) }
                    Label("Run", systemImage: "sparkles") }
            }.disabled(working || app.currentBackend().isOffline)

            if !app.assistantLog.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(recentAssistantLogEntries) { entry in
                        Text(entry.text)
                            .font(.system(size: 11, design: entry.text.hasPrefix("  •") ? .monospaced : .default))
                            .foregroundStyle(entry.text.hasPrefix("you:") ? Color.primary : (entry.text.hasPrefix("⚠️") ? Color.orange : Color.secondary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
    }
}

// MARK: - Instrument target (which synth the agent designs for)

struct InstrumentTargetView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Instrument Target").font(.headline).padding(.top, 8)
            if let t = app.selectedTrack {
                Text("Selected track: \(t.name)").font(.caption).foregroundStyle(.secondary)
                Text("Built-in & Vital can write presets. Serum/Massive/Omnisphere use AU hosting for live parameter control; if the AU is not loaded, Lemmings writes a handoff note instead of pretending it can edit proprietary preset files.")
                    .font(.caption2).foregroundStyle(.secondary)

                ForEach(KnownPlugins.synths) { synth in
                    targetRow(track: t, name: synth.name,
                              detail: synth.writablePresets ? "writable presets" : "host AU / handoff note")
                }
                if !app.discoveredPlugins.isEmpty {
                    Text("Detected Audio Units").font(.caption.bold()).padding(.top, 4)
                    ForEach(app.discoveredPlugins) { p in
                        targetRow(track: t, name: p.name, detail: p.manufacturer)
                    }
                }
                Button { app.scanPlugins() } label: { Label("Rescan Audio Units", systemImage: "arrow.clockwise") }
                    .padding(.top, 4)
            } else {
                Text("Select a track.").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
    }

    private func targetRow(track: Track, name: String, detail: String) -> some View {
        let selected = (track.pluginTargetID ?? "Built-in Analog") == name
        return Button {
            track.pluginTargetID = name
            app.engine.rebuild()
            app.pluginScanStatus = "Selected \(name). If it ships an Audio Unit, Lemmings will host it and drive exposed parameters live."
        } label: {
            HStack {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - MIDI controllers + recording

struct MIDIControllersView: View {
    @Environment(AppState.self) private var app
    @State private var importNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MIDI & Recording").font(.headline).padding(.top, 8)

            Text("Controllers").font(.caption.bold())
            if app.midiSourceNames.isEmpty {
                Text("No MIDI sources detected. Connect a controller and reopen.").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(app.midiSourceNames, id: \.self) { Text("• \($0)").font(.caption) }
            }

            Divider()
            Text("Inherit mappings").font(.caption.bold())
            Button { importNote = app.importDAWConfigs() } label: { Label("Import from Ableton / Logic", systemImage: "square.and.arrow.down") }
            Text("\(app.midiMap.mappings.count) mapping(s) loaded.").font(.caption2).foregroundStyle(.secondary)
            if !importNote.isEmpty { Text(importNote).font(.caption2).foregroundStyle(.secondary) }

            Divider()
            Text("Recording").font(.caption.bold())
            if let t = app.selectedTrack {
                @Bindable var track = t
                Toggle("Arm \(t.name) for recording", isOn: $track.armed)
                if t.kind == .audio {
                    Picker("Monitor", selection: Binding(get: { track.audioInputMonitorMode }, set: { app.setAudioInputMonitorMode($0, for: track) })) {
                        ForEach(AudioInputMonitorMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    Text(track.audioInputMonitorMode.helpText).font(.caption2).foregroundStyle(.secondary)
                    Picker("Input Device", selection: Binding(get: { track.audioInputDeviceUID ?? AudioRecorder.systemDefaultDeviceUID },
                                                              set: { app.setAudioInputDevice(for: track, uid: $0) })) {
                        ForEach(app.recorder.inputDevices) { device in
                            Text(device.name + " · \(device.channelCount)ch").tag(device.uid)
                        }
                    }
                    Picker("Input Channel", selection: $track.audioInputChannelIndex) {
                        let uid = track.audioInputDeviceUID ?? AudioRecorder.systemDefaultDeviceUID
                        ForEach(0..<app.recorder.channelCount(for: uid), id: \.self) { index in
                            Text(app.recorder.channelLabel(for: index, deviceUID: uid)).tag(index)
                        }
                    }
                }
                Text("Input: \(t.audioInputDeviceName) · \(app.recorder.inputName)").font(.caption2).foregroundStyle(.secondary)
                Button {
                    app.toggleRecord()
                } label: {
                    Label(app.recorder.isRecording ? "Stop recording" : "Record",
                          systemImage: app.recorder.isRecording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(app.recorder.isRecording ? Color.red : Color.primary)
                }
                if t.kind != .audio {
                    Text("Tip: add an “Audio (Recorded)” track to capture & play back mic input.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
    }
}
