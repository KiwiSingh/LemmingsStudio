import AVFoundation
import Foundation
import Darwin

fileprivate enum VisionStockTimbre: Int, Sendable {
    case oscillatron
    case lemmingBass
    case glassLemming
    case cloudPad
    case pluckNest
}

fileprivate final class VisionVoiceBank: @unchecked Sendable {
    struct Voice { var phase: Double; var frequency: Double; var amplitude: Double; var target: Double; var timbre: VisionStockTimbre }
    struct DrumHit { var note: UInt8; var age: Double; var level: Double; var pan: Double; var phase: Double; var rng: UInt64 }
    struct ClickHit { var age: Double; var accent: Bool }

    private let lock = NSLock()
    private var voices: [UInt8: Voice] = [:]
    private var drums: [DrumHit] = []
    private var clicks: [ClickHit] = []
    private var metronomeEnabled = false
    private var metronomeTempo = 124.0
    private var metronomeBeatsPerBar = 4
    private var metronomeBeatPosition = 0.0
    private var nextMetronomeBeatIndex = 0

    func noteOn(_ note: UInt8, velocity: UInt8, timbre: VisionStockTimbre) {
        let f = 440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
        lock.lock()
        voices[note] = Voice(
            phase: 0,
            frequency: f,
            amplitude: 0,
            target: Double(velocity) / 127.0 * 0.24,
            timbre: timbre
        )
        lock.unlock()
    }
    func noteOff(_ note: UInt8) { lock.lock(); if var v = voices[note] { v.target = 0; voices[note] = v }; lock.unlock() }
    func allNotesOff() { lock.lock(); for key in voices.keys { voices[key]?.target = 0 }; drums.removeAll(); clicks.removeAll(); lock.unlock() }

    func triggerDrum(note: UInt8, velocity: UInt8, pan: Float) {
        lock.lock()
        drums.append(DrumHit(note: note, age: 0, level: Double(velocity) / 127.0, pan: Double(max(-1, min(1, pan))), phase: 0, rng: UInt64(note) &* 0x9E3779B97F4A7C15))
        if drums.count > 48 { drums.removeFirst(drums.count - 48) }
        lock.unlock()
    }

    func triggerClick(accent: Bool) {
        lock.lock(); clicks.append(ClickHit(age: 0, accent: accent)); lock.unlock()
    }

    func configureMetronome(enabled: Bool, tempo: Double, beatsPerBar: Int, fromBeat: Double) {
        lock.lock()
        metronomeEnabled = enabled
        metronomeTempo = max(20, tempo)
        metronomeBeatsPerBar = max(1, beatsPerBar)
        metronomeBeatPosition = max(0, fromBeat)
        nextMetronomeBeatIndex = Int(ceil(metronomeBeatPosition - 0.000_001))
        if !enabled { clicks.removeAll() }
        lock.unlock()
    }

    @inline(__always) private func nextNoise(_ state: inout UInt64) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double(state >> 33) / Double((UInt64(1) << 31) - 1)
        return unit * 2.0 - 1.0
    }

    private func drumSample(_ hit: inout DrumHit, sampleRate: Double) -> Double {
        let t = hit.age
        let dt = 1.0 / sampleRate
        let noise = nextNoise(&hit.rng)
        var sample = 0.0
        switch Int(hit.note) {
        case 36: // macOS DrumVoiceID.kick
            let f = 52.0 * (1.0 + 6.0 * exp(-t / 0.012))
            hit.phase += 2.0 * .pi * f * dt
            sample = sin(hit.phase) * exp(-t / 0.16) + noise * exp(-t / 0.004) * 0.6
        case 35: // 808 Sub
            let f = 44.0 * (1.0 + 2.0 * exp(-t / 0.03))
            hit.phase += 2.0 * .pi * f * dt
            sample = tanh(sin(hit.phase) * exp(-t / 0.5) * 1.6)
        case 38: // Snare
            sample = sin(2.0 * .pi * 190.0 * t) * exp(-t / 0.09) * 0.5 + noise * exp(-t / 0.12) * 0.7
        case 39: // Clap
            var burst = 0.0
            for offset in [0.0, 0.009, 0.018] where t >= offset { burst += noise * exp(-(t - offset) / 0.012) }
            sample = (burst + noise * exp(-t / 0.12) * 0.5) * 0.6
        case 37: // Rim
            sample = (sin(2.0 * .pi * 1700.0 * t) + noise * 0.5) * exp(-t / 0.012)
        case 42: // Closed Hat
            sample = noise * exp(-t / 0.025)
        case 46: // Open Hat
            sample = noise * exp(-t / 0.35)
        case 45: // Tom
            let f = 120.0 * (1.0 + 1.5 * exp(-t / 0.04))
            hit.phase += 2.0 * .pi * f * dt
            sample = sin(hit.phase) * exp(-t / 0.22)
        case 51: // Ride
            sample = ([1.0, 1.34, 1.71, 2.4].reduce(0.0) { $0 + sin(2.0 * .pi * 520.0 * $1 * t) } * 0.25 + noise * 0.3) * exp(-t / 0.5)
        case 49: // Crash
            sample = noise * exp(-t / 0.65)
        default:
            let f = 440.0 * pow(2.0, (Double(hit.note) - 69.0) / 12.0)
            hit.phase += 2.0 * .pi * f * dt
            sample = sin(hit.phase) * exp(-t / 0.12)
        }
        hit.age += dt
        return tanh(sample * 1.25) * hit.level * 0.72
    }

    private func isDrumFinished(_ hit: DrumHit) -> Bool {
        switch Int(hit.note) {
        case 42: return hit.age > 0.12
        case 46: return hit.age > 0.42
        case 49: return hit.age > 0.72
        case 51: return hit.age > 0.60
        case 35: return hit.age > 1.0
        default: return hit.age > 0.45
        }
    }

    func render(frames: Int, sampleRate: Double, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        lock.lock(); defer { lock.unlock() }
        for frame in 0..<frames {
            if metronomeEnabled {
                while metronomeBeatPosition + 0.000_000_1 >= Double(nextMetronomeBeatIndex) {
                    let accent = nextMetronomeBeatIndex % metronomeBeatsPerBar == 0
                    clicks.append(ClickHit(age: 0, accent: accent))
                    nextMetronomeBeatIndex += 1
                }
                metronomeBeatPosition += (metronomeTempo / 60.0) / sampleRate
            }
            var l = 0.0, r = 0.0
            for key in Array(voices.keys) {
                guard var voice = voices[key] else { continue }
                voice.amplitude += (voice.target - voice.amplitude) * (voice.target == 0 ? 0.006 : 0.012)
                let fundamental = sin(voice.phase * .pi * 2)
                let harmonic2 = sin(voice.phase * .pi * 4)
                let harmonic3 = sin(voice.phase * .pi * 6)
                let sawish = (2.0 * voice.phase) - 1.0
                let squareish = fundamental >= 0 ? 1.0 : -1.0
                let tone: Double
                switch voice.timbre {
                case .oscillatron:
                    tone = 0.68 * fundamental + 0.20 * harmonic2 + 0.12 * harmonic3
                case .lemmingBass:
                    tone = tanh((0.82 * fundamental + 0.18 * harmonic2) * 1.6) * 0.86
                case .glassLemming:
                    tone = 0.56 * fundamental + 0.24 * harmonic3 + 0.20 * sin(voice.phase * .pi * 10)
                case .cloudPad:
                    tone = 0.58 * fundamental + 0.20 * sin((voice.phase + 0.006) * .pi * 2) + 0.14 * harmonic2 + 0.08 * harmonic3
                case .pluckNest:
                    let brightness = max(0.18, min(1.0, voice.amplitude * 6.0))
                    tone = (0.44 * sawish + 0.36 * fundamental + 0.20 * squareish) * brightness
                }
                let s = tone * voice.amplitude
                l += s; r += s
                voice.phase += voice.frequency / sampleRate
                if voice.phase >= 1 { voice.phase -= 1 }
                if voice.target == 0 && voice.amplitude < 0.00005 { voices.removeValue(forKey: key) } else { voices[key] = voice }
            }
            for i in drums.indices.reversed() {
                var hit = drums[i]
                let s = drumSample(&hit, sampleRate: sampleRate)
                let lg = sqrt((1.0 - hit.pan) * 0.5), rg = sqrt((1.0 + hit.pan) * 0.5)
                l += s * lg; r += s * rg
                drums[i] = hit
                if isDrumFinished(hit) { drums.remove(at: i) }
            }
            for i in clicks.indices.reversed() {
                var click = clicks[i]
                let freq = click.accent ? 1760.0 : 1320.0
                let amp = exp(-click.age / 0.025) * (click.accent ? 0.36 : 0.24)
                let s = sin(2.0 * .pi * freq * click.age) * amp
                l += s; r += s
                click.age += 1.0 / sampleRate
                clicks[i] = click
                if click.age > 0.09 { clicks.remove(at: i) }
            }
            left[frame] = Float(max(-0.95, min(0.95, l)))
            right[frame] = Float(max(-0.95, min(0.95, r)))
        }
    }

    func renderMono(frames: Int, sampleRate: Double, output: UnsafeMutablePointer<Float>) {
        render(frames: frames, sampleRate: sampleRate, left: output, right: output)
    }
}

fileprivate final class VisionMeterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    private var rms: Float = 0
    func update(peak: Float, rms: Float) { lock.lock(); self.peak = max(self.peak * 0.92, peak); self.rms = rms; lock.unlock() }
    func snapshot() -> (Float, Float) { lock.lock(); defer { lock.unlock() }; return (peak, rms) }
}

@MainActor
final class VisionAudioEngine {
    enum InstrumentKind: String, CaseIterable, Identifiable {
        case oscillatron = "Oscillatron"
        case lemmingBass = "LemmingBass"
        case glassLemming = "Glass Lemming"
        case cloudPad = "Cloud Pad"
        case pluckNest = "Pluck Nest"

        var id: String { rawValue }

        fileprivate var timbre: VisionStockTimbre {
            switch self {
            case .oscillatron: return .oscillatron
            case .lemmingBass: return .lemmingBass
            case .glassLemming: return .glassLemming
            case .cloudPad: return .cloudPad
            case .pluckNest: return .pluckNest
            }
        }
    }



    private let engine = AVAudioEngine()
    private let bank: VisionVoiceBank
    private let source: AVAudioSourceNode
    private let stockFilter = AVAudioUnitEQ(numberOfBands: 1)
    private let stockCrusher = AVAudioUnitDistortion()
    private let stockDrive = AVAudioUnitDistortion()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()
    private let synthMixer = AVAudioMixerNode()
    private let returnAMixer = AVAudioMixerNode()
    private let returnBMixer = AVAudioMixerNode()
    private let returnADelay = AVAudioUnitDelay()
    private let returnBReverb = AVAudioUnitReverb()
    private var projectTrackMixers: [Int: AVAudioMixerNode] = [:]
    private var projectSendAMixers: [Int: AVAudioMixerNode] = [:]
    private var projectSendBMixers: [Int: AVAudioMixerNode] = [:]
    private var projectTrackFilters: [Int: AVAudioUnitEQ] = [:]
    private var projectTrackCrushers: [Int: AVAudioUnitDistortion] = [:]
    private var projectTrackDrives: [Int: AVAudioUnitDistortion] = [:]
    private var projectTrackDelays: [Int: AVAudioUnitDelay] = [:]
    private var projectTrackReverbs: [Int: AVAudioUnitReverb] = [:]
    private var projectTrackVoiceBanks: [Int: VisionVoiceBank] = [:]
    private var projectTrackSources: [Int: AVAudioSourceNode] = [:]
    private var meterBoxes: [String: VisionMeterBox] = [:]
    private var instrument: InstrumentKind = .oscillatron
    private var clipPlayers: [AVAudioPlayerNode] = []
    private var clipRateNodes: [AVAudioUnitVarispeed] = []
    private var oneShotPlayers: [AVAudioPlayerNode] = []
    private var hostedAudioUnit: AVAudioUnit?
    private var hostedAudioUnitKind: VisionAudioUnitKind?


    private(set) var isRunning = false
    private var graphConfigured = false

    init() {
        let voiceBank = VisionVoiceBank()
        self.bank = voiceBank
        source = Self.makeSourceNode(voiceBank: voiceBank)
        configureEffects()
    }

    /// Build the real-time render closure from a nonisolated context so Swift 6 does not
    /// attach MainActor executor checks to the callback that AVFAudio invokes on AURemoteIO.
    nonisolated private static func makeSourceNode(voiceBank: VisionVoiceBank) -> AVAudioSourceNode {
        AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard !buffers.isEmpty,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            if buffers.count >= 2,
               let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                voiceBank.render(frames: Int(frameCount), sampleRate: 48_000, left: left, right: right)
            } else {
                // Mono routes are uncommon, but avoid actor hops and heap allocation in the
                // real-time callback by rendering into the available channel twice in place.
                voiceBank.renderMono(frames: Int(frameCount), sampleRate: 48_000, output: left)
            }
            return noErr
        }
    }

    private func configureEffects() {
        stockFilter.bands[0].filterType = .lowPass
        stockFilter.bands[0].frequency = 18_000
        stockFilter.bands[0].bandwidth = 2.5
        stockFilter.bands[0].bypass = false
        stockCrusher.loadFactoryPreset(.multiDecimated3)
        stockCrusher.preGain = -8
        stockCrusher.wetDryMix = 0
        stockDrive.loadFactoryPreset(.multiDistortedSquared)
        stockDrive.preGain = 0
        stockDrive.wetDryMix = 0
        eq.bands[0].filterType = .lowShelf; eq.bands[0].frequency = 120; eq.bands[0].gain = 0; eq.bands[0].bypass = false
        eq.bands[1].filterType = .parametric; eq.bands[1].frequency = 1_200; eq.bands[1].bandwidth = 1; eq.bands[1].gain = 0; eq.bands[1].bypass = false
        eq.bands[2].filterType = .highShelf; eq.bands[2].frequency = 8_000; eq.bands[2].gain = 0; eq.bands[2].bypass = false
        delay.delayTime = 0.24; delay.feedback = 18; delay.wetDryMix = 0
        reverb.loadFactoryPreset(.mediumHall); reverb.wetDryMix = 0
        returnADelay.delayTime = 0.28; returnADelay.feedback = 24; returnADelay.wetDryMix = 100
        returnBReverb.loadFactoryPreset(.largeHall); returnBReverb.wetDryMix = 100
    }

    func start() throws {
        guard !isRunning else { return }

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        guard outputFormat.channelCount > 0, outputFormat.sampleRate > 0 else {
            throw NSError(
                domain: "LemmingsStudio.VisionAudioEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No usable simulator or device audio output route is available yet."]
            )
        }

        if !graphConfigured {
            engine.attach(source)
            engine.attach(synthMixer)
            engine.attach(stockFilter)
            engine.attach(stockCrusher)
            engine.attach(stockDrive)
            engine.attach(eq)
            engine.attach(delay)
            engine.attach(reverb)
            engine.attach(returnAMixer)
            engine.attach(returnBMixer)
            engine.attach(returnADelay)
            engine.attach(returnBReverb)

            engine.connect(source, to: synthMixer, format: nil)
            engine.connect(synthMixer, to: stockFilter, format: nil)
            engine.connect(stockFilter, to: stockCrusher, format: nil)
            engine.connect(stockCrusher, to: stockDrive, format: nil)
            engine.connect(stockDrive, to: eq, format: nil)
            engine.connect(eq, to: delay, format: nil)
            engine.connect(delay, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)
            engine.connect(returnAMixer, to: returnADelay, format: nil)
            engine.connect(returnADelay, to: engine.mainMixerNode, format: nil)
            engine.connect(returnBMixer, to: returnBReverb, format: nil)
            engine.connect(returnBReverb, to: engine.mainMixerNode, format: nil)
            installMeter(on: engine.mainMixerNode, key: "master")
            installMeter(on: returnAMixer, key: "return-a")
            installMeter(on: returnBMixer, key: "return-b")
            graphConfigured = true
        }

        try engine.start()
        isRunning = true
    }

    func stop() {
        bank.allNotesOff()
        stopProjectAudio()
        engine.stop()
        isRunning = false
    }

    private func installMeter(on node: AVAudioMixerNode, key: String) {
        let box = meterBoxes[key] ?? VisionMeterBox()
        meterBoxes[key] = box
        node.installTap(
            onBus: 0,
            bufferSize: 512,
            format: nil,
            block: Self.makeMeterTapBlock(box: box)
        )
    }

    /// Construct meter callbacks outside MainActor isolation. AVFAudio invokes tap blocks on
    /// its RealtimeMessenger service queue, not the main actor executor.
    nonisolated private static func makeMeterTapBlock(box: VisionMeterBox) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let count = Int(buffer.format.channelCount)
            guard frames > 0, count > 0 else { return }

            var peak: Float = 0
            var sum: Float = 0
            for channel in 0..<count {
                let samples = channels[channel]
                for frame in 0..<frames {
                    let value = abs(samples[frame])
                    peak = max(peak, value)
                    sum += value * value
                }
            }
            box.update(peak: peak, rms: sqrt(sum / Float(frames * count)))
        }
    }

    func stopProjectAudio() {
        for player in clipPlayers {
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.detach(player)
        }
        clipPlayers.removeAll()
        for node in clipRateNodes {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        clipRateNodes.removeAll()
        for (index, mixer) in projectTrackMixers {
            mixer.removeTap(onBus: 0)
            engine.disconnectNodeOutput(mixer)
            engine.detach(mixer)
            meterBoxes.removeValue(forKey: "track-\(index)")
        }
        projectTrackMixers.removeAll()
        for node in projectTrackFilters.values { engine.disconnectNodeOutput(node); engine.detach(node) }
        for node in projectTrackCrushers.values { engine.disconnectNodeOutput(node); engine.detach(node) }
        for node in projectTrackDrives.values { engine.disconnectNodeOutput(node); engine.detach(node) }
        for node in projectTrackDelays.values { engine.disconnectNodeOutput(node); engine.detach(node) }
        for node in projectTrackReverbs.values { engine.disconnectNodeOutput(node); engine.detach(node) }
        projectTrackFilters.removeAll()
        projectTrackCrushers.removeAll()
        projectTrackDrives.removeAll()
        projectTrackDelays.removeAll()
        projectTrackReverbs.removeAll()
        for source in projectTrackSources.values { engine.disconnectNodeOutput(source); engine.detach(source) }
        projectTrackSources.removeAll()
        projectTrackVoiceBanks.removeAll()
        for mixer in projectSendAMixers.values { engine.disconnectNodeOutput(mixer); engine.detach(mixer) }
        for mixer in projectSendBMixers.values { engine.disconnectNodeOutput(mixer); engine.detach(mixer) }
        projectSendAMixers.removeAll()
        projectSendBMixers.removeAll()
    }

    func scheduleProjectAudio(project: LemmingsProject, projectURL: URL?, fromBeat: Double) {
        stopProjectAudio()
        let tempo = max(20, project.effectiveTempo)
        let secondsPerBeat = 60.0 / tempo
        let projectFolder = VisionProjectPersistence.packageBaseURL(for: projectURL)

        let hasSolo = project.tracks.contains { $0.solo == true }
        configureReturns(project.returnBuses ?? VisionReturnBus.defaults)
        setMasterVolume((project.masterMuted == true) ? 0 : (project.masterVolume ?? 1))

        for (trackIndex, track) in project.tracks.enumerated() where track.mute != true && (!hasSolo || track.solo == true) {
            let trackMixer = AVAudioMixerNode()
            engine.attach(trackMixer)
            trackMixer.outputVolume = track.volume ?? 1
            trackMixer.pan = track.pan ?? 0
            projectTrackMixers[trackIndex] = trackMixer
            installMeter(on: trackMixer, key: "track-\(trackIndex)")

            let trackVoiceBank = VisionVoiceBank()
            let trackSource = Self.makeSourceNode(voiceBank: trackVoiceBank)
            projectTrackVoiceBanks[trackIndex] = trackVoiceBank
            projectTrackSources[trackIndex] = trackSource
            engine.attach(trackSource)
            engine.connect(trackSource, to: trackMixer, format: nil)

            let output = track.outputBusId ?? "master"
            let sends = track.sends ?? [:]
            let sendA = AVAudioMixerNode()
            let sendB = AVAudioMixerNode()
            engine.attach(sendA); engine.attach(sendB)
            sendA.outputVolume = sends["return-a"] ?? 0
            sendB.outputVolume = sends["return-b"] ?? 0
            projectSendAMixers[trackIndex] = sendA
            projectSendBMixers[trackIndex] = sendB
            // Every project track owns deterministic mixer input buses. Reusing bus 0
            // across multiple tracks creates an invalid AVAudioEngine graph and AVFAudio
            // aborts while preparing the connection instead of returning a Swift error.
            let sendBus = AVAudioNodeBus(trackIndex * 2)
            let directReturnBus = AVAudioNodeBus(trackIndex * 2 + 1)
            let masterBus = AVAudioNodeBus(trackIndex + 1) // bus 0 is the live keyboard source

            engine.connect(sendA, to: returnAMixer, fromBus: 0, toBus: sendBus, format: nil)
            engine.connect(sendB, to: returnBMixer, fromBus: 0, toBus: sendBus, format: nil)

            var points: [AVAudioConnectionPoint] = [
                AVAudioConnectionPoint(node: sendA, bus: 0),
                AVAudioConnectionPoint(node: sendB, bus: 0)
            ]
            if output == "return-a" {
                points.append(AVAudioConnectionPoint(node: returnAMixer, bus: directReturnBus))
            } else if output == "return-b" {
                points.append(AVAudioConnectionPoint(node: returnBMixer, bus: directReturnBus))
            } else {
                points.append(AVAudioConnectionPoint(node: synthMixer, bus: masterBus))
            }
            let filter = AVAudioUnitEQ(numberOfBands: 1)
            filter.bands[0].filterType = .lowPass
            filter.bands[0].frequency = 18_000
            filter.bands[0].bandwidth = 2.5
            filter.bands[0].bypass = false
            let crusher = AVAudioUnitDistortion()
            crusher.loadFactoryPreset(.multiDecimated3)
            crusher.preGain = -8
            crusher.wetDryMix = 0
            let drive = AVAudioUnitDistortion()
            drive.loadFactoryPreset(.multiDistortedSquared)
            drive.preGain = 0
            drive.wetDryMix = 0
            let trackDelay = AVAudioUnitDelay()
            trackDelay.delayTime = 0.24
            trackDelay.feedback = 18
            trackDelay.wetDryMix = 0
            let trackReverb = AVAudioUnitReverb()
            trackReverb.loadFactoryPreset(.mediumHall)
            trackReverb.wetDryMix = 10

            [filter, crusher, drive, trackDelay, trackReverb].forEach { engine.attach($0) }
            projectTrackFilters[trackIndex] = filter
            projectTrackCrushers[trackIndex] = crusher
            projectTrackDrives[trackIndex] = drive
            projectTrackDelays[trackIndex] = trackDelay
            projectTrackReverbs[trackIndex] = trackReverb

            engine.connect(trackMixer, to: filter, format: nil)
            engine.connect(filter, to: crusher, format: nil)
            engine.connect(crusher, to: drive, format: nil)
            engine.connect(drive, to: trackDelay, format: nil)
            engine.connect(trackDelay, to: trackReverb, format: nil)
            engine.connect(trackReverb, to: points, fromBus: 0, format: nil)

            let rack = track.stockFXRack ?? .defaults
            for parameter in VisionStockFXParameterRegistry.all {
                setTrackStockFXParameter(
                    trackIndex: trackIndex,
                    effect: parameter.effect,
                    parameterID: parameter.parameterID,
                    normalizedValue: rack.value(effect: parameter.effect, parameterID: parameter.parameterID)
                )
            }

            for clip in track.audioClips {
                guard let sourcePath = clip.sourcePath, !sourcePath.isEmpty else { continue }
                let url: URL
                if sourcePath.hasPrefix("/") {
                    url = URL(fileURLWithPath: sourcePath)
                } else if let projectFolder {
                    url = projectFolder.appendingPathComponent(sourcePath)
                } else {
                    url = URL(fileURLWithPath: sourcePath)
                }
                guard FileManager.default.fileExists(atPath: url.path), let file = try? AVAudioFile(forReading: url) else { continue }

                let clipEnd = clip.startBeat + clip.lengthBeats
                guard clipEnd > fromBeat else { continue }
                let player = AVAudioPlayerNode()
                player.volume = 1
                player.pan = 0
                engine.attach(player)
                let rate = Float(max(0.25, min(4.0, clip.playbackRate ?? 1)))
                if clip.autoStretchEnabled == true, abs(rate - 1) > 0.001 {
                    let varispeed = AVAudioUnitVarispeed()
                    varispeed.rate = rate
                    engine.attach(varispeed)
                    engine.connect(player, to: varispeed, format: file.processingFormat)
                    engine.connect(varispeed, to: trackMixer, format: file.processingFormat)
                    clipRateNodes.append(varispeed)
                } else {
                    engine.connect(player, to: trackMixer, format: file.processingFormat)
                }

                let skippedTimelineBeats = max(0, fromBeat - clip.startBeat)
                let sourceBeatOffset = (clip.sourceOffsetBeats ?? 0) + skippedTimelineBeats
                let startFrame = AVAudioFramePosition(sourceBeatOffset * secondsPerBeat * file.processingFormat.sampleRate)
                let availableFrames = max(0, file.length - startFrame)
                let desiredFrames = AVAudioFrameCount(max(0, min(Double(availableFrames), (clip.lengthBeats - skippedTimelineBeats) * secondsPerBeat * file.processingFormat.sampleRate)))
                guard desiredFrames > 0 else { engine.detach(player); continue }

                let delaySeconds = max(0, clip.startBeat - fromBeat) * secondsPerBeat
                let hostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delaySeconds)
                player.scheduleSegment(file, startingFrame: startFrame, frameCount: desiredFrames, at: nil)
                player.play(at: AVAudioTime(hostTime: hostTime))
                clipPlayers.append(player)
            }
        }
    }
    func hostAudioUnit(_ unit: AVAudioUnit, kind: VisionAudioUnitKind) throws {
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        unhostAudioUnit(restart: false)

        engine.attach(unit)
        switch kind {
        case .instrument, .generator:
            engine.connect(unit, to: synthMixer, format: nil)
        case .effect, .other:
            engine.disconnectNodeOutput(synthMixer)
            engine.connect(synthMixer, to: unit, format: nil)
            engine.connect(unit, to: stockFilter, format: nil)
        }
        hostedAudioUnit = unit
        hostedAudioUnitKind = kind
        if wasRunning { try engine.start() }
    }

    func unhostAudioUnit() { unhostAudioUnit(restart: true) }

    private func unhostAudioUnit(restart: Bool) {
        guard let unit = hostedAudioUnit else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }
        engine.disconnectNodeOutput(unit)
        engine.disconnectNodeInput(unit)
        if hostedAudioUnitKind == .effect || hostedAudioUnitKind == .other {
            engine.disconnectNodeOutput(synthMixer)
            engine.connect(synthMixer, to: stockFilter, format: nil)
        }
        engine.detach(unit)
        hostedAudioUnit = nil
        hostedAudioUnitKind = nil
        if restart && wasRunning { try? engine.start() }
    }


    func playOneShotSample(path: String, projectURL: URL?, volume: Float, pan: Float) {
        let url: URL
        if path.hasPrefix("/") { url = URL(fileURLWithPath: path) }
        else if let projectURL { url = VisionProjectPersistence.resolveAssetPath(path, projectURL: projectURL) }
        else { url = URL(fileURLWithPath: path) }
        guard FileManager.default.fileExists(atPath: url.path), let file = try? AVAudioFile(forReading: url) else { return }
        let player = AVAudioPlayerNode()
        player.volume = max(0, min(1.5, volume))
        player.pan = max(-1, min(1, pan))
        engine.attach(player)
        engine.connect(player, to: synthMixer, format: file.processingFormat)
        player.scheduleFile(file, at: nil) { [weak self, weak player] in
            Task { @MainActor in
                guard let self, let player else { return }
                player.stop()
                self.engine.disconnectNodeOutput(player)
                self.engine.detach(player)
                self.oneShotPlayers.removeAll { $0 === player }
            }
        }
        oneShotPlayers.append(player)
        player.play()
    }

    func setInstrument(_ kind: InstrumentKind) { instrument = kind }
    func triggerSequencerVoice(note: UInt8, velocity: UInt8, pan: Float = 0) { bank.triggerDrum(note: note, velocity: velocity, pan: pan) }
    func triggerMetronome(accent: Bool) { bank.triggerClick(accent: accent) }
    func configureMetronome(enabled: Bool, tempo: Double, beatsPerBar: Int, fromBeat: Double) {
        bank.configureMetronome(enabled: enabled, tempo: tempo, beatsPerBar: beatsPerBar, fromBeat: fromBeat)
    }
    func noteOn(note: UInt8, velocity: UInt8) { bank.noteOn(note, velocity: velocity, timbre: instrument.timbre) }
    func noteOff(note: UInt8) { bank.noteOff(note) }
    func noteOn(trackIndex: Int, note: UInt8, velocity: UInt8) {
        (projectTrackVoiceBanks[trackIndex] ?? bank).noteOn(note, velocity: velocity, timbre: instrument.timbre)
    }
    func noteOff(trackIndex: Int, note: UInt8) {
        (projectTrackVoiceBanks[trackIndex] ?? bank).noteOff(note)
    }
    func panic() {
        bank.allNotesOff()
        for voiceBank in projectTrackVoiceBanks.values { voiceBank.allNotesOff() }
    }

    func setTrackStockFXParameter(trackIndex: Int, effect: VisionStockFXKind, parameterID: String, normalizedValue: Float) {
        let value = max(0, min(1, normalizedValue))
        switch (effect, parameterID) {
        case (.lemmingsFilter, "cutoff"):
            let minHz: Float = 30
            let maxHz: Float = 18_000
            projectTrackFilters[trackIndex]?.bands[0].frequency = minHz * pow(maxHz / minHz, value)
        case (.lemmingsFilter, "resonance"):
            projectTrackFilters[trackIndex]?.bands[0].bandwidth = max(0.05, 4.0 - value * 3.95)
        case (.lemmingCrusher, "crush"):
            projectTrackCrushers[trackIndex]?.preGain = -12 + value * 36
        case (.lemmingCrusher, "mix"):
            projectTrackCrushers[trackIndex]?.wetDryMix = value * 100
        case (.burrowDelay, "time"):
            projectTrackDelays[trackIndex]?.delayTime = 0.03 + Double(value) * 1.17
        case (.burrowDelay, "feedback"):
            projectTrackDelays[trackIndex]?.feedback = value * 90
        case (.burrowDelay, "mix"):
            projectTrackDelays[trackIndex]?.wetDryMix = value * 100
        case (.lemmingVerb, "mix"):
            projectTrackReverbs[trackIndex]?.wetDryMix = value * 100
        case (.lemmingDrive, "drive"):
            projectTrackDrives[trackIndex]?.preGain = value * 24
        case (.lemmingDrive, "mix"):
            projectTrackDrives[trackIndex]?.wetDryMix = value * 100
        default:
            break
        }
    }

    func setLowGain(_ db: Float) { eq.bands[0].gain = max(-24, min(24, db)) }
    func setMidGain(_ db: Float) { eq.bands[1].gain = max(-24, min(24, db)) }
    func setHighGain(_ db: Float) { eq.bands[2].gain = max(-24, min(24, db)) }
    func setDelayMix(_ value: Float) { delay.wetDryMix = max(0, min(100, value)) }
    func setReverbMix(_ value: Float) { reverb.wetDryMix = max(0, min(100, value)) }
    func setMasterVolume(_ value: Float) { engine.mainMixerNode.outputVolume = max(0, min(1.5, value)) }

    func snapshotLiveFX() -> VisionLiveFXSnapshot {
        VisionLiveFXSnapshot(
            lowGain: eq.bands[0].gain,
            midGain: eq.bands[1].gain,
            highGain: eq.bands[2].gain,
            delayTime: delay.delayTime,
            delayFeedback: delay.feedback,
            delayMix: delay.wetDryMix,
            reverbMix: reverb.wetDryMix
        )
    }

    func configureReturns(_ buses: [VisionReturnBus]) {
        let a = buses.first(where: { $0.id == "return-a" }) ?? VisionReturnBus.defaults[0]
        let b = buses.first(where: { $0.id == "return-b" }) ?? VisionReturnBus.defaults[1]
        returnAMixer.outputVolume = a.mute ? 0 : a.volume
        returnAMixer.pan = a.pan
        returnBMixer.outputVolume = b.mute ? 0 : b.volume
        returnBMixer.pan = b.pan
        returnADelay.wetDryMix = a.effectMix ?? 100
        returnBReverb.wetDryMix = b.effectMix ?? 100
    }

    func updateTrackMixer(index: Int, volume: Float, pan: Float, muted: Bool) {
        guard let mixer = projectTrackMixers[index] else { return }
        mixer.outputVolume = muted ? 0 : volume
        mixer.pan = pan
    }

    func updateTrackSend(index: Int, busID: String, value: Float) {
        if busID == "return-a" { projectSendAMixers[index]?.outputVolume = value }
        if busID == "return-b" { projectSendBMixers[index]?.outputVolume = value }
    }

    func meterSnapshot(key: String) -> (peak: Float, rms: Float) {
        let v = meterBoxes[key]?.snapshot() ?? (0, 0)
        return (v.0, v.1)
    }

    var inputNode: AVAudioInputNode { engine.inputNode }
    var avEngine: AVAudioEngine { engine }
}
