import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Original professional DAW shell
// Inspired by modern clip-based DAWs, but deliberately uses Lemmings Studio's own visual language.

struct ProDAWShell: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            ProTransportStrip()
            Divider().opacity(0.35)
            HSplitView {
                ProBrowserPanel()
                    .frame(minWidth: 265, idealWidth: 310, maxWidth: 390)
                    .liquidGlass(cornerRadius: 18)
                    .padding(.leading, 8).padding(.vertical, 8)

                VStack(spacing: 0) {
                    WorkspaceTabBar()
                    Divider()
                    VSplitView {
                        Group {
                            switch app.workspace {
                            case .session: SessionMatrixView()
                            case .arrangement: ArrangementView()
                            case .pianoRoll: PianoRollView()
                            case .step: StepSequencerView()
                            case .devices: DeviceRackView()
                            case .automation: AutomationView()
                            case .mixer: MixerView()
                            }
                        }
                        .frame(minHeight: 420)

                        DetailDeckView()
                            .frame(minHeight: 190, idealHeight: 230, maxHeight: 330)
                    }
                }
                .frame(minWidth: 640)
                .liquidGlass(cornerRadius: 18)
                .padding(.vertical, 8)

                ProRightDock()
                    .frame(minWidth: 350, idealWidth: 405, maxWidth: 520)
                    .liquidGlass(cornerRadius: 18)
                    .padding(.trailing, 8).padding(.vertical, 8)
            }
            LSStatusBar()
        }
        .background(LSTheme.windowBackground)
    }
}

/// Bottom status bar: surfaces editStatus / record / recorder diagnostics (which
/// previously were set in code but never displayed anywhere), plus always-clickable
/// Undo/Redo so undo works regardless of keyboard/menu focus routing.
struct LSStatusBar: View {
    @Environment(AppState.self) private var app

    private var message: String {
        for s in [app.recorderStatus, app.editStatus, app.recordStatus] where !s.isEmpty { return s }
        return "Ready"
    }
    private var isProblem: Bool {
        let m = message.lowercased()
        return m.contains("could not") || m.contains("empty") || m.contains("failed") || m.contains("no audio") || m.contains("no input") || m.contains("permission") || m.contains("⚠")
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                app.undoLastAction()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .help("Undo (\(app.canUndo ? "available" : "nothing to undo"))")
            Button {
                app.redoLastAction()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .help("Redo")
            Divider().frame(height: 16)
            if app.recorder.isRecording {
                Circle().fill(LSTheme.record).frame(width: 8, height: 8)
                Text("REC").font(.caption2.bold()).foregroundStyle(LSTheme.record)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(isProblem ? Color.orange : LSTheme.dim)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(LSTheme.windowBackground.opacity(0.6))
        .overlay(alignment: .top) { Divider().opacity(0.35) }
    }
}

private struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [LSTheme.glassHighlight, Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LSTheme.glassStroke, lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 12)
    }
}

private extension View {
    func liquidGlass(cornerRadius: CGFloat = 16, padding: CGFloat = 0) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius, padding: padding))
    }
}

struct ProTransportStrip: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var project = app.project
        TimelineView(.animation) { _ in
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(LSTheme.play).frame(width: 7, height: 18)
                    VStack(alignment: .leading, spacing: -1) {
                        Text("LemmingsStudio").font(.system(size: 13, weight: .bold))
                        Text("creative DAW · \(LSTheme.logoGlyph)").font(.system(size: 8, weight: .medium)).foregroundStyle(LSTheme.dim)
                    }
                }
                .frame(width: 158, alignment: .leading)

                transportButton(system: app.engine.transport.isPlaying ? "pause.fill" : "play.fill", tint: LSTheme.play) { app.togglePlay() }
                transportButton(system: "stop.fill", tint: LSTheme.text) { app.stopTransport() }
                transportButton(system: "backward.end.fill", tint: LSTheme.text) { app.returnToStart() }
                transportButton(system: app.recorder.isRecording ? "record.circle.fill" : "record.circle", tint: LSTheme.record) { app.toggleRecord() }
                transportButton(system: "metronome", tint: app.metronomeEnabled ? .yellow : LSTheme.dim, active: app.metronomeEnabled) { app.toggleMetronome() }
                    .help("Metronome on/off (⌘M)")
                transportButton(system: "timer", tint: app.countInEnabled ? .orange : LSTheme.dim, active: app.countInEnabled) {
                    app.countInEnabled.toggle()
                    app.persistSettings()
                    app.editStatus = app.countInEnabled ? "Record count-in on" : "Record count-in off"
                }
                    .help("Click-in / count-in before recording")
                transportButton(system: "q.circle", tint: app.recordQuantizationEnabled ? .cyan : LSTheme.dim, active: app.recordQuantizationEnabled) { app.toggleRecordQuantization() }
                    .help("Record quantization")

                Divider().frame(height: 28)

                transportReadout(title: "POSITION", value: barBeatTick(app.engine.currentBeat))
                transportReadout(title: "TIME", value: secondsString(app.engine.currentBeat))

                HStack(spacing: 5) {
                    Text("BPM").font(.caption2).foregroundStyle(LSTheme.dim)
                    TempoTextField(compact: true)
                    Button("Tap") { app.tapTempo() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(app.tapTempoStatus)
                    Toggle("Q", isOn: Binding(get: { app.recordQuantizationEnabled }, set: { _ in app.toggleRecordQuantization() }))
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .help("Record quantization")
                }

                CompactProjectKeySelector(rootWidth: 68, scaleWidth: 160)

                Menu {
                    generatorMenu("Bhangra Architect", kind: .bhangraArchitect)
                    generatorMenu("2C", kind: .guaracha2C)
                    generatorMenu("Bailaton", kind: .bailaton)
                    generatorMenu("Dubstep Wrangler", kind: .dubstepWrangler)
                    generatorMenu("LemmingBass", kind: .lemmingBass)
                    generatorMenu("Oscillatron", kind: .oscillatron)
                    generatorMenu("Drum Machine", kind: .drums)
                    generatorMenu("Sequencer", kind: .sequencer)
                } label: {
                    Label("Devices", systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(LSTheme.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(ExportFormat.allCases) { fmt in
                        Button("Export \(fmt.rawValue)…") { app.export(format: fmt) }
                    }
                    Divider()
                    Button("Show Studio Export Panel") {
                        app.inspector = .studio
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(LSTheme.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Export WAV, FLAC, AAC, or MP3")

                if app.exportIsActive {
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: app.exportProgress)
                            .frame(width: 96)
                        Text("Export \(Int((app.exportProgress * 100).rounded()))%")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(LSTheme.dim)
                    }
                } else if app.stemProgress > 0 && app.stemProgress < 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: app.stemProgress)
                            .frame(width: 96)
                        Text("Stems \(Int((app.stemProgress * 100).rounded()))%")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(LSTheme.dim)
                    }
                } else if app.exportDidClip {
                    Label("Clip", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                        .help(app.exportStatus)
                }

                Menu {
                    ForEach(LemmingsVisualTheme.allCases) { theme in
                        Button {
                            app.visualTheme = theme
                            app.persistSettings()
                        } label: {
                            Label(theme.displayName, systemImage: theme.primaryGlyph)
                        }
                    }
                } label: {
                    Label(LSTheme.current.displayName, systemImage: LSTheme.current.primaryGlyph)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(LSTheme.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Switch Liquid Glass theme")

                Spacer(minLength: 10)

                HStack(spacing: 5) {
                    statusPill("CPU", String(format: "%.0f%%", min(99, app.engine.masterMeterPeak() * 100)))
                    statusPill("SR", "\(Int(app.project.sampleRate / 1000))k")
                    statusPill("MCP", app.spliceTools.isEmpty ? "off" : "on")
                }
            }
            .foregroundStyle(LSTheme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .liquidGlass(cornerRadius: 16)
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }

    private func transportButton(system: String, tint: Color, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 28)
                .foregroundStyle(tint)
                .background(active ? LSTheme.panel2.opacity(1.0) : LSTheme.panel2)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? tint.opacity(0.75) : Color.clear, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func generatorMenu(_ title: String, kind: InstrumentKind) -> some View {
        Menu(title) {
            Button("Create Arrangement MIDI Clip") { app.launchGeneratorDevice(kind, mode: .midiClip) }
            Button("Open Step Sequencer") { app.launchGeneratorDevice(kind, mode: .stepSequence) }
            Button("Load Device Only") { app.launchGeneratorDevice(kind, mode: .deviceOnly) }
        }
    }

    private func transportReadout(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 17, weight: .semibold, design: .monospaced))
            Text(title).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(LSTheme.dim)
        }.frame(width: title == "POSITION" ? 94 : 70, alignment: .leading)
    }

    private func statusPill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) { Text(label).foregroundStyle(LSTheme.dim); Text(value).foregroundStyle(LSTheme.text) }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(LSTheme.panel2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func barBeatTick(_ beat: Double) -> String {
        let beatsPerBar = max(1, app.project.beatsPerBar)
        let whole = max(0, Int(floor(beat)))
        let bar = whole / beatsPerBar + 1
        let beatInBar = whole % beatsPerBar + 1
        let tick = Int(((beat - floor(beat)) * 96).rounded())
        return String(format: "%03d.%02d.%02d", bar, beatInBar, tick)
    }

    private func secondsString(_ beat: Double) -> String {
        let seconds = max(0, beat * 60.0 / max(1, app.project.tempo))
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

/// A commit-on-submit BPM editor. SwiftUI's numeric TextField writes intermediate
/// values while the user types (e.g. 1 → 12 → 128), which is nasty in a DAW
/// because each intermediate write re-warps clips, resets transport anchors, and
/// can make the visible BPM appear to jump to nonsense values. Keep text local,
/// then commit only on Return/focus loss.
struct TempoTextField: View {
    @Environment(AppState.self) private var app
    @FocusState private var focused: Bool
    @State private var text = ""
    var compact = false

    var body: some View {
        TextField("BPM", text: $text)
            .frame(width: compact ? 54 : 68)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { syncFromProject(force: true) }
            .onChange(of: text) { _, newValue in app.noteTempoEditorDraft(newValue) }
            .onChange(of: app.project.tempo) { _, _ in syncFromProject(force: false) }
            .onChange(of: app.audibleTempo) { _, _ in syncFromProject(force: false) }
            .overlay(alignment: .bottomTrailing) {
                if app.project.tempoAutomationEnabled && !focused {
                    Text("AUTO")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.orange)
                        .offset(x: -4, y: 9)
                }
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    syncFromProject(force: true)
                } else {
                    commit()
                }
            }
            .onSubmit { commit() }
            .help(app.project.tempoAutomationEnabled ? "Showing automated live BPM. Click/type to edit the base project BPM." : "Type BPM and press Return. Values are clamped from 20 to 300 BPM.")
    }

    private func syncFromProject(force: Bool) {
        guard force || !focused else { return }
        let source = app.project.tempoAutomationEnabled && !focused ? app.audibleTempo : app.project.tempo
        let bpm = Int(source.rounded())
        text = "\(bpm)"
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value.isFinite else {
            syncFromProject(force: true)
            return
        }
        app.setProjectTempo(value)
        syncFromProject(force: true)
    }
}

struct ProBrowserPanel: View {
    @State private var tab: BrowserTab = .library

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(BrowserTab.allCases) { item in
                    Button(item.rawValue) { tab = item }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(tab == item ? LSTheme.panel2 : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
            }
            .padding(8)
            Divider()
            switch tab {
            case .library: LibraryBrowserView()
            case .tracks: BrowserAndTrackColumn()
            case .splice: SpliceMiniBrowserView()
            case .samples: UserSamplesBrowserView()
            case .sounds: SoundPromptMiniView()
            case .pads: DrumPadsBrowserView()
            case .effects: EffectsPluginsBrowserView(onBack: { tab = .library })
            }
        }
        .background(Color.clear)
        .foregroundStyle(LSTheme.text)
    }
}

private enum BrowserTab: String, CaseIterable, Identifiable {
    case library = "Library", tracks = "Tracks", splice = "Splice", samples = "Samples", sounds = "Sounds", pads = "Pads", effects = "FX/Plugins"
    var id: String { rawValue }
}



private struct UserLibraryFolderBucket: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let depth: Int
    let items: [UserLibraryItem]
}

struct UserSamplesBrowserView: View {
    @Environment(AppState.self) private var app
    @State private var selectedKind: UserLibraryMediaKind = .oneShot
    @State private var search = ""
    @State private var expandedFolders: Set<String> = ["__root__"]

    private var filteredItems: [UserLibraryItem] {
        app.userLibraryItems.filter { item in
            item.kind == selectedKind && (search.isEmpty || item.name.localizedCaseInsensitiveContains(search) || folderLabel(for: item).localizedCaseInsensitiveContains(search))
        }
    }

    private var folderBuckets: [UserLibraryFolderBucket] {
        let root = app.userLibraryFolder.isEmpty ? nil : URL(fileURLWithPath: app.userLibraryFolder, isDirectory: true).standardizedFileURL.path
        let grouped = Dictionary(grouping: filteredItems) { item -> String in
            let parent = item.url.deletingLastPathComponent().standardizedFileURL.path
            guard let root, parent.hasPrefix(root) else { return parent }
            let rel = String(parent.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return rel.isEmpty ? "__root__" : rel
        }
        return grouped.map { key, items in
            let display = key == "__root__" ? "Library Root" : key
            let depth = key == "__root__" ? 0 : key.split(separator: "/").count - 1
            let sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let subtitle: String
            if key == "__root__" {
                subtitle = app.userLibraryFolder.isEmpty ? "Choose a folder" : URL(fileURLWithPath: app.userLibraryFolder).lastPathComponent
            } else {
                subtitle = "Folder · \(sorted.count) item\(sorted.count == 1 ? "" : "s")"
            }
            return UserLibraryFolderBucket(id: key, title: display, subtitle: subtitle, depth: depth, items: sorted)
        }
        .sorted { a, b in
            if a.id == "__root__" { return true }
            if b.id == "__root__" { return false }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("User Samples", systemImage: "folder.badge.gearshape")
                    .font(.headline)
                Spacer()
                Button("Choose…") { app.chooseAndScanUserLibrary() }.controlSize(.small)
                Button("Rescan") { app.scanUserLibrary() }.controlSize(.small)
                    .disabled(app.userLibraryFolder.isEmpty)
            }
            if !app.userLibraryFolder.isEmpty {
                Label(app.userLibraryFolder, systemImage: "folder")
                    .font(.caption2)
                    .foregroundStyle(LSTheme.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                if app.userLibraryScanInProgress { ProgressView().controlSize(.small) }
                Text(app.userLibraryScanStatus)
                    .font(.caption2)
                    .foregroundStyle(LSTheme.dim)
                    .lineLimit(2)
            }
            Text(app.userLibraryPreviewStatus)
                .font(.caption2)
                .foregroundStyle(app.userLibraryPreviewStatus.hasPrefix("⚠️") ? .orange : LSTheme.dim)
                .lineLimit(2)
            TextField("Search one-shots, loops, MIDIs, folders…", text: $search)
                .textFieldStyle(.roundedBorder)
            Picker("Type", selection: $selectedKind) {
                ForEach(UserLibraryMediaKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Button("Expand All") { expandedFolders = Set(folderBuckets.map(\.id)) }.controlSize(.mini)
                Button("Collapse") { expandedFolders = [] }.controlSize(.mini)
                Spacer()
                Text("Drag files into Arrangement. Click Preview to audition.")
                    .font(.caption2)
                    .foregroundStyle(LSTheme.dim)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(folderBuckets) { bucket in
                        folderBucketView(bucket)
                    }
                    if filteredItems.isEmpty {
                        Text("No \(selectedKind.rawValue.lowercased()) found. Choose your User Library folder, rescan, or switch type.")
                            .font(.caption)
                            .foregroundStyle(LSTheme.dim)
                            .padding(.top, 10)
                    }
                }
            }
        }
        .padding(10)
        .onAppear { if !app.userLibraryFolder.isEmpty && app.userLibraryItems.isEmpty { app.scanUserLibrary() } }
    }

    private func folderBucketView(_ bucket: UserLibraryFolderBucket) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedFolders.contains(bucket.id) || !search.isEmpty },
            set: { isOpen in
                if isOpen { expandedFolders.insert(bucket.id) } else { expandedFolders.remove(bucket.id) }
            }
        )) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(bucket.items) { item in
                    UserSampleRow(item: item)
                        .padding(.leading, CGFloat(max(0, bucket.depth)) * 10)
                }
            }
            .padding(.top, 5)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: bucket.id == "__root__" ? "externaldrive" : "folder")
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bucket.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(bucket.subtitle).font(.caption2).foregroundStyle(LSTheme.dim).lineLimit(1)
                }
                Spacer()
                Text("\(bucket.items.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(LSTheme.dim)
            }
            .padding(7)
            .background(LSTheme.panel2.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private func folderLabel(for item: UserLibraryItem) -> String {
        let parent = item.url.deletingLastPathComponent().path
        guard !app.userLibraryFolder.isEmpty, parent.hasPrefix(app.userLibraryFolder) else { return parent }
        return String(parent.dropFirst(app.userLibraryFolder.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct UserSampleRow: View {
    @Environment(AppState.self) private var app
    let item: UserLibraryItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(LSTheme.dim).lineLimit(1)
            }
            Spacer()
            Button(app.userLibraryPreviewingID == item.id ? "Stop" : "Preview") {
                if app.userLibraryPreviewingID == item.id { app.stopUserLibraryPreview() }
                else { app.previewUserLibraryItem(item) }
            }
            .controlSize(.mini)
            if item.kind == .midi {
                Button("Add MIDI") { app.importMIDIFileAsClip(item.url, on: app.selectedTrack) }.controlSize(.mini)
            } else {
                Button("Add Clip") { try? app.importAudioFile(item.url, originalTempo: item.detectedTempo) }.controlSize(.mini)
            }
        }
        .padding(7)
        .background(app.userLibraryPreviewingID == item.id ? LSTheme.focus.opacity(0.20) : LSTheme.panel2.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { app.previewUserLibraryItem(item) }
        .onDrag { NSItemProvider(object: PluginDragPasteboard.encodeSample(path: item.url.path) as NSString) }
        .contextMenu {
            Button("Preview") { app.previewUserLibraryItem(item) }
            if item.kind == .midi {
                Button("Add MIDI Clip") { app.importMIDIFileAsClip(item.url, on: app.selectedTrack) }
            } else {
                Button("Add Audio Clip") { try? app.importAudioFile(item.url, originalTempo: item.detectedTempo) }
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
        .help("Drag into Arrangement or onto a track. Preview auditions without adding a Step Sequencer layer.")
    }

    private var icon: String {
        switch item.kind {
        case .oneShot: return "waveform"
        case .loop: return "repeat"
        case .midi: return "music.note.list"
        }
    }

    private var subtitle: String {
        var parts = [item.kind.rawValue]
        if let bpm = item.detectedTempo { parts.append("\(Int(bpm)) BPM") }
        parts.append(item.url.deletingLastPathComponent().lastPathComponent)
        return parts.joined(separator: " · ")
    }
}

struct DrumPadsBrowserView: View {
    @Environment(AppState.self) private var app

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Drum Pads", systemImage: "square.grid.3x3.fill")
                    .font(.headline)
                Spacer()
                Button("New Drum Track") { app.addTrack(kind: .drums) }
                    .controlSize(.small)
            }

            Picker("Controller", selection: $app.drumPadPreset) {
                ForEach(DrumPadPreset.allCases) { preset in Text(preset.rawValue).tag(preset) }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Transpose")
                    .font(.caption)
                    .foregroundStyle(LSTheme.dim)
                Stepper(value: $app.drumPadTranspose, in: -48...48) {
                    Text(app.drumPadTranspose == 0 ? "0 semitones" : "\(app.drumPadTranspose) semitones")
                        .font(.system(size: 11, design: .monospaced))
                }
            }

            HStack {
                Picker("Learn", selection: $app.drumPadLearnVoice) {
                    ForEach(DrumVoiceID.allCases) { voice in Text(voice.label).tag(voice) }
                }
                Button(app.drumPadLearnMode ? "Hit a pad…" : "Learn Pad") {
                    app.drumPadLearnMode.toggle()
                }
                .controlSize(.small)
            }

            Text(app.drumPadLastHit)
                .font(.caption)
                .foregroundStyle(LSTheme.dim)
                .lineLimit(1)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(DrumVoiceID.allCases) { voice in
                    DrumPadButton(voice: voice)
                }
            }

            Divider()
            Text("CURRENT MAP")
                .font(.caption2.bold())
                .foregroundStyle(LSTheme.dim)

            if app.drumPadAssignments.isEmpty {
                Text("No pad assignments. Use Learn Pad or switch presets.")
                    .font(.caption2)
                    .foregroundStyle(LSTheme.dim)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(app.drumPadAssignments.prefix(32)) { assignment in
                            HStack {
                                Text("Note \(assignment.note)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Spacer()
                                Text(assignment.voice.label)
                                    .font(.caption)
                                    .foregroundStyle(LSTheme.dim)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(LSTheme.panel2.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            Text("Arm/select a Drum Machine track, then hit MPK Mini / ATOM pads. Drum tracks bypass scale-snap so pads trigger the intended one-shots.")
                .font(.caption2)
                .foregroundStyle(LSTheme.dim)
            Spacer(minLength: 0)
        }
        .padding(10)
        .onDisappear { app.persistSettings() }
    }
}

struct DrumPadButton: View {
    @Environment(AppState.self) private var app
    let voice: DrumVoiceID

    var body: some View {
        Button {
            app.triggerDrumPad(voice)
        } label: {
            VStack(spacing: 3) {
                Text(voice.label)
                    .font(.system(size: 12, weight: .bold))
                Text("MIDI \(voice.midiNote)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(LSTheme.dim)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(app.drumPadLastHit.contains(voice.label) ? LSTheme.focus.opacity(0.30) : LSTheme.panel2.opacity(0.65))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(LSTheme.grid.opacity(0.8)))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("Preview \(voice.label); external pads trigger the mapped MIDI note")
    }
}

private struct PluginBrowserBucket: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let plugins: [DiscoveredPlugin]
}

struct EffectsPluginsBrowserView: View {
    @Environment(AppState.self) private var app
    let onBack: () -> Void
    @State private var search = ""
    @State private var expandedDeviceSections: Set<String> = Set(DeviceKind.categorizedBrowserSections.map(\.id))
    @State private var expandedPluginSections: Set<String> = []

    private var filteredPlugins: [DiscoveredPlugin] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return app.discoveredPlugins }
        return app.discoveredPlugins.filter { plugin in
            plugin.name.localizedCaseInsensitiveContains(q)
            || plugin.manufacturer.localizedCaseInsensitiveContains(q)
            || plugin.format.rawValue.localizedCaseInsensitiveContains(q)
            || plugin.role.rawValue.localizedCaseInsensitiveContains(q)
            || (plugin.path ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private var pluginBuckets: [PluginBrowserBucket] {
        let grouped = Dictionary(grouping: filteredPlugins) { plugin -> String in
            let maker = plugin.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Developer" : plugin.manufacturer
            return "\(plugin.format.rawValue) · \(plugin.role.rawValue) · \(maker)"
        }
        return grouped.map { key, plugins in
            let sorted = plugins.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return PluginBrowserBucket(id: key, title: key, subtitle: "\(sorted.count) plug-in\(sorted.count == 1 ? "" : "s")", plugins: sorted)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var filteredDeviceSections: [DeviceBrowserSection] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return DeviceKind.categorizedBrowserSections }
        return DeviceKind.categorizedBrowserSections.compactMap { section in
            let devices = section.devices.filter {
                $0.rawValue.localizedCaseInsensitiveContains(q)
                || $0.role.rawValue.localizedCaseInsensitiveContains(q)
                || $0.browserCategory.localizedCaseInsensitiveContains(q)
            }
            return devices.isEmpty ? nil : DeviceBrowserSection(id: section.id, title: section.title, role: section.role, devices: devices)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { onBack() } label: { Label("Library", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Back to Library categories")
                Label("FX / Plugins", systemImage: "puzzlepiece.extension")
                    .font(.headline)
                Spacer()
                Button("Scan") { app.scanPlugins() }.controlSize(.small)
            }
            TextField("Search AU, VST3, VST, built-in FX…", text: $search)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Button("Expand") {
                    expandedDeviceSections = Set(filteredDeviceSections.map(\.id))
                    expandedPluginSections = Set(pluginBuckets.map(\.id))
                }.controlSize(.mini)
                Button("Collapse") {
                    expandedDeviceSections = []
                    expandedPluginSections = []
                }.controlSize(.mini)
                Spacer()
                Text("Browse by category. Drag onto tracks, device racks, mixer slots, or drop zone.")
                    .font(.caption2)
                    .foregroundStyle(LSTheme.dim)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    browserHeading("BUILT-IN DEVICES")
                    ForEach(filteredDeviceSections) { section in
                        deviceSectionView(section)
                    }

                    Divider().padding(.vertical, 2)
                    HStack {
                        browserHeading("SCANNED PLUGINS")
                        Spacer()
                        Text(app.pluginScanStatus).font(.caption2).foregroundStyle(LSTheme.dim).lineLimit(1)
                    }
                    if pluginBuckets.isEmpty {
                        Text("No scanned plugins yet. Scan looks in Audio Unit, VST3, and VST locations. AU instruments can be hosted; VST/VST3 are drag targets / bridge slots until a native VST host path is added.")
                            .font(.caption2).foregroundStyle(LSTheme.dim)
                    } else {
                        ForEach(pluginBuckets) { bucket in
                            pluginSectionView(bucket)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .onAppear {
            if expandedPluginSections.isEmpty { expandedPluginSections = Set(pluginBuckets.prefix(4).map(\.id)) }
        }
    }

    private func browserHeading(_ text: String) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(LSTheme.dim)
    }

    private func deviceSectionView(_ section: DeviceBrowserSection) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { !search.isEmpty || expandedDeviceSections.contains(section.id) },
            set: { isOpen in
                if isOpen { expandedDeviceSections.insert(section.id) } else { expandedDeviceSections.remove(section.id) }
            }
        )) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(section.devices) { kind in
                    deviceRow(kind)
                }
            }
            .padding(.top, 5)
        } label: {
            HStack {
                Text(section.title.uppercased()).font(.caption2.bold()).foregroundStyle(LSTheme.dim)
                Spacer()
                Text("\(section.devices.count) · \(section.role.rawValue)")
                    .font(.caption2).foregroundStyle(LSTheme.dim)
            }
            .padding(7)
            .background(LSTheme.panel2.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private func deviceRow(_ kind: DeviceKind) -> some View {
        HStack {
            Image(systemName: icon(for: kind)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.rawValue).font(.system(size: 12, weight: .medium))
                Text("\(kind.role.rawValue) · \(kind.implementationStatus)")
                    .font(.caption2).foregroundStyle(LSTheme.dim)
            }
            Spacer()
            Text("Drag")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(LSTheme.panel2)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Button("Add") { addEffect(kind) }.controlSize(.mini)
        }
        .padding(7)
        .background(LSTheme.panel2.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onDrag { NSItemProvider(object: PluginDragPasteboard.encode(kind) as NSString) }
        .contextMenu {
            Button("Add to Selected Track") { addEffect(kind) }
            Button("Reveal Target: Arrangement") { app.workspace = .arrangement }
            Button("Reveal Target: Devices") { app.detailDeck = .devices; app.workspace = .arrangement }
        }
    }

    private func pluginSectionView(_ bucket: PluginBrowserBucket) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { !search.isEmpty || expandedPluginSections.contains(bucket.id) },
            set: { isOpen in
                if isOpen { expandedPluginSections.insert(bucket.id) } else { expandedPluginSections.remove(bucket.id) }
            }
        )) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(bucket.plugins) { plugin in
                    pluginRow(plugin)
                }
            }
            .padding(.top, 5)
        } label: {
            HStack {
                Image(systemName: "folder.badge.gearshape").frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bucket.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(bucket.subtitle).font(.caption2).foregroundStyle(LSTheme.dim)
                }
                Spacer()
            }
            .padding(7)
            .background(LSTheme.panel2.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private func addEffect(_ kind: DeviceKind) {
        let track: Track
        if let selected = app.selectedTrack {
            track = selected
        } else {
            app.addTrack(kind: defaultTrackKind(for: kind))
            guard let created = app.selectedTrack else { return }
            track = created
        }
        app.addEffect(kind, to: track)
        app.detailDeck = .devices
        app.workspace = .arrangement
    }

    private func defaultTrackKind(for kind: DeviceKind) -> InstrumentKind {
        switch kind {
        case .drumRack, .impulse, .dsClap, .dsClang, .dsCymbal, .dsHH, .dsKick, .dsSnare, .dsTone, .drumBuss:
            return .drums
        case .bhangraArchitect:
            return .bhangraArchitect
        case .guaracha2C:
            return .guaracha2C
        case .bailaton:
            return .bailaton
        case .dubstepWrangler:
            return .dubstepWrangler
        case .oscillatron:
            return .oscillatron
        case .lemmingBass, .bass:
            return .lemmingBass
        default:
            return .analog
        }
    }

    private func pluginRow(_ plugin: DiscoveredPlugin) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: plugin.role == .effect ? "slider.horizontal.3" : "pianokeys")
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(plugin.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(plugin.format.rawValue)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(LSTheme.panel2)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text(plugin.displaySubtitle)
                    .font(.caption2)
                    .foregroundStyle(LSTheme.dim)
                    .lineLimit(2)
                if plugin.format != .audioUnit {
                    Text("Drag to a track. If an AU version exists, Lemmings can prefer it for hosting; otherwise this becomes an external/bridge target slot.")
                        .font(.caption2).foregroundStyle(LSTheme.dim)
                }
            }
            Button("Add") { _ = app.dropPlugin(plugin, on: app.selectedTrack) }.controlSize(.mini)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LSTheme.panel2.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onDrag { NSItemProvider(object: PluginDragPasteboard.encode(plugin) as NSString) }
        .contextMenu {
            Button("Add / Assign to Selected Track") { _ = app.dropPlugin(plugin, on: app.selectedTrack) }
            if let path = plugin.path { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
        }
        .help("Drag onto an arrangement track, track header, device rack, mixer insert slot, or bottom drop zone")
    }

    private func icon(for kind: DeviceKind) -> String {
        switch kind {
        case .reverb, .hybridReverb: return "cloud"
        case .delay, .echo, .filterDelay, .grainDelay, .vectorDelay, .alignDelay: return "repeat"
        case .fxArchitect: return "sparkles"
        case .autoFilter, .shaper, .lfo, .envelopeFollower: return "line.3.horizontal.decrease.circle"
        case .eqEight, .channelEQ, .eqThree, .spectrum, .tuner: return "slider.horizontal.3"
        case .compressor, .glueCompressor, .multibandDynamics, .gate, .limiter: return "arrow.down.forward.and.arrow.up.backward"
        case .tune, .pitch, .shifter, .scale, .velocity, .noteLength, .random, .chord, .arpeggiator, .bouncyNotes: return "music.quarternote.3"
        case .amp, .overdrive, .pedal, .dynamicTube, .saturator, .roar, .vinylDistortion, .drumBuss: return "bolt.fill"
        case .autoPan, .beatRepeat, .chorusEnsemble, .phaserFlanger, .erosion, .redux: return "waveform"
        case .drumRack, .impulse, .dsClap, .dsClang, .dsCymbal, .dsHH, .dsKick, .dsSnare, .dsTone: return "square.grid.4x3.fill"
        case .audioEffectRack, .instrumentRack, .midiEffectRack: return "square.stack.3d.up"
        case .sampler, .simpler, .granulator, .spectralResonator, .spectralTime, .resonators, .corpus, .looper, .vocoder: return "waveform.badge.magnifyingglass"
        case .analog, .bass, .collision, .drift, .electric, .emit, .meld, .operatorSynth, .poli, .tension, .treeTone, .vectorFM, .vectorGrain, .wavetable, .oscillatron, .lemmingBass: return "keyboard"
        default: return "puzzlepiece.extension"
        }
    }
}

struct LibraryBrowserView: View {
    @Environment(AppState.self) private var app
    @State private var search = ""
    @State private var selectedPack: String? = nil

    private let packs = ["Drums", "Synths", "Bass", "Guitars", "Indian Percussion", "FX", "User Samples"]
    private let presetsByPack: [String: [String]] = [
        "Drums": ["Tech House Kit", "Percussion Pads", "Kick + Sidechain Kit", "808 Drum Matrix"],
        "Synths": ["Warm Analog Pluck", "Oscillatron Lead", "Motion Pad", "Particle Synth"],
        "Bass": ["Subby Mono Bass", "LemmingBass Round", "Zap Bass", "Sidechain Bass"],
        "Guitars": ["Amped Clean Guitar", "Tube Drive Guitar", "Pedal Board"],
        "Indian Percussion": ["Bhangra Dhol Chaal", "Dhol + Chimta Kit", "Tumbi Pulse", "Bhangra Architect"],
        "Latin / Caribbean": ["Bailaton", "Dembow Kit", "Moombah Kit", "Moombahton Kit", "Reggaeton 3-3-2"],
        "FX": ["Sidechain Pad", "Tape Stop FX", "Vocal Chop Rack", "Hybrid Space Send"],
        "User Samples": ["Choose/Scan User Library…", "Import Audio Clip…"]
    ]

    var presets: [String] {
        if let selectedPack { return presetsByPack[selectedPack] ?? [] }
        return packs.flatMap { presetsByPack[$0] ?? [] }
    }

    var filteredPresets: [String] {
        search.isEmpty ? presets : presets.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("Search library or Splice…", text: $search)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                Button { app.workspace = .session } label: { Label("Session", systemImage: "square.grid.3x3") }
                Button { app.workspace = .arrangement } label: { Label("Arrangement", systemImage: "timeline.selection") }
            }
            .controlSize(.small)

            HStack {
                Text("CATEGORIES").font(.caption2.bold()).foregroundStyle(LSTheme.dim)
                Spacer()
                if selectedPack != nil {
                    Button("All") { selectedPack = nil }.controlSize(.mini)
                }
            }
            ForEach(packs, id: \.self) { pack in
                Button { selectedPack = pack } label: {
                    HStack {
                        Image(systemName: icon(for: pack)).frame(width: 18)
                        Text(pack).font(.system(size: 12, weight: selectedPack == pack ? .bold : .regular))
                        Spacer()
                        Image(systemName: selectedPack == pack ? "checkmark.circle.fill" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(selectedPack == pack ? LSTheme.focus : LSTheme.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(7)
                .background(selectedPack == pack ? LSTheme.focus.opacity(0.18) : LSTheme.panel2.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Divider()
            Text(selectedPack.map { "\($0.uppercased()) PRESETS" } ?? "QUICK PRESETS")
                .font(.caption2.bold()).foregroundStyle(LSTheme.dim)
            ForEach(filteredPresets, id: \.self) { preset in
                Button { applyPreset(preset) } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text(preset).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .padding(7)
                .background(LSTheme.panel2.opacity(0.38))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
        }
        .padding(10)
    }

    private func applyPreset(_ preset: String) {
        switch preset {
        case "Tech House Kit", "Percussion Pads", "Kick + Sidechain Kit", "808 Drum Matrix":
            let genre: DrumGenre = preset == "808 Drum Matrix" ? .slapHouse : .techHouse
            app.quickDrumKitInArrangement(genre)
            app.selectedTrack?.name = preset
        case "Bhangra Dhol Chaal", "Dhol + Chimta Kit", "Tumbi Pulse", "Bhangra Architect":
            app.createBhangraArchitectTrack()
            app.selectedTrack?.name = preset == "Bhangra Architect" ? "Bhangra Architect" : preset
        case "Bailaton", "Dembow Kit", "Moombah Kit", "Moombahton Kit", "Reggaeton 3-3-2":
            let genre: DrumGenre = preset.contains("Moombahton") ? .moombahton : preset.contains("Moombah") ? .moombah : preset.contains("3-3-2") ? .reggaeton332 : .dembow
            app.createBailatonTrack(genre: genre)
            app.selectedTrack?.name = preset
            app.workspace = .step
        case "Subby Mono Bass", "LemmingBass Round", "Zap Bass", "Sidechain Bass":
            app.addTrack(kind: .lemmingBass)
            app.selectedTrack?.name = preset
            app.workspace = .arrangement
        case "Oscillatron Lead", "Warm Analog Pluck", "Motion Pad", "Particle Synth":
            app.addTrack(kind: preset == "Oscillatron Lead" ? .oscillatron : .analog)
            app.selectedTrack?.name = preset
            app.workspace = .arrangement
        case "Import Audio Clip…":
            app.importAudioFromPanel()
        case "Choose/Scan User Library…":
            app.chooseAndScanUserLibrary()
        case "Import Sequencer Sample Layer…":
            app.importAudioFromPanel()
        default:
            if let t = app.selectedTrack { t.name = preset; app.engine.rebuild() }
        }
    }

    private func icon(for pack: String) -> String {
        switch pack {
        case "Drums": return "circle.grid.cross"
        case "Synths": return "waveform"
        case "Bass": return "speaker.wave.2"
        case "Guitars": return "guitars"
        case "Indian Percussion": return "circle.hexagongrid"
        case "FX": return "sparkles"
        default: return "folder"
        }
    }
}


struct CompactProjectKeySelector: View {
    @Environment(AppState.self) private var app
    @State private var showCircle = false
    var rootWidth: CGFloat = 64
    var scaleWidth: CGFloat = 178

    var body: some View {
        @Bindable var project = app.project
        HStack(spacing: 5) {
            Toggle("Key Snap", isOn: $project.keySnapEnabled)
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Snap generated/edited MIDI notes to the project key")
            Picker("", selection: Binding(
                get: { project.keyRoot },
                set: { app.applyProjectKey(root: $0) }
            )) {
                ForEach(NoteName.allCases) { n in Text(n.sharpLabel).tag(n.rawValue) }
            }
            .frame(width: rootWidth)
            .labelsHidden()
            .help("Project root note")
            Picker("", selection: Binding(
                get: { project.scale.name },
                set: { name in app.applyProjectKey(scale: ScaleLibrary.all.first { $0.name == name } ?? ScaleLibrary.major) }
            )) {
                ForEach(ScaleLibrary.all) { s in Text(s.name).tag(s.name) }
            }
            .frame(width: scaleWidth)
            .labelsHidden()
            .help("Project scale")
            Button {
                showCircle.toggle()
            } label: {
                Label("Fifths", systemImage: "circle.hexagongrid.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(LSTheme.panel2.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Pick the project key from the Circle of Fifths")
            .popover(isPresented: $showCircle, arrowEdge: .bottom) {
                CircleOfFifthsView()
                    .frame(width: 390, height: 455)
                    .padding(8)
            }
        }
    }
}

struct VoiceAIStudioView: View {
    @Environment(AppState.self) private var app

    private var models: [SingingVoiceModel] { app.voiceModels.repository + app.voiceModels.imported }

    var body: some View {
        @Bindable var appState = app
        @Bindable var store = app.voiceModels
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Voice AI", systemImage: "mic.and.signal.meter").font(.headline)
                Spacer()
                Button("Import Model…") { appState.importVoiceModelFromPanel() }
                    .controlSize(.small)
            }
            Text("Consent-first voice cloning and voice-to-voice singing. Use your own voice or explicitly licensed models only.")
                .font(.caption)
                .foregroundStyle(LSTheme.dim)

            GroupBox("Voice-to-Voice / Singing Conversion") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Model", selection: Binding(
                        get: { appState.selectedVoiceModelID ?? models.first?.id ?? "" },
                        set: { appState.selectedVoiceModelID = $0 }
                    )) {
                        ForEach(models) { model in
                            Text("\(model.name) · \(model.license.rawValue)").tag(model.id)
                        }
                    }
                    .labelsHidden()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button("Choose Input Vocal…") { appState.selectVoiceAIInputAudio() }
                            if appState.voiceAIRecording {
                                Button("Stop + Use") { appState.stopVoiceAIRecording() }
                                    .tint(.red)
                                Button("Cancel") { appState.cancelVoiceAIRecording() }
                            } else {
                                Button("Record Vocal Here") { appState.startVoiceAIRecording() }
                            }
                            Text(appState.voiceAIInputAudioPath.isEmpty ? "No input selected" : URL(fileURLWithPath: appState.voiceAIInputAudioPath).lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(LSTheme.dim)
                                .lineLimit(1)
                        }
                        Text("Kits-style flow: record a clean dry take in-app, choose/convert with a consented model, then import the rendered vocal back onto the timeline.")
                            .font(.caption2)
                            .foregroundStyle(LSTheme.dim)
                    }
                    HStack {
                        Button("Output Folder…") { appState.chooseVoiceAIOutputFolder() }
                        Button("Render + Import") { appState.renderVoiceToVoice() }
                            .disabled(appState.voiceAIInputAudioPath.isEmpty || models.isEmpty)
                    }
                    Text(appState.voiceAIStatus).font(.caption).foregroundStyle(LSTheme.dim)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Voice Cloning Prep") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("I have rights/consent for this voice", isOn: $store.cloneConsentChecked)
                    Toggle("I read dataset guidance", isOn: $store.cloneDatasetGuidanceAccepted)
                    Button("Choose Training Folder…") { appState.selectVoiceCloneTrainingFolder() }
                        .disabled(!store.cloneConsentChecked || !store.cloneDatasetGuidanceAccepted)
                    Text(appState.voiceCloneTrainingFolder.isEmpty ? VoiceCloneGuide.minimumGuidance : "Dataset: \(URL(fileURLWithPath: appState.voiceCloneTrainingFolder).lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(LSTheme.dim)
                    Text(VoiceCloneGuide.requiredConsent)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 4)
            }

            Text("Installed / available models").font(.caption.bold()).foregroundStyle(LSTheme.dim)
            ForEach(models) { model in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.name).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(model.license.rawValue).font(.caption2).foregroundStyle(LSTheme.dim)
                    }
                    Text(model.style).font(.caption).foregroundStyle(LSTheme.dim)
                    Text(model.notes).font(.caption2).foregroundStyle(LSTheme.dim).lineLimit(3)
                }
                .padding(8)
                .background(LSTheme.panel2.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
    }
}

struct ProRightDock: View {
    @State private var tab: RightDockTab = .assistant

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(RightDockTab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(tab == item ? LSTheme.panel2 : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(8)
            Divider()
            ScrollView {
                switch tab {
                case .chat: GeneralChatView()
                case .assistant: AIAssistantView()
                case .sound: DescribeASoundView()
                case .splice: SpliceBrowserView()
                case .voice: VoiceAIStudioView()
                case .fifths:
                    CircleOfFifthsView()
                        .padding(10)
                case .inspector: InspectorPanel()
                }
            }
        }
        .background(LSTheme.panel)
        .foregroundStyle(LSTheme.text)
    }
}

private enum RightDockTab: String, CaseIterable, Identifiable {
    case chat = "Chat", assistant = "AI", sound = "Sound", splice = "Splice", voice = "Voices", fifths = "Fifths", inspector = "Inspect"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .assistant: return "sparkles"
        case .sound: return "waveform"
        case .splice: return "square.grid.2x2"
        case .voice: return "mic.and.signal.meter"
        case .fifths: return "circle.hexagongrid.fill"
        case .inspector: return "slider.horizontal.3"
        }
    }
}

struct SessionMatrixView: View {
    @Environment(AppState.self) private var app
    @State private var scenes = 8

    private var sceneIDs: [Int] { Swift.Array(0..<scenes) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Session", systemImage: "square.grid.3x3").font(.headline)
                Text("Launch clips/scenes · double-click empty slots to create MIDI clips")
                    .font(.caption2).foregroundStyle(LSTheme.dim)
                Spacer()
                Stepper("Scenes: \(scenes)", value: $scenes, in: 4...16)
                    .font(.caption)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("SCENES")
                            .font(.caption2.bold()).foregroundStyle(LSTheme.dim)
                            .frame(width: 86, height: 36)
                        ForEach(app.project.tracks) { track in
                            SessionTrackHeader(track: track).frame(width: 138, height: 36)
                        }
                    }
                    ForEach(sceneIDs, id: \.self) { scene in
                        HStack(spacing: 0) {
                            Button { app.launchScene(scene) } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Scene \(scene + 1)")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 86, height: 58)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(LSTheme.play)
                            .background(LSTheme.panel2.opacity(0.5))
                            .overlay(Rectangle().stroke(LSTheme.grid, lineWidth: 0.5))

                            ForEach(app.project.tracks) { track in
                                SessionSlotView(track: track, scene: scene)
                                    .frame(width: 138, height: 58)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(LSTheme.window)
        }
    }
}

struct SessionTrackHeader: View {
    @Environment(AppState.self) private var app
    @Bindable var track: Track

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(track.color).frame(width: 5, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(track.kind.rawValue).font(.system(size: 8)).foregroundStyle(LSTheme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .background(app.selectedTrackID == track.id ? track.color.opacity(0.22) : LSTheme.panel)
        .overlay(Rectangle().stroke(LSTheme.grid, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { app.selectTrack(track, extending: NSEvent.modifierFlags.contains(.shift)) }
    }
}

struct SessionSlotView: View {
    @Environment(AppState.self) private var app
    @Bindable var track: Track
    let scene: Int

    var body: some View {
        let beat = Double(scene * app.project.beatsPerBar * 4)
        let midi = track.clips.first { Int($0.startBeat / Double(app.project.beatsPerBar * 4)) == scene }
        let audio = track.audioClips.first { Int($0.startBeat / Double(app.project.beatsPerBar * 4)) == scene }

        Group {
            if let midi {
                clipButton(title: midi.name, subtitle: "MIDI · \(Int(midi.lengthBeats)) beats", color: track.color) {
                    app.launchClip(midi, on: track)
                }
            } else if let audio {
                clipButton(title: track.name, subtitle: "Audio", color: track.color) {
                    app.launchAudioClip(audio, on: track)
                }
            } else {
                Button {
                    createClip(at: beat)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: track.kind == .audio ? "waveform" : "plus")
                            .foregroundStyle(LSTheme.dim)
                        Text(track.kind == .audio ? "drop audio" : "new clip")
                            .font(.system(size: 9)).foregroundStyle(LSTheme.dim)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .background(LSTheme.panel2.opacity(0.22))
            }
        }
        .overlay(Rectangle().stroke(LSTheme.grid, lineWidth: 0.5))
    }

    private func clipButton(title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                    Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(subtitle).font(.system(size: 9)).foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(color.opacity(0.72))
        }
        .buttonStyle(.plain)
    }

    private func createClip(at beat: Double) {
        guard track.kind != .audio else { return }
        let clip = Clip(name: "Scene \(scene + 1)", startBeat: beat, lengthBeats: Double(app.project.beatsPerBar * 4), color: track.color)
        clip.notes = GenerativeFill(seed: UInt64(abs(track.name.hashValue &+ scene) & 0x7fffffff)).fill(clip: clip, project: app.project, untilBeat: clip.lengthBeats)
        track.clips.append(clip)
        app.selectedTrackID = track.id
        app.engine.rebuild()
    }
}

struct DetailDeckView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let tab = app.detailDeck
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(DetailDeckTab.allCases) { item in
                    Button(item.rawValue) { app.detailDeck = item }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(app.detailDeck == item ? LSTheme.panel2 : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
                if let selected = app.selectedTrack {
                    Text(selected.name).font(.caption).foregroundStyle(LSTheme.dim)
                }
            }
            .padding(8)
            Divider()
            switch tab {
            case .devices: DeviceRackView()
            case .clip: ClipInspectorDeck()
            case .mix: CompactMixerDeck()
            case .automation: AutomationView()
            }
        }
        .background(Color.clear)
        .foregroundStyle(LSTheme.text)
    }
}

enum DetailDeckTab: String, CaseIterable, Identifiable {
    case devices = "Devices", clip = "Clip", mix = "Mix", automation = "Automation"
    var id: String { rawValue }
}

struct ClipInspectorDeck: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let clip = app.selectedAudioClip {
                Text("Selected Audio Clip").font(.caption2.bold()).foregroundStyle(LSTheme.dim)
                HStack(spacing: 12) {
                    Image(systemName: "waveform").font(.title2)
                    VStack(alignment: .leading) {
                        Text("Audio Region").font(.headline)
                        Text("Drag audio FX directly onto the clip in Arrangement").font(.caption).foregroundStyle(LSTheme.dim)
                    }
                    Spacer()
                    Menu("Add Clip FX") {
                        ForEach(DeviceKind.categorizedBrowserSections.filter { $0.role == .audioEffect || $0.role == .analyzer }) { section in
                            Section(section.title) {
                                ForEach(section.devices) { kind in
                                    Button("\(kind.rawValue) · \(kind.role.rawValue)") { app.addEffect(kind, to: clip) }
                                }
                            }
                        }
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    parameterCard("Gain", String(format: "%+.1f dB", clip.gainDB))
                    parameterCard("Pitch", String(format: "%+d st", clip.pitchSemitones))
                    parameterCard("Fine", String(format: "%+.0f ¢", clip.pitchCents))
                    parameterCard("Warp", clip.warpEnabled ? "On" : "Off")
                    parameterCard("Tempo", String(format: "%.0f", clip.originalTempo))
                }
                AudioClipGainPitchControls(clip: clip)
                AudioClipWarpControls(clip: clip)
                if !clip.devices.isEmpty || !clip.externalPluginSlots.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(clip.devices) { device in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.kind.rawValue).font(.caption.bold())
                                    Text("clip insert").font(.caption2).foregroundStyle(LSTheme.dim)
                                    Button("Remove") { clip.devices.removeAll { $0.id == device.id } }.controlSize(.mini)
                                }
                                .padding(8).background(LSTheme.panel2.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            ForEach(clip.externalPluginSlots) { slot in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(slot.name).font(.caption.bold()).lineLimit(1)
                                    Text("external clip slot").font(.caption2).foregroundStyle(LSTheme.dim)
                                    Button("Reveal") { app.openPluginGUI(slot) }.controlSize(.mini)
                                }
                                .padding(8).background(LSTheme.panel2.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            } else if let track = app.selectedTrack {
                Text("Selected Track").font(.caption2.bold()).foregroundStyle(LSTheme.dim)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3).fill(track.color).frame(width: 18, height: 42)
                    VStack(alignment: .leading) {
                        Text(track.name).font(.headline)
                        Text(track.kind.rawValue).font(.caption).foregroundStyle(LSTheme.dim)
                    }
                    Spacer()
                    Button("Delete Track") { app.deleteTrack(track) }.disabled(app.project.tracks.count <= 1)
                    Button("New Clip") { addClip(to: track) }.disabled(track.kind == .audio)
                    Button("Generate") { generate(on: track) }.disabled(track.kind == .audio)
                    Menu("Quick Generators") {
                        Button("Bhangra Architect → MIDI Clip") { app.launchGeneratorDevice(.bhangraArchitect, mode: .midiClip) }
                        Button("Bhangra Architect → Step Sequence") { app.launchGeneratorDevice(.bhangraArchitect, mode: .stepSequence) }
                        Button("2C → MIDI Clip") { app.launchGeneratorDevice(.guaracha2C, mode: .midiClip) }
                        Button("Bailaton → Step Sequence") { app.launchGeneratorDevice(.bailaton, mode: .stepSequence) }
                        Button("Dubstep Wrangler → Step Sequence") { app.launchGeneratorDevice(.dubstepWrangler, mode: .stepSequence) }
                        Button("LemmingBass Device") { app.launchGeneratorDevice(.lemmingBass, mode: .deviceOnly) }
                        Button("Oscillatron Device") { app.launchGeneratorDevice(.oscillatron, mode: .deviceOnly) }
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    parameterCard("MIDI Clips", "\(track.clips.count)")
                    parameterCard("Audio Clips", "\(track.audioClips.count)")
                    parameterCard("Devices", "\(track.devices.count)")
                    parameterCard("Volume", String(format: "%.0f%%", track.volume * 100))
                    parameterCard("Pan", String(format: "%.0f", track.pan * 100))
                }
            } else {
                Text("Select a track or clip to edit details.").foregroundStyle(LSTheme.dim).padding()
            }
            Spacer()
        }
        .padding(12)
    }

    private func parameterCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(LSTheme.dim)
            Text(value).font(.system(size: 16, weight: .semibold, design: .monospaced))
        }
        .frame(width: 96, alignment: .leading)
        .padding(9)
        .background(LSTheme.panel2.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }


private struct AudioClipGainPitchControls: View {
    @Environment(AppState.self) private var app
    let clip: AudioClip

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clip Gain / Pitch").font(.caption.bold())
                Spacer()
                Button("Reset") {
                    clip.gainDB = 0
                    clip.pitchSemitones = 0
                    clip.pitchCents = 0
                    app.editStatus = "Reset audio clip gain/pitch"
                    rebuildIfStopped()
                }
                .controlSize(.mini)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Gain").font(.caption2).foregroundStyle(LSTheme.dim)
                        Spacer()
                        Text(String(format: "%+.1f dB", clip.gainDB)).font(.caption.monospacedDigit())
                    }
                    Slider(value: Binding(get: { clip.gainDB }, set: { clip.gainDB = $0; rebuildIfStopped() }), in: -36...24, step: 0.1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Semitones").font(.caption2).foregroundStyle(LSTheme.dim)
                        Spacer()
                        Text(String(format: "%+d st", clip.pitchSemitones)).font(.caption.monospacedDigit())
                    }
                    Stepper(value: Binding(get: { clip.pitchSemitones }, set: { clip.pitchSemitones = max(-48, min(48, $0)); rebuildIfStopped() }), in: -48...48, step: 1) {
                        Slider(value: Binding(
                            get: { Double(clip.pitchSemitones) },
                            set: { clip.pitchSemitones = max(-48, min(48, Int($0.rounded()))); rebuildIfStopped() }
                        ), in: -48...48, step: 1)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Cents").font(.caption2).foregroundStyle(LSTheme.dim)
                        Spacer()
                        Text(String(format: "%+.0f ¢", clip.pitchCents)).font(.caption.monospacedDigit())
                    }
                    Stepper(value: Binding(get: { clip.pitchCents }, set: { clip.pitchCents = max(-100, min(100, $0)); rebuildIfStopped() }), in: -100...100, step: 1) {
                        Slider(value: Binding(get: { clip.pitchCents }, set: { clip.pitchCents = max(-100, min(100, $0)); rebuildIfStopped() }), in: -100...100, step: 1)
                    }
                }
            }
        }
        .padding(10)
        .background(LSTheme.panel2.opacity(0.48), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LSTheme.glassStroke.opacity(0.7), lineWidth: 0.7)
        }
    }

    private func rebuildIfStopped() {
        if !app.engine.transport.isPlaying { app.engine.rebuild() }
    }
}

private struct AudioClipWarpControls: View {
    @Environment(AppState.self) private var app
    let clip: AudioClip
    @State private var enabled: Bool = false
    @State private var mode: WarpMode = .beat
    @State private var bpmText: String = "120"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topRow
            statusLabel
        }
        .padding(10)
        .background(LSTheme.panel2.opacity(0.48), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LSTheme.glassStroke.opacity(0.7), lineWidth: 0.7)
        }
        .onAppear(perform: syncFromClip)
        .onChange(of: clip.id) { _, _ in syncFromClip() }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            warpToggle
            warpModePicker
            tempoControls
            Spacer()
        }
    }

    private var warpToggle: some View {
        Toggle("Warp", isOn: $enabled)
            .toggleStyle(.switch)
            .onChange(of: enabled) { _, newValue in
                app.setWarp(clip, enabled: newValue, mode: mode, originalTempo: parsedTempo)
            }
    }

    private var warpModePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(WarpMode.allCases) { warpMode in
                Text(warpMode.rawValue).tag(warpMode)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 150)
        .onChange(of: mode) { _, newValue in
            app.setWarp(clip, enabled: enabled, mode: newValue, originalTempo: parsedTempo)
        }
    }

    private var tempoControls: some View {
        HStack(spacing: 5) {
            Text("Clip BPM")
                .font(.caption2.bold())
                .foregroundStyle(LSTheme.dim)
            TextField("BPM", text: $bpmText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .onSubmit { applyTempo() }
            Button("Apply", action: applyTempo)
                .controlSize(.mini)
            Button("½") { setTempo(clip.originalTempo / 2) }
                .controlSize(.mini)
            Button("×2") { setTempo(clip.originalTempo * 2) }
                .controlSize(.mini)
            detectedTempoButton
        }
    }

    @ViewBuilder
    private var detectedTempoButton: some View {
        if let detected = clip.detectedTempo {
            let detectedTitle = "Detected " + String(Int(detected))
            Button(detectedTitle, action: resetTempoToDetected)
                .controlSize(.mini)
        }
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(.caption2)
            .foregroundStyle(clip.manualTempoOverride ? LSTheme.focus : LSTheme.dim)
    }

    private var parsedTempo: Double? {
        Double(bpmText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var statusText: String {
        let detected = clip.detectedTempo.map { "detected \(Int($0)) BPM" } ?? "no detected BPM"
        let source = clip.manualTempoOverride ? "manual override" : detected
        return "Warp uses \(clip.warpMode.rawValue) at \(Int(clip.originalTempo)) BPM · \(source)"
    }

    private func syncFromClip() {
        enabled = clip.warpEnabled
        mode = clip.warpMode
        bpmText = String(format: "%.0f", clip.originalTempo)
    }

    private func applyTempo() {
        guard let bpm = parsedTempo else { return }
        app.setClipTempo(clip, bpm: bpm, enableWarp: enabled)
        syncFromClip()
    }

    private func setTempo(_ bpm: Double) {
        app.setClipTempo(clip, bpm: bpm, enableWarp: enabled)
        syncFromClip()
    }

    private func resetTempoToDetected() {
        app.resetClipTempoToDetected(clip)
        syncFromClip()
    }
}

    private func addClip(to track: Track) {
        let start = track.clips.map { $0.startBeat + $0.lengthBeats }.max() ?? 0
        let clip = Clip(name: "Clip \(track.clips.count + 1)", startBeat: start, lengthBeats: Double(app.project.beatsPerBar * 4), color: track.color)
        track.clips.append(clip)
        app.engine.rebuild()
    }

    private func generate(on track: Track) {
        if track.kind.isStepEditable {
            if track.kind == .bhangraArchitect || track.kind == .bhangraDhol || track.kind == .indianPercussion {
                track.stepPattern.loadGroove(BhangraToolkit.chaal)
            } else if track.kind == .guaracha2C {
                track.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: .guaracha))
            } else {
                track.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: track.drumGenre))
            }
            _ = app.createArrangementClipFromStepPattern(on: track, name: "Generated Groove")
            return
        }
        let start = track.clips.map { $0.startBeat + $0.lengthBeats }.max() ?? 0
        let clip = Clip(name: "Generated", startBeat: start, lengthBeats: Double(app.project.beatsPerBar * 4), color: track.color)
        clip.notes = GenerativeFill(seed: UInt64(track.clips.count + 99)).fill(clip: clip, project: app.project, untilBeat: clip.lengthBeats)
        track.clips.append(clip)
        app.engine.rebuild()
    }
}

struct CompactMixerDeck: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(app.project.tracks) { track in
                    CompactChannelStrip(track: track)
                }
                ForEach(app.project.groups) { group in
                    CompactGroupStrip(group: group)
                }
                ForEach(app.project.returnBuses) { bus in
                    CompactBusStrip(bus: bus)
                }
            }
            .padding(12)
        }
    }
}

struct CompactChannelStrip: View {
    @Environment(AppState.self) private var app
    @Bindable var track: Track

    var body: some View {
        VStack(spacing: 6) {
            Text(track.name).font(.system(size: 10, weight: .semibold)).lineLimit(1).frame(width: 92)
            MeterColumn(level: app.engine.meterPeak(for: track), color: track.color, clipped: app.engine.meterIsClipping(for: track))
                .frame(width: 12, height: 72)
            Slider(value: Binding(get: { Double(track.volume) }, set: { track.volume = Float($0) }), in: 0...1)
                .frame(width: 86)
            HStack(spacing: 5) {
                Button("M") { app.toggleMute(track) }.foregroundStyle(track.mute ? Color.orange : LSTheme.dim)
                Button("S") { app.toggleSolo(track) }.foregroundStyle(track.solo ? Color.yellow : LSTheme.dim)
                Button("A") { app.toggleTrackArm(track) }.foregroundStyle(track.armed ? Color.red : LSTheme.dim)
            }
            .buttonStyle(.plain)
            .font(.caption.bold())

            mixerDeviceStack
        }
        .padding(8)
        .background((app.selectedTrackID == track.id || app.selectedTrackIDs.contains(track.id)) ? track.color.opacity(0.18) : LSTheme.panel2.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { app.selectTrack(track, extending: NSEvent.modifierFlags.contains(.shift)) }
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    DispatchQueue.main.async { _ = app.handlePluginDropText(text, on: track) }
                }
                return true
            }
            return false
        }
    }

    private var mixerDeviceStack: some View {
        VStack(spacing: 2) {
            MixerFXDropSlot(label: track.devices.isEmpty ? "Drop FX" : "") { text in
                app.handleMixerDeviceDropText(text, on: track, at: 0)
            }
            ForEach(Array(track.devices.enumerated()), id: \.element.id) { index, device in
                mixerDevicePill(device, index: index)
                MixerFXDropSlot(label: "") { text in
                    app.handleMixerDeviceDropText(text, on: track, at: index + 1)
                }
            }
        }
        .frame(width: 88)
        .help("Drag FX above or below other FX to reorder the chain, like Live's vertical device stack.")
    }

    private func mixerDevicePill(_ device: DeviceModel, index: Int) -> some View {
        let selected = app.selectedMixerDeviceTrackID == track.id && app.selectedMixerDeviceIDs.contains(device.id)
        return HStack(spacing: 3) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(LSTheme.dim)
            Text(device.kind.rawValue).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 8, weight: .medium))
        .padding(.horizontal, 5).padding(.vertical, 3)
        .background(selected ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture {
            if app.selectedMixerDeviceTrackID != track.id { app.selectedMixerDeviceIDs.removeAll() }
            app.selectedMixerDeviceTrackID = track.id
            if NSEvent.modifierFlags.contains(.shift) {
                if selected { app.selectedMixerDeviceIDs.remove(device.id) } else { app.selectedMixerDeviceIDs.insert(device.id) }
            } else {
                app.selectedMixerDeviceIDs = [device.id]
            }
        }
        .contextMenu {
            Button("Create FX Chain from Selection") { app.makeFXChain(on: track, deviceIDs: app.selectedMixerDeviceIDs) }
                .disabled(app.selectedMixerDeviceTrackID != track.id || app.selectedMixerDeviceIDs.count < 2)
            Divider()
            if index > 0 { Button("Move Earlier") { app.moveDevice(on: track, from: IndexSet(integer: index), to: index - 1) } }
            if index < track.devices.count - 1 { Button("Move Later") { app.moveDevice(on: track, from: IndexSet(integer: index), to: index + 2) } }
        }
        .onDrag { NSItemProvider(object: PluginDragPasteboard.encodeMixerDevice(ownerKind: "track", ownerID: track.id, deviceID: device.id) as NSString) }
    }
}



struct CompactGroupStrip: View {
    @Environment(AppState.self) private var app
    @Bindable var group: TrackGroup

    var body: some View {
        VStack(spacing: 6) {
            Text(group.name).font(.system(size: 10, weight: .semibold)).lineLimit(1).frame(width: 92)
            Text("Group / Bus").font(.system(size: 8)).foregroundStyle(LSTheme.dim)
            Slider(value: Binding(get: { Double(group.volume) }, set: { group.volume = Float($0) }), in: 0...1).frame(width: 86)
            HStack {
                Button("M") { group.mute.toggle(); app.engine.rebuild() }.foregroundStyle(group.mute ? Color.orange : LSTheme.dim)
                Button("S") { group.solo.toggle(); app.engine.rebuild() }.foregroundStyle(group.solo ? Color.yellow : LSTheme.dim)
            }.buttonStyle(.plain).font(.caption.bold())
            groupDeviceStack
            Menu("Add FX") {
                ForEach(DeviceKind.categorizedBrowserSections.filter { $0.role == .audioEffect || $0.role == .analyzer }) { section in
                    Section(section.title) {
                        ForEach(section.devices) { kind in Button(kind.rawValue) { app.addEffect(kind, to: group) } }
                    }
                }
            }.controlSize(.mini)
            Button("Ungroup") {
                app.selectedTrackIDs = Set(group.trackIDs)
                app.ungroupSelectedTracks()
            }.controlSize(.mini)
        }
        .padding(8)
        .background(LSTheme.panel2.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    DispatchQueue.main.async {
                        if let kind = PluginDragPasteboard.effectKind(from: text) { app.addEffect(kind, to: group) }
                    }
                }
                return true
            }
            return false
        }
    }

    private var groupDeviceStack: some View {
        VStack(spacing: 2) {
            MixerFXDropSlot(label: group.devices.isEmpty ? "Drop FX" : "") { text in
                app.handleMixerDeviceDropText(text, on: group, at: 0)
            }
            ForEach(Array(group.devices.enumerated()), id: \.element.id) { index, device in
                groupDevicePill(device, index: index)
                MixerFXDropSlot(label: "") { text in
                    app.handleMixerDeviceDropText(text, on: group, at: index + 1)
                }
            }
        }
        .frame(width: 88)
    }

    private func groupDevicePill(_ device: DeviceModel, index: Int) -> some View {
        Text(device.kind.rawValue)
            .font(.system(size: 8, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contextMenu {
                if index > 0 { Button("Move Earlier") { group.devices.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1); app.engine.rebuild() } }
                if index < group.devices.count - 1 { Button("Move Later") { group.devices.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2); app.engine.rebuild() } }
            }
            .onDrag { NSItemProvider(object: PluginDragPasteboard.encodeMixerDevice(ownerKind: "group", ownerID: group.id, deviceID: device.id) as NSString) }
    }
}

struct CompactBusStrip: View {
    @Environment(AppState.self) private var app
    @Bindable var bus: ReturnBus

    var body: some View {
        VStack(spacing: 6) {
            Text(bus.name).font(.system(size: 10, weight: .semibold)).lineLimit(1).frame(width: 92)
            Text("Return Bus").font(.system(size: 8)).foregroundStyle(LSTheme.dim)
            Slider(value: Binding(get: { Double(bus.volume) }, set: { bus.volume = Float($0) }), in: 0...1).frame(width: 86)
            Button("M") { bus.mute.toggle(); app.engine.rebuild() }.foregroundStyle(bus.mute ? Color.orange : LSTheme.dim).buttonStyle(.plain)
            busDeviceStack
            Menu("Add FX") {
                ForEach(DeviceKind.categorizedBrowserSections.filter { $0.role == .audioEffect || $0.role == .analyzer }) { section in
                    Section(section.title) { ForEach(section.devices) { kind in Button(kind.rawValue) { app.addEffect(kind, to: bus) } } }
                }
            }.controlSize(.mini)
        }
        .padding(8)
        .background(LSTheme.panel2.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String else { return }
                DispatchQueue.main.async { _ = app.handleMixerDeviceDropText(text, on: bus, at: bus.devices.count) }
            }
            return true
        }
    }

    private var busDeviceStack: some View {
        VStack(spacing: 2) {
            MixerFXDropSlot(label: bus.devices.isEmpty ? "Drop FX" : "") { text in
                app.handleMixerDeviceDropText(text, on: bus, at: 0)
            }
            ForEach(Array(bus.devices.enumerated()), id: \.element.id) { index, device in
                busDevicePill(device, index: index)
                MixerFXDropSlot(label: "") { text in
                    app.handleMixerDeviceDropText(text, on: bus, at: index + 1)
                }
            }
        }
        .frame(width: 88)
    }

    private func busDevicePill(_ device: DeviceModel, index: Int) -> some View {
        Text(device.kind.rawValue)
            .font(.system(size: 8, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contextMenu {
                if index > 0 { Button("Move Earlier") { bus.devices.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1); app.engine.rebuild() } }
                if index < bus.devices.count - 1 { Button("Move Later") { bus.devices.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2); app.engine.rebuild() } }
            }
            .onDrag { NSItemProvider(object: PluginDragPasteboard.encodeMixerDevice(ownerKind: "bus", ownerID: bus.id, deviceID: device.id) as NSString) }
    }
}

struct MixerFXDropSlot: View {
    let label: String
    let perform: (String) -> Bool
    @State private var targeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(targeted ? Color.accentColor.opacity(0.45) : Color.accentColor.opacity(label.isEmpty ? 0.10 : 0.18))
            .frame(height: label.isEmpty ? 5 : 18)
            .overlay {
                if !label.isEmpty {
                    Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(LSTheme.dim)
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: [UTType.text], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    DispatchQueue.main.async { _ = perform(text) }
                }
                return true
            }
    }
}

struct MeterColumn: View {
    let level: Float
    let color: Color
    var clipped: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.35))
                RoundedRectangle(cornerRadius: 3).fill(clipped ? Color.red : color).frame(height: geo.size.height * CGFloat(min(1, max(0, level * 4))))
                if clipped {
                    Text("!")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
}
