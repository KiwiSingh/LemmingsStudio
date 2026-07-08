import SwiftUI

/// visionOS-only expressive automation surface.
/// Gestures are mapped into ordinary VisionAutomationLane breakpoint data so every
/// performance can be edited later in the traditional lane editor and rendered by
/// the same deterministic automation evaluator used by export.
struct VisionSpatialAutomationStageView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var sway: Double = 0.5
    @State private var pulse: Double = 0.5
    @State private var glide: Double = 0.5
    @State private var press: Double = 0.5
    @State private var sculpt: Double = 0.5
    @State private var fieldGestureActive = false

    var body: some View {
        @Bindable var automation = model.automationParity
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(automation: automation)
                HStack(alignment: .top, spacing: 20) {
                    performanceField
                    VStack(spacing: 16) {
                        continuousControl(.glide, value: $glide, icon: "arrow.up.and.down.and.arrow.left.and.right")
                        continuousControl(.press, value: $press, icon: "hand.point.down.fill")
                        continuousControl(.sculpt, value: $sculpt, icon: "hands.and.sparkles.fill")
                        strikeControl
                    }
                    .frame(width: 380)
                }
                mappingMonitor(automation: automation)
            }
            .padding(28)
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
    }

    private func header(automation: VisionAutomationParityState) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Spatial Automation Stage").font(.largeTitle.bold())
                Text("Perform motion-driven automation, then refine the exact beat, value, interpolation, and curve handle in the lane editor.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(String(format: "Beat %.2f", model.playheadBeat)).monospacedDigit()
                Text(automation.status).font(.caption).foregroundStyle(.secondary)
                Button("Release Latches", systemImage: "lock.open") { automation.releaseAllLatches() }
            }
        }
    }

    private var performanceField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Sway × Pulse Field", systemImage: "move.3d")
                    .font(.title2.bold())
                Spacer()
                Text("Drag freely")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.thinMaterial)
                    grid
                    Circle()
                        .fill(.primary)
                        .frame(width: 34, height: 34)
                        .shadow(radius: 8)
                        .position(x: sway * proxy.size.width, y: (1 - pulse) * proxy.size.height)
                    VStack {
                        Text("PULSE +").font(.caption.bold())
                        Spacer()
                        HStack {
                            Text("SWAY −").font(.caption.bold())
                            Spacer()
                            Text("SWAY +").font(.caption.bold())
                        }
                        Spacer()
                        Text("PULSE −").font(.caption.bold())
                    }
                    .padding(18)
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !fieldGestureActive {
                                fieldGestureActive = true
                                model.beginSpatialPerformanceGesture(.sway)
                                model.beginSpatialPerformanceGesture(.pulse)
                            }
                            sway = max(0, min(1, value.location.x / max(1, proxy.size.width)))
                            pulse = max(0, min(1, 1 - value.location.y / max(1, proxy.size.height)))
                            model.performSpatialAutomationGesture(.sway, normalizedValue: Float(sway))
                            model.performSpatialAutomationGesture(.pulse, normalizedValue: Float(pulse))
                        }
                        .onEnded { _ in
                            fieldGestureActive = false
                            model.endSpatialPerformanceGesture(.sway)
                            model.endSpatialPerformanceGesture(.pulse)
                        }
                )
            }
            .frame(minHeight: 520)
        }
        .padding(20)
        .lemmingsGlass(cornerRadius: 30)
    }

    private var grid: some View {
        Canvas { context, size in
            var path = Path()
            for i in 1..<4 {
                let x = size.width * CGFloat(i) / 4
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let y = size.height * CGFloat(i) / 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.secondary.opacity(0.24)), lineWidth: 1)
        }
    }

    private func continuousControl(_ gesture: VisionSpatialAutomationGesture, value: Binding<Double>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(gesture.rawValue, systemImage: icon).font(.headline)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(3))))
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1, onEditingChanged: { editing in
                if editing { model.beginSpatialPerformanceGesture(gesture) }
                else { model.endSpatialPerformanceGesture(gesture) }
            })
            .onChange(of: value.wrappedValue) { _, newValue in
                model.performSpatialAutomationGesture(gesture, normalizedValue: Float(newValue))
            }
            Text(gesture.help).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .lemmingsGlass(cornerRadius: 20)
    }

    private var strikeControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Strike", systemImage: "bolt.fill").font(.headline)
            HStack {
                Button("Soft") { strike(0.25) }
                Button("Medium") { strike(0.55) }
                Button("Hard") { strike(1.0) }
            }
            .buttonStyle(.borderedProminent)
            Text(VisionSpatialAutomationGesture.strike.help).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .lemmingsGlass(cornerRadius: 20)
    }

    private func strike(_ amount: Float) {
        model.beginSpatialPerformanceGesture(.strike)
        model.performSpatialAutomationGesture(.strike, normalizedValue: amount)
        model.endSpatialPerformanceGesture(.strike)
    }

    private func mappingMonitor(automation: VisionAutomationParityState) -> some View {
        GroupBox("Gesture Mappings") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(VisionSpatialAutomationGesture.allCases) { gesture in
                    let mapped = automation.lanes(mappedTo: gesture)
                    HStack(alignment: .firstTextBaseline) {
                        Text(gesture.rawValue).font(.headline).frame(width: 90, alignment: .leading)
                        if mapped.isEmpty {
                            Text("Unmapped").foregroundStyle(.secondary)
                        } else {
                            Text(mapped.map(\.address.displayName).joined(separator: " • "))
                        }
                    }
                }
                Text("Mapping and precision editing live in Automation → Lane Editor. Gesture input changes the target live; recording obeys each lane's Arm and Read/Write/Touch/Latch state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
