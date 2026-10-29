import Foundation
import AVFoundation
import Darwin

// MARK: - Transport

public enum PlaybackScope: Equatable {
    /// Arrangement/session style playback: Arrangement MIDI/audio clips render, live Step Sequencer grids stay muted.
    case arrangement
    /// Step Sequencer focus: only live step-sequencer lanes render; Arrangement clips/audio stay muted.
    case stepSequencer
    /// Piano Roll focus: Arrangement clips render so edited notes are audible; live step grids stay muted to avoid doubling.
    case pianoRoll
    /// Legacy/unrestricted rendering. Kept for future preview tools, but normal UI tabs set a narrower scope.
    case all
}


public final class Transport {
    public var isPlaying = false
    public var tempo: Double = 124
    public var beatsPerBar = 4
    /// Sample time captured on the first playing render block. -1 == not anchored.
    /// NOTE: this is read/written from audio render threads. For a production
    /// build move this to a lock-free atomic; the benign first-buffer race here
    /// only affects sub-millisecond start alignment.
    public var anchorSampleTime: Double = -1
    public var sampleRate: Double = 44100
    /// Timeline position used when stopped, and as the offset when playback starts.
    public var playStartBeat: Double = 0
    /// Optional tempo automation. When set, beat↔time uses the curve, not `tempo`.
    public var tempoMap: TempoMap? = nil
    /// Wall-clock fallback used for UI/MIDI overdub timing before CoreAudio has
    /// produced a fresh render timestamp. This keeps recording from stacking all
    /// incoming notes at beat 0 when the user starts recording and immediately
    /// plays a controller.
    public var wallClockStartTime: TimeInterval = 0

    public func play()  {
        anchorSampleTime = -1
        wallClockStartTime = Date.timeIntervalSinceReferenceDate
        isPlaying = true
    }
    public func stop(at beat: Double? = nil)  {
        if let beat { playStartBeat = max(0, beat) }
        isPlaying = false
        anchorSampleTime = -1
        wallClockStartTime = 0
    }
    public func setBeat(_ beat: Double) {
        playStartBeat = max(0, beat)
        if isPlaying {
            anchorSampleTime = -1
            wallClockStartTime = Date.timeIntervalSinceReferenceDate
        }
    }

    @inline(__always)
    public func beat(at sampleTime: Double) -> Double {
        guard anchorSampleTime >= 0 else { return wallClockBeat() }
        let seconds = (sampleTime - anchorSampleTime) / sampleRate
        if let map = tempoMap { return playStartBeat + map.beat(atSeconds: seconds) }
        return playStartBeat + seconds * tempo / 60.0
    }

    public func wallClockBeat() -> Double {
        guard isPlaying, wallClockStartTime > 0 else { return playStartBeat }
        let seconds = max(0, Date.timeIntervalSinceReferenceDate - wallClockStartTime)
        if let map = tempoMap { return playStartBeat + map.beat(atSeconds: seconds) }
        return playStartBeat + seconds * tempo / 60.0
    }
}

// MARK: - Per-track render state

final class TrackRenderState {
    let track: Track
    let instrument: Instrument
    let scratchL: UnsafeMutablePointer<Float>
    let scratchR: UnsafeMutablePointer<Float>
    let capacity: Int
    var pendingOffs: [(beatEnd: Double, note: Int)] = []
    var lastStepIndex = -1
    var lastStepNotes: [Int] = []
    var meterPeak: Float = 0

    // Device chain + automatable nodes (instrument + effects), keyed by nodeID.
    var effects: [AudioEffect] = []
    var effectMono: [Bool] = []          // engine pre-collapses to mono before these
    var effectModels: [DeviceModel] = []
    var externalEffectSlots: [ExternalPluginSlot] = []
    var externalEffects: [AudioEffect] = []
    var externalFactory: ((ExternalPluginSlot) -> AudioEffect?)? = nil
    var nodes: [String: Automatable] = [:]

    init(track: Track, instrument: Instrument, capacity: Int) {
        self.track = track
        self.instrument = instrument
        self.capacity = capacity
        self.scratchL = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.scratchR = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.scratchL.initialize(repeating: 0, count: capacity)
        self.scratchR.initialize(repeating: 0, count: capacity)
        if let a = instrument as? Automatable { nodes["instrument"] = a }
    }
    deinit { scratchL.deallocate(); scratchR.deallocate() }

    func rebuildEffects(sampleRate: Double) {
        // DeviceModel rows whose kind is a built-in instrument are rack/editor
        // representations for the track source instrument. They must not be
        // instantiated as post-instrument audio effects, or Oscillatron /
        // LemmingBass appear as controls while the real generator is elsewhere.
        let insertModels = track.devices.filter { !$0.kind.isBuiltInTrackInstrument }
        effectModels = insertModels
        effects = insertModels.map { DeviceFactory.make(from: $0, sampleRate: sampleRate) }
        effectMono = insertModels.map { $0.mono }
        externalEffectSlots = track.externalPluginSlots.filter { $0.role != .instrument }
        externalEffects = externalEffectSlots.map { slot in
            if let created = externalFactory?(slot) { return created }
            #if canImport(AVFoundation) && canImport(AudioToolbox)
            if slot.format == .audioUnit, let hosted = HostedAUAudioEffect(pluginName: slot.name, sampleRate: sampleRate, componentDescription: AudioUnitCatalog.description(name:slot.name,path:slot.path,identifier:slot.pluginID)) {
                return hosted
            }
            #endif
            return RackPassThroughEffect(kind: .externalAudioEffect)
        }
        nodes = [:]
        if let automatableInstrument = instrument as? Automatable {
            nodes["instrument"] = automatableInstrument
            for model in track.devices where model.kind.isBuiltInTrackInstrument {
                nodes[model.nodeID] = automatableInstrument
                for (id, value) in model.params { automatableInstrument.setParam(id, value) }
            }
        }
        for (model, fx) in zip(insertModels, effects) { nodes[model.nodeID] = fx }
        for (slot, fx) in zip(externalEffectSlots, externalEffects) { nodes[slot.nodeID] = fx }
    }

    /// Apply all enabled automation lanes at a beat to their target nodes.
    ///
    /// `AutomationSpecialParam.deviceOn` intentionally targets the DeviceModel
    /// itself, not the DSP node parameter list. This gives LemmingsStudio the
    /// Ableton-style Device On/Off automation lane: values >= 0.5 mean ON,
    /// values < 0.5 mean OFF/bypassed. The live AudioEffect mirror is updated
    /// too so the current block follows the lane immediately.
    func applyAutomation(atBeat beat: Double) {
        for lane in track.automationLanes where lane.enabled {
            guard let v = lane.value(atBeat: beat) else { continue }
            if let channel = AutomationSpecialParam.pitchBendChannel(from: lane.paramID) {
                let bend = Float(max(-1.0, min(1.0, v)))
                instrument.pitchBend(
                    bend,
                    channel: channel,
                    rangeSemitones: max(1, track.pitchBendRangeSemitones)
                )
                continue
            }
            if lane.paramID == AutomationSpecialParam.deviceOn {
                let shouldBeOn = v >= 0.5
                if let idx = effectModels.firstIndex(where: { $0.nodeID == lane.nodeID }) {
                    effectModels[idx].bypassed = !shouldBeOn
                    if effects.indices.contains(idx) { effects[idx].bypassed = !shouldBeOn }
                }
                if let live = track.devices.first(where: { $0.nodeID == lane.nodeID }) {
                    live.bypassed = !shouldBeOn
                }
                continue
            }
            guard let node = nodes[lane.nodeID] else { continue }
            node.setParam(lane.paramID, v)
        }
    }
}

final class ReturnRenderState {
    weak var bus: ReturnBus?
    var effects: [AudioEffect] = []
    let busL: UnsafeMutablePointer<Float>
    let busR: UnsafeMutablePointer<Float>
    let scratchL: UnsafeMutablePointer<Float>
    let scratchR: UnsafeMutablePointer<Float>
    let capacity: Int
    var meterPeak: Float = 0

    init(bus: ReturnBus, capacity: Int, sampleRate: Double) {
        self.bus = bus
        self.capacity = capacity
        self.busL = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.busR = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.scratchL = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.scratchR = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        busL.initialize(repeating: 0, count: capacity); busR.initialize(repeating: 0, count: capacity)
        scratchL.initialize(repeating: 0, count: capacity); scratchR.initialize(repeating: 0, count: capacity)
        rebuildEffects(sampleRate: sampleRate)
    }
    deinit { busL.deallocate(); busR.deallocate(); scratchL.deallocate(); scratchR.deallocate() }
    func rebuildEffects(sampleRate: Double) {
        effects = bus?.devices.map { DeviceFactory.make(from: $0, sampleRate: sampleRate) } ?? []
    }
}

// MARK: - Audio engine

private final class ClipPluginRenderState {
    let left:UnsafeMutablePointer<Float>;let right:UnsafeMutablePointer<Float>;let effects:[AudioEffect]
    init(capacity:Int,effects:[AudioEffect]){self.effects=effects;left = .allocate(capacity:capacity);right = .allocate(capacity:capacity);left.initialize(repeating:0,count:capacity);right.initialize(repeating:0,count:capacity)}
    deinit{left.deallocate();right.deallocate()}
}

public final class AudioEngine {
    public let avEngine = AVAudioEngine()
    public let transport = Transport()
    public private(set) var sampleRate: Double = 44100
    private let maxFrames = 4096

    private weak var project: Project?
    private var states: [UUID: TrackRenderState] = [:]
    private var sourceNodes: [UUID: AVAudioSourceNode] = [:]
    private var returnStates: [UUID: ReturnRenderState] = [:]
    private var returnSourceNodes: [UUID: AVAudioSourceNode] = [:]
    private var metronomeNode: AVAudioSourceNode?
    /// Cache hosted AU instruments across graph rebuilds so a Sound Agent patch
    /// written into Serum 2 survives record/count-in/track UI rebuilds.
    #if canImport(AVFoundation) && canImport(AudioToolbox)
    private var clipPluginStates:[UUID:ClipPluginRenderState]=[:]
    private var nativePluginCache: [UUID:NativeHostedPlugin] = [:]
    private var externalAUCache: [UUID:HostedAUAudioEffect] = [:]
    private var hostedAUInstrumentCache: [String: HostedAUInstrument] = [:]
    #endif
    public var metronomeEnabled = true
    public var playbackScope: PlaybackScope = .arrangement
    public var metronomeVolume: Float = 0.55
    private var countInClickStartTime: TimeInterval? = nil
    private var countInClickBeats: Int = 0
    private var countInClickTempo: Double = 124

    public var isCountInClicking: Bool {
        guard let start = countInClickStartTime else { return false }
        let seconds = Double(max(1, countInClickBeats)) * 60.0 / max(20.0, countInClickTempo)
        return Date.timeIntervalSinceReferenceDate - start < seconds
    }

    public func startCountInClick(beats: Int, tempo: Double) {
        countInClickBeats = max(1, beats)
        countInClickTempo = max(20.0, tempo)
        countInClickStartTime = Date.timeIntervalSinceReferenceDate
    }

    public func stopCountInClick() {
        countInClickStartTime = nil
    }
    private var stereoFormat: AVAudioFormat!

    public init() {
        sampleRate = avEngine.outputNode.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 44100 }
        transport.sampleRate = sampleRate
        stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
    }

    public func setSampleRate(_ newSampleRate: Double) {
        let sr = newSampleRate.isFinite && newSampleRate > 0 ? newSampleRate : 44100
        sampleRate = sr
        transport.sampleRate = sr
        stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)
    }

    public func attach(project: Project) {
        if self.project !== project { nativePluginCache.removeAll(); externalAUCache.removeAll(); hostedAUInstrumentCache.removeAll() }
        self.project = project
        transport.tempo = project.tempo
        transport.beatsPerBar = project.beatsPerBar
        rebuild()
    }

    public func makeInstrument(for track: Track) -> Instrument {
        // If the track targets a hosted Audio Unit (not built-in / Vital), try it.
        // Exception: a live Step Sequencer drum kit must not inherit a stale
        // plug-in target from a previous plugin-lane experiment. Otherwise Tech
        // House/EDM kit lanes get sent to Serum/another AU and every lane sounds
        // like a bass note instead of Kick/Snare/Hat. Pure plug-in sequencer
        // tracks may still host the AU; mixed racks can be upgraded later with a
        // true per-lane instrument rack.
        let liveStepKitHasBuiltInLanes = track.kind.isStepEditable
            && track.useStepSequencer
            && track.sequencerLayers.contains { $0.source != .plugin }
        #if canImport(AVFoundation) && canImport(AudioToolbox)
        if !liveStepKitHasBuiltInLanes,
           let target = track.pluginTargetID, target != "Built-in Analog", target != "Vital" {
            if let slot=track.externalPluginSlots.first(where:{$0.role != .effect && (AudioUnitCatalog.compact($0.name.components(separatedBy:":").last ?? $0.name)==AudioUnitCatalog.compact(target.components(separatedBy:":").last ?? target) || $0.pluginID == target)}),slot.format == .vst3 {
                if let hosted = nativePlugin(for:slot) { return hosted }
                return UnavailablePluginInstrument(name:slot.name)
            }
            let cacheKey = hostedAUCacheKey(trackID: track.id, pluginName: target)
            if let cached = hostedAUInstrumentCache[cacheKey], cached.ready { return cached }
            let slot=track.externalPluginSlots.first(where:{$0.role != .effect && (AudioUnitCatalog.compact($0.name.components(separatedBy:":").last ?? $0.name)==AudioUnitCatalog.compact(target.components(separatedBy:":").last ?? target) || $0.pluginID == target)})
            let desc=AudioUnitCatalog.description(name:slot?.name ?? target,path:slot?.path,identifier:slot?.pluginID ?? "")
            if let au = HostedAUInstrument(pluginName: target, sampleRate: sampleRate, componentDescription:desc), au.ready {
                if let slot = track.externalPluginSlots.first(where: { $0.name == target || $0.pluginID == target }) {
                    au.restorePresetStateBase64(slot.presetStateBase64)
                }
                hostedAUInstrumentCache[cacheKey] = au
                return au
            }
            return UnavailablePluginInstrument(name:slot?.name ?? target)
        }
        #endif
        switch track.kind {
        case .analog:           return AnalogSynth(name: track.name, sampleRate: sampleRate)
        case .guitar:           return GuitarInstrument(sampleRate: sampleRate)
        case .drums:
            if track.sequencerLayers.contains(where: { $0.samplePath != nil || $0.embeddedSamples != nil }) {
                return SampleLayerDrumKit(name: track.name, genre: track.drumGenre, layers: track.sequencerLayers, sampleRate: sampleRate)
            }
            return DrumKit(name: track.name, genre: track.drumGenre, sampleRate: sampleRate)
        case .indianPercussion:
            let base = IndianPercussion(sampleRate: sampleRate)
            if track.sequencerLayers.contains(where: { $0.samplePath != nil || $0.embeddedSamples != nil }) {
                return SampleLayerHybridInstrument(name: track.name, base: base, layers: track.sequencerLayers, sampleRate: sampleRate)
            }
            return base
        case .bhangraDhol:
            let base = IndianPercussion(sampleRate: sampleRate)
            if track.sequencerLayers.contains(where: { $0.samplePath != nil || $0.embeddedSamples != nil }) {
                return SampleLayerHybridInstrument(name: track.name, base: base, layers: track.sequencerLayers, sampleRate: sampleRate)
            }
            return base
        case .sequencer:
            if track.sequencerLayers.contains(where: { $0.samplePath != nil || $0.embeddedSamples != nil }) {
                return SampleLayerDrumKit(name: track.name, genre: track.drumGenre, layers: track.sequencerLayers, sampleRate: sampleRate)
            }
            return DrumKit(name: track.name, genre: track.drumGenre, sampleRate: sampleRate)
        case .bhangraArchitect:
            let base = BhangraArchitectInstrument(sampleRate: sampleRate)
            if track.sequencerLayers.contains(where: { $0.samplePath != nil || $0.embeddedSamples != nil }) {
                return SampleLayerHybridInstrument(name: track.name, base: base, layers: track.sequencerLayers, sampleRate: sampleRate)
            }
            return base
        case .guaracha2C:
            if track.sequencerLayers.contains(where: { $0.samplePath != nil || $0.embeddedSamples != nil }) {
                return SampleLayerDrumKit(name: track.name, genre: .guaracha, layers: track.sequencerLayers, sampleRate: sampleRate)
            }
            return DrumKit(name: track.name, genre: .guaracha, sampleRate: sampleRate)
        case .bailaton:
            if track.sequencerLayers.contains(where: { $0.samplePath != nil || $0.embeddedSamples != nil }) {
                return SampleLayerDrumKit(name: track.name, genre: track.drumGenre, layers: track.sequencerLayers, sampleRate: sampleRate)
            }
            return DrumKit(name: track.name, genre: track.drumGenre, sampleRate: sampleRate)
        case .dubstepWrangler:
            // Dubstep Wrangler is a step-sequencer kit/generator, not a single
            // monophonic instrument for every lane. If its lanes are drum/sample
            // lanes, route them through the Dubstep DrumKit so Kick/Snare/Hat do
            // not all become wobble-bass notes. A pure plug-in lane rack is still
            // handled by the hosted-AU branch above.
            if track.sequencerLayers.contains(where: { $0.samplePath != nil || $0.embeddedSamples != nil }) {
                return SampleLayerDrumKit(name: track.name, genre: .dubstep, layers: track.sequencerLayers, sampleRate: sampleRate)
            }
            return DrumKit(name: track.name, genre: .dubstep, sampleRate: sampleRate)
        case .oscillatron:     return OscillatronInstrument(sampleRate: sampleRate)
        case .lemmingBass:     return LemmingBassInstrument(sampleRate: sampleRate)
        case .audio:            return SilenceInstrument()   // playback handled in renderTrack
        }
    }

    #if canImport(AVFoundation) && canImport(AudioToolbox)
    private func hostedAUCacheKey(trackID: UUID, pluginName: String) -> String {
        "\(trackID.uuidString)|\(pluginName.lowercased())|\(Int(sampleRate.rounded()))"
    }
    #endif

    /// Drop the cached hosted-AU instance for a track so the next rebuild creates
    /// a genuinely fresh plug-in instance. The Sound Agent uses this for new patch
    /// requests: writing a new AI patch on top of an unknown Serum/Omnisphere/etc.
    /// state causes misleading results, so each design pass starts from the
    /// vendor's Init/default instance instead.
    public func resetHostedAudioUnit(for track: Track, pluginName: String? = nil) {
        #if canImport(AVFoundation) && canImport(AudioToolbox)
        let prefix = "\(track.id.uuidString)|"
        if let pluginName, !pluginName.isEmpty {
            hostedAUInstrumentCache.removeValue(forKey: hostedAUCacheKey(trackID: track.id, pluginName: pluginName))
        } else {
            hostedAUInstrumentCache = hostedAUInstrumentCache.filter { !$0.key.hasPrefix(prefix) }
        }
        #endif
    }

    /// Tear down and reconnect a source node per track.
    public func rebuild() {
        guard let project = project else { return }
        let wasRunning=avEngine.isRunning
        if wasRunning {avEngine.stop()}
        // Repair legacy file-only AU labels and effects that older scans marked
        // as instruments. Keep plugin IDs/state and automation references intact.
        for track in project.tracks {
            for index in track.externalPluginSlots.indices {
                let slot=track.externalPluginSlots[index]
                var role=slot.role
                if slot.format == .audioUnit,let path=slot.path,let entries=Bundle(path:path)?.infoDictionary?["AudioComponents"] as? [[String:Any]],let entry=entries.first(where:{AudioUnitCatalog.compact($0["name"] as? String ?? "")==AudioUnitCatalog.compact(slot.name)}) ?? entries.first {
                    let type=entry["type"] as? String ?? ""
                    role = type == "aumu" || type == "augn" ? .instrument : .effect
                } else if slot.format == .vst3,let loaded=nativePlugin(for:slot) {role=loaded.isInstrument ? .instrument:.effect}
                else if role == .unknown {role=PluginScanner.classifyPluginRole(name:slot.name,path:slot.path)}
                track.externalPluginSlots[index].role=role
                if role == .effect,track.pluginTargetID==slot.name || track.pluginTargetID==slot.pluginID {track.pluginTargetID=track.externalPluginSlots.first(where:{$0.id != slot.id && $0.role == .instrument})?.name}
            }
        }
        #if canImport(AVFoundation) && canImport(AudioToolbox)
        let validHostedAUKeys = Set(project.tracks.compactMap { track -> String? in
            guard let target = track.pluginTargetID, target != "Built-in Analog", target != "Vital" else { return nil }
            return hostedAUCacheKey(trackID: track.id, pluginName: target)
        })
        hostedAUInstrumentCache = hostedAUInstrumentCache.filter { validHostedAUKeys.contains($0.key) }
        #endif
        let validSlotIDs=Set(project.tracks.flatMap{track in (track.externalPluginSlots + track.audioClips.flatMap(\.externalPluginSlots)).map(\.id)})
        nativePluginCache=nativePluginCache.filter{validSlotIDs.contains($0.key)}
        externalAUCache=externalAUCache.filter{validSlotIDs.contains($0.key)}
        for node in sourceNodes.values { avEngine.detach(node) }
        for node in returnSourceNodes.values { avEngine.detach(node) }
        if let metronomeNode { avEngine.detach(metronomeNode) }
        metronomeNode = nil
        sourceNodes.removeAll()
        returnSourceNodes.removeAll()
        states.removeAll()
        returnStates.removeAll()

        clipPluginStates.removeAll()
        for track in project.tracks {
            for clip in track.audioClips where !clip.externalPluginSlots.isEmpty {
                let effects=clip.externalPluginSlots.compactMap{externalPlugin(for:$0)}
                clipPluginStates[clip.id]=ClipPluginRenderState(capacity:maxFrames,effects:effects)
            }
            let instrument = makeInstrument(for: track)
            let state = TrackRenderState(track: track, instrument: instrument, capacity: maxFrames)
            state.externalFactory = { [weak self] slot in self?.externalPlugin(for:slot) }
            state.rebuildEffects(sampleRate: sampleRate)
            states[track.id] = state

            let node = AVAudioSourceNode(format: stereoFormat) { [weak self, weak project, weak state]
                isSilence, timestamp, frameCount, abl in
                guard let self, let project, let state else {
                    isSilence.pointee = true; return noErr
                }
                self.renderTrack(state: state, project: project,
                                 timestamp: timestamp, frames: Int(frameCount), abl: abl)
                // Do not mark source nodes as silent just because the current buffer
                // happens to contain silence. Some AU synths (Serum 2 included)
                // interpret host silence/suspension aggressively and their editor
                // shows "DAW suspended processing"; recording then appears to use
                // an Init instance. Keep the live hosted AU render path active.
                isSilence.pointee = false
                return noErr
            }
            sourceNodes[track.id] = node
            avEngine.attach(node)
            avEngine.connect(node, to: avEngine.mainMixerNode, format: stereoFormat)
        }


        let clickNode = AVAudioSourceNode(format: stereoFormat) { [weak self] isSilence, timestamp, frameCount, abl in
            guard let self else { isSilence.pointee = true; return noErr }
            self.renderMetronome(timestamp: timestamp, frames: Int(frameCount), abl: abl)
            // Keep the click source alive whenever the metronome is enabled.
            // Marking this node silent between beats/count-in buffers can cause
            // AVAudioEngine to stop pulling it right when the count-in begins,
            // which made the transport look active while no click was audible.
            isSilence.pointee = ObjCBool(!self.metronomeEnabled)
            return noErr
        }
        metronomeNode = clickNode
        avEngine.attach(clickNode)
        avEngine.connect(clickNode, to: avEngine.mainMixerNode, format: stereoFormat)

        for bus in project.returnBuses {
            let rstate = ReturnRenderState(bus: bus, capacity: maxFrames, sampleRate: sampleRate)
            returnStates[bus.id] = rstate
            let node = AVAudioSourceNode(format: stereoFormat) { [weak self, weak rstate] isSilence, timestamp, frameCount, abl in
                guard let self, let rstate else { isSilence.pointee = true; return noErr }
                self.renderReturn(state: rstate, frames: Int(frameCount), abl: abl)
                return noErr
            }
            returnSourceNodes[bus.id] = node
            avEngine.attach(node)
            avEngine.connect(node, to: avEngine.mainMixerNode, format: stereoFormat)
        }

        if wasRunning { try? avEngine.start() }
    }

    public func start() {
        if ProcessInfo.processInfo.arguments.contains("--validate-hosting") || ProcessInfo.processInfo.arguments.contains("--validate-export-grid") {return}
        if !avEngine.isRunning {
            avEngine.prepare()
            try? avEngine.start()
        }
    }
    public func stop() { avEngine.stop() }

    /// True while CoreAudio is actively pulling from source nodes. App-level
    /// code uses this to pause rendering before replacing step-sequencer kits
    /// so the render callback never reads a half-mutated lane/track array.
    public var isRunning: Bool { avEngine.isRunning }

    // Live auditioning from the UI (keyboard / clicking notes).
    public func audition(track: Track, note: Int, on: Bool) {
        guard let state = states[track.id] else { return }
        if on { state.instrument.noteOn(note, velocity: 0.9) }
        else  { state.instrument.noteOff(note) }
    }

    public func meterPeak(for track: Track) -> Float { states[track.id]?.meterPeak ?? 0 }
    public func meterIsClipping(for track: Track) -> Bool { (states[track.id]?.meterPeak ?? 0) >= 0.985 }

    /// Master output level (0...1, mapped onto the main mixer's output volume).
    public var masterVolume: Float {
        get { avEngine.mainMixerNode.outputVolume }
        set { avEngine.mainMixerNode.outputVolume = max(0, min(1, newValue)) }
    }

    /// Approximate master meter: the loudest currently-audible track. Cheap, and
    /// avoids installing a tap on the audio thread just to drive a UI bar.
    public func masterMeterPeak() -> Float {
        var peak: Float = 0
        for state in states.values { peak = max(peak, state.meterPeak) }
        for state in returnStates.values { peak = max(peak, state.meterPeak) }
        return min(1, peak * masterVolume)
    }

    public func masterMeterIsClipping() -> Bool {
        var peak: Float = 0
        for state in states.values { peak = max(peak, state.meterPeak) }
        for state in returnStates.values { peak = max(peak, state.meterPeak) }
        return peak * masterVolume >= 0.985
    }

    /// The live AnalogSynth instance the audio thread is rendering, for in-place
    /// preset editing from the UI.
    public func liveAnalog(for track: Track) -> AnalogSynth? {
        states[track.id]?.instrument as? AnalogSynth
    }

    /// Any stock synth that exposes the built-in analog patch surface. This is
    /// broader than `liveAnalog`: Oscillatron, LemmingBass, and the melodic
    /// voices inside Bhangra Architect also wrap AnalogSynth voices and should be
    /// patchable by the Sound Agent.
    public func liveStockAnalog(for track: Track) -> StockAnalogPatchable? {
        states[track.id]?.instrument as? StockAnalogPatchable
    }

    // MARK: Render

    private func renderTrack(state: TrackRenderState, project: Project,
                             timestamp: UnsafePointer<AudioTimeStamp>,
                             frames: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        let n = min(frames, state.capacity)
        let L = state.scratchL, R = state.scratchR
        let track = state.track

        // In Step Sequencer focus the Arrangement must be fully isolated. Earlier
        // fixes only stopped MIDI/audio clip scheduling, but frozen bounces and
        // hosted instruments on other tracks could still render their stale audio.
        // Hard-gate every non-live-step track before source rendering so Step view
        // behaves like a soloed sequencer preview, not Arrangement playback.
        if playbackScope == .stepSequencer && !(track.kind.isStepEditable && track.useStepSequencer) {
            state.instrument.allNotesOff()
            state.pendingOffs.removeAll()
            for i in 0..<n { L[i] = 0; R[i] = 0 }
            finishStereo(state: state, track: track, project: project, L: L, R: R, n: n, abl: abl, runEffects: false, automationBeat: 0)
            return
        }

        // ---- Transport scheduling ----
        var beatNow = 0.0
        if transport.isPlaying {
            let startSample = timestamp.pointee.mSampleTime
            if transport.anchorSampleTime < 0 { transport.anchorSampleTime = startSample }
            let beat0 = transport.beat(at: startSample)
            let beat1 = transport.beat(at: startSample + Double(n))
            beatNow = beat0

            state.pendingOffs.removeAll { off in
                if off.beatEnd <= beat1 { state.instrument.noteOff(off.note); return true }
                return false
            }
            // Playback is scoped to the visible workspace. This prevents the
            // classic double-trigger bug where the Step Sequencer grid and a
            // printed Arrangement clip both fire the same notes.
            if track.kind != .audio && !track.frozen {
                switch playbackScope {
                case .stepSequencer:
                    if track.kind.isStepEditable && track.useStepSequencer {
                        scheduleSteps(state: state, project: project, beat0: beat0, beat1: beat1)
                    }
                case .arrangement, .pianoRoll:
                    scheduleClips(state: state, project: project, beat0: beat0, beat1: beat1)
                case .all:
                    if track.kind.isStepEditable && track.useStepSequencer {
                        scheduleSteps(state: state, project: project, beat0: beat0, beat1: beat1)
                    } else {
                        scheduleClips(state: state, project: project, beat0: beat0, beat1: beat1)
                    }
                }
            }
        }

        // ---- Automation at this block's start beat ----
        if !track.automationLanes.isEmpty { state.applyAutomation(atBeat: beatNow) }

        if let native=state.instrument as? NativeHostedPlugin {native.setTransport(bpm:currentTempo(atBeat:beatNow),beat:beatNow,playing:transport.isPlaying)}
        // ---- Source: frozen bounce > recorded audio > instrument ----
        if track.frozen, let bounce = track.bounced {
            renderClip(bounce, into: L, R, frames: n, beat0: beatNow)
            // a frozen bounce already includes its device chain — skip effects below
            finishStereo(state: state, track: track, project: project, L: L, R: R, n: n, abl: abl, runEffects: false, automationBeat: beatNow)
            return
        } else if track.kind == .audio {
            for i in 0..<n { L[i] = 0; R[i] = 0 }
            if playbackScope != .stepSequencer {
                for clip in track.audioClips where clip.isActive { renderClip(clip, into: L, R, frames: n, beat0: beatNow, accumulate: true) }
            }
        } else if state.instrument.renderStereo(left: L, right: R, frames: n) {
            // AU/host filled stereo directly
        } else {
            state.instrument.render(into: L, frames: n)
            for i in 0..<n { R[i] = L[i] }     // mono → dual
        }

        finishStereo(state: state, track: track, project: project, L: L, R: R, n: n, abl: abl, runEffects: true, automationBeat: beatNow)
    }

    /// Keep live DSP mirrors aligned with rack controls. Earlier builds only
    /// copied DeviceModel params when the engine rebuilt, so several stock
    /// devices looked alive in the UI but kept processing with stale/default
    /// values until a full rebuild.
    private func currentTempo(atBeat beat: Double) -> Double {
        if let map = transport.tempoMap { return map.bpm(atBeat: beat) }
        return transport.tempo
    }

    private func syncEffect(_ fx: AudioEffect, from model: DeviceModel, atTempo tempo: Double) {
        fx.bypassed = model.bypassed
        if let tempoAware = fx as? TempoAware { tempoAware.setTempo(tempo) }
        for (id, value) in model.params { fx.setParam(id, value) }
    }

    /// Apply device automation after the static rack model has been mirrored into
    /// the live DSP node. Buildfix193 added per-block rack-param syncing so UI
    /// knob moves became audible immediately, but that also meant every block
    /// copied DeviceModel.params over the DSP node after automation had already
    /// been evaluated. The visible automation lane was correct; the processor was
    /// reset back to the manual knob value just before processing.
    ///
    /// Keep the order DAW-like: manual parameter state is the baseline, then the
    /// automation lane overrides it for this block. Do not write the automated
    /// value back into DeviceModel.params here, otherwise playback would
    /// destructively move the user's saved/manual knob position.
    private func applyDeviceAutomation(_ lanes: [AutomationLane], to fx: AudioEffect, model: DeviceModel, atBeat beat: Double) {
        guard !lanes.isEmpty else { return }
        for lane in lanes where lane.enabled && lane.nodeID == model.nodeID {
            guard let value = lane.value(atBeat: beat) else { continue }
            if lane.paramID == AutomationSpecialParam.deviceOn {
                fx.bypassed = value < 0.5
            } else {
                fx.setParam(lane.paramID, value)
            }
        }
    }


    /// Apply automation to hosted third-party plug-in effects. Their node ids are
    /// stable `external-plugin:<plugin id>` strings, and parameter ids are AU
    /// parameter addresses/names exposed by the plug-in. Values are scheduled
    /// into the live AU before the current audio block is rendered, so AU effects
    /// such as iZotope Neutron follow lanes during playback, freeze and export.
    private func applyExternalPluginAutomation(_ lanes: [AutomationLane], to fx: AudioEffect, nodeID: String, atBeat beat: Double) {
        guard !lanes.isEmpty else { return }
        for lane in lanes where lane.enabled && lane.nodeID == nodeID {
            guard let value = lane.value(atBeat: beat) else { continue }
            if lane.paramID == AutomationSpecialParam.deviceOn {
                fx.bypassed = value < 0.5
            } else {
                fx.setParam(lane.paramID, value)
            }
        }
    }

    /// Device chain (stereo, with per-device mono collapse) + balance/volume + meter → output.
    private func finishStereo(state: TrackRenderState, track: Track, project: Project,
                              L: UnsafeMutablePointer<Float>, R: UnsafeMutablePointer<Float>,
                              n: Int, abl: UnsafeMutablePointer<AudioBufferList>, runEffects: Bool,
                              automationBeat: Double) {
        if runEffects {
            for (i, fx) in state.effects.enumerated() {
                if i < state.effectModels.count {
                    let model = state.effectModels[i]
                    syncEffect(fx, from: model, atTempo: currentTempo(atBeat: automationBeat))
                    applyDeviceAutomation(track.automationLanes, to: fx, model: model, atBeat: automationBeat)
                }
                guard !fx.bypassed else { continue }
                if i < state.effectModels.count, let scID = state.effectModels[i].sidechainInputTrackID, state.effectModels[i].sidechainEnabled, let source = states[scID], let scfx = fx as? SidechainAudioEffect {
                    scfx.processSidechain(L, R, sidechainL: UnsafePointer(source.scratchL), sidechainR: UnsafePointer(source.scratchR), frames: n)
                    continue
                }
                if i < state.effectMono.count && state.effectMono[i] {
                    for j in 0..<n { let m = (L[j] + R[j]) * 0.5; L[j] = m; R[j] = m }
                }
                fx.process(L, R, frames: n)
            }
        }

        if runEffects && !state.externalEffects.isEmpty {
            for (slot, fx) in zip(state.externalEffectSlots, state.externalEffects) {
                applyExternalPluginAutomation(track.automationLanes, to: fx, nodeID: slot.nodeID, atBeat: automationBeat)
                guard !fx.bypassed else { continue }
                (fx as? NativeHostedPlugin)?.setTransport(bpm:currentTempo(atBeat:automationBeat),beat:automationBeat,playing:transport.isPlaying)
                fx.process(L, R, frames: n)
            }
        }

        var groupVol: Float = 1
        var groupPan: Float = 0
        var groupAudible: Bool = true
        if let gid = track.groupID, let group = project.groups.first(where: { $0.id == gid }) {
            if runEffects && !group.devices.isEmpty {
                var groupNodes: [String: Automatable] = [:]
                let groupFX = group.devices.map { model -> (DeviceModel, AudioEffect) in
                    let fx = DeviceFactory.make(from: model, sampleRate: sampleRate)
                    groupNodes[model.nodeID] = fx
                    return (model, fx)
                }
                for (model, fx) in groupFX {
                    syncEffect(fx, from: model, atTempo: currentTempo(atBeat: automationBeat))
                    applyDeviceAutomation(group.automationLanes, to: fx, model: model, atBeat: automationBeat)
                    guard !model.bypassed && !fx.bypassed else { continue }
                    if model.mono {
                        for j in 0..<n { let m = (L[j] + R[j]) * 0.5; L[j] = m; R[j] = m }
                    }
                    fx.process(L, R, frames: n)
                }
            }
            groupVol = group.volume
            groupPan = group.pan
            groupAudible = !group.mute
        }

        let anySolo = project.tracks.contains { $0.solo }
        let audible = !track.mute && groupAudible && (!anySolo || track.solo)
        let dryToMaster: Float = (track.outputMode == .sendsOnly) ? 0 : 1
        let vol = track.volume * groupVol * (audible ? 1 : 0)
        let pan = max(-1, min(1, track.pan + groupPan))
        let width = max(0, min(2, track.stereoWidth))
        let lGain = vol * dryToMaster * (pan > 0 ? (1 - pan) : 1) * (track.panMode == .trueStereo ? width : 1)
        let rGain = vol * dryToMaster * (pan < 0 ? (1 + pan) : 1) * (track.panMode == .trueStereo ? width : 1)

        // Send taps feed return buses. Post-fader sends follow channel volume/pan;
        // pre-fader sends use the already-processed device signal before fader.
        for send in track.sends where send.amount > 0.0001 {
            guard let ret = returnStates[send.returnBusID] else { continue }
            let g = send.amount
            let sgL = send.preFader ? g : g * lGain
            let sgR = send.preFader ? g : g * rGain
            for i in 0..<n {
                ret.busL[i] += L[i] * sgL
                ret.busR[i] += R[i] * sgR
            }
        }

        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        var peak: Float = 0
        if buffers.count >= 2,
           let lp = buffers[0].mData?.assumingMemoryBound(to: Float.self),
           let rp = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
            for i in 0..<n {
                let l = L[i] * lGain, r = R[i] * rGain
                lp[i] = l; rp[i] = r
                let a = max(abs(l), abs(r)); if a > peak { peak = a }
            }
        }
        state.meterPeak = state.meterPeak * 0.85 + peak * 0.15
    }

    private func shouldSnapPitch(for track: Track) -> Bool {
        switch track.kind {
        case .drums, .indianPercussion, .bhangraDhol, .sequencer, .bhangraArchitect, .guaracha2C, .bailaton, .dubstepWrangler:
            return false
        default:
            return true
        }
    }

    private func playablePitch(_ note: Int, track: Track, project: Project) -> Int {
        shouldSnapPitch(for: track) ? project.snap(note) : note
    }

    private struct MIDINotePlan {
        var pitches: [Int]
        var velocity: Float
        var length: Double
    }

    private func clampedMIDIPitch(_ p: Int) -> Int { max(0, min(127, p)) }

    private func midiEffectPlan(base: Int, velocity: Float, length: Double, track: Track, project: Project) -> MIDINotePlan {
        var pitches = [playablePitch(base, track: track, project: project)]
        var vel = max(0, min(1, velocity))
        var len = max(0.02, length)

        for device in track.devices where !device.bypassed {
            switch device.kind {
            case .pitch:
                let semis = Int((device.params["transpose"] ?? 0).rounded()) + 12 * Int((device.params["octave"] ?? 0).rounded())
                pitches = pitches.map { clampedMIDIPitch($0 + semis) }
            case .tune, .scale:
                let amount = device.params["amount"] ?? 1
                if amount >= 0.5 { pitches = pitches.map { playablePitch($0, track: track, project: project) } }
            case .velocity:
                let gain = Float(device.params["gain"] ?? 1)
                let comp = Float(device.params["compress"] ?? 0)
                vel = max(0.01, min(1, vel * gain))
                if comp > 0 { vel = vel * (1 - comp) + (0.72 + (vel - 0.72) * 0.45) * comp }
            case .noteLength:
                let gate = device.params["gate"] ?? 0.9
                let minimum = device.params["minimum"] ?? 0.08
                len = max(minimum, len * gate)
            case .chord:
                let root = pitches.first ?? base
                var chord = [root]
                if (device.params["third"] ?? 1) >= 0.5 { chord.append(root + 4) }
                if (device.params["fifth"] ?? 1) >= 0.5 { chord.append(root + 7) }
                if (device.params["seventh"] ?? 0) >= 0.5 { chord.append(root + 11) }
                if (device.params["octave"] ?? 0) >= 0.5 { chord.append(root + 12) }
                pitches = chord.map(clampedMIDIPitch)
            case .random:
                let chance = device.params["chance"] ?? 0
                if chance > 0.001 {
                    let choices = max(1, Int((device.params["choices"] ?? 3).rounded()))
                    let offset = ((base * 1103515245 + choices * 12345) & 0x7fffffff) % max(1, choices)
                    let semis = [-12, -7, -5, 0, 5, 7, 12][min(6, offset)]
                    pitches = pitches.map { playablePitch(clampedMIDIPitch($0 + semis), track: track, project: project) }
                }
            case .bouncyNotes:
                let root = pitches.first ?? base
                var bounce = pitches
                if (device.params["fifth"] ?? 0) >= 0.5 { bounce.append(root + 7) }
                if (device.params["octave"] ?? 0) >= 0.5 { bounce.append(root + 12) }
                pitches = Array(Set(bounce.map(clampedMIDIPitch))).sorted()
            default:
                break
            }
        }
        return MIDINotePlan(pitches: pitches.isEmpty ? [playablePitch(base, track: track, project: project)] : pitches, velocity: vel, length: len)
    }

    private func arpeggiatorDevice(on track: Track) -> DeviceModel? {
        track.devices.first(where: { $0.kind == .arpeggiator && !$0.bypassed })
    }

    private func arpeggiatedPitches(base: Int, track: Track) -> [Int] {
        guard let arp = arpeggiatorDevice(on: track) else { return [base] }
        let octaves = max(1, min(4, Int((arp.params["octaves"] ?? 2).rounded())))
        var result: [Int] = []
        for octave in 0..<octaves { result.append(max(0, min(127, base + octave * 12))) }
        return result.isEmpty ? [base] : result
    }

    private func arpeggiatorRateBeats(on track: Track) -> Double {
        guard let arp = arpeggiatorDevice(on: track) else { return 0 }
        return max(0.03125, min(4.0, arp.params["rate"] ?? 0.25))
    }

    private func arpeggiatorGate(on track: Track) -> Double {
        guard let arp = arpeggiatorDevice(on: track) else { return 1 }
        return max(0.02, min(1.0, arp.params["gate"] ?? 0.45))
    }

    private func arpeggiatedStepPitches(base: Int, layer: SequencerLayer, track: Track) -> [Int] {
        // Track-level arpeggiators are for melodic MIDI/plugin lanes. They must
        // not transpose drum-kit or one-shot lanes: a Kick lane arped to +12/+24
        // becomes an unrelated drum note or a bassy wrong hit. This was one of
        // the paths that made Dubstep Wrangler poison EDM/Tech House after kit
        // switching.
        if layer.source == .builtIn || layer.source == .splice || layer.samplePath != nil || layer.embeddedSamples != nil { return [base] }
        return arpeggiatedPitches(base: base, track: track)
    }

    private func scheduleClips(state: TrackRenderState, project: Project, beat0: Double, beat1: Double) {
        let hasArp = arpeggiatorDevice(on: state.track) != nil
        let epsilon = 1.0e-9
        for clip in state.track.clips where clip.isActive {
            for note in clip.notes {
                let absStart = clip.startBeat + note.start
                let noteEnd = absStart + max(0.02, note.length)
                guard noteEnd > beat0 && absStart < beat1 else { continue }
                let plan = midiEffectPlan(base: note.pitch, velocity: note.velocity, length: note.length, track: state.track, project: project)
                if hasArp {
                    let rate = arpeggiatorRateBeats(on: state.track)
                    let gate = arpeggiatorGate(on: state.track)
                    let firstStep = max(0, Int(floor(((max(absStart, beat0) - absStart) / rate) + epsilon)))
                    var step = firstStep
                    while true {
                        let tickBeat = absStart + Double(step) * rate
                        if tickBeat >= beat1 - epsilon || tickBeat >= noteEnd - epsilon { break }
                        if tickBeat >= beat0 - epsilon {
                            var arpPool: [Int] = []
                            for pitch in plan.pitches { arpPool.append(contentsOf: arpeggiatedPitches(base: pitch, track: state.track)) }
                            if arpPool.isEmpty { arpPool = plan.pitches }
                            let pitch = arpPool[step % arpPool.count]
                            let length = min(rate * gate, noteEnd - tickBeat, beat1 - tickBeat)
                            if length > 0.001 {
                                state.instrument.noteOn(pitch, velocity: plan.velocity)
                                state.pendingOffs.append((tickBeat + length, pitch))
                            }
                        }
                        step += 1
                    }
                } else if absStart >= beat0 && absStart < beat1 {
                    for pitch in plan.pitches {
                        state.instrument.noteOn(pitch, velocity: plan.velocity)
                        state.pendingOffs.append((absStart + plan.length, pitch))
                    }
                }
            }
        }
    }

    private func scheduleSteps(state: TrackRenderState, project: Project, beat0: Double, beat1: Double) {
        let pattern = state.track.stepPattern
        guard pattern.hasAnyHits else {
            // Clear must be absolute: once the grid is empty, kill any previous
            // live notes and keep the render cursor invalidated so the last kit
            // cannot ghost under the next one.
            if !state.lastStepNotes.isEmpty { for old in state.lastStepNotes { state.instrument.noteOff(old) } }
            state.instrument.allNotesOff()
            state.pendingOffs.removeAll()
            state.lastStepNotes.removeAll()
            state.lastStepIndex = -1
            return
        }
        let stepLen = 1.0 / Double(pattern.stepsPerBeat)
        let patternBeats = Double(pattern.stepCount) * stepLen
        guard patternBeats > 0 else { return }

        let firstBoundary = (beat0 / stepLen).rounded(.up) * stepLen
        var b = firstBoundary
        while b < beat1 {
            let idx = Int((b / stepLen).rounded()) % pattern.stepCount
            if idx != state.lastStepIndex {
                for old in state.lastStepNotes { state.instrument.noteOff(old) }
                let step = pattern.steps[idx]
                var pitches: [Int] = []
                if !step.activeNotes.isEmpty {
                    for laneNote in step.activeNotes {
                        if let layer = state.track.sequencerLayer(for: laneNote) {
                            let plan = midiEffectPlan(base: layer.playbackNote(project: project), velocity: layer.playbackVelocity(baseVelocity: step.velocity), length: stepLen, track: state.track, project: project)
                            for pitch in plan.pitches {
                                for arpPitch in arpeggiatedStepPitches(base: pitch, layer: layer, track: state.track) {
                                    state.instrument.noteOn(arpPitch, velocity: plan.velocity)
                                    pitches.append(arpPitch)
                                }
                            }
                        } else {
                            let plan = midiEffectPlan(base: laneNote, velocity: step.velocity, length: stepLen, track: state.track, project: project)
                            for pitch in plan.pitches {
                                for arpPitch in arpeggiatedPitches(base: pitch, track: state.track) {
                                    state.instrument.noteOn(arpPitch, velocity: plan.velocity)
                                    pitches.append(arpPitch)
                                }
                            }
                        }
                    }
                    state.lastStepNotes = pitches
                } else {
                    state.lastStepNotes.removeAll()
                }
                state.lastStepIndex = idx
            }
            b += stepLen
        }
    }

    /// Mix one clip's samples into L/R at the current beat. Uses the clip's
    /// warped buffer when present (the warp engine pre-stretches to project tempo).
    private func renderClip(_ clip: AudioClip, into L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>,
                            frames: Int, beat0: Double, accumulate: Bool = false) {
        if !accumulate { for i in 0..<frames { L[i] = 0; R[i] = 0 } }
        guard transport.isPlaying else { return }
        let blockTempo = currentTempo(atBeat: beat0)
        let src = clip.activeSamples
        let clipEndBeat = clip.startBeat + clip.arrangementLengthBeats(projectTempo: blockTempo)
        let gain = clip.gainLinear

        // If the clip has its own insert FX, render the clip into a temporary
        // stereo block first, process that block, then add it to the track bus.
        // This keeps track FX and clip FX independent from the user's POV.
        let hostedClip=clipPluginStates[clip.id]
        if !clip.devices.isEmpty || hostedClip != nil {
            let clipL = hostedClip?.left ?? UnsafeMutablePointer<Float>.allocate(capacity: frames)
            let clipR = hostedClip?.right ?? UnsafeMutablePointer<Float>.allocate(capacity: frames)
            defer {if hostedClip == nil {clipL.deallocate();clipR.deallocate()}}
            for i in 0..<frames { clipL[i] = 0; clipR[i] = 0 }
            for i in 0..<frames {
                let beat = beat0 + (Double(i) / sampleRate) * (blockTempo / 60.0)
                if beat < clip.startBeat || beat >= clipEndBeat { continue }
                let idx = clip.playbackSampleIndex(beatOffset: beat - clip.startBeat, projectTempo: blockTempo)
                if idx >= 0 && idx < src.count { let sample = src[idx] * gain; clipL[i] += sample; clipR[i] += sample }
            }
            for device in clip.devices where !device.bypassed {
                if device.mono {
                    for j in 0..<frames { let m = (clipL[j] + clipR[j]) * 0.5; clipL[j] = m; clipR[j] = m }
                }
                let fx = DeviceFactory.make(from: device, sampleRate: sampleRate)
                syncEffect(fx, from: device, atTempo: blockTempo)
                fx.process(clipL, clipR, frames: frames)
            }
            for fx in hostedClip?.effects ?? [] where !fx.bypassed {
                (fx as? NativeHostedPlugin)?.setTransport(bpm:blockTempo,beat:beat0,playing:true)
                fx.process(clipL,clipR,frames:frames)
            }
            for i in 0..<frames { L[i] += clipL[i]; R[i] += clipR[i] }
            return
        }

        for i in 0..<frames {
            let beat = beat0 + (Double(i) / sampleRate) * (blockTempo / 60.0)
            if beat < clip.startBeat || beat >= clipEndBeat { continue }
            let idx = clip.playbackSampleIndex(beatOffset: beat - clip.startBeat, projectTempo: blockTempo)
            if idx >= 0 && idx < src.count { let sample = src[idx] * gain; L[i] += sample; R[i] += sample }
        }
    }

    private func renderMetronome(timestamp: UnsafePointer<AudioTimeStamp>, frames: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        guard buffers.count >= 2,
              let lp = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let rp = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }

        for i in 0..<frames { lp[i] = 0; rp[i] = 0 }
        guard !avEngine.isInManualRenderingMode, metronomeEnabled else { return }

        let startSample = timestamp.pointee.mSampleTime
        let bpm = max(20.0, transport.isPlaying ? currentTempo(atBeat: transport.wallClockBeat()) : countInClickTempo)
        let secPerBeat = 60.0 / bpm
        let clickSeconds = min(0.070, secPerBeat * 0.45)
        let sr = max(1.0, sampleRate)
        let countInStart = countInClickStartTime
        let countInNow = Date.timeIntervalSinceReferenceDate
        let countInActive = isCountInClicking

        if !transport.isPlaying && !countInActive { return }
        if !countInActive, countInStart != nil { countInClickStartTime = nil }

        let blockBeat0 = transport.isPlaying ? transport.beat(at: startSample) : 0
        let blockBeat1 = transport.isPlaying ? transport.beat(at: startSample + Double(frames)) : 0
        let pulledBoundary = (!countInActive && transport.isPlaying) ? ceil(blockBeat0 - 1.0e-9) : .infinity
        let shouldPullBoundary = pulledBoundary >= blockBeat0 && pulledBoundary < blockBeat1

        for i in 0..<frames {
            let beat: Double
            if countInActive, let start = countInStart {
                // Count-in is intentionally wall-clock based and independent of
                // the project transport. This keeps the audible click alive while
                // recording has not begun yet, and avoids pre-roll rendering
                // arrangement clips or retriggering live synths.
                let bufferOffsetSeconds = Double(i) / sr
                beat = max(0, countInNow - start + bufferOffsetSeconds) / secPerBeat
            } else {
                // Arrangement MIDI/Step playback in this engine is block-triggered:
                // notes whose start falls anywhere in the current render quantum are
                // fired at the start of that quantum. A sample-perfect metronome then
                // sounded late next to printed Step Sequencer clips even though the
                // printed MIDI was tempo-correct. Mirror the transport scheduler by
                // pulling an imminent beat boundary to frame zero of the block.
                if i == 0, shouldPullBoundary {
                    beat = pulledBoundary
                } else {
                    beat = transport.beat(at: startSample + Double(i))
                }
            }
            let wholeBeat = floor(beat)
            let fraction = beat - wholeBeat
            let secIntoBeat = fraction * secPerBeat
            if shouldPullBoundary, i > 0, wholeBeat == pulledBoundary, secIntoBeat < clickSeconds { continue }
            guard secIntoBeat >= 0, secIntoBeat < clickSeconds else { continue }

            let beatInBar = Int(wholeBeat.rounded(.down)) % max(1, transport.beatsPerBar)
            let downbeat = beatInBar == 0
            let freq = downbeat ? 1760.0 : 1180.0
            let decay = exp(-secIntoBeat * (downbeat ? 42.0 : 54.0))
            let tone = sin(2.0 * Double.pi * freq * secIntoBeat)
            // Add a tiny front-loaded impulse so the click survives small buffers,
            // output-device smoothing, and host suspension heuristics. This makes
            // it behave like a real DAW metronome instead of a barely-audible sine.
            let impulse = secIntoBeat < 0.004 ? (1.0 - secIntoBeat / 0.004) : 0.0
            let click = (tone * 0.82 + impulse * 0.55) * decay
            let tick = Float(click) * metronomeVolume * (downbeat ? 1.0 : 0.72)
            lp[i] += tick
            rp[i] += tick
        }
    }

    private func renderReturn(state: ReturnRenderState, frames: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        let n = min(frames, state.capacity)
        let L = state.scratchL, R = state.scratchR
        for i in 0..<n { L[i] = state.busL[i]; R[i] = state.busR[i]; state.busL[i] = 0; state.busR[i] = 0 }
        if let bus = state.bus, !bus.mute {
            for fx in state.effects where !fx.bypassed { fx.process(L, R, frames: n) }
            let vol = bus.volume
            let pan = bus.pan
            let lGain = vol * (pan > 0 ? (1 - pan) : 1)
            let rGain = vol * (pan < 0 ? (1 + pan) : 1)
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            var peak: Float = 0
            if buffers.count >= 2, let lp = buffers[0].mData?.assumingMemoryBound(to: Float.self), let rp = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<n { let l = L[i] * lGain, r = R[i] * rGain; lp[i] = l; rp[i] = r; peak = max(peak, max(abs(l), abs(r))) }
            }
            state.meterPeak = state.meterPeak * 0.85 + peak * 0.15
        } else {
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            if buffers.count >= 2, let lp = buffers[0].mData?.assumingMemoryBound(to: Float.self), let rp = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<n { lp[i] = 0; rp[i] = 0 }
            }
            state.meterPeak *= 0.85
        }
    }

    /// Called before recording/count-in so hosted synths are definitely alive and
    /// the vendor UI is attached to the same AU that the engine renders.
    public func warmUpHostedAudioUnits() {
        #if canImport(AVFoundation) && canImport(AudioToolbox)
        for inst in hostedAUInstrumentCache.values where inst.ready {
            let frames = 128
            let L = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            let R = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            L.initialize(repeating: 0, count: frames)
            R.initialize(repeating: 0, count: frames)
            _ = inst.renderStereo(left: L, right: R, frames: frames)
            L.deallocate(); R.deallocate()
        }
        #endif
    }

    // MARK: Live node access (for UI device racks, automation, MIDI, the agent)

    private func nativePlugin(for slot:ExternalPluginSlot)->NativeHostedPlugin? {
        if let cached=nativePluginCache[slot.id] {return cached}
        guard let plugin=NativeHostedPlugin(slot:slot,sampleRate:sampleRate,maxFrames:maxFrames) else {return nil}
        nativePluginCache[slot.id]=plugin
        for track in project?.tracks ?? [] {if let i=track.externalPluginSlots.firstIndex(where:{$0.id==slot.id}){track.externalPluginSlots[i].hosted=true}}
        return plugin
    }
    private func externalPlugin(for slot:ExternalPluginSlot)->AudioEffect? {
        if slot.format == .vst3 {return nativePlugin(for:slot)}
        if slot.format == .audioUnit {
            if let cached=externalAUCache[slot.id] {return cached}
            guard let unit=HostedAUAudioEffect(pluginName:slot.name,sampleRate:sampleRate,componentDescription:AudioUnitCatalog.description(name:slot.name,path:slot.path,identifier:slot.pluginID)) else {return nil}
            unit.restorePresetStateBase64(slot.presetStateBase64);externalAUCache[slot.id]=unit
            for track in project?.tracks ?? [] {if let i=track.externalPluginSlots.firstIndex(where:{$0.id==slot.id}){track.externalPluginSlots[i].hosted=true}}
            return unit
        }
        return nil
    }
    public func liveNativePlugin(for slot:ExternalPluginSlot)->NativeHostedPlugin? {nativePluginCache[slot.id]}
    public func liveExternalAU(for slot:ExternalPluginSlot)->AUAudioUnit? {externalAUCache[slot.id]?.hostedAudioUnit}
    public func liveAUOwner(for slot:ExternalPluginSlot)->AnyObject? {
        if let effect=externalAUCache[slot.id] {return effect}
        for track in project?.tracks ?? [] where track.externalPluginSlots.contains(where:{$0.id==slot.id}) {
            if let instrument=states[track.id]?.instrument as? HostedAUInstrument {return instrument}
        }
        return nil
    }
    public func capturedExternalState(for slot:ExternalPluginSlot)->String? {
        if let unit=nativePluginCache[slot.id] {return unit.capturedPresetStateBase64()}
        return externalAUCache[slot.id]?.capturedPresetStateBase64()
    }
    public func liveInstrument(for track: Track) -> Instrument? { states[track.id]?.instrument }
    public func liveDrumKit(for track: Track) -> DrumKit? { states[track.id]?.instrument as? DrumKit }
    public func liveEffects(for track: Track) -> [AudioEffect] { states[track.id]?.effects ?? [] }
    public func liveNode(track: Track, nodeID: String) -> Automatable? { states[track.id]?.nodes[nodeID] }

    /// Rebuild only the effect chain for one track (after add/remove/reorder),
    /// without tearing down source nodes.
    public func refreshDevices(for track: Track) {
        let running=avEngine.isRunning
        if running {avEngine.stop()}
        states[track.id]?.rebuildEffects(sampleRate: sampleRate)
        for state in returnStates.values { state.rebuildEffects(sampleRate: sampleRate) }
        if running {start()}
    }

    /// Route a live MIDI/UI note to a specific track's instrument.
    public func sendNote(to track: Track, note: Int, velocity: Float, on: Bool, channel: Int = 0) {
        // Live keyboard/MIDI audition should never feel like the engine wakes up
        // on the first note. Start the CoreAudio graph before opening the gate so
        // Oscillatron/LemmingBass respond immediately when played from a controller
        // or the piano roll keyboard.
        if on && !avEngine.isRunning { start() }
        guard let inst = states[track.id]?.instrument else { return }
        if on { inst.noteOn(note, velocity: velocity, channel: channel) } else { inst.noteOff(note, channel: channel) }
    }

    /// Panic/transport-stop helper. A stopped DAW must never leave a synth/AU
    /// voice hanging just because the corresponding MIDI note-off was swallowed
    /// by transport state changes or a recording stop. Also clears render-thread
    /// scheduled note-offs so stale clip notes do not fire after the stop.
    public func allNotesOff() {
        for state in states.values {
            state.instrument.allNotesOff()
            state.pendingOffs.removeAll()
            state.lastStepNotes.removeAll()
            state.lastStepIndex = -1
        }
    }

    /// Reset only one step-sequencer track's render cursor. This is needed after
    /// clearing lanes or swapping grooves while transport is already running;
    /// otherwise the render thread may keep the previous kit voice alive until the
    /// next step boundary, which feels like Clear did nothing.
    public func resetStepSequencerState(for track: Track) {
        guard let state = states[track.id] else { allNotesOff(); return }
        state.instrument.allNotesOff()
        state.pendingOffs.removeAll()
        state.lastStepNotes.removeAll()
        state.lastStepIndex = -1
    }

    public func sendPitchBend(to track: Track, value: Float, channel: Int, rangeSemitones: Int) {
        states[track.id]?.instrument.pitchBend(value, channel: channel, rangeSemitones: rangeSemitones)
    }

    public func sendPressure(to track: Track, value: Float, note: Int? = nil, channel: Int) {
        states[track.id]?.instrument.pressure(value, note: note, channel: channel)
    }

    public func sendTimbre(to track: Track, value: Float, channel: Int) {
        states[track.id]?.instrument.timbre(value, channel: channel)
    }

    /// UI/MIDI-facing transport position.
    ///
    /// Do not derive this from `outputNode.lastRenderTime`: on some macOS/Xcode
    /// beta/CoreAudio combinations the output node can report a stale render time
    /// while source nodes are warming up or the graph is effectively silent. That
    /// made the playhead freeze and caused overdubbed MIDI notes to all land at
    /// the same beat. The render thread still uses sample timestamps internally
    /// for audio scheduling; the app/UI/MIDI layer uses this monotonic wall-clock
    /// clock so Play and Record always scrub immediately.
    public var currentBeat: Double {
        transport.isPlaying ? transport.wallClockBeat() : transport.playStartBeat
    }

    public func setCurrentBeat(_ beat: Double) {
        transport.setBeat(beat)
    }
}

// MARK: - Silent instrument (for recorded-audio tracks)

public final class SilenceInstrument: Instrument {
    public let name = "Audio"
    public init() {}
    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames { out[i] = 0 }
    }
    public func noteOn(_ note: Int, velocity: Float) {}
    public func noteOff(_ note: Int) {}
    public func allNotesOff() {}
}
