import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WebKit

// MARK: - Ableton-style shell additions

struct BrowserAndTrackColumn: View {
    @Environment(AppState.self) private var app
    @State private var tab: LeftBrowserTab = .tracks
    @State private var draggedTrackID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(LeftBrowserTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)
            Divider()

            switch tab {
            case .tracks:
                trackList
            case .splice:
                SpliceMiniBrowserView()
            case .sounds:
                SoundPromptMiniView()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TRACKS").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(InstrumentKind.allCases) { kind in
                        Button(kind.rawValue) { app.addTrack(kind: kind) }
                    }
                } label: { Label("Add", systemImage: "plus") }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(app.project.tracks) { track in
                        TrackRow(track: track)
                            .onDrag {
                                draggedTrackID = track.id
                                return NSItemProvider(object: track.id.uuidString as NSString)
                            }
                            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                                handleTrackDrop(providers: providers, before: track.id)
                            }
                    }
                }
                .padding(8)
            }
            Divider()
            Text("Tip: drag track rows to reorder. Drop Splice samples into the selected audio track from the browser.")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(10)
        }
    }

    private func handleTrackDrop(providers: [NSItemProvider], before targetID: UUID) -> Bool {
        if let draggedTrackID {
            app.moveTrack(id: draggedTrackID, before: targetID)
            self.draggedTrackID = nil
            return true
        }
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = UUID(uuidString: text) else { return }
            DispatchQueue.main.async { app.moveTrack(id: id, before: targetID) }
        }
        return true
    }
}

enum LeftBrowserTab: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case splice = "Splice"
    case sounds = "Sounds"
    var id: String { rawValue }
}

struct CreativeDockView: View {
    @Environment(AppState.self) private var app
    @State private var tab: CreativeDockTab = .assistant

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(CreativeDockTab.allCases) { item in
                    Button { tab = item; app.inspector = item.inspectorTab } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(tab == item ? Color.accentColor.opacity(0.24) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            Divider()
            ScrollView {
                switch tab {
                case .assistant:
                    AIAssistantView()
                case .sound:
                    DescribeASoundView()
                case .splice:
                    SpliceBrowserView()
                case .inspector:
                    InspectorPanel()
                        .frame(minHeight: 520)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

enum CreativeDockTab: String, CaseIterable, Identifiable {
    case assistant = "AI"
    case sound = "Sound"
    case splice = "Splice"
    case inspector = "More"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .assistant: return "sparkles"
        case .sound: return "waveform"
        case .splice: return "square.grid.2x2"
        case .inspector: return "slider.horizontal.3"
        }
    }
    var inspectorTab: InspectorTab {
        switch self {
        case .assistant: return .ai
        case .sound: return .describe
        case .splice: return .splice
        case .inspector: return .studio
        }
    }
}

struct SpliceMiniBrowserView: View {
    @Environment(AppState.self) private var app
    @State private var query = "124 bpm tech house loop"
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Splice", systemImage: "square.grid.2x2").font(.headline)
                Spacer()
                Button("Connect") { Task { await app.connectSplice() } }.controlSize(.small)
            }
            SpliceIsolatedTextField(placeholder: "Search samples…", text: $query, onCommit: search)
            HStack {
                Button { search() } label: {
                    HStack { if working { ProgressView().controlSize(.small) }; Text("Search") }
                }
                Button("Full Browser") { app.inspector = .splice }
                Spacer()
            }
            Text(app.spliceStatus).font(.caption2).foregroundStyle(app.spliceStatus.hasPrefix("⚠️") ? Color.orange : Color.secondary)
            Divider()
            if app.spliceResults.isEmpty {
                Text("Results appear here. Drag samples into Arrangement or Step Sequencer slots.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(Swift.Array(app.spliceResults.prefix(10))) { sample in
                    compactSampleRow(sample)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    private func search() {
        let searchText = query
        DispatchQueue.main.async {
            Task {
                working = true
                await app.searchSplice(query: searchText)
                working = false
            }
        }
    }

    private func compactSampleRow(_ sample: SpliceSample) -> some View {
        SpliceSampleRow(sample: sample)
    }
}

struct SoundPromptMiniView: View {
    @Environment(AppState.self) private var app
    @State private var prompt = "warm Juno-style pluck with short decay"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Describe a Sound", systemImage: "waveform").font(.headline)
            Text("Quick access to the sound agent. Select an instrument track first.")
                .font(.caption2).foregroundStyle(.secondary)
            TextField("Describe a synth patch…", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4)
            Button { app.inspector = .describe } label: { Label("Open Sound Agent", systemImage: "wand.and.stars") }
            Spacer()
        }
        .padding(10)
    }
}


struct GlobalShortcutCatcher: NSViewRepresentable {
    var onSpace: () -> Void
    var onDelete: () -> Void
    var canDeleteInCurrentContext: () -> Bool = { true }
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onTab: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = GlobalShortcutCatcherView()
        view.onSpace = onSpace
        view.onDelete = onDelete
        view.canDeleteInCurrentContext = canDeleteInCurrentContext
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onTab = onTab
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? GlobalShortcutCatcherView else { return }
        view.onSpace = onSpace
        view.onDelete = onDelete
        view.canDeleteInCurrentContext = canDeleteInCurrentContext
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onTab = onTab
    }
}

final class GlobalShortcutCatcherView: NSView {
    var onSpace: (() -> Void)?
    var onDelete: (() -> Void)?
    var canDeleteInCurrentContext: (() -> Bool)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onTab: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                // Tab is a DAW-level view switch in Lemmings Studio. Text fields
                // normally intercept it for focus traversal, so handle it before
                // the typing-context guard. Option-Tab is left alone for macOS
                // focus navigation/accessibility users.
                if event.keyCode == 48 && flags.intersection([.command, .option, .control]).isEmpty {
                    self.onTab?()
                    return nil
                }

                if Self.shouldLeaveKeyEventForFocusedAppOrEditor(event) { return event }

                if event.keyCode == 49 && flags.isEmpty {
                    self.onSpace?()
                    return nil
                }
                if (event.keyCode == 51 || event.keyCode == 117) && flags.isEmpty {
                    guard self.canDeleteInCurrentContext?() == true else { return event }
                    self.onDelete?()
                    return nil
                }
                // Undo/redo are handled by the always-enabled Edit-menu commands
                // (⌘Z / ⇧⌘Z). We intentionally do NOT consume them here: a focused
                // text field's own field editor still gets first crack for text
                // undo, and not consuming avoids firing undo twice per keystroke.
                return event
            }
        }
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    private static func shouldLeaveKeyEventForFocusedAppOrEditor(_ event: NSEvent) -> Bool {
        guard let window = event.window ?? NSApp.keyWindow else { return false }

        // If focus moved into an attached sheet, AU vendor editor, Carla bridge,
        // or embedded browser surface, this app-level shortcut catcher must back
        // off completely. Otherwise Backspace inside Splice Sounds can delete a
        // Lemmings track, and normal typing can leak into the DAW command layer.
        if let main = NSApp.mainWindow, window !== main { return true }
        if isProtectedWindowTitle(window.title) { return true }

        guard let responder = window.firstResponder else { return false }
        if responder is NSTextView { return true }
        if responder is NSTextField { return true }
        if viewHierarchyContainsProtectedEditor(from: responder) { return true }
        return false
    }

    private static func isProtectedWindowTitle(_ title: String) -> Bool {
        let text = title.lowercased()
        return text.contains("splice") || text.contains("carla") || text.contains("bridge") || text.contains("plug-in") || text.contains("plugin")
    }

    private static func viewHierarchyContainsProtectedEditor(from responder: NSResponder) -> Bool {
        var current: NSResponder? = responder
        while let node = current {
            if node is WKWebView { return true }
            let className = String(describing: type(of: node)).lowercased()
            if className.contains("wk") || className.contains("webview") || className.contains("splice") || className.contains("auv") || className.contains("auview") {
                return true
            }
            if let view = node as? NSView {
                if containsProtectedSubview(view) { return true }
                current = view.superview ?? view.nextResponder
            } else {
                current = node.nextResponder
            }
        }
        return false
    }

    private static func containsProtectedSubview(_ view: NSView) -> Bool {
        if view is WKWebView { return true }
        let name = String(describing: type(of: view)).lowercased()
        if name.contains("wk") || name.contains("webview") || name.contains("splice") || name.contains("auv") || name.contains("auview") {
            return true
        }
        for child in view.subviews {
            if containsProtectedSubview(child) { return true }
        }
        return false
    }
}
