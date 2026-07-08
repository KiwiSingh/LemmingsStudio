import SwiftUI
import UniformTypeIdentifiers

struct VisionStepSequencerView: View {
    @Environment(VisionStudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var sampleImportLayer: Int?
    @State private var showSampleImporter = false

    var body: some View {
        @Bindable var model = model
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let seq = model.project.stepSequencer {
                    ForEach(Array(seq.layers.enumerated()), id: \.element.id) { index, layer in
                        layerRow(index: index, layer: layer, seq: seq)
                    }
                }
            }.padding(18)
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
        .onAppear { model.ensureStepSequencerDefaults() }
        .fileImporter(isPresented: $showSampleImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            guard let layer = sampleImportLayer, case .success(let urls) = result, let url = urls.first else { return }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            guard model.project.stepSequencer?.layers.indices.contains(layer) == true else { return }
            model.project.stepSequencer!.layers[layer].sourcePath = url.path
            model.project.stepSequencer!.layers[layer].name = url.deletingPathExtension().lastPathComponent
            model.statusMessage = "Assigned \(url.lastPathComponent) to sequencer lane"
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Step Sequencer").font(.title2.bold())
                Text("Live pattern editor").font(.caption).foregroundStyle(.secondary)
            }

            Divider().frame(height: 34)

            Button("Stop", systemImage: "stop.fill") { model.stop() }
            Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.togglePlayback()
            }
            .buttonStyle(.borderedProminent)

            Button { model.setMetronomeEnabled(!model.metronomeEnabled) } label: {
                Label(model.metronomeEnabled ? "Metronome On" : "Metronome Off", systemImage: "metronome")
            }
                    .buttonStyle(.bordered)
            .tint(model.metronomeEnabled ? Color.accentColor : Color.secondary)

            Toggle("Live Pattern", isOn: Binding(
                get: { model.project.stepSequencer?.enabled ?? true },
                set: { model.project.stepSequencer?.enabled = $0 }
            ))
            .toggleStyle(.button)

            Menu("Steps: \(model.project.stepSequencer?.stepCount ?? 16)") {
                ForEach([8, 16, 24, 32, 48, 64], id: \.self) { count in
                    Button("\(count)") { model.setSequencerStepCount(count) }
                }
            }

            Button("Print to Arrangement", systemImage: "rectangle.stack.badge.plus") {
                model.printSequencerToArrangement()
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 8)

            if let step = model.activeSequencerStep {
                Text("Step \(step + 1)")
                    .monospacedDigit()
                    .foregroundStyle(VisionThemeCatalog.palette(for: model.visualTheme).accent)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func layerRow(index: Int, layer: VisionSequencerLayer, seq: VisionStepSequencerState) -> some View {
        HStack(spacing: 8) {
            layerControls(index: index, layer: layer)

            LazyHGrid(rows: [GridItem(.fixed(48))], spacing: 7) {
                ForEach(0..<seq.stepCount, id: \.self) { step in
                    stepButton(layerIndex: index, layer: layer, step: step, stepsPerBeat: seq.stepsPerBeat)
                }
            }
        }
        .padding(12)
        .dropDestination(for: String.self) { ids, _ in
            handleDrop(ids: ids, layerIndex: index)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func layerControls(index: Int, layer: VisionSequencerLayer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(layer.name)
                .font(.headline)
                .lineLimit(1)

            Text("MIDI \(layer.midiNote)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Sample", systemImage: "waveform") {
                    sampleImportLayer = index
                    showSampleImporter = true
                }
                Button("Clear", role: .destructive) {
                    model.clearSequencerLayer(index)
                }
            }
            .font(.caption)

            Slider(value: volumeBinding(for: index), in: 0...1.25)
                .frame(width: 165)
            Slider(value: panBinding(for: index), in: -1...1)
                .frame(width: 165)
        }
        .frame(width: 190, alignment: .leading)
    }

    private func stepButton(
        layerIndex: Int,
        layer: VisionSequencerLayer,
        step: Int,
        stepsPerBeat: Int
    ) -> some View {
        let active = step < layer.hits.count && layer.hits[step]
        let isBeatBoundary = step % max(1, stepsPerBeat) == 0
        let inactiveOpacity = isBeatBoundary ? 0.15 : 0.07
        let palette = VisionThemeCatalog.palette(for: model.visualTheme)
        let fillColor: Color = active ? palette.accent : Color.white.opacity(inactiveOpacity)
        let labelColor: Color = active ? .black : .secondary
        let isPlayhead = model.activeSequencerStep == step

        return Button {
            model.toggleSequencerHit(layer: layerIndex, step: step)
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .fill(fillColor)
                .overlay {
                    Text("\(step + 1)")
                        .font(.caption2)
                        .foregroundStyle(labelColor)
                }
                .frame(width: 44, height: 44)
                .overlay {
                    if isPlayhead {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.white, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func volumeBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: { Double(model.project.stepSequencer?.layers[index].volume ?? 1) },
            set: { newValue in
                guard model.project.stepSequencer?.layers.indices.contains(index) == true else { return }
                model.project.stepSequencer?.layers[index].volume = Float(newValue)
            }
        )
    }

    private func panBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: { Double(model.project.stepSequencer?.layers[index].pan ?? 0) },
            set: { newValue in
                guard model.project.stepSequencer?.layers.indices.contains(index) == true else { return }
                model.project.stepSequencer?.layers[index].pan = Float(newValue)
            }
        )
    }

    private func handleDrop(ids: [String], layerIndex: Int) -> Bool {
        guard
            let id = ids.first,
            let sample = model.spliceSearchResults.first(where: { $0.id == id })
        else {
            return false
        }

        model.selectedSpliceSampleID = id
        if model.spliceMCP.fetchOnDropEnabled {
            model.fetchSpliceSample(sample, sequencerLayerIndex: layerIndex)
        } else if sample.localFilePath != nil {
            model.importSampleCandidateToStepSequencer(sample, layerIndex: layerIndex)
        } else {
            model.statusMessage = "Fetch on Drop is off; download the Splice sample first"
        }
        return true
    }

}
