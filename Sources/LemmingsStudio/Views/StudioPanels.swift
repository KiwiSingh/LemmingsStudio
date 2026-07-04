import SwiftUI
import AppKit

// MARK: - Studio panel (export / stems / bounce / warp / tempo)

struct StudioPanelView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ExportSection()
            Divider()
            StemSection()
            Divider()
            FreezeSection()
            Divider()
            WarpSection()
            Divider()
            TempoSection()
        }
        .padding(12)
    }
}

// MARK: Export

private struct ExportSection: View {
    @Environment(AppState.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Export", systemImage: "square.and.arrow.up").font(.headline)
            Text("Offline render of the whole project (same engine as playback, +1s reverb tail).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                ForEach(ExportFormat.allCases) { fmt in
                    Button(fmt.rawValue) { app.export(format: fmt) }
                        .buttonStyle(.bordered)
                }
            }
            if app.exportIsActive {
                ProgressView(value: app.exportProgress) {
                    Text("Export progress")
                } currentValueLabel: {
                    Text("\(Int((app.exportProgress * 100).rounded()))%")
                }
                .progressViewStyle(.linear)
            }
            if !app.exportStatus.isEmpty {
                Text(app.exportStatus)
                    .font(.caption)
                    .foregroundStyle(app.exportDidClip ? .red : .secondary)
            }
            if app.exportDidClip {
                Label("Last export clipped. Lower the master/track faders or add limiting headroom before sharing.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Text("WAV/FLAC/AAC encode natively. MP3 needs ffmpeg or lame on PATH.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: Stems

private struct StemSection: View {
    @Environment(AppState.self) private var app
    @State private var model: StemModel = .htdemucs_6s
    @State private var backend: StemBackend = .auto
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Stem Splitter (Demucs)", systemImage: "waveform.path.ecg").font(.headline)
            Picker("Backend", selection: $backend) {
                ForEach(StemBackend.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: backend) { _, newValue in app.selectedStemBackend = newValue }

            Picker("Model", selection: $model) {
                ForEach(StemModel.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.menu).labelsHidden()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(model.stems, id: \.self) { stem in
                    Toggle(stem.capitalized, isOn: Binding(
                        get: { app.selectedStemOutputs.contains(stem) },
                        set: { enabled in
                            if enabled { app.selectedStemOutputs.insert(stem) }
                            else { app.selectedStemOutputs.remove(stem) }
                        }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }
            Menu("Output routing") {
                Toggle("Merge selected stems to one audio track", isOn: Binding(get: { app.stemMergeToSingleAudioTrack }, set: { app.stemMergeToSingleAudioTrack = $0 }))
                Toggle("Create submix group for stem tracks", isOn: Binding(get: { app.stemCreateSubmixGroup }, set: { app.stemCreateSubmixGroup = $0 }))
            }
            Button("Separate selected audio clip to new tracks…") { app.runStemSplit(model: model, backend: backend) }
                .buttonStyle(.borderedProminent)
                .disabled(app.selectedAudioClip == nil)
            if app.stemProgress > 0 && app.stemProgress < 1 {
                ProgressView(value: app.stemProgress)
                Text("Extracting stems… \(Int((app.stemProgress * 100).rounded()))%")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !app.stemStatus.isEmpty {
                Text(app.stemStatus).font(.caption).foregroundStyle(.secondary)
            }
            if !app.stemResults.isEmpty {
                ForEach(app.stemResults.sorted(by: { $0.key < $1.key }), id: \.key) { stem, url in
                    HStack {
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                        Text(stem.capitalized).font(.caption).bold()
                        Spacer()
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            }
            Text(backend.note)
                .font(.caption2).foregroundStyle(.tertiary)
            Text("htdemucs_6s adds guitar + piano stems when the selected backend supports those weights. Saxophone has no open-source SOTA model — closest is the ‘other’ stem.")
                .font(.caption2).foregroundStyle(.tertiary)
            Text("Select an audio clip in Arrangement first. Official Demucs needs `pip3 install demucs`; MLX/Core ML runners can be bundled or pointed to with LEMMINGS_DEMUCS_MLX_BIN / LEMMINGS_HTDEMUCS_COREML_BIN.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: Freeze / bounce

private struct FreezeSection: View {
    @Environment(AppState.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Freeze / Bounce", systemImage: "snowflake").font(.headline)
            Text("Render a track to audio to free CPU. Unfreeze to edit again.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(app.project.tracks) { track in
                HStack {
                    Image(systemName: track.frozen ? "snowflake" : "circle")
                        .foregroundStyle(track.frozen ? Color.cyan : Color.secondary)
                    Text(track.name).font(.caption)
                    Spacer()
                    Button(track.frozen ? "Unfreeze" : "Freeze") { app.toggleFreeze(track) }
                        .buttonStyle(.bordered).font(.caption)
                        .disabled(track.kind == .audio)
                }
            }
        }
    }
}

// MARK: Warp

private struct WarpSection: View {
    @Environment(AppState.self) private var app
    var clips: [(Track, AudioClip)] {
        app.project.tracks.flatMap { t in t.audioClips.map { (t, $0) } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Warp (audio clips)", systemImage: "metronome").font(.headline)
            if clips.isEmpty {
                Text("Record or import audio to warp it to the project tempo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Swift.Array(0..<clips.count), id: \.self) { index in
                let pair = clips[index]
                WarpRow(track: pair.0, clip: pair.1)
            }
        }
    }
}

private struct WarpRow: View {
    @Environment(AppState.self) private var app
    let track: Track
    let clip: AudioClip
    @State private var enabled: Bool = false
    @State private var mode: WarpMode = .beat
    @State private var origTempo: Double = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("Warp", isOn: $enabled).labelsHidden()
                Text(track.name).font(.caption).bold()
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(WarpMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(width: 130)
            }
            HStack {
                Text("Clip BPM").font(.caption2).foregroundStyle(.secondary)
                TextField("", value: $origTempo, format: .number).frame(width: 60).textFieldStyle(.roundedBorder)
                Spacer()
                Button("Apply") {
                    app.setWarp(clip, enabled: enabled, mode: mode, originalTempo: origTempo)
                }.buttonStyle(.bordered).font(.caption)
                if let detected = clip.detectedTempo {
                    Button("Detected \(Int(detected))") {
                        app.resetClipTempoToDetected(clip)
                        origTempo = clip.originalTempo
                    }.buttonStyle(.bordered).font(.caption)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { enabled = clip.warpEnabled; mode = clip.warpMode; origTempo = clip.originalTempo }
    }
}

// MARK: Tempo automation

private struct TempoSection: View {
    @Environment(AppState.self) private var app
    @State private var beat = "0"
    @State private var bpm = "124"

    var body: some View {
        @Bindable var proj = app.project
        VStack(alignment: .leading, spacing: 8) {
            Label("Tempo Automation", systemImage: "chart.xyaxis.line").font(.headline)
            Toggle("Enable tempo curve", isOn: $proj.tempoAutomationEnabled)
                .onChange(of: app.project.tempoAutomationEnabled) { _, _ in app.rebuildTempoMap() }
            HStack {
                TextField("Beat", text: $beat).frame(width: 60).textFieldStyle(.roundedBorder)
                TextField("BPM", text: $bpm).frame(width: 60).textFieldStyle(.roundedBorder)
                Button("Add point") {
                    if let b = Double(beat), let t = Double(bpm) {
                        app.project.tempoPoints.append(TempoPoint(beat: b, bpm: t))
                        app.project.tempoPoints.sort { $0.beat < $1.beat }
                        app.rebuildTempoMap()
                    }
                }.buttonStyle(.bordered)
            }
            ForEach(Swift.Array(0..<app.project.tempoPoints.count), id: \.self) { index in
                let p = app.project.tempoPoints[index]
                HStack {
                    Text("beat \(p.beat, specifier: "%.2f") → \(p.bpm, specifier: "%.1f") BPM").font(.caption)
                    Spacer()
                    Button(role: .destructive) {
                        app.project.tempoPoints.remove(at: index); app.rebuildTempoMap()
                    } label: { Image(systemName: "trash") }.buttonStyle(.borderless).font(.caption)
                }
            }
            if app.project.tempoPoints.isEmpty {
                Text("Add points to ramp/step the tempo across the song. Audio clips re-warp automatically.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
