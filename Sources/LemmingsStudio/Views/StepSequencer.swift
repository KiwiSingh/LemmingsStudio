import SwiftUI
import UniformTypeIdentifiers

struct StepSequencerView: View {
    @Environment(AppState.self) private var app

    private var track: Track? { app.selectedTrack }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Step Sequencer").font(.headline)
                Spacer()
                if let t = track {
                    Toggle("Drive track from sequencer", isOn: Binding(
                        get: { t.useStepSequencer }, set: { t.useStepSequencer = $0 }))
                        .toggleStyle(.switch)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            if let track = track {
                sequencerToolbar(track)
                if track.kind == .indianPercussion || track.kind == .bhangraDhol || track.kind == .bhangraArchitect {
                    grooveBar(track)
                }
                if track.kind == .drums || track.kind == .sequencer || track.kind == .guaracha2C || track.kind == .bailaton || track.kind == .dubstepWrangler {
                    drumGrooveBar(track)
                }
                ScrollView([.horizontal, .vertical]) {
                    grid(track)
                        .padding(12)
                }
            } else {
                Spacer(); Text("Select a track.").foregroundStyle(.secondary); Spacer()
            }
        }
    }

    private func sequencerToolbar(_ track: Track) -> some View {
        HStack(spacing: 8) {
            Toggle("Arm", isOn: Binding(get: { track.armed }, set: { _ in app.toggleTrackArm(track) }))
                .toggleStyle(.button)
                .controlSize(.small)
            Button("New Sequencer") { app.createSequencerTrack() }.controlSize(.small)
            Menu("Kits") {
                Button("Tech House Kit") { app.applyDrumKit(.techHouse, to: track, loadGroove: true) }
                Button("Guaracha Kit") { app.applyDrumKit(.guaracha, to: track, loadGroove: true) }
                Button("Bailaton / Dembow Kit") { app.applyDrumKit(.dembow, to: track, loadGroove: true) }
                Button("EDM Kit") { app.applyDrumKit(.edm, to: track, loadGroove: true) }
                Button("Lo-Fi Kit") { app.applyDrumKit(.lofi, to: track, loadGroove: true) }
                Button("Breakbeat Kit") { app.applyDrumKit(.breakbeat, to: track, loadGroove: true) }
                Button("Dubstep Wrangler Kit") { app.applyDrumKit(.dubstep, to: track, loadGroove: true) }
                Button("Rock Kit") { app.applyDrumKit(.rock, to: track, loadGroove: true) }
                Button("Orchestral Kit") { app.applyDrumKit(.orchestral, to: track, loadGroove: true) }
            }.controlSize(.small)
            Button("Drum Machine") {
                app.applyDrumKit(.techHouse, to: track, loadGroove: false)
            }.controlSize(.small)
            Button("Import Sample Layer…") { app.importSequencerSampleLayerFromPanel() }.controlSize(.small)
            Divider().frame(height: 18)
            Button("Print to Arrangement") {
                app.printStepPatternToNewArrangementTrack(from: track)
            }
            .controlSize(.small)
            .help("Create a new Arrangement track containing this step pattern as editable MIDI notes.")
            Spacer()
            Text("Drop any one-shot onto a row/slot to replace it; Print makes editable MIDI in Arrangement.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func grooveBar(_ track: Track) -> some View {
        HStack(spacing: 8) {
            Text("Bhangra grooves:").font(.caption).foregroundStyle(.secondary)
            ForEach(BhangraToolkit.all) { groove in
                Button(groove.name) {
                    app.applyBhangraGroove(groove, to: track)
                }.controlSize(.small)
            }
            Spacer()
            Button("Clear") {
                app.clearStepPattern(on: track)
            }.controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func drumGrooveBar(_ track: Track) -> some View {
        HStack(spacing: 8) {
            Text("Drum grooves:").font(.caption).foregroundStyle(.secondary)
            ForEach(DrumGenre.allCases) { genre in
                Button(genre.rawValue) {
                    app.applyDrumGroove(genre, to: track)
                }.controlSize(.small)
            }
            Spacer()
            Button("Clear") {
                app.clearStepPattern(on: track)
            }.controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // Rows: strokes, samples, plug-ins, and drum channels. Avoid exposing raw
    // MIDI-note names unless this is a plain melodic track with no sequencer kit.
    private func rows(for track: Track) -> [(label: String, note: Int)] {
        if track.kind == .indianPercussion || track.kind == .bhangraDhol || track.kind == .bhangraArchitect {
            let layers = track.sequencerLayers.isEmpty ? BhangraToolkit.layers : track.sequencerLayers
            return layers.map { ($0.displayName(project: app.project), $0.note) }
        }

        if track.useStepSequencer {
            let layers = track.sequencerLayers.isEmpty ? SequencerLayer.emptyKit() : track.sequencerLayers
            return layers.map { layer in
                let suffix = layer.source == .splice ? " · sample" : layer.source == .plugin ? " · plugin" : ""
                return (layer.displayName(project: app.project) + suffix, layer.note)
            }
        }

        if track.kind == .drums || track.kind == .guaracha2C || track.kind == .bailaton || track.kind == .dubstepWrangler || track.kind == .sequencer {
            return DrumVoiceID.allCases.map { ($0.label, $0.midiNote) }
        }

        let notes = app.project.key.scale.notes(root: app.project.key.root, from: 60, to: 72)
        return notes.reversed().map { ($0.name, $0.number) }
    }

    private func grid(_ track: Track) -> some View {
        let pattern = track.stepPattern
        let rowsList = rows(for: track)
        return VStack(spacing: 3) {
            // step header with live indicator
            HStack(spacing: 3) {
                Spacer().frame(width: 156)
                TimelineView(.animation) { _ in
                    let live = liveStep(pattern)
                    HStack(spacing: 3) {
                        ForEach(Swift.Array(0..<pattern.stepCount), id: \.self) { i in
                            Circle()
                                .fill(i == live && app.engine.transport.isPlaying ? Color.red : Color.secondary.opacity(0.25))
                                .frame(width: 6, height: 6)
                                .frame(width: 26)
                        }
                    }
                }
            }
            ForEach(Swift.Array(0..<rowsList.count), id: \.self) { rowIndex in
                let row = rowsList[rowIndex]
                HStack(spacing: 3) {
                    HStack(spacing: 5) {
                        Text(row.label)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .frame(width: 82, alignment: .trailing)
                        laneControls(track: track, note: row.note)
                    }
                    .frame(width: 156, alignment: .trailing)
                    .help("Drop one-shots or instrument plug-ins here. Plug-in lanes play the project root note, with octave/pan/volume controls.")
                    .contextMenu {
                        Button("Clear whole lane") { clearLane(track, note: row.note) }
                    }
                    .onDrop(of: [UTType.text, UTType.fileURL, .audio], isTargeted: nil) { providers in
                        handleSequencerDrop(providers, track: track, step: nil, note: row.note)
                    }
                    ForEach(Swift.Array(0..<pattern.stepCount), id: \.self) { i in
                        let active = pattern.isOn(step: i, note: row.note)
                        let beatGroup = (i / pattern.stepsPerBeat) % 2 == 0
                        Button {
                            toggle(pattern, step: i, note: row.note)
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(active ? track.color
                                      : Color.secondary.opacity(beatGroup ? 0.12 : 0.06))
                                .frame(width: 26, height: 22)
                                .overlay(alignment: .bottomTrailing) {
                                    if active { Circle().fill(Color.white.opacity(0.7)).frame(width: 4, height: 4).padding(3) }
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Add this step") { app.addStepHit(on: track, step: i, note: row.note) }
                            Button("Clear this step") { app.clearStepHit(on: track, step: i, note: row.note) }
                            Divider()
                            Button("Clear whole lane") { clearLane(track, note: row.note) }
                        }
                        .onDrop(of: [UTType.text, UTType.fileURL, .audio], isTargeted: nil) { providers in
                            handleSequencerDrop(providers, track: track, step: i, note: row.note)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func laneControls(track: Track, note: Int) -> some View {
        if let layerID = track.sequencerLayers.first(where: { $0.note == note })?.id {
            HStack(spacing: 3) {
                Stepper("", value: safeLaneIntBinding(track: track, layerID: layerID, keyPath: \.octaveOffset, range: -3...3, resetEngine: true), in: -3...3)
                    .labelsHidden()
                    .frame(width: 28)
                    .help("Lane octave: \(safeLaneOctaveLabel(track: track, layerID: layerID))")

                Slider(value: safeLaneFloatBinding(track: track, layerID: layerID, keyPath: \.pan, range: -1...1), in: -1...1)
                    .frame(width: 28)
                    .help("Lane pan")

                Slider(value: safeLaneFloatBinding(track: track, layerID: layerID, keyPath: \.volume, range: 0...1.5), in: 0...1.5)
                    .frame(width: 28)
                    .help("Lane volume")
            }
        } else {
            Spacer().frame(width: 92)
        }
    }

    private func safeLaneOctaveLabel(track: Track, layerID: UUID) -> String {
        let value = track.sequencerLayers.first(where: { $0.id == layerID })?.octaveOffset ?? 0
        return "\(value >= 0 ? "+" : "")\(value)"
    }

    private func safeLaneIntBinding(track: Track, layerID: UUID, keyPath: WritableKeyPath<SequencerLayer, Int>, range: ClosedRange<Int>, resetEngine: Bool = false) -> Binding<Int> {
        Binding(
            get: {
                track.sequencerLayers.first(where: { $0.id == layerID })?[keyPath: keyPath] ?? 0
            },
            set: { newValue in
                guard let idx = track.sequencerLayers.firstIndex(where: { $0.id == layerID }) else { return }
                track.sequencerLayers[idx][keyPath: keyPath] = max(range.lowerBound, min(range.upperBound, newValue))
                if resetEngine { app.engine.resetStepSequencerState(for: track) }
            }
        )
    }

    private func safeLaneFloatBinding(track: Track, layerID: UUID, keyPath: WritableKeyPath<SequencerLayer, Float>, range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: {
                Double(track.sequencerLayers.first(where: { $0.id == layerID })?[keyPath: keyPath] ?? 0)
            },
            set: { newValue in
                guard let idx = track.sequencerLayers.firstIndex(where: { $0.id == layerID }) else { return }
                let clamped = max(range.lowerBound, min(range.upperBound, newValue))
                track.sequencerLayers[idx][keyPath: keyPath] = Float(clamped)
            }
        )
    }

    private func liveStep(_ pattern: StepPattern) -> Int {
        let beat = app.engine.currentBeat
        return Int(beat * Double(pattern.stepsPerBeat)) % pattern.stepCount
    }

    private func handleSequencerDrop(_ providers: [NSItemProvider], track: Track, step: Int?, note: Int) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String else { return }
                DispatchQueue.main.async {
                    if !app.handlePluginDropTextOnStepSequencer(text, on: track, step: step, laneNote: note) {
                        _ = app.handleSampleDropText(text, on: track, step: step, note: note)
                    }
                }
            }
            return true
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data,
                      let raw = String(data: data, encoding: .utf8) else { return }
                let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    if !app.handlePluginDropTextOnStepSequencer(cleaned, on: track, step: step, laneNote: note) {
                        _ = app.handleSampleDropText(cleaned, on: track, step: step, note: note)
                    }
                }
            }
            return true
        }
        return false
    }

    private func toggle(_ pattern: StepPattern, step: Int, note: Int) {
        guard let track = track else { return }
        let currentlyOn = pattern.isOn(step: step, note: note)
        app.setStepHit(on: track, step: step, note: note, enabled: !currentlyOn)
        // audition only the lane's hit; this should not mute/unmute the whole row.
        if !currentlyOn {
            app.engine.audition(track: track, note: note, on: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                app.engine.audition(track: track, note: note, on: false)
            }
        }
    }

    private func clearLane(_ track: Track, note: Int) {
        for step in 0..<track.stepPattern.stepCount {
            app.setStepHit(on: track, step: step, note: note, enabled: false)
        }
    }
}
