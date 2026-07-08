import SwiftUI

@MainActor
extension VisionStudioModel {
    static let visionKeyNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    static let visionScaleNames = ["Major", "Natural Minor", "Harmonic Minor", "Melodic Minor", "Dorian", "Phrygian", "Lydian", "Mixolydian", "Major Pentatonic", "Minor Pentatonic", "Blues"]

    func setProjectTempo(_ bpm: Double) {
        let safe = max(20, min(400, bpm))
        project.bpm = safe
        project.tempo = safe
        statusMessage = String(format: "Tempo set to %.1f BPM", safe)
        persistAutomationIntoProject()
    }

    func setProjectKey(root: Int, scale: String? = nil) {
        let safeRoot = ((root % 12) + 12) % 12
        project.keyRoot = safeRoot
        project.keyName = Self.visionKeyNames[safeRoot]
        if let scale { project.scaleName = scale }
        statusMessage = "Key set to \(project.keyName ?? "C") \(project.scaleName ?? "Major")"
    }
}

struct VisionTempoKeyControlStrip: View {
    @Environment(VisionStudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "metronome")
                TextField("BPM", value: Binding(
                    get: { model.project.effectiveTempo },
                    set: { model.setProjectTempo($0) }
                ), format: .number.precision(.fractionLength(1)))
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
                Text("BPM").font(.caption).foregroundStyle(.secondary)
                Stepper("", value: Binding(
                    get: { model.project.effectiveTempo },
                    set: { model.setProjectTempo($0) }
                ), in: 20...400, step: 1)
                .labelsHidden()
            }

            Menu {
                Picker("Root", selection: Binding(
                    get: { model.project.keyRoot ?? 0 },
                    set: { model.setProjectKey(root: $0) }
                )) {
                    ForEach(Array(VisionStudioModel.visionKeyNames.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                Picker("Scale", selection: Binding(
                    get: { model.project.scaleName ?? "Major" },
                    set: { model.setProjectKey(root: model.project.keyRoot ?? 0, scale: $0) }
                )) {
                    ForEach(VisionStudioModel.visionScaleNames, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                Label("\(model.project.keyName ?? "C") \(model.project.scaleName ?? "Major")", systemImage: "music.quarternote.3")
            }

            Button("Circle of Fifths", systemImage: "circle.hexagongrid.circle") {
                openWindow(id: "circle-of-fifths")
            }
            .labelStyle(.iconOnly)
            .help("Open Circle of Fifths")
        }
    }
}

struct VisionCircleOfFifthsView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var mode = "Major"

    private let order = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Circle of Fifths").font(.largeTitle.bold())
                    Text("Choose a tonal center spatially; transport, scale assist, and piano roll stay synchronized.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Mode", selection: $mode) {
                    Text("Major").tag("Major")
                    Text("Minor").tag("Natural Minor")
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                ZStack {
                    Circle().fill(.thinMaterial).frame(width: size * 0.92, height: size * 0.92)
                    Circle().stroke(.secondary.opacity(0.25), lineWidth: 1).frame(width: size * 0.68, height: size * 0.68)
                    Circle().stroke(.secondary.opacity(0.18), lineWidth: 1).frame(width: size * 0.40, height: size * 0.40)

                    ForEach(Array(order.enumerated()), id: \.offset) { index, root in
                        let angle = Angle.degrees(Double(index) * 30 - 90)
                        let radius = size * 0.36
                        let x = center.x + CGFloat(cos(angle.radians)) * radius
                        let y = center.y + CGFloat(sin(angle.radians)) * radius
                        Button {
                            let selectedRoot = mode == "Natural Minor" ? (root + 9) % 12 : root
                            model.setProjectKey(root: selectedRoot, scale: mode)
                        } label: {
                            VStack(spacing: 2) {
                                Text(VisionStudioModel.visionKeyNames[root]).font(.headline.bold())
                                Text(VisionStudioModel.visionKeyNames[(root + 9) % 12] + "m").font(.caption)
                            }
                            .frame(width: 72, height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isSelected(root: root) ? .accentColor : .secondary.opacity(0.35))
                        .position(x: x, y: y)
                    }

                    VStack(spacing: 6) {
                        Text(model.project.keyName ?? "C").font(.system(size: 42, weight: .bold, design: .rounded))
                        Text(model.project.scaleName ?? "Major").font(.headline).foregroundStyle(.secondary)
                        Text(String(format: "%.1f BPM", model.project.effectiveTempo)).font(.title3.monospacedDigit())
                    }
                    .position(center)
                }
            }

            HStack {
                Picker("Scale", selection: Binding(
                    get: { model.project.scaleName ?? "Major" },
                    set: { model.setProjectKey(root: model.project.keyRoot ?? 0, scale: $0) }
                )) {
                    ForEach(VisionStudioModel.visionScaleNames, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 320)
                Spacer()
                VisionTempoKeyControlStrip()
            }
        }
        .padding(28)
        .background(VisionThemeBackground(theme: model.visualTheme))
    }

    private func isSelected(root: Int) -> Bool {
        let current = model.project.keyRoot ?? 0
        return mode == "Natural Minor" ? current == (root + 9) % 12 : current == root
    }
}
