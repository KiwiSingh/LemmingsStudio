import Foundation

public enum DrumPadPreset: String, CaseIterable, Identifiable, Sendable {
    case generalMIDI = "General MIDI / ATOM"
    case mpkMini = "MPK Mini"
    case mpc16 = "MPC 16 Pads"
    case custom = "Custom"

    public var id: String { rawValue }

    public var notes: [Int: DrumVoiceID] {
        switch self {
        case .generalMIDI:
            return [
                36: .kick, 35: .sub808, 38: .snare, 40: .snare,
                39: .clap, 37: .rim, 42: .closedHat, 46: .openHat,
                45: .tom, 47: .tom, 49: .crash, 51: .ride
            ]
        case .mpkMini:
            // Common Akai MPK Mini pad defaults. Users can transpose or switch to Custom.
            return [
                36: .kick, 37: .snare, 38: .clap, 39: .closedHat,
                40: .openHat, 41: .tom, 42: .crash, 43: .sub808,
                44: .rim, 45: .ride, 46: .closedHat, 47: .openHat
            ]
        case .mpc16:
            return [
                36: .kick, 37: .rim, 38: .snare, 39: .clap,
                40: .snare, 41: .tom, 42: .closedHat, 43: .tom,
                44: .closedHat, 45: .tom, 46: .openHat, 47: .tom,
                48: .tom, 49: .crash, 50: .tom, 51: .ride
            ]
        case .custom:
            return [:]
        }
    }
}

public struct DrumPadAssignment: Identifiable, Hashable, Sendable {
    public var note: Int
    public var voice: DrumVoiceID
    public var id: String { "\(note)-\(voice.rawValue)" }
    public init(note: Int, voice: DrumVoiceID) {
        self.note = note
        self.voice = voice
    }
}

public enum DrumPadMapper {
    public static func assignments(preset: DrumPadPreset, customText: String, transpose: Int) -> [DrumPadAssignment] {
        let base: [Int: DrumVoiceID]
        if preset == .custom {
            base = parseCustomMap(customText)
        } else {
            base = preset.notes
        }
        return base.map { note, voice in DrumPadAssignment(note: note + transpose, voice: voice) }
            .sorted { lhs, rhs in lhs.note == rhs.note ? lhs.voice.rawValue < rhs.voice.rawValue : lhs.note < rhs.note }
    }

    public static func voice(for note: Int, preset: DrumPadPreset, customText: String, transpose: Int) -> DrumVoiceID? {
        let adjusted = note - transpose
        if preset == .custom { return parseCustomMap(customText)[adjusted] }
        return preset.notes[adjusted] ?? DrumVoiceID.from(midiNote: note)
    }

    public static func parseCustomMap(_ text: String) -> [Int: DrumVoiceID] {
        var result: [Int: DrumVoiceID] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split { $0 == ":" || $0 == "=" || $0 == "," || $0 == "\t" || $0 == " " }
            guard parts.count >= 2, let note = Int(parts[0]) else { continue }
            let wanted = parts.dropFirst().joined(separator: " ").lowercased()
            if let voice = DrumVoiceID.allCases.first(where: { voice in
                wanted == voice.label.lowercased()
                || wanted == voice.debugName.lowercased()
                || wanted == voice.rawValue.description
            }) {
                result[note] = voice
            }
        }
        return result
    }

    public static let defaultCustomMap = """
    # MIDI note : drum voice
    36: kick
    37: rim
    38: snare
    39: clap
    42: closedhat
    46: openhat
    45: tom
    49: crash
    51: ride
    35: sub808
    """
}

public extension DrumVoiceID {
    var debugName: String {
        switch self {
        case .kick: return "kick"
        case .sub808: return "sub808"
        case .snare: return "snare"
        case .clap: return "clap"
        case .rim: return "rim"
        case .closedHat: return "closedhat"
        case .openHat: return "openhat"
        case .tom: return "tom"
        case .ride: return "ride"
        case .crash: return "crash"
        }
    }
}
