@preconcurrency import AVFAudio
import AudioToolbox
import Foundation
import Observation

enum VisionNativeExportFormat: String, CaseIterable, Identifiable, Sendable {
    case wav24 = "WAV 24-bit"
    case wav32Float = "WAV 32-bit Float"
    case aiff24 = "AIFF 24-bit"
    case m4aAAC = "M4A / AAC"
    var id: String { rawValue }
    var fileExtension: String {
        switch self { case .wav24, .wav32Float: "wav"; case .aiff24: "aiff"; case .m4aAAC: "m4a" }
    }
}

enum VisionStemMode: String, CaseIterable, Identifiable, Sendable {
    case preFader = "Pre-Fader"
    case postFader = "Post-Fader"
    case postFX = "Post-FX"
    var id: String { rawValue }
}

enum VisionReturnExportMode: String, CaseIterable, Identifiable, Sendable {
    case baked = "Bake Into Mix"
    case separate = "Separate Returns"
    case both = "Bake + Separate"
    case none = "Exclude Returns"
    var id: String { rawValue }
    var includesBakedReturns: Bool { self == .baked || self == .both }
    var exportsSeparateReturns: Bool { self == .separate || self == .both }
}

struct VisionExportProgress: Sendable {
    var phase: String
    var trackName: String
    var trackIndex: Int
    var totalTracks: Int
    var completedFrames: Int64
    var totalFrames: Int64
    var fraction: Double
}

@MainActor
@Observable
final class VisionNativeExportState {
    var format: VisionNativeExportFormat = .wav24
    var sampleRate: Double = 48_000
    var normalize = false
    var startBeat: Double = 0
    var endBeat: Double = 128
    var tailSeconds: Double = 2
    var stemMode: VisionStemMode = .postFader
    var returnMode: VisionReturnExportMode = .baked
    var isExporting = false
    var progress: Double = 0
    var phase = "Idle"
    var currentTrack = ""
    var trackIndex = 0
    var totalTracks = 0
    var completedFrames: Int64 = 0
    var totalFrames: Int64 = 0
    var status = "Ready to export"
    var latestMasterURL: URL?
    var latestStemsDirectory: URL?
    var exportTask: Task<Void, Never>?
}

enum VisionNativeExportError: LocalizedError {
    case invalidRange
    case cannotCreateBuffer
    case unsupportedFormat
    case manualRenderingFailure(String)
    case cancelled
    var errorDescription: String? {
        switch self {
        case .invalidRange: "Export range is empty."
        case .cannotCreateBuffer: "Could not allocate the export audio buffer."
        case .unsupportedFormat: "The selected audio format could not be encoded on this device."
        case .manualRenderingFailure(let message): "Offline graph render failed: \(message)"
        case .cancelled: "Export cancelled."
        }
    }
}

struct VisionLiveFXSnapshot: Sendable {
    var lowGain: Float = 0
    var midGain: Float = 0
    var highGain: Float = 0
    var delayTime: Double = 0.24
    var delayFeedback: Float = 18
    var delayMix: Float = 0
    var reverbMix: Float = 10
}

struct VisionNativeExportStateSnapshot: Sendable {
    var format: VisionNativeExportFormat
    var sampleRate: Double
    var normalize: Bool
    var startBeat: Double
    var endBeat: Double
    var tailSeconds: Double
    var stemMode: VisionStemMode
    var returnMode: VisionReturnExportMode
    var liveFX: VisionLiveFXSnapshot
}

struct StereoPCM: Sendable {
    var left: [Float]
    var right: [Float]
    var frameCount: Int { min(left.count, right.count) }
    static func silence(frames: Int) -> StereoPCM {
        StereoPCM(left: [Float](repeating: 0, count: frames), right: [Float](repeating: 0, count: frames))
    }
    mutating func add(_ other: StereoPCM) {
        let count = min(frameCount, other.frameCount)
        for i in 0..<count { left[i] += other.left[i]; right[i] += other.right[i] }
    }
}

private struct VisionRenderedTrack: Sendable {
    var index: Int
    var track: VisionTrack
    var preFader: StereoPCM
    var postFader: StereoPCM
    var sendA: StereoPCM
    var sendB: StereoPCM
}

actor VisionNativeProjectRenderer {
    static let shared = VisionNativeProjectRenderer()
    typealias ProgressHandler = @Sendable (VisionExportProgress) -> Void

    func renderMaster(
        project: LemmingsProject,
        projectURL: URL?,
        state: VisionNativeExportStateSnapshot,
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        try Task.checkCancellation()
        let tracks = try await renderTracks(project: project, projectURL: projectURL, state: state, progress: progress)
        try Task.checkCancellation()

        var dry = StereoPCM.silence(frames: totalFrames(project: project, state: state))
        var sendA = StereoPCM.silence(frames: dry.frameCount)
        var sendB = StereoPCM.silence(frames: dry.frameCount)
        for item in tracks { dry.add(item.postFader); sendA.add(item.sendA); sendB.add(item.sendB) }

        let returns = project.returnBuses ?? VisionReturnBus.defaults
        let graph = try await renderSharedFXGraph(
            dry: dry,
            sendA: state.returnMode == .none || state.returnMode == .separate ? .silence(frames: dry.frameCount) : sendA,
            sendB: state.returnMode == .none || state.returnMode == .separate ? .silence(frames: dry.frameCount) : sendB,
            returns: returns,
            state: state,
            hostedAU: project.visionHostedAudioUnit,
            progressBase: 0.78,
            progressSpan: 0.18,
            progress: progress
        )
        var master = graph
        applyMasterGain(project: project, pcm: &master)
        try Task.checkCancellation()
        progress(.init(phase: "Writing master", trackName: "Master", trackIndex: 1, totalTracks: 1, completedFrames: Int64(master.frameCount), totalFrames: Int64(master.frameCount), fraction: 0.98))
        try write(pcm: master, sampleRate: state.sampleRate, format: state.format, normalize: state.normalize, destination: destination)
        progress(.init(phase: "Complete", trackName: "Master", trackIndex: 1, totalTracks: 1, completedFrames: Int64(master.frameCount), totalFrames: Int64(master.frameCount), fraction: 1))
    }

    func renderStems(
        project: LemmingsProject,
        projectURL: URL?,
        state: VisionNativeExportStateSnapshot,
        directory: URL,
        progress: @escaping ProgressHandler
    ) async throws -> [URL] {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rendered = try await renderTracks(project: project, projectURL: projectURL, state: state, progress: progress)
        var urls: [URL] = []
        let returns = project.returnBuses ?? VisionReturnBus.defaults
        let total = rendered.count + (state.returnMode.exportsSeparateReturns ? 2 : 0)

        for (position, item) in rendered.enumerated() {
            try Task.checkCancellation()
            let safe = sanitize(item.track.name.isEmpty ? "Track \(item.index + 1)" : item.track.name)
            let url = directory.appendingPathComponent(String(format: "%02d-%@", item.index + 1, safe)).appendingPathExtension(state.format.fileExtension)
            let pcm: StereoPCM
            switch state.stemMode {
            case .preFader:
                pcm = item.preFader
            case .postFader:
                pcm = item.postFader
            case .postFX:
                pcm = try await renderSharedFXGraph(
                    dry: item.postFader,
                    sendA: state.returnMode.includesBakedReturns ? item.sendA : .silence(frames: item.postFader.frameCount),
                    sendB: state.returnMode.includesBakedReturns ? item.sendB : .silence(frames: item.postFader.frameCount),
                    returns: returns,
                    state: state,
                    hostedAU: project.visionHostedAudioUnit,
                    progressBase: 0.72 + Double(position) / Double(max(1, total)) * 0.20,
                    progressSpan: 0.20 / Double(max(1, total)),
                    progress: progress
                )
            }
            progress(.init(phase: "Writing stem", trackName: item.track.name, trackIndex: position + 1, totalTracks: total, completedFrames: Int64(pcm.frameCount), totalFrames: Int64(pcm.frameCount), fraction: 0.74 + Double(position) / Double(max(1, total)) * 0.24))
            try write(pcm: pcm, sampleRate: state.sampleRate, format: state.format, normalize: state.normalize, destination: url)
            urls.append(url)
        }

        if state.returnMode.exportsSeparateReturns {
            var allA = StereoPCM.silence(frames: totalFrames(project: project, state: state))
            var allB = StereoPCM.silence(frames: allA.frameCount)
            for item in rendered { allA.add(item.sendA); allB.add(item.sendB) }
            let returnA = try await renderReturnOnly(input: allA, bus: returns.first(where: { $0.id == "return-a" }) ?? VisionReturnBus.defaults[0], kind: .delay, state: state)
            let returnB = try await renderReturnOnly(input: allB, bus: returns.first(where: { $0.id == "return-b" }) ?? VisionReturnBus.defaults[1], kind: .reverb, state: state)
            let aURL = directory.appendingPathComponent("Return-A").appendingPathExtension(state.format.fileExtension)
            let bURL = directory.appendingPathComponent("Return-B").appendingPathExtension(state.format.fileExtension)
            try write(pcm: returnA, sampleRate: state.sampleRate, format: state.format, normalize: state.normalize, destination: aURL)
            try write(pcm: returnB, sampleRate: state.sampleRate, format: state.format, normalize: state.normalize, destination: bURL)
            urls.append(contentsOf: [aURL, bURL])
        }
        progress(.init(phase: "Complete", trackName: "Stems", trackIndex: total, totalTracks: total, completedFrames: Int64(totalFrames(project: project, state: state)), totalFrames: Int64(totalFrames(project: project, state: state)), fraction: 1))
        return urls
    }

    private func renderTracks(
        project: LemmingsProject,
        projectURL: URL?,
        state: VisionNativeExportStateSnapshot,
        progress: @escaping ProgressHandler
    ) async throws -> [VisionRenderedTrack] {
        let audible = audibleTracks(project)
        let frames = totalFrames(project: project, state: state)
        let package = VisionProjectPersistence.packageBaseURL(for: projectURL)
        var output: [VisionRenderedTrack] = []
        for (position, pair) in audible.enumerated() {
            try Task.checkCancellation()
            let (index, track) = pair
            let trackName = track.name.isEmpty ? "Track \(index + 1)" : track.name
            progress(.init(phase: "Rendering track", trackName: trackName, trackIndex: position + 1, totalTracks: audible.count, completedFrames: 0, totalFrames: Int64(frames), fraction: Double(position) / Double(max(1, audible.count)) * 0.70))
            var dry = StereoPCM.silence(frames: frames)
            for clip in track.audioClips {
                try Task.checkCancellation()
                try mixAudioClip(clip, package: package, bpm: max(20, project.effectiveTempo), state: state, left: &dry.left, right: &dry.right)
            }
            for clip in track.clips {
                try Task.checkCancellation()
                synthesizeMIDIClip(clip, bpm: max(20, project.effectiveTempo), state: state, left: &dry.left, right: &dry.right)
            }
            var post = dry
            var sendA = StereoPCM.silence(frames: frames)
            var sendB = StereoPCM.silence(frames: frames)
            applyTrackAutomationAndRouting(project: project, track: track, state: state, dry: dry, post: &post, sendA: &sendA, sendB: &sendB) { frame in
                if frame % 8192 == 0 {
                    let local = Double(frame) / Double(max(1, frames))
                    let fraction = (Double(position) + local) / Double(max(1, audible.count)) * 0.70
                    progress(.init(phase: "Applying automation", trackName: trackName, trackIndex: position + 1, totalTracks: audible.count, completedFrames: Int64(frame), totalFrames: Int64(frames), fraction: fraction))
                }
            }
            output.append(.init(index: index, track: track, preFader: dry, postFader: post, sendA: sendA, sendB: sendB))
        }
        return output
    }

    private func audibleTracks(_ project: LemmingsProject) -> [(Int, VisionTrack)] {
        let hasSolo = project.tracks.contains { $0.solo == true }
        return project.tracks.enumerated().compactMap { index, track in
            guard track.mute != true, !hasSolo || track.solo == true else { return nil }
            return (index, track)
        }
    }

    private func totalFrames(project: LemmingsProject, state: VisionNativeExportStateSnapshot) -> Int {
        let secondsPerBeat = 60.0 / max(20, project.effectiveTempo)
        let duration = max(0, state.endBeat - state.startBeat) * secondsPerBeat + max(0, state.tailSeconds)
        return max(1, Int(ceil(duration * state.sampleRate)))
    }

    private func applyTrackAutomationAndRouting(
        project: LemmingsProject,
        track: VisionTrack,
        state: VisionNativeExportStateSnapshot,
        dry: StereoPCM,
        post: inout StereoPCM,
        sendA: inout StereoPCM,
        sendB: inout StereoPCM,
        progress: (Int) -> Void
    ) {
        let bpm = max(20, project.effectiveTempo)
        let secondsPerBeat = 60.0 / bpm
        let lanes = project.automationLanes ?? []
        let volumeLane = lanes.first { $0.address.backendID == "visionMixer" && $0.address.instanceID == track.id.uuidString && $0.address.parameterID == "volume" }
        let panLane = lanes.first { $0.address.backendID == "visionMixer" && $0.address.instanceID == track.id.uuidString && $0.address.parameterID == "pan" }
        let sendALane = lanes.first { $0.address.backendID == "visionMixer" && $0.address.instanceID == track.id.uuidString && $0.address.parameterID == "send.return-a" }
        let sendBLane = lanes.first { $0.address.backendID == "visionMixer" && $0.address.instanceID == track.id.uuidString && $0.address.parameterID == "send.return-b" }
        let baseVolume = max(0, track.volume ?? 1)
        let basePan = max(-1, min(1, track.pan ?? 0))
        let baseA = max(0, track.sends?["return-a"] ?? 0)
        let baseB = max(0, track.sends?["return-b"] ?? 0)
        let count = dry.frameCount
        for frame in 0..<count {
            let seconds = Double(frame) / state.sampleRate
            let beat = state.startBeat + seconds / secondsPerBeat
            let volume = volumeLane.flatMap { automationValue($0, at: beat) } ?? baseVolume
            let panNorm = panLane.flatMap { automationValue($0, at: beat) }
            let pan = panNorm.map { max(-1, min(1, $0 * 2 - 1)) } ?? basePan
            let gainL = volume * (pan <= 0 ? 1 : 1 - pan)
            let gainR = volume * (pan >= 0 ? 1 : 1 + pan)
            post.left[frame] = dry.left[frame] * gainL
            post.right[frame] = dry.right[frame] * gainR
            let a = sendALane.flatMap { automationValue($0, at: beat) } ?? baseA
            let b = sendBLane.flatMap { automationValue($0, at: beat) } ?? baseB
            sendA.left[frame] = post.left[frame] * a; sendA.right[frame] = post.right[frame] * a
            sendB.left[frame] = post.left[frame] * b; sendB.right[frame] = post.right[frame] * b
            progress(frame)
        }
    }

    private func automationValue(_ lane: VisionAutomationLane, at beat: Double) -> Float? {
        let points = lane.points.sorted { $0.beat < $1.beat }
        guard let first = points.first else { return nil }
        if beat <= first.beat { return first.value }
        guard let last = points.last else { return first.value }
        if beat >= last.beat { return last.value }
        for (a, b) in zip(points, points.dropFirst()) where beat >= a.beat && beat <= b.beat {
            let raw = Float((beat - a.beat) / max(0.000001, b.beat - a.beat))
            let h = max(-0.95, min(0.95, a.curveHandle))
            let biased = abs(h) < 0.001 ? raw : powf(max(0, min(1, raw)), powf(2, h * -3))
            let t: Float
            switch a.curve {
            case .hold: return a.value
            case .linear: t = biased
            case .smooth: t = biased * biased * (3 - 2 * biased)
            case .exponential: t = powf(max(0, raw), powf(2, a.curveHandle * 3))
            }
            return a.value + (b.value - a.value) * t
        }
        return last.value
    }

    private enum ReturnKind { case delay, reverb }

    private func renderSharedFXGraph(
        dry: StereoPCM,
        sendA: StereoPCM,
        sendB: StereoPCM,
        returns: [VisionReturnBus],
        state: VisionNativeExportStateSnapshot,
        hostedAU: VisionHostedAudioUnitState?,
        progressBase: Double,
        progressSpan: Double,
        progress: @escaping ProgressHandler
    ) async throws -> StereoPCM {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: state.sampleRate, channels: 2, interleaved: false)!
        let engine = AVAudioEngine()
        let dryPlayer = AVAudioPlayerNode(), aPlayer = AVAudioPlayerNode(), bPlayer = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 3)
        let delay = AVAudioUnitDelay(), reverb = AVAudioUnitReverb()
        let returnADelay = AVAudioUnitDelay(), returnBReverb = AVAudioUnitReverb()
        engine.attach(dryPlayer); engine.attach(aPlayer); engine.attach(bPlayer)
        engine.attach(eq); engine.attach(delay); engine.attach(reverb); engine.attach(returnADelay); engine.attach(returnBReverb)

        eq.bands[0].filterType = .lowShelf; eq.bands[0].frequency = 120; eq.bands[0].gain = state.liveFX.lowGain; eq.bands[0].bypass = false
        eq.bands[1].filterType = .parametric; eq.bands[1].frequency = 1_200; eq.bands[1].bandwidth = 1; eq.bands[1].gain = state.liveFX.midGain; eq.bands[1].bypass = false
        eq.bands[2].filterType = .highShelf; eq.bands[2].frequency = 8_000; eq.bands[2].gain = state.liveFX.highGain; eq.bands[2].bypass = false
        delay.delayTime = state.liveFX.delayTime; delay.feedback = state.liveFX.delayFeedback; delay.wetDryMix = state.liveFX.delayMix
        reverb.loadFactoryPreset(.mediumHall); reverb.wetDryMix = state.liveFX.reverbMix
        returnADelay.delayTime = 0.28; returnADelay.feedback = 24; returnADelay.wetDryMix = 100
        returnBReverb.loadFactoryPreset(.largeHall); returnBReverb.wetDryMix = 100

        let aBus = returns.first(where: { $0.id == "return-a" }) ?? VisionReturnBus.defaults[0]
        let bBus = returns.first(where: { $0.id == "return-b" }) ?? VisionReturnBus.defaults[1]
        let aMixer = AVAudioMixerNode(), bMixer = AVAudioMixerNode()
        engine.attach(aMixer); engine.attach(bMixer)
        aMixer.outputVolume = aBus.mute ? 0 : aBus.volume; aMixer.pan = aBus.pan
        bMixer.outputVolume = bBus.mute ? 0 : bBus.volume; bMixer.pan = bBus.pan
        returnADelay.wetDryMix = aBus.effectMix ?? 100
        returnBReverb.wetDryMix = bBus.effectMix ?? 100

        var offlineAU: AVAudioUnit?
        if let hostedAU, hostedAU.kind == .effect || hostedAU.kind == .other {
            offlineAU = try await instantiateAudioUnit(hostedAU)
            if let offlineAU { engine.attach(offlineAU) }
        }
        if let offlineAU {
            engine.connect(dryPlayer, to: offlineAU, format: format)
            engine.connect(offlineAU, to: eq, format: format)
        } else {
            engine.connect(dryPlayer, to: eq, format: format)
        }
        engine.connect(eq, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.connect(aPlayer, to: aMixer, format: format); engine.connect(aMixer, to: returnADelay, format: format); engine.connect(returnADelay, to: engine.mainMixerNode, format: format)
        engine.connect(bPlayer, to: bMixer, format: format); engine.connect(bMixer, to: returnBReverb, format: format); engine.connect(returnBReverb, to: engine.mainMixerNode, format: format)

        let dryBuffer = try makeBuffer(dry, format: format), aBuffer = try makeBuffer(sendA, format: format), bBuffer = try makeBuffer(sendB, format: format)
        dryPlayer.scheduleBuffer(dryBuffer, completionHandler: nil)
        aPlayer.scheduleBuffer(aBuffer, completionHandler: nil)
        bPlayer.scheduleBuffer(bBuffer, completionHandler: nil)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 2048)
        engine.prepare(); try engine.start(); dryPlayer.play(); aPlayer.play(); bPlayer.play()
        let total = dry.frameCount
        var output = StereoPCM.silence(frames: total)
        var offset = 0
        while offset < total {
            try Task.checkCancellation()
            let request = AVAudioFrameCount(min(2048, total - offset))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: request) else { throw VisionNativeExportError.cannotCreateBuffer }
            let status = try engine.renderOffline(request, to: buffer)
            switch status {
            case .success:
                guard let channels = buffer.floatChannelData else { throw VisionNativeExportError.cannotCreateBuffer }
                let count = Int(buffer.frameLength)
                for i in 0..<count { output.left[offset + i] = channels[0][i]; output.right[offset + i] = channels[1][i] }
                offset += count
                let f = progressBase + Double(offset) / Double(max(1, total)) * progressSpan
                progress(.init(phase: offlineAU == nil ? "Rendering FX graph" : "Rendering AUv3 + FX graph", trackName: "FX Graph", trackIndex: 1, totalTracks: 1, completedFrames: Int64(offset), totalFrames: Int64(total), fraction: min(0.99, f)))
            case .insufficientDataFromInputNode: continue
            case .cannotDoInCurrentContext: await Task.yield()
            case .error: throw VisionNativeExportError.manualRenderingFailure("AVAudioEngine returned .error")
            @unknown default: throw VisionNativeExportError.manualRenderingFailure("Unknown manual rendering status")
            }
        }
        engine.stop(); engine.disableManualRenderingMode()
        return output
    }

    private func renderReturnOnly(input: StereoPCM, bus: VisionReturnBus, kind: ReturnKind, state: VisionNativeExportStateSnapshot) async throws -> StereoPCM {
        let silence = StereoPCM.silence(frames: input.frameCount)
        switch kind {
        case .delay:
            return try await renderSharedFXGraph(dry: silence, sendA: input, sendB: silence, returns: [bus, VisionReturnBus.defaults[1]], state: state, hostedAU: nil, progressBase: 0.92, progressSpan: 0.05, progress: { _ in })
        case .reverb:
            return try await renderSharedFXGraph(dry: silence, sendA: silence, sendB: input, returns: [VisionReturnBus.defaults[0], bus], state: state, hostedAU: nil, progressBase: 0.92, progressSpan: 0.05, progress: { _ in })
        }
    }

    private func instantiateAudioUnit(_ saved: VisionHostedAudioUnitState) async throws -> AVAudioUnit {
        let description = AudioComponentDescription(componentType: saved.componentType, componentSubType: saved.componentSubType, componentManufacturer: saved.componentManufacturer, componentFlags: 0, componentFlagsMask: 0)
        let unit: AVAudioUnit = try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: [.loadOutOfProcess]) { unit, error in
                if let unit { continuation.resume(returning: unit) }
                else { continuation.resume(throwing: error ?? NSError(domain: "LemmingsStudio.AUv3Offline", code: -1)) }
            }
        }
        if let data = Data(base64Encoded: saved.stateBase64),
           let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            unit.auAudioUnit.fullStateForDocument = dictionary
        }
        return unit
    }

    private func makeBuffer(_ pcm: StereoPCM, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.frameCount)), let channels = buffer.floatChannelData else { throw VisionNativeExportError.cannotCreateBuffer }
        buffer.frameLength = AVAudioFrameCount(pcm.frameCount)
        pcm.left.withUnsafeBufferPointer { src in channels[0].update(from: src.baseAddress!, count: pcm.frameCount) }
        pcm.right.withUnsafeBufferPointer { src in channels[1].update(from: src.baseAddress!, count: pcm.frameCount) }
        return buffer
    }

    private func applyMasterGain(project: LemmingsProject, pcm: inout StereoPCM) {
        let gain = project.masterMuted == true ? Float(0) : max(0, project.masterVolume ?? 1)
        guard gain != 1 else { return }
        for i in 0..<pcm.frameCount { pcm.left[i] *= gain; pcm.right[i] *= gain }
    }

    private func mixAudioClip(_ clip: VisionAudioClip, package: URL?, bpm: Double, state: VisionNativeExportStateSnapshot, left: inout [Float], right: inout [Float]) throws {
        guard let path = clip.sourcePath, !path.isEmpty else { return }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : (package?.appendingPathComponent(path) ?? URL(fileURLWithPath: path))
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let file = try AVAudioFile(forReading: url)
        let count = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { return }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return }
        let srcFrames = Int(buffer.frameLength), srcRate = file.processingFormat.sampleRate
        let secondsPerBeat = 60.0 / bpm
        let outStart = Int(round((clip.startBeat - state.startBeat) * secondsPerBeat * state.sampleRate))
        let outCount = Int(round(clip.lengthBeats * secondsPerBeat * state.sampleRate))
        let sourceOffsetSeconds = (clip.sourceOffsetBeats ?? 0) * secondsPerBeat
        let rate = max(0.25, min(4, clip.playbackRate ?? 1))
        let channelCount = Int(buffer.format.channelCount)
        for n in 0..<outCount {
            let dst = outStart + n
            guard dst >= 0, dst < left.count else { continue }
            let sourcePosition = (sourceOffsetSeconds + Double(n) / state.sampleRate * rate) * srcRate
            let i0 = Int(sourcePosition)
            guard i0 >= 0, i0 < srcFrames else { continue }
            let i1 = min(srcFrames - 1, i0 + 1), frac = Float(sourcePosition - Double(i0))
            let lv = channels[0][i0] + (channels[0][i1] - channels[0][i0]) * frac
            let rv = channelCount > 1 ? channels[1][i0] + (channels[1][i1] - channels[1][i0]) * frac : lv
            left[dst] += lv; right[dst] += rv
        }
    }

    private func synthesizeMIDIClip(_ clip: VisionMIDIClip, bpm: Double, state: VisionNativeExportStateSnapshot, left: inout [Float], right: inout [Float]) {
        guard let notes = clip.notes, !notes.isEmpty else { return }
        let secondsPerBeat = 60.0 / bpm, loopLength = max(0.001, clip.loopLengthBeats ?? clip.lengthBeats)
        var cycle = 0.0
        while cycle < clip.lengthBeats - 0.0001 {
            for note in notes {
                let visibleBeat = clip.startBeat + cycle + note.startBeat
                guard visibleBeat < clip.startBeat + clip.lengthBeats else { continue }
                let startSeconds = (visibleBeat - state.startBeat) * secondsPerBeat
                let durationSeconds = max(0.02, min(note.lengthBeats, clip.lengthBeats - cycle - note.startBeat) * secondsPerBeat)
                synthesizeNote(note: note.note, velocity: note.velocity, startSeconds: startSeconds, durationSeconds: durationSeconds, sampleRate: state.sampleRate, left: &left, right: &right)
            }
            cycle += loopLength
        }
    }

    private func synthesizeNote(note: Int, velocity: Int, startSeconds: Double, durationSeconds: Double, sampleRate: Double, left: inout [Float], right: inout [Float]) {
        let start = Int(round(startSeconds * sampleRate)), frames = Int(round(durationSeconds * sampleRate))
        guard frames > 0 else { return }
        let amp = Float(max(1, min(127, velocity))) / 127 * 0.22
        let isDrum = (35...51).contains(note), frequency = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
        var seed = UInt64(bitPattern: Int64(note * 7919 + start)) | 1
        for n in 0..<frames {
            let dst = start + n
            guard dst >= 0, dst < left.count else { continue }
            let t = Double(n) / sampleRate
            let value: Float
            if isDrum {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let noise = Float(Double(Int64(bitPattern: seed)) / Double(Int64.max))
                let decay = Float(exp(-t * (note == 36 ? 8 : note == 38 ? 16 : 32)))
                let tonal = Float(sin(2 * Double.pi * (note == 36 ? 58 : 180) * t))
                value = amp * decay * (note == 36 ? tonal : 0.55 * noise + 0.45 * tonal)
            } else {
                let attack = min(1.0, t / 0.01), releaseStart = max(0, durationSeconds - 0.08)
                let release = t > releaseStart ? max(0, (durationSeconds - t) / 0.08) : 1
                value = amp * Float(attack * release) * Float(sin(2 * .pi * frequency * t) + 0.28 * sin(2 * .pi * frequency * 2 * t))
            }
            left[dst] += value; right[dst] += value
        }
    }

    private func write(pcm: StereoPCM, sampleRate: Double, format: VisionNativeExportFormat, normalize: Bool, destination: URL) throws {
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: destination)
        var left = pcm.left, right = pcm.right
        if normalize {
            let peak = max(left.lazy.map { Swift.abs($0) }.max() ?? 0, right.lazy.map { Swift.abs($0) }.max() ?? 0)
            if peak > 0.0001 {
                let scale = min(8, 0.98 / peak)
                for i in left.indices { left[i] *= scale; right[i] *= scale }
            }
        }
        let avFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(left.count)), let channels = buffer.floatChannelData else { throw VisionNativeExportError.cannotCreateBuffer }
        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { src in channels[0].update(from: src.baseAddress!, count: left.count) }
        right.withUnsafeBufferPointer { src in channels[1].update(from: src.baseAddress!, count: right.count) }
        let settings: [String: Any]
        switch format {
        case .wav24: settings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        case .wav32Float: settings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false]
        case .aiff24: settings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true]
        case .m4aAAC: settings = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000]
        }
        let file = try AVAudioFile(forWriting: destination, settings: settings)
        try file.write(from: buffer)
    }

    private func sanitize(_ text: String) -> String {
        let safe = text.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
        return safe.isEmpty ? "Track" : safe
    }
}

extension VisionStudioModel {
    func exportMasterLocally() {
        guard !nativeExport.isExporting else { return }
        beginExport(kind: "master")
    }

    func exportStemsLocally() {
        guard !nativeExport.isExporting else { return }
        beginExport(kind: "stems")
    }

    func cancelNativeExport() {
        guard nativeExport.isExporting else { return }
        nativeExport.status = "Cancelling export…"
        nativeExport.exportTask?.cancel()
    }

    private func beginExport(kind: String) {
        let state = exportSnapshot()
        let projectSnapshot = project
        let projectURL = currentProjectURL
        let root = localExportsDirectory()
        let name = safeExportName(project.name)
        nativeExport.isExporting = true
        nativeExport.progress = 0
        nativeExport.phase = "Preparing"
        nativeExport.status = kind == "master" ? "Preparing master export…" : "Preparing stems export…"

        nativeExport.exportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let progressHandler: VisionNativeProjectRenderer.ProgressHandler = { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.nativeExport.progress = update.fraction
                    self.nativeExport.phase = update.phase
                    self.nativeExport.currentTrack = update.trackName
                    self.nativeExport.trackIndex = update.trackIndex
                    self.nativeExport.totalTracks = update.totalTracks
                    self.nativeExport.completedFrames = update.completedFrames
                    self.nativeExport.totalFrames = update.totalFrames
                    self.nativeExport.status = update.trackName.isEmpty ? update.phase : "\(update.phase): \(update.trackName)"
                }
            }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                if kind == "master" {
                    let url = root.appendingPathComponent("\(name)-Master").appendingPathExtension(state.format.fileExtension)
                    try await VisionNativeProjectRenderer.shared.renderMaster(project: projectSnapshot, projectURL: projectURL, state: state, destination: url, progress: progressHandler)
                    self.nativeExport.latestMasterURL = url
                    self.nativeExport.status = "Master exported: \(url.lastPathComponent)"
                } else {
                    let directory = root.appendingPathComponent("\(name)-Stems", isDirectory: true)
                    try? FileManager.default.removeItem(at: directory)
                    let files = try await VisionNativeProjectRenderer.shared.renderStems(project: projectSnapshot, projectURL: projectURL, state: state, directory: directory, progress: progressHandler)
                    self.nativeExport.latestStemsDirectory = directory
                    self.nativeExport.status = "Exported \(files.count) stem/return file(s)"
                }
                self.nativeExport.progress = 1
                self.statusMessage = self.nativeExport.status
            } catch is CancellationError {
                self.nativeExport.status = "Export cancelled cleanly."
                self.statusMessage = self.nativeExport.status
            } catch {
                self.nativeExport.status = "Export failed: \(error.localizedDescription)"
                self.statusMessage = self.nativeExport.status
            }
            self.nativeExport.isExporting = false
            self.nativeExport.exportTask = nil
        }
    }

    private func exportSnapshot() -> VisionNativeExportStateSnapshot {
        VisionNativeExportStateSnapshot(
            format: nativeExport.format,
            sampleRate: nativeExport.sampleRate,
            normalize: nativeExport.normalize,
            startBeat: nativeExport.startBeat,
            endBeat: max(nativeExport.startBeat + 0.25, nativeExport.endBeat),
            tailSeconds: nativeExport.tailSeconds,
            stemMode: nativeExport.stemMode,
            returnMode: nativeExport.returnMode,
            liveFX: audioEngine.snapshotLiveFX()
        )
    }

    private func localExportsDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("LemmingsStudio Exports", isDirectory: true)
    }

    private func safeExportName(_ value: String) -> String {
        let safe = value.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
        return safe.isEmpty ? "Untitled" : safe
    }
}
