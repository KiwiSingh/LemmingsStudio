import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif

// MARK: - Sound design (the agent's output)

/// A backend-agnostic patch description the agent produces and a target realizes.
public struct SoundDesign: Sendable {
    public var presetName: String
    public var analog: AnalogPreset?          // for the built-in synth
    public var params: [String: Double]       // generic name → value, for plugins
    public var notes: String
    public init(presetName: String = "Lemmings Patch", analog: AnalogPreset? = nil,
                params: [String: Double] = [:], notes: String = "") {
        self.presetName = presetName; self.analog = analog; self.params = params; self.notes = notes
    }
}

public struct PluginParam: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var min: Double
    public var max: Double
}

// MARK: - Target protocol

public protocol InstrumentTarget: AnyObject {
    var displayName: String { get }
    var parameters: [PluginParam] { get }
    /// Realize a design. Returns a human-readable summary of what it did.
    @discardableResult func apply(_ design: SoundDesign) throws -> String
}

public enum InstrumentTargetError: LocalizedError {
    case notHosted, presetWriteFailed(String), unsupported(String)
    public var errorDescription: String? {
        switch self {
        case .notHosted: return "This plugin isn't currently hosted, so parameters can't be set live."
        case .presetWriteFailed(let s): return "Couldn't write preset: \(s)"
        case .unsupported(let s): return s
        }
    }
}

// MARK: - Built-in analog target

public final class BuiltinAnalogTarget: InstrumentTarget {
    private let synth: StockAnalogPatchable
    public init(synth: StockAnalogPatchable) { self.synth = synth }
    public var displayName: String { synth.stockAnalogDisplayName.isEmpty ? "Built-in Analog" : synth.stockAnalogDisplayName }
    public var parameters: [PluginParam] {
        synth.stockAnalogParameters.map { PluginParam(id: $0.id, name: $0.name, min: $0.min, max: $0.max) }
    }
    @discardableResult public func apply(_ design: SoundDesign) throws -> String {
        var changed = 0
        if let preset = design.analog {
            synth.applyStockAnalogPreset(preset)
            changed += 1
        }
        for (rawKey, rawValue) in design.params {
            guard let mapped = Self.mapStockAnalogParam(rawKey, available: synth.stockAnalogParameters) else { continue }
            let value = Self.scaleStockAnalogValue(rawValue, for: mapped)
            synth.setStockAnalogParam(mapped.id, value)
            changed += 1
        }
        guard changed > 0 else {
            throw InstrumentTargetError.unsupported("The Sound Agent produced no usable stock-synth parameters for \(displayName).")
        }
        return "Applied “\(design.presetName)” to \(displayName) using stock analog ADSR/filter/oscillator controls."
    }

    private static func mapStockAnalogParam(_ key: String, available: [ParamInfo]) -> ParamInfo? {
        let n = normalize(key)
        let aliases: [String: String] = [
            "filtercutoff": "cutoff", "cutoff": "cutoff", "filcutoff": "cutoff", "brightness": "cutoff", "tone": "cutoff",
            "filterresonance": "resonance", "resonance": "resonance", "reso": "resonance", "q": "resonance",
            "env1attack": "attack", "ampattack": "attack", "attack": "attack", "atk": "attack",
            "env1decay": "decay", "ampdecay": "decay", "decay": "decay", "dec": "decay",
            "env1sustain": "sustain", "ampsustain": "sustain", "sustain": "sustain", "sus": "sustain",
            "env1release": "release", "amprelease": "release", "release": "release", "rel": "release",
            "osc2mix": "osc2Mix", "oscbmix": "osc2Mix", "oscmix": "osc2Mix", "blend": "osc2Mix", "oscblevel": "osc2Mix",
            "detune": "detuneCents", "detunecents": "detuneCents", "fine": "detuneCents", "spread": "detuneCents", "width": "detuneCents",
            "gain": "gain", "volume": "gain", "level": "gain", "output": "gain", "mastervolume": "gain"
        ]
        if let id = aliases[n], let p = available.first(where: { $0.id == id }) { return p }
        return available.first { normalize($0.id) == n || normalize($0.name) == n }
    }

    private static func scaleStockAnalogValue(_ value: Double, for p: ParamInfo) -> Double {
        let v = value.isFinite ? value : p.min
        if p.max > 1.0, v >= 0.0, v <= 1.0 {
            return p.min + (p.max - p.min) * v
        }
        return min(max(v, p.min), p.max)
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Vital target (writes a real .vital JSON preset)

public final class VitalTarget: InstrumentTarget {
    public let displayName = "Vital"
    public init() {}

    public var parameters: [PluginParam] {
        [PluginParam(id: "osc_1_wave", name: "Osc 1 Wave", min: 0, max: 1),
         PluginParam(id: "filter_1_cutoff", name: "Filter Cutoff", min: 8, max: 136),
         PluginParam(id: "filter_1_resonance", name: "Filter Resonance", min: 0, max: 1),
         PluginParam(id: "env_1_attack", name: "Env Attack", min: 0, max: 2),
         PluginParam(id: "env_1_release", name: "Env Release", min: 0, max: 4)]
    }

    /// Vital preset dirs (the app reads any of these). We write under a Lemmings folder.
    var presetDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Music/Vital/Presets/Lemmings", isDirectory: true)
    }

    @discardableResult public func apply(_ design: SoundDesign) throws -> String {
        let url = try writePreset(design)
        return "Wrote Vital preset → \(url.path). Open it from Vital's browser (Lemmings folder)."
    }

    /// Vital's `.vital` format is open JSON. This writes a minimal but valid
    /// settings block mapping our design onto Vital's parameter names. Not every
    /// Vital field is populated — it's a usable starting patch, not a full clone.
    func writePreset(_ design: SoundDesign) throws -> URL {
        let a = design.analog ?? AnalogPreset()
        // Map analog params → Vital's normalized-ish parameter space.
        let cutoffMidi = 12 * log2(max(a.cutoff, 20) / 440) + 69      // Hz → MIDI-ish for filter_cutoff
        var settings: [String: Any] = [
            "osc_1_on": 1,
            "osc_1_transpose": 0,
            "filter_1_on": 1,
            "filter_1_cutoff": min(max(cutoffMidi, 8), 136),
            "filter_1_resonance": min(max(a.resonance, 0), 1),
            "env_1_attack": a.attack,
            "env_1_decay": a.decay,
            "env_1_sustain": a.sustain,
            "env_1_release": a.release,
            "volume": Double(a.gain) * 10000,
            "polyphony": 8,
        ]
        for (k, v) in design.params { settings[k] = v }   // agent overrides
        let preset: [String: Any] = [
            "synth_version": "1.5.5",
            "preset_name": design.presetName,
            "author": "Lemmings Studio",
            "comments": design.notes,
            "settings": settings,
        ]
        let data = try JSONSerialization.data(withJSONObject: preset, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: presetDir, withIntermediateDirectories: true)
        let safe = design.presetName.replacingOccurrences(of: "/", with: "-")
        let url = presetDir.appendingPathComponent("\(safe).vital")
        do { try data.write(to: url) } catch { throw InstrumentTargetError.presetWriteFailed(error.localizedDescription) }
        return url
    }
}

// MARK: - Hosted Audio Unit target (Serum/Massive/Omnisphere when run as AU)

#if canImport(AVFoundation)
public final class AudioUnitTarget: InstrumentTarget {
    public let displayName: String
    private let auAudioUnit: AUAudioUnit?

    public init(name: String, audioUnit: AUAudioUnit?) {
        self.displayName = name; self.auAudioUnit = audioUnit
    }

    public var parameters: [PluginParam] {
        guard let tree = auAudioUnit?.parameterTree else { return [] }
        return tree.allParameters.map {
            PluginParam(id: String($0.address), name: $0.displayName,
                        min: Double($0.minValue), max: Double($0.maxValue))
        }
    }

    /// Set parameters on a live-hosted AU by name (fuzzy) or address. Real AU
    /// parameter API — works once the unit is instantiated and in the graph.
    @discardableResult public func apply(_ design: SoundDesign) throws -> String {
        guard let tree = auAudioUnit?.parameterTree else { throw InstrumentTargetError.notHosted }
        var set = 0
        for (key, value) in design.params {
            let normalized = DeviceTranslationLayer.normalizeParameterName(key)
            let candidates = [key, normalized]
            var hit: AUParameter? = nil
            for candidate in candidates where hit == nil {
                if let addr = AUParameterAddress(candidate), let p = tree.parameter(withAddress: addr) { hit = p; break }
                let needle = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let compact = needle.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
                hit = tree.allParameters.first(where: {
                    let name = $0.displayName.lowercased()
                    let id = $0.identifier.lowercased()
                    return name == needle || id == needle ||
                        name.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").contains(compact) ||
                        id.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "").contains(compact)
                })
            }
            if let p = hit {
                let minV = Double(p.minValue), maxV = Double(p.maxValue), range = maxV - minV
                let scaled = (value >= 0 && value <= 1 && range > 1.0001 && !(minV == 0 && maxV == 1)) ? minV + value * range : value
                let newValue = AUValue(min(max(scaled, minV), maxV))
                auAudioUnit?.scheduleParameterBlock(AUEventSampleTimeImmediate, 0, p.address, newValue)
                p.setValue(newValue, originator: nil)
                p.value = newValue
                set += 1
            }
        }
        if set == 0 {
            let exposed = tree.allParameters.prefix(16).map { "\($0.address):\($0.displayName)" }.joined(separator: ", ")
            throw InstrumentTargetError.unsupported("Hosted \(displayName), but no writable AU parameters matched the sound-agent patch. Refusing to report false success. Exposed AU params: \(exposed.isEmpty ? "none" : exposed)")
        }
        return "Set \(set) parameter(s) on \(displayName)."
    }
}
#endif

// MARK: - Generic scaffold for proprietary-preset synths

/// Serum, Massive, Omnisphere etc. use proprietary, undocumented preset formats,
/// so Lemmings can't write their `.fxp`/native presets blind. The supported path
/// is to host them as Audio Units (see `AudioUnitTarget`) and drive parameters,
/// or drop the design as a starting note next to their preset folder.
public final class GenericPluginTarget: InstrumentTarget {
    public let displayName: String
    private let presetFolderHint: String?
    public init(name: String, presetFolderHint: String?) {
        self.displayName = name; self.presetFolderHint = presetFolderHint
    }
    public var parameters: [PluginParam] { [] }
    @discardableResult public func apply(_ design: SoundDesign) throws -> String {
        let url = try writeDesignHandoff(design)
        return "Saved a sound-design handoff for \(displayName) → \(url.path). To apply it live, host \(displayName) on the selected track as an Audio Unit and the agent will drive its exposed AU parameters directly."
    }

    private func writeDesignHandoff(_ design: SoundDesign) throws -> URL {
        let base: URL
        if let presetFolderHint, !presetFolderHint.isEmpty {
            let expanded = (presetFolderHint as NSString).expandingTildeInPath
            base = URL(fileURLWithPath: expanded, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Music/LemmingsStudio/Sound Designs/\(displayName)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let safe = design.presetName.replacingOccurrences(of: "/", with: "-")
        let url = base.appendingPathComponent("\(safe).lemmings-sounddesign.md")
        let params = design.params.keys.sorted().map { "- \($0): \(design.params[$0] ?? 0)" }.joined(separator: "\n")
        let analog = design.analog.map { a in
            """
            - cutoff: \(a.cutoff)
            - resonance: \(a.resonance)
            - attack: \(a.attack)
            - decay: \(a.decay)
            - sustain: \(a.sustain)
            - release: \(a.release)
            - gain: \(a.gain)
            """
        } ?? "- no built-in analog macro block"
        let body = """
        # \(design.presetName)

        Target: \(displayName)

        \(design.notes)

        ## Macro / parameter plan
        \(params.isEmpty ? "- no explicit plugin parameters" : params)

        ## Built-in synth reference
        \(analog)

        ## How to use
        Proprietary synth preset files are not written blindly. Load/host \(displayName) as an Audio Unit inside LemmingsStudio, then run the Sound Agent again so it can drive exposed AU parameters live. Use this note as a manual recipe or macro-mapping reference.
        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}



/// VST/VST3 instruments hosted through Carla are not opaque anymore: the Sound
/// Agent can target numeric Carla parameters via the bridge's OSC control path.
/// Because VST3 parameter metadata is not available until Carla owns the plug-in,
/// this target exposes safe macro/index slots. Agent prompts should prefer
/// `macro_1...macro_8` or explicit `param_0...param_63` controls.
public final class CarlaBridgedPluginTarget: InstrumentTarget {
    public let displayName: String
    private let pluginPath: String?
    private let format: PluginFormat

    public init(name: String, pluginPath: String?, format: PluginFormat) {
        self.displayName = name
        self.pluginPath = pluginPath
        self.format = format
    }

    public var parameters: [PluginParam] { CarlaBridgeSupport.agenticParameters(for: displayName) }

    @discardableResult public func apply(_ design: SoundDesign) throws -> String {
        guard format != .audioUnit else { throw InstrumentTargetError.unsupported("Use native AU hosting for Audio Unit parameter control.") }
        guard !(pluginPath?.isEmpty ?? true) else {
            throw InstrumentTargetError.unsupported("\(displayName) is selected, but LemmingsStudio does not know its VST/VST3 bundle path yet. Rescan plug-ins, then select the discovered Serum 2 entry instead of the generic known-synth placeholder.")
        }

        var sendable = DeviceTranslationLayer.carlaMacroParams(from: design.params)
        if sendable.isEmpty {
            sendable = DeviceTranslationLayer.fallbackMacroParams(from: design.notes + "\n" + design.presetName, targetName: displayName)
        }

        let targetDisplayName = displayName
        let targetPluginPath = pluginPath
        let targetFormat = format
        let targetParams = sendable

        let immediateSummary = CarlaBridgeSupport.applyAgenticParameters(pluginName: targetDisplayName, pluginPath: targetPluginPath, format: targetFormat, params: targetParams)
        Task { @MainActor in
            CarlaBridgeSupport.openBridge(forPluginName: targetDisplayName, pluginPath: targetPluginPath, format: targetFormat) { _ in }
            // Give carla-single a moment to create the client before sending again.
            // UDP is fire-and-forget, so this retry is the difference between a real
            // first apply and a false "sent 0/nowhere" status when Serum 2 is cold.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                _ = CarlaBridgeSupport.applyAgenticParameters(pluginName: targetDisplayName, pluginPath: targetPluginPath, format: targetFormat, params: targetParams)
            }
        }
        let mapped = sendable.keys.sorted().joined(separator: ", ")
        return "Opened/targeted Carla-bridged \(displayName) for ‘\(design.presetName)’ and queued \(sendable.count) agentic control(s): \(mapped). \(immediateSummary)"
    }
}

// MARK: - Known synths + scanner

public struct KnownSynth: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var presetFolderHint: String?
    public var writablePresets: Bool      // true only where the format is open (Vital)
}

public enum KnownPlugins {
    public static let synths: [KnownSynth] = [
        KnownSynth(name: "Built-in Analog", presetFolderHint: nil, writablePresets: true),
        KnownSynth(name: "Vital", presetFolderHint: "~/Music/Vital", writablePresets: true),
        KnownSynth(name: "Serum", presetFolderHint: "~/Music/Xfer/Serum Presets", writablePresets: false),
        KnownSynth(name: "Serum 2", presetFolderHint: "~/Music/Xfer/Serum 2 Presets", writablePresets: false),
        KnownSynth(name: "Massive", presetFolderHint: nil, writablePresets: false),
        KnownSynth(name: "Massive X", presetFolderHint: nil, writablePresets: false),
        KnownSynth(name: "Omnisphere", presetFolderHint: nil, writablePresets: false),
    ]
}

public enum PluginFormat: String, CaseIterable, Identifiable, Sendable {
    case audioUnit = "AU"
    case vst3 = "VST3"
    case vst = "VST"
    public var id: String { rawValue }
}

public enum PluginRole: String, CaseIterable, Identifiable, Sendable {
    case instrument = "Instrument"
    case effect = "Effect"
    case unknown = "Unknown"
    public var id: String { rawValue }
}

public struct DiscoveredPlugin: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var manufacturer: String
    public var isKnownSynth: Bool
    public var format: PluginFormat
    public var role: PluginRole
    public var path: String?

    public init(id: String, name: String, manufacturer: String, isKnownSynth: Bool,
                format: PluginFormat = .audioUnit, role: PluginRole = .instrument, path: String? = nil) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.isKnownSynth = isKnownSynth
        self.format = format
        self.role = role
        self.path = path
    }

    public var displaySubtitle: String {
        var pieces = [format.rawValue, role.rawValue]
        if !manufacturer.isEmpty { pieces.append(manufacturer) }
        if let path { pieces.append(path) }
        return pieces.joined(separator: " · ")
    }
}



public enum PluginDragPasteboard {
    public static let pluginPrefix = "lemmings-plugin:"
    public static let builtinEffectPrefix = "lemmings-effect:"
    public static let samplePrefix = "lemmings-sample:"
    public static let spliceSamplePrefix = "lemmings-splice-sample:"
    public static let mixerDevicePrefix = "lemmings-mixer-device:"

    public static func encode(_ plugin: DiscoveredPlugin) -> String {
        pluginPrefix + plugin.id
    }

    public static func encode(_ kind: DeviceKind) -> String {
        builtinEffectPrefix + kind.rawValue
    }

    public static func encodeSample(path: String) -> String {
        samplePrefix + path
    }

    public static func encodeSpliceSample(id: String) -> String {
        spliceSamplePrefix + id
    }

    public static func encodeMixerDevice(ownerKind: String, ownerID: UUID, deviceID: UUID) -> String {
        "\(mixerDevicePrefix)\(ownerKind):\(ownerID.uuidString):\(deviceID.uuidString)"
    }

    public static func pluginID(from text: String) -> String? {
        text.hasPrefix(pluginPrefix) ? String(text.dropFirst(pluginPrefix.count)) : nil
    }

    public static func effectKind(from text: String) -> DeviceKind? {
        guard text.hasPrefix(builtinEffectPrefix) else { return nil }
        let raw = String(text.dropFirst(builtinEffectPrefix.count))
        return DeviceKind(rawValue: raw)
    }

    public static func samplePath(from text: String) -> String? {
        text.hasPrefix(samplePrefix) ? String(text.dropFirst(samplePrefix.count)) : nil
    }

    public static func spliceSampleID(from text: String) -> String? {
        text.hasPrefix(spliceSamplePrefix) ? String(text.dropFirst(spliceSamplePrefix.count)) : nil
    }

    public static func mixerDevice(from text: String) -> (ownerKind: String, ownerID: UUID, deviceID: UUID)? {
        guard text.hasPrefix(mixerDevicePrefix) else { return nil }
        let body = String(text.dropFirst(mixerDevicePrefix.count))
        let parts = body.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let ownerID = UUID(uuidString: parts[1]), let deviceID = UUID(uuidString: parts[2]) else { return nil }
        return (parts[0], ownerID, deviceID)
    }
}

public enum PluginScanner {
    public static let defaultSearchPaths = [
        Bundle.main.builtInPlugInsURL?.path ?? Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns").path,
        "/Library/Audio/Plug-Ins/Components",
        "~/Library/Audio/Plug-Ins/Components",
        "/Library/Audio/Plug-Ins/VST3",
        "~/Library/Audio/Plug-Ins/VST3",
        "/Library/Audio/Plug-Ins/VST",
        "~/Library/Audio/Plug-Ins/VST"
    ] + ((try? FileManager.default.contentsOfDirectory(atPath:"/Volumes")) ?? []).flatMap { volume in
        ["system","user"].flatMap { scope in ["Components","VST3","VST"].map {"/Volumes/\(volume)/Audio-Plugins/\(scope)/\($0)"} }
    }

    /// Scan Audio Units through the system component manager, then enumerate VST/VST3/AU bundles on disk.
    /// Audio Units can be instantiated by Lemmings. VST/VST3 are indexed for browsing/targeting,
    /// but need a dedicated VST host bridge before they can be processed directly.
    public static func scanAllPlugins(extraSearchPaths: [String] = []) -> [DiscoveredPlugin] {
        var out: [DiscoveredPlugin] = []
        out.append(contentsOf: scanAudioUnits())
        out.append(contentsOf: scanPluginBundles(searchPaths: defaultSearchPaths + extraSearchPaths))
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.sorted {
            if $0.role.rawValue != $1.role.rawValue { return $0.role.rawValue < $1.role.rawValue }
            if $0.format.rawValue != $1.format.rawValue { return $0.format.rawValue < $1.format.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Back-compat for older panels.
    public static func scanAudioUnitInstruments() -> [DiscoveredPlugin] {
        scanAllPlugins().filter { $0.format == .audioUnit && $0.role == .instrument }
    }

    public static func scanAudioUnits() -> [DiscoveredPlugin] {
        #if canImport(AVFoundation)
        let known = Set(KnownPlugins.synths.map { $0.name.lowercased() })
        let roles: [(OSType, PluginRole)] = [(kAudioUnitType_MusicDevice, .instrument), (kAudioUnitType_Effect, .effect), (kAudioUnitType_MusicEffect, .effect)]
        return roles.flatMap { componentType, role in
            var desc = AudioComponentDescription()
            desc.componentType = componentType
            return AVAudioUnitComponentManager.shared().components(matching: desc).map { comp in
                DiscoveredPlugin(id: "AU.\(role.rawValue).\(comp.manufacturerName).\(comp.name)",
                                 name: comp.name,
                                 manufacturer: comp.manufacturerName,
                                 isKnownSynth: known.contains(comp.name.lowercased()),
                                 format: .audioUnit,
                                 role: role,
                                 path: nil)
            }
        }
        #else
        return []
        #endif
    }

    public static func classifyPluginRole(name: String, path: String? = nil) -> PluginRole {
        if name.caseInsensitiveCompare("VoxGarden") == .orderedSame { return .effect }
        let lower = ([name, path ?? ""].joined(separator: " ")).lowercased()
        let instrumentHints = ["synth", "serum", "vital", "massive", "omnisphere", "kontakt", "instrument", "piano", "keys", "organ", "bass", "drum", "sampler", "rompler", "fm", "wavetable", "uhe", "diva", "pigments", "spire", "sylenth"]
        let effectHints = ["eq", "compress", "limiter", "reverb", "delay", "echo", "chorus", "flanger", "phaser", "distortion", "saturat", "filter", "gate", "de-esser", "clipper", "shaper", "pan", "widen", "meter", "analyzer", "tuner", "kickstart", "sidechain", "neutron", "ozone", "pro-q"]
        if instrumentHints.contains(where: { lower.contains($0) }) { return .instrument }
        if effectHints.contains(where: { lower.contains($0) }) { return .effect }
        return .unknown
    }

    public static func scanPluginBundles(searchPaths: [String] = defaultSearchPaths) -> [DiscoveredPlugin] {
        let fm = FileManager.default
        let roots = searchPaths.map { NSString(string: $0).expandingTildeInPath }

        var out: [DiscoveredPlugin] = []
        for root in roots where fm.fileExists(atPath: root) {
            guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: root),
                                                includingPropertiesForKeys: [.isDirectoryKey],
                                                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ["component", "vst3", "vst"].contains(ext) else { continue }
                if ext == "component", let entries=Bundle(url:url)?.infoDictionary?["AudioComponents"] as? [[String:Any]],!entries.isEmpty {
                    for entry in entries {
                        guard let name=entry["name"] as? String,let type=entry["type"] as? String,let sub=entry["subtype"] as? String,let maker=entry["manufacturer"] as? String else {continue}
                        let role:PluginRole = type == "aumu" || type == "augn" ? .instrument : .effect
                        out.append(DiscoveredPlugin(id:"AU.component.\(type).\(sub).\(maker)",name:name,manufacturer:maker,isKnownSynth:role == .instrument,format:.audioUnit,role:role,path:url.path))
                    }
                    continue
                }
                let name = url.deletingPathExtension().lastPathComponent
                let format: PluginFormat = ext == "component" ? .audioUnit : (ext == "vst3" ? .vst3 : .vst)
                let lower = name.lowercased()
                let role: PluginRole = Self.classifyPluginRole(name: name, path: url.path)
                out.append(DiscoveredPlugin(id: "\(format.rawValue).file.\(url.path)",
                                            name: name,
                                            manufacturer: "Local",
                                            isKnownSynth: KnownPlugins.synths.contains { lower.contains($0.name.lowercased()) },
                                            format: format,
                                            role: role,
                                            path: url.path))
            }
        }
        return out
    }
}
