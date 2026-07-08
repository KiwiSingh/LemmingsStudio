import SwiftUI

struct VisionClipInspectorView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 18) {
            Label("Clip Inspector", systemImage: "slider.horizontal.3")
                .font(.title2.bold())

            if let clip = model.selectedClipSummary {
                Group {
                    LabeledContent("Name", value: clip.name)
                    LabeledContent("Type", value: clip.kind)
                    LabeledContent("Track", value: clip.trackName)
                }

                Divider()

                VStack(alignment: .leading) {
                    Text("Start Beat")
                    Slider(
                        value: Binding(
                            get: { model.selectedClipSummary?.startBeat ?? 0 },
                            set: { model.setSelectedClipStart($0) }
                        ),
                        in: 0...max(1, model.project.totalBeats)
                    )
                }

                VStack(alignment: .leading) {
                    Text("Length")
                    Slider(
                        value: Binding(
                            get: { model.selectedClipSummary?.lengthBeats ?? 1 },
                            set: { model.setSelectedClipLength($0) }
                        ),
                        in: 0.125...max(1, model.project.totalBeats)
                    )
                }

                HStack {
                    Button("Split", systemImage: "scissors") { model.splitSelectedClip() }
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateSelectedClip() }
                    Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelectedClip() }
                }
            } else {
                ContentUnavailableView(
                    "No Clip Selected",
                    systemImage: "rectangle.dashed",
                    description: Text("Look at a clip and pinch to select it, then edit it here.")
                )
            }

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 420)
        .lemmingsGlass(cornerRadius: 30)
        .background(VisionThemeBackground(theme: model.visualTheme))
    }
}
