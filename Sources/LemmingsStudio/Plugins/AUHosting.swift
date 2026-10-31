import Foundation
import Darwin
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif

// MARK: - Hosted Audio Unit instrument
//
// Wraps an instantiated AUAudioUnit and exposes it through our `Instrument`
// protocol: audio is pulled from the unit's render block straight into the
// track's stereo scratch, and notes go in via its MIDI scheduling block. This is
// the real integration path for Serum/Massive/Omnisphere etc. when they ship an
// Audio Unit (v2/v3). It's the fiddliest part of the codebase — format/entitlement
// quirks vary per plugin — so failures degrade gracefully to silence.

#if canImport(AVFoundation) && canImport(AudioToolbox)
public final class HostedAUInstrument: Instrument, InstrumentTarget, Automatable {
    public let name: String
    public var displayName: String { name }
    private let au: AUAudioUnit
    /// Retain the AVAudioUnit wrapper when the unit was instantiated out-of-process.
    /// Without this strong reference macOS can tear down the remote AU host and the
    /// visible vendor editor no longer represents the engine-rendered instance.
    private let avUnit: AVAudioUnit?
    /// The actual live AU instance used by the audio engine. The plug-in editor
    /// must attach to this exact object; opening a second AVAudioUnit creates a
    /// second Serum/Vital instance that stays at Init while the engine instance
    /// receives the automation.
    private let musicalClock = HostedMusicalClock()
    public func setTransport(bpm: Double, beat: Double, playing: Bool, timelineSeconds: Double? = nil) { musicalClock.update(bpm: bpm, beat: beat, playing: playing, timelineSeconds: timelineSeconds) }
    public var hostedAudioUnit: AUAudioUnit { au }
    private let sampleRate: Double
    private var sampleTime: Float64 = 0
    private var abl: UnsafeMutableAudioBufferListPointer
    private var renderBlock: AURenderBlock?
    private var midiBlock: AUScheduleMIDIEventBlock?
    public private(set) var ready = false

    public init?(pluginName: String, sampleRate: Double, maxFrames: Int = 4096, componentDescription: AudioComponentDescription? = nil) {
        self.name = pluginName
        self.sampleRate = sampleRate
        self.abl = AudioBufferList.allocate(maximumBuffers: 2)
        guard let desc = componentDescription ?? Self.description(forPluginNamed: pluginName) else { return nil }
        do {
            // Use the same hosting model as Logic/GarageBand-style AU hosting:
            // instantiate through AVAudioUnit out-of-process first, then keep that
            // wrapper alive while rendering the unit's AUAudioUnit directly.  The
            // previous AUAudioUnit(componentDescription:) path created an in-process
            // object and made it far too easy for the editor/record path to drift
            // into a different Serum 2 instance.
            if let wrapper = Self.instantiateComponentSynchronously(desc, preferOutOfProcess: true) {
                self.avUnit = wrapper
                self.au = wrapper.auAudioUnit
            } else {
                let unit = try AUAudioUnit(componentDescription: desc)
                self.avUnit = nil
                self.au = unit
            }
            let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
            try self.au.outputBusses[0].setFormat(fmt)
            self.au.maximumFramesToRender = AUAudioFrameCount(maxFrames)
            try self.au.allocateRenderResources()
            self.renderBlock = self.au.renderBlock
            self.midiBlock = self.au.scheduleMIDIEventBlock
            musicalClock.install(on: self.au, sampleRate: sampleRate)
            self.ready = true
        } catch {
            free(self.abl.unsafeMutablePointer)
            return nil
        }
    }

    static func instantiateComponentSynchronously(_ desc: AudioComponentDescription, preferOutOfProcess: Bool) -> AVAudioUnit? {
        let options: AudioComponentInstantiationOptions = preferOutOfProcess && !AudioUnitCatalog.isLocal(desc) ? [.loadOutOfProcess] : []
        let semaphore = DispatchSemaphore(value: 0)
        final class Box { var unit: AVAudioUnit? = nil }
        let box = Box()
        AVAudioUnit.instantiate(with: desc, options: options) { unit, _ in
            box.unit = unit
            semaphore.signal()
        }
        // AU validation/remote-host spin-up can be slow the first time Serum 2 is
        // opened. Wait long enough to get the sandboxed instance, but fall back to
        // the normal path rather than blocking the app indefinitely.
        let completed: Bool
        if Thread.isMainThread {
            let end = Date().addingTimeInterval(8)
            var signaled = false
            repeat {
                if semaphore.wait(timeout: .now()) == .success { signaled = true; break }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
            } while Date() < end
            completed = signaled
        } else { completed = semaphore.wait(timeout: .now() + 8) == .success }
        return completed ? box.unit : nil
    }

    deinit { free(abl.unsafeMutablePointer) }

    static func description(forPluginNamed name: String) -> AudioComponentDescription? {
        var d = AudioComponentDescription(); d.componentType = kAudioUnitType_MusicDevice
        let comps = AVAudioUnitComponentManager.shared().components(matching: d)
        let requested = compactPluginName(name)
        return comps.first { component in
            let raw = component.name.lowercased()
            let compact = compactPluginName(component.name)
            return raw == name.lowercased()
                || raw.contains(name.lowercased())
                || compact == requested
                || compact.contains(requested)
                || requested.contains(compact)
        }?.audioComponentDescription
    }

    private static func compactPluginName(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "audio unit", with: "")
            .replacingOccurrences(of: "vst3", with: "")
            .replacingOccurrences(of: "vst", with: "")
            .replacingOccurrences(of: "au", with: "")
            .replacingOccurrences(of: "xfer", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }



    public func capturedPresetStateBase64() -> String? {
        let state = au.fullStateForDocument ?? au.fullState
        guard let state,
              PropertyListSerialization.propertyList(state, isValidFor: .binary),
              let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
        else { return nil }
        return data.base64EncodedString()
    }

    public func restorePresetStateBase64(_ encoded: String?) {
        guard let encoded,
              let data = Data(base64Encoded: encoded),
              let state = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return }
        au.fullState = state
    }

    public var currentPresetName: String? { au.currentPreset?.name }

    public var parameters: [PluginParam] {
        guard let tree = au.parameterTree else { return [] }
        return tree.allParameters.map {
            PluginParam(id: String($0.address), name: $0.displayName,
                        min: Double($0.minValue), max: Double($0.maxValue))
        }
    }

    @discardableResult public func apply(_ design: SoundDesign) throws -> String {
        guard let tree = au.parameterTree else { throw InstrumentTargetError.notHosted }
        var applied: [String] = []
        var scheduled = 0
        var missed: [String] = []
        for (rawKey, rawValue) in normalizedParameterPlan(for: design) {
            guard let param = findParameter(named: rawKey, in: tree) else {
                missed.append(rawKey)
                continue
            }
            let newValue = scaledValue(rawValue, for: param)
            if setLiveParameter(param, to: newValue) {
                scheduled += 1
                applied.append(param.displayName.isEmpty ? param.identifier : param.displayName)
            }
        }
        if scheduled == 0 {
            let exposed = tree.allParameters.prefix(24).map { "\($0.address):\($0.displayName.isEmpty ? $0.identifier : $0.displayName)" }.joined(separator: ", ")
            throw InstrumentTargetError.unsupported("Hosted \(displayName), but no AU parameter events were delivered for ‘\(design.presetName)’. Refusing to report false success. Unmatched requested knobs: \(missed.prefix(12).joined(separator: ", ")). Exposed AU params: \(exposed.isEmpty ? "none" : exposed)")
        }
        let unique = Array(Set(applied)).sorted()
        let missedNote = missed.isEmpty ? "" : " Skipped unmatched knobs: \(missed.prefix(8).joined(separator: ", "))."
        return "Applied ‘\(design.presetName)’ to the live \(displayName) AU by scheduling \(scheduled) host automation event(s): \(unique.prefix(10).joined(separator: ", "))\(unique.count > 10 ? "…" : "").\(missedNote)"
    }

    /// Some AU instruments, including Serum 2, do not reliably react when a host
    /// only mutates `AUParameter.value`. DAW automation should be delivered through
    /// the unit's scheduleParameterBlock so the processor and vendor UI receive a
    /// real host automation event. We still mirror the value onto the AUParameter
    /// object so Lemmings' generic editor and future reads stay in sync.
    private func setLiveParameter(_ param: AUParameter, to value: AUValue) -> Bool {
        let clamped = AUValue(min(max(Float(value), param.minValue), param.maxValue))
        au.scheduleParameterBlock(AUEventSampleTimeImmediate, 0, param.address, clamped)
        param.setValue(clamped, originator: nil)
        param.value = clamped
        return true
    }

    private func normalizedParameterPlan(for design: SoundDesign) -> [(String, Double)] {
        var plan: [(String, Double)] = []
        for (key, value) in design.params { plan.append((key, value)) }
        if let a = design.analog {
            // Convert Lemmings' generic synth design into common AU/plugin names.
            // Serum/Vital/Omnisphere/Massive expose different parameter labels, so
            // `findParameter` below uses aliases/fuzzy matching rather than assuming
            // a proprietary preset format.
            let cutoffNormalized = min(max((log2(max(a.cutoff, 20) / 20.0) / log2(20000.0 / 20.0)), 0), 1)
            let mapped: [(String, Double)] = [
                ("Cutoff", cutoffNormalized),
                ("Filter Cutoff", cutoffNormalized),
                ("Resonance", Double(a.resonance)),
                ("Filter Resonance", Double(a.resonance)),
                ("Attack", Double(a.attack)),
                ("Env Attack", Double(a.attack)),
                ("Decay", Double(a.decay)),
                ("Sustain", Double(a.sustain)),
                ("Release", Double(a.release)),
                ("Env Release", Double(a.release)),
                ("Volume", Double(a.gain)),
                ("Level", Double(a.gain))
            ]
            plan.append(contentsOf: mapped)
        }
        return plan
    }

    private func findParameter(named key: String, in tree: AUParameterTree) -> AUParameter? {
        if let address = AUParameterAddress(key), let p = tree.parameter(withAddress: address) { return p }
        if let macro = Self.macroNumber(from: key), let p = findMacroParameter(number: macro, in: tree) { return p }
        let normalizedKey = DeviceTranslationLayer.normalizeParameterName(key)
        let candidates = [key, normalizedKey]
        for candidate in candidates {
            if let macro = Self.macroNumber(from: candidate), let p = findMacroParameter(number: macro, in: tree) { return p }
            let needle = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = tree.allParameters.first(where: { $0.displayName.lowercased() == needle || $0.identifier.lowercased() == needle }) { return exact }
            let simplified = needle.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
            if let compact = tree.allParameters.first(where: {
                let dn = $0.displayName.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
                let id = $0.identifier.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
                return dn.contains(simplified) || id.contains(simplified)
            }) { return compact }
            let aliases = Self.parameterAliases[needle] ?? Self.parameterAliases[simplified] ?? []
            for alias in aliases {
                let a = alias.lowercased().replacingOccurrences(of: " ", with: "")
                if let hit = tree.allParameters.first(where: {
                    let dn = $0.displayName.lowercased().replacingOccurrences(of: " ", with: "")
                    let id = $0.identifier.lowercased().replacingOccurrences(of: " ", with: "")
                    return dn.contains(a) || id.contains(a)
                }) { return hit }
            }
        }

        // Big Serum/Serum 2 semantic fallback. The host AU parameter list may use
        // terse vendor labels such as "A Vol", "Fil Cutoff", "Env1 Dec",
        // "Cho Mix", or "Verb Wet" while the agent speaks in full synth terms.
        // Try a broad static alias list before giving up.
        for alias in Self.serumAliasCandidates(for: key) + Self.serumAliasCandidates(for: normalizedKey) {
            let compactAlias = Self.compactSearchText(alias)
            guard !compactAlias.isEmpty else { continue }
            if let hit = tree.allParameters.first(where: { param in
                let hay = Self.compactParameterText(param)
                return hay == compactAlias || hay.contains(compactAlias) || compactAlias.contains(hay)
            }) { return hit }
        }

        // Cross-synth agent map: Vital, Phase Plant, Sylenth1, Omnisphere and many
        // other popular instruments publish different host labels for the same musical
        // controls. Keep this in the agent/host layer rather than forcing the LLM to
        // know every vendor abbreviation.
        for alias in Self.crossSynthAliasCandidates(for: key) + Self.crossSynthAliasCandidates(for: normalizedKey) {
            let compactAlias = Self.compactSearchText(alias)
            guard !compactAlias.isEmpty else { continue }
            if let hit = tree.allParameters.first(where: { param in
                let hay = Self.compactParameterText(param)
                return hay == compactAlias || hay.contains(compactAlias) || compactAlias.contains(hay)
            }) { return hit }
        }

        if let scored = Self.bestSerumFuzzyParameter(for: key, in: tree) { return scored }
        if normalizedKey != key, let scored = Self.bestSerumFuzzyParameter(for: normalizedKey, in: tree) { return scored }
        return nil
    }

    private static func compactSearchText(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func serumAliasCandidates(for raw: String) -> [String] {
        let canonical = DeviceTranslationLayer.normalizeParameterName(raw)
        let compact = compactSearchText(canonical)
        var map: [String: [String]] = [
            "oscaon": ["A On", "Osc A On", "Oscillator A On"],
            "oscalevel": ["A Vol", "A Volume", "A Level", "Osc A Vol", "Osc A Volume", "Osc A Level", "Oscillator A Level", "Osc 1 Level", "Osc1 Level"],
            "oscapan": ["A Pan", "Osc A Pan"],
            "oscawtpos": ["A WTPos", "A WT Pos", "A Wavetable Pos", "A Position", "Osc A WTPos", "Osc A WT Pos", "WT Pos A", "Wavetable Position A"],
            "oscaunison": ["A Uni", "A Unison", "Osc A Uni", "Osc A Unison", "Unison A", "Osc 1 Unison"],
            "oscadetune": ["A Det", "A Detune", "Osc A Det", "Osc A Detune", "Detune A", "Osc 1 Detune"],
            "oscablend": ["A Blend", "Osc A Blend", "Blend A"],
            "oscaphase": ["A Phase", "Osc A Phase", "Phase A"],
            "oscarand": ["A Rand", "A Random", "Osc A Rand", "Rand A"],
            "oscawarp": ["A Warp", "Osc A Warp", "Warp A"],
            "oscawarpmode": ["A Warp Mode", "Osc A Warp Mode", "Warp Mode A"],
            "oscaoctave": ["A Oct", "A Octave", "Osc A Oct", "Osc A Octave"],
            "oscasemitone": ["A Semi", "A Semitone", "Osc A Semi", "Osc A Semitone"],
            "oscafine": ["A Fine", "Osc A Fine", "Fine A"],

            "oscbon": ["B On", "Osc B On", "Oscillator B On"],
            "oscblevel": ["B Vol", "B Volume", "B Level", "Osc B Vol", "Osc B Volume", "Osc B Level", "Oscillator B Level", "Osc 2 Level", "Osc2 Level"],
            "oscbpan": ["B Pan", "Osc B Pan"],
            "oscbwtpos": ["B WTPos", "B WT Pos", "B Wavetable Pos", "B Position", "Osc B WTPos", "Osc B WT Pos", "WT Pos B"],
            "oscbunison": ["B Uni", "B Unison", "Osc B Uni", "Osc B Unison", "Unison B", "Osc 2 Unison"],
            "oscbdetune": ["B Det", "B Detune", "Osc B Det", "Osc B Detune", "Detune B", "Osc 2 Detune"],
            "oscbblend": ["B Blend", "Osc B Blend", "Blend B"],
            "oscbphase": ["B Phase", "Osc B Phase", "Phase B"],
            "oscbrand": ["B Rand", "B Random", "Osc B Rand", "Rand B"],
            "oscbwarp": ["B Warp", "Osc B Warp", "Warp B"],
            "oscbwarpmode": ["B Warp Mode", "Osc B Warp Mode", "Warp Mode B"],
            "oscboctave": ["B Oct", "B Octave", "Osc B Oct", "Osc B Octave"],
            "oscbsemitone": ["B Semi", "B Semitone", "Osc B Semi", "Osc B Semitone"],
            "oscbfine": ["B Fine", "Osc B Fine", "Fine B"],

            "subon": ["Sub On", "Sub Enable"],
            "sublevel": ["Sub Vol", "Sub Volume", "Sub Level"],
            "subpan": ["Sub Pan"],
            "suboctave": ["Sub Oct", "Sub Octave"],
            "subwave": ["Sub Wave", "Sub Shape"],
            "noiseon": ["Noise On", "Nse On"],
            "noiselevel": ["Noise Vol", "Noise Volume", "Noise Level", "Nse Vol", "Nse Level"],
            "noisepitch": ["Noise Pitch", "Nse Pitch"],
            "noisestart": ["Noise Start", "Nse Start"],
            "noiserand": ["Noise Rand", "Nse Rand"],

            "filteron": ["Filter On", "Fil On", "Flt On"],
            "filtertype": ["Filter Type", "Fil Type", "Flt Type"],
            "filtercutoff": ["Cutoff", "Filter Cutoff", "Fil Cutoff", "Flt Cutoff", "Filter Freq", "Fil Freq", "Frequency"],
            "filterresonance": ["Res", "Reso", "Resonance", "Filter Res", "Fil Res", "Filter Resonance", "Flt Res"],
            "filterdrive": ["Filter Drive", "Fil Drive", "Flt Drive", "Drive"],
            "filterfat": ["Filter Fat", "Fil Fat", "Flt Fat", "Fat"],
            "filtermix": ["Filter Mix", "Fil Mix", "Flt Mix"],
            "filterpan": ["Filter Pan", "Fil Pan"],
            "filterkeytrack": ["Filter Keytrack", "Fil Keytrack", "Keytrack"],
            "filtera": ["Filter A", "Fil A", "A to Filter", "Osc A Filter"],
            "filterb": ["Filter B", "Fil B", "B to Filter", "Osc B Filter"],
            "filterc": ["Filter C", "Fil C", "C to Filter", "Osc C Filter"],
            "filternoise": ["Filter Noise", "Fil Noise", "Noise to Filter"],
            "filtersub": ["Filter Sub", "Fil Sub", "Sub to Filter"],

            "env1attack": ["Env1 Atk", "Env 1 Atk", "Env1 Attack", "Env 1 Attack", "Amp Attack", "Attack"],
            "env1hold": ["Env1 Hold", "Env 1 Hold", "Hold"],
            "env1decay": ["Env1 Dec", "Env 1 Dec", "Env1 Decay", "Env 1 Decay", "Decay"],
            "env1sustain": ["Env1 Sus", "Env 1 Sus", "Env1 Sustain", "Env 1 Sustain", "Sustain"],
            "env1release": ["Env1 Rel", "Env 1 Rel", "Env1 Release", "Env 1 Release", "Amp Release", "Release"],
            "env2attack": ["Env2 Atk", "Env 2 Atk", "Env2 Attack", "Env 2 Attack"],
            "env2hold": ["Env2 Hold", "Env 2 Hold"],
            "env2decay": ["Env2 Dec", "Env 2 Dec", "Env2 Decay", "Env 2 Decay"],
            "env2sustain": ["Env2 Sus", "Env 2 Sus", "Env2 Sustain", "Env 2 Sustain"],
            "env2release": ["Env2 Rel", "Env 2 Rel", "Env2 Release", "Env 2 Release"],
            "env3attack": ["Env3 Atk", "Env 3 Atk", "Env3 Attack", "Env 3 Attack"],
            "env3decay": ["Env3 Dec", "Env 3 Dec", "Env3 Decay", "Env 3 Decay"],
            "env3sustain": ["Env3 Sus", "Env 3 Sus", "Env3 Sustain", "Env 3 Sustain"],
            "env3release": ["Env3 Rel", "Env 3 Rel", "Env3 Release", "Env 3 Release"],

            "lfo1rate": ["LFO1 Rate", "LFO 1 Rate", "LFO1 Speed", "LFO 1 Speed"],
            "lfo1rise": ["LFO1 Rise", "LFO 1 Rise"],
            "lfo1delay": ["LFO1 Delay", "LFO 1 Delay"],
            "lfo1smooth": ["LFO1 Smooth", "LFO 1 Smooth"],
            "lfo2rate": ["LFO2 Rate", "LFO 2 Rate", "LFO2 Speed", "LFO 2 Speed"],
            "lfo3rate": ["LFO3 Rate", "LFO 3 Rate"],
            "lfo4rate": ["LFO4 Rate", "LFO 4 Rate"],
            "lfo5rate": ["LFO5 Rate", "LFO 5 Rate"],
            "lfo6rate": ["LFO6 Rate", "LFO 6 Rate"],

            "distortionon": ["Dist On", "Distortion On", "Dist Enable"],
            "distortiondrive": ["Dist Drive", "Distortion Drive", "Drive"],
            "distortionmix": ["Dist Mix", "Distortion Mix", "Dist Wet"],
            "distortiontone": ["Dist Tone", "Distortion Tone"],
            "hyperon": ["Hyper On"], "hypermix": ["Hyper Mix"], "hyperdetune": ["Hyper Detune", "Hyp Det"],
            "dimensionon": ["Dimension On", "Dim On"], "dimensionsize": ["Dimension Size", "Dim Size"], "dimensionmix": ["Dimension Mix", "Dim Mix"],
            "choruson": ["Chorus On", "Cho On"],
            "chorusmix": ["Chorus Mix", "Cho Mix", "Chorus Wet", "Cho Wet"],
            "chorusdepth": ["Chorus Depth", "Cho Depth"],
            "chorusrate": ["Chorus Rate", "Cho Rate"],
            "chorusdelay": ["Chorus Delay", "Cho Delay"],
            "chorusfeedback": ["Chorus Feedback", "Cho Feedback", "Cho FB"],
            "delayon": ["Delay On", "Dly On"],
            "delaymix": ["Delay Mix", "Dly Mix", "Delay Wet", "Dly Wet"],
            "delaytime": ["Delay Time", "Dly Time"],
            "delaytimeleft": ["Delay Time Left", "Dly L", "Delay Left"],
            "delaytimeright": ["Delay Time Right", "Dly R", "Delay Right"],
            "delayfeedback": ["Delay Feedback", "Dly Feedback", "Dly FB"],
            "delaypingpong": ["Delay Ping Pong", "Delay PingPong", "Dly PingPong", "Dly Ping Pong"],
            "delaywidth": ["Delay Width", "Dly Width"],
            "reverbon": ["Reverb On", "Verb On", "Rev On"],
            "reverbmix": ["Reverb Mix", "Verb Mix", "Rev Mix", "Reverb Wet", "Verb Wet", "Rev Wet"],
            "reverbsize": ["Reverb Size", "Verb Size", "Rev Size"],
            "reverbdecay": ["Reverb Decay", "Verb Decay", "Rev Decay"],
            "reverblowcut": ["Reverb Low Cut", "Verb Low Cut", "Rev Low Cut"],
            "reverbhighcut": ["Reverb High Cut", "Verb High Cut", "Rev High Cut"],
            "compressoron": ["Compressor On", "Comp On"],
            "compressorgain": ["Compressor Gain", "Comp Gain"],
            "compressormix": ["Compressor Mix", "Comp Mix"],
            "compressormultiband": ["Compressor Multiband", "Comp MB", "Multiband"],
            "eqon": ["EQ On", "Equalizer On"],
            "eqhighshelfgain": ["EQ High Shelf Gain", "EQ High Gain", "High Shelf Gain", "High Gain"],
            "eqhighshelffreq": ["EQ High Shelf Freq", "EQ High Freq", "High Shelf Freq", "High Freq"],
            "mastervolume": ["MasterVol", "Master Vol", "Master Volume", "Output", "Output Volume", "Volume"],
            "polyphony": ["Poly", "Polyphony", "Voices"],
            "portamento": ["Porta", "Portamento", "Glide"],
            "mono": ["Mono"], "legato": ["Legato"]
        ]
        var aliases = map[compact] ?? []
        if compact.hasPrefix("macro"), let number = Int(compact.dropFirst("macro".count)) {
            aliases += ["Macro \(number)", "Macro\(number)", "Perf Macro \(number)", "Perform Macro \(number)"]
        }
        aliases.append(canonical)
        aliases.append(raw)
        return aliases
    }

    private static func crossSynthAliasCandidates(for raw: String) -> [String] {
        let canonical = DeviceTranslationLayer.normalizeParameterName(raw)
        let compact = compactSearchText(canonical)
        let shared: [String: [String]] = [
            // Macro/performance systems: Vital macros, Phase Plant macros, Omnisphere/ORB, Sylenth mod controls.
            "macro1": ["Macro 1", "Macro1", "M1", "Performance Macro 1", "Perform Macro 1", "Orb", "Omni Macro 1"],
            "macro2": ["Macro 2", "Macro2", "M2", "Performance Macro 2", "Perform Macro 2", "Omni Macro 2"],
            "macro3": ["Macro 3", "Macro3", "M3", "Performance Macro 3", "Perform Macro 3", "Omni Macro 3"],
            "macro4": ["Macro 4", "Macro4", "M4", "Performance Macro 4", "Perform Macro 4", "Omni Macro 4"],
            "macro5": ["Macro 5", "Macro5", "M5", "Performance Macro 5", "Perform Macro 5"],
            "macro6": ["Macro 6", "Macro6", "M6", "Performance Macro 6", "Perform Macro 6"],
            "macro7": ["Macro 7", "Macro7", "M7", "Performance Macro 7", "Perform Macro 7"],
            "macro8": ["Macro 8", "Macro8", "M8", "Performance Macro 8", "Perform Macro 8"],

            // Oscillators across Vital/Phase Plant/Sylenth/Omnisphere.
            "oscalevel": ["Osc 1 Level", "Oscillator 1 Level", "OSC1 Volume", "Osc1 Vol", "Part A Level", "Layer A Level", "Source 1 Level", "Generator 1 Level", "Oscillator A Volume"],
            "oscblevel": ["Osc 2 Level", "Oscillator 2 Level", "OSC2 Volume", "Osc2 Vol", "Part B Level", "Layer B Level", "Source 2 Level", "Generator 2 Level", "Oscillator B Volume"],
            "oscawtpos": ["Wavetable Position", "WT Position", "Wave Position", "Frame", "Osc 1 Position", "Oscillator 1 WT Pos", "Wavetable 1 Position"],
            "oscbwtpos": ["Osc 2 Position", "Oscillator 2 WT Pos", "Wavetable 2 Position", "Wave 2 Position"],
            "oscaunison": ["Unison Voices", "Voice Count", "Osc 1 Unison", "Oscillator 1 Unison", "Unison 1"],
            "oscadetune": ["Unison Detune", "Osc 1 Detune", "Oscillator 1 Detune", "Detune 1", "Spread Detune"],
            "oscbdetune": ["Osc 2 Detune", "Oscillator 2 Detune", "Detune 2"],

            // Filters. Vital and Sylenth often use Filter 1; Omnisphere often uses Layer/Part Filter.
            "filtercutoff": ["Filter 1 Cutoff", "Filter1 Cutoff", "Filter Freq", "Filter Frequency", "Cutoff 1", "LP Cutoff", "Layer A Filter Cutoff", "Part Filter Cutoff", "VCF Cutoff"],
            "filterresonance": ["Filter 1 Resonance", "Filter1 Resonance", "Filter Q", "Cutoff Resonance", "Resonance 1", "VCF Resonance"],
            "filterdrive": ["Filter 1 Drive", "Filter Drive", "Filter Saturation", "VCF Drive"],
            "filterenvamount": ["Filter Env Amount", "Env To Filter", "Env->Filter", "Mod Env To Filter", "Filter Mod Amount", "ENV1 Filter", "ENV2 Filter", "Contour Amount"],
            "env2filtercutoff": ["Env To Cutoff", "Envelope To Cutoff", "Mod Env To Cutoff", "Filter Envelope Amount"],

            // ADSR labels.
            "env1attack": ["Amp Env Attack", "Amplitude Attack", "Volume Env Attack", "ENV1 Attack", "Envelope 1 Attack", "Attack 1", "A Attack"],
            "env1decay": ["Amp Env Decay", "Amplitude Decay", "Volume Env Decay", "ENV1 Decay", "Envelope 1 Decay", "Decay 1", "A Decay"],
            "env1sustain": ["Amp Env Sustain", "Amplitude Sustain", "Volume Env Sustain", "ENV1 Sustain", "Envelope 1 Sustain", "Sustain 1", "A Sustain"],
            "env1release": ["Amp Env Release", "Amplitude Release", "Volume Env Release", "ENV1 Release", "Envelope 1 Release", "Release 1", "A Release"],
            "env2attack": ["Mod Env Attack", "Filter Env Attack", "ENV2 Attack", "Envelope 2 Attack"],
            "env2decay": ["Mod Env Decay", "Filter Env Decay", "ENV2 Decay", "Envelope 2 Decay"],
            "env2sustain": ["Mod Env Sustain", "Filter Env Sustain", "ENV2 Sustain", "Envelope 2 Sustain"],
            "env2release": ["Mod Env Release", "Filter Env Release", "ENV2 Release", "Envelope 2 Release"],

            // Common FX blocks.
            "chorusmix": ["Chorus Wet", "Chorus Mix", "Chorus Amount", "Ensemble Mix"],
            "reverbmix": ["Reverb Wet", "Reverb Mix", "Reverb Amount", "Space Amount", "Verb Wet"],
            "delaymix": ["Delay Wet", "Delay Mix", "Echo Wet", "Echo Mix"],
            "tremolomix": ["Tremolo Mix", "Tremolo Depth", "Trem Amount", "Amp Tremolo", "Amplitude Modulation"],
            "tremolorate": ["Tremolo Rate", "Trem Rate", "Amp Tremolo Rate", "Amplitude Mod Rate"],
            "lfo1amplevel": ["LFO 1 Amp", "LFO1 Amp", "LFO 1 Volume", "LFO 1 -> Amp", "LFO 1 -> Amp Level"],
            "distortiondrive": ["Distortion Drive", "Drive", "Saturation", "Tube Drive", "Overdrive"],
            "mastervolume": ["Master Volume", "Output Gain", "Output Level", "Main Volume", "Volume", "Level"],
            "portamento": ["Glide", "Portamento", "Porta Time"],
            "polyphony": ["Polyphony", "Voices", "Voice Limit"]
        ]
        var aliases = shared[compact] ?? []
        if compact.hasPrefix("macro"), let number = Int(compact.dropFirst("macro".count)) {
            aliases += ["Macro \(number)", "Macro\(number)", "M\(number)", "Performance Macro \(number)", "Perform Macro \(number)"]
        }
        aliases.append(canonical)
        aliases.append(raw)
        return aliases
    }

    private static func bestSerumFuzzyParameter(for raw: String, in tree: AUParameterTree) -> AUParameter? {
        let normalized = compactSearchText(DeviceTranslationLayer.normalizeParameterName(raw))
        guard normalized.count >= 4 else { return nil }
        var best: (param: AUParameter, score: Int)? = nil
        for param in tree.allParameters {
            let hay = compactParameterText(param)
            var score = 0
            if hay == normalized { score += 100 }
            if hay.contains(normalized) || normalized.contains(hay) { score += 70 }
            for token in serumTokens(from: normalized) where hay.contains(token) { score += max(4, token.count) }
            if score > (best?.score ?? 0) { best = (param, score) }
        }
        guard let result = best, result.score >= 14 else { return nil }
        return result.param
    }

    private static func serumTokens(from compact: String) -> [String] {
        var tokens: [String] = []
        let dictionary = ["osc", "osca", "oscb", "oscc", "sub", "noise", "filter", "fil", "cutoff", "res", "drive", "fat", "mix", "env1", "env2", "env3", "attack", "decay", "sustain", "release", "lfo1", "rate", "dist", "chorus", "delay", "reverb", "verb", "eq", "high", "gain", "master", "volume", "poly", "porta", "glide", "macro", "wavetable", "unison", "detune", "amp", "mod", "filter1"]
        for word in dictionary where compact.contains(word) { tokens.append(word) }
        return tokens
    }

    private func findMacroParameter(number: Int, in tree: AUParameterTree) -> AUParameter? {
        guard number >= 1, number <= 32 else { return nil }
        let wanted = String(number)
        let macroCandidates = tree.allParameters.filter { param in
            let hay = Self.compactParameterText(param)
            return hay.contains("macro") || hay.contains("perform")
        }
        if let exact = macroCandidates.first(where: { param in
            let hay = Self.compactParameterText(param)
            return hay == "macro\(wanted)" || hay == "macro0\(wanted)" || hay == "performmacro\(wanted)"
        }) { return exact }
        return macroCandidates.first { param in
            let hay = Self.compactParameterText(param)
            return hay.contains("macro\(wanted)") || hay.contains("macro0\(wanted)") || hay.contains("performmacro\(wanted)") || hay.contains("mac\(wanted)")
        }
    }

    private static func macroNumber(from raw: String) -> Int? {
        let compact = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        let prefixes = ["macro", "mac", "performancemacro", "performmacro"]
        for prefix in prefixes where compact.hasPrefix(prefix) {
            let tail = compact.dropFirst(prefix.count)
            if let n = Int(tail), n > 0 { return n }
        }
        return nil
    }

    private static func compactParameterText(_ param: AUParameter) -> String {
        [param.displayName, param.identifier]
            .joined(separator: " ")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func scaledValue(_ raw: Double, for param: AUParameter) -> AUValue {
        let minV = Double(param.minValue)
        let maxV = Double(param.maxValue)
        let range = maxV - minV
        let value: Double
        if raw >= 0, raw <= 1, range > 1.0001, !(minV == 0 && maxV == 1) {
            value = minV + raw * range
        } else {
            value = raw
        }
        return AUValue(min(max(value, minV), maxV))
    }

    private static let parameterAliases: [String: [String]] = [
        "cutoff": ["cutoff", "filter cutoff", "flt cutoff", "filter freq", "frequency"],
        "filter cutoff": ["cutoff", "filter cutoff", "fil cutoff", "flt cutoff", "filter freq", "frequency"],
        "resonance": ["resonance", "reso", "q"],
        "filter resonance": ["resonance", "reso", "q"],
        "attack": ["attack", "env attack", "env1 attack", "amp attack"],
        "env attack": ["attack", "env attack", "env1 attack", "amp attack"],
        "decay": ["decay", "env decay", "env1 decay"],
        "sustain": ["sustain", "env sustain", "env1 sustain"],
        "release": ["release", "env release", "env1 release", "amp release"],
        "env release": ["release", "env release", "env1 release", "amp release"],
        "volume": ["volume", "level", "master", "output", "mastervol"],
        "level": ["volume", "level", "master", "output"],
        "filtercutoff": ["cutoff", "filter cutoff", "fil cutoff", "flt cutoff", "filter freq", "freq"],
        "osc a level": ["osc a level", "osc a vol", "a vol", "a volume", "osc a", "oscillator a level", "osc 1 level", "osc1 level", "a level"],
        "osc b level": ["osc b level", "osc b vol", "b vol", "b volume", "osc b", "oscillator b level", "osc 2 level", "osc2 level", "b level"],
        "osc a wt pos": ["wt pos", "wtpos", "wavetable pos", "osc a wt", "osc a wtpos", "a wtpos", "osc 1 wt"],
        "osc b wt pos": ["osc b wt", "osc b wtpos", "b wtpos", "osc 2 wt", "wavetable pos"],
        "env 1 attack": ["env 1 attack", "env1 attack", "env1 atk", "env 1 atk", "amp attack", "attack", "atk"],
        "env 1 decay": ["env 1 decay", "env1 decay", "env1 dec", "env 1 dec", "decay", "dec"],
        "env 1 sustain": ["env 1 sustain", "env1 sustain", "env1 sus", "env 1 sus", "sustain", "sus"],
        "env 1 release": ["env 1 release", "env1 release", "env1 rel", "env 1 rel", "amp release", "release", "rel"],
        "lfo 1 rate": ["lfo 1 rate", "lfo1 rate", "lfo speed", "rate"],
        "distortion drive": ["drive", "distortion drive", "dist drive", "distortion drv", "dist drv"],
        "reverb mix": ["reverb mix", "reverb wet", "verb mix", "verb wet", "rev wet"],
        "delay mix": ["delay mix", "delay wet", "echo mix", "echo wet"],
        "chorus mix": ["chorus mix", "chorus wet"],
        "filter drive": ["filter drive", "fil drive", "flt drive"],
        "osc a unison": ["osc a unison", "a unison", "unison", "uni"],
        "osc a detune": ["osc a detune", "a detune", "detune", "det"],
        "sub level": ["sub level", "sub vol", "sub volume"],
        "noise level": ["noise level", "noise vol", "noise volume"],
        "env 2 decay": ["env 2 decay", "env2 decay", "env2 dec", "env 2 dec"],
        "env 2 -> filter cutoff": ["env 2 filter cutoff", "env2 filter cutoff", "env2 fil cutoff", "filter env", "filter envelope"],
        "filter env amount": ["filter env amount", "env amt", "env amount", "mod amount"],
        "master volume": ["master volume", "mastervol", "master vol", "out volume", "output"]
    ]


    // MARK: Host automation surface

    /// Expose AU parameters to Lemmings automation lanes. Parameter IDs are the
    /// AUParameter address strings, which are stable for host automation and also
    /// work well for third-party plug-ins such as Serum, Neutron, Ozone, etc.
    public var automatableParams: [ParamInfo] {
        guard let tree = au.parameterTree else { return [] }
        return tree.allParameters.map { p in
            let name = p.displayName.isEmpty ? p.identifier : p.displayName
            return ParamInfo(String(p.address), name, Double(p.minValue), Double(p.maxValue))
        }
    }

    public func setParam(_ id: String, _ value: Double) {
        guard let tree = au.parameterTree else { return }
        let param: AUParameter?
        if let address = AUParameterAddress(id) {
            param = tree.parameter(withAddress: address) ?? findParameter(named: id, in: tree)
        } else {
            param = findParameter(named: id, in: tree)
        }
        guard let p = param else { return }
        _ = setLiveParameter(p, to: scaledValue(value, for: p))
    }

    public func getParam(_ id: String) -> Double {
        guard let tree = au.parameterTree else { return 0 }
        if let address = AUParameterAddress(id), let p = tree.parameter(withAddress: address) { return Double(p.value) }
        if let p = findParameter(named: id, in: tree) { return Double(p.value) }
        return 0
    }

    public func renderStereo(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) -> Bool {
        guard ready, let render = renderBlock else { return false }
        abl[0].mNumberChannels = 1; abl[0].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size); abl[0].mData = UnsafeMutableRawPointer(left)
        abl[1].mNumberChannels = 1; abl[1].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size); abl[1].mData = UnsafeMutableRawPointer(right)
        var ts = AudioTimeStamp(); ts.mSampleTime = sampleTime; ts.mFlags = .sampleTimeValid
        var flags = AudioUnitRenderActionFlags()
        let status = render(&flags, &ts, AUAudioFrameCount(frames), 0, abl.unsafeMutablePointer, nil)
        sampleTime += Float64(frames)
        if status != noErr { for i in 0..<frames { left[i] = 0; right[i] = 0 }; return true }
        return true
    }

    public func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        // Mono fallback: render stereo into scratch and downmix.
        let L = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let R = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { L.deallocate(); R.deallocate() }
        _ = renderStereo(left: L, right: R, frames: frames)
        for i in 0..<frames { out[i] = (L[i] + R[i]) * 0.5 }
    }

    public func noteOn(_ note: Int, velocity: Float) { noteOn(note, velocity: velocity, channel: 0) }
    public func noteOff(_ note: Int) { noteOff(note, channel: 0) }

    public func noteOn(_ note: Int, velocity: Float, channel: Int) {
        let v = UInt8(max(1, min(127, Int(velocity * 127))))
        sendMIDI([UInt8(0x90) | UInt8(channel & 0x0F), UInt8(note & 0x7F), v])
    }
    public func noteOff(_ note: Int, channel: Int) {
        sendMIDI([UInt8(0x80) | UInt8(channel & 0x0F), UInt8(note & 0x7F), 0])
    }

    public func pitchBend(_ value: Float, channel: Int, rangeSemitones: Int) {
        // Assumes the plug-in's bend range is configured to match the app setting.
        // MPE synths like Serum 2 will usually handle this per channel.
        let clamped = max(-1, min(1, value))
        let raw = max(0, min(16383, Int((clamped + 1.0) * 8192.0)))
        let lsb = UInt8(raw & 0x7F)
        let msb = UInt8((raw >> 7) & 0x7F)
        sendMIDI([UInt8(0xE0) | UInt8(channel & 0x0F), lsb, msb])
    }

    public func pressure(_ value: Float, note: Int?, channel: Int) {
        let v = UInt8(max(0, min(127, Int(value * 127))))
        if let note { sendMIDI([UInt8(0xA0) | UInt8(channel & 0x0F), UInt8(note & 0x7F), v]) }
        else { sendMIDI([UInt8(0xD0) | UInt8(channel & 0x0F), v]) }
    }

    public func timbre(_ value: Float, channel: Int) {
        let v = UInt8(max(0, min(127, Int(value * 127))))
        sendMIDI([UInt8(0xB0) | UInt8(channel & 0x0F), 74, v])
    }

    public func allNotesOff() {
        for ch in 0..<16 { sendMIDI([UInt8(0xB0) | UInt8(ch), 123, 0]) }
    }

    private func sendMIDI(_ bytes: [UInt8]) {
        guard let block = midiBlock else { return }
        bytes.withUnsafeBufferPointer { buf in
            block(AUEventSampleTimeImmediate, 0, buf.count, buf.baseAddress!)
        }
    }
}


// MARK: - Hosted Audio Unit effect

/// Native AU effect host used for third-party insert effects (for example
/// iZotope Neutron/Ozone, FabFilter, Soundtoys, etc.). This gives external AU
/// effects the same automation contract as stock devices: automation lanes push
/// values into the live AU through scheduleParameterBlock before the block is
/// rendered.
public final class HostedAUAudioEffect: AudioEffect {
    private let musicalClock = HostedMusicalClock()
    public func setTransport(bpm: Double, beat: Double, playing: Bool, timelineSeconds: Double? = nil) { musicalClock.update(bpm: bpm, beat: beat, playing: playing, timelineSeconds: timelineSeconds) }
    public var hostedAudioUnit: AUAudioUnit { au }
    public func capturedPresetStateBase64() -> String? {
        guard let state=au.fullStateForDocument ?? au.fullState, let data=try? PropertyListSerialization.data(fromPropertyList:state,format:.binary,options:0) else {return nil};return data.base64EncodedString()
    }
    public func restorePresetStateBase64(_ value:String?) {
        guard let value,let data=Data(base64Encoded:value),let state=try? PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any] else {return};au.fullState=state
    }
    public let kind: DeviceKind = .externalAudioEffect
    public var bypassed: Bool = false
    public let name: String

    private let au: AUAudioUnit
    private let avUnit: AVAudioUnit?
    private let sampleRate: Double
    private var sampleTime: Float64 = 0
    private var abl: UnsafeMutableAudioBufferListPointer
    private var inputABL: UnsafeMutableAudioBufferListPointer
    private var renderBlock: AURenderBlock?
    public private(set) var ready = false

    public init?(pluginName: String, sampleRate: Double, maxFrames: Int = 4096, componentDescription: AudioComponentDescription? = nil) {
        self.name = pluginName
        self.sampleRate = sampleRate
        self.abl = AudioBufferList.allocate(maximumBuffers: 2)
        self.inputABL = AudioBufferList.allocate(maximumBuffers: 2)
        guard let desc = componentDescription ?? Self.description(forPluginNamed: pluginName) else {
            free(self.abl.unsafeMutablePointer)
            free(self.inputABL.unsafeMutablePointer)
            return nil
        }
        do {
            if let wrapper = HostedAUInstrument.instantiateComponentSynchronously(desc, preferOutOfProcess: true) {
                self.avUnit = wrapper
                self.au = wrapper.auAudioUnit
            } else {
                let unit = try AUAudioUnit(componentDescription: desc)
                self.avUnit = nil
                self.au = unit
            }
            let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
            if self.au.inputBusses.count > 0 { try self.au.inputBusses[0].setFormat(fmt) }
            if self.au.outputBusses.count > 0 { try self.au.outputBusses[0].setFormat(fmt) }
            self.au.maximumFramesToRender = AUAudioFrameCount(maxFrames)
            try self.au.allocateRenderResources()
            self.renderBlock = self.au.renderBlock
            musicalClock.install(on: self.au, sampleRate: sampleRate)
            self.ready = true
        } catch {
            free(self.abl.unsafeMutablePointer)
            free(self.inputABL.unsafeMutablePointer)
            return nil
        }
    }

    deinit {
        free(abl.unsafeMutablePointer)
        free(inputABL.unsafeMutablePointer)
    }

    private static func description(forPluginNamed name: String) -> AudioComponentDescription? {
        let types: [OSType] = [kAudioUnitType_Effect, kAudioUnitType_MusicEffect]
        let requested = compactPluginName(name)
        for type in types {
            var d = AudioComponentDescription()
            d.componentType = type
            let comps = AVAudioUnitComponentManager.shared().components(matching: d)
            if let hit = comps.first(where: { component in
                let raw = component.name.lowercased()
                let compact = compactPluginName(component.name)
                return raw == name.lowercased()
                    || raw.contains(name.lowercased())
                    || compact == requested
                    || compact.contains(requested)
                    || requested.contains(compact)
            }) { return hit.audioComponentDescription }
        }
        return nil
    }

    private static func compactPluginName(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "audio unit", with: "")
            .replacingOccurrences(of: "vst3", with: "")
            .replacingOccurrences(of: "vst", with: "")
            .replacingOccurrences(of: "au", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    public var automatableParams: [ParamInfo] {
        guard let tree = au.parameterTree else { return [] }
        return tree.allParameters.map { p in
            let label = p.displayName.isEmpty ? p.identifier : p.displayName
            return ParamInfo(String(p.address), label, Double(p.minValue), Double(p.maxValue))
        }
    }

    public func setParam(_ id: String, _ value: Double) {
        guard let tree = au.parameterTree else { return }
        let param: AUParameter?
        if let address = AUParameterAddress(id) {
            param = tree.parameter(withAddress: address) ?? findParameter(named: id, in: tree)
        } else {
            param = findParameter(named: id, in: tree)
        }
        guard let p = param else { return }
        let clamped = AUValue(min(max(Float(value), p.minValue), p.maxValue))
        au.scheduleParameterBlock(AUEventSampleTimeImmediate, 0, p.address, clamped)
        p.setValue(clamped, originator: nil)
        p.value = clamped
    }

    public func getParam(_ id: String) -> Double {
        guard let tree = au.parameterTree else { return 0 }
        if let address = AUParameterAddress(id), let p = tree.parameter(withAddress: address) { return Double(p.value) }
        if let p = findParameter(named: id, in: tree) { return Double(p.value) }
        return 0
    }

    private func findParameter(named key: String, in tree: AUParameterTree) -> AUParameter? {
        if let address = AUParameterAddress(key), let p = tree.parameter(withAddress: address) { return p }
        let needle = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = tree.allParameters.first(where: { $0.displayName.lowercased() == needle || $0.identifier.lowercased() == needle }) { return exact }
        let compact = needle.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
        return tree.allParameters.first(where: {
            let dn = $0.displayName.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
            let id = $0.identifier.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
            return dn.contains(compact) || id.contains(compact)
        })
    }

    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard ready, !bypassed, let render = renderBlock else { return }
        inputABL[0].mNumberChannels = 1
        inputABL[0].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
        inputABL[0].mData = UnsafeMutableRawPointer(left)
        inputABL[1].mNumberChannels = 1
        inputABL[1].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
        inputABL[1].mData = UnsafeMutableRawPointer(right)

        abl[0].mNumberChannels = 1
        abl[0].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
        abl[0].mData = UnsafeMutableRawPointer(left)
        abl[1].mNumberChannels = 1
        abl[1].mDataByteSize = UInt32(frames * MemoryLayout<Float>.size)
        abl[1].mData = UnsafeMutableRawPointer(right)

        let input: AURenderPullInputBlock = { [inputABL] _, _, frameCount, _, outData in
            let dst = UnsafeMutableAudioBufferListPointer(outData)
            let src = inputABL
            for b in 0..<min(dst.count, src.count) {
                dst[b].mNumberChannels = src[b].mNumberChannels
                dst[b].mDataByteSize = min(dst[b].mDataByteSize, UInt32(Int(frameCount) * MemoryLayout<Float>.size))
                if let d = dst[b].mData, let s = src[b].mData {
                    memcpy(d, s, Int(dst[b].mDataByteSize))
                }
            }
            return noErr
        }
        var ts = AudioTimeStamp()
        ts.mSampleTime = sampleTime
        ts.mFlags = .sampleTimeValid
        var flags = AudioUnitRenderActionFlags()
        let status = render(&flags, &ts, AUAudioFrameCount(frames), 0, abl.unsafeMutablePointer, input)
        sampleTime += Float64(frames)
        if status != noErr { return }
    }

    public func reset() { sampleTime = 0 }
}

#endif
