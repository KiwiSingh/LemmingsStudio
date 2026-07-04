import Foundation

public struct MIDIControllerPreset: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var maker: String
    public var notes: String
    public var ccMap: [Int: String]
    public var padNotes: [Int: DrumVoiceID]
}

public enum MIDIControllerPresetLibrary {
    public static let presets: [MIDIControllerPreset] = [
        MIDIControllerPreset(id: "akai-mpk-mini", name: "MPK Mini", maker: "Akai", notes: "Pads default around GM drum notes; knobs map to macro 1-8.", ccMap: [70:"macro1",71:"macro2",72:"macro3",73:"macro4",74:"cutoff",75:"resonance",76:"macro7",77:"macro8"], padNotes: [36:.kick,38:.snare,42:.closedHat,46:.openHat,49:.crash,45:.tom,39:.clap,51:.ride]),
        MIDIControllerPreset(id: "akai-mpk-mini-iv", name: "MPK Mini IV", maker: "Akai", notes: "Sanity preset for MPK Mini IV-style compact keyboards: eight knobs as macros/filter controls, pads on GM drum notes, pitch bend learned as a high-resolution control source when moved during MIDI Learn.", ccMap: [70:"macro1",71:"macro2",72:"macro3",73:"macro4",74:"cutoff",75:"resonance",76:"macro7",77:"macro8"], padNotes: [36:.kick,38:.snare,42:.closedHat,46:.openHat,49:.crash,45:.tom,39:.clap,51:.ride]),
        MIDIControllerPreset(id: "presonus-atom", name: "ATOM", maker: "PreSonus", notes: "16-pad GM-ish drum rack profile.", ccMap: [14:"macro1",15:"macro2",16:"macro3",17:"macro4"], padNotes: [36:.kick,37:.rim,38:.snare,39:.clap,42:.closedHat,46:.openHat,45:.tom,49:.crash]),
        MIDIControllerPreset(id: "novation-launchkey", name: "Launchkey", maker: "Novation", notes: "Common eight-knob instrument/effect macro profile.", ccMap: [21:"macro1",22:"macro2",23:"macro3",24:"macro4",25:"macro5",26:"macro6",27:"macro7",28:"macro8"], padNotes: [36:.kick,38:.snare,42:.closedHat,46:.openHat])
    ]
}
