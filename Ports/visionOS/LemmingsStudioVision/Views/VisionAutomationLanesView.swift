import SwiftUI

struct VisionAutomationLanesView: View {
    @Environment(VisionStudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var beat: Double = 0
    @State private var value: Double = 0.5

    var body: some View {
        @Bindable var automation = model.automationParity
        NavigationSplitView {
            List(selection: $automation.selectedLaneID) {
                Section("Expose") {
                    Button("Project Tempo", systemImage: "metronome") { model.exposeProjectTempoAutomation() }
                    Button("Mixer Volume + Pan", systemImage: "slider.horizontal.3") { model.exposeVisionMixerAutomation() }
                    Button("Stock FX Parameters", systemImage: "waveform.path.ecg.rectangle") { model.exposeStockFXAutomation() }
                    Button("Mac Host Parameters", systemImage: "macwindow") { model.exposeSelectedCompanionParametersForAutomation() }
                    Button("Selected Spatial Surface", systemImage: "move.3d") { model.exposeSelectedSpatialAutomation() }
                }
                Section("Automation Lanes") {
                    ForEach($automation.lanes) { $lane in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lane.address.displayName).font(.headline)
                            Text("\(lane.address.backendID) • \(lane.writeMode.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(Optional(lane.id))
                    }
                }
            }
            .navigationTitle("Automation")
        } detail: {
            if let laneID = automation.selectedLaneID,
               let index = automation.lanes.firstIndex(where: { $0.id == laneID }) {
                AutomationLaneDetail(lane: $automation.lanes[index], automation: automation, playheadBeat: model.playheadBeat)
            } else {
                ContentUnavailableView("Select an Automation Lane", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("Expose mixer, hosted plug-in, or spatial parameters, then select a lane to edit and record."))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Text(automation.status).foregroundStyle(.secondary)
                Button("Spatial Stage", systemImage: "move.3d") { openWindow(id: "spatial-automation-stage") }
                Button("Release Latches", systemImage: "lock.open") { automation.releaseAllLatches() }
                Button("Save Into Project", systemImage: "square.and.arrow.down") {
                    model.persistAutomationIntoProject()
                    automation.status = "Automation data staged in the project document."
                }
            }
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
    }
}

private struct AutomationLaneDetail: View {
    @Binding var lane: VisionAutomationLane
    let automation: VisionAutomationParityState
    let playheadBeat: Double
    @State private var newBeat: Double = 0
    @State private var newValue: Double = 0.5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(lane.address.displayName).font(.largeTitle.bold())
                        Text("\(lane.address.backendID) / \(lane.address.parameterID)").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Visible", isOn: $lane.visible)
                    Toggle("Armed", isOn: $lane.armed)
                }

                GroupBox("Write Mode") {
                    Picker("Mode", selection: $lane.writeMode) {
                        ForEach(VisionAutomationWriteMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    Text(modeHelp).font(.caption).foregroundStyle(.secondary)
                }

                GroupBox("Spatial Performance Mapping") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Gesture", selection: $lane.spatialGesture) {
                            Text("None").tag(Optional<VisionSpatialAutomationGesture>.none)
                            ForEach(VisionSpatialAutomationGesture.allCases) { gesture in
                                Text(gesture.rawValue).tag(Optional(gesture))
                            }
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text("Range")
                            Slider(value: Binding(get: { Double(lane.spatialMinimum) }, set: { lane.spatialMinimum = Float(min($0, Double(lane.spatialMaximum))) }), in: 0...1)
                            Text(lane.spatialMinimum.formatted(.number.precision(.fractionLength(2)))).monospacedDigit().frame(width: 44)
                            Text("to")
                            Slider(value: Binding(get: { Double(lane.spatialMaximum) }, set: { lane.spatialMaximum = Float(max($0, Double(lane.spatialMinimum))) }), in: 0...1)
                            Text(lane.spatialMaximum.formatted(.number.precision(.fractionLength(2)))).monospacedDigit().frame(width: 44)
                            Toggle("Invert", isOn: $lane.spatialInverted)
                        }
                        Text(lane.spatialGesture?.help ?? "Leave unmapped to use this lane only through conventional automation editing and playback.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                GroupBox("Add Automation Point") {
                    HStack {
                        Button("Use Playhead") { newBeat = playheadBeat }
                        TextField("Beat", value: $newBeat, format: .number).frame(width: 120)
                        Slider(value: $newValue, in: 0...1)
                        Text(newValue.formatted(.number.precision(.fractionLength(3)))).monospacedDigit().frame(width: 64)
                        Button("Add", systemImage: "plus") { automation.addPoint(laneID: lane.id, beat: newBeat, value: Float(newValue)) }
                    }
                }

                GroupBox("Curve Editor") {
                    VStack(spacing: 12) {
                        ForEach($lane.points) { $point in
                            AutomationPointRow(laneID: lane.id, point: $point, automation: automation)
                            Divider()
                        }
                        if lane.points.isEmpty { Text("No automation points yet.").foregroundStyle(.secondary) }
                    }
                }

                GroupBox("Spatial Gesture Recording") {
                    Text("For spatial X/Y/Z lanes, arm the lane and choose Write, Touch, or Latch. Moving the matching Spatial Editor slider records automation against the transport playhead. Touch records only while the slider is held; Latch continues until Release Latches is pressed.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .navigationTitle("Lane Editor")
    }

    private var modeHelp: String {
        switch lane.writeMode {
        case .read: return "Read plays existing automation without recording gestures."
        case .write: return "Write records every incoming gesture value while the lane is armed."
        case .touch: return "Touch records only while the control is actively manipulated, then returns to existing automation."
        case .latch: return "Latch starts recording when the control is touched and keeps writing the last value until latches are released."
        }
    }
}

private struct AutomationPointRow: View {
    let laneID: UUID
    @Binding var point: VisionAutomationPoint
    let automation: VisionAutomationParityState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Beat")
                TextField("Beat", value: $point.beat, format: .number).frame(width: 100)
                Text("Value")
                Slider(value: Binding(get: { Double(point.value) }, set: { point.value = Float(max(0, min(1, $0))) }), in: 0...1)
                Text(point.value.formatted(.number.precision(.fractionLength(3)))).monospacedDigit().frame(width: 60)
                Button(role: .destructive) { automation.removePoint(laneID: laneID, pointID: point.id) } label: { Image(systemName: "trash") }
            }
            HStack {
                Picker("Curve", selection: $point.curve) {
                    ForEach(VisionAutomationCurve.allCases) { curve in Text(curve.rawValue).tag(curve) }
                }
                .frame(width: 220)
                Text("Curve Handle")
                Slider(value: Binding(get: { Double(point.curveHandle) }, set: { point.curveHandle = Float(max(-1, min(1, $0))) }), in: -1...1)
                Text(point.curveHandle.formatted(.number.precision(.fractionLength(2)))).monospacedDigit().frame(width: 50)
            }
        }
    }
}
