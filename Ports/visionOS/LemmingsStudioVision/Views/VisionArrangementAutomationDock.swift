import SwiftUI

struct VisionArrangementAutomationDock: View {
    @Environment(VisionStudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var automation = model.automationParity
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Label("Automation", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)

                Button("Tempo", systemImage: "metronome") {
                    model.exposeProjectTempoAutomation()
                }
                Button("Mixer", systemImage: "slider.horizontal.3") {
                    model.exposeVisionMixerAutomation()
                }
                Button("Spatial", systemImage: "move.3d") {
                    model.exposeSelectedSpatialAutomation()
                }

                Picker("Lane", selection: $automation.selectedLaneID) {
                    Text("Choose Lane").tag(UUID?.none)
                    ForEach(automation.lanes) { lane in
                        Text(lane.address.displayName).tag(UUID?.some(lane.id))
                    }
                }
                .frame(maxWidth: 320)

                if let laneIndex = selectedLaneIndex {
                    Toggle("Arm", isOn: $automation.lanes[laneIndex].armed)
                        .toggleStyle(.button)
                    Picker("Mode", selection: $automation.lanes[laneIndex].writeMode) {
                        ForEach(VisionAutomationWriteMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .frame(width: 130)
                }

                Spacer()

                Button("Spatial Stage", systemImage: "move.3d") {
                    openWindow(id: "spatial-automation-stage")
                }
                Button("Full Editor", systemImage: "arrow.up.left.and.arrow.down.right") {
                    openWindow(id: "automation")
                }
            }

            if let lane = selectedLane {
                automationGraph(lane)
            } else {
                ContentUnavailableView(
                    "No Automation Lane Selected",
                    systemImage: "waveform.path.ecg.rectangle",
                    description: Text("Expose Tempo, Mixer, plug-in, or spatial parameters, then choose a lane. Spatial performances and precise breakpoint editing share the same data.")
                )
                .frame(height: 115)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var selectedLaneIndex: Int? {
        guard let id = model.automationParity.selectedLaneID else { return nil }
        return model.automationParity.lanes.firstIndex(where: { $0.id == id })
    }

    private var selectedLane: VisionAutomationLane? {
        guard let index = selectedLaneIndex else { return nil }
        return model.automationParity.lanes[index]
    }

    private func automationGraph(_ lane: VisionAutomationLane) -> some View {
        GeometryReader { proxy in
            let totalBeats = max(1, model.project.totalBeats)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    for bar in 0...max(1, model.project.lengthBars) {
                        let beat = Double(bar * max(1, model.project.beatsPerBar))
                        let x = CGFloat(beat / totalBeats) * size.width
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(.secondary.opacity(0.16)), lineWidth: 1)
                    }

                    let points = lane.points.sorted { $0.beat < $1.beat }
                    if let first = points.first {
                        var path = Path()
                        path.move(to: pointPosition(first, size: size, totalBeats: totalBeats))
                        for point in points.dropFirst() {
                            path.addLine(to: pointPosition(point, size: size, totalBeats: totalBeats))
                        }
                        context.stroke(path, with: .color(.accentColor), lineWidth: 2.5)
                    }
                }

                ForEach(lane.points) { point in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 14, height: 14)
                        .position(pointPosition(point, size: proxy.size, totalBeats: totalBeats))
                }

                Rectangle()
                    .fill(.red.opacity(0.85))
                    .frame(width: 2)
                    .offset(x: CGFloat(model.playheadBeat / totalBeats) * proxy.size.width)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let beat = max(0, min(totalBeats, Double(value.location.x / max(1, proxy.size.width)) * totalBeats))
                        let normalized = Float(max(0, min(1, 1 - value.location.y / max(1, proxy.size.height))))
                        model.automationParity.addPoint(laneID: lane.id, beat: beat, value: normalized)
                        model.persistAutomationIntoProject()
                    }
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Text(lane.address.displayName).font(.caption.bold())
                    Text("• \(lane.points.count) points").font(.caption).foregroundStyle(.secondary)
                    if let gesture = lane.spatialGesture {
                        Text("• \(gesture.rawValue)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }
        }
        .frame(height: 135)
        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func pointPosition(_ point: VisionAutomationPoint, size: CGSize, totalBeats: Double) -> CGPoint {
        CGPoint(
            x: CGFloat(max(0, min(totalBeats, point.beat)) / totalBeats) * size.width,
            y: CGFloat(1 - max(0, min(1, point.value))) * size.height
        )
    }
}
