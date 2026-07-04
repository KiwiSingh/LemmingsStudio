import SwiftUI
import AppKit

struct LemmingsSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var tab: SettingsTab = .audio

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsTab.allCases) { item in
                    Button { tab = item } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(tab == item ? Color.accentColor.opacity(0.18) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10)
            .frame(minWidth: 170, idealWidth: 185, maxWidth: 220)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .appearance: appearancePane
                    case .daw: dawPane
                    case .audio: audioPane
                    case .midi: midiPane
                    case .mpe: mpePane
                    case .pads: drumPadsPane
                    case .mappings: mappingPane
                    case .plugins: pluginPane
                    case .library: userLibraryPane
                    case .splice: splicePane
                    case .voices: voicesPane
                    case .controllers: controllersPane
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toolbar {
            Button("Save") { app.persistSettings() }
            Button("Rescan") { app.scanPlugins() }
        }
    }


    private var appearancePane: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "Appearance", subtitle: "Liquid Glass theme presets with original matching glyph systems.")
            Picker("Theme", selection: $app.visualTheme) {
                ForEach(LemmingsVisualTheme.allCases) { theme in
                    Label(theme.displayName, systemImage: theme.primaryGlyph).tag(theme)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: app.visualTheme) { _, _ in app.persistSettings() }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(LemmingsVisualTheme.allCases) { theme in
                    Button {
                        app.visualTheme = theme
                        app.persistSettings()
                    } label: {
                        ThemePreviewCard(theme: theme, selected: app.visualTheme == theme)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Theme names are vibe labels; icons are original SF Symbol-based glyph sets rather than official logos, mascots, album art, or game UI. Each palette keeps the Liquid Glass surface rules from buildfix130: translucent panels, bright edge highlights, soft bloom, readable contrast, and rounded continuous geometry.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dawPane: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "DAW", subtitle: "Transport, metronome, grid snapping, quantization, and audio import/warp defaults.")
            Form {
                Toggle("Metronome", isOn: Binding(
                    get: { app.metronomeEnabled },
                    set: { app.setMetronome($0) }
                ))
                Toggle("Count-in before recording", isOn: $app.countInEnabled)
                Picker("Count-in Length", selection: $app.countInBeats) {
                    Text("1 beat").tag(1)
                    Text("2 beats").tag(2)
                    Text("1 bar / 4 beats").tag(4)
                    Text("2 bars / 8 beats").tag(8)
                }
                Toggle("Snap to Grid", isOn: $app.snapToGridEnabled)
                Picker("Grid", selection: $app.gridSubdivisionBeats) {
                    Text("1 Bar").tag(4.0)
                    Text("1/2").tag(2.0)
                    Text("1/4").tag(1.0)
                    Text("1/8").tag(0.5)
                    Text("1/16").tag(0.25)
                    Text("1/32").tag(0.125)
                }
                Toggle("Record Quantization", isOn: $app.recordQuantizationEnabled)
                Toggle("Multi-arm tracks", isOn: $app.multiArmEnabled)
                Toggle("Multi-solo tracks", isOn: $app.multiSoloEnabled)
                Toggle("Multi-mute tracks", isOn: $app.multiMuteEnabled)
                Picker("Record Quantize", selection: $app.recordQuantizationBeats) {
                    Text("1/4").tag(1.0)
                    Text("1/8").tag(0.5)
                    Text("1/16").tag(0.25)
                    Text("1/32").tag(0.125)
                }
                Toggle("Launch full screen by default", isOn: $app.launchFullscreenEnabled)
                Toggle("Auto-warp Imported Audio", isOn: $app.autoWarpImportedAudio)
                Picker("Default Warp Mode", selection: $app.defaultWarpMode) {
                    ForEach(WarpMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
            }
            HStack {
                Button("Quantize Selected Clip") { app.quantizeSelectedClip() }
                Button("Check/Install Homebrew + Ollama") { app.bootstrapHomebrewAndOllama() }
                Spacer()
                Text(app.bootstrapStatus).foregroundStyle(.secondary)
            }
            Text("Ollama model weights remain external. The app can install/check brew + Ollama, then the AI panel can pull models as needed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var audioPane: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "Audio", subtitle: "Driver, input/output device preferences, latency, and sample rate.")
            Form {
                Picker("Driver", selection: $app.audioDriverName) {
                    Text("CoreAudio").tag("CoreAudio")
                    Text("Aggregate Device").tag("Aggregate Device")
                    Text("External Interface").tag("External Interface")
                }
                Picker("Input Device", selection: $app.audioInputDeviceUID) {
                    ForEach(app.recorder.inputDevices) { device in
                        Text(device.name + (device.isDefault ? " · current default" : "") + " · \(device.channelCount)ch").tag(device.uid)
                    }
                }
                .onChange(of: app.audioInputDeviceUID) { _, uid in app.setDefaultAudioInputDevice(uid: uid) }
                HStack {
                    Text("Output Device")
                    TextField("Output Device", text: $app.audioOutputDevice)
                }
                Picker("Sample Rate", selection: $app.preferredSampleRate) {
                    Text("44.1 kHz").tag(44100.0)
                    Text("48 kHz").tag(48000.0)
                    Text("88.2 kHz").tag(88200.0)
                    Text("96 kHz").tag(96000.0)
                }
                Picker("Buffer Size", selection: $app.preferredBufferSize) {
                    ForEach([64, 128, 256, 512, 1024, 2048], id: \.self) { size in
                        Text("\(size) samples").tag(size)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Refresh Audio Devices") { app.refreshAudioInputDevices() }
                Text(app.recorder.inputName).font(.caption).foregroundStyle(.secondary)
            }
            Text("Audio tracks can now pick the actual CoreAudio input device — Revelator Dynamic, Continuity/iPhone mic, USB interfaces, aggregate devices — and then choose Input 1/2/etc. per track in Arrangement.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var midiPane: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "MIDI", subtitle: "Input ports, controller monitoring, and MIDI learn status.")
            Toggle("Enable MIDI input", isOn: $app.midiInputEnabled)
            Toggle("MIDI mapping mode", isOn: $app.midiMappingMode)
            Toggle("MIDI monitor / sanity log", isOn: $app.midiMonitorEnabled)
            HStack {
                Button("Refresh MIDI Ports") { app.setupMIDI() }
                Text("\(app.midiSourceNames.count) source(s)").foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: app.pendingMIDILearnTarget == nil ? "dot.radiowaves.left.and.right" : "record.circle")
                Text(app.midiLearnStatus)
                    .font(.caption)
                    .foregroundStyle(app.pendingMIDILearnTarget == nil ? .secondary : .primary)
                Spacer()
                if app.pendingMIDILearnTarget != nil {
                    Button("Cancel Learn") { app.cancelMIDILearn() }
                        .controlSize(.small)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if app.midiSourceNames.isEmpty {
                Text("No MIDI input sources detected yet.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(app.midiSourceNames, id: \.self) { name in
                        HStack { Image(systemName: "pianokeys"); Text(name); Spacer(); Text("Input").foregroundStyle(.secondary) }
                            .padding(8).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            if app.midiMonitorEnabled {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Recent MIDI data")
                            .font(.caption.bold())
                        Spacer()
                        Button("Clear") { app.midiMonitorEvents.removeAll() }
                            .controlSize(.small)
                    }
                    if app.midiMonitorEvents.isEmpty {
                        Text("Move a knob, press a key, or touch pitch bend on the MPK Mini IV to verify the decoded MIDI payload.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ForEach(app.midiMonitorEvents.prefix(10), id: \.self) { line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var mpePane: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "MPE / Pitch Bend", subtitle: "Pitch bend, aftertouch, CC74 timbre, and MPE channel-zone routing for expressive controllers and synths like Serum 2.")
            Form {
                Picker("Expression mode", selection: $app.mpeMode) {
                    ForEach(MPEMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                Stepper(value: $app.mpePitchBendRange, in: 1...96) {
                    Text("Pitch bend range: ±\(app.mpePitchBendRange) semitone(s)")
                }
                Stepper(value: $app.mpeMasterChannel, in: 0...15) {
                    Text("Master channel: \(app.mpeMasterChannel + 1)")
                }
                Stepper(value: $app.mpeMemberChannelStart, in: 0...15) {
                    Text("Member channel start: \(app.mpeMemberChannelStart + 1)")
                }
                Stepper(value: $app.mpeMemberChannelEnd, in: 0...15) {
                    Text("Member channel end: \(app.mpeMemberChannelEnd + 1)")
                }
                Toggle("Map CC74 to Timbre / Slide", isOn: $app.mpeMapCC74ToTimbre)
                Toggle("Enable channel/poly pressure", isOn: $app.mpePressureEnabled)
            }
            HStack {
                Label(app.mpeStatus, systemImage: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Serum-style MPE") {
                    app.mpeMode = .lowerZone
                    app.mpePitchBendRange = 48
                    app.mpeMasterChannel = 0
                    app.mpeMemberChannelStart = 1
                    app.mpeMemberChannelEnd = 15
                    app.mpeMapCC74ToTimbre = true
                    app.mpePressureEnabled = true
                    app.persistSettings()
                }
            }
            Text("For hosted AU instruments, LemmingsStudio forwards channelized note on/off, per-channel pitch bend, pressure, and CC74. For built-in Analog, pitch bend is global. VST/VST3 entries still need an AU or bridge before they can receive live MIDI directly.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }


    private var drumPadsPane: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "Drum Pads", subtitle: "MPK Mini, PreSonus ATOM, MPC-style pad routing, transposition, and MIDI learn.")
            Form {
                Picker("Pad preset", selection: $app.drumPadPreset) {
                    ForEach(DrumPadPreset.allCases) { preset in Text(preset.rawValue).tag(preset) }
                }
                Stepper(value: $app.drumPadTranspose, in: -48...48) {
                    Text("Transpose: \(app.drumPadTranspose) semitone(s)")
                }
                Picker("Learn target", selection: $app.drumPadLearnVoice) {
                    ForEach(DrumVoiceID.allCases) { voice in Text(voice.label).tag(voice) }
                }
            }
            HStack {
                Button(app.drumPadLearnMode ? "Waiting for Pad…" : "Learn Next Pad") { app.drumPadLearnMode.toggle() }
                Button("Reset MPK Mini") { app.drumPadPreset = .mpkMini; app.drumPadTranspose = 0 }
                Button("Reset ATOM / GM") { app.drumPadPreset = .generalMIDI; app.drumPadTranspose = 0 }
                Spacer()
                Text(app.drumPadLastHit).foregroundStyle(.secondary).lineLimit(1)
            }
            TextEditor(text: $app.drumPadCustomMapText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 130)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            Text("Custom map format: `36: kick`, `38: snare`, `42: closedhat`. Select/arm a Drum Machine track, then external pad notes are translated to the drum engine's General MIDI notes before playback.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mappingPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "Mappings", subtitle: "Keyboard shortcuts and MIDI mapping actions.")
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                shortcutRow("Space", "Play / Pause")
                shortcutRow("Backspace / Delete", "Delete selected track")
                shortcutRow("⌘Z", "Undo last edit")
                shortcutRow("⇧⌘Z / ⌘Y", "Redo last edit")
                shortcutRow("⇧⌘P", "Rescan plug-ins")
                shortcutRow("⇧⌘R", "Rebuild audio engine")
            }
            Text("Shortcut editing UI is scaffolded here; current shortcuts are active globally outside text fields.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var pluginPane: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "Plug-ins", subtitle: "AU/VST3/VST scan folders and plug-in indexing.")
            TextEditor(text: $app.pluginScanFoldersText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 130)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            HStack {
                Button("Reset Defaults") { app.pluginScanFoldersText = PluginScanner.defaultSearchPaths.joined(separator: "\n") }
                Button("Scan Now") { app.persistSettings(); app.scanPlugins() }
                Spacer()
                Text(app.pluginScanStatus).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("AU effects/instruments can be indexed through the system. VST/VST3 are currently browsed and assigned as external slots unless an AU counterpart exists.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var userLibraryPane: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "User Library", subtitle: "Choose the folder LemmingsStudio scans for your one-shots, loops, MIDIs, and downloaded/open sample packs.")
            Form {
                TextField("User Library Folder", text: $app.userLibraryFolder)
                HStack {
                    Button("Choose Folder…") { app.chooseAndScanUserLibrary() }
                    Button("Scan Library") { app.persistSettings(); app.scanUserLibrary() }
                        .disabled(app.userLibraryFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Use Default") {
                        app.userLibraryFolder = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Music/Lemmings Studio/User Library", isDirectory: true).path
                        app.persistSettings()
                        app.scanUserLibrary()
                    }
                }
            }
            Text(app.userLibraryScanStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text("This is intentionally separate from Splice settings. Splice can keep using its working MCP/download flow; this tab only controls the local library folder that the DAW browser indexes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var voicesPane: some View {
        @Bindable var store = app.voiceModels
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "Singing Voices", subtitle: "Consent-first voice conversion repository, manual model import, and cloning guidance.")
            HStack {
                Toggle("I have rights/consent for cloning datasets", isOn: $store.cloneConsentChecked)
                Toggle("I read dataset guidance", isOn: $store.cloneDatasetGuidanceAccepted)
            }
            Text(VoiceCloneGuide.requiredConsent).font(.caption).foregroundStyle(.orange)
            Text(VoiceCloneGuide.minimumGuidance).font(.caption).foregroundStyle(.secondary)
            ForEach(store.repository + store.imported) { model in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(model.name).font(.headline); Spacer(); Text(model.license.rawValue).foregroundStyle(.secondary) }
                    Text(model.style).font(.caption)
                    Text(model.notes).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(8).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button("Import Model…") {
                    let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = true; panel.canChooseFiles = true
                    if panel.runModal() == .OK, let url = panel.url { store.importModel(at: url) }
                }
                Spacer(); Text(store.status).foregroundStyle(.secondary)
            }
        }
    }

    private var controllersPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "Controller Presets", subtitle: "Built-in maps for common MIDI keyboards, pad controllers, and macro knobs.")
            ForEach(MIDIControllerPresetLibrary.presets) { preset in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(preset.name).font(.headline); Spacer(); Text(preset.maker).foregroundStyle(.secondary) }
                    Text(preset.notes).font(.caption).foregroundStyle(.secondary)
                    Text("CCs: \(preset.ccMap.map { "\($0.key)→\($0.value)" }.sorted().joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(8).background(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var splicePane: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: 14) {
            SettingsHeader(title: "Splice", subtitle: "MCP endpoint, OAuth, and download location.")
            Form {
                TextField("MCP URL", text: $app.spliceMCPURL)
                TextField("OAuth Authorization Server", text: $app.spliceOAuthAuthorizationServer)
                TextField("OAuth Client ID", text: $app.spliceOAuthClientID)
                TextField("Authorize URL", text: $app.spliceOAuthAuthURL)
                TextField("Token URL", text: $app.spliceOAuthTokenURL)
                TextField("Dynamic Registration URL", text: $app.spliceOAuthRegistrationURL)
                TextField("Redirect URI", text: $app.spliceOAuthRedirectURI)
                TextField("Scope", text: $app.spliceOAuthScope)
                TextField("Download Folder", text: $app.spliceDownloadDirectory)
            }
            HStack {
                Button("Save OAuth Settings") { app.persistSpliceOAuthSettings() }
                Button("Discover + Browser Login") { app.openSpliceMCPLoginPage() }
                Button("Connect MCP") { Task { await app.connectSplice() } }
            }
            Text(app.spliceStatus).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func shortcutRow(_ keys: String, _ action: String) -> some View {
        GridRow {
            Text(keys).font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(action)
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance = "Appearance", daw = "DAW", audio = "Audio", midi = "MIDI", mpe = "MPE / Bend", pads = "Drum Pads", mappings = "Mappings", plugins = "Plug-ins", library = "User Library", splice = "Splice", voices = "Voices", controllers = "Controllers"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .appearance: return "sparkles.rectangle.stack"
        case .daw: return "slider.horizontal.3"
        case .audio: return "speaker.wave.3"
        case .midi: return "pianokeys"
        case .mpe: return "waveform.path.ecg"
        case .pads: return "square.grid.3x3.fill"
        case .mappings: return "keyboard"
        case .plugins: return "puzzlepiece.extension"
        case .library: return "folder.badge.gearshape"
        case .splice: return "square.grid.2x2"
        case .voices: return "waveform.badge.mic"
        case .controllers: return "dial.medium"
        }
    }
}

private struct ThemePreviewCard: View {
    let theme: LemmingsVisualTheme
    let selected: Bool

    private var palette: LemmingsThemePalette { LSTheme.palette(for: theme) }

    var body: some View {
        let p = palette
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(theme.displayName, systemImage: theme.primaryGlyph)
                    .font(.headline)
                Spacer()
                Text(theme.logoGlyph).font(.title3)
            }
            Text(theme.subtitle)
                .font(.caption)
                .foregroundStyle(p.dim)
                .lineLimit(2)
            HStack(spacing: 8) {
                ForEach(theme.motifGlyphs, id: \.self) { glyph in
                    Image(systemName: glyph)
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(p.panel2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Spacer()
                Capsule().fill(p.focus).frame(width: 38, height: 8)
            }
        }
        .padding(12)
        .foregroundStyle(p.text)
        .background {
            ZStack {
                LinearGradient(colors: [p.backgroundA, p.backgroundB, p.backgroundC], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [p.glowA.opacity(0.25), .clear], center: .topTrailing, startRadius: 8, endRadius: 170)
                RadialGradient(colors: [p.glowB.opacity(0.20), .clear], center: .bottomLeading, startRadius: 8, endRadius: 180)
                p.panel
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? p.focus : p.glassStroke, lineWidth: selected ? 2.0 : 0.8)
        }
        .shadow(color: .black.opacity(0.22), radius: selected ? 14 : 8, x: 0, y: 8)
    }
}

private struct SettingsHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}
