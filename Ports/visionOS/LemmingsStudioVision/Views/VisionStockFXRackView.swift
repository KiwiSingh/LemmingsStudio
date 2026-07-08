import SwiftUI

struct VisionStockFXRackView: View {
    @Environment(VisionStudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTrackID: UUID?

    init() { _selectedTrackID = State(initialValue: nil) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stock FX Rack").font(.largeTitle.bold())
                        Text("Native, automatable effects designed for breakpoint editing and spatial performance gestures.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Expose Selected Track", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                        model.exposeStockFXAutomation(trackID: activeTrackID)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Spatial Stage", systemImage: "move.3d") {
                        openWindow(id: "spatial-automation-stage")
                    }
                }

                HStack {
                    Label("Insert FX on", systemImage: "music.note.list")
                        .font(.headline)
                    Picker("Track", selection: Binding(
                        get: { activeTrackID },
                        set: { selectedTrackID = $0 }
                    )) {
                        ForEach(model.project.tracks) { track in
                            Text(track.name).tag(track.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Text("FX and gesture automation affect only this track.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .lemmingsGlass(cornerRadius: 20)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 18)], spacing: 18) {
                    ForEach(VisionStockFXKind.allCases) { effect in
                        VisionStockFXCard(effect: effect, trackID: activeTrackID)
                            .environment(model)
                    }
                }

                GroupBox("Gesture workflow") {
                    Text("Expose the rack, open Automation, map any FX parameter to Sway, Pulse, Glide, Strike, Press, or Sculpt, arm the lane, and perform it in Spatial Automation Stage. The result remains ordinary editable breakpoint automation.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(28)
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
        .onAppear {
            model.ensureTrackStockFXDefaults()
            if selectedTrackID == nil { selectedTrackID = model.project.tracks.first?.id }
            model.syncTrackStockFXRacksToAudioEngine()
        }
    }

    private var activeTrackID: UUID {
        selectedTrackID ?? model.project.tracks.first?.id ?? UUID()
    }
}

private struct VisionStockFXCard: View {
    @Environment(VisionStudioModel.self) private var model
    let effect: VisionStockFXKind
    let trackID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(effect.rawValue, systemImage: effect.symbol)
                .font(.title2.bold())
            ForEach(VisionStockFXParameterRegistry.parameters(for: effect)) { parameter in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(parameter.name).font(.headline)
                        Spacer()
                        Text(displayValue(parameter))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.trackStockFXValue(trackID: trackID, effect: effect, parameterID: parameter.parameterID)) },
                            set: { model.setTrackStockFXParameter(trackID: trackID, effect: effect, parameterID: parameter.parameterID, normalizedValue: Float($0)) }
                        ),
                        in: 0...1
                    )
                }
            }
        }
        .padding(20)
        .lemmingsGlass(cornerRadius: 26)
    }

    private func displayValue(_ parameter: VisionStockFXParameterDefinition) -> String {
        let value = model.trackStockFXValue(trackID: trackID, effect: effect, parameterID: parameter.parameterID)
        switch (effect, parameter.parameterID) {
        case (.lemmingsFilter, "cutoff"):
            let hz = 30 * pow(18_000.0 / 30.0, Double(value))
            return hz >= 1000 ? String(format: "%.1f kHz", hz / 1000) : String(format: "%.0f Hz", hz)
        case (.burrowDelay, "time"):
            return String(format: "%.2f s", 0.03 + Double(value) * 1.17)
        case (.lemmingDrive, "drive"):
            return String(format: "%.1f dB", Double(value) * 24)
        default:
            return String(format: "%.0f%%", Double(value) * 100)
        }
    }
}
