import Foundation

// MARK: - Sound design agent
//
// Replaces the old "here's a preset, you apply it" flow with an agent that
// designs a patch for a chosen *target* (built-in analog, Vital, or a hosted
// Audio Unit like Serum/Massive/Omnisphere) using the selected LLM backend, then
// realizes it on that target. Offline falls back to the deterministic heuristic.

public struct SoundAgent {
    public var backend: LLMBackend
    public init(backend: LLMBackend) { self.backend = backend }

    public func design(description: String, for target: InstrumentTarget) async -> SoundDesign {
        // Offline / no backend → deterministic heuristic patch.
        if backend.isOffline {
            return SoundDesign(presetName: sanitizedPresetName(nil, fallback: description),
                               analog: DescribeASound().local(description),
                               notes: "Offline heuristic patch.")
        }
        let params = target.parameters
        let paramList = params.isEmpty
            ? "(this target exposes no introspectable parameters; use generic synth terms)"
            : params.map { "\($0.id) [\($0.name)] range \(fmt($0.min))…\(fmt($0.max))" }.joined(separator: "\n")
        let system = """
        You are a synthesis sound-designer driving \(target.displayName). Translate the
        FULL user request into concrete parameter values. Do not shorten, paraphrase,
        or truncate the request before deciding the patch.

        Use these exact host parameter ids/display names when they are useful:
        \(paramList)

        If the target is Serum or Serum 2, do NOT collapse the patch to generic
        macros. Use the Serum/Serum 2 synthesis vocabulary directly. The agentic
        layer knows a broad static Serum map and will fuzzy-map these names to
        whatever AU parameters Serum actually exposes in this host instance.
        For festival/progressive/epic/mainstage bass requests, especially Tiesto-like
        references, avoid hollow square-wave patches: use a saw-forward mono bass
        with controlled sub, modest detune, low resonance, tight release, and mostly
        dry FX.

        For Rhodes/electric-piano/Wurli/tine/FM-piano requests, do not leave the
        target near Init. Use a dedicated electric-piano recipe: sine/triangle
        oscillator body, small octave-up tine layer, low resonance, percussive
        attack, medium decay, low sustain, playable release, chorus/tremolo, and
        subtle room. This is a different family from generic piano/keys.
        Good Serum control names include:
        \(DeviceTranslationLayer.serumAgentParameterReference)

        If the target is a LemmingsStudio stock synth / analog device, use the
        stock analog vocabulary directly. Good stock control names include:
        cutoff, resonance, attack, decay, sustain, release, detuneCents, osc2Mix, gain.
        For stock synth ADSR, use seconds for attack/decay/release and normalized
        0...1 for sustain/gain/osc2Mix/resonance; do not use click-length envelopes
        for leads, saws, keys, supersaws, basses, 808s, or pads.

        Prefer normalized 0...1 for continuous plug-in controls, small integers for unison,
        semitone/polyphony, and 0/1 for on/off switches.

        Reply with a JSON object: {"presetName": string, "notes": string,
        "params": { "<param_id_or_serum_style_name>": number, ... }}. Pick musical,
        in-range values. Prefer normalized 0...1 values when the exact AU range is unknown.
        The presetName should be a short patch name like "80s Synthwave Pluck", not
        the literal prompt and not the first few words of the prompt.

        IMPORTANT: never claim that you changed a control the host cannot access. When an important
        control, mode, wavetable, routing switch, modulation assignment, or FX setting is unavailable,
        include concise manual completion steps in the notes field. Name the exact knob/control path,
        give a direction or approximate value/range, and state the listening goal.
        """
        do {
            let client = LLMClient(backend: backend)
            let text = try await client.complete(system: system, user: description, jsonOnly: true)
            // Parse both the model reply and the original prompt. This prevents a
            // weak/over-literal model from reducing "Create me an '80s style synthwave
            // pluck" to the useless preset title "Create Me An 80S" and only touching
            // one or two generic knobs. The user's request is always a first-class
            // sound-design source.
            let requestParams = DeviceTranslationLayer.normalizedPluginParams(fromNaturalLanguage: description, targetName: target.displayName)
            let naturalParams = DeviceTranslationLayer.normalizedPluginParams(fromNaturalLanguage: text, targetName: target.displayName)
            guard let json = DescribeASound.extractJSON(from: text)?.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
            else {
                var design = SoundDesign(presetName: sanitizedPresetName(nil, fallback: description),
                                         notes: proseFallbackNote(description: description,
                                                                 modelText: text,
                                                                 targetName: target.displayName,
                                                                 promptParamCount: requestParams.count,
                                                                 responseParamCount: naturalParams.count))
                for (k, v) in requestParams { design.params[k] = v }
                for (k, v) in naturalParams { design.params[k] = v }
                if design.params.isEmpty {
                    for (k, v) in DeviceTranslationLayer.fallbackMacroParams(from: description + "\n" + text, targetName: target.displayName) {
                        design.params[k] = v
                    }
                    design.notes += "\nNo direct sound-family recipe or prose knobs were found, so LemmingsStudio used macro fallback parameters."
                }
                // Final Serum guardrail: keep pluck envelopes audible after prose/static mapping.
                DeviceTranslationLayer.repairSerumMusicality(&design.params, intent: description + "\n" + text, targetName: target.displayName)
                // Give built-in/analog-compatible targets a musical fallback body too.
                design.analog = DescribeASound().local(description)
                if let caveat = DeviceTranslationLayer.wavetableTimbreCaveat(intent: description + "\n" + text, targetName: target.displayName) {
                    design.notes += (design.notes.isEmpty ? "" : "\n") + caveat
                }
                return design
            }
            var design = SoundDesign(presetName: sanitizedPresetName((obj["presetName"] as? String), fallback: description),
                                     notes: (obj["notes"] as? String) ?? "")
            let translated = DeviceTranslationLayer.normalizedPluginParams(from: obj)
            for (k, v) in requestParams { design.params[k] = v }
            for (k, v) in naturalParams { design.params[k] = v }
            for (k, v) in translated { design.params[k] = v }
            if translated.isEmpty, let p = obj["params"] as? [String: Any] {
                for (k, v) in p { if let d = numeric(v) { design.params[k] = d } }
            }
            if design.params.isEmpty {
                for (k, v) in DeviceTranslationLayer.fallbackMacroParams(from: description + "\n" + text, targetName: target.displayName) {
                    design.params[k] = v
                }
                design.notes += (design.notes.isEmpty ? "" : "\n") + "No explicit usable knobs were found in JSON/prose, so LemmingsStudio generated a conservative macro patch instead of reporting a fake success."
            } else if (!naturalParams.isEmpty || !requestParams.isEmpty) && !design.notes.localizedCaseInsensitiveContains("natural") {
                design.notes += (design.notes.isEmpty ? "" : "\n") + "Also parsed natural-language patch details from the prompt/response."
            }
            // Final Serum guardrail: model JSON can still ask for click-length envelopes.
            DeviceTranslationLayer.repairSerumMusicality(&design.params, intent: description + "\n" + text, targetName: target.displayName)
            // Stock analog targets always get a heuristic AnalogPreset baseline,
            // even when the model also returned parameter-level overrides.
            if target is BuiltinAnalogTarget {
                design.analog = DescribeASound().local(description)
            }
            if let caveat = DeviceTranslationLayer.wavetableTimbreCaveat(intent: description + "\n" + text, targetName: target.displayName) {
                design.notes += (design.notes.isEmpty ? "" : "\n") + caveat
            }
            return design
        } catch {
            return fallback(description)
        }
    }


    private func proseFallbackNote(description: String, modelText: String, targetName: String, promptParamCount: Int, responseParamCount: Int) -> String {
        let combined = (description + "\n" + modelText + "\n" + targetName).lowercased()
        let family: String
        if combined.contains("rhodes") || combined.contains("electric piano") || combined.contains("e-piano") || combined.contains("epiano") || combined.contains("wurli") || combined.contains("wurlitzer") || combined.contains("tine") || combined.contains("dx7 piano") || combined.contains("fm piano") {
            family = "Rhodes/electric-piano"
        } else if combined.contains("supersaw") || combined.contains("super saw") {
            family = "supersaw"
        } else if combined.contains("tiesto") || combined.contains("tiësto") || combined.contains("mainstage") || combined.contains("festival") || combined.contains("big room") || combined.contains("epic") {
            family = "festival/progressive"
        } else if combined.contains("pluck") || combined.contains("plucky") {
            family = "pluck"
        } else if combined.contains("808") || combined.contains("sub bass") || combined.contains("subbass") {
            family = "808/sub-bass"
        } else if combined.contains("bass") {
            family = "bass"
        } else if combined.contains("lead") {
            family = "lead"
        } else if combined.contains("pad") || combined.contains("ambient") || combined.contains("wash") {
            family = "pad"
        } else if combined.contains("keys") || combined.contains("piano") || combined.contains("stab") {
            family = "keys/stab"
        } else {
            family = "generic synth"
        }

        if promptParamCount > 0 || responseParamCount > 0 {
            let source: String
            if promptParamCount > 0 && responseParamCount > 0 {
                source = "the user prompt and the AI prose"
            } else if responseParamCount > 0 {
                source = "the AI prose"
            } else {
                source = "the user prompt"
            }
            return "AI returned prose instead of JSON; parsed \(source) as a \(family) sound-family recipe and translated it into concrete plug-in parameter moves."
        }
        return "AI returned prose instead of JSON; LemmingsStudio could not find a concrete sound-family recipe in the prompt or response."
    }

    private func fallback(_ d: String) -> SoundDesign {
        SoundDesign(presetName: sanitizedPresetName(nil, fallback: d), analog: DescribeASound().local(d),
                    notes: "Fell back to offline heuristic.")
    }
    private func sanitizedPresetName(_ proposed: String?, fallback: String) -> String {
        let source = ((proposed?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? proposed! : fallback)
            .replacingOccurrences(of: "’", with: "'")
        let stripped = source
            .replacingOccurrences(of: #"^(?i)\s*(create|make|give|design|build)\s+(me\s+)?(an?\s+)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bstyle\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "'80s", with: "80s")
            .replacingOccurrences(of: "‘80s", with: "80s")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = stripped.split(whereSeparator: { $0.isWhitespace }).prefix(8).map { token -> String in
            let raw = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "'`‘’.,;:!?")).lowercased()
            if raw == "80s" || raw == "'80s" { return "80s" }
            if raw == "ai" { return "AI" }
            return raw.capitalized
        }
        let name = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Lemmings Patch" : name
    }
    private func fmt(_ d: Double) -> String { abs(d) >= 100 ? String(Int(d)) : String(format: "%.2f", d) }
    private func numeric(_ v: Any) -> Double? {
        if let d = v as? Double { return d }; if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }; return nil
    }
}

// MARK: - AI assistant (edits MIDI / audio / automation)

public struct AssistantResult {
    public var text: String
    public var ops: [[String: Any]]
    public var log: [String] = []
}

public struct AIAssistant {
    public var backend: LLMBackend
    public init(backend: LLMBackend) { self.backend = backend }

    public func run(prompt: String, project: Project) async throws -> AssistantResult {
        guard !backend.isOffline else {
            return AssistantResult(text: "Pick a Claude API key or a local Ollama model to enable the AI assistant.", ops: [])
        }
        let system = Self.systemPrompt
        let context = Self.projectSummary(project)
        let user = "PROJECT STATE:\n\(context)\n\nREQUEST:\n\(prompt)"
        let client = LLMClient(backend: backend)
        let text = try await client.complete(system: system, user: user, jsonOnly: true)
        guard let json = DescribeASound.extractJSON(from: text)?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        else {
            if let fallback = Self.naturalLanguageFallback(prompt: prompt, project: project, modelText: text) {
                return fallback
            }
            return AssistantResult(text: "Couldn't parse the assistant's plan.", ops: [])
        }
        let ops = (obj["ops"] as? [[String: Any]]) ?? []
        let summary = (obj["summary"] as? String) ?? "Done."
        if ops.isEmpty, let fallback = Self.naturalLanguageFallback(prompt: prompt, project: project, modelText: text) {
            return fallback
        }
        return AssistantResult(text: summary, ops: ops)
    }

    static let systemPrompt = """
    You are the AI producer inside Lemmings Studio, a DAW. You edit the project by
    emitting a plan of operations. Reply with JSON:
    {"summary": string, "ops": [ <op>, ... ]}

    Supported ops (use beats as the time unit; pitch is MIDI number):
    - {"op":"add_notes","track":"<name>","clip":0,"notes":[{"pitch":48,"start":0,"length":0.5,"vel":0.9}]}
    - {"op":"set_clip_length","track":"<name>","clip":0,"length":16}
    - {"op":"clear_clip","track":"<name>","clip":0}
    - {"op":"transpose","track":"<name>","clip":0,"semitones":-12}
    - {"op":"quantize","track":"<name>","clip":0,"grid":0.25}
    - {"op":"humanize","track":"<name>","clip":0,"amount":0.02}
    - {"op":"set_automation","track":"<name>","node":"instrument","param":"cutoff","points":[{"beat":0,"value":400},{"beat":8,"value":6000}]}
    - {"op":"add_device","track":"<name>","device":"Reverb|Delay|Auto Filter|EQ Eight|Compressor|Tune"}
    - {"op":"set_param","track":"<name>","node":"instrument|<deviceIndex>","param":"<id>","value":0.4}
    - {"op":"set_drum_groove","track":"<name>","genre":"Lo-Fi|Tech House|Slap House|EDM|Breakbeat"}
    - {"op":"set_tempo","bpm":126}

    Make tasteful, musical choices. Keep notes within sensible ranges. Prefer
    automation with smooth multi-point curves for "brilliant" movement.

    For requests like "create 4 bars of bass chords on the Bassline track", emit
    concrete MIDI note arrays. Do not answer in prose. Resolve track names from
    PROJECT STATE and use set_clip_length + clear_clip + add_notes when creating
    a new musical phrase.

    If you absolutely must express music in prose, include explicit bar lines or
    a 16th-note grid using note names with octaves, e.g. Bar 1: C2 - - - | E2 - G2 -.
    The host can translate that grid back into MIDI, but JSON ops are preferred.
    """


    static func naturalLanguageFallback(prompt: String, project: Project, modelText: String) -> AssistantResult? {
        let source = (prompt + "\n" + modelText).lowercased()
        let wantsNotes = source.contains("bar") || source.contains("chord") || source.contains("notes") || source.contains("bassline") || source.contains("melody") || source.contains("riff") || source.contains("progression")
        guard wantsNotes else { return nil }
        let trackName = resolveRequestedTrackName(from: prompt, project: project)
        let bars = max(1, min(32, parseBarCount(from: prompt) ?? parseBarCount(from: modelText) ?? 4))
        let beatLength = Double(bars * max(1, project.beatsPerBar))
        let wantsBass = source.contains("bass") || trackName.lowercased().contains("bass")
        let wantsChords = source.contains("chord") || source.contains("progression")
        let parsed = parseExplicitMIDINotes(from: prompt + "\n" + modelText, project: project, defaultBars: bars)
        let notes: [[String: Any]]
        let parsedFromProse: Bool
        if !parsed.isEmpty {
            notes = parsed
            parsedFromProse = true
        } else if wantsChords {
            notes = generateChordNotes(bars: bars, project: project, bassVoicing: wantsBass)
            parsedFromProse = false
        } else if wantsBass {
            notes = generateBassLineNotes(bars: bars, project: project)
            parsedFromProse = false
        } else {
            notes = generateSimpleMelodyNotes(bars: bars, project: project)
            parsedFromProse = false
        }
        guard !notes.isEmpty else { return nil }
        let ops: [[String: Any]] = [
            ["op": "set_clip_length", "track": trackName, "clip": 0, "length": beatLength],
            ["op": "clear_clip", "track": trackName, "clip": 0],
            ["op": "add_notes", "track": trackName, "clip": 0, "notes": notes]
        ]
        let summaryKind = wantsChords ? (wantsBass ? "bass chords" : "chords") : (wantsBass ? "bassline" : "MIDI phrase")
        let sourceLabel = parsedFromProse ? "parsed from the assistant's prose/grid" : "generated by LemmingsStudio's deterministic fallback"
        return AssistantResult(text: "Created \(bars) bars of \(summaryKind) on \(trackName) from \(sourceLabel).", ops: ops, log: [parsedFromProse ? "Parsed explicit notes from model prose/table/code block and converted them to MIDI notes." : "Used deterministic note translator because the model did not return parseable JSON ops or explicit note prose."])
    }

    private static func parseExplicitMIDINotes(from text: String, project: Project, defaultBars: Int) -> [[String: Any]] {
        let beatsPerBar = max(1, project.beatsPerBar)
        let lines = text.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: .newlines)
        var parsedBars: [(Int, [String])] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let barNumber = parseBarNumber(in: line) else { continue }
            let cells = extractGridCells(fromBarLine: line)
            let meaningful = cells.filter { isNoteToken($0) }
            if !meaningful.isEmpty, !parsedBars.contains(where: { $0.0 == barNumber }) {
                parsedBars.append((barNumber, cells))
            }
        }

        if parsedBars.isEmpty { return [] }
        parsedBars.sort { $0.0 < $1.0 }
        var notes: [[String: Any]] = []
        for (index, entry) in parsedBars.enumerated() {
            let barNumber = max(1, entry.0)
            let barIndex = parsedBars.contains(where: { $0.0 == barNumber }) ? (barNumber - 1) : index
            let cells = entry.1
            let step = Double(beatsPerBar) / Double(max(1, cells.count))
            let barStart = Double(barIndex * beatsPerBar)
            var activePitch: Int? = nil
            var activeStart = 0.0
            var activeVelocity = 0.78

            func closeActive(at beat: Double) {
                guard let pitch = activePitch else { return }
                let length = max(step, beat - activeStart)
                notes.append(["pitch": max(0, min(127, pitch)), "start": activeStart, "length": length, "vel": activeVelocity])
                activePitch = nil
            }

            for (cellIndex, rawCell) in cells.enumerated() {
                let beat = barStart + Double(cellIndex) * step
                let token = cleanMIDIToken(rawCell)
                if let pitch = midiPitch(from: token) {
                    closeActive(at: beat)
                    activePitch = pitch
                    activeStart = beat
                    let positionInBar = cellIndex % max(1, cells.count)
                    activeVelocity = positionInBar == 0 ? 0.92 : (cellIndex % 4 == 0 ? 0.84 : 0.74)
                } else if isHardRestToken(token) {
                    closeActive(at: beat)
                } else {
                    // A dash in DAW/prose grids usually means "hold the previous note".
                    // If no note is active, it naturally becomes silence.
                    continue
                }
            }
            closeActive(at: barStart + Double(beatsPerBar))
        }

        return notes.sorted {
            let a = ($0["start"] as? Double) ?? 0
            let b = ($1["start"] as? Double) ?? 0
            if a == b { return (($0["pitch"] as? Int) ?? 0) < (($1["pitch"] as? Int) ?? 0) }
            return a < b
        }
    }

    private static func parseBarNumber(in line: String) -> Int? {
        let pattern = #"(?i)\bbar\s*(\d+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges > 1 else { return nil }
        return Int(ns.substring(with: match.range(at: 1)))
    }

    private static func extractGridCells(fromBarLine line: String) -> [String] {
        var working = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")

        if working.contains("|") {
            let chunks = working.components(separatedBy: "|")
            let cells = chunks.flatMap { chunk -> [String] in
                let withoutBarLabel = chunk.replacingOccurrences(of: #"(?i)\bbar\s*\d+\b"#, with: " ", options: .regularExpression)
                return tokenizeGridFragment(withoutBarLabel)
            }
            return cells.filter { isNoteToken($0) || isHoldToken($0) || isHardRestToken($0) }
        }

        if let colon = working.firstIndex(of: ":") {
            working = String(working[working.index(after: colon)...])
        } else {
            working = working.replacingOccurrences(of: #"(?i)\bbar\s*\d+\b"#, with: " ", options: .regularExpression)
        }
        return tokenizeGridFragment(working).filter { isNoteToken($0) || isHoldToken($0) || isHardRestToken($0) }
    }

    private static func tokenizeGridFragment(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .map(cleanMIDIToken)
            .filter { !$0.isEmpty }
    }

    private static func cleanMIDIToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).subtracting(CharacterSet(charactersIn: "#b-")))
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
    }

    private static func isNoteToken(_ token: String) -> Bool { midiPitch(from: token) != nil }
    private static func isHoldToken(_ token: String) -> Bool { ["-", "_", "~", ""].contains(cleanMIDIToken(token).lowercased()) }
    private static func isHardRestToken(_ token: String) -> Bool { ["r", "rest", "silence", "0"].contains(cleanMIDIToken(token).lowercased()) }

    private static func midiPitch(from token: String) -> Int? {
        let t = cleanMIDIToken(token)
        let pattern = #"(?i)^([A-G])([#b]?)(-?\d{1,2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = t as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: t, range: range), match.numberOfRanges >= 4 else { return nil }
        let letter = ns.substring(with: match.range(at: 1)).uppercased()
        let accidental = ns.substring(with: match.range(at: 2)).lowercased()
        guard let octave = Int(ns.substring(with: match.range(at: 3))) else { return nil }
        let base: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var semitone = base[letter] ?? 0
        if accidental == "#" { semitone += 1 }
        if accidental == "b" { semitone -= 1 }
        return max(0, min(127, (octave + 1) * 12 + ((semitone % 12) + 12) % 12))
    }

    private static func resolveRequestedTrackName(from prompt: String, project: Project) -> String {
        let lower = prompt.lowercased()
        for track in project.tracks {
            if lower.contains(track.name.lowercased()) { return track.name }
        }
        if let range = lower.range(of: #"on\s+(the\s+)?(.+?)\s+track"#, options: .regularExpression) {
            let phrase = String(lower[range])
                .replacingOccurrences(of: #"^on\s+(the\s+)?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+track$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = project.tracks.first(where: { $0.name.lowercased().contains(phrase) || phrase.contains($0.name.lowercased()) }) { return match.name }
        }
        if lower.contains("bass") {
            if let bass = project.tracks.first(where: { $0.name.localizedCaseInsensitiveContains("bass") || $0.kind.rawValue.localizedCaseInsensitiveContains("bass") }) { return bass.name }
        }
        return project.tracks.first?.name ?? "Track 1"
    }

    private static func parseBarCount(from text: String) -> Int? {
        let lower = text.lowercased()
        if let range = lower.range(of: #"\b\d+\s*bars?\b"#, options: .regularExpression) {
            let digits = lower[range].filter { $0.isNumber }
            return Int(String(digits))
        }
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "sixteen": 16]
        for (word, value) in words where lower.contains("\(word) bar") { return value }
        return nil
    }

    private static func generateChordNotes(bars: Int, project: Project, bassVoicing: Bool) -> [[String: Any]] {
        let progression = isMinor(project.scale) ? [0, 8, 3, 10] : [0, 7, 9, 5] // i-bVI-bIII-bVII or I-V-vi-IV pitch-class roots
        var notes: [[String: Any]] = []
        for bar in 0..<bars {
            let rootPC = (project.keyRoot + progression[bar % progression.count] + 120) % 12
            let root = nearestMidi(for: rootPC, low: bassVoicing ? 36 : 48, high: bassVoicing ? 47 : 60)
            let start = Double(bar * max(1, project.beatsPerBar))
            let len = max(0.5, Double(project.beatsPerBar) - 0.125)
            let third = chordThird(forRootOffset: progression[bar % progression.count], scale: project.scale)
            let chord = bassVoicing
                ? [root, root + 7, root + 12, root + third + 12]
                : [root, root + third, root + 7, root + 12]
            for (i, pitch) in chord.enumerated() {
                notes.append(["pitch": max(0, min(127, pitch)), "start": start, "length": len, "vel": i == 0 ? 0.92 : 0.78])
            }
        }
        return notes
    }

    private static func generateBassLineNotes(bars: Int, project: Project) -> [[String: Any]] {
        let progression = isMinor(project.scale) ? [0, 8, 3, 10] : [0, 7, 9, 5]
        var notes: [[String: Any]] = []
        for bar in 0..<bars {
            let rootPC = (project.keyRoot + progression[bar % progression.count] + 120) % 12
            let root = nearestMidi(for: rootPC, low: 36, high: 47)
            let barStart = Double(bar * max(1, project.beatsPerBar))
            for step in 0..<4 {
                notes.append(["pitch": step == 3 ? root + 7 : root, "start": barStart + Double(step), "length": 0.75, "vel": step == 0 ? 0.95 : 0.82])
            }
        }
        return notes
    }

    private static func generateSimpleMelodyNotes(bars: Int, project: Project) -> [[String: Any]] {
        let scale = project.scale.intervals.isEmpty ? [0, 2, 4, 5, 7, 9, 11] : project.scale.intervals
        var notes: [[String: Any]] = []
        let pattern = [0, 2, 4, 2, 5, 4, 2, 1]
        let totalSteps = bars * max(1, project.beatsPerBar) * 2
        for i in 0..<totalSteps {
            let pc = (project.keyRoot + scale[pattern[i % pattern.count] % scale.count]) % 12
            let pitch = nearestMidi(for: pc, low: 60, high: 76)
            notes.append(["pitch": pitch, "start": Double(i) * 0.5, "length": 0.45, "vel": 0.78])
        }
        return notes
    }

    private static func nearestMidi(for pc: Int, low: Int, high: Int) -> Int {
        let normalized = (pc % 12 + 12) % 12
        let candidates = (low...high).filter { (($0 % 12) + 12) % 12 == normalized }
        return candidates.first ?? max(0, min(127, low + ((normalized - low) % 12 + 12) % 12))
    }

    private static func isMinor(_ scale: Scale) -> Bool {
        let intervals = Set(scale.intervals.map { (($0 % 12) + 12) % 12 })
        return intervals.contains(3) && !intervals.contains(4)
    }

    private static func chordThird(forRootOffset offset: Int, scale: Scale) -> Int {
        // Prefer the scale-correct third above the requested chord root. Fall back to minor third for minor-ish scales.
        let intervals = Set(scale.intervals.map { (($0 % 12) + 12) % 12 })
        let majorThirdPC = ((offset + 4) % 12 + 12) % 12
        let minorThirdPC = ((offset + 3) % 12 + 12) % 12
        if intervals.contains(majorThirdPC) { return 4 }
        if intervals.contains(minorThirdPC) { return 3 }
        return isMinor(scale) ? 3 : 4
    }

    static func projectSummary(_ p: Project) -> String {
        var lines = ["tempo=\(Int(p.tempo)) key=\(p.keyRoot) scale=\(p.scale.name) bars=\(p.lengthBars)"]
        for t in p.tracks {
            let clipInfo = t.clips.enumerated().map { "clip\($0.offset)(\($0.element.notes.count)n@\(fmtBeat($0.element.startBeat)))" }.joined(separator: ",")
            let devs = t.devices.map { $0.kind.rawValue }.joined(separator: "+")
            lines.append("track \"\(t.name)\" kind=\(t.kind.rawValue) \(clipInfo) devices=[\(devs)]")
        }
        return lines.joined(separator: "\n")
    }
    static func fmtBeat(_ b: Double) -> String { String(format: "%.1f", b) }
}

// MARK: - Op executor (mutates models; call on the main actor)

public enum AssistantExecutor {
    @discardableResult
    public static func apply(_ ops: [[String: Any]], project: Project, engine: AudioEngine) -> [String] {
        var log: [String] = []
        var needsRebuild = false
        for op in ops {
            guard let kind = op["op"] as? String else { continue }
            switch kind {
            case "set_tempo":
                if let bpm = num(op["bpm"]) { project.tempo = bpm; engine.transport.tempo = bpm; log.append("Tempo → \(Int(bpm))") }
            case "add_notes":
                guard let t = track(op, project) else { break }
                let clip = clip(op, t, createIfNeeded: true)
                if let arr = op["notes"] as? [[String: Any]] {
                    var farthestBeat: Double = 0
                    for n in arr {
                        let start = num(n["start"]) ?? 0
                        let length = num(n["length"]) ?? 0.5
                        clip?.notes.append(ClipNote(pitch: Int(num(n["pitch"]) ?? 60),
                                                    start: start,
                                                    length: length,
                                                    velocity: Float(num(n["vel"]) ?? 0.9)))
                        farthestBeat = max(farthestBeat, start + length)
                    }
                    if let clip, farthestBeat > clip.lengthBeats { clip.lengthBeats = ceil(farthestBeat) }
                    log.append("Added \(arr.count) notes to \(t.name)")
                }
            case "clear_clip":
                if let c = clip(op, track(op, project), createIfNeeded: false) { c.notes.removeAll(); log.append("Cleared clip") }
            case "set_clip_length":
                if let c = clip(op, track(op, project), createIfNeeded: true), let length = num(op["length"]) {
                    c.lengthBeats = max(0.25, length)
                    c.loopLengthBeats = max(c.loopLengthBeats, min(c.lengthBeats, max(1, length)))
                    log.append("Clip length → \(String(format: "%.1f", c.lengthBeats)) beats")
                }
            case "transpose":
                if let c = clip(op, track(op, project), createIfNeeded: false), let s = num(op["semitones"]) {
                    c.notes = c.notes.map { var x = $0; x.pitch += Int(s); return x }
                    log.append("Transposed \(Int(s)) st")
                }
            case "quantize":
                if let c = clip(op, track(op, project), createIfNeeded: false) {
                    let g = num(op["grid"]) ?? 0.25
                    c.notes = c.notes.map { var x = $0; x.start = (x.start / g).rounded() * g; return x }
                    log.append("Quantized to \(g)")
                }
            case "humanize":
                if let c = clip(op, track(op, project), createIfNeeded: false) {
                    let a = num(op["amount"]) ?? 0.02
                    c.notes = c.notes.map { var x = $0
                        x.start = max(0, x.start + Double.random(in: -a...a))
                        x.velocity = Float(min(1, max(0.1, Double(x.velocity) + Double.random(in: -0.1...0.1))))
                        return x }
                    log.append("Humanized \(t(op))")
                }
            case "set_automation":
                guard let t = track(op, project) else { break }
                let node = (op["node"] as? String) ?? "instrument"
                let param = (op["param"] as? String) ?? "cutoff"
                let nodeID = resolveNodeID(node, track: t)
                let lane = t.lane(nodeID: nodeID, paramID: param)
                lane.points.removeAll()
                if let pts = op["points"] as? [[String: Any]] {
                    for p in pts { lane.addPoint(beat: num(p["beat"]) ?? 0, value: num(p["value"]) ?? 0) }
                }
                log.append("Automation: \(t.name).\(param) (\(lane.points.count) pts)")
            case "add_device":
                guard let t = track(op, project), let name = op["device"] as? String,
                      let dk = DeviceKind(rawValue: name) ?? deviceKindLoose(name) else { break }
                t.devices.append(DeviceModel(kind: dk)); needsRebuild = true
                log.append("Added \(dk.rawValue) to \(t.name)")
            case "set_param":
                guard let t = track(op, project) else { break }
                let node = (op["node"] as? String) ?? "instrument"
                let nodeID = resolveNodeID(node, track: t)
                if let param = op["param"] as? String, let v = num(op["value"]) {
                    engine.liveNode(track: t, nodeID: nodeID)?.setParam(param, v)
                    if let model = t.devices.first(where: { $0.nodeID == nodeID }) { model.params[param] = v }
                    log.append("\(t.name).\(param) = \(v)")
                }
            case "set_drum_groove":
                guard let t = track(op, project), t.kind == .drums,
                      let g = DrumGenre(rawValue: (op["genre"] as? String) ?? "") else { break }
                t.drumGenre = g
                engine.liveDrumKit(for: t)?.genre = g
                applyGrooveToSteps(t, genre: g)
                log.append("\(t.name) groove → \(g.rawValue)")
            default:
                log.append("Skipped unknown op \(kind)")
            }
        }
        if needsRebuild { engine.rebuild() }
        return log
    }

    // helpers
    private static func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }; if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }; return nil
    }
    private static func t(_ op: [String: Any]) -> String { (op["track"] as? String) ?? "?" }
    private static func track(_ op: [String: Any], _ p: Project) -> Track? {
        guard let name = op["track"] as? String else { return p.tracks.first }
        return p.tracks.first { $0.name.lowercased() == name.lowercased() }
            ?? Int(name).flatMap { $0 < p.tracks.count ? p.tracks[$0] : nil }
    }
    private static func clip(_ op: [String: Any], _ track: Track?, createIfNeeded: Bool) -> Clip? {
        guard let track else { return nil }
        let idx = Int(num(op["clip"]) ?? 0)
        if idx < track.clips.count { return track.clips[idx] }
        if createIfNeeded {
            let c = Clip(name: "AI Clip", startBeat: 0, lengthBeats: 16, color: track.color)
            track.clips.append(c); return c
        }
        return nil
    }
    private static func resolveNodeID(_ node: String, track: Track) -> String {
        if node == "instrument" { return "instrument" }
        if let i = Int(node), i < track.devices.count { return track.devices[i].nodeID }
        // match by device kind name
        if let m = track.devices.first(where: { $0.kind.rawValue.lowercased() == node.lowercased() }) { return m.nodeID }
        return "instrument"
    }
    private static func deviceKindLoose(_ s: String) -> DeviceKind? {
        DeviceKind.allCases.first { $0.rawValue.lowercased() == s.lowercased() || $0.rawValue.lowercased().contains(s.lowercased()) }
    }
    private static func applyGrooveToSteps(_ track: Track, genre: DrumGenre) {
        let groove = DrumKitLibrary.groove(for: genre)
        let pattern = track.stepPattern
        pattern.loadDrumGroove(groove)
        track.useStepSequencer = true
    }
}
