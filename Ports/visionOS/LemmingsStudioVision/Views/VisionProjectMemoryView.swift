import SwiftUI

struct VisionProjectMemoryView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var title = ""
    @State private var detail = ""
    @State private var kind: VisionProjectMemoryEventKind = .mixDecision
    @State private var tags = ""
    @State private var pin = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    captureCard
                    contextCard
                    preferencesCard
                    eventsCard
                }
                .padding(26)
            }
            .background(VisionThemeBackground(theme: model.visualTheme))
            .navigationTitle("Living Project Memory")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Session Snapshot", systemImage: "camera.metering.matrix") { model.addSessionMemorySnapshot() }
                    Button("Compact", systemImage: "text.badge.checkmark") { model.compactProjectMemory() }
                }
            }
            .onAppear { model.ensureProjectMemory() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project memory for \(model.project.name)").font(.largeTitle.bold())
            Text("A durable memory layer for AI agents: decisions, rejected ideas, preferences, open issues, export notes, and session snapshots.")
                .foregroundStyle(.secondary)
            HStack {
                Label("\(model.project.memory?.events.count ?? 0) events", systemImage: "list.bullet.rectangle")
                Label("\(model.project.memory?.preferences.count ?? 0) preferences", systemImage: "heart.text.square")
                Label("\(model.project.memory?.unresolvedIssues.count ?? 0) open issues", systemImage: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .lemmingsGlass(cornerRadius: 26)
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Capture memory", systemImage: "square.and.pencil").font(.title2.bold())
            Picker("Kind", selection: $kind) {
                ForEach(VisionProjectMemoryEventKind.allCases) { item in
                    Label(item.rawValue, systemImage: item.symbolName).tag(item)
                }
            }
            .pickerStyle(.segmented)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Detail / evidence", text: $detail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            TextField("Tags, comma-separated", text: $tags)
                .textFieldStyle(.roundedBorder)
            Toggle("Pin this memory", isOn: $pin)
            Button("Add Memory", systemImage: "plus.circle.fill") {
                let parsedTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                model.addMemoryEvent(kind: kind, title: title.isEmpty ? kind.rawValue : title, detail: detail.isEmpty ? "Captured from Living Project Memory." : detail, tags: parsedTags, pin: pin)
                title = ""; detail = ""; tags = ""; pin = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .lemmingsGlass(cornerRadius: 26)
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agent context digest", systemImage: "brain.head.profile").font(.title2.bold())
            Toggle("Include memory in MLX agent context", isOn: Binding(
                get: { model.project.memory?.includeInMLXContext ?? true },
                set: { model.ensureProjectMemory(); model.project.memory?.includeInMLXContext = $0 }
            ))
            Toggle("Include memory in Semantic Graph", isOn: Binding(
                get: { model.project.memory?.includeInSemanticGraph ?? true },
                set: { model.ensureProjectMemory(); model.project.memory?.includeInSemanticGraph = $0; model.rebuildSemanticGraph() }
            ))
            Text(model.memoryContextForAgents())
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(20)
        .lemmingsGlass(cornerRadius: 26)
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Learned preferences", systemImage: "heart.text.square").font(.title2.bold())
            if let preferences = model.project.memory?.preferences, !preferences.isEmpty {
                ForEach(preferences) { preference in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text(preference.key).font(.headline)
                            Text(preference.value).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("×\(preference.evidenceCount)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            } else {
                Text("No preferences learned yet. Add a Preference memory event to seed the project.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .lemmingsGlass(cornerRadius: 26)
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Memory timeline", systemImage: "clock.arrow.circlepath").font(.title2.bold())
            if let events = model.project.memory?.events, !events.isEmpty {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: event.kind.symbolName).font(.title3).frame(width: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(event.title).font(.headline)
                                if event.isPinned { Image(systemName: "pin.fill").foregroundStyle(.yellow) }
                                Spacer()
                                Text(event.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(event.detail).foregroundStyle(.secondary)
                            if !event.tags.isEmpty {
                                Text(event.tags.map { "#\($0)" }.joined(separator: " ")).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button(event.isPinned ? "Unpin" : "Pin") { model.toggleMemoryPinned(event.id) }
                                if model.project.memory?.unresolvedIssues.contains(event.id) == true {
                                    Button("Resolve") { model.resolveMemoryIssue(event.id) }
                                }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            } else {
                Text("No memory events yet.").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .lemmingsGlass(cornerRadius: 26)
    }
}
