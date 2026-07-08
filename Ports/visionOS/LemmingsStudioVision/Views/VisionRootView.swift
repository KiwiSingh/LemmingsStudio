import SwiftUI
import UniformTypeIdentifiers

struct VisionRootView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            VStack(spacing: 0) {
                VisionTopBar()
                Divider()
                primaryWorkspaceContent
                Divider()
                VisionStatusBar()
            }
            .opacity(model.hasCompletedStartupBranding ? 1 : 0)

            if !model.hasCompletedStartupBranding {
                VisionStartupBrandingView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
        .fileImporter(
            isPresented: $model.showImporter,
            allowedContentTypes: [.lemmingsProject, .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.openProject(at: url) }
            case .failure(let error):
                model.statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        .fileExporter(
            isPresented: $model.showProjectExporter,
            document: model.projectDocumentForExport(),
            contentType: .lemmingsProject,
            defaultFilename: model.project.name == "Untitled" ? "Untitled.lemmingsproject" : "\(model.project.name).lemmingsproject"
        ) { result in
            model.completeSaveAs(result)
        }
        .onOpenURL { model.handleAppURL($0) }
    }
    @ViewBuilder
    private var primaryWorkspaceContent: some View {
        switch model.activePrimaryWorkspace {
        case .arrangement:
            VisionArrangementView()
        case .pianoRoll:
            VisionPianoRollView()
        case .stepSequencer:
            VisionStepSequencerView()
        case .mixer:
            VisionMixerView()
        }
    }

}

private struct VisionTopBar: View {
    @Environment(VisionStudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                projectMenu
                Divider().frame(height: 30)
                transportControls
                Button { model.setMetronomeEnabled(!model.metronomeEnabled) } label: {
                    Label(model.metronomeEnabled ? "Metronome On" : "Metronome Off", systemImage: "metronome")
                }
                .buttonStyle(.bordered)
                .tint(model.metronomeEnabled ? Color.accentColor : Color.secondary)

                VisionTempoKeyControlStrip()

                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.project.name).font(.headline)
                    Text(String(format: "%.1f BPM • %@ %@", model.project.effectiveTempo, model.project.keyName ?? "C", model.project.scaleName ?? "Major"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("View")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                VisionWorkspaceQuickSwitcher()
                if model.activePrimaryWorkspace == .arrangement {
                    Button("New MIDI Clip", systemImage: "plus.rectangle.on.rectangle") {
                        _ = model.createMIDIClipOnSelectedTrack()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Keyboard", systemImage: "pianokeys") {
                    openWindow(id: "floating-midi-keyboard")
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 8)
                editingControls
                workspaceLauncher
                appearanceMenu
            }
        }
        .padding(14)
        .lemmingsGlass(cornerRadius: 24)
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var projectMenu: some View {
        Menu {
            Button("New Project", systemImage: "doc.badge.plus") { model.newProject() }
            Button("Open Project", systemImage: "folder") { model.showImporter = true }
            Button("Save Project", systemImage: "square.and.arrow.down") { model.saveProject() }
            Button("Save Project As…", systemImage: "square.and.arrow.down.on.square") { model.prepareSaveAs() }
            Divider()
            launcher("Export Song / Stems", "waveform.badge.plus", "local-export")

            if model.recoveryProjectAvailable {
                Divider()
                Button("Recover Autosave", systemImage: "clock.arrow.circlepath") { model.recoverAutosave() }
            }

            if !model.recentProjects.isEmpty {
                Divider()
                Section("Recent Projects") {
                    ForEach(model.recentProjects) { recent in
                        Button(recent.displayName, systemImage: "clock") { model.openRecentProject(recent) }
                    }
                }
            }
        } label: {
            Label("Project", systemImage: "doc.on.doc")
        }
        .buttonStyle(.bordered)
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            Button("Stop", systemImage: "stop.fill") { model.stop() }
            Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.togglePlayback()
            }
            .buttonStyle(.borderedProminent)
            Button(model.isRecordingMIDI || model.isRecordingAudio || model.isArmedForPunch ? "Recording" : "Record", systemImage: model.isRecordingMIDI || model.isRecordingAudio ? "record.circle.fill" : "record.circle") {
                model.togglePrimaryRecord()
            }
            .buttonStyle(.bordered)
            .tint(model.isRecordingMIDI || model.isRecordingAudio || model.isArmedForPunch ? Color.red : Color.secondary)
        }
        .labelStyle(.titleAndIcon)
    }

    private var editingControls: some View {
        Menu {
            Picker("Snap", selection: Bindable(model).snapDivision) {
                ForEach(VisionStudioModel.SnapDivision.allCases) { division in
                    Text(division.rawValue).tag(division)
                }
            }
        } label: {
            Label("Snap \(model.snapDivision.rawValue)", systemImage: "grid")
        }
    }

    private var workspaceLauncher: some View {
        Menu {
            Section("Edit") {
                Button("Arrangement", systemImage: "rectangle.3.group") { model.activePrimaryWorkspace = .arrangement }
                Button("Piano Roll", systemImage: "pianokeys") { model.activePrimaryWorkspace = .pianoRoll }
                Button("Step Sequencer", systemImage: "square.grid.4x3.fill") { model.activePrimaryWorkspace = .stepSequencer }
                launcher("Automation", "point.topleft.down.to.point.bottomright.curvepath", "automation")
                launcher("Circle of Fifths", "circle.hexagongrid.circle", "circle-of-fifths")
                launcher("Spatial Automation Stage", "move.3d", "spatial-automation-stage")
                launcher("Recording Takes", "square.stack.3d.up", "recording-takes")
                launcher("MIDI Keyboard", "pianokeys.inverse", "floating-midi-keyboard")
            }
            Section("Mix & Spatial") {
                Button("Mixer", systemImage: "slider.horizontal.3") { model.activePrimaryWorkspace = .mixer }
                launcher("Spatial Mixer", "cube.transparent", "spatial-mixer")
                launcher("Spatial Deck", "move.3d", "spatial-control")
                launcher("Spatial Editor", "view.3d", "spatial-editor")
                launcher("Audio Control", "waveform.circle", "audio-control")
                launcher("Stock FX Rack", "slider.horizontal.3", "stock-fx-rack")
            }
            Section("Plugins & Services") {
                launcher("Plug-in Browser", "puzzlepiece.extension", "plugin-browser")
                launcher("Mac Host Mode", "desktopcomputer", "desktop-bridge")
                launcher("Sample Browser", "waveform.badge.magnifyingglass", "sample-browser")
                launcher("Splice MCP", "waveform.badge.magnifyingglass", "splice-mcp")
                launcher("Local Export", "waveform.badge.plus", "local-export")
                launcher("Compatibility Lab", "wrench.and.screwdriver", "compatibility-lab")
                launcher("Plugin Parity", "checkmark.seal", "plugin-parity")
            }
            Section("AI & Project Intelligence") {
                launcher("AI Agent", "brain.head.profile", "agent-panel")
                launcher("MLX Runtime", "cpu", "mlx-runtime")
                launcher("Project Memory", "clock.arrow.circlepath", "project-memory")
                launcher("Semantic Graph", "point.3.connected.trianglepath.dotted", "semantic-graph")
                launcher("Parity Roadmap", "checklist.checked", "parity-roadmap")
            }
            Section("Inspect") {
                launcher("Clip Inspector", "sidebar.right", "clip-inspector")
            }
        } label: {
            Label("Workspaces", systemImage: "square.grid.2x2")
        }
        .buttonStyle(.borderedProminent)
    }

    private var appearanceMenu: some View {
        Menu {
            ForEach(VisionVisualTheme.allCases) { theme in
                Button {
                    model.visualTheme = theme
                    model.persistTheme()
                } label: {
                    Label(theme.rawValue, systemImage: theme.glyph)
                }
            }
            Divider()
            Button("Skin Gallery", systemImage: "paintpalette") { openWindow(id: "appearance") }
            Button("Replay Startup Branding", systemImage: "sparkles.tv") { model.replayStartupBranding() }
        } label: {
            Label("Appearance", systemImage: "paintpalette")
        }
    }

    private func launcher(_ title: String, _ systemImage: String, _ id: String) -> some View {
        Button {
            openWindow(id: id)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct VisionStatusBar: View {
    @Environment(VisionStudioModel.self) private var model
    var body: some View {
        HStack {
            Text(model.statusMessage)
            Spacer()
            Text(String(format: "Beat %.2f", model.playheadBeat)).monospacedDigit()
            Text("•")
            Text("\(model.project.tracks.count) tracks")
            Text("•")
            Text("Semantic \(model.semanticGraphSummary().nodeCount) nodes")
            Text("•")
            Text("Memory \(model.project.memory?.events.count ?? 0)")
            Text("•")
            Text("MIDI \(model.midiSourceSummary)")
            Text("•")
            Text("Snap \(model.snapDivision.rawValue)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
