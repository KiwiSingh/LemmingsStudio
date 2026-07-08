import Foundation

/// buildfix262: Living Project Memory for visionOS.
///
/// This is intentionally project-local and JSON-serializable for now. It gives the
/// Semantic Project Graph and MLX Runtime a durable memory surface without requiring
/// SQLite/CoreData in the first pass. A future build can swap the persistence backend
/// to Project.sqlite while keeping these value types and UI contracts stable.
enum VisionProjectMemoryEventKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case session = "Session"
    case mixDecision = "Mix Decision"
    case arrangementDecision = "Arrangement Decision"
    case pluginDecision = "Plugin Decision"
    case recordingDecision = "Recording Decision"
    case export = "Export"
    case rejection = "Rejected Idea"
    case preference = "Preference"
    case issue = "Issue"
    case aiNote = "AI Note"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .session: return "clock.arrow.circlepath"
        case .mixDecision: return "slider.horizontal.3"
        case .arrangementDecision: return "timeline.selection"
        case .pluginDecision: return "puzzlepiece.extension"
        case .recordingDecision: return "record.circle"
        case .export: return "square.and.arrow.up"
        case .rejection: return "xmark.octagon"
        case .preference: return "heart"
        case .issue: return "exclamationmark.triangle"
        case .aiNote: return "brain.head.profile"
        }
    }
}

struct VisionProjectMemoryEvent: Identifiable, Codable, Sendable, Hashable {
    var id = UUID()
    var createdAt = Date()
    var kind: VisionProjectMemoryEventKind
    var title: String
    var detail: String
    var relatedSemanticNodeIDs: [UUID] = []
    var tags: [String] = []
    var confidence: Double = 1.0
    var isPinned: Bool = false

    var compactLine: String {
        let tagSuffix = tags.isEmpty ? "" : " #" + tags.joined(separator: " #")
        return "[\(kind.rawValue)] \(title) — \(detail)\(tagSuffix)"
    }
}

struct VisionProjectPreference: Identifiable, Codable, Sendable, Hashable {
    var id = UUID()
    var key: String
    var value: String
    var evidenceCount: Int = 1
    var lastUpdated = Date()
    var sourceEventIDs: [UUID] = []
}

struct VisionProjectMemoryState: Codable, Sendable {
    var schemaVersion: Int = 1
    var projectID: UUID = UUID()
    var summary: String = "No project memory yet. Start by adding a session note, preference, issue, or export marker."
    var events: [VisionProjectMemoryEvent] = []
    var preferences: [VisionProjectPreference] = []
    var unresolvedIssues: [UUID] = []
    var lastCompactedAt: Date?
    var includeInMLXContext: Bool = true
    var includeInSemanticGraph: Bool = true
    var autoCaptureSessions: Bool = true
    var requireConfirmationForLearnedPreferences: Bool = true

    var pinnedEvents: [VisionProjectMemoryEvent] { events.filter(\.isPinned) }
    var recentEvents: [VisionProjectMemoryEvent] { Array(events.sorted { $0.createdAt > $1.createdAt }.prefix(12)) }

    var contextDigest: String {
        var lines: [String] = []
        lines.append("Project memory summary: \(summary)")
        if !preferences.isEmpty {
            lines.append("Preferences:")
            for preference in preferences.sorted(by: { $0.key < $1.key }).prefix(10) {
                lines.append("- \(preference.key): \(preference.value) (evidence \(preference.evidenceCount))")
            }
        }
        let important = (pinnedEvents + recentEvents).uniquedByID().prefix(12)
        if !important.isEmpty {
            lines.append("Recent/pinned decisions:")
            for event in important { lines.append("- \(event.compactLine)") }
        }
        if !unresolvedIssues.isEmpty {
            let issueTitles = events.filter { unresolvedIssues.contains($0.id) }.map(\.title).prefix(8)
            lines.append("Unresolved issues: \(issueTitles.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}

private extension Array where Element == VisionProjectMemoryEvent {
    func uniquedByID() -> [VisionProjectMemoryEvent] {
        var seen = Set<UUID>()
        return filter { seen.insert($0.id).inserted }
    }
}

struct VisionProjectMemoryStore: Sendable {
    func defaultMemory(for project: LemmingsProject) -> VisionProjectMemoryState {
        var memory = VisionProjectMemoryState()
        memory.summary = "Fresh memory for \(project.name). No durable decisions captured yet."
        return memory
    }

    func compact(_ memory: VisionProjectMemoryState, project: LemmingsProject) -> VisionProjectMemoryState {
        var copy = memory
        let pinned = copy.pinnedEvents.map(\.title)
        let exports = copy.events.filter { $0.kind == .export }.suffix(3).map(\.title)
        let issues = copy.events.filter { copy.unresolvedIssues.contains($0.id) }.map(\.title)
        let prefs = copy.preferences.sorted { $0.evidenceCount > $1.evidenceCount }.prefix(5).map { "\($0.key)=\($0.value)" }
        var parts: [String] = []
        parts.append("\(project.name): \(copy.events.count) memory events, \(copy.preferences.count) learned preferences.")
        if !prefs.isEmpty { parts.append("Preferences: \(prefs.joined(separator: "; ")).") }
        if !pinned.isEmpty { parts.append("Pinned: \(pinned.prefix(4).joined(separator: "; ")).") }
        if !exports.isEmpty { parts.append("Recent exports: \(exports.joined(separator: "; ")).") }
        if !issues.isEmpty { parts.append("Open issues: \(issues.prefix(5).joined(separator: "; ")).") }
        copy.summary = parts.joined(separator: " ")
        copy.lastCompactedAt = Date()
        return copy
    }
}

extension VisionStudioModel {
    func ensureProjectMemory() {
        if project.memory == nil {
            project.memory = VisionProjectMemoryStore().defaultMemory(for: project)
        }
    }

    func addMemoryEvent(kind: VisionProjectMemoryEventKind, title: String, detail: String, tags: [String] = [], pin: Bool = false) {
        ensureProjectMemory()
        var event = VisionProjectMemoryEvent(kind: kind, title: title, detail: detail, tags: tags, isPinned: pin)
        if let selectedClipID { event.relatedSemanticNodeIDs = [selectedClipID] }
        project.memory?.events.insert(event, at: 0)
        if kind == .issue { project.memory?.unresolvedIssues.append(event.id) }
        if kind == .preference { learnPreferenceFromEvent(event) }
        compactProjectMemory()
        rebuildSemanticGraph()
        statusMessage = "Memory captured: \(title)"
    }

    func addSessionMemorySnapshot() {
        ensureProjectMemory()
        let summary = semanticGraphSummary()
        addMemoryEvent(
            kind: .session,
            title: "Session snapshot",
            detail: "\(project.tracks.count) tracks, \(summary.nodeCount) semantic nodes, tempo \(String(format: "%.1f", project.effectiveTempo)) BPM.",
            tags: ["session", "semantic-graph"]
        )
    }

    func toggleMemoryPinned(_ eventID: UUID) {
        ensureProjectMemory()
        guard let index = project.memory?.events.firstIndex(where: { $0.id == eventID }) else { return }
        project.memory?.events[index].isPinned.toggle()
        compactProjectMemory()
        statusMessage = "Memory pin toggled"
    }

    func resolveMemoryIssue(_ eventID: UUID) {
        ensureProjectMemory()
        project.memory?.unresolvedIssues.removeAll { $0 == eventID }
        addMemoryEvent(kind: .aiNote, title: "Resolved issue", detail: "Marked memory issue \(eventID.uuidString.prefix(8)) as resolved.", tags: ["resolved"])
    }

    func compactProjectMemory() {
        ensureProjectMemory()
        guard let memory = project.memory else { return }
        project.memory = VisionProjectMemoryStore().compact(memory, project: project)
        mlxRuntime.lastDryRunSummary = "Memory context ready: \(project.memory?.events.count ?? 0) events, \(project.memory?.preferences.count ?? 0) preferences."
    }

    private func learnPreferenceFromEvent(_ event: VisionProjectMemoryEvent) {
        let key = event.tags.first ?? event.title.lowercased().replacingOccurrences(of: " ", with: "-")
        var preferences = project.memory?.preferences ?? []
        if let index = preferences.firstIndex(where: { $0.key == key }) {
            preferences[index].value = event.detail
            preferences[index].evidenceCount += 1
            preferences[index].lastUpdated = Date()
            preferences[index].sourceEventIDs.append(event.id)
        } else {
            preferences.append(.init(key: key, value: event.detail, sourceEventIDs: [event.id]))
        }
        project.memory?.preferences = preferences
    }

    func memoryContextForAgents() -> String {
        ensureProjectMemory()
        guard project.memory?.includeInMLXContext == true else { return "Project memory context disabled." }
        return project.memory?.contextDigest ?? "No project memory."
    }
}
