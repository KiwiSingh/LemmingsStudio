import SwiftUI

struct VisionParityRoadmapView: View {
    @Environment(VisionStudioModel.self) private var model

    private let completed = [
        "Startup branding: MagmaVance pre-splash + LemmingsStudio splash",
        "Spatial editor shell and saved scene graph",
        "Piano Roll, Step Sequencer, floating MIDI keyboard, and Bluetooth MIDI path",
        "Volumetric mixer/control surfaces and return-bus foundations",
        "Native AUv3 host path",
        "Integrated Mac Host Mode discovery, pairing, AU instantiation, MIDI, parameters, state, and live audio return",
        "Mac Host Mode streamed plug-in editor frames with visionOS pointer/drag input return",
        "Mac-side tempo-aware offline WAV render transport",
        "Semantic Project Graph + Living Project Memory",
        "Full automation parity: persistent lanes, Read/Write/Touch/Latch, curve handles, and spatial gesture recording",
        "Recording parity: punch in/out, count-in, pre-roll, take lanes, region comping, swipe take selection, and consolidation",
        "Wine ARM64 bring-up pipeline: runtime layout, architecture gates, prefix, loader/DLL/mmap diagnostics, executable smoke test, VST3 enumeration, DSP transport, editor bridge, captured logs, and timeout isolation",
        "Authenticated Splice MCP search, preview, download, project storage, drag/drop, auto-fit, and sequencer mapping"
    ]

    private let next = [
        "Hardware/Xcode validation of Host Mode editor input across JUCE, Cocoa, and generic AU editors",
        "Hardware validation of project-level Master, Selected Track/Clip, Stems, return bus, and hosted-plug-in bounce",
        "Enable the opt-in MLX Swift LM package profile and validate local VLM loading on Vision Pro hardware",
        "Final macOS-vs-visionOS feature audit and performance pass"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("visionOS → macOS Parity", systemImage: "checklist.checked")
                    .font(.largeTitle.bold())
                Text("Buildfix270 adds the staged Wine ARM64 bring-up pipeline on top of the real MLX runtime path: architecture validation, loader/DLL/memory diagnostics, VST3 probing, DSP transport and editor-surface experiments, captured logs, and crash/timeout isolation. The remaining roadmap is hardware/Xcode validation and final parity hardening.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Landed").font(.title3.bold())
                    ForEach(completed, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                    }
                }
                .padding()
                .lemmingsGlass()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Next steps for full parity").font(.title3.bold())
                    ForEach(next, id: \.self) { item in
                        Label(item, systemImage: "circle.dashed")
                    }
                }
                .padding()
                .lemmingsGlass()
            }
            .padding(28)
        }
        .background(VisionThemeBackground(theme: model.visualTheme))
    }
}
