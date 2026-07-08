import Foundation
@preconcurrency import Network
import AVFoundation
import Observation

@MainActor
@Observable
final class VisionDesktopBridgeClient {
    private let queue = DispatchQueue(label: "com.magmavance.LemmingsStudioVision.bridge")
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var status: DesktopBridgeStatus = .offline
    var discoveredHosts: [NWBrowser.Result] = []
    var discoveredHostNames: [String] = []
    var plugins: [DesktopPluginDescriptor] = []
    var parameters: [DesktopPluginParameter] = []
    var activeInstanceID: UUID?
    var activePlugin: DesktopPluginDescriptor?
    var statusMessage = "Integrated Mac Host Mode offline"
    var pairingCode = ""
    var audioReturnEnabled = false
    var audioReturnVolume: Float = 1
    var editorStreamingEnabled = false
    var editorJPEGData: Data?
    var editorFrameSize: CGSize = .zero
    var editorFrameSequence: UInt64 = 0
    var offlineRenderBPM: Double = 120
    var offlineRenderLengthBeats: Double = 16
    var lastOfflineRenderURL: URL?
    var projectBounceInFlight = false
    var projectBounceProgress = "Idle"
    var lastProjectBounceURLs: [URL] = []

    let audioReturn = BridgeAudioReturnPlayer()

    func startDiscovery() {
        stopDiscovery()
        status = .discovering
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_lemmings-plugin._tcp", domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                if case .failed(let error) = state {
                    self.status = .degraded
                    self.statusMessage = "Host Mode discovery failed: \(error.localizedDescription)"
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.discoveredHosts = Array(results)
                self.discoveredHostNames = results.map { result in
                    if case .service(let name, _, _, _) = result.endpoint { return name }
                    return String(describing: result.endpoint)
                }
                self.statusMessage = results.isEmpty ? "Searching for LemmingsStudio Mac Host Mode…" : "Found \(results.count) Mac host(s)"
            }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    func stopDiscovery() { browser?.cancel(); browser = nil }

    func connect(index: Int) {
        guard discoveredHosts.indices.contains(index) else { return }
        disconnect()
        let connection = NWConnection(to: discoveredHosts[index].endpoint, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.status = .pairing
                    self.statusMessage = "Connected. Waiting for pairing."
                    self.send(.hello(protocolVersion: 2, deviceName: ProcessInfo.processInfo.hostName))
                    self.receiveLoop()
                case .failed(let error):
                    self.status = .degraded
                    self.statusMessage = "Host Mode connection failed: \(error.localizedDescription)"
                case .cancelled:
                    self.status = .offline
                default: break
                }
            }
        }
        connection.start(queue: queue)
    }

    func submitPairingCode() { send(.pair(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))) }
    func refreshPlugins() { send(.listPlugins) }

    func instantiate(_ descriptor: DesktopPluginDescriptor) {
        let instance = UUID()
        activeInstanceID = instance
        activePlugin = descriptor
        editorJPEGData = nil
        send(.instantiate(pluginID: descriptor.id, instanceID: instance))
    }

    func refreshParameters() {
        guard let id = activeInstanceID else { return }
        send(.listParameters(instanceID: id))
    }

    func setParameter(id: String, normalizedValue: Double) {
        guard let instance = activeInstanceID else { return }
        send(.setParameter(instanceID: instance, parameterID: id, value: normalizedValue))
    }

    func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8, sampleOffset: Int = 0) {
        guard let instance = activeInstanceID else { return }
        send(.midi(instanceID: instance, status: status, data1: data1, data2: data2, sampleOffset: sampleOffset))
    }

    func setAudioReturnVolume(_ value: Float) {
        audioReturnVolume = max(0, min(1.5, value)); audioReturn.setVolume(audioReturnVolume)
    }

    func setAudioReturnEnabled(_ enabled: Bool) {
        guard let instance = activeInstanceID else { return }
        audioReturnEnabled = enabled
        if enabled { audioReturn.start() } else { audioReturn.stop() }
        send(.subscribeAudio(instanceID: instance, enabled: enabled))
    }

    func setEditorStreamingEnabled(_ enabled: Bool, width: Int = 1000, height: Int = 700, fps: Int = 12) {
        guard let instance = activeInstanceID else { return }
        editorStreamingEnabled = enabled
        send(.subscribeEditor(instanceID: instance, enabled: enabled, width: width, height: height, fps: fps))
        if !enabled { editorJPEGData = nil }
    }

    func sendEditorInput(kind: String, x: Double, y: Double, deltaX: Double = 0, deltaY: Double = 0, button: Int = 0) {
        guard let instance = activeInstanceID else { return }
        send(.editorInput(instanceID: instance, input: .init(kind: kind, x: x, y: y, deltaX: deltaX, deltaY: deltaY, button: button)))
    }

    func requestProjectBounce(_ request: DesktopProjectBounceRequest) {
        guard status == .connected else {
            statusMessage = "Connect and pair with LemmingsStudio Mac Host Mode first"
            return
        }
        projectBounceInFlight = true
        projectBounceProgress = "Uploading project render manifest and assets…"
        lastProjectBounceURLs = []
        send(.requestProjectBounce(request: request))
    }

    func requestOfflineRender() {
        guard let instance = activeInstanceID else { return }
        lastOfflineRenderURL = nil
        statusMessage = "Requesting Mac-rendered WAV…"
        send(.requestOfflineRender(instanceID: instance, startBeat: 0, lengthBeats: max(0.25, offlineRenderLengthBeats), bpm: max(20, min(400, offlineRenderBPM))))
    }

    func disconnect() {
        connection?.cancel(); connection = nil
        receiveBuffer.removeAll(keepingCapacity: false)
        status = .offline
        activeInstanceID = nil
        activePlugin = nil
        parameters = []
        editorJPEGData = nil
        editorStreamingEnabled = false
        audioReturn.stop()
    }

    private func send(_ message: DesktopBridgeMessage) {
        guard let connection else { return }
        do {
            var data = try encoder.encode(message)
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { _ in })
        } catch {
            statusMessage = "Host Mode encode error: \(error.localizedDescription)"
        }
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024 * 1024) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.receiveBuffer.append(data); self.consumeLines() }
                if complete || error != nil {
                    self.status = .degraded
                    self.statusMessage = error?.localizedDescription ?? "Mac Host Mode disconnected"
                    return
                }
                self.receiveLoop()
            }
        }
    }

    private func consumeLines() {
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let line = receiveBuffer.prefix(upTo: newline)
            receiveBuffer.removeSubrange(...newline)
            guard !line.isEmpty, let message = try? decoder.decode(DesktopBridgeMessage.self, from: Data(line)) else { continue }
            handle(message)
        }
    }

    private func handle(_ message: DesktopBridgeMessage) {
        switch message {
        case .pairingRequired:
            status = .pairing; statusMessage = "Enter the six-digit code shown on the Mac"
        case .pairResult(let accepted, let message):
            status = accepted ? .connected : .pairing; statusMessage = message
            if accepted { refreshPlugins() }
        case .helloAccepted(_, let hostName):
            statusMessage = "Connected to \(hostName)"
        case .plugins(let values):
            plugins = values; statusMessage = "Loaded \(values.count) desktop plug-ins"
        case .instantiateResult(let instance, let accepted, let message):
            statusMessage = message
            if accepted { activeInstanceID = instance; refreshParameters() }
        case .parameters(_, let values):
            parameters = values
        case .audioChunk(let chunk):
            audioReturn.enqueue(chunk)
        case .editorFrame(let frame):
            guard frame.sequence >= editorFrameSequence, let data = Data(base64Encoded: frame.jpegBase64) else { return }
            editorFrameSequence = frame.sequence
            editorJPEGData = data
            editorFrameSize = CGSize(width: frame.width, height: frame.height)
        case .offlineRenderResult(_, let wavBase64, let message):
            statusMessage = message
            guard let wavBase64, let data = Data(base64Encoded: wavBase64) else { return }
            do {
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
                let url = directory.appendingPathComponent("LemmingsStudio-MacHost-\(Int(Date().timeIntervalSince1970)).wav")
                try data.write(to: url, options: .atomic)
                lastOfflineRenderURL = url
                statusMessage += " Saved to \(url.lastPathComponent)."
            } catch {
                statusMessage = "Render received, but save failed: \(error.localizedDescription)"
            }
        case .projectBounceResult(_, let artifacts, let message):
            projectBounceInFlight = false
            statusMessage = message
            projectBounceProgress = message
            do {
                let root = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
                    .appendingPathComponent("Exports", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                var urls: [URL] = []
                for artifact in artifacts {
                    guard let data = Data(base64Encoded: artifact.wavBase64) else { continue }
                    let url = root.appendingPathComponent(artifact.name)
                    try data.write(to: url, options: .atomic)
                    urls.append(url)
                }
                lastProjectBounceURLs = urls
                projectBounceProgress = urls.isEmpty ? message : "Saved \(urls.count) artifact(s) to Documents/Exports."
            } catch {
                projectBounceProgress = "Render received, but export save failed: \(error.localizedDescription)"
            }
        case .error(let message): statusMessage = message
        case .pong: break
        default: break
        }
    }
}

@MainActor
final class BridgeAudioReturnPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    func start() {
        guard !started else { return }
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = 1
        try? engine.start(); player.play(); started = true
    }

    func stop() {
        guard started else { return }
        player.stop(); engine.stop(); started = false
    }

    func setVolume(_ value: Float) { player.volume = max(0, min(1.5, value)) }

    func enqueue(_ chunk: DesktopBridgeAudioChunk) {
        guard started,
              let raw = Data(base64Encoded: chunk.interleavedFloat32Base64),
              chunk.channels == 2,
              let format = AVAudioFormat(standardFormatWithSampleRate: chunk.sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(chunk.frames)
        raw.withUnsafeBytes { bytes in
            guard let src = bytes.baseAddress?.assumingMemoryBound(to: Float.self),
                  let left = buffer.floatChannelData?[0], let right = buffer.floatChannelData?[1] else { return }
            for i in 0..<chunk.frames { left[i] = src[i * 2]; right[i] = src[i * 2 + 1] }
        }
        player.scheduleBuffer(buffer)
    }
}
