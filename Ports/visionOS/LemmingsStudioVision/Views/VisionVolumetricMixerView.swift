import SwiftUI

struct VisionVolumetricMixerView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        let palette = VisionThemeCatalog.palette(for: model.visualTheme)
        VStack(spacing: 18) {
            Text("LemmingsStudio Spatial Mixer").font(.title2.bold())
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(model.project.tracks.prefix(8).enumerated()), id: \.offset) { index, track in
                    VStack(spacing: 8) {
                        VisionLevelMeter(key: "track-\(index)", accent: palette.accent).environment(model)
                            .frame(height: 100)
                        Text(track.name).font(.caption).lineLimit(1)
                        HStack(spacing: 5) {
                            Button("M") { model.toggleTrackMute(index: index) }
                            Button("S") { model.toggleTrackSolo(index: index) }
                        }.font(.caption2)
                    }
                    .frame(width: 90, height: 180)
                    .padding(8)
                    .lemmingsGlass(cornerRadius: 18)
                }
            }
            HStack(spacing: 18) {
                ForEach(model.project.returnBuses ?? VisionReturnBus.defaults) { bus in
                    VStack {
                        Text(bus.name).bold()
                        VisionLevelMeter(key: bus.id, accent: palette.secondaryAccent).environment(model)
                            .frame(height: 80)
                    }
                    .frame(width: 160, height: 120)
                    .padding(10)
                    .lemmingsGlass(cornerRadius: 20)
                }
                VStack {
                    Text("MASTER").bold()
                    VisionLevelMeter(key: "master", accent: palette.accent).environment(model)
                        .frame(height: 90)
                }
                .frame(width: 170, height: 130)
                .padding(10)
                .lemmingsGlass(cornerRadius: 22)
            }
        }
        .padding(24)
    }
}
