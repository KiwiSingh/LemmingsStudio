import Foundation

/// Typed fields own known keys; opaque extension fields survive save and edits.
enum DocumentPreservation {
    private static let known: [String: Set<String>] = [
        "root": Set(["version", "name", "tempo", "bpm", "beatsPerBar", "lengthBars", "keyRoot", "keyName", "scaleName", "keySnapEnabled", "tempoAutomationEnabled", "tempoPoints", "tracks", "returnBuses", "sampleRate", "bitDepth", "channelFormat", "groups", "masterDevices", "swingAmount", "customChannelCount", "channelNames"]),
        "tracks": Set(["id", "name", "kind", "colorIndex", "clips", "audioClips", "devices", "automationLanes", "externalPluginSlots", "pluginTargetID", "sequencerLayers", "armed", "inputMonitor", "audioInputMonitorMode", "audioInputDeviceUID", "audioInputDeviceName", "audioInputChannelIndex", "useStepSequencer", "volume", "pan", "mute", "solo", "sends", "outputBusName", "outputMode", "outputChannelIndex", "panMode", "stereoWidth", "loopDragEnabled", "sequencerPrintSourceTrackID", "sequencerPrintTargetTrackID", "groupID", "drumGenre", "stepPattern", "frozen", "bounced"]),
        "sequencerLayers": Set(["id", "name", "source", "note", "steps", "velocity", "samplePath", "embeddedSamples", "pluginTargetID", "octaveOffset", "pan", "volume"]),
        "clips": Set(["id", "name", "startBeat", "lengthBeats", "notes", "isActive", "loopEnabled", "loopLengthBeats"]),
        "notes": Set(["id", "pitch", "start", "length", "velocity"]),
        "audioClips": Set(["id", "startBeat", "samples", "sampleRate", "devices", "externalPluginSlots", "warpEnabled", "warpMode", "originalTempo", "manualTempoOverride", "displayName", "sourceURL", "isActive", "lengthBeatsOverride", "trimStartBeats", "loopEnabled", "loopLengthBeats", "gainDB", "pitchSemitones", "pitchCents"]),
        "devices": Set(["id", "kind", "bypassed", "mono", "params", "sidechainEnabled", "sidechainInputTrackID"]),
        "bounced": Set(["id", "startBeat", "samples", "sampleRate", "devices", "externalPluginSlots", "warpEnabled", "warpMode", "originalTempo", "manualTempoOverride", "displayName", "sourceURL", "isActive", "lengthBeatsOverride", "trimStartBeats", "loopEnabled", "loopLengthBeats", "gainDB", "pitchSemitones", "pitchCents"]),
        "masterDevices": Set(["id", "kind", "bypassed", "mono", "params", "sidechainEnabled", "sidechainInputTrackID"]),
        "externalPluginSlots": Set(["id", "pluginID", "name", "format", "role", "path", "hosted"]),
        "sends": Set(["id", "returnBusID", "amount", "preFader"]),
        "returnBuses": Set(["id", "name", "devices", "volume", "pan", "mute"]),
        "groups": Set(["id", "name", "trackIDs", "devices", "volume", "pan", "mute", "solo", "automationLanes"]),
        "automationLanes": Set(["nodeID", "paramID", "points", "enabled"]),
        "points": Set(["beat", "value"]),
        "tempoPoints": Set(["beat", "bpm"]),
    ]
    static func merge(original: Data?, updated: Data) throws -> Data {
        guard let original else { return updated }
        let old = try JSONSerialization.jsonObject(with: original)
        let new = try JSONSerialization.jsonObject(with: updated)
        return try JSONSerialization.data(withJSONObject: mergeValue(old, new, role: "root"), options: [.prettyPrinted, .sortedKeys])
    }
    private static func identity(_ object: [String: Any]) -> String? {
        if let id = object["id"] as? String { return "id:" + id.lowercased() }
        if let node = object["nodeID"] as? String, let param = object["paramID"] as? String {
            return "lane:" + node + ":" + param
        }
        return nil
    }
    private static func mergeValue(_ old: Any?, _ new: Any, role: String) -> Any {
        if role == "params" { return new }
        if let current = new as? [String: Any] {
            let previous = old as? [String: Any] ?? [:]
            var result = previous
            for key in known[role] ?? [] where current[key] == nil { result.removeValue(forKey: key) }
            for (key, value) in current { result[key] = mergeValue(previous[key], value, role: key) }
            return result
        }
        if let current = new as? [Any] {
            let previous = old as? [Any] ?? []
            return current.enumerated().map { index, value -> Any in
                guard let object = value as? [String: Any] else { return value }
                if let key = identity(object) {
                    let match = previous.first { candidate in
                        guard let candidate = candidate as? [String: Any] else { return false }
                        return identity(candidate) == key
                    }
                    let legacy = index < previous.count ? previous[index] as? [String: Any] : nil
                    let base: Any? = match ?? legacy.flatMap { identity($0) == nil ? $0 : nil }
                    return mergeValue(base, value, role: role)
                }
                return mergeValue(index < previous.count ? previous[index] : nil, value, role: role)
            }
        }
        return new
    }
}
