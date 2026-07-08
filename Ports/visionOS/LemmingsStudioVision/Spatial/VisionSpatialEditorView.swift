import SwiftUI

struct VisionSpatialEditorView: View {
    @Environment(VisionStudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 18) {
            List(selection: $model.spatialSelectedObjectID) {
                ForEach(model.spatialObjects) { object in
                    Label(object.name, systemImage: object.kind.systemImage)
                        .tag(Optional(object.id))
                }
            }
            .frame(minWidth: 280)
            .lemmingsGlass(cornerRadius: 24)

            VStack(alignment: .leading, spacing: 18) {
                header
                if let object = model.selectedSpatialObject {
                    SpatialTransformEditor(object: object)
                } else {
                    ContentUnavailableView("No Spatial Surface", systemImage: "cube", description: Text("Pick or create a surface to edit its 3D transform."))
                }
                Spacer()
            }
            .padding(24)
            .frame(minWidth: 720)
            .lemmingsGlass(cornerRadius: 28)
        }
        .padding(24)
        .background(VisionThemeBackground(theme: model.visualTheme))
        .onAppear { model.ensureSpatialScene() }
    }

    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Spatial Editor")
                        .font(.largeTitle.bold())
                    Text("Scene-graph transforms for Arrangement, Mixer, plug-ins, editors, bridge, and AI panels.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undoSpatialEdit() }
                Button("Redo", systemImage: "arrow.uturn.forward") { model.redoSpatialEdit() }
            }
            HStack {
                Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateSelectedSpatialObject() }
                Button("Snap", systemImage: "grid") { model.snapSelectedSpatialObject() }
                Button("Reset", systemImage: "arrow.counterclockwise") { model.resetSelectedSpatialObject() }
                Button("Delete", systemImage: "trash", role: .destructive) { model.deleteSelectedSpatialObject() }
            }
        }
    }
}

private struct SpatialTransformEditor: View {
    @Environment(VisionStudioModel.self) private var model
    var object: VisionSpatialObject

    var body: some View {
        @Bindable var model = model
        let transform = object.transform
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(object.kind.displayName, systemImage: object.kind.systemImage)
                    .font(.title2.bold())
                Spacer()
                Toggle("Visible", isOn: Binding(get: { object.isVisible }, set: { model.setSelectedSpatialVisibility($0) }))
            }

            group(title: "Position", suffix: "m") {
                slider("X", parameterID: "position.x", value: transform.position.x, range: -2...2) { value in mutate { $0.position.x = value } }
                slider("Y", parameterID: "position.y", value: transform.position.y, range: -1.2...1.2) { value in mutate { $0.position.y = value } }
                slider("Z", parameterID: "position.z", value: transform.position.z, range: -3...0.2) { value in mutate { $0.position.z = value } }
            }

            group(title: "Rotation", suffix: "°") {
                slider("Pitch", parameterID: nil, value: transform.rotationDegrees.x, range: -60...60) { value in mutate { $0.rotationDegrees.x = value } }
                slider("Yaw", parameterID: nil, value: transform.rotationDegrees.y, range: -90...90) { value in mutate { $0.rotationDegrees.y = value } }
                slider("Roll", parameterID: nil, value: transform.rotationDegrees.z, range: -45...45) { value in mutate { $0.rotationDegrees.z = value } }
            }

            group(title: "Scale", suffix: "×") {
                slider("X", parameterID: nil, value: transform.scale.x, range: 0.25...2.0) { value in mutate { $0.scale.x = value } }
                slider("Y", parameterID: nil, value: transform.scale.y, range: 0.25...2.0) { value in mutate { $0.scale.y = value } }
                slider("Z", parameterID: nil, value: transform.scale.z, range: 0.25...2.0) { value in mutate { $0.scale.z = value } }
            }

            HStack {
                Button("←") { model.nudgeSelectedSpatialObject(dx: -0.05) }
                Button("→") { model.nudgeSelectedSpatialObject(dx: 0.05) }
                Button("↑") { model.nudgeSelectedSpatialObject(dy: 0.05) }
                Button("↓") { model.nudgeSelectedSpatialObject(dy: -0.05) }
                Button("Near") { model.nudgeSelectedSpatialObject(dz: 0.05) }
                Button("Far") { model.nudgeSelectedSpatialObject(dz: -0.05) }
            }
        }
    }

    private func mutate(_ edit: (inout VisionSpatialTransform) -> Void) {
        var next = object.transform
        edit(&next)
        model.updateSelectedSpatialTransform(next)
    }

    private func group<Content: View>(title: String, suffix: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func slider(_ title: String, parameterID: String?, value: Double, range: ClosedRange<Double>, set: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        HStack {
            Text(title).frame(width: 56, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { newValue in
                MainActor.assumeIsolated { set(newValue) }
            }), in: range, onEditingChanged: { editing in
                guard let parameterID else { return }
                if editing { model.beginSpatialAutomationTouch(objectID: object.id, parameterID: parameterID) }
                else { model.endSpatialAutomationTouch(objectID: object.id, parameterID: parameterID) }
            })
            Text(value.formatted(.number.precision(.fractionLength(2))))
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
    }
}
