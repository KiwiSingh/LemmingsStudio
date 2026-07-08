import SwiftUI

struct VisionSpatialControlView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 22) {
            Text("Spatial Control Deck")
                .font(.title.bold())

            HStack(spacing: 18) {
                Button { model.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                Button { model.togglePlayback() } label: {
                    Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading) {
                Text("Timeline Zoom")
                Slider(value: $model.horizontalZoom, in: 35...320)
                Text("Track Height")
                Slider(value: $model.verticalZoom, in: 0.7...2.0)
            }

            Picker("Snap", selection: $model.snapDivision) {
                ForEach(VisionStudioModel.SnapDivision.allCases) { division in
                    Text(division.rawValue).tag(division)
                }
            }
            .pickerStyle(.segmented)

            Text(String(format: "Beat %.2f", model.playheadBeat))
                .font(.system(.title2, design: .monospaced))
        }
        .padding(32)
        .frame(minWidth: 520, minHeight: 360)
        .lemmingsGlass(cornerRadius: 32)
        .background(VisionThemeBackground(theme: model.visualTheme))
    }
}
