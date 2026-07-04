import SwiftUI
import Foundation
import AppKit
import Observation
import WebKit

// MARK: - Transport bar

struct TransportBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var project = app.project
        TimelineView(.animation) { _ in
            HStack(spacing: 14) {
                Text("🐹 Lemmings Studio")
                    .font(.system(size: 14, weight: .bold))

                Button { app.togglePlay() } label: {
                    Image(systemName: app.engine.transport.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 36, height: 28)
                }
                .help("Play / pause (Space)")

                Button { app.scrub(to: 0) } label: {
                    Image(systemName: "backward.end.fill").frame(width: 26, height: 24)
                }
                .help("Return to start")

                Button { app.toggleMetronome() } label: {
                    Image(systemName: "metronome")
                        .foregroundStyle(app.metronomeEnabled ? Color.yellow : Color.secondary)
                        .frame(width: 26, height: 24)
                }
                .help("Metronome on/off (⌘M)")

                VStack(alignment: .leading, spacing: 1) {
                    Text(barBeatString(app.engine.currentBeat))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    Text("BAR.BEAT")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 92, alignment: .leading)

                HStack(spacing: 4) {
                    Text("BPM").font(.caption).foregroundStyle(.secondary)
                    TempoTextField(compact: true)
                }

                Divider().frame(height: 24)

                HStack(spacing: 6) {
                    Text("Key").font(.caption).foregroundStyle(.secondary)
                    CompactProjectKeySelector(rootWidth: 64, scaleWidth: 178)
                }
                if project.scale.isMicrotonalApproximation {
                    Text("≈12-TET").font(.caption2).foregroundStyle(.orange)
                }

                Spacer()
                Button { app.workspace = .arrangement } label: { Label("Arrangement", systemImage: "rectangle.split.3x1") }
                Button { app.inspector = .ai } label: { Label("AI", systemImage: "sparkles") }
                Button { app.inspector = .splice } label: { Label("Splice", systemImage: "square.grid.2x2") }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private func barBeatString(_ beat: Double) -> String {
        let beatsPerBar = max(1, app.project.beatsPerBar)
        let whole = max(0, Int(floor(beat)))
        let bar = whole / beatsPerBar + 1
        let beatInBar = whole % beatsPerBar + 1
        let tick = Int(((beat - floor(beat)) * 100).rounded())
        return String(format: "%02d.%02d.%02d", bar, beatInBar, tick)
    }
}

// MARK: - Track sidebar

struct TrackSidebar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TRACKS").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(InstrumentKind.allCases) { kind in
                        Button(kind.rawValue) { app.addTrack(kind: kind) }
                    }
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton).frame(width: 28)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            Divider()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(app.project.tracks) { track in
                        TrackRow(track: track)
                    }
                }.padding(8)
            }

            if let t = app.selectedTrack, t.kind == .analog {
                Divider()
                AnalogQuickRack(track: t)
                    .padding(10)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct TrackRow: View {
    @Environment(AppState.self) private var app
    @Bindable var track: Track

    var body: some View {
        let selected = app.selectedTrackID == track.id || app.selectedTrackIDs.contains(track.id)
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(track.color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(track.kind.rawValue).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("M") { app.toggleMute(track) }
                .buttonStyle(.plain).foregroundStyle(track.mute ? Color.orange : Color.secondary).font(.caption.bold())
            Button("S") { app.toggleSolo(track) }
                .buttonStyle(.plain).foregroundStyle(track.solo ? Color.yellow : Color.secondary).font(.caption.bold())
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            let extending = NSEvent.modifierFlags.contains(.shift)
            app.selectTrack(track, extending: extending)
        }
        .contextMenu {
            Button("Group Selected Tracks") { app.groupSelectedTracks() }
            Button("Ungroup Selected Tracks") { app.ungroupSelectedTracks() }
            Divider()
            Button("Delete", role: .destructive) {
                if app.selectedTrackIDs.contains(track.id) && app.selectedTrackIDs.count > 1 { app.deleteSelectedTracks() }
                else { app.deleteTrack(track) }
            }
        }
    }
}

struct AnalogQuickRack: View {
    @Environment(AppState.self) private var app
    let track: Track
    @State private var refresh = false

    private var synth: AnalogSynth? {
        // The engine owns the live instrument; we edit its preset in place.
        app.engine.liveAnalog(for: track)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ANALOG").font(.caption.bold()).foregroundStyle(.secondary)
            if let synth = synth {
                knob("Cutoff", value: Binding(
                    get: { synth.preset.cutoff }, set: { synth.preset.cutoff = $0; refresh.toggle() }),
                     range: 100...10000)
                knob("Reso", value: Binding(
                    get: { synth.preset.resonance }, set: { synth.preset.resonance = $0; refresh.toggle() }),
                     range: 0...0.95)
                knob("Attack", value: Binding(
                    get: { synth.preset.attack }, set: { synth.preset.attack = $0; refresh.toggle() }),
                     range: 0.001...1.5)
                knob("Release", value: Binding(
                    get: { synth.preset.release }, set: { synth.preset.release = $0; refresh.toggle() }),
                     range: 0.02...2)
            } else {
                Text("Select an analog track").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func knob(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).frame(width: 50, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.0f", value.wrappedValue >= 10 ? value.wrappedValue : value.wrappedValue * 1000))
                .font(.system(size: 9, design: .monospaced)).frame(width: 36)
        }
    }
}

// MARK: - Inspector

struct InspectorPanel: View {
    @Environment(AppState.self) private var app
    var body: some View {
        @Bindable var appB = app
        VStack(spacing: 0) {
            Picker("", selection: $appB.inspector) {
                ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().padding(8)
            Divider()
            ScrollView {
                switch app.inspector {
                case .circle:   CircleOfFifthsView()
                case .chords:   ChordGeneratorView()
                case .describe: DescribeASoundView()
                case .ai:       AIAssistantView()
                case .plugins:  InstrumentTargetView()
                case .midi:     MIDIControllersView()
                case .studio:   StudioPanelView()
                case .splice:   SpliceBrowserView()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Circle of fifths (Fender Studio-style wheel)

struct CircleOfFifthsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var project = app.project
        VStack(spacing: 12) {
            Text("Circle of Fifths").font(.headline).padding(.top, 8)
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        .frame(width: size*0.92, height: size*0.92)
                    ForEach(Swift.Array(0..<CircleOfFifths.order.count), id: \.self) { index in
                        let pc = CircleOfFifths.order[index]
                        let angle = Double(index)/12 * 2 * .pi - .pi/2
                        keyButton(major: pc, at: angle, center: center, radius: size*0.40, major: true)
                        keyButton(major: CircleOfFifths.relativeMinor(of: pc), at: angle, center: center,
                                  radius: size*0.24, major: false, displayPC: CircleOfFifths.relativeMinor(of: pc))
                    }
                }
            }
            .frame(height: 280)

            let sig = CircleOfFifths.keySignature(major: project.keyRoot)
            Text(sig == 0 ? "No sharps/flats"
                 : sig > 0 ? "\(sig) sharp\(sig > 1 ? "s" : "")"
                 : "\(-sig) flat\(-sig > 1 ? "s" : "")")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                pill("V", NoteName(rawValue: CircleOfFifths.dominant(of: project.keyRoot))!.sharpLabel)
                pill("IV", NoteName(rawValue: CircleOfFifths.subdominant(of: project.keyRoot))!.sharpLabel)
                pill("rel.", NoteName(rawValue: CircleOfFifths.relativeMinor(of: project.keyRoot))!.sharpLabel + "m")
            }
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private func keyButton(major pc: PitchClass, at angle: Double, center: CGPoint,
                           radius: CGFloat, major: Bool, displayPC: PitchClass? = nil) -> some View {
        let dpc = displayPC ?? pc
        let isCurrent = app.project.keyRoot == dpc &&
            (major ? app.project.scale.name == ScaleLibrary.major.name
                   : app.project.scale.name == ScaleLibrary.naturalMinor.name)
        let x = center.x + radius * CGFloat(cos(angle))
        let y = center.y + radius * CGFloat(sin(angle))
        Button {
            app.applyProjectKey(root: dpc, scale: major ? ScaleLibrary.major : ScaleLibrary.naturalMinor)
        } label: {
            Text(NoteName(rawValue: dpc)!.sharpLabel + (major ? "" : "m"))
                .font(.system(size: major ? 13 : 10, weight: isCurrent ? .bold : .regular))
                .frame(width: major ? 38 : 30, height: major ? 38 : 30)
                .background(Circle().fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.15)))
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .position(x: x, y: y)
    }

    private func pill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold))
        }
    }
}

// MARK: - Chord generator

struct ChordGeneratorView: View {
    @Environment(AppState.self) private var app
    @State private var sevenths = false
    @State private var templateIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generative Chords").font(.headline).padding(.top, 8)
            Text(app.project.key.displayName).font(.caption).foregroundStyle(.secondary)

            Toggle("Use 7th chords", isOn: $sevenths)

            Text("Diatonic chords").font(.caption.bold()).foregroundStyle(.secondary)
            FlowChips(chords: ChordGenerator.diatonicChords(key: app.project.key, sevenths: sevenths)) { play($0) }

            Divider()
            Text("Progression").font(.caption.bold()).foregroundStyle(.secondary)
            Picker("", selection: $templateIndex) {
                ForEach(Swift.Array(0..<ChordGenerator.progressionTemplates.count), id: \.self) { index in
                    let template = ChordGenerator.progressionTemplates[index]
                    Text(template.name).tag(index)
                }
            }.labelsHidden()

            let prog = ChordGenerator.progression(
                key: app.project.key,
                template: ChordGenerator.progressionTemplates[templateIndex].degrees,
                sevenths: sevenths)
            FlowChips(chords: prog) { play($0) }

            Button {
                dropProgression(prog)
            } label: {
                Label("Drop progression to arrangement", systemImage: "plus.rectangle.on.rectangle")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
    }

    private func play(_ chord: Chord) {
        guard let track = app.selectedTrack else { return }
        for n in chord.midiNotes(octave: 4) { app.engine.audition(track: track, note: app.project.snap(n.number), on: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            for n in chord.midiNotes(octave: 4) { app.engine.audition(track: track, note: app.project.snap(n.number), on: false) }
        }
    }

    private func dropProgression(_ prog: [Chord]) {
        guard let track = app.selectedTrack else { return }
        let clip = Clip(name: "Chords", startBeat: 0, lengthBeats: Double(prog.count * 2), color: track.color)
        for (i, chord) in prog.enumerated() {
            for n in chord.midiNotes(octave: 4) {
                clip.notes.append(ClipNote(pitch: app.project.snap(n.number),
                                           start: Double(i*2), length: 1.8, velocity: 0.85))
            }
        }
        track.clips.append(clip)
    }
}

struct FlowChips: View {
    let chords: [Chord]
    let onTap: (Chord) -> Void
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 56), spacing: 6)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
            ForEach(chords) { chord in
                Button(chord.symbol) { onTap(chord) }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Describe a sound

struct DescribeASoundView: View {
    @Environment(AppState.self) private var app
    @State private var prompt = "warm detuned analog pad"
    @State private var status = ""
    @State private var working = false
    @State private var transcript = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound Agent").font(.headline).padding(.top, 8)
            Text("Describe a sound; the agent designs a patch for the selected track's instrument target and applies it.")
                .font(.caption).foregroundStyle(.secondary)

            AIBackendPicker()

            if let t = app.selectedTrack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                        Text("Target instrument / plugin")
                            .font(.caption.bold())
                        Spacer()
                        Button("Scan") { app.scanPlugins() }.controlSize(.small)
                    }
                    Picker("", selection: Binding(
                        get: { t.pluginTargetID ?? "Built-in Analog" },
                        set: { t.pluginTargetID = $0 == "Built-in Analog" ? nil : $0; app.engine.rebuild() }
                    )) {
                        ForEach(app.soundTargetNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text(app.pluginScanStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if t.kind != .analog && t.pluginTargetID == nil {
                        Text("Pick Built-in Analog, Vital, AU, VST3, or VST. AU instruments can be hosted; VST/VST3 are indexed and used as design targets until a VST bridge is added.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            TextField("e.g. squelchy acid bass", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...4)

            Button { Task { await design() } } label: {
                HStack { if working { ProgressView().controlSize(.small) }
                    Label("Design patch", systemImage: "wand.and.stars") }
            }.disabled(working)

            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(status.hasPrefix("⚠️") ? Color.orange : Color.green)
            }
            if !transcript.isEmpty {
                Text(transcript).font(.caption2).foregroundStyle(.secondary)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
    }

    @MainActor
    private func design() async {
        working = true
        status = ""
        transcript = ""
        guard let target = app.prepareSoundAgentTarget(resetForNewPatch: true) else {
            status = "⚠️ Select a track with an instrument first."
            working = false
            return
        }
        let design = await SoundAgent(backend: app.currentBackend()).design(description: prompt, for: target)
        do {
            let summary = try target.apply(design)
            status = "✓ \(design.presetName)"
            transcript = summary + (design.notes.isEmpty ? "" : "\n\(design.notes)")
            working = false
        } catch {
            status = "⚠️ \(error.localizedDescription)"
            working = false
        }
    }
}


// MARK: - Isolated text input for Splice / plugin-adjacent browser surfaces

struct SpliceIsolatedTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var width: CGFloat? = nil
    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onCommit: onCommit) }

    func makeNSView(context: Context) -> NSSecureTextFieldFreeText {
        let field = NSSecureTextFieldFreeText()
        field.placeholderString = placeholder
        field.stringValue = text
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.target = context.coordinator
        field.action = #selector(Coordinator.commitFromAction(_:))
        field.delegate = context.coordinator
        if let width { field.widthAnchor.constraint(equalToConstant: width).isActive = true }
        return field
    }

    func updateNSView(_ nsView: NSSecureTextFieldFreeText, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onCommit: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
        }

        @objc func commitFromAction(_ sender: NSTextField) {
            text.wrappedValue = sender.stringValue
            DispatchQueue.main.async { [onCommit] in onCommit() }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            UserDefaults.standard.set(true, forKey: "LemmingsStudio.ProtectedTextEntryActive")
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            UserDefaults.standard.set(false, forKey: "LemmingsStudio.ProtectedTextEntryActive")
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
                commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                text.wrappedValue = textView.string
                DispatchQueue.main.async { [onCommit] in onCommit() }
                return true
            }
            return false
        }
    }
}

final class NSSecureTextFieldFreeText: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Keep DAW-level key handlers out of Splice/plugin-adjacent text entry.
        // Return is handled by the field editor/delegate above; Delete/Backspace
        // remain normal text editing and should never bubble into track deletion.
        super.keyDown(with: event)
    }
}

// MARK: - Splice browser

enum SpliceSampleTypeFilter: String, CaseIterable, Identifiable {
    case all, loops, oneshots
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .loops: return "Loops"
        case .oneshots: return "One-shots"
        }
    }
    /// Value sent to Splice's describe_a_sound `type` enum (loop/oneshot); nil = no filter.
    var mcpValue: String? {
        switch self {
        case .all: return nil
        case .loops: return "loop"
        case .oneshots: return "oneshot"
        }
    }
}

struct SpliceBrowserView: View {
    @Environment(AppState.self) private var app
    @State private var query = "industrial house 124 bpm drum loop"
    @State private var showingAdvanced = false
    @State private var showingOAuth = true
    @State private var pastedOAuthCode = ""
    @State private var filterKey = ""
    @State private var filterBPM = ""
    @State private var filterGenre = ""
    @State private var sampleType: SpliceSampleTypeFilter = .all
    @State private var resultsPage = 0
    @State private var mcpURL = ""
    @State private var bearerToken = ""
    @State private var downloadDirectory = ""
    @State private var settingsLoaded = false

    private let resultsPerPage = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Splice MCP").font(.headline).padding(.top, 8)
                Spacer()
                Button("Connect") { Task { await app.connectSplice() } }
                    .controlSize(.small)
            }

            HStack {
                SpliceIsolatedTextField(placeholder: "Search samples by feel, instrument, label…", text: $query, onCommit: searchWithFilters)
                Button("Search") { searchWithFilters() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Picker("Type", selection: $sampleType) {
                    ForEach(SpliceSampleTypeFilter.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: sampleType) { _, _ in searchWithFilters() }

                HStack(spacing: 6) {
                    SpliceIsolatedTextField(placeholder: "Key", text: $filterKey, width: 56, onCommit: searchWithFilters)
                        .frame(width: 56)
                    SpliceIsolatedTextField(placeholder: "BPM", text: $filterBPM, width: 62, onCommit: searchWithFilters)
                        .frame(width: 62)
                    SpliceIsolatedTextField(placeholder: "Genre", text: $filterGenre, onCommit: searchWithFilters)
                    Button("Clear") {
                        filterKey = ""; filterBPM = ""; filterGenre = ""; sampleType = .all
                        searchWithFilters()
                    }
                    .controlSize(.small)
                }
                Text("Loops/one-shots and BPM are sent to Splice; key/genre also filter locally when metadata returns. Drag results into Arrangement or a Step Sequencer slot — fetch-on-drop uses official MCP.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup("Official Splice remote MCP", isExpanded: $showingOAuth) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Use Splice's supported streamable HTTP MCP endpoint. Licensing/downloads stay on the official MCP/OAuth path; browser WebView preview is disabled in beta for stability.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("type: streamable-http  •  url: https://mcp.splice.com/mcp")
                        .font(.caption2).monospaced().textSelection(.enabled)
                    Text("Auth metadata: authorization_servers → https://mcp.splice.com · scopes → openid profile email offline_access")
                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack(spacing: 8) {
                        Button { app.resetSpliceToOfficialRemoteMCP(); Task { await app.connectSplice() } } label: {
                            Label("Use Official Endpoint", systemImage: "link.badge.plus")
                        }
                        Button { app.openSpliceMCPLoginPage() } label: {
                            Label("Discover + Browser Login", systemImage: "safari")
                        }
                        Button("Docs") { NSWorkspace.shared.open(SpliceOfficialMCP.docs) }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)

            DisclosureGroup("MCP settings", isExpanded: $showingAdvanced) {
                VStack(alignment: .leading, spacing: 6) {
                    SpliceIsolatedTextField(placeholder: "MCP URL", text: $mcpURL, onCommit: applyMCPSettings)
                    SpliceIsolatedTextField(placeholder: "Debug bearer/session token — leave blank for official browser MCP", text: $bearerToken, onCommit: applyMCPSettings)
                    Text("Token pasting is intentionally not part of the supported Splice beta flow. This field is only for partner/debug builds. Public-preview tricks from unofficial clients are intentionally not used for downloads.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        SpliceIsolatedTextField(placeholder: "Download folder", text: $downloadDirectory, onCommit: applyMCPSettings)
                        Button("Choose…") { chooseDownloadFolder() }
                    }
                    HStack(spacing: 8) {
                        Button("Apply Settings") { applyMCPSettings() }
                        Button("Open Splice MCP page") {
                            NSWorkspace.shared.open(URL(string: "https://splice.com/tools/mcp-server")!)
                        }
                        if !app.spliceTools.isEmpty {
                            Text(app.spliceTools.map(\.name).joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)

            DisclosureGroup("Open sample library downloader") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloads are optional and stored in your User Library/Open Samples folder. Lemmings does not silently bundle third-party audio; verify license text before redistribution.")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(AppState.OpenSampleSource.allCases) { source in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.rawValue).font(.caption.bold())
                                Text(source.licenseNote).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(source.url == nil ? "Info" : "Download") { app.downloadOpenSampleLibrary(source) }
                                .controlSize(.small)
                        }
                    }
                    Text(app.openSampleStatus).font(.caption2).foregroundStyle(app.openSampleStatus.hasPrefix("⚠️") ? Color.orange : Color.secondary)
                }
                .padding(.top, 4)
            }
            .font(.caption)

            Text(app.spliceStatus)
                .font(.caption2)
                .foregroundStyle(app.spliceStatus.hasPrefix("⚠️") ? Color.orange : Color.secondary)

            if app.spliceResults.isEmpty {
                Text("Search goes through Splice’s official remote streamable HTTP MCP server. First use may require browser login.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else if filteredSpliceResults.isEmpty {
                Text("No results match the current local key/BPM/genre filters. Try clearing a filter or searching broader.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                SpliceResultsAppKitList(samples: pagedSpliceResults, app: app, onTagClick: applySpliceTagFilter)
                    .frame(height: pagedListHeight)
                if pageCount > 1 {
                    HStack(spacing: 10) {
                        Button { if resultsPage > 0 { resultsPage -= 1 } } label: {
                            Image(systemName: "chevron.left")
                        }
                        .controlSize(.small)
                        .disabled(resultsPage == 0)
                        Text("Page \(resultsPage + 1) of \(pageCount)")
                            .font(.caption2).foregroundStyle(.secondary)
                        Button { if resultsPage < pageCount - 1 { resultsPage += 1 } } label: {
                            Image(systemName: "chevron.right")
                        }
                        .controlSize(.small)
                        .disabled(resultsPage >= pageCount - 1)
                        Spacer()
                        Text("\(filteredSpliceResults.count) result\(filteredSpliceResults.count == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .onChange(of: app.spliceResults.count) { _, _ in resultsPage = 0 }
        .onAppear {
            syncMCPSettingsIfNeeded()
            if app.spliceResults.isEmpty { searchWithFilters() }
        }
    }

    /// Results for the current page. The official MCP returns one block per search
    /// (no server-side offset), so paging is over the locally filtered set — this
    /// keeps the list short enough that rows never overlap or overflow the panel.
    private var pagedSpliceResults: [SpliceSample] {
        let all = filteredSpliceResults
        guard !all.isEmpty else { return [] }
        let start = min(resultsPage * resultsPerPage, max(0, all.count - 1))
        let end = min(start + resultsPerPage, all.count)
        return Array(all[start..<end])
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(filteredSpliceResults.count) / Double(resultsPerPage))))
    }

    private var pagedListHeight: CGFloat {
        let rowHeight: CGFloat = 118
        let count = CGFloat(max(1, pagedSpliceResults.count))
        return min(max(140, count * rowHeight), CGFloat(resultsPerPage) * rowHeight)
    }

    private var filteredSpliceResults: [SpliceSample] {
        app.spliceResults.filter { sample in
            let keyOK: Bool = {
                let wanted = filterKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !wanted.isEmpty else { return true }
                return sample.key?.lowercased().replacingOccurrences(of: " ", with: "") == wanted.replacingOccurrences(of: " ", with: "")
            }()
            let bpmOK: Bool = {
                let raw = filterBPM.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return true }
                guard let wanted = Int(raw), let bpm = sample.bpm else { return true }
                return abs(bpm - wanted) <= 3
            }()
            let genreOK: Bool = {
                let wanted = filterGenre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !wanted.isEmpty else { return true }
                var fields = [sample.name]
                fields.append(contentsOf: [sample.packName, sample.creatorName, sample.instrument, sample.soundType].compactMap { $0 })
                fields.append(contentsOf: sample.tags)
                let haystack = fields.joined(separator: " ").lowercased()
                return haystack.contains(wanted)
            }()
            return keyOK && bpmOK && genreOK
        }
    }


    private func syncMCPSettingsIfNeeded() {
        guard !settingsLoaded else { return }
        settingsLoaded = true
        mcpURL = app.spliceMCPURL
        bearerToken = app.spliceBearerToken
        downloadDirectory = app.spliceDownloadDirectory
    }

    private func applyMCPSettings() {
        app.spliceMCPURL = mcpURL.trimmingCharacters(in: .whitespacesAndNewlines)
        app.spliceBearerToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        app.spliceDownloadDirectory = downloadDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredSearchQuery: String {
        var parts = [query.trimmingCharacters(in: .whitespacesAndNewlines)]
        let key = filterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let bpm = filterBPM.trimmingCharacters(in: .whitespacesAndNewlines)
        let genre = filterGenre.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { parts.append("key " + key) }
        if !bpm.isEmpty { parts.append(bpm + " bpm") }
        if !genre.isEmpty { parts.append(genre) }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func searchWithFilters() {
        let searchText = filteredSearchQuery
        resultsPage = 0
        let type = sampleType.mcpValue
        var bpmMin: Int? = nil
        var bpmMax: Int? = nil
        if let wanted = Int(filterBPM.trimmingCharacters(in: .whitespacesAndNewlines)) {
            bpmMin = max(20, wanted - 3)
            bpmMax = wanted + 3
        }
        DispatchQueue.main.async {
            Task { await app.searchSplice(query: searchText, type: type, bpmMin: bpmMin, bpmMax: bpmMax) }
        }
    }

    private func applySpliceTagFilter(_ tag: String) {
        let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if filterGenre.isEmpty {
            filterGenre = cleaned
        } else if !filterGenre.lowercased().contains(cleaned.lowercased()) {
            filterGenre += " " + cleaned
        }
        searchWithFilters()
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            downloadDirectory = url.path
            applyMCPSettings()
        }
    }
}


private struct SpliceResultsAppKitList: NSViewRepresentable {
    let samples: [SpliceSample]
    let app: AppState
    var onTagClick: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(app: app, onTagClick: onTagClick) }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    func updateNSView(_ stack: NSStackView, context: Context) {
        context.coordinator.app = app
        context.coordinator.onTagClick = onTagClick
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for sample in samples {
            let row = SpliceAppKitSampleRow(sample: sample, app: app, coordinator: context.coordinator)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
            stack.addArrangedSubview(row)
        }
    }

    final class Coordinator: NSObject {
        var app: AppState
        var onTagClick: (String) -> Void

        init(app: AppState, onTagClick: @escaping (String) -> Void) {
            self.app = app
            self.onTagClick = onTagClick
        }

        @objc func previewClicked(_ sender: SpliceSampleActionButton) {
            guard let sample = sender.sample else { return }
            DispatchQueue.main.async { [app] in app.previewSplice(sample) }
        }

        @objc func tagClicked(_ sender: SpliceSampleActionButton) {
            guard let tag = sender.spliceTag else { return }
            DispatchQueue.main.async { [onTagClick] in onTagClick(tag) }
        }
    }
}

private final class SpliceSampleActionButton: NSButton {
    var sample: SpliceSample?
    var spliceTag: String?
}

private final class SpliceAppKitSampleRow: NSView, NSDraggingSource {
    private let sample: SpliceSample
    private weak var app: AppState?
    private var mouseDownEvent: NSEvent?

    init(sample: SpliceSample, app: AppState, coordinator: SpliceResultsAppKitList.Coordinator) {
        self.sample = sample
        self.app = app
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.075).cgColor
        layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
        layer?.borderWidth = 1
        build(coordinator: coordinator)
    }

    required init?(coder: NSCoder) { nil }

    private var hasPlayablePreview: Bool {
        sample.previewURL != nil || sample.downloadURL != nil || sample.localFileURL != nil
    }

    private var canFetchAudio: Bool {
        hasPlayablePreview || sample.hiddenAssetUUID != nil
    }

    private func build(coordinator: SpliceResultsAppKitList.Coordinator) {
        let v = NSStackView()
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 6
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            v.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            v.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 106)
        ])

        let title = NSTextField(labelWithString: sample.name)
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 2
        v.addArrangedSubview(title)

        let subtitleText = sample.subtitle.isEmpty ? "Splice sample" : sample.subtitle
        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = NSFont.systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        v.addArrangedSubview(subtitle)

        let meta = [sample.bpm.map { "\($0) BPM" }, sample.key, sample.soundType, sample.durationText]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !meta.isEmpty {
            let metaField = NSTextField(labelWithString: meta)
            metaField.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            metaField.textColor = .secondaryLabelColor
            metaField.lineBreakMode = .byTruncatingTail
            v.addArrangedSubview(metaField)
        }

        if !sample.tags.isEmpty {
            let tags = NSStackView()
            tags.orientation = .horizontal
            tags.spacing = 4
            tags.alignment = .leading
            for tag in sample.tags.prefix(4) {
                let b = SpliceSampleActionButton(title: tag, target: coordinator, action: #selector(SpliceResultsAppKitList.Coordinator.tagClicked(_:)))
                b.spliceTag = tag
                b.bezelStyle = .rounded
                b.controlSize = .mini
                tags.addArrangedSubview(b)
            }
            v.addArrangedSubview(tags)
        }

        let h = NSStackView()
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 8
        let previewTitle: String = canFetchAudio ? "Preview" : "Open Page"
        let preview = SpliceSampleActionButton(title: previewTitle, target: coordinator, action: #selector(SpliceResultsAppKitList.Coordinator.previewClicked(_:)))
        preview.sample = sample
        preview.bezelStyle = .rounded
        preview.controlSize = .small
        preview.isEnabled = canFetchAudio || sample.pageURL != nil
        h.addArrangedSubview(preview)
        let badge = NSTextField(labelWithString: canFetchAudio ? "FETCH ON DROP" : (sample.pageURL != nil ? "OPEN PAGE" : "MCP FETCH"))
        badge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        badge.textColor = .secondaryLabelColor
        h.addArrangedSubview(badge)
        v.addArrangedSubview(h)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        // Always emit the same Splice sample payload. Even page-only rows should
        // attempt official MCP resolve/license/download on drop; hiding behind a
        // separate “web-preview only” pasteboard type made Arrangement drops feel
        // like they did absolutely nothing.
        let payload = PluginDragPasteboard.encodeSpliceSample(id: sample.id)
        app?.spliceStatus = "Dragging ‘\(sample.name)’ — Arrangement/Step drop will fetch via official Splice MCP."
        let item = NSPasteboardItem()
        item.setString(payload, forType: .string)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: dragImage())
        beginDraggingSession(with: [draggingItem], event: start, source: self)
        mouseDownEvent = nil
    }

    private func dragImage() -> NSImage {
        let image = NSImage(size: NSSize(width: max(bounds.width, 220), height: max(bounds.height, 72)))
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: image.size), xRadius: 10, yRadius: 10).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        NSString(string: sample.name).draw(in: NSRect(x: 10, y: image.size.height - 28, width: image.size.width - 20, height: 20), withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}


private struct SpliceWaveformPreviewStrip: View {
    private let bars = Array(0..<28)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(bars, id: \.self) { i in
                let height = CGFloat(6 + ((i * 17) % 23))
                let opacity = 0.28 + Double((i * 7) % 10) / 20.0
                RoundedRectangle(cornerRadius: 1.5)
                    .frame(width: 3, height: height)
                    .opacity(opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpliceWebPreviewSheet: View {
    @Environment(AppState.self) private var app
    let url: URL
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Splice Web Preview")
                        .font(.headline)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
                Button("Done") { app.closeSpliceWebPreview() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            SpliceWebPreview(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Text("Preview is rendered from Splice’s own page in a WebView. Drag/download still uses the authenticated MCP path and Splice credits/quota when MCP exposes a fetchable asset.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SpliceWebPreview: NSViewRepresentable {
    @Environment(AppState.self) private var app
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(app: app) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        Task { @MainActor in app.captureSpliceWebPreviewURL(url) }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.app = app
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
            Task { @MainActor in app.captureSpliceWebPreviewURL(url) }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var app: AppState

        init(app: AppState) { self.app = app }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if let url = webView.url { Task { @MainActor in app.captureSpliceWebPreviewURL(url) } }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url { Task { @MainActor in app.captureSpliceWebPreviewURL(url) } }
            let js = """
            JSON.stringify({
                url: window.location.href,
                title: document.title,
                html: document.documentElement ? document.documentElement.outerHTML : document.body.innerHTML
            })
            """
            webView.evaluateJavaScript(js) { [weak self, weak webView] value, _ in
                guard let self else { return }
                let currentURL = webView?.url
                var payload = ""
                if let text = value as? String, let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    payload = [json["url"] as? String, json["title"] as? String, json["html"] as? String]
                        .compactMap { $0 }
                        .joined(separator: "\n")
                } else if let text = value as? String {
                    payload = text
                }
                guard !payload.isEmpty else { return }
                Task { @MainActor in self.app.captureSpliceWebPreviewHTML(payload, url: currentURL) }
            }
        }
    }
}

struct SpliceSampleRow: View {
    @Environment(AppState.self) private var app
    let sample: SpliceSample
    var onTagClick: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(sample.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if let duration = sample.durationText { chip(duration, systemImage: "clock") }
                    }
                    if !sample.subtitle.isEmpty {
                        Text(sample.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if let b = sample.bpm { chip("\(b) BPM", systemImage: "metronome") }
                        if let k = sample.key { chip(k, systemImage: "music.note") }
                        if let type = sample.soundType { chip(type, systemImage: "waveform") }
                    }
                    if !sample.tags.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(Swift.Array(sample.tags.prefix(5)), id: \.self) { tag in
                                Button { onTagClick(tag) } label: {
                                    Text(tag)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.11))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .help("Filter Splice results by ‘\(tag)’")
                            }
                        }
                    }
                }
            }

            SpliceWaveformPreviewStrip()
                .padding(.vertical, 2)

            HStack(spacing: 8) {
                Button { app.previewSplice(sample) } label: {
                    Label(previewTitle, systemImage: previewIcon)
                }
                .controlSize(.small)
                .disabled(!canFetchAudio && sample.pageURL == nil)
                .help(canFetchAudio ? "Preview or fetch this Splice asset in LemmingsStudio" : "Open the Splice page externally; embedded WebView preview is disabled in beta.")

                if canFetchAudio {
                    Text(sample.hiddenAssetUUID != nil && !hasPlayablePreview ? "UUID RESOLVED" : "FETCH ON DROP")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14))
                        .clipShape(Capsule())
                } else if sample.pageURL != nil {
                    Text("OPEN PAGE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14))
                        .clipShape(Capsule())
                }
                Spacer()
                Text(sample.pageURL != nil && !canFetchAudio ? "Drag to Arrangement / Step slot to fetch via MCP, or open the page externally" : "Drag to Arrangement / Step slot")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.075))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12)))
        )
        .opacity(sample.pageURL != nil && !canFetchAudio ? 0.95 : 1.0)
        .onDrag {
            app.spliceStatus = "Dragging ‘\(sample.name)’ — Arrangement/Step drop will fetch via official Splice MCP."
            return NSItemProvider(object: PluginDragPasteboard.encodeSpliceSample(id: sample.id) as NSString)
        }
    }

    private var hasPlayablePreview: Bool {
        sample.previewURL != nil || sample.downloadURL != nil || sample.localFileURL != nil
    }

    private var canFetchAudio: Bool {
        hasPlayablePreview || sample.hiddenAssetUUID != nil
    }

    private var previewTitle: String {
        if app.splicePreviewingID == sample.id { return "Stop" }
        return canFetchAudio ? "Preview" : "Open Page"
    }

    private var previewIcon: String {
        if app.splicePreviewingID == sample.id { return "stop.fill" }
        return canFetchAudio ? "play.fill" : "arrow.up.forward.app"
    }

    @ViewBuilder private var artwork: some View {
        if let url = sample.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack { Color.secondary.opacity(0.16); Image(systemName: "waveform").foregroundStyle(.secondary) }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.14))
                Image(systemName: sample.soundType?.lowercased().contains("loop") == true ? "repeat" : "waveform")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 46, height: 46)
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
    }
}
