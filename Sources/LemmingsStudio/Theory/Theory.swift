import Foundation

// MARK: - Pitch

/// A pitch class 0...11 where 0 == C.
public typealias PitchClass = Int

public enum NoteName: Int, CaseIterable, Identifiable {
    case c = 0, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b
    public var id: Int { rawValue }

    public var sharpLabel: String {
        ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][rawValue]
    }
    public var flatLabel: String {
        ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"][rawValue]
    }
}

public struct MIDINote: Equatable, Hashable {
    public var number: Int            // 0...127, 60 == middle C
    public init(_ number: Int) { self.number = max(0, min(127, number)) }

    public var pitchClass: PitchClass { ((number % 12) + 12) % 12 }
    public var octave: Int { number / 12 - 1 }
    public var name: String { NoteName(rawValue: pitchClass)!.sharpLabel + "\(octave)" }

    /// Equal-tempered frequency in Hz (A4 = 440).
    public var frequency: Double { 440.0 * pow(2.0, Double(number - 69) / 12.0) }
}

// MARK: - Scales

/// A scale is defined by ascending semitone steps within one octave.
public struct Scale: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    /// Semitone offsets from the root, e.g. major = [0,2,4,5,7,9,11].
    public let intervals: [Int]
    /// Marks scales that only approximate microtonal systems in 12-TET.
    public let isMicrotonalApproximation: Bool

    public init(_ name: String, _ intervals: [Int], approximate: Bool = false) {
        self.name = name
        self.intervals = intervals
        self.isMicrotonalApproximation = approximate
    }

    /// Pitch classes for a given root.
    public func pitchClasses(root: PitchClass) -> Set<PitchClass> {
        Set(intervals.map { (($0 + root) % 12 + 12) % 12 })
    }

    /// Absolute MIDI notes across a range for a given root pitch class.
    public func notes(root: PitchClass, from low: Int = 36, to high: Int = 84) -> [MIDINote] {
        (low...high).compactMap { n in
            pitchClasses(root: root).contains(((n % 12) + 12) % 12) ? MIDINote(n) : nil
        }
    }
}

public enum ScaleLibrary {
    // Common
    public static let major          = Scale("Major (Ionian)", [0,2,4,5,7,9,11])
    public static let naturalMinor   = Scale("Natural Minor (Aeolian)", [0,2,3,5,7,8,10])
    public static let harmonicMinor  = Scale("Harmonic Minor", [0,2,3,5,7,8,11])
    public static let melodicMinor   = Scale("Melodic Minor", [0,2,3,5,7,9,11])
    // Modes
    public static let dorian         = Scale("Dorian", [0,2,3,5,7,9,10])
    public static let phrygian       = Scale("Phrygian", [0,1,3,5,7,8,10])
    public static let lydian         = Scale("Lydian", [0,2,4,6,7,9,11])
    public static let mixolydian     = Scale("Mixolydian", [0,2,4,5,7,9,10])
    public static let locrian        = Scale("Locrian", [0,1,3,5,6,8,10])
    // Pentatonic / blues
    public static let majorPent      = Scale("Major Pentatonic", [0,2,4,7,9])
    public static let minorPent      = Scale("Minor Pentatonic", [0,3,5,7,10])
    public static let blues          = Scale("Blues", [0,3,5,6,7,10])
    // Symmetric
    public static let wholeTone      = Scale("Whole Tone", [0,2,4,6,8,10])
    public static let octatonicHW    = Scale("Octatonic (H-W)", [0,1,3,4,6,7,9,10])
    public static let octatonicWH    = Scale("Octatonic (W-H)", [0,2,3,5,6,8,9,11])
    // Exotic / world
    public static let harmonicMajor  = Scale("Harmonic Major", [0,2,4,5,7,8,11])
    public static let doubleHarmonic = Scale("Double Harmonic (Byzantine)", [0,1,4,5,7,8,11])
    public static let hungarianMinor = Scale("Hungarian Minor", [0,2,3,6,7,8,11])
    public static let phrygianDom    = Scale("Phrygian Dominant (Freygish)", [0,1,4,5,7,8,10])
    public static let persian        = Scale("Persian", [0,1,4,5,6,8,11])
    public static let hijaz          = Scale("Hijaz (maqam ≈12-TET)", [0,1,4,5,7,8,10], approximate: true)
    public static let bhairav        = Scale("Bhairav (raga ≈12-TET)", [0,1,4,5,7,8,11], approximate: true)
    public static let todi           = Scale("Todi (raga ≈12-TET)", [0,1,3,6,7,8,11], approximate: true)
    public static let marwa          = Scale("Marwa (raga ≈12-TET)", [0,1,4,6,7,9,11], approximate: true)
    public static let bhairavi       = Scale("Bhairavi (raga ≈12-TET)", [0,1,3,5,7,8,10], approximate: true)
    public static let yaman          = Scale("Yaman / Kalyan (raga ≈12-TET)", [0,2,4,6,7,9,11], approximate: true)

    public static let all: [Scale] = [
        major, naturalMinor, harmonicMinor, melodicMinor,
        dorian, phrygian, lydian, mixolydian, locrian,
        majorPent, minorPent, blues,
        wholeTone, octatonicHW, octatonicWH,
        harmonicMajor, doubleHarmonic, hungarianMinor, phrygianDom, persian,
        hijaz, bhairav, todi, marwa, bhairavi, yaman
    ]
}

// MARK: - Key + snapping

public struct MusicalKey: Equatable {
    public var root: PitchClass
    public var scaleName: String
    public var intervals: [Int]

    public init(root: PitchClass, scale: Scale) {
        self.root = root
        self.scaleName = scale.name
        self.intervals = scale.intervals
    }

    public var scale: Scale { Scale(scaleName, intervals) }
    public var pitchClasses: Set<PitchClass> { scale.pitchClasses(root: root) }
    public var displayName: String { "\(NoteName(rawValue: root)!.sharpLabel) \(scaleName)" }

    public func contains(_ note: MIDINote) -> Bool { pitchClasses.contains(note.pitchClass) }

    /// Snap an arbitrary MIDI note to the nearest in-key note (Ableton-style "fold to scale").
    public func snap(_ note: MIDINote) -> MIDINote {
        if contains(note) { return note }
        for delta in 1...6 {
            if pitchClasses.contains((((note.number - delta) % 12) + 12) % 12) {
                return MIDINote(note.number - delta)
            }
            if pitchClasses.contains((((note.number + delta) % 12) + 12) % 12) {
                return MIDINote(note.number + delta)
            }
        }
        return note
    }
}

// MARK: - Chords

public struct Chord: Identifiable, Hashable {
    public let id = UUID()
    public let symbol: String
    public let rootPitchClass: PitchClass
    public let intervals: [Int]   // semitone offsets from root, e.g. major triad [0,4,7]

    public init(symbol: String, root: PitchClass, intervals: [Int]) {
        self.symbol = symbol
        self.rootPitchClass = root
        self.intervals = intervals
    }

    public func midiNotes(octave: Int = 4) -> [MIDINote] {
        let base = (octave + 1) * 12 + rootPitchClass
        return intervals.map { MIDINote(base + $0) }
    }
}

public enum ChordQuality: String, CaseIterable {
    case major = "", minor = "m", diminished = "dim", augmented = "aug"
    case major7 = "maj7", minor7 = "m7", dominant7 = "7", halfDim7 = "m7b5", dim7 = "dim7"
    case sus2 = "sus2", sus4 = "sus4", add9 = "add9"

    public var intervals: [Int] {
        switch self {
        case .major:      return [0,4,7]
        case .minor:      return [0,3,7]
        case .diminished: return [0,3,6]
        case .augmented:  return [0,4,8]
        case .major7:     return [0,4,7,11]
        case .minor7:     return [0,3,7,10]
        case .dominant7:  return [0,4,7,10]
        case .halfDim7:   return [0,3,6,10]
        case .dim7:       return [0,3,6,9]
        case .sus2:       return [0,2,7]
        case .sus4:       return [0,5,7]
        case .add9:       return [0,4,7,14]
        }
    }
}

// MARK: - Circle of Fifths

public struct CircleOfFifths {
    /// Clockwise from C: each step is a perfect fifth up.
    public static let order: [PitchClass] = [0,7,2,9,4,11,6,1,8,3,10,5] // C G D A E B F# Db Ab Eb Bb F

    public static func relativeMinor(of major: PitchClass) -> PitchClass { ((major - 3) % 12 + 12) % 12 }
    public static func dominant(of root: PitchClass) -> PitchClass { (root + 7) % 12 }
    public static func subdominant(of root: PitchClass) -> PitchClass { ((root - 7) % 12 + 12) % 12 }

    /// Sharps (positive) or flats (negative) in the major key signature.
    public static func keySignature(major: PitchClass) -> Int {
        let sharps: [PitchClass: Int] = [0:0, 7:1, 2:2, 9:3, 4:4, 11:5, 6:6]
        let flats:  [PitchClass: Int] = [5:1, 10:2, 3:3, 8:4, 1:5, 6:6]
        if let s = sharps[major] { return s }
        if let f = flats[major]  { return -f }
        return 0
    }
}

// MARK: - Generative chords

public struct ChordGenerator {
    /// Build the diatonic chords by stacking scale tones in thirds.
    public static func diatonicChords(key: MusicalKey, sevenths: Bool = false) -> [Chord] {
        let scaleNotes = key.intervals.map { ($0 + key.root) % 12 }
        let degrees = scaleNotes.count
        guard degrees >= 3 else { return [] }
        var chords: [Chord] = []
        for i in 0..<degrees {
            var tones = [0, 2, 4]
            if sevenths { tones.append(6) }
            let pcs = tones.map { scaleNotes[(i + $0) % degrees] }
            let root = pcs[0]
            let rel = pcs.map { (($0 - root) % 12 + 12) % 12 }.sorted()
            chords.append(Chord(symbol: label(root: root, intervals: rel),
                                root: root, intervals: rel))
        }
        return chords
    }

    /// Suggest a progression. Templates are scale-degree based (1 = tonic).
    public static func progression(key: MusicalKey,
                                   template: [Int] = [1, 5, 6, 4],
                                   sevenths: Bool = false) -> [Chord] {
        let chords = diatonicChords(key: key, sevenths: sevenths)
        guard !chords.isEmpty else { return [] }
        return template.map { chords[(($0 - 1) % chords.count + chords.count) % chords.count] }
    }

    public static let progressionTemplates: [(name: String, degrees: [Int])] = [
        ("Pop I–V–vi–IV", [1,5,6,4]),
        ("Axis vi–IV–I–V", [6,4,1,5]),
        ("Jazz ii–V–I", [2,5,1]),
        ("Andalusian i–VII–VI–V", [1,7,6,5]),
        ("Blues I–IV–I–V", [1,4,1,5]),
        ("Bollywood vamp i–VI–III–VII", [1,6,3,7])
    ]

    private static func label(root: PitchClass, intervals: [Int]) -> String {
        let name = NoteName(rawValue: root)!.sharpLabel
        for q in ChordQuality.allCases where q.intervals == intervals { return name + q.rawValue }
        // fall back to nearest triad label
        if intervals.prefix(3).elementsEqual([0,3,7]) { return name + "m" }
        if intervals.prefix(3).elementsEqual([0,3,6]) { return name + "dim" }
        if intervals.prefix(3).elementsEqual([0,4,8]) { return name + "aug" }
        return name
    }
}
