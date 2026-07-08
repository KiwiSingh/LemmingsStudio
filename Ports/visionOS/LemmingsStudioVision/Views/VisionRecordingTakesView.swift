import SwiftUI

struct VisionRecordingTakesView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var regionStart: Double = 0
    @State private var regionEnd: Double = 4

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("Recording Setup") {
                    Stepper("Count-in: \(model.recordingSettings.countInBars) bars", value: Binding(
                        get: { model.recordingSettings.countInBars },
                        set: { value in model.updateRecordingSettings { $0.countInBars = value } }
                    ), in: 0...8)
                    Stepper("Pre-roll: \(model.recordingSettings.preRollBars) bars", value: Binding(
                        get: { model.recordingSettings.preRollBars },
                        set: { value in model.updateRecordingSettings { $0.preRollBars = value } }
                    ), in: 0...8)
                    Toggle("Punch In / Out", isOn: Binding(
                        get: { model.recordingSettings.punchEnabled },
                        set: { value in model.updateRecordingSettings { $0.punchEnabled = value } }
                    ))
                    if model.recordingSettings.punchEnabled {
                        HStack {
                            Text("Punch In")
                            TextField("Beat", value: Binding(
                                get: { model.recordingSettings.punchInBeat },
                                set: { value in model.updateRecordingSettings { $0.punchInBeat = value } }
                            ), format: .number).frame(width: 100)
                            Text("Punch Out")
                            TextField("Beat", value: Binding(
                                get: { model.recordingSettings.punchOutBeat },
                                set: { value in model.updateRecordingSettings { $0.punchOutBeat = value } }
                            ), format: .number).frame(width: 100)
                        }
                    }
                    if let countdown = model.recordingCountdownSeconds {
                        Label("Count-in: \(countdown)", systemImage: "metronome.fill").foregroundStyle(.orange)
                    }
                    if model.isArmedForPunch {
                        Label("Armed for punch", systemImage: "scope").foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Create Take Folder", systemImage: "folder.badge.plus") { model.createTakeFolder() }
                }

                ForEach(model.project.takeFolders ?? []) { folder in
                    Section(folder.name) {
                        if folder.takes.isEmpty {
                            Text("Record audio from the Audio window to add takes.").foregroundStyle(.secondary)
                        }
                        ForEach(folder.takes) { take in
                            Button {
                                model.selectCompTake(folderID: folder.id, takeID: take.id)
                            } label: {
                                HStack {
                                    Image(systemName: folder.selectedTakeID == take.id ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading) {
                                        Text(take.name)
                                        Text(URL(fileURLWithPath: take.sourcePath).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if folder.compRegions.contains(where: { $0.takeID == take.id }) {
                                        Label("Used", systemImage: "scissors").labelStyle(.iconOnly).foregroundStyle(.green)
                                    }
                                }
                            }
                        }

                        if let selectedTakeID = folder.selectedTakeID {
                            DisclosureGroup("Comp Regions") {
                                if folder.compRegions.isEmpty {
                                    Text("No comp regions yet.").foregroundStyle(.secondary)
                                }
                                ForEach(folder.compRegions.sorted(by: { $0.startBeat < $1.startBeat })) { region in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Button {
                                                model.selectedCompRegionID = region.id
                                            } label: {
                                                Image(systemName: model.selectedCompRegionID == region.id ? "checkmark.square.fill" : "square")
                                            }
                                            Text(String(format: "Beat %.2f → %.2f", region.startBeat, region.endBeat))
                                            Spacer()
                                            Menu("Take") {
                                                ForEach(folder.takes) { take in
                                                    Button(take.name) {
                                                        model.swipeCompRegion(folderID: folder.id, regionID: region.id, toTakeID: take.id)
                                                    }
                                                }
                                            }
                                            Button("Split @ Playhead", systemImage: "scissors") {
                                                model.splitCompRegion(folderID: folder.id, regionID: region.id, at: model.playheadBeat)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .gesture(DragGesture(minimumDistance: 28).onEnded { value in
                                            let direction = value.translation.width < 0 ? 1 : -1
                                            model.cycleCompTake(folderID: folder.id, regionID: region.id, direction: direction)
                                        })
                                        Text("Swipe-comp equivalent: choose a take for this time region; split at the playhead for finer edits.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }

                                HStack {
                                    TextField("Start", value: $regionStart, format: .number).frame(width: 90)
                                    TextField("End", value: $regionEnd, format: .number).frame(width: 90)
                                    Button("Add Region", systemImage: "plus.rectangle.on.rectangle") {
                                        model.addCompRegion(folderID: folder.id, takeID: selectedTakeID, startBeat: regionStart, endBeat: regionEnd)
                                    }
                                }
                            }
                        }

                        HStack {
                            Button("Consolidate Comp", systemImage: "waveform.badge.plus") {
                                model.consolidateComp(folderID: folder.id)
                            }
                            if let path = folder.consolidatedCompPath {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Takes & Comping")
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
    }
}
