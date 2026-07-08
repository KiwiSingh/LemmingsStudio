import SwiftUI

@main
struct LemmingsStudioVisionApp: App {
    @State private var model = VisionStudioModel()

    var body: some Scene {
        WindowGroup(id: "arrangement") {
            VisionRootView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1500, height: 900)

        WindowGroup(id: "clip-inspector") {
            VisionClipInspectorView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 500, height: 560)

        WindowGroup(id: "audio-control") {
            VisionAudioControlView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 760, height: 720)

        WindowGroup(id: "appearance") {
            NavigationStack { VisionAppearanceView().environment(model) }
        }
        .windowStyle(.plain)
        .defaultSize(width: 1050, height: 780)

        WindowGroup(id: "plugin-browser") {
            VisionPluginBrowserView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 980, height: 760)

        WindowGroup(id: "plugin-control") {
            VisionPluginControlView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1180, height: 820)


        WindowGroup(id: "desktop-bridge") {
            VisionDesktopBridgeView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1280, height: 820)



        WindowGroup(id: "piano-roll") {
            VisionPianoRollView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1500, height: 920)

        WindowGroup(id: "step-sequencer") {
            VisionStepSequencerView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1600, height: 860)

        WindowGroup(id: "mixer") {
            NavigationStack { VisionMixerView().environment(model) }
        }
        .windowStyle(.plain)
        .defaultSize(width: 1500, height: 820)

        WindowGroup(id: "spatial-mixer") {
            VisionVolumetricMixerView().environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.15, height: 0.60, depth: 0.32, in: .meters)

        WindowGroup(id: "spatial-control") {
            VisionSpatialControlView().environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.65, height: 0.42, depth: 0.18, in: .meters)

        WindowGroup(id: "spatial-editor") {
            VisionSpatialEditorView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1280, height: 820)

        WindowGroup(id: "agent-panel") {
            VisionAgentPanelView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1120, height: 780)

        WindowGroup(id: "local-export") {
            VisionExportView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 980, height: 760)


        WindowGroup(id: "splice-mcp") {
            VisionSpliceMCPView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1180, height: 780)


        WindowGroup(id: "compatibility-lab") {
            VisionCompatibilityLabView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1260, height: 840)

        WindowGroup(id: "plugin-parity") {
            VisionPluginParityView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 980, height: 760)

        WindowGroup(id: "parity-roadmap") {
            VisionParityRoadmapView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1040, height: 820)


        WindowGroup(id: "semantic-graph") {
            VisionSemanticGraphView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1280, height: 840)

        WindowGroup(id: "floating-midi-keyboard") {
            VisionFloatingMIDIKeyboardView().environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.38, height: 0.44, depth: 0.26, in: .meters)

        WindowGroup(id: "sample-browser") {
            VisionSampleBrowserView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1180, height: 820)

        WindowGroup(id: "stock-fx-rack") {
            VisionStockFXRackView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1280, height: 860)

        WindowGroup(id: "circle-of-fifths") {
            VisionCircleOfFifthsView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 900, height: 900)

        WindowGroup(id: "mlx-runtime") {
            VisionMLXRuntimeView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1180, height: 820)

        WindowGroup(id: "project-memory") {
            VisionProjectMemoryView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1180, height: 860)

        WindowGroup(id: "recording-takes") {
            VisionRecordingTakesView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 980, height: 760)

        WindowGroup(id: "automation") {
            VisionAutomationLanesView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1200, height: 820)

        WindowGroup(id: "spatial-automation-stage") {
            VisionSpatialAutomationStageView().environment(model)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1380, height: 900)

    }
}
