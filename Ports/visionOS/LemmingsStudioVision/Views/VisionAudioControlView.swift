import SwiftUI

struct VisionAudioControlView: View {
    @Environment(VisionStudioModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Native Audio", systemImage: "waveform.circle.fill").font(.title2.bold())
                if let folders = model.project.takeFolders, !folders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Take Folders").font(.headline)
                    ForEach(folders) { folder in
                        HStack {
                            Text(folder.name)
                            Spacer()
                            Text("\(folder.takes.count) takes").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding().lemmingsGlass()
            }
            Spacer()
                Text(model.audioEngineRunning ? "Engine Running" : "Engine Stopped")
                    .foregroundStyle(model.audioEngineRunning ? .green : .secondary)
            }
            .padding().lemmingsGlass()

            HStack(spacing: 16) {
                Picker("Instrument", selection: $model.selectedInstrument) {
                    ForEach(VisionAudioEngine.InstrumentKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: model.selectedInstrument) { _, newValue in model.selectInstrument(newValue) }
                Button("Test C4", systemImage: "pianokeys") { model.previewNote(60) }
                Button("Panic", systemImage: "exclamationmark.triangle") { model.panic() }
            }
            .padding().lemmingsGlass()

            VStack(alignment: .leading, spacing: 12) {
                Text("Stock Effects").font(.headline)
                effectSlider("Low EQ", value: $model.lowEQ, range: -24...24) { model.setLowEQ($0) }
                effectSlider("Mid EQ", value: $model.midEQ, range: -24...24) { model.setMidEQ($0) }
                effectSlider("High EQ", value: $model.highEQ, range: -24...24) { model.setHighEQ($0) }
                effectSlider("Delay", value: $model.delayMix, range: 0...100) { model.setDelayMix($0) }
                effectSlider("Reverb", value: $model.reverbMix, range: 0...100) { model.setReverbMix($0) }
            }
            .padding().lemmingsGlass()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Button(model.isRecordingAudio || model.isArmedForPunch ? "Stop Recording" : "Record Audio", systemImage: model.isRecordingAudio ? "stop.circle.fill" : "record.circle") {
                        model.toggleAudioRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    Text(model.recordingStatus).foregroundStyle(.secondary)
                    if let countdown = model.recordingCountdownSeconds {
                        Text("\(countdown)").font(.title.bold()).monospacedDigit().foregroundStyle(.orange)
                    }
                    Spacer()
                    Label("MIDI: \(model.midiSourceSummary)", systemImage: "cable.connector")
                }
                HStack(spacing: 14) {
                    Label("Count-in \(model.recordingSettings.countInBars)b", systemImage: "metronome")
                    Label("Pre-roll \(model.recordingSettings.preRollBars)b", systemImage: "backward.end.alt")
                    if model.recordingSettings.punchEnabled {
                        Label(String(format: "Punch %.1f–%.1f", model.recordingSettings.punchInBeat, model.recordingSettings.punchOutBeat), systemImage: "scope")
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            .padding().lemmingsGlass()
            Spacer()
        }
        .padding(24)
        .background(VisionThemeBackground(theme: model.visualTheme))
    }

    private func effectSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label).frame(width: 90, alignment: .leading)
            Slider(value: value, in: range).onChange(of: value.wrappedValue) { _, newValue in onChange(newValue) }
            Text(String(format: "%.1f", value.wrappedValue)).monospacedDigit().frame(width: 54, alignment: .trailing)
        }
    }
}
