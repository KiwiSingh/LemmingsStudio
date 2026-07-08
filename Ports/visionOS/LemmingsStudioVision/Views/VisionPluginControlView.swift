import SwiftUI

struct VisionPluginControlView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var showCustomUI = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(model.audioUnitHost.activeDescriptor?.name ?? "No Audio Unit Loaded").font(.title2.bold())
                    if let descriptor = model.audioUnitHost.activeDescriptor {
                        Text("\(descriptor.manufacturer) • \(descriptor.type.rawValue)").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.audioUnitHost.customViewController != nil {
                    Toggle("Plug-in UI", isOn: $showCustomUI).toggleStyle(.button)
                }
                Button("Save State", systemImage: "square.and.arrow.down") { model.captureAudioUnitState() }
                Button("Unload", role: .destructive) { model.unloadAudioUnit() }
            }
            .padding().lemmingsGlass()

            if showCustomUI, let controller = model.audioUnitHost.customViewController {
                VisionAudioUnitCustomView(controller: controller)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .lemmingsGlass(cornerRadius: 24)
            } else if model.audioUnitHost.parameters.isEmpty {
                ContentUnavailableView("No Generic Parameters", systemImage: "slider.horizontal.3", description: Text("This Audio Unit exposes no parameter tree. Try its custom plug-in UI if available."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.audioUnitHost.parameters) { parameter in
                            VisionAudioUnitParameterRow(parameter: parameter)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(VisionThemeBackground(theme: model.visualTheme))
    }
}

private struct VisionAudioUnitParameterRow: View {
    @Environment(VisionStudioModel.self) private var model
    let parameter: VisionAudioUnitParameter
    @State private var value: Double

    init(parameter: VisionAudioUnitParameter) {
        self.parameter = parameter
        _value = State(initialValue: Double(parameter.value))
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(parameter.name).font(.headline)
                Text(parameter.identifier).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(width: 220, alignment: .leading)
            Slider(value: $value, in: Double(parameter.minValue)...Double(parameter.maxValue))
                .onChange(of: value) { _, newValue in model.setAudioUnitParameter(id: parameter.id, value: Float(newValue)) }
            Text(String(format: "%.3f %@", value, parameter.unitName))
                .monospacedDigit().frame(width: 130, alignment: .trailing)
        }
        .padding().lemmingsGlass(cornerRadius: 18)
    }
}
