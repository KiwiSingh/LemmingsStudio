import Foundation

struct VisionVirtualMIDIKeyboardState: Codable, Sendable {
    var baseOctave: Int = 3
    var visibleOctaves: Int = 2
    var velocity: UInt8 = 96
    var latch: Bool = false
    var scaleAssist: Bool = false
    var activeNotes: Set<UInt8> = []
    var lastEventSummary: String = "Virtual keyboard idle"

    var firstNote: UInt8 { UInt8(max(0, min(108, (baseOctave + 1) * 12))) }
    var noteCount: Int { max(12, min(48, visibleOctaves * 12)) }
}

struct VisionMIDIDeviceSummary: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var kind: String
    var isBluetoothLikely: Bool
    var isConnected: Bool
}

extension VisionStudioModel {
    func virtualMIDINoteDown(_ note: UInt8) {
        if virtualKeyboard.latch && virtualKeyboard.activeNotes.contains(note) {
            virtualMIDINoteUp(note)
            return
        }
        virtualKeyboard.activeNotes.insert(note)
        virtualKeyboard.lastEventSummary = "Note on \(note) velocity \(virtualKeyboard.velocity)"
        beginMIDIRecordingNote(note, velocity: virtualKeyboard.velocity)
        performMIDINoteOn(note: note, velocity: virtualKeyboard.velocity, guaranteeLocalAudition: true)
    }

    func virtualMIDINoteUp(_ note: UInt8) {
        guard virtualKeyboard.activeNotes.contains(note) else { return }
        if virtualKeyboard.latch { return }
        virtualKeyboard.activeNotes.remove(note)
        virtualKeyboard.lastEventSummary = "Note off \(note)"
        endMIDIRecordingNote(note)
        performMIDINoteOff(note: note, guaranteeLocalAudition: true)
    }

    func virtualMIDIToggleLatchedNote(_ note: UInt8) {
        if virtualKeyboard.activeNotes.contains(note) {
            virtualKeyboard.activeNotes.remove(note)
            virtualKeyboard.lastEventSummary = "Latched note off \(note)"
            endMIDIRecordingNote(note)
            performMIDINoteOff(note: note, guaranteeLocalAudition: true)
        } else {
            virtualKeyboard.activeNotes.insert(note)
            virtualKeyboard.lastEventSummary = "Latched note on \(note)"
            beginMIDIRecordingNote(note, velocity: virtualKeyboard.velocity)
            performMIDINoteOn(note: note, velocity: virtualKeyboard.velocity, guaranteeLocalAudition: true)
        }
    }

    func allVirtualMIDINotesOff() {
        for note in virtualKeyboard.activeNotes { performMIDINoteOff(note: note, guaranteeLocalAudition: true) }
        virtualKeyboard.activeNotes.removeAll()
        virtualKeyboard.lastEventSummary = "All notes off"
    }

    func refreshMIDIDevices() {
        midiManager.refreshSources()
        midiSourceSummary = midiManager.sourceNames.isEmpty ? "None" : midiManager.sourceNames.joined(separator: ", ")
        bluetoothMIDIDevices = midiManager.deviceSummaries
        statusMessage = "MIDI devices refreshed: \(midiSourceSummary)"
    }

    func performMIDINoteOn(note: UInt8, velocity: UInt8, guaranteeLocalAudition: Bool = false) {
        ensureAudioEngineRunningForLiveMIDI()
        if guaranteeLocalAudition || (!audioUnitHost.hasActiveInstrument && desktopBridge.activeInstanceID == nil) {
            audioEngine.noteOn(note: note, velocity: velocity)
        }
        audioUnitHost.sendNoteOn(note: note, velocity: velocity)
        desktopBridge.sendMIDI(status: 0x90, data1: note, data2: velocity)
    }

    /// Live MIDI input must be audible even when transport playback has never been started.
    /// The transport path starts the engine in `play()`, but a spatial keyboard can be opened
    /// and performed independently, so lazily start the engine on the first note-on.
    private func ensureAudioEngineRunningForLiveMIDI() {
        guard !audioEngineRunning else { return }
        do {
            try audioEngine.start()
            audioEngineRunning = true
            statusMessage = "Audio engine started for live MIDI input"
        } catch {
            audioEngineRunning = false
            statusMessage = "Audio unavailable: \(error.localizedDescription)"
        }
    }

    func performMIDINoteOff(note: UInt8, guaranteeLocalAudition: Bool = false) {
        if guaranteeLocalAudition || (!audioUnitHost.hasActiveInstrument && desktopBridge.activeInstanceID == nil) { audioEngine.noteOff(note: note) }
        audioUnitHost.sendNoteOff(note: note)
        desktopBridge.sendMIDI(status: 0x80, data1: note, data2: 0)
    }
}
