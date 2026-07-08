import Foundation
import Network
import AVFoundation
import AppKit
import AudioToolbox

private enum ProviderKind: String, Codable, Sendable { case nativeAU, nativeVST3, experimentalWine }
private struct BridgePluginDescriptor: Codable, Identifiable, Sendable, Hashable {
    var id: UUID; var name: String; var vendor: String; var format: String; var platform: String; var kind: String; var provider: ProviderKind
}
private struct BridgePluginParameter: Codable, Identifiable, Sendable, Hashable {
    var id: String; var name: String; var normalizedValue: Double; var displayValue: String?
}
private struct BridgeAudioChunk: Codable, Sendable {
    var instanceID: UUID; var sampleRate: Double; var channels: Int; var frames: Int; var interleavedFloat32Base64: String
}
private struct BridgeEditorFrame: Codable, Sendable {
    var instanceID: UUID; var width: Int; var height: Int; var sequence: UInt64; var jpegBase64: String
}
private struct BridgeEditorInput: Codable, Sendable {
    var kind: String; var x: Double; var y: Double; var deltaX: Double; var deltaY: Double; var button: Int
}

private struct BridgeProjectBounceAsset: Codable, Sendable { var assetID: String; var filename: String; var base64: String }
private struct BridgeProjectBounceClip: Codable, Sendable { var assetID: String; var startBeat: Double; var lengthBeats: Double; var sourceOffsetBeats: Double; var sourceBPM: Double?; var playbackRate: Double }
private struct BridgeProjectBounceTrack: Codable, Sendable { var id: UUID; var name: String; var volume: Double; var pan: Double; var muted: Bool; var solo: Bool; var sends: [String: Double]; var clips: [BridgeProjectBounceClip] }
private struct BridgeProjectBounceReturnBus: Codable, Sendable { var id: String; var name: String; var volume: Double; var pan: Double; var muted: Bool; var effectKind: String?; var effectMix: Double }
private struct BridgeProjectBounceRequest: Codable, Sendable {
    var requestID: UUID; var projectName: String; var scope: String; var bpm: Double; var startBeat: Double; var endBeat: Double; var sampleRate: Double
    var selectedTrackIDs: [UUID]; var includeReturnBuses: Bool; var includeCompanionReturn: Bool; var normalize: Bool; var activeHostedInstanceID: UUID?
    var assets: [BridgeProjectBounceAsset]; var tracks: [BridgeProjectBounceTrack]; var returnBuses: [BridgeProjectBounceReturnBus]
}
private struct BridgeRenderedArtifact: Codable, Sendable { var id: UUID; var kind: String; var name: String; var wavBase64: String }

private enum BridgeMessage: Codable, Sendable {
    case hello(protocolVersion: Int, deviceName: String)
    case helloAccepted(protocolVersion: Int, hostName: String)
    case pairingRequired
    case pair(code: String)
    case pairResult(accepted: Bool, message: String)
    case listPlugins
    case plugins([BridgePluginDescriptor])
    case instantiate(pluginID: UUID, instanceID: UUID)
    case instantiateResult(instanceID: UUID, accepted: Bool, message: String)
    case listParameters(instanceID: UUID)
    case parameters(instanceID: UUID, values: [BridgePluginParameter])
    case midi(instanceID: UUID, status: UInt8, data1: UInt8, data2: UInt8, sampleOffset: Int)
    case setParameter(instanceID: UUID, parameterID: String, value: Double)
    case requestState(instanceID: UUID)
    case state(instanceID: UUID, base64: String?)
    case restoreState(instanceID: UUID, base64: String)
    case subscribeAudio(instanceID: UUID, enabled: Bool)
    case audioChunk(BridgeAudioChunk)
    case subscribeEditor(instanceID: UUID, enabled: Bool, width: Int, height: Int, fps: Int)
    case editorFrame(BridgeEditorFrame)
    case editorInput(instanceID: UUID, input: BridgeEditorInput)
    case requestOfflineRender(instanceID: UUID, startBeat: Double, lengthBeats: Double, bpm: Double)
    case offlineRenderResult(instanceID: UUID, wavBase64: String?, message: String)
    case requestProjectBounce(request: BridgeProjectBounceRequest)
    case projectBounceResult(requestID: UUID, artifacts: [BridgeRenderedArtifact], message: String)
    case error(String)
    case ping
    case pong
}

/// Integrated macOS Host Mode for LemmingsStudio visionOS.
/// Buildfix264 adds live editor surfaces/input and tempo-aware offline render transport.
final class DesktopPluginBridgeServer {
    static let shared = DesktopPluginBridgeServer()

    private let queue = DispatchQueue(label: "com.magmavance.LemmingsStudio.desktop-plugin-bridge")
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: ClientSession] = [:]
    private var pluginMap: [UUID: AVAudioUnitComponent] = [:]
    private var instances: [UUID: HostedInstance] = [:]
    private let pairingCode = String(format: "%06d", Int.random(in: 0...999_999))

    private init() {}

    var isRunning: Bool { listener != nil }
    var currentPairingCode: String { pairingCode }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "LemmingsStudio Mac", type: "_lemmings-plugin._tcp")
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready: print("[HostMode] Ready via Bonjour. Pairing code: \(self.pairingCode)")
                case .failed(let error): print("[HostMode] Listener failed: \(error)")
                default: break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            print("[HostMode] Unable to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        for session in sessions.values { session.connection.cancel() }
        sessions.removeAll()
        for instance in instances.values { instance.shutdown() }
        instances.removeAll()
    }

    func showHostModeStatus() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = self.isRunning ? "LemmingsStudio Host Mode is running" : "LemmingsStudio Host Mode is stopped"
            alert.informativeText = self.isRunning
                ? "Bonjour service: _lemmings-plugin._tcp\nPairing code: \(self.pairingCode)\n\nUse the Desktop Bridge window on Vision Pro to discover and pair with this Mac."
                : "Start Host Mode from the LemmingsStudio → Host Mode menu."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func accept(_ connection: NWConnection) {
        let session = ClientSession(connection: connection)
        sessions[ObjectIdentifier(session)] = session
        connection.stateUpdateHandler = { [weak self, weak session] state in
            guard let self, let session else { return }
            if case .ready = state { self.receive(session) }
            if case .failed = state { self.sessions.removeValue(forKey: ObjectIdentifier(session)) }
            if case .cancelled = state { self.sessions.removeValue(forKey: ObjectIdentifier(session)) }
        }
        connection.start(queue: queue)
    }

    private func receive(_ session: ClientSession) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024 * 1024) { [weak self, weak session] data, _, complete, error in
            guard let self, let session else { return }
            if let data { session.buffer.append(data); self.consume(session) }
            if complete || error != nil { session.connection.cancel(); return }
            self.receive(session)
        }
    }

    private func consume(_ session: ClientSession) {
        while let newline = session.buffer.firstIndex(of: 0x0A) {
            let line = session.buffer.prefix(upTo: newline)
            session.buffer.removeSubrange(...newline)
            guard !line.isEmpty, let message = try? JSONDecoder().decode(BridgeMessage.self, from: Data(line)) else { continue }
            handle(message, session: session)
        }
    }

    private func handle(_ message: BridgeMessage, session: ClientSession) {
        switch message {
        case .hello(let version, let deviceName):
            session.deviceName = deviceName
            send(.helloAccepted(protocolVersion: min(version, 2), hostName: Host.current().localizedName ?? "Mac"), to: session)
            send(.pairingRequired, to: session)
            showPairingCode(for: deviceName)

        case .pair(let code):
            let accepted = code == pairingCode
            session.paired = accepted
            send(.pairResult(accepted: accepted, message: accepted ? "Paired with this Mac" : "Pairing code rejected"), to: session)

        case .listPlugins:
            guard requirePairing(session) else { return }
            send(.plugins(scanPlugins()), to: session)

        case .instantiate(let pluginID, let instanceID):
            guard requirePairing(session), let component = pluginMap[pluginID] else { send(.error("Unknown Audio Unit"), to: session); return }
            AVAudioUnit.instantiate(with: component.audioComponentDescription, options: []) { [weak self, weak session] unit, error in
                guard let self, let session else { return }
                self.queue.async {
                    if let unit {
                        do {
                            let hosted = try HostedInstance(
                                id: instanceID,
                                unit: unit,
                                sendAudio: { [weak self, weak session] chunk in
                                    guard let self, let session else { return }
                                    self.send(.audioChunk(chunk), to: session)
                                },
                                sendEditorFrame: { [weak self, weak session] frame in
                                    guard let self, let session else { return }
                                    self.send(.editorFrame(frame), to: session)
                                }
                            )
                            self.instances[instanceID]?.shutdown()
                            self.instances[instanceID] = hosted
                            self.send(.instantiateResult(instanceID: instanceID, accepted: true, message: "Loaded \(component.name) on Mac"), to: session)
                        } catch {
                            self.send(.instantiateResult(instanceID: instanceID, accepted: false, message: error.localizedDescription), to: session)
                        }
                    } else {
                        self.send(.instantiateResult(instanceID: instanceID, accepted: false, message: error?.localizedDescription ?? "Instantiation failed"), to: session)
                    }
                }
            }

        case .listParameters(let instanceID):
            guard let instance = instances[instanceID] else { send(.error("Instance not loaded"), to: session); return }
            send(.parameters(instanceID: instanceID, values: instance.parameters()), to: session)

        case .setParameter(let instanceID, let parameterID, let value):
            instances[instanceID]?.setParameter(id: parameterID, normalized: value)

        case .midi(let instanceID, let status, let data1, let data2, let sampleOffset):
            instances[instanceID]?.sendMIDI(status: status, data1: data1, data2: data2, sampleOffset: sampleOffset)

        case .requestState(let instanceID):
            send(.state(instanceID: instanceID, base64: instances[instanceID]?.stateBase64()), to: session)

        case .restoreState(let instanceID, let base64):
            instances[instanceID]?.restoreState(base64)

        case .subscribeAudio(let instanceID, let enabled):
            instances[instanceID]?.setAudioStreaming(enabled)

        case .subscribeEditor(let instanceID, let enabled, let width, let height, let fps):
            guard let instance = instances[instanceID] else { send(.error("Instance not loaded"), to: session); return }
            instance.setEditorStreaming(enabled: enabled, width: width, height: height, fps: fps)

        case .editorInput(let instanceID, let input):
            instances[instanceID]?.sendEditorInput(input)

        case .requestOfflineRender(let instanceID, _, let lengthBeats, let bpm):
            guard let instance = instances[instanceID] else { send(.error("Instance not loaded"), to: session); return }
            do {
                let data = try instance.renderOffline(lengthBeats: lengthBeats, bpm: bpm)
                send(.offlineRenderResult(instanceID: instanceID, wavBase64: data.base64EncodedString(), message: "Rendered \(String(format: "%.2f", lengthBeats)) beats at \(String(format: "%.1f", bpm)) BPM on Mac"), to: session)
            } catch {
                send(.offlineRenderResult(instanceID: instanceID, wavBase64: nil, message: "Render failed: \(error.localizedDescription)"), to: session)
            }

        case .requestProjectBounce(let request):
            guard requirePairing(session) else { return }
            do {
                let artifacts = try DesktopProjectBounceRenderer.render(request: request, hostedInstances: instances)
                send(.projectBounceResult(requestID: request.requestID, artifacts: artifacts, message: "Rendered \(artifacts.count) project artifact(s) on Mac"), to: session)
            } catch {
                send(.projectBounceResult(requestID: request.requestID, artifacts: [], message: "Project bounce failed: \(error.localizedDescription)"), to: session)
            }

        case .ping: send(.pong, to: session)
        default: break
        }
    }

    private func requirePairing(_ session: ClientSession) -> Bool {
        if !session.paired { send(.error("Pair the Vision Pro with this Mac first"), to: session) }
        return session.paired
    }

    private func scanPlugins() -> [BridgePluginDescriptor] {
        pluginMap.removeAll(keepingCapacity: true)
        let types: [OSType] = [kAudioUnitType_MusicDevice, kAudioUnitType_MusicEffect, kAudioUnitType_Effect, kAudioUnitType_Generator]
        var output: [BridgePluginDescriptor] = []
        for type in types {
            let desc = AudioComponentDescription(componentType: type, componentSubType: 0, componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
            for component in AVAudioUnitComponentManager.shared().components(matching: desc) {
                let id = UUID(); pluginMap[id] = component
                output.append(.init(id: id, name: component.name, vendor: component.manufacturerName, format: "AU", platform: "macOS", kind: kindName(type), provider: .nativeAU))
            }
        }
        return output.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func kindName(_ type: OSType) -> String {
        switch type {
        case kAudioUnitType_MusicDevice: return "Instrument"
        case kAudioUnitType_Generator: return "Generator"
        case kAudioUnitType_MusicEffect: return "Music Effect"
        default: return "Effect"
        }
    }

    private func send(_ message: BridgeMessage, to session: ClientSession) {
        guard var data = try? JSONEncoder().encode(message) else { return }
        data.append(0x0A)
        session.connection.send(content: data, completion: .contentProcessed { error in
            if let error { print("[HostMode] send error: \(error)") }
        })
    }

    private func showPairingCode(for deviceName: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "LemmingsStudio Vision Pro pairing"
            alert.informativeText = "Enter this code on \(deviceName): \(self.pairingCode)"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

private final class ClientSession {
    let connection: NWConnection
    var buffer = Data()
    var paired = false
    var deviceName = "Vision Pro"
    init(connection: NWConnection) { self.connection = connection }
}

private final class HostedInstance {
    let id: UUID
    let unit: AVAudioUnit
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let sendAudio: (BridgeAudioChunk) -> Void
    private let sendEditorFrame: (BridgeEditorFrame) -> Void
    private var streaming = false
    private var tapInstalled = false
    private var editorSurface: HostedEditorSurface?

    init(id: UUID, unit: AVAudioUnit, sendAudio: @escaping (BridgeAudioChunk) -> Void, sendEditorFrame: @escaping (BridgeEditorFrame) -> Void) throws {
        self.id = id; self.unit = unit; self.sendAudio = sendAudio; self.sendEditorFrame = sendEditorFrame
        engine.attach(unit); engine.attach(mixer)
        let type = unit.auAudioUnit.componentDescription.componentType
        if type == kAudioUnitType_MusicDevice || type == kAudioUnitType_Generator {
            engine.connect(unit, to: mixer, format: nil)
        } else {
            let source = AVAudioSourceNode { _, _, _, abl in
                for buffer in UnsafeMutableAudioBufferListPointer(abl) {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                return noErr
            }
            engine.attach(source)
            engine.connect(source, to: unit, format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
            engine.connect(unit, to: mixer, format: nil)
        }
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        installTap()
        try engine.start()
    }

    func shutdown() {
        editorSurface?.stop(); editorSurface = nil
        if tapInstalled { mixer.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
    }

    func setAudioStreaming(_ enabled: Bool) { streaming = enabled }

    private func installTap() {
        guard !tapInstalled else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        mixer.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self, self.streaming, let left = buffer.floatChannelData?[0] else { return }
            let right = (buffer.format.channelCount > 1 ? buffer.floatChannelData?[1] : nil) ?? left
            let frames = Int(buffer.frameLength)
            var interleaved = [Float](repeating: 0, count: frames * 2)
            for i in 0..<frames { interleaved[i * 2] = left[i]; interleaved[i * 2 + 1] = right[i] }
            let data = interleaved.withUnsafeBufferPointer { Data(buffer: $0) }
            self.sendAudio(.init(instanceID: self.id, sampleRate: buffer.format.sampleRate, channels: 2, frames: frames, interleavedFloat32Base64: data.base64EncodedString()))
        }
        tapInstalled = true
    }

    func parameters() -> [BridgePluginParameter] {
        guard let tree = unit.auAudioUnit.parameterTree else { return [] }
        return tree.allParameters.map { parameter in
            let normalized = Double((parameter.value - parameter.minValue) / max(0.000001, parameter.maxValue - parameter.minValue))
            return .init(id: String(parameter.address), name: parameter.displayName, normalizedValue: normalized, displayValue: parameter.string(fromValue: nil))
        }
    }

    func setParameter(id: String, normalized: Double) {
        guard let address = AUParameterAddress(id), let parameter = unit.auAudioUnit.parameterTree?.parameter(withAddress: address) else { return }
        let clamped = min(1, max(0, normalized))
        parameter.value = parameter.minValue + AUValue(clamped) * (parameter.maxValue - parameter.minValue)
    }

    func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8, sampleOffset: Int) {
        guard let instrument = unit as? AVAudioUnitMIDIInstrument else { return }
        let command = status & 0xF0
        let channel = status & 0x0F
        switch command {
        case 0x80: instrument.stopNote(data1, onChannel: channel)
        case 0x90:
            if data2 == 0 { instrument.stopNote(data1, onChannel: channel) }
            else { instrument.startNote(data1, withVelocity: data2, onChannel: channel) }
        default: instrument.sendMIDIEvent(status, data1: data1, data2: data2)
        }
    }

    func stateBase64() -> String? {
        guard let state = unit.auAudioUnit.fullStateForDocument,
              let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0) else { return nil }
        return data.base64EncodedString()
    }

    func restoreState(_ base64: String) {
        guard let data = Data(base64Encoded: base64),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return }
        unit.auAudioUnit.fullStateForDocument = plist
    }

    func setEditorStreaming(enabled: Bool, width: Int, height: Int, fps: Int) {
        if !enabled { editorSurface?.stop(); editorSurface = nil; return }
        if editorSurface == nil {
            editorSurface = HostedEditorSurface(instanceID: id, audioUnit: unit.auAudioUnit, sendFrame: sendEditorFrame)
        }
        editorSurface?.start(width: max(320, width), height: max(240, height), fps: max(1, min(20, fps)))
    }

    func sendEditorInput(_ input: BridgeEditorInput) { editorSurface?.send(input) }

    func renderOffline(lengthBeats: Double, bpm: Double) throws -> Data {
        let safeBPM = max(20, min(400, bpm))
        let seconds = max(0.1, lengthBeats * 60.0 / safeBPM)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("LemmingsHostRender-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        streaming = false
        if tapInstalled { mixer.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        let totalFrames = AVAudioFramePosition(seconds * format.sampleRate)
        try engine.start()
        var rendered: AVAudioFramePosition = 0
        while rendered < totalFrames {
            let count = AVAudioFrameCount(min(AVAudioFramePosition(engine.manualRenderingMaximumFrameCount), totalFrames - rendered))
            let status = try engine.renderOffline(count, to: buffer)
            switch status {
            case .success:
                try file.write(from: buffer)
                rendered += AVAudioFramePosition(buffer.frameLength)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                Thread.sleep(forTimeInterval: 0.002)
            case .error:
                throw NSError(domain: "LemmingsHostMode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio Unit manual render returned an error"])
            @unknown default:
                throw NSError(domain: "LemmingsHostMode", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown manual rendering status"])
            }
        }
        engine.stop()
        engine.disableManualRenderingMode()
        installTap()
        try engine.start()
        return try Data(contentsOf: tempURL)
    }
}

private final class HostedEditorSurface {
    private let instanceID: UUID
    private let audioUnit: AUAudioUnit
    private let sendFrame: (BridgeEditorFrame) -> Void
    private var panel: NSPanel?
    private var view: NSView?
    private var timer: Timer?
    private var sequence: UInt64 = 0
    private var targetSize = NSSize(width: 900, height: 620)

    init(instanceID: UUID, audioUnit: AUAudioUnit, sendFrame: @escaping (BridgeEditorFrame) -> Void) {
        self.instanceID = instanceID; self.audioUnit = audioUnit; self.sendFrame = sendFrame
    }

    func start(width: Int, height: Int, fps: Int) {
        targetSize = NSSize(width: width, height: height)
        DispatchQueue.main.async {
            self.ensureViewController {
                self.timer?.invalidate()
                self.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in self?.captureFrame() }
                self.captureFrame()
            }
        }
    }

    func stop() {
        DispatchQueue.main.async {
            self.timer?.invalidate(); self.timer = nil
            self.panel?.close(); self.panel = nil; self.view = nil
        }
    }

    private func ensureViewController(_ completion: @escaping () -> Void) {
        if view != nil { completion(); return }
        audioUnit.requestViewController { controller in
            DispatchQueue.main.async {
                let rootView = controller?.view ?? self.genericParameterView()
                rootView.frame = NSRect(origin: .zero, size: self.targetSize)
                let panel = NSPanel(contentRect: rootView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                panel.contentView = rootView
                panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
                panel.orderFrontRegardless()
                self.panel = panel; self.view = rootView
                completion()
            }
        }
    }

    private func genericParameterView() -> NSView {
        let label = NSTextField(labelWithString: "This Audio Unit does not expose a custom editor. Use the synchronized parameter controls on Vision Pro.")
        label.alignment = .center
        label.maximumNumberOfLines = 3
        let container = NSView(frame: NSRect(origin: .zero, size: targetSize))
        label.frame = NSRect(x: 30, y: targetSize.height / 2 - 40, width: targetSize.width - 60, height: 80)
        container.addSubview(label)
        return container
    }

    private func captureFrame() {
        guard let view else { return }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.68]) else { return }
        sequence &+= 1
        sendFrame(.init(instanceID: instanceID, width: Int(bounds.width), height: Int(bounds.height), sequence: sequence, jpegBase64: jpeg.base64EncodedString()))
    }

    func send(_ input: BridgeEditorInput) {
        DispatchQueue.main.async {
            guard let view = self.view, let window = view.window else { return }
            let x = max(0, min(1, input.x)) * view.bounds.width
            let y = (1 - max(0, min(1, input.y))) * view.bounds.height
            let locationInWindow = view.convert(NSPoint(x: x, y: y), to: nil)
            let type: NSEvent.EventType
            switch input.kind {
            case "down": type = .leftMouseDown
            case "up": type = .leftMouseUp
            default: type = .leftMouseDragged
            }
            if let event = NSEvent.mouseEvent(with: type, location: locationInWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: type == .leftMouseDown ? 1 : 0, pressure: type == .leftMouseUp ? 0 : 1) {
                window.sendEvent(event)
            }
        }
    }
}

// MARK: - Buildfix266 project-level Host Mode bounce

private enum DesktopProjectBounceRenderer {
    private struct StereoPCM {
        var left: [Float]
        var right: [Float]
        let sampleRate: Double

        init(frames: Int, sampleRate: Double) {
            self.left = Array(repeating: 0, count: max(1, frames))
            self.right = Array(repeating: 0, count: max(1, frames))
            self.sampleRate = sampleRate
        }

        mutating func add(_ other: StereoPCM, gain: Float = 1, at start: Int = 0) {
            guard start < left.count else { return }
            let count = min(other.left.count, left.count - start)
            guard count > 0 else { return }
            for i in 0..<count {
                left[start + i] += other.left[i] * gain
                right[start + i] += other.right[i] * gain
            }
        }

        mutating func applyGainAndPan(gain: Double, pan: Double) {
            let p = max(-1.0, min(1.0, pan))
            let angle = (p + 1.0) * Double.pi / 4.0
            let lg = Float(cos(angle) * max(0, gain))
            let rg = Float(sin(angle) * max(0, gain))
            for i in left.indices { left[i] *= lg; right[i] *= rg }
        }

        mutating func normalizeIfNeeded(_ enabled: Bool) {
            guard enabled else { return }
            var peak: Float = 0
            for i in left.indices { peak = max(peak, max(abs(left[i]), abs(right[i]))) }
            guard peak > 0.000_001 else { return }
            let gain = min(1.0, 0.98 / peak)
            for i in left.indices { left[i] *= gain; right[i] *= gain }
        }
    }

    static func render(request: BridgeProjectBounceRequest, hostedInstances: [UUID: HostedInstance]) throws -> [BridgeRenderedArtifact] {
        let sampleRate = max(22_050, min(192_000, request.sampleRate))
        let bpm = max(20, min(400, request.bpm))
        let startBeat = max(0, request.startBeat)
        let endBeat = max(startBeat + 0.25, request.endBeat)
        let durationSeconds = (endBeat - startBeat) * 60.0 / bpm
        let totalFrames = max(1, Int((durationSeconds * sampleRate).rounded(.up)))
        let selectedIDs = Set(request.selectedTrackIDs)
        let hasSolo = request.tracks.contains(where: { $0.solo && !$0.muted })
        let assets = Dictionary(uniqueKeysWithValues: request.assets.map { ($0.assetID, $0) })

        var trackPCM: [UUID: StereoPCM] = [:]
        var trackNames: [UUID: String] = [:]

        for track in request.tracks {
            let audible = !track.muted && (!hasSolo || track.solo)
            guard audible else { continue }
            var pcm = StereoPCM(frames: totalFrames, sampleRate: sampleRate)
            for clip in track.clips {
                guard let asset = assets[clip.assetID], let data = Data(base64Encoded: asset.base64) else { continue }
                let decoded = try decodeAudio(data: data, filename: asset.filename, sampleRate: sampleRate)
                let sourceBPM = clip.sourceBPM ?? bpm
                let offsetSeconds = max(0, clip.sourceOffsetBeats) * 60.0 / max(20, sourceBPM)
                let sourceStart = Int(offsetSeconds * sampleRate)
                let desiredFrames = Int(max(0.01, clip.lengthBeats * 60.0 / bpm) * sampleRate)
                let rate = max(0.05, min(8.0, clip.playbackRate))
                let clipStartBeat = clip.startBeat - startBeat
                let destinationStart = Int(max(0, clipStartBeat * 60.0 / bpm) * sampleRate)
                let resampled = resampleSlice(decoded, sourceStart: sourceStart, destinationFrames: desiredFrames, playbackRate: rate)
                pcm.add(resampled, at: destinationStart)
            }
            pcm.applyGainAndPan(gain: track.volume, pan: track.pan)
            trackPCM[track.id] = pcm
            trackNames[track.id] = track.name
        }

        var returnPCM: [String: StereoPCM] = [:]
        if request.includeReturnBuses {
            for bus in request.returnBuses where !bus.muted {
                var sendMix = StereoPCM(frames: totalFrames, sampleRate: sampleRate)
                for track in request.tracks {
                    guard let pcm = trackPCM[track.id], let send = track.sends[bus.id], send > 0 else { continue }
                    sendMix.add(pcm, gain: Float(send))
                }
                let effected = applyReturnEffect(sendMix, kind: bus.effectKind, mixPercent: bus.effectMix, bpm: bpm)
                var adjusted = effected
                adjusted.applyGainAndPan(gain: bus.volume, pan: bus.pan)
                returnPCM[bus.id] = adjusted
            }
        }

        var companionPCM: StereoPCM?
        if request.includeCompanionReturn,
           let instanceID = request.activeHostedInstanceID,
           let instance = hostedInstances[instanceID] {
            let wav = try instance.renderOffline(lengthBeats: endBeat - startBeat, bpm: bpm)
            companionPCM = try decodeAudio(data: wav, filename: "HostedReturn.wav", sampleRate: sampleRate)
        }

        func master(includeOnly ids: Set<UUID>? = nil) -> StereoPCM {
            var out = StereoPCM(frames: totalFrames, sampleRate: sampleRate)
            for (id, pcm) in trackPCM where ids == nil || ids!.contains(id) { out.add(pcm) }
            if request.includeReturnBuses {
                for pcm in returnPCM.values { out.add(pcm) }
            }
            if let companionPCM { out.add(companionPCM) }
            return out
        }

        var artifacts: [BridgeRenderedArtifact] = []
        switch request.scope {
        case "selectedTrack":
            var out = master(includeOnly: selectedIDs.isEmpty ? nil : selectedIDs)
            out.normalizeIfNeeded(request.normalize)
            artifacts.append(try artifact(kind: "selectedTrack", name: "\(safe(request.projectName))-Selected-Tracks.wav", pcm: out))

        case "stems":
            let ids = selectedIDs.isEmpty ? Set(trackPCM.keys) : selectedIDs
            for id in ids.sorted(by: { (trackNames[$0] ?? "") < (trackNames[$1] ?? "") }) {
                guard var pcm = trackPCM[id] else { continue }
                pcm.normalizeIfNeeded(request.normalize)
                artifacts.append(try artifact(kind: "trackStem", name: "\(safe(trackNames[id] ?? "Track"))-Stem.wav", pcm: pcm))
            }
            if request.includeReturnBuses {
                for bus in request.returnBuses {
                    guard var pcm = returnPCM[bus.id] else { continue }
                    pcm.normalizeIfNeeded(request.normalize)
                    artifacts.append(try artifact(kind: "returnBus", name: "\(safe(bus.name))-Return.wav", pcm: pcm))
                }
            }
            if var companionPCM {
                companionPCM.normalizeIfNeeded(request.normalize)
                artifacts.append(try artifact(kind: "hostedPluginReturn", name: "Mac-Hosted-Plugin-Return.wav", pcm: companionPCM))
            }

        default:
            var out = master()
            out.normalizeIfNeeded(request.normalize)
            artifacts.append(try artifact(kind: "master", name: "\(safe(request.projectName))-Master.wav", pcm: out))
        }
        return artifacts
    }

    private static func safe(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(cleaned).replacingOccurrences(of: "--", with: "-")
    }

    private static func artifact(kind: String, name: String, pcm: StereoPCM) throws -> BridgeRenderedArtifact {
        let data = try encodeWAV(pcm)
        return .init(id: UUID(), kind: kind, name: name, wavBase64: data.base64EncodedString())
    }

    private static func decodeAudio(data: Data, filename: String, sampleRate: Double) throws -> StereoPCM {
        let ext = URL(fileURLWithPath: filename).pathExtension.isEmpty ? "wav" : URL(fileURLWithPath: filename).pathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LemmingsBounceDecode-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url, options: .atomic)
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(max(1, file.length))) else {
            throw NSError(domain: "LemmingsHostMode", code: 30, userInfo: [NSLocalizedDescriptionKey: "Could not allocate decode buffer"])
        }
        try file.read(into: sourceBuffer)
        let destinationFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        guard let converter = AVAudioConverter(from: sourceFormat, to: destinationFormat) else {
            throw NSError(domain: "LemmingsHostMode", code: 31, userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }
        let ratio = sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(max(1, Int(Double(sourceBuffer.frameLength) * ratio) + 32))
        let output = AVAudioPCMBuffer(pcmFormat: destinationFormat, frameCapacity: capacity)!
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true; status.pointee = .haveData; return sourceBuffer
        }
        if let error { throw error }
        var pcm = StereoPCM(frames: Int(output.frameLength), sampleRate: sampleRate)
        if let channels = output.floatChannelData {
            for i in 0..<Int(output.frameLength) { pcm.left[i] = channels[0][i]; pcm.right[i] = channels[1][i] }
        }
        return pcm
    }

    private static func resampleSlice(_ input: StereoPCM, sourceStart: Int, destinationFrames: Int, playbackRate: Double) -> StereoPCM {
        var out = StereoPCM(frames: destinationFrames, sampleRate: input.sampleRate)
        guard sourceStart < input.left.count else { return out }
        for i in 0..<destinationFrames {
            let pos = Double(sourceStart) + Double(i) * playbackRate
            let a = Int(pos)
            let b = min(a + 1, input.left.count - 1)
            guard a >= 0 && a < input.left.count else { break }
            let t = Float(pos - Double(a))
            out.left[i] = input.left[a] * (1 - t) + input.left[b] * t
            out.right[i] = input.right[a] * (1 - t) + input.right[b] * t
        }
        return out
    }

    private static func applyReturnEffect(_ input: StereoPCM, kind: String?, mixPercent: Double, bpm: Double) -> StereoPCM {
        let wet = Float(max(0, min(100, mixPercent)) / 100.0)
        guard wet > 0 else { return input }
        var effected = input
        let lower = (kind ?? "").lowercased()
        if lower.contains("delay") {
            let delayFrames = max(1, Int((60.0 / bpm) * 0.75 * input.sampleRate))
            for i in delayFrames..<effected.left.count {
                effected.left[i] += effected.left[i - delayFrames] * 0.42
                effected.right[i] += effected.right[i - delayFrames] * 0.42
            }
        } else {
            let taps = [0.029, 0.043, 0.061, 0.089].map { max(1, Int($0 * input.sampleRate)) }
            for tap in taps {
                for i in tap..<effected.left.count {
                    effected.left[i] += effected.right[i - tap] * 0.16
                    effected.right[i] += effected.left[i - tap] * 0.16
                }
            }
        }
        var out = StereoPCM(frames: input.left.count, sampleRate: input.sampleRate)
        for i in out.left.indices {
            out.left[i] = input.left[i] * (1 - wet) + effected.left[i] * wet
            out.right[i] = input.right[i] * (1 - wet) + effected.right[i] * wet
        }
        return out
    }

    private static func encodeWAV(_ pcm: StereoPCM) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LemmingsProjectBounce-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: pcm.sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.left.count))!
        buffer.frameLength = AVAudioFrameCount(pcm.left.count)
        if let channels = buffer.floatChannelData {
            for i in pcm.left.indices { channels[0][i] = pcm.left[i]; channels[1][i] = pcm.right[i] }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return try Data(contentsOf: url)
    }
}
