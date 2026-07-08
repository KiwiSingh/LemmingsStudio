import SwiftUI

struct VisionExportView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Export").font(.largeTitle.bold())
                    Text("Offline rendering with live FX topology, AUv3 effect processing, sample-accurate mixer automation, stems, and return-bus routing.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.nativeExport.isExporting {
                    VStack(alignment: .trailing, spacing: 5) {
                        ProgressView(value: model.nativeExport.progress).frame(width: 220)
                        Text("\(Int(model.nativeExport.progress * 100))% · \(model.nativeExport.phase)").font(.caption.monospacedDigit())
                    }
                }
            }

            Form {
                Picker("Format", selection: $model.nativeExport.format) {
                    ForEach(VisionNativeExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Sample Rate", selection: $model.nativeExport.sampleRate) {
                    Text("44.1 kHz").tag(44_100.0); Text("48 kHz").tag(48_000.0); Text("96 kHz").tag(96_000.0)
                }
                Picker("Stem Mode", selection: $model.nativeExport.stemMode) {
                    ForEach(VisionStemMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Return Buses", selection: $model.nativeExport.returnMode) {
                    ForEach(VisionReturnExportMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Normalize", isOn: $model.nativeExport.normalize)
                LabeledContent("Start Beat") { TextField("0", value: $model.nativeExport.startBeat, format: .number).frame(width: 100) }
                LabeledContent("End Beat") { TextField("128", value: $model.nativeExport.endBeat, format: .number).frame(width: 100) }
                LabeledContent("Tail") { TextField("2", value: $model.nativeExport.tailSeconds, format: .number).frame(width: 100); Text("seconds") }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Button("Export Song", systemImage: "waveform.badge.plus") { model.exportMasterLocally() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.nativeExport.isExporting)
                Button("Export Stems", systemImage: "square.stack.3d.up") { model.exportStemsLocally() }
                    .disabled(model.nativeExport.isExporting)
                if model.nativeExport.isExporting {
                    Button("Cancel", systemImage: "xmark.circle.fill", role: .destructive) { model.cancelNativeExport() }
                }
                Spacer()
                if let url = model.nativeExport.latestMasterURL { ShareLink(item: url) { Label("Share Master", systemImage: "square.and.arrow.up") } }
                if let directory = model.nativeExport.latestStemsDirectory { ShareLink(item: directory) { Label("Share Stems Folder", systemImage: "square.and.arrow.up.on.square") } }
            }

            if model.nativeExport.isExporting {
                GroupBox("Render Progress") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow { Text("Phase").foregroundStyle(.secondary); Text(model.nativeExport.phase) }
                        GridRow { Text("Track").foregroundStyle(.secondary); Text(model.nativeExport.currentTrack.isEmpty ? "—" : model.nativeExport.currentTrack) }
                        GridRow { Text("Track Progress").foregroundStyle(.secondary); Text("\(model.nativeExport.trackIndex)/\(max(1, model.nativeExport.totalTracks))").monospacedDigit() }
                        GridRow { Text("Frames").foregroundStyle(.secondary); Text("\(model.nativeExport.completedFrames)/\(max(1, model.nativeExport.totalFrames))").monospacedDigit() }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text(model.nativeExport.status).font(.callout).foregroundStyle(.secondary)

            GroupBox("buildfix304 render behavior") {
                Text("Master export uses the live EQ → Delay → Reverb topology, project sends and Return A/B buses, saved AUv3 effect state through AVAudioEngine manual rendering, and per-sample mixer/send automation. Stem export supports pre-fader, post-fader, and post-FX modes plus baked or separate return buses. Cancellation is checked throughout track, automation, FX, and write phases.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
        .padding(28)
        .background(VisionThemeBackground(theme: model.visualTheme))
        .onAppear { model.nativeExport.endBeat = max(model.nativeExport.endBeat, model.project.totalBeats) }
    }
}
