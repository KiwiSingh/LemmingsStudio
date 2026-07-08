import SwiftUI

struct VisionPluginBrowserView: View {
    @Environment(VisionStudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var search = ""

    private var filtered: [VisionAudioUnitDescriptor] {
        guard !search.isEmpty else { return model.audioUnitHost.availableUnits }
        return model.audioUnitHost.availableUnits.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.manufacturer.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Audio Units", systemImage: "puzzlepiece.extension.fill").font(.title2.bold())
                Spacer()
                Button("Scan", systemImage: "arrow.clockwise") { model.scanAudioUnits() }
                    .disabled(model.audioUnitHost.isScanning)
            }
            .padding().lemmingsGlass()

            HStack {
                TextField("Search Audio Units", text: $search)
                    .textFieldStyle(.roundedBorder)
                Text("\(filtered.count) found").foregroundStyle(.secondary)
            }

            List(filtered) { descriptor in
                HStack(spacing: 14) {
                    Image(systemName: descriptor.type == .instrument ? "pianokeys" : "slider.horizontal.3")
                        .font(.title2)
                        .frame(width: 36)
                    VStack(alignment: .leading) {
                        Text(descriptor.name).font(.headline)
                        Text("\(descriptor.manufacturer) • \(descriptor.type.rawValue) • \(descriptor.versionString)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Load") {
                        Task {
                            await model.loadAudioUnit(descriptor)
                            openWindow(id: "plugin-control")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.audioUnitHost.isLoading)
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)

            HStack {
                Text(model.audioUnitHost.statusMessage).foregroundStyle(.secondary)
                Spacer()
                if model.audioUnitHost.activeDescriptor != nil {
                    Button("Open Controls", systemImage: "slider.horizontal.3") { openWindow(id: "plugin-control") }
                    Button("Unload", role: .destructive) { model.unloadAudioUnit() }
                }
            }
            .padding().lemmingsGlass()
        }
        .padding(24)
        .background(VisionThemeBackground(theme: model.visualTheme))
        .task { if model.audioUnitHost.availableUnits.isEmpty { model.scanAudioUnits() } }
    }
}
