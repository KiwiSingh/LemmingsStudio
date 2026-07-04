import Foundation

public struct DeviceTranslationRequest: Codable, Sendable {
    public var userIntent: String
    public var trackName: String
    public var deviceName: String
    public var parameters: [String: Double]
    public var availableParameters: [String]
}

public struct DeviceParameterChange: Codable, Hashable, Sendable {
    public var deviceID: String
    public var parameterID: String
    public var value: Double
    public var reason: String
}

public enum DeviceTranslationLayer {
    public static func describe(track: Track, device: DeviceModel, userIntent: String) -> String {
        let params = DeviceFactory.make(from: device, sampleRate: 44100).automatableParams.map { p in
            "- \(p.id): \(p.name), range \(p.min)...\(p.max) \(p.unit)"
        }.joined(separator: "\n")
        return """
        You are controlling LemmingsStudio, a DAW. Translate the user's musical intent into conservative parameter changes only.
        Track: \(track.name)
        Device: \(device.kind.rawValue)
        Current parameters: \(device.params)
        Available parameters:\n\(params)
        User intent: \(userIntent)
        Return JSON array of {deviceID, parameterID, value, reason}. Keep values inside allowed ranges.
        """
    }

    public static func apply(_ changes: [DeviceParameterChange], to track: Track) {
        for change in changes {
            guard let device = track.devices.first(where: { $0.nodeID == change.deviceID }) else { continue }
            device.params[change.parameterID] = change.value
        }
    }
}


// MARK: - Agentic plug-in parameter normalization

extension DeviceTranslationLayer {
    /// Claude/LLMs often know Serum-style names but reply with wildly different JSON shapes:
    /// `{params:{...}}`, `{serum:{filter_cutoff:0.4}}`, arrays of `{name,value}`, etc.
    /// This flattens those responses into the same `[parameter: value]` map the AU target layer uses.
    public static func normalizedPluginParams(from object: [String: Any]) -> [String: Double] {
        var out: [String: Double] = [:]
        let preferredKeys = [
            "params", "parameters", "pluginParams", "plugin_parameters",
            "serum", "serum2", "serum_2", "serumParameters", "serum_parameters",
            "au", "audioUnit", "audio_unit", "macros", "macroControls", "controls"
        ]
        for key in preferredKeys {
            if let value = object[key] { collect(value, prefix: nil, into: &out) }
        }
        if out.isEmpty { collect(object, prefix: nil, into: &out) }
        var normalized: [String: Double] = [:]
        for (key, value) in out {
            let k = normalizeParameterName(key)
            normalized[k] = clampLikelyNormalized(value)
            normalized[key] = value
        }
        return normalized
    }

    /// Converts any semantic plug-in parameter names into stable Carla macro slots.
    /// Carla VST/VST3 metadata is not available to Lemmings until the plug-in is
    /// running, so semantic Serum names must be sent as macros instead of being
    /// dropped as "unnamed controls".
    public static func carlaMacroParams(from params: [String: Double], limit: Int = 8) -> [String: Double] {
        var out: [String: Double] = [:]
        var macroIndex = 1
        for key in params.keys.sorted() {
            guard macroIndex <= max(1, limit) else { break }
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("macro_") || lower.hasPrefix("macro ") || lower.hasPrefix("param_") || lower.hasPrefix("parameter_") || Int(lower) != nil {
                out[trimmed] = params[key] ?? 0
            } else {
                out["macro_\(macroIndex)"] = params[key] ?? 0
                macroIndex += 1
            }
        }
        return out
    }

    /// Last-resort musical macro recipe used when a model replies with broad prose
    /// like "make a wide supersaw pluck" without enumerating any knobs. This keeps
    /// agentic AI from reporting a fake success with zero actionable controls.
    public static func fallbackMacroParams(from intent: String, targetName: String? = nil) -> [String: Double] {
        let lower = (intent + " " + (targetName ?? "")).lowercased()
        var out: [String: Double] = [:]
        func put(_ idx: Int, _ value: Double) { out["macro_\(idx)"] = max(0, min(1, value)) }

        if lower.contains("pluck") || lower.contains("stab") {
            put(1, 0.30)   // cutoff / brightness
            put(2, 0.18)   // decay
            put(3, 0.05)   // sustain
            put(4, 0.22)   // release
        } else if lower.contains("pad") || lower.contains("ambient") || lower.contains("lush") {
            put(1, 0.62)
            put(2, 0.58)
            put(3, 0.72)
            put(4, 0.66)
        } else if lower.contains("bass") || lower.contains("acid") || lower.contains("wobble") {
            put(1, 0.36)
            put(2, lower.contains("acid") ? 0.72 : 0.44)
            put(3, 0.54)
            put(4, 0.28)
        } else {
            put(1, 0.55)
            put(2, 0.35)
            put(3, 0.50)
            put(4, 0.40)
        }

        if lower.contains("wide") || lower.contains("supersaw") || lower.contains("unison") { put(5, 0.74) }
        if lower.contains("detune") || lower.contains("chorus") { put(6, 0.38) }
        if lower.contains("reverb") || lower.contains("space") { put(7, 0.32) }
        if lower.contains("delay") || lower.contains("echo") { put(8, 0.26) }
        return out
    }

    private static func collect(_ value: Any, prefix: String?, into out: inout [String: Double]) {
        if let dict = value as? [String: Any] {
            if let name = (dict["parameter"] ?? dict["param"] ?? dict["id"] ?? dict["name"]) as? String,
               let v = numeric(dict["value"] ?? dict["amount"] ?? dict["normalized"] ?? dict["target"]) {
                out[prefix.map { "\($0).\(name)" } ?? name] = v
            }
            for (key, sub) in dict {
                guard !["reason", "notes", "description", "presetName", "preset_name", "explanation"].contains(key) else { continue }
                if let v = numeric(sub) { out[prefix.map { "\($0).\(key)" } ?? key] = v }
                else { collect(sub, prefix: prefix.map { "\($0).\(key)" } ?? key, into: &out) }
            }
        } else if let arr = value as? [Any] {
            for item in arr { collect(item, prefix: prefix, into: &out) }
        }
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let f = value as? Float { return Double(f) }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String {
            let cleaned = s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = Double(cleaned) { return s.contains("%") ? d / 100.0 : d }
        }
        return nil
    }

    private static func clampLikelyNormalized(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    public static func normalizeParameterName(_ raw: String) -> String {
        let base = raw
            .replacingOccurrences(of: "serum2.", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "serum.", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "plugin.", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let compact = base.replacingOccurrences(of: " ", with: "")
        let aliases: [String: String] = [
            "filtercutoff": "Filter Cutoff", "cutoff": "Filter Cutoff", "filcutoff": "Filter Cutoff", "fltcutoff": "Filter Cutoff",
            "filterresonance": "Filter Resonance", "resonance": "Filter Resonance", "reso": "Filter Resonance",
            "oscalevel": "Osc A Level", "osc1level": "Osc A Level", "oscillator1level": "Osc A Level", "oscavolume": "Osc A Level",
            "oscaunison": "Osc A Unison", "osc1unison": "Osc A Unison", "unison": "Osc A Unison",
            "oscadetune": "Osc A Detune", "osc1detune": "Osc A Detune", "detune": "Osc A Detune",
            "oscawave": "Osc A Wave", "osc1wave": "Osc A Wave", "oscawarp": "Osc A Warp", "oscawarpmode": "Osc A Warp Mode",
            "oscblevel": "Osc B Level", "osc2level": "Osc B Level", "oscillator2level": "Osc B Level", "oscbvolume": "Osc B Level",
            "oscbwave": "Osc B Wave", "osc2wave": "Osc B Wave", "oscbsemitone": "Osc B Semitone", "osc2semitone": "Osc B Semitone",
            "oscawtpos": "Osc A WT Pos", "osc1wavetableposition": "Osc A WT Pos", "wavetableposition": "Osc A WT Pos",
            "oscbwtpos": "Osc B WT Pos", "osc2wavetableposition": "Osc B WT Pos",
            "env1attack": "Env 1 Attack", "ampattack": "Env 1 Attack", "attack": "Env 1 Attack",
            "env1decay": "Env 1 Decay", "decay": "Env 1 Decay",
            "env1sustain": "Env 1 Sustain", "sustain": "Env 1 Sustain",
            "env1release": "Env 1 Release", "amprelease": "Env 1 Release", "release": "Env 1 Release",
            "env1hold": "Env 1 Hold", "hold": "Env 1 Hold",
            "env2attack": "Env 2 Attack", "env2decay": "Env 2 Decay", "env2sustain": "Env 2 Sustain", "env2release": "Env 2 Release",
            "env2filtercutoff": "Env 2 -> Filter Cutoff", "filterenvamount": "Filter Env Amount",
            "lfospeed": "LFO 1 Rate", "lfo1rate": "LFO 1 Rate", "lfo1speed": "LFO 1 Rate",
            "mastervolume": "Master Volume", "volume": "Master Volume", "level": "Master Volume",
            "distortiondrive": "Distortion Drive", "drive": "Distortion Drive",
            "reverbmix": "Reverb Mix", "reverbdecay": "Reverb Decay", "reverbon": "Reverb On",
            "delaymix": "Delay Mix", "delayfeedback": "Delay Feedback", "delaytime": "Delay Time", "delaypingpong": "Delay Ping Pong", "delayon": "Delay On",
            "chorusmix": "Chorus Mix", "chorusdepth": "Chorus Depth", "chorusrate": "Chorus Rate", "chorusdelay": "Chorus Delay", "choruson": "Chorus On",
            "tremolomix": "Tremolo Mix", "tremoloon": "Tremolo On", "lfo1amplevel": "LFO 1 -> Amp Level", "lfo1amp": "LFO 1 -> Amp Level",
            "sublevel": "Sub Level", "suboctave": "Sub Octave",
            "filtertype": "Filter Type", "filterdrive": "Filter Drive", "velocityfilterenv": "Velocity -> Filter Env",
            "eqhighshelfgain": "EQ High Shelf Gain", "eqhighshelffreq": "EQ High Shelf Freq",
            "lfo1oscawtpos": "LFO 1 -> Osc A WT Pos", "distortionon": "Distortion On", "polypohny": "Polyphony", "polyphony": "Polyphony"
        ]
        return aliases[compact] ?? raw
    }

    /// Claude often answers Serum/Serum 2 requests with a prose recipe instead of JSON.
    /// This conservative parser extracts the common synth-design phrases from that prose
    /// and turns them into the same semantic parameter names the AU-hosting layer can map.
    public static func normalizedPluginParams(fromNaturalLanguage text: String, targetName: String? = nil) -> [String: Double] {
        let lower = text.lowercased()
        guard lower.contains("osc") || lower.contains("env") || lower.contains("filter") || lower.contains("cutoff") || lower.contains("reson") || lower.contains("serum") || lower.contains("synth") || lower.contains("wavetable") || lower.contains("supersaw") || lower.contains("saw") || lower.contains("pluck") || lower.contains("bass") || lower.contains("pad") || lower.contains("key") || lower.contains("keys") || lower.contains("piano") || lower.contains("rhodes") || lower.contains("wurli") || lower.contains("wurlitzer") || lower.contains("epiano") || lower.contains("e-piano") || lower.contains("electric piano") || lower.contains("tine") || lower.contains("reverb") || lower.contains("delay") || lower.contains("chorus") || lower.contains("tremolo") || lower.contains("lfo") || lower.contains("macro") else { return [:] }
        var out: [String: Double] = [:]
        func put(_ key: String, _ value: Double) { out[normalizeParameterName(key)] = value }
        func has(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }

        // Generic labelled-line parsing first: handles prose from Claude, Ollama,
        // local uncensored models, and copy/pasted recipes such as
        // "Filter cutoff: 35%" or "Macro 1 = 0.62".
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let cleaned = line
                .replacingOccurrences(of: "•", with: "")
                .replacingOccurrences(of: "- ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let separators = [":", "=", "→", "->"]
            for sep in separators where cleaned.contains(sep) {
                let parts = cleaned.components(separatedBy: sep)
                guard parts.count >= 2 else { continue }
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let rest = parts.dropFirst().joined(separator: sep)
                guard name.count >= 3 else { continue }
                if let value = valueFromLabelledText(rest, fallbackLine: cleaned) {
                    put(name, value)
                }
                // Natural-language model replies usually say things like
                // "Oscillator A: sine/triangle body" or "Amp envelope: fast attack,
                // medium decay, low sustain" rather than giving numeric values.
                // Treat those labelled prose lines as real patch instructions instead of
                // falling back to a generic sound-family preset.
                for (semanticKey, semanticValue) in semanticValuesFromLabelledText(name: name, body: rest, fullLine: cleaned) {
                    put(semanticKey, semanticValue)
                }
                break
            }
        }

        // Whole-paragraph prose parsing. Some providers return a Markdown recipe
        // without clean labels; still pull out the musical intent.
        for (semanticKey, semanticValue) in semanticValuesFromUnlabelledProse(lower: lower) {
            put(semanticKey, semanticValue)
        }

        // Oscillator / wavetable intent.
        if has(["saw", "saw/square", "saw square"]) {
            put("Osc A Wave", 0.75)
            put("Osc A WT Pos", lower.contains("square") ? 0.62 : 0.72)
        }
        if has(["basic shapes", "analog_bd_sin", "basic wavetable"]) { put("Osc A WT Pos", out["Osc A WT Pos"] ?? 0.72) }
        if let unison = firstNumber(in: lower, near: ["unison", "voices"]) { put("Osc A Unison", min(max(unison, 1), 16)) }
        else if lower.contains("unison") { put("Osc A Unison", 4) }
        if let detune = firstNumber(in: lower, near: ["detune"]) { put("Osc A Detune", detune > 1 ? detune / 100.0 : detune) }
        else if lower.contains("detune") { put("Osc A Detune", 0.20) }
        if lower.contains("sync") { put("Osc A Warp Mode", 1.0); put("Osc A Warp", 0.18) }

        if lower.contains("osc b") || lower.contains("oscillator b") {
            if has(["sine", "triangle", "bell sheen", "glassy"]) { put("Osc B Wave", lower.contains("triangle") ? 0.35 : 0.15) }
            put("Osc B Level", lower.contains("30") || lower.contains("40") ? 0.35 : 0.28)
            if lower.contains("+12") || lower.contains("12 semitone") || lower.contains("octave") { put("Osc B Semitone", 12) }
        }
        if lower.contains("sub osc") || lower.contains("sub oscillator") || lower.contains("sub") {
            put("Sub Level", lower.contains("low level") ? 0.16 : 0.22)
            if lower.contains("−12") || lower.contains("-12") { put("Sub Octave", -1) }
        }

        // Amp envelope (Env 1). Times are kept roughly normalized/seconds-ish; the AU layer
        // still maps them into the target's reported parameter range when needed.
        if let attack = valueNear(labelCandidates: ["attack"], in: text, defaultUnit: .milliseconds) { put("Env 1 Attack", attack) }
        else if lower.contains("instant attack") || lower.contains("0 ms") { put("Env 1 Attack", 0.0) }
        if let decay = valueNear(labelCandidates: ["decay"], in: text, defaultUnit: .milliseconds) { put("Env 1 Decay", decay) }
        else if lower.contains("pluck") { put("Env 1 Decay", 0.24) }
        if let sustain = valueNear(labelCandidates: ["sustain"], in: text, defaultUnit: .percent) { put("Env 1 Sustain", sustain) }
        else if lower.contains("no sustain") || lower.contains("0 sustain") { put("Env 1 Sustain", 0.0) }
        if let release = valueNear(labelCandidates: ["release"], in: text, defaultUnit: .milliseconds) { put("Env 1 Release", release) }
        else if lower.contains("pluck") { put("Env 1 Release", 0.15) }
        if lower.contains("hold") { put("Env 1 Hold", valueNear(labelCandidates: ["hold"], in: text, defaultUnit: .milliseconds) ?? 0.0) }

        // Filter and modulation-envelope intent.
        if lower.contains("lp 12") { put("Filter Type", 0.25) }
        if lower.contains("lp 24") || lower.contains("lowpass") { put("Filter Type", lower.contains("lp 12") ? 0.25 : 0.35) }
        if lower.contains("base cutoff") || lower.contains("fairly low") { put("Filter Cutoff", 0.28) }
        if let res = valueNear(labelCandidates: ["resonance", "reso"], in: text, defaultUnit: .percent) { put("Filter Resonance", res) }
        else if lower.contains("touch of resonance") { put("Filter Resonance", 0.20) }
        if lower.contains("env 2") || lower.contains("filter cutoff") {
            put("Env 2 Attack", 0.0)
            if let d = valueNear(labelCandidates: ["env 2", "decay"], in: text, defaultUnit: .milliseconds) { put("Env 2 Decay", d) }
            else { put("Env 2 Decay", 0.14) }
            put("Env 2 Sustain", 0.0)
            put("Env 2 -> Filter Cutoff", 0.68)
            put("Filter Env Amount", 0.68)
        }
        if lower.contains("velocity") && lower.contains("filter") { put("Velocity -> Filter Env", 0.35) }

        // FX rack.
        if lower.contains("rhodes") || lower.contains("electric piano") || lower.contains("e-piano") || lower.contains("epiano") || lower.contains("wurli") || lower.contains("wurlitzer") || lower.contains("tine") {
            put("Osc A WT Pos", 0.0); put("Osc A Level", 0.76); put("Osc A Unison", 1.0); put("Osc A Detune", 0.012)
            put("Osc B On", 1.0); put("Osc B Level", 0.14); put("Osc B WT Pos", 0.0); put("Osc B Semitone", 12.0)
            put("Filter Cutoff", 0.64); put("Filter Resonance", 0.10); put("Filter Env Amount", 0.18)
            put("Env 1 Attack", 0.006); put("Env 1 Decay", 0.56); put("Env 1 Sustain", 0.26); put("Env 1 Release", 0.42)
            put("Chorus On", 1.0); put("Chorus Mix", 0.28); put("Chorus Depth", 0.38); put("Chorus Rate", 0.12)
            put("Tremolo On", 1.0); put("Tremolo Mix", 0.18); put("Tremolo Rate", 0.24); put("LFO 1 Rate", 0.20); put("LFO 1 -> Amp Level", 0.12)
            put("Reverb On", 1.0); put("Reverb Mix", 0.20); put("Reverb Decay", 0.46); put("Delay On", 1.0); put("Delay Mix", 0.06)
        }
        if lower.contains("chorus") { put("Chorus Mix", 0.34); put("Chorus Depth", 0.55); put("Chorus On", 1.0) }
        if lower.contains("reverb") { put("Reverb Mix", valueNear(labelCandidates: ["wet"], in: text, defaultUnit: .percent) ?? 0.28); put("Reverb Decay", lower.contains("medium decay") ? 0.55 : 0.45); put("Reverb On", 1.0) }
        if lower.contains("delay") { put("Delay Mix", 0.24); put("Delay Feedback", valueNear(labelCandidates: ["feedback"], in: text, defaultUnit: .percent) ?? 0.30); put("Delay Time", lower.contains("dotted") || lower.contains("3/16") ? 0.375 : 0.25); put("Delay Ping Pong", lower.contains("ping-pong") || lower.contains("ping pong") ? 1.0 : 0.0); put("Delay On", 1.0) }
        if lower.contains("drive") || lower.contains("saturation") || lower.contains("distortion") { put("Distortion Drive", 0.22); put("Distortion On", 1.0) }
        if lower.contains("high-shelf") || lower.contains("high shelf") || lower.contains("air") { put("EQ High Shelf Gain", 0.58); put("EQ High Shelf Freq", 0.74) }
        if lower.contains("lfo") && lower.contains("wavetable") { put("LFO 1 Rate", lower.contains("slow") ? 0.18 : 0.32); put("LFO 1 -> Osc A WT Pos", lower.contains("subtle") ? 0.12 : 0.22) }

        // Style-level recipes. These are not just macros: they intentionally use
        // Serum-style direct controls so the AU layer can hit real exposed params
        // such as Fil Cutoff / Env1 Dec / A WTPos when Serum publishes them.
        // Serum/Serum 2 agent layer: deliberately broad static control recipe.
        // Serum 2 does not publish every internal/dynamic FX parameter to the host
        // until the user exposes it, but the agent should still reason in the full
        // Serum vocabulary and then let AUHosting hit every exposed match it can find.
        if looksLikeSerumIntent(lower, targetName: targetName) {
            for (k, v) in serumStaticRecipeParams(fromLowercaseIntent: lower) {
                put(k, v)
            }
        }
        return out
    }

    public static var serumAgentParameterReference: String {
        serumCanonicalParameterNames.joined(separator: ", ")
    }

    public static let serumCanonicalParameterNames: [String] = [
        "Osc A On", "Osc A Level", "Osc A Pan", "Osc A WT Pos", "Osc A Unison", "Osc A Detune", "Osc A Blend", "Osc A Phase", "Osc A Rand", "Osc A Warp", "Osc A Warp Mode", "Osc A Octave", "Osc A Semitone", "Osc A Fine",
        "Osc B On", "Osc B Level", "Osc B Pan", "Osc B WT Pos", "Osc B Unison", "Osc B Detune", "Osc B Blend", "Osc B Phase", "Osc B Rand", "Osc B Warp", "Osc B Warp Mode", "Osc B Octave", "Osc B Semitone", "Osc B Fine",
        "Osc C On", "Osc C Level", "Osc C Pan", "Osc C WT Pos", "Osc C Unison", "Osc C Detune", "Osc C Blend", "Osc C Phase", "Osc C Rand", "Osc C Warp", "Osc C Warp Mode", "Osc C Octave", "Osc C Semitone", "Osc C Fine",
        "Sub On", "Sub Level", "Sub Pan", "Sub Octave", "Sub Wave", "Noise On", "Noise Level", "Noise Pan", "Noise Pitch", "Noise Fine", "Noise Start", "Noise Rand",
        "Filter On", "Filter Type", "Filter Cutoff", "Filter Resonance", "Filter Drive", "Filter Fat", "Filter Mix", "Filter Pan", "Filter Keytrack", "Filter A", "Filter B", "Filter C", "Filter Noise", "Filter Sub",
        "Env 1 Attack", "Env 1 Hold", "Env 1 Decay", "Env 1 Sustain", "Env 1 Release", "Env 2 Attack", "Env 2 Hold", "Env 2 Decay", "Env 2 Sustain", "Env 2 Release", "Env 3 Attack", "Env 3 Hold", "Env 3 Decay", "Env 3 Sustain", "Env 3 Release",
        "LFO 1 Rate", "LFO 1 Rise", "LFO 1 Delay", "LFO 1 Smooth", "LFO 1 BPM", "LFO 2 Rate", "LFO 2 Rise", "LFO 2 Delay", "LFO 2 Smooth", "LFO 3 Rate", "LFO 4 Rate", "LFO 5 Rate", "LFO 6 Rate",
        "Env 2 -> Filter Cutoff", "Filter Env Amount", "Velocity -> Filter Env", "Velocity -> Amp", "LFO 1 -> Osc A WT Pos", "LFO 1 -> Filter Cutoff", "LFO 1 -> Fine Pitch",
        "Distortion On", "Distortion Type", "Distortion Drive", "Distortion Mix", "Distortion Tone", "Distortion PrePost",
        "Hyper On", "Hyper Mix", "Hyper Rate", "Hyper Detune", "Dimension On", "Dimension Size", "Dimension Mix",
        "Chorus On", "Chorus Mix", "Chorus Depth", "Chorus Rate", "Chorus Delay", "Chorus Feedback", "Chorus LPF",
        "Delay On", "Delay Mix", "Delay Time", "Delay Time Left", "Delay Time Right", "Delay Feedback", "Delay Ping Pong", "Delay Filter", "Delay Width",
        "Reverb On", "Reverb Mix", "Reverb Size", "Reverb Decay", "Reverb Low Cut", "Reverb High Cut", "Reverb Damp", "Reverb Width",
        "Compressor On", "Compressor Threshold", "Compressor Ratio", "Compressor Attack", "Compressor Release", "Compressor Gain", "Compressor Mix", "Compressor Multiband",
        "EQ On", "EQ Low Freq", "EQ Low Gain", "EQ Mid Freq", "EQ Mid Gain", "EQ Mid Q", "EQ High Freq", "EQ High Gain", "EQ High Shelf Gain", "EQ High Shelf Freq",
        "Phaser On", "Phaser Mix", "Phaser Rate", "Phaser Depth", "Flanger On", "Flanger Mix", "Flanger Rate", "Flanger Depth", "Filter FX On", "Filter FX Cutoff", "Filter FX Resonance",
        "Tremolo On", "Tremolo Mix", "Tremolo Rate", "Tremolo Depth", "LFO 1 -> Amp Level",
        "Macro 1", "Macro 2", "Macro 3", "Macro 4", "Macro 5", "Macro 6", "Macro 7", "Macro 8", "Master Volume", "Polyphony", "Portamento", "Mono", "Legato"
    ]

    private static func looksLikeSerumIntent(_ lower: String, targetName: String?) -> Bool {
        let target = (targetName ?? "").lowercased()
        return target.contains("serum") || target.contains("vital") || target.contains("phase plant") || target.contains("phaseplant") || target.contains("sylenth") || target.contains("omnisphere") || lower.contains("serum") || lower.contains("vital") || lower.contains("phase plant") || lower.contains("sylenth") || lower.contains("omnisphere") || lower.contains("synth") || lower.contains("pluck") || lower.contains("pad") || lower.contains("bass") || lower.contains("808") || lower.contains("keys") || lower.contains("piano") || lower.contains("rhodes") || lower.contains("electric piano") || lower.contains("epiano") || lower.contains("e-piano") || lower.contains("wurli") || lower.contains("wurlitzer") || lower.contains("tine") || lower.contains("lead") || lower.contains("supersaw") || lower.contains("synthwave") || lower.contains("80s") || lower.contains("'80s") || lower.contains("80's")
    }

    private enum AgentSoundFamily { case pluck, lead, supersaw, festivalBass, bass, sub808, electricPiano, keys, pad, stab, generic }

    private static func agentSoundFamily(from lower: String) -> AgentSoundFamily {
        if lower.contains("808") || lower.contains("sub bass") || lower.contains("sub-bass") { return .sub808 }
        if lower.contains("supersaw") || lower.contains("super saw") || lower.contains("festival saw") || lower.contains("anthem saw") { return .supersaw }
        if lower.contains("pluck") || lower.contains("plucky") { return .pluck }
        if lower.contains("stab") { return .stab }
        if lower.contains("rhodes") || lower.contains("electric piano") || lower.contains("e-piano") || lower.contains("epiano") || lower.contains("wurli") || lower.contains("wurlitzer") || lower.contains("tine") || lower.contains("dx7 piano") || lower.contains("fm piano") { return .electricPiano }
        if lower.contains("key") || lower.contains("keys") || lower.contains("chord") || lower.contains("piano") { return .keys }
        if looksLikeFestivalBass(lower) { return .festivalBass }
        if lower.contains("bass") || lower.contains("reese") || lower.contains("acid") || lower.contains("donk") { return .bass }
        if lower.contains("pad") || lower.contains("ambient") || lower.contains("lush") || lower.contains("wash") { return .pad }
        if lower.contains("lead") || lower.contains("solo") || lower.contains("hook") { return .lead }
        return .generic
    }

    private static func looksLikeFestivalBass(_ lower: String) -> Bool {
        guard lower.contains("bass") else { return false }
        return lower.contains("tiesto") || lower.contains("tiësto") || lower.contains("epic") || lower.contains("festival") || lower.contains("progressive") || lower.contains("prog house") || lower.contains("big room") || lower.contains("edm") || lower.contains("trance") || lower.contains("anthem") || lower.contains("mainstage")
    }

    private struct EnvelopeRecipe { var attack: Double; var hold: Double; var decay: Double; var sustain: Double; var release: Double; var filterDecay: Double; var filterAmount: Double }

    private static func envelopeRecipe(for family: AgentSoundFamily) -> EnvelopeRecipe {
        switch family {
        case .pluck:
            // Short, audible synth pluck. Not click-length.
            return EnvelopeRecipe(attack: 0.014, hold: 0.035, decay: 0.42, sustain: 0.15, release: 0.30, filterDecay: 0.36, filterAmount: 0.44)
        case .stab:
            return EnvelopeRecipe(attack: 0.010, hold: 0.045, decay: 0.34, sustain: 0.25, release: 0.20, filterDecay: 0.28, filterAmount: 0.36)
        case .lead:
            return EnvelopeRecipe(attack: 0.020, hold: 0.020, decay: 0.26, sustain: 0.72, release: 0.34, filterDecay: 0.34, filterAmount: 0.24)
        case .supersaw:
            return EnvelopeRecipe(attack: 0.030, hold: 0.015, decay: 0.32, sustain: 0.82, release: 0.42, filterDecay: 0.42, filterAmount: 0.28)
        case .festivalBass:
            // Mainstage/progressive house bass: saw-forward body, strong sustain, tight but not clicky.
            return EnvelopeRecipe(attack: 0.004, hold: 0.025, decay: 0.22, sustain: 0.82, release: 0.11, filterDecay: 0.22, filterAmount: 0.20)
        case .bass:
            return EnvelopeRecipe(attack: 0.006, hold: 0.020, decay: 0.30, sustain: 0.60, release: 0.16, filterDecay: 0.24, filterAmount: 0.30)
        case .sub808:
            return EnvelopeRecipe(attack: 0.004, hold: 0.020, decay: 0.68, sustain: 0.36, release: 0.38, filterDecay: 0.16, filterAmount: 0.12)
        case .electricPiano:
            // Rhodes/Wurli style: percussive tine attack, decaying body, playable release.
            return EnvelopeRecipe(attack: 0.006, hold: 0.010, decay: 0.56, sustain: 0.26, release: 0.42, filterDecay: 0.44, filterAmount: 0.18)
        case .keys:
            return EnvelopeRecipe(attack: 0.012, hold: 0.018, decay: 0.48, sustain: 0.36, release: 0.28, filterDecay: 0.38, filterAmount: 0.30)
        case .pad:
            return EnvelopeRecipe(attack: 0.24, hold: 0.020, decay: 0.78, sustain: 0.78, release: 0.70, filterDecay: 0.62, filterAmount: 0.24)
        case .generic:
            return EnvelopeRecipe(attack: 0.018, hold: 0.015, decay: 0.36, sustain: 0.55, release: 0.34, filterDecay: 0.34, filterAmount: 0.28)
        }
    }

    /// Honest caveat for timbres whose character lives in the oscillator's
    /// WAVETABLE (or FM/warp mode) — which Serum/Vital/etc. do NOT expose as
    /// host-automatable parameters. We can shape envelope/octave/FX, but we can't
    /// load the core wavetable via automation, so we tell the user instead of
    /// shipping a sine-with-FX and calling it a Rhodes.
    public static func wavetableTimbreCaveat(intent: String, targetName: String?) -> String? {
        let lower = intent.lowercased()
        guard looksLikeSerumIntent(lower, targetName: targetName) else { return nil }
        let tableDependent = ["rhodes", "wurli", "wurlitzer", "electric piano", "e-piano", "epiano",
                              "tine", "acoustic piano", "grand piano", "real piano", "fm piano",
                              "dx7", "dx-7", "bell", "organ", "choir", "guitar", "strings",
                              "brass", "sax", "flute", "vocal"].contains { lower.contains($0) }
        guard tableDependent else { return nil }
        return "Heads-up: this timbre's character lives in the oscillator's wavetable (and FM/warp mode), which Serum/Vital don't expose as host-automatable parameters. LemmingsStudio dialed in everything it CAN control from the host — sine-leaning oscillator, tine octave, amp envelope, tremolo, chorus, reverb — but for an authentic result, load an electric-piano/FM (or matching) wavetable, or start from a suitable preset, inside the plug-in. Parameter automation alone can't swap the core wavetable."
    }

    private static func serumStaticRecipeParams(fromLowercaseIntent lower: String) -> [String: Double] {
        var out: [String: Double] = [:]
        func put(_ key: String, _ value: Double) { out[key] = value }
        let family = agentSoundFamily(from: lower)
        let env = envelopeRecipe(for: family)
        let isPluck = family == .pluck || family == .stab
        let isSynthwave = lower.contains("synthwave") || lower.contains("80s") || lower.contains("'80s") || lower.contains("80's") || lower.contains("retro")
        let isBass = family == .bass || family == .festivalBass || family == .sub808
        let isPad = family == .pad
        let isLead = family == .lead
        let isSupersaw = family == .supersaw
        let isFestivalBass = family == .festivalBass
        let isElectricPiano = family == .electricPiano
        let isKeys = family == .keys || isElectricPiano
        let wide = lower.contains("wide") || isSupersaw || isSynthwave

        // Broad static synth vocabulary. AUHosting will write only the exposed host params.
        put("Osc A On", 1.0)
        put("Osc A Level", isBass ? 0.90 : (isPluck ? 0.86 : (isElectricPiano ? 0.76 : 0.82)))
        // Festival/progressive bass should be saw-forward and weighty, not the hollow Basic Shapes square slot.
        // Rhodes/e-piano should sit near sine/triangle territory, not Init/default saw/square.
        put("Osc A WT Pos", family == .sub808 ? 0.08 : (isFestivalBass ? 0.70 : (family == .bass ? 0.52 : (isElectricPiano ? 0.0 : (isSynthwave ? 0.62 : (isKeys ? 0.45 : 0.55))))))
        put("Osc A Unison", isFestivalBass ? 2.0 : (isElectricPiano ? 1.0 : (isSupersaw ? 7.0 : (wide ? (isPluck ? 3.0 : 5.0) : 1.0))))
        put("Osc A Detune", isFestivalBass ? 0.045 : (isElectricPiano ? 0.012 : (isSupersaw ? 0.22 : (wide ? (isPluck ? 0.08 : 0.16) : 0.04))))
        put("Osc A Blend", isBass ? 0.46 : 0.70)
        put("Osc A Phase", 0.50)
        put("Osc A Rand", isPluck || family == .sub808 ? 0.0 : 0.32)
        put("Osc A Pan", 0.50)

        if isSynthwave || wide || isLead || isKeys {
            put("Osc B On", 1.0)
            put("Osc B Level", isPluck ? 0.18 : (isElectricPiano ? 0.14 : (isKeys ? 0.22 : 0.38)))
            put("Osc B WT Pos", isElectricPiano ? 0.12 : (isKeys ? 0.38 : 0.58))
            put("Osc B Semitone", isLead ? 7.0 : (isElectricPiano ? 12.0 : (isKeys ? 12.0 : 12.0)))
            put("Osc B Unison", isElectricPiano ? 1.0 : (isSupersaw ? 5.0 : (wide ? 3.0 : 1.0)))
            put("Osc B Detune", isElectricPiano ? 0.006 : (isSupersaw ? 0.16 : (wide ? 0.10 : 0.03)))
            put("Osc B Rand", isPluck || isElectricPiano ? 0.0 : 0.28)
        } else if isBass {
            put("Osc B On", 1.0)
            put("Osc B Level", family == .sub808 ? 0.18 : (isFestivalBass ? 0.18 : 0.28))
            put("Osc B WT Pos", family == .sub808 ? 0.08 : (isFestivalBass ? 0.58 : 0.32))
            put("Osc B Semitone", isFestivalBass ? 0.0 : -12.0)
            put("Osc B Detune", isFestivalBass ? 0.025 : 0.0)
        }

        if isBass {
            put("Sub On", 1.0); put("Sub Level", family == .sub808 ? 0.70 : (isFestivalBass ? 0.34 : 0.46)); put("Sub Octave", -1.0)
        } else if isPluck || isSynthwave || isKeys {
            put("Sub On", 1.0); put("Sub Level", isKeys ? 0.08 : 0.12); put("Sub Octave", -1.0)
        }

        if lower.contains("noise") || lower.contains("air") || lower.contains("breath") || lower.contains("vinyl") {
            put("Noise On", 1.0); put("Noise Level", isPluck ? 0.025 : (isKeys ? 0.035 : 0.08)); put("Noise Pitch", 0.42)
        } else if !isElectricPiano {
            // For Rhodes/e-piano patches, do not send a redundant Noise Off automation
            // request. Many hosts do not expose boolean FX/source toggles and the skipped
            // knob list made successful patches look broken.
            put("Noise On", 0.0); put("Noise Level", 0.0)
        }

        put("Filter On", 1.0)
        put("Filter Type", isBass ? 0.30 : 0.35)
        switch family {
        case .pluck, .stab: put("Filter Cutoff", 0.54)
        case .lead: put("Filter Cutoff", 0.62)
        case .supersaw: put("Filter Cutoff", 0.68)
        case .festivalBass: put("Filter Cutoff", 0.48)
        case .bass: put("Filter Cutoff", 0.36)
        case .sub808: put("Filter Cutoff", 0.28)
        case .electricPiano: put("Filter Cutoff", 0.64)
        case .keys: put("Filter Cutoff", 0.58)
        case .pad: put("Filter Cutoff", 0.56)
        case .generic: put("Filter Cutoff", 0.50)
        }
        put("Filter Resonance", isElectricPiano ? 0.10 : (isFestivalBass ? 0.10 : (isPluck ? 0.14 : (isBass ? 0.12 : 0.16))))
        put("Filter Drive", isElectricPiano ? 0.08 : (isFestivalBass ? 0.24 : (isBass ? 0.30 : (isPluck ? 0.14 : 0.18))))
        put("Filter Fat", isElectricPiano ? 0.05 : (isFestivalBass ? 0.18 : (isBass ? 0.24 : 0.12)))
        put("Filter Mix", 1.0)
        put("Filter A", 1.0); put("Filter B", (isSynthwave || isSupersaw || isKeys) ? 0.65 : 0.0); put("Filter Noise", lower.contains("noise") ? 1.0 : 0.0)

        put("Env 1 Attack", env.attack)
        put("Env 1 Hold", env.hold)
        put("Env 1 Decay", env.decay)
        put("Env 1 Sustain", env.sustain)
        put("Env 1 Release", env.release)
        put("Env 2 Attack", family == .pad ? 0.08 : 0.0)
        put("Env 2 Hold", 0.0)
        put("Env 2 Decay", env.filterDecay)
        put("Env 2 Sustain", family == .pad ? 0.25 : 0.0)
        put("Env 2 Release", max(0.12, env.release * 0.65))
        put("Env 2 -> Filter Cutoff", env.filterAmount)
        put("Filter Env Amount", env.filterAmount)
        put("Velocity -> Filter Env", isKeys ? 0.34 : 0.24)
        if !isElectricPiano {
            put("Velocity -> Amp", isKeys ? 0.32 : 0.18)
        }

        if wide || isSynthwave || isKeys {
            put("Chorus On", 1.0); put("Chorus Mix", isElectricPiano ? 0.28 : (isKeys ? 0.22 : 0.30)); put("Chorus Depth", isElectricPiano ? 0.38 : 0.44); put("Chorus Rate", isElectricPiano ? 0.12 : 0.18); put("Chorus Delay", isElectricPiano ? 0.34 : 0.28)
            if !isElectricPiano {
                put("Hyper On", isKeys ? 0.0 : 1.0); put("Hyper Mix", isKeys ? 0.0 : 0.18); put("Hyper Detune", 0.22)
            }
            put("Dimension On", 1.0); put("Dimension Mix", isElectricPiano ? 0.08 : (isKeys ? 0.12 : 0.18)); put("Dimension Size", isElectricPiano ? 0.42 : 0.55)
        }
        if isSynthwave || lower.contains("delay") || lower.contains("echo") || isLead || (isKeys && !isElectricPiano) {
            put("Delay On", 1.0); put("Delay Mix", isPluck ? 0.14 : (isKeys ? 0.12 : 0.24)); put("Delay Feedback", 0.24); put("Delay Ping Pong", 1.0); put("Delay Time", 0.375); put("Delay Width", 0.70)
        }
        if isSynthwave || lower.contains("reverb") || lower.contains("space") || isPad || isKeys {
            put("Reverb On", 1.0); put("Reverb Mix", isPluck ? 0.20 : (isElectricPiano ? 0.20 : (isKeys ? 0.18 : 0.36))); put("Reverb Decay", isPluck ? 0.42 : (isElectricPiano ? 0.46 : (isKeys ? 0.38 : 0.62))); put("Reverb Size", isElectricPiano ? 0.48 : 0.56); put("Reverb Low Cut", 0.20); put("Reverb High Cut", 0.74)
        }
        if isBass || lower.contains("drive") || lower.contains("saturation") || isSynthwave || isKeys {
            put("Distortion On", 1.0); put("Distortion Drive", isFestivalBass ? 0.22 : (isBass ? 0.36 : (isElectricPiano ? 0.07 : (isKeys ? 0.10 : 0.18)))); put("Distortion Mix", isFestivalBass ? 0.26 : (isBass ? 0.42 : (isElectricPiano ? 0.10 : (isKeys ? 0.12 : 0.20)))); put("Distortion Tone", isFestivalBass ? 0.48 : 0.55)
        }
        put("EQ On", 1.0)
        put("EQ High Shelf Gain", isSynthwave ? 0.58 : (isBass ? 0.42 : 0.52))
        put("EQ High Shelf Freq", 0.72)
        if isPluck { put("LFO 1 Rate", 0.25); put("LFO 1 -> Osc A WT Pos", 0.10) }
        if isElectricPiano {
            // Rhodes-style movement: gentle tremolo/amp LFO + chorus. Hosts that do not expose
            // these params simply skip them, but the recipe is still much less Init-like.
            put("Tremolo On", 1.0); put("Tremolo Mix", 0.18); put("Tremolo Rate", 0.24); put("Tremolo Depth", 0.22)
            put("LFO 1 Rate", 0.20); put("LFO 1 -> Amp Level", 0.12)
            put("Macro 1", 0.62); put("Macro 2", 0.28); put("Macro 3", 0.30); put("Macro 4", 0.18); put("Macro 5", 0.40); put("Macro 6", 0.64); put("Macro 7", 0.20); put("Macro 8", 0.70)
        }
        put("Master Volume", isFestivalBass ? 0.74 : (isBass ? 0.78 : (isElectricPiano ? 0.70 : 0.72)))
        put("Polyphony", isBass ? 1.0 : (family == .sub808 ? 1.0 : (isSupersaw ? 10.0 : 8.0)))
        put("Mono", isBass ? 1.0 : 0.0)
        put("Legato", isLead && lower.contains("legato") ? 1.0 : 0.0)
        put("Portamento", isFestivalBass ? 0.035 : ((isLead || isBass) && (lower.contains("glide") || lower.contains("porta") || lower.contains("808")) ? 0.16 : 0.0))
        if isFestivalBass {
            // Eight macro slots give Carla/VST fallback and macro-first synths a usable musical target.
            put("Macro 1", 0.48) // cutoff/body
            put("Macro 2", 0.22) // drive/grit
            put("Macro 3", 0.16) // detune/width, kept tight for bass
            put("Macro 4", 0.10) // release/tail
            put("Macro 5", 0.34) // sub weight
            put("Macro 6", 0.18) // movement
            put("Macro 7", 0.06) // space, nearly dry
            put("Macro 8", 0.74) // output
        }
        return out
    }

    private enum NaturalUnit { case normalized, percent, milliseconds }

    /// Final guardrail for Serum/Serum 2. LLMs and broad static maps tend to
    /// overdo the textbook "pluck = instant attack, zero sustain, tiny decay" idea.
    /// In Serum AU automation space that collapses the amp envelope and leaves only
    /// a noise/filter tick. This pass keeps plucks short but audible and protects
    /// the oscillator body from being buried by noise or an over-closed filter.
    /// Final guardrail for Serum/Vital/Phase Plant/Sylenth/Omnisphere-style agents.
    /// The agent is allowed to use a broad static vocabulary, but envelopes must stay musical.
    /// This pass prevents collapsed blips and gives each requested sound family sensible ADSR.
    public static func repairSerumMusicality(_ params: inout [String: Double], intent: String, targetName: String? = nil) {
        let lower = intent.lowercased()
        guard looksLikeSerumIntent(lower, targetName: targetName) else { return }
        let family = agentSoundFamily(from: lower)
        let env = envelopeRecipe(for: family)

        func set(_ key: String, _ value: Double) { params[normalizeParameterName(key)] = min(max(value, 0.0), 1.0) }
        func raise(_ key: String, to floor: Double) {
            let n = normalizeParameterName(key)
            params[n] = max(params[n] ?? floor, floor)
        }
        func cap(_ key: String, to ceiling: Double) {
            let n = normalizeParameterName(key)
            params[n] = min(params[n] ?? ceiling, ceiling)
        }
        func putIfMissing(_ key: String, _ value: Double) {
            let n = normalizeParameterName(key)
            if params[n] == nil { params[n] = value }
        }

        // Fill missing envelopes and repair unsafe model output. The floors here are
        // intentionally normalized-AU-space, not literal seconds, because each vendor
        // exposes time knobs on its own curve.
        putIfMissing("Env 1 Attack", env.attack)
        putIfMissing("Env 1 Hold", env.hold)
        putIfMissing("Env 1 Decay", env.decay)
        putIfMissing("Env 1 Sustain", env.sustain)
        putIfMissing("Env 1 Release", env.release)
        putIfMissing("Env 2 Decay", env.filterDecay)
        putIfMissing("Filter Env Amount", env.filterAmount)
        putIfMissing("Env 2 -> Filter Cutoff", env.filterAmount)

        switch family {
        case .pluck, .stab:
            raise("Osc A Level", to: 0.78)
            raise("Filter Cutoff", to: 0.50)
            cap("Filter Resonance", to: 0.22)
            cap("Filter Env Amount", to: 0.50)
            cap("Env 2 -> Filter Cutoff", to: 0.50)
            raise("Env 1 Attack", to: 0.012)
            raise("Env 1 Hold", to: 0.030)
            raise("Env 1 Decay", to: 0.38)
            raise("Env 1 Sustain", to: 0.12)
            raise("Env 1 Release", to: 0.28)
            raise("Env 2 Decay", to: 0.30)
            raise("Env 2 Release", to: 0.18)
            cap("Reverb Mix", to: 0.22)
            cap("Delay Mix", to: 0.16)
        case .lead:
            raise("Env 1 Sustain", to: 0.62)
            raise("Env 1 Release", to: 0.24)
            raise("Filter Cutoff", to: 0.54)
        case .supersaw:
            raise("Env 1 Sustain", to: 0.74)
            raise("Env 1 Release", to: 0.34)
            raise("Osc A Unison", to: 5.0)
            raise("Filter Cutoff", to: 0.62)
        case .festivalBass:
            // Prevent the "epic bass" path from landing on a hollow square blip.
            raise("Osc A Level", to: 0.84)
            raise("Osc A WT Pos", to: 0.62)
            cap("Osc A Unison", to: 3.0)
            cap("Osc A Detune", to: 0.08)
            cap("Osc B Level", to: 0.28)
            raise("Sub Level", to: 0.28)
            raise("Filter Cutoff", to: 0.42)
            cap("Filter Resonance", to: 0.18)
            cap("Filter Env Amount", to: 0.30)
            raise("Env 1 Sustain", to: 0.76)
            cap("Env 1 Release", to: 0.16)
            cap("Reverb Mix", to: 0.06)
            cap("Delay Mix", to: 0.05)
            set("Mono", 1.0)
            raise("Portamento", to: 0.025)
        case .bass:
            raise("Env 1 Sustain", to: 0.48)
            cap("Env 1 Release", to: 0.24)
            cap("Reverb Mix", to: 0.08)
            cap("Delay Mix", to: 0.08)
            set("Mono", 1.0)
        case .sub808:
            raise("Env 1 Decay", to: 0.60)
            raise("Env 1 Release", to: 0.30)
            cap("Filter Cutoff", to: 0.42)
            cap("Reverb Mix", to: 0.04)
            cap("Delay Mix", to: 0.04)
            set("Mono", 1.0)
            raise("Portamento", to: 0.10)
        case .electricPiano:
            // Do not let a generic "piano" response leave Serum at Init.
            cap("Osc A Unison", to: 1.0)
            cap("Osc A Detune", to: 0.04)
            raise("Osc A Level", to: 0.70)
            raise("Osc A WT Pos", to: 0.08)
            cap("Osc A WT Pos", to: 0.22)
            cap("Osc B Level", to: 0.22)
            raise("Env 1 Decay", to: 0.48)
            cap("Env 1 Sustain", to: 0.38)
            raise("Env 1 Release", to: 0.30)
            raise("Filter Cutoff", to: 0.56)
            cap("Filter Resonance", to: 0.16)
            cap("Distortion Mix", to: 0.14)
            raise("Chorus Mix", to: 0.20)
            cap("Delay Mix", to: 0.10)
            cap("Reverb Mix", to: 0.24)
            set("Mono", 0.0)
        case .keys:
            raise("Env 1 Decay", to: 0.42)
            raise("Env 1 Sustain", to: 0.28)
            raise("Env 1 Release", to: 0.22)
            cap("Reverb Mix", to: 0.24)
        case .pad:
            raise("Env 1 Attack", to: 0.18)
            raise("Env 1 Sustain", to: 0.70)
            raise("Env 1 Release", to: 0.58)
        case .generic:
            raise("Env 1 Decay", to: 0.28)
            raise("Env 1 Release", to: 0.22)
        }

        if !(lower.contains("noise") || lower.contains("air") || lower.contains("breath") || lower.contains("vinyl")) {
            set("Noise On", 0.0)
            set("Noise Level", 0.0)
            set("Filter Noise", 0.0)
        } else if family == .pluck || family == .stab {
            cap("Noise Level", to: 0.035)
        }
    }

    private static func firstNumber(in text: String, near needles: [String]) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines where needles.contains(where: { line.contains($0) }) {
            if let n = numbers(in: line).first { return n }
        }
        return nil
    }

    private static func valueNear(labelCandidates: [String], in text: String, defaultUnit: NaturalUnit) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.lowercased()
            guard labelCandidates.contains(where: { line.contains($0.lowercased()) }) else { continue }
            let nums = numbers(in: line)
            guard !nums.isEmpty else { continue }
            let raw = nums.count >= 2 ? nums.prefix(2).reduce(0, +) / Double(min(2, nums.count)) : nums[0]
            if line.contains("ms") || defaultUnit == .milliseconds { return max(0, raw / 1000.0) }
            if line.contains("%") || defaultUnit == .percent { return max(0, min(1, raw / 100.0)) }
            return raw > 1 && defaultUnit == .normalized ? raw / 100.0 : raw
        }
        return nil
    }

    private static func semanticValuesFromLabelledText(name rawName: String, body rawBody: String, fullLine: String) -> [(String, Double)] {
        let name = rawName.lowercased()
        let body = rawBody.lowercased()
        let line = fullLine.lowercased()
        var pairs: [(String, Double)] = []
        func add(_ key: String, _ value: Double) { pairs.append((key, value)) }
        func any(_ needles: [String], in haystack: String? = nil) -> Bool {
            let h = haystack ?? line
            return needles.contains { h.contains($0) }
        }
        func intensity(default base: Double = 0.35) -> Double {
            if any(["off", "disabled", "bypass", "none"], in: body) { return 0.0 }
            if any(["tiny", "very low", "barely", "hint", "very subtle"], in: body) { return 0.08 }
            if any(["subtle", "small", "low", "quiet", "soft", "gentle", "light"], in: body) { return 0.18 }
            if any(["medium", "moderate", "balanced", "some"], in: body) { return 0.34 }
            if any(["strong", "high", "big", "wide", "heavy", "deep", "lots"], in: body) { return 0.62 }
            if any(["huge", "massive", "maximum", "max", "extreme"], in: body) { return 0.82 }
            return base
        }
        func waveValue() -> Double? {
            if any(["sine", "sin"], in: body) { return 0.08 }
            if any(["triangle", "tri"], in: body) { return 0.18 }
            if any(["sawtooth", "saw"], in: body) { return 0.70 }
            if any(["square", "pulse"], in: body) { return 0.48 }
            if any(["bell", "tine", "glassy", "fm"], in: body) { return 0.12 }
            return nil
        }
        let isOscA = any(["osc a", "oscillator a", "osc 1", "oscillator 1", "oscillator one"], in: name)
        let isOscB = any(["osc b", "oscillator b", "osc 2", "oscillator 2", "oscillator two"], in: name)
        if isOscA || isOscB || name.contains("oscillator") || name.contains("wavetable") {
            let prefix = isOscB ? "Osc B" : "Osc A"
            if isOscB { add("Osc B On", 1.0) }
            if let wt = waveValue() { add("\(prefix) WT Pos", wt); add("\(prefix) Wave", wt) }
            if any(["octave up", "+12", "12 semitone", "one octave above", "upper octave"], in: body) { add("\(prefix) Semitone", 12.0) }
            if any(["octave down", "-12", "−12", "one octave below"], in: body) { add("\(prefix) Semitone", -12.0) }
            if any(["body", "main", "fundamental", "dominant"], in: body) { add("\(prefix) Level", isOscB ? 0.22 : 0.78) }
            if any(["tine", "bell", "glassy", "sparkle", "attack layer"], in: body) { add("\(prefix) Level", isOscB ? 0.15 : 0.58) }
            if any(["detune", "chorused", "wide", "spread"], in: body) { add("\(prefix) Detune", intensity(default: 0.12)); add("\(prefix) Unison", any(["wide", "spread"], in: body) ? 4.0 : 2.0) }
            if any(["mono", "single", "one voice"], in: body) { add("\(prefix) Unison", 1.0); add("\(prefix) Detune", 0.01) }
        }

        if name.contains("amp") || name.contains("env 1") || name.contains("envelope") || name.contains("adsr") {
            if any(["fast attack", "instant attack", "percussive attack", "sharp attack"], in: line) { add("Env 1 Attack", 0.006) }
            if any(["slow attack", "fade in", "soft attack"], in: line) { add("Env 1 Attack", 0.18) }
            if any(["medium decay", "moderate decay", "decaying body"], in: line) { add("Env 1 Decay", 0.54) }
            if any(["short decay", "tight decay"], in: line) { add("Env 1 Decay", 0.30) }
            if any(["long decay", "ringing", "sustained decay"], in: line) { add("Env 1 Decay", 0.72) }
            if any(["low sustain", "little sustain", "reduced sustain"], in: line) { add("Env 1 Sustain", 0.24) }
            if any(["no sustain", "zero sustain"], in: line) { add("Env 1 Sustain", 0.0) }
            if any(["high sustain", "full sustain"], in: line) { add("Env 1 Sustain", 0.78) }
            if any(["medium release", "playable release", "natural release"], in: line) { add("Env 1 Release", 0.40) }
            if any(["short release", "tight release"], in: line) { add("Env 1 Release", 0.16) }
            if any(["long release", "tail", "wash"], in: line) { add("Env 1 Release", 0.68) }
        }

        if name.contains("filter") || name.contains("cutoff") || name.contains("tone") {
            if any(["low-pass", "lowpass", "lp24", "lp 24"], in: line) { add("Filter Type", 0.35) }
            if any(["lp12", "lp 12"], in: line) { add("Filter Type", 0.25) }
            if any(["bright", "open", "high cutoff"], in: line) { add("Filter Cutoff", 0.68) }
            if any(["warm", "rounded", "mellow", "soft", "low cutoff"], in: line) { add("Filter Cutoff", 0.48) }
            if any(["low resonance", "little resonance", "minimal resonance"], in: line) { add("Filter Resonance", 0.10) }
            if any(["medium resonance", "moderate resonance", "touch of resonance"], in: line) { add("Filter Resonance", 0.20) }
            if any(["drive", "saturation"], in: line) { add("Filter Drive", intensity(default: 0.20)) }
            if any(["filter envelope", "env amount", "envelope amount"], in: line) { add("Filter Env Amount", intensity(default: 0.28)); add("Env 2 -> Filter Cutoff", intensity(default: 0.28)) }
        }

        if name.contains("chorus") { add("Chorus On", intensity() > 0 ? 1.0 : 0.0); add("Chorus Mix", intensity(default: 0.28)); add("Chorus Depth", max(0.22, intensity(default: 0.36))) }
        if name.contains("tremolo") || line.contains("amp lfo") { add("Tremolo On", intensity() > 0 ? 1.0 : 0.0); add("Tremolo Mix", intensity(default: 0.18)); add("Tremolo Rate", any(["slow"], in: body) ? 0.16 : 0.24); add("LFO 1 -> Amp Level", intensity(default: 0.12)) }
        if name.contains("reverb") || name.contains("room") { add("Reverb On", intensity() > 0 ? 1.0 : 0.0); add("Reverb Mix", intensity(default: 0.18)); add("Reverb Decay", any(["long", "large", "hall"], in: body) ? 0.62 : 0.42) }
        if name.contains("delay") || name.contains("echo") { add("Delay On", intensity() > 0 ? 1.0 : 0.0); add("Delay Mix", intensity(default: 0.16)); add("Delay Feedback", min(0.42, max(0.12, intensity(default: 0.24)))) }
        if name.contains("drive") || name.contains("distortion") || name.contains("saturation") { add("Distortion On", intensity() > 0 ? 1.0 : 0.0); add("Distortion Drive", intensity(default: 0.18)); add("Distortion Mix", min(0.30, intensity(default: 0.14))) }
        if name.contains("noise") { add("Noise On", intensity() > 0 ? 1.0 : 0.0); add("Noise Level", intensity(default: 0.05)) }
        if name.contains("sub") { add("Sub On", intensity() > 0 ? 1.0 : 0.0); add("Sub Level", intensity(default: 0.20)) }
        return pairs
    }

    private static func semanticValuesFromUnlabelledProse(lower: String) -> [(String, Double)] {
        var pairs: [(String, Double)] = []
        func add(_ key: String, _ value: Double) { pairs.append((key, value)) }
        if lower.contains("rhodes") || lower.contains("electric piano") || lower.contains("e-piano") || lower.contains("epiano") || lower.contains("wurli") || lower.contains("wurlitzer") || lower.contains("tine") {
            // This mirrors the model-prose concepts, but is intentionally prose-derived:
            // warm sine/triangle body, quiet octave-up tine, percussive envelope,
            // low resonance, chorus/tremolo/room. It prevents the "prose instead of JSON"
            // path from degenerating into a status-only recipe or generic macros.
            add("Osc A WT Pos", 0.10); add("Osc A Level", 0.76); add("Osc A Unison", 1.0); add("Osc A Detune", 0.012)
            add("Osc B On", 1.0); add("Osc B WT Pos", 0.12); add("Osc B Semitone", 12.0); add("Osc B Level", 0.14)
            add("Filter Cutoff", lower.contains("bright") ? 0.68 : 0.56); add("Filter Resonance", 0.10); add("Filter Env Amount", 0.18)
            add("Env 1 Attack", 0.006); add("Env 1 Decay", 0.56); add("Env 1 Sustain", 0.26); add("Env 1 Release", 0.42)
            add("Chorus On", 1.0); add("Chorus Mix", 0.28); add("Chorus Depth", 0.38)
            add("Tremolo On", 1.0); add("Tremolo Mix", 0.18); add("Tremolo Rate", 0.24); add("LFO 1 -> Amp Level", 0.12)
            add("Reverb On", 1.0); add("Reverb Mix", 0.18); add("Reverb Decay", 0.44)
        }
        if lower.contains("no delay") || lower.contains("without delay") || lower.contains("dry") { add("Delay On", 0.0); add("Delay Mix", 0.0) }
        if lower.contains("no reverb") || lower.contains("without reverb") { add("Reverb On", 0.0); add("Reverb Mix", 0.0) }
        return pairs
    }

    private static func valueFromLabelledText(_ text: String, fallbackLine: String) -> Double? {
        let lower = fallbackLine.lowercased()
        guard let raw = numbers(in: text).first ?? numbers(in: fallbackLine).last else { return nil }
        if lower.contains("%") { return max(0, min(1, raw / 100.0)) }
        if lower.contains("ms") { return max(0, raw / 1000.0) }
        if lower.contains("hz") {
            // Rough musical normalization: 20 Hz ... 20 kHz on a log-ish curve.
            let v = max(20, min(20000, raw))
            return max(0, min(1, log10(v / 20.0) / log10(1000.0)))
        }
        if raw > 1, lower.contains("macro") || lower.contains("mix") || lower.contains("amount") || lower.contains("level") || lower.contains("depth") || lower.contains("cutoff") || lower.contains("reson") {
            return max(0, min(1, raw / 100.0))
        }
        return raw
    }

    private static func numbers(in string: String) -> [Double] {
        let pattern = #"[-+]?\d+(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = string as NSString
        return regex.matches(in: string, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            Double(ns.substring(with: match.range))
        }
    }

}
