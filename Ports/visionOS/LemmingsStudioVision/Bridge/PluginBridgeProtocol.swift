import Foundation

enum DesktopBridgeStatus: String, Codable, Sendable {
    case offline, discovering, pairing, connected, degraded
}

struct DesktopPluginDescriptor: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var vendor: String
    var format: String
    var platform: String
    var kind: String
    var provider: CompatibilityProviderKind
}

struct DesktopPluginParameter: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var name: String
    var normalizedValue: Double
    var displayValue: String?
}

struct DesktopBridgeAudioChunk: Codable, Sendable {
    var instanceID: UUID
    var sampleRate: Double
    var channels: Int
    var frames: Int
    var interleavedFloat32Base64: String
}

struct DesktopBridgeEditorFrame: Codable, Sendable {
    var instanceID: UUID
    var width: Int
    var height: Int
    var sequence: UInt64
    var jpegBase64: String
}

struct DesktopBridgeEditorInput: Codable, Sendable {
    var kind: String
    var x: Double
    var y: Double
    var deltaX: Double
    var deltaY: Double
    var button: Int
}


struct DesktopProjectBounceAsset: Codable, Sendable {
    var assetID: String
    var filename: String
    var base64: String
}

struct DesktopProjectBounceClip: Codable, Sendable {
    var assetID: String
    var startBeat: Double
    var lengthBeats: Double
    var sourceOffsetBeats: Double
    var sourceBPM: Double?
    var playbackRate: Double
}

struct DesktopProjectBounceTrack: Codable, Sendable {
    var id: UUID
    var name: String
    var volume: Double
    var pan: Double
    var muted: Bool
    var solo: Bool
    var sends: [String: Double]
    var clips: [DesktopProjectBounceClip]
}

struct DesktopProjectBounceReturnBus: Codable, Sendable {
    var id: String
    var name: String
    var volume: Double
    var pan: Double
    var muted: Bool
    var effectKind: String?
    var effectMix: Double
}

struct DesktopProjectBounceRequest: Codable, Sendable {
    var requestID: UUID
    var projectName: String
    var scope: String
    var bpm: Double
    var startBeat: Double
    var endBeat: Double
    var sampleRate: Double
    var selectedTrackIDs: [UUID]
    var includeReturnBuses: Bool
    var includeCompanionReturn: Bool
    var normalize: Bool
    var activeHostedInstanceID: UUID?
    var assets: [DesktopProjectBounceAsset]
    var tracks: [DesktopProjectBounceTrack]
    var returnBuses: [DesktopProjectBounceReturnBus]
}

struct DesktopRenderedArtifact: Codable, Sendable, Identifiable {
    var id: UUID
    var kind: String
    var name: String
    var wavBase64: String
}

enum DesktopBridgeMessage: Codable, Sendable {
    case hello(protocolVersion: Int, deviceName: String)
    case helloAccepted(protocolVersion: Int, hostName: String)
    case pairingRequired
    case pair(code: String)
    case pairResult(accepted: Bool, message: String)
    case listPlugins
    case plugins([DesktopPluginDescriptor])
    case instantiate(pluginID: UUID, instanceID: UUID)
    case instantiateResult(instanceID: UUID, accepted: Bool, message: String)
    case listParameters(instanceID: UUID)
    case parameters(instanceID: UUID, values: [DesktopPluginParameter])
    case midi(instanceID: UUID, status: UInt8, data1: UInt8, data2: UInt8, sampleOffset: Int)
    case setParameter(instanceID: UUID, parameterID: String, value: Double)
    case requestState(instanceID: UUID)
    case state(instanceID: UUID, base64: String?)
    case restoreState(instanceID: UUID, base64: String)
    case subscribeAudio(instanceID: UUID, enabled: Bool)
    case audioChunk(DesktopBridgeAudioChunk)
    case subscribeEditor(instanceID: UUID, enabled: Bool, width: Int, height: Int, fps: Int)
    case editorFrame(DesktopBridgeEditorFrame)
    case editorInput(instanceID: UUID, input: DesktopBridgeEditorInput)
    case requestOfflineRender(instanceID: UUID, startBeat: Double, lengthBeats: Double, bpm: Double)
    case offlineRenderResult(instanceID: UUID, wavBase64: String?, message: String)
    case requestProjectBounce(request: DesktopProjectBounceRequest)
    case projectBounceResult(requestID: UUID, artifacts: [DesktopRenderedArtifact], message: String)
    case error(String)
    case ping
    case pong
}

enum CompatibilityProviderKind: String, Codable, Sendable {
    case nativeAU
    case nativeVST3
    case experimentalWine
}
