import Foundation

// MARK: - Describe-a-sound

/// Turns a natural-language prompt into AnalogPreset parameters.
///
/// Two paths:
///   1. `local(_:)`  — fully offline keyword heuristic. Works with no network
///      and is deterministic. Good enough to be genuinely useful.
///   2. `remote(_:)` — optional LLM call (Anthropic Messages API) that returns
///      structured JSON. Scaffolded: add your API key in `apiKey` to enable.
public struct DescribeASound {

    public init() {}

    public func local(_ prompt: String) -> AnalogPreset {
        let p = prompt.lowercased()
        var preset = AnalogPreset()

        func has(_ words: String...) -> Bool { words.contains { p.contains($0) } }

        // Timbre / waveform
        if has("bright", "buzzy", "harsh", "aggressive") { preset.osc1 = .saw;  preset.osc2 = .square }
        if has("warm", "soft", "mellow", "round", "analog") { preset.osc1 = .saw; preset.osc2 = .triangle; preset.osc2Mix = 0.35; preset.cutoff = 2400 }
        if has("hollow", "woody", "reedy", "organ") { preset.osc1 = .square; preset.osc2 = .square; preset.osc2Mix = 0.42 }
        if has("pure", "clean", "flute", "sine") { preset.osc1 = .sine; preset.osc2Mix = 0 }

        // Sound-family envelopes. These are deliberately musical for the stock
        // AnalogSynth engine; do not copy Serum's normalized values directly.
        if has("pluck", "stab", "percussive", "pizzicato", "marimba") {
            preset.osc1 = .saw; preset.osc2 = .square; preset.osc2Mix = 0.22
            preset.attack = 0.003; preset.decay = 0.22; preset.sustain = 0.18; preset.release = 0.18
            preset.cutoff = 2600; preset.resonance = 0.20; preset.detuneCents = 5
        }
        if has("rhodes", "electric piano", "e-piano", "epiano", "wurli", "wurlitzer", "tine piano", "fm piano", "dx7 piano") {
            // Rhodes/Wurli approximation for the built-in subtractive synth: sine/triangle body,
            // percussive tine-like decay, low resonance, playable release.
            preset.osc1 = .sine; preset.osc2 = .triangle; preset.osc2Mix = 0.18
            preset.attack = 0.004; preset.decay = 0.52; preset.sustain = 0.28; preset.release = 0.46
            preset.cutoff = 4200; preset.resonance = 0.10; preset.detuneCents = 1; preset.gain = 0.58
        } else if has("key", "keys", "keyboard", "m1", "house chord") {
            preset.osc1 = .square; preset.osc2 = .triangle; preset.osc2Mix = 0.36
            preset.attack = 0.006; preset.decay = 0.34; preset.sustain = 0.46; preset.release = 0.28
            preset.cutoff = 3000; preset.resonance = 0.18
        }
        if has("lead", "screaming", "solo", "hook", "melody") {
            preset.osc1 = .saw; preset.osc2 = .saw; preset.osc2Mix = 0.54
            preset.attack = 0.006; preset.decay = 0.22; preset.sustain = 0.74; preset.release = 0.22
            preset.cutoff = 4400; preset.resonance = 0.32; preset.detuneCents = 8
        }
        if has("supersaw", "super saw", "wide saw", "festival", "trance saw", "big saw") {
            preset.osc1 = .saw; preset.osc2 = .saw; preset.osc2Mix = 0.82
            preset.attack = 0.018; preset.decay = 0.38; preset.sustain = 0.82; preset.release = 0.55
            preset.cutoff = 6200; preset.resonance = 0.18; preset.detuneCents = 22; preset.gain = 0.42
        }
        if has("saw", "saw bass", "reese") && !has("supersaw", "super saw") {
            preset.osc1 = .saw; preset.osc2 = .saw; preset.osc2Mix = 0.62
            preset.attack = 0.004; preset.decay = 0.20; preset.sustain = 0.72; preset.release = 0.12
            preset.cutoff = 1400; preset.resonance = 0.22; preset.detuneCents = 12
        }
        if has("bass", "sub", "low") {
            preset.osc1 = .sine; preset.osc2 = .saw; preset.osc2Mix = 0.20
            preset.attack = 0.003; preset.decay = 0.20; preset.sustain = 0.80; preset.release = 0.10
            preset.cutoff = 650; preset.resonance = 0.18; preset.detuneCents = 2; preset.gain = 0.68
        }
        if has("tiesto", "tiësto", "epic bass", "festival bass", "progressive bass", "big room bass", "mainstage bass", "trance bass", "edm bass") {
            // Mainstage/progressive-house bass: saw body plus controlled sub, not a square/hollow patch.
            preset.osc1 = .saw; preset.osc2 = .sine; preset.osc2Mix = 0.24
            preset.attack = 0.003; preset.decay = 0.18; preset.sustain = 0.84; preset.release = 0.09
            preset.cutoff = 1250; preset.resonance = 0.12; preset.detuneCents = 4; preset.gain = 0.66
        }
        if has("808", "sub drop", "boomy") {
            preset.osc1 = .sine; preset.osc2 = .triangle; preset.osc2Mix = 0.08
            preset.attack = 0.002; preset.decay = 1.20; preset.sustain = 0.0; preset.release = 0.55
            preset.cutoff = 300; preset.resonance = 0.08; preset.detuneCents = 0; preset.gain = 0.78
        }
        if has("pad", "lush", "swell", "ambient", "string", "wash") {
            preset.osc1 = .saw; preset.osc2 = .triangle; preset.osc2Mix = 0.60
            preset.attack = 0.65; preset.decay = 0.8; preset.sustain = 0.88; preset.release = 1.4
            preset.cutoff = 2600; preset.resonance = 0.16; preset.detuneCents = 14; preset.gain = 0.38
        }

        // Filter / brightness modifiers
        if has("dark", "muffled", "dull", "lofi", "lo-fi") { preset.cutoff = min(preset.cutoff, 900) }
        if has("bright", "open", "airy", "sparkle") { preset.cutoff = max(preset.cutoff, 5600) }
        if has("squelch", "acid", "resonant", "talky") { preset.resonance = 0.78; preset.cutoff = min(max(preset.cutoff, 900), 2200) }

        // Style modifiers
        if has("80s", "'80s", "synthwave", "retro wave", "retrowave") {
            preset.osc1 = .saw; preset.osc2 = .square; preset.osc2Mix = max(preset.osc2Mix, 0.28)
            preset.cutoff = max(preset.cutoff, 2400); preset.resonance = max(preset.resonance, 0.22)
            preset.detuneCents = max(preset.detuneCents, 9)
            if has("pluck") { preset.decay = max(preset.decay, 0.24); preset.sustain = max(preset.sustain, 0.20); preset.release = max(preset.release, 0.22) }
        }
        if has("detuned", "fat", "wide", "unison", "super") { preset.detuneCents = max(preset.detuneCents, 18); preset.osc2Mix = max(preset.osc2Mix, 0.6) }
        if has("thin", "tight")  { preset.detuneCents = min(preset.detuneCents, 2); preset.osc2Mix = min(preset.osc2Mix, 0.18) }
        if has("punchy")         { preset.attack = min(preset.attack, 0.004); preset.decay = max(preset.decay, 0.14) }

        return preset
    }

    // --- Optional remote path ---
    public var apiKey: String = ""   // set to enable the LLM path

    public func remote(_ prompt: String) async throws -> AnalogPreset {
        guard !apiKey.isEmpty else { return local(prompt) }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 400,
            "system": Self.patchSystemPrompt,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        // Parse Anthropic response -> text -> JSON params. Falls back to local on any miss.
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = root["content"] as? [[String: Any]],
            let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
            let jsonData = Self.extractJSON(from: text)?.data(using: .utf8),
            let params = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return local(prompt) }

        return apply(params, onto: local(prompt))   // heuristic base, model overrides
    }

    // --- Local Ollama path (offline LLM, no API key) ---

    /// Translate a prompt into a preset using a locally-running Ollama model.
    /// The model is expected to return a single JSON object (we request
    /// `format: "json"`). Falls back to the offline heuristic on any miss, so a
    /// flaky model or partial JSON never leaves the user empty-handed.
    public func ollama(_ prompt: String, client: OllamaClient, model: String) async throws -> AnalogPreset {
        let text = try await client.generateJSON(model: model, system: Self.patchSystemPrompt, prompt: prompt)
        guard
            let jsonData = Self.extractJSON(from: text)?.data(using: .utf8),
            let params = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return local(prompt) }
        return apply(params, onto: local(prompt))
    }

    // --- Shared bits ---

    /// The instruction both the Claude and Ollama paths use, kept in one place.
    static let patchSystemPrompt = """
    You are a synth-patch designer. Given a sound description, classify the sound family first, then reply with ONLY a JSON object \
    with keys: osc1, osc2 (one of sine/triangle/saw/square), osc2Mix (0-1), detuneCents (0-30), \
    cutoff (20-12000), resonance (0-1), attack, decay, sustain, release (seconds, 0-2), gain (0-1). \
    Rhodes/electric-piano/Wurli sounds should use sine or triangle body, small osc2Mix, quick attack, medium decay, low sustain, medium release, low resonance, and moderate cutoff. \
    Leads/saws/basses/plucks/pads should use distinct ADSR and oscillator choices instead of Init-like defaults. \
    No prose, no markdown, no code fences.
    """

    /// Pull the first balanced `{...}` object out of arbitrary model text. Small
    /// uncensored models love to wrap JSON in chatter or fences; this rescues it.
    static func extractJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        while idx < text.endIndex {
            let c = text[idx]
            if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { return String(text[start...idx]) } }
            idx = text.index(after: idx)
        }
        return nil
    }

    /// Apply a parsed JSON param dictionary onto a base preset (shared by both
    /// LLM backends). Numbers may decode as Double or Int depending on source.
    func apply(_ params: [String: Any], onto base: AnalogPreset) -> AnalogPreset {
        var preset = base
        func num(_ key: String) -> Double? {
            if let d = params[key] as? Double { return d }
            if let i = params[key] as? Int { return Double(i) }
            if let s = params[key] as? String { return Double(s) }
            return nil
        }
        if let s = params["osc1"] as? String, let w = Waveform(rawValue: s) { preset.osc1 = w }
        if let s = params["osc2"] as? String, let w = Waveform(rawValue: s) { preset.osc2 = w }
        if let v = num("osc2Mix")     { preset.osc2Mix = Float(v) }
        if let v = num("detuneCents") { preset.detuneCents = v }
        if let v = num("cutoff")      { preset.cutoff = v }
        if let v = num("resonance")   { preset.resonance = v }
        if let v = num("attack")      { preset.attack = v }
        if let v = num("decay")       { preset.decay = v }
        if let v = num("sustain")     { preset.sustain = v }
        if let v = num("release")     { preset.release = v }
        if let v = num("gain")        { preset.gain = Float(v) }
        return preset
    }
}
