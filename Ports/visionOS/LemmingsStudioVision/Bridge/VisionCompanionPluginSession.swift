import Foundation

/// Buildfix258: Mac Companion desktop plug-in parity session model.
/// This is the visionOS-side contract for desktop AU/VST3/CLAP hosting.
struct VisionCompanionPluginDescriptor: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var vendor: String?
    var format: String
    var category: String?
    var architecture: String?
    var supportsEditor: Bool
    var supportsAudioReturn: Bool
    var supportsParameters: Bool
}

struct VisionCompanionParameter: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var address: String
    var value: Float
    var defaultValue: Float?
    var minValue: Float
    var maxValue: Float
    var unit: String?
    var isAutomatable: Bool
}

struct VisionCompanionEditorSurface: Codable, Identifiable, Hashable, Sendable {
    enum TransportKind: String, Codable, Sendable { case streamTexture, bitmapFrames, remoteWindow, unavailable }
    var id: String
    var title: String
    var transportKind: TransportKind
    var nominalWidth: Int
    var nominalHeight: Int
    var refreshRate: Int
    var inputMode: String
}

struct VisionCompanionPluginInstance: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var descriptor: VisionCompanionPluginDescriptor
    var parameters: [VisionCompanionParameter]
    var editorSurface: VisionCompanionEditorSurface?
    var latencySamples: Int
    var sampleRate: Double
    var blockSize: Int
    var status: String
}

@MainActor
@Observable
final class VisionCompanionPluginParityState {
    var discovered: [VisionCompanionPluginDescriptor] = []
    var activeInstances: [VisionCompanionPluginInstance] = []
    var selectedInstanceID: String?
    var lastCommandPreview = "lemmings-companion scan --formats au,vst3,clap --json"
    var status = "Mac Companion parity idle"

    var selectedInstance: VisionCompanionPluginInstance? {
        activeInstances.first { $0.id == selectedInstanceID }
    }

    func seedDemoInventory() {
        discovered = [
            .init(id: "au.serum2.demo", name: "Serum 2", vendor: "Xfer", format: "AU", category: "Instrument", architecture: "arm64/x86_64", supportsEditor: true, supportsAudioReturn: true, supportsParameters: true),
            .init(id: "vst3.splicesounds.demo", name: "Splice Sounds", vendor: "Splice", format: "VST3", category: "Instrument", architecture: "arm64", supportsEditor: true, supportsAudioReturn: true, supportsParameters: true),
            .init(id: "clap.generic.demo", name: "CLAP Desktop Candidate", vendor: "Unknown", format: "CLAP", category: "Effect", architecture: "arm64", supportsEditor: false, supportsAudioReturn: true, supportsParameters: true)
        ]
        status = "Loaded demo Companion inventory contract. Replace with /plugins scan response when the Mac daemon is live."
    }

    func instantiatePreview(_ descriptor: VisionCompanionPluginDescriptor) {
        let instance = VisionCompanionPluginInstance(
            id: "vision-companion-\(UUID().uuidString)",
            descriptor: descriptor,
            parameters: [
                .init(id: "gain", name: "Gain", address: "main.gain", value: 0.75, defaultValue: 0.75, minValue: 0, maxValue: 1, unit: nil, isAutomatable: true),
                .init(id: "mix", name: "Mix", address: "main.mix", value: 1, defaultValue: 1, minValue: 0, maxValue: 1, unit: "%", isAutomatable: true),
                .init(id: "cutoff", name: "Cutoff", address: "filter.cutoff", value: 0.6, defaultValue: 0.5, minValue: 0, maxValue: 1, unit: "norm", isAutomatable: true)
            ],
            editorSurface: descriptor.supportsEditor ? .init(id: "editor-\(descriptor.id)", title: descriptor.name, transportKind: .streamTexture, nominalWidth: 1280, nominalHeight: 800, refreshRate: 60, inputMode: "pointer+gesture") : nil,
            latencySamples: 256,
            sampleRate: 48_000,
            blockSize: 128,
            status: "Preview instance queued; Mac Companion daemon supplies the real process handle."
        )
        activeInstances.insert(instance, at: 0)
        selectedInstanceID = instance.id
        lastCommandPreview = "lemmings-companion instantiate --plugin-id \"\(descriptor.id)\" --stream editor,audio,parameters --json"
        status = "Prepared Companion instance preview for \(descriptor.name)."
    }
}
