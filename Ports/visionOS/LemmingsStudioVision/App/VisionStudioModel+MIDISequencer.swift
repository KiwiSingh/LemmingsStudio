import Foundation

@MainActor
extension VisionStudioModel {
    enum PianoLane: String, CaseIterable, Identifiable {
        case velocity = "Velocity"
        case modWheel = "CC1 Mod Wheel"
        case pitchBend = "Pitch Bend"
        case sustain = "Sustain"
        var id: String { rawValue }
    }

    var selectedMIDIClipLocation: (track: Int, clip: Int)? {
        guard let selectedClipID else { return nil }
        for ti in project.tracks.indices {
            if let ci = project.tracks[ti].clips.firstIndex(where: { $0.id == selectedClipID }) { return (ti, ci) }
        }
        return nil
    }


    var selectedTrackIndex: Int? {
        if let selectedTrackID,
           let index = project.tracks.firstIndex(where: { $0.id == selectedTrackID }) {
            return index
        }
        if let clipLocation = selectedMIDIClipLocation { return clipLocation.track }
        return project.tracks.firstIndex(where: { isMIDICapableTrack($0) })
    }

    func isMIDICapableTrack(_ track: VisionTrack) -> Bool {
        !track.kind.lowercased().contains("audio")
    }

    @discardableResult
    func createMIDIClip(
        onTrack index: Int,
        startBeat: Double,
        lengthBeats: Double,
        openPianoRoll: Bool = true
    ) -> UUID? {
        guard project.tracks.indices.contains(index) else {
            statusMessage = "Choose a track before creating a MIDI clip"
            return nil
        }
        guard isMIDICapableTrack(project.tracks[index]) else {
            statusMessage = "MIDI clips can only be created on Instrument, MIDI, or Drum tracks"
            return nil
        }

        let projectEnd = project.totalBeats
        let start = min(max(0, snapped(startBeat)), max(0, projectEnd - 0.125))
        let requestedEnd = min(projectEnd, max(start + 0.125, snapped(startBeat + lengthBeats)))
        let length = max(0.125, requestedEnd - start)
        let clip = VisionMIDIClip(
            id: UUID(),
            name: "MIDI Clip",
            startBeat: start,
            lengthBeats: length,
            loopLengthBeats: length,
            notes: [],
            midiEvents: []
        )

        project.tracks[index].clips.append(clip)
        project.tracks[index].clips.sort { lhs, rhs in
            if lhs.startBeat == rhs.startBeat { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.startBeat < rhs.startBeat
        }
        selectedTrackID = project.tracks[index].id
        selectedClipID = clip.id
        statusMessage = "Created MIDI Clip on \(project.tracks[index].name) at beat \(String(format: "%.2f", start))"
        if openPianoRoll { activePrimaryWorkspace = .pianoRoll }
        return clip.id
    }

    @discardableResult
    func createMIDIClipOnSelectedTrack() -> UUID? {
        guard let index = selectedTrackIndex else {
            statusMessage = "No MIDI-capable track is available"
            return nil
        }
        let oneBar = Double(max(1, project.beatsPerBar))
        return createMIDIClip(onTrack: index, startBeat: playheadBeat, lengthBeats: oneBar, openPianoRoll: true)
    }


    func togglePrimaryRecord() {
        if isRecordingMIDI {
            stopMIDIRecording()
            return
        }
        if isRecordingAudio || isArmedForPunch {
            toggleAudioRecording()
            return
        }
        if selectedMIDIClipLocation != nil || selectedTrackIndex.map({ isMIDICapableTrack(project.tracks[$0]) }) == true {
            startMIDIRecording()
        } else {
            toggleAudioRecording()
        }
    }

    func startMIDIRecording() {
        if selectedMIDIClipLocation == nil {
            guard createMIDIClipOnSelectedTrack() != nil else { return }
        }
        guard selectedMIDIClipLocation != nil else {
            statusMessage = "Select or create a MIDI clip before recording"
            return
        }
        activeMIDINoteStarts.removeAll()
        isRecordingMIDI = true
        midiRecordingStatus = "Recording MIDI…"
        statusMessage = midiRecordingStatus
        if !isPlaying { play() }
    }

    func stopMIDIRecording() {
        guard isRecordingMIDI else { return }
        let stillHeld = Array(activeMIDINoteStarts.keys)
        for note in stillHeld { endMIDIRecordingNote(note) }
        activeMIDINoteStarts.removeAll()
        isRecordingMIDI = false
        midiRecordingStatus = "MIDI recording stopped"
        statusMessage = midiRecordingStatus
    }

    func beginMIDIRecordingNote(_ note: UInt8, velocity: UInt8) {
        guard isRecordingMIDI, selectedMIDIClipLocation != nil else { return }
        activeMIDINoteStarts[note] = playheadBeat
    }

    func endMIDIRecordingNote(_ note: UInt8) {
        guard isRecordingMIDI,
              let absoluteStart = activeMIDINoteStarts.removeValue(forKey: note),
              let loc = selectedMIDIClipLocation else { return }
        let clipStart = project.tracks[loc.track].clips[loc.clip].startBeat
        let localStart = max(0, absoluteStart - clipStart)
        let localEnd = max(localStart + 0.05, playheadBeat - clipStart)
        var recorded = VisionNote(
            note: Int(note),
            startBeat: localStart,
            lengthBeats: localEnd - localStart,
            velocity: Int(virtualKeyboard.velocity)
        )
        recorded.id = UUID()
        if project.tracks[loc.track].clips[loc.clip].notes == nil {
            project.tracks[loc.track].clips[loc.clip].notes = []
        }
        project.tracks[loc.track].clips[loc.clip].notes!.append(recorded)
        statusMessage = "Recorded MIDI note \(note)"
    }

    func ensureStepSequencerDefaults() {
        if project.stepSequencer == nil { project.stepSequencer = .defaultPattern }
        guard var seq = project.stepSequencer else { return }
        seq.stepCount = max(1, min(64, seq.stepCount))
        seq.stepsPerBeat = max(1, min(8, seq.stepsPerBeat))
        for i in seq.layers.indices {
            if seq.layers[i].hits.count < seq.stepCount {
                seq.layers[i].hits += Array(repeating: false, count: seq.stepCount - seq.layers[i].hits.count)
            } else if seq.layers[i].hits.count > seq.stepCount {
                seq.layers[i].hits = Array(seq.layers[i].hits.prefix(seq.stepCount))
            }
        }
        project.stepSequencer = seq
    }

    func toggleSequencerHit(layer: Int, step: Int) {
        ensureStepSequencerDefaults()
        guard project.stepSequencer?.layers.indices.contains(layer) == true,
              project.stepSequencer?.layers[layer].hits.indices.contains(step) == true else { return }
        project.stepSequencer!.layers[layer].hits[step].toggle()
        statusMessage = "Sequencer step \(step + 1) updated"
    }

    func setSequencerStepCount(_ count: Int) {
        ensureStepSequencerDefaults()
        project.stepSequencer?.stepCount = max(1, min(64, count))
        ensureStepSequencerDefaults()
    }

    func setSequencerSwing(_ swing: Double) {
        ensureStepSequencerDefaults()
        project.stepSequencer?.swing = max(0, min(0.75, swing))
    }

    func clearSequencerLayer(_ layer: Int) {
        ensureStepSequencerDefaults()
        guard project.stepSequencer?.layers.indices.contains(layer) == true else { return }
        project.stepSequencer!.layers[layer].hits = Array(repeating: false, count: project.stepSequencer!.stepCount)
    }

    func printSequencerToArrangement() {
        ensureStepSequencerDefaults()
        guard let seq = project.stepSequencer, !seq.layers.isEmpty else { return }

        let length = Double(seq.stepCount) / Double(seq.stepsPerBeat)
        let start = snapped(playheadBeat)
        var notes: [VisionNote] = []

        for layer in seq.layers {
            for step in 0..<min(seq.stepCount, layer.hits.count) where layer.hits[step] {
                let beat = Double(step) / Double(seq.stepsPerBeat)
                let swingDelay = (step % 2 == 1) ? seq.swing / Double(seq.stepsPerBeat) : 0
                notes.append(.init(
                    id: UUID(),
                    note: layer.midiNote,
                    startBeat: beat + swingDelay,
                    lengthBeats: max(0.05, 0.35 / Double(seq.stepsPerBeat)),
                    velocity: Int(max(1, min(127, layer.volume * 110)))
                ))
            }
        }

        guard !notes.isEmpty else {
            statusMessage = "Nothing to print — enable at least one sequencer step"
            return
        }

        notes.sort {
            if $0.startBeat == $1.startBeat { return $0.note < $1.note }
            return $0.startBeat < $1.startBeat
        }

        let clip = VisionMIDIClip(
            id: UUID(),
            name: "Step Sequencer Pattern",
            startBeat: start,
            lengthBeats: length,
            loopLengthBeats: length,
            notes: notes,
            midiEvents: []
        )

        let trackName = "Step Sequencer"
        if let target = project.tracks.firstIndex(where: { $0.name == trackName }) {
            var track = project.tracks.remove(at: target)
            track.kind = "Drums"
            track.clips.append(clip)
            project.tracks.insert(track, at: 0)
        } else {
            let track = VisionTrack(
                name: trackName,
                kind: "Drums",
                clips: [clip],
                audioClips: [],
                volume: 1,
                pan: 0,
                mute: false,
                solo: false,
                sends: [:],
                outputBusId: "master"
            )
            project.tracks.insert(track, at: 0)
        }

        guard let insertedClip = project.tracks
            .flatMap(\.clips)
            .first(where: { $0.id == clip.id }),
              let insertedNotes = insertedClip.notes,
              insertedNotes.count == notes.count else {
            statusMessage = "Print failed: MIDI note payload was not committed to Arrangement"
            return
        }

        selectedClipID = insertedClip.id
        project.stepSequencer?.enabled = false
        activeSequencerStep = nil
        activePrimaryWorkspace = .arrangement
        playheadBeat = start
        statusMessage = "Printed one Step Sequencer MIDI clip with \(insertedNotes.count) note(s) at beat \(String(format: "%.2f", start)); live pattern disabled"
    }

    func syncSequencer(at beat: Double) {
        guard activePrimaryWorkspace == .stepSequencer,
              let seq = project.stepSequencer,
              seq.enabled,
              seq.stepCount > 0,
              seq.stepsPerBeat > 0 else {
            activeSequencerStep = nil
            return
        }
        let rawStep = Int(floor(beat * Double(seq.stepsPerBeat)))
        let step = ((rawStep % seq.stepCount) + seq.stepCount) % seq.stepCount
        guard step != activeSequencerStep else { return }
        activeSequencerStep = step
        for layer in seq.layers where step < layer.hits.count && layer.hits[step] {
            let note = UInt8(clamping: layer.midiNote)
            let velocity = UInt8(clamping: Int(layer.volume * 110))
            if let path = layer.sourcePath, !path.isEmpty {
                audioEngine.playOneShotSample(path: path, projectURL: currentProjectURL, volume: layer.volume, pan: layer.pan)
            } else {
                if !audioUnitHost.hasActiveInstrument && desktopBridge.activeInstanceID == nil { audioEngine.triggerSequencerVoice(note: note, velocity: velocity, pan: layer.pan) }
                audioUnitHost.sendNoteOn(note: note, velocity: velocity)
                desktopBridge.sendMIDI(status: 0x90, data1: note, data2: velocity)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(90))
                    guard let self else { return }
                    self.audioUnitHost.sendNoteOff(note: note)
                    self.desktopBridge.sendMIDI(status: 0x80, data1: note, data2: 0)
                }
            }
        }
    }

    func syncExpressiveMIDI(at beat: Double) {
        for track in project.tracks where track.mute != true {
            for clip in track.clips {
                let visibleLocal = beat - clip.startBeat
                guard visibleLocal >= 0, visibleLocal <= clip.lengthBeats else { continue }
                let sourceLength = max(0.000_001, clip.loopLengthBeats ?? clip.lengthBeats)
                let local = clip.lengthBeats > sourceLength
                    ? visibleLocal.truncatingRemainder(dividingBy: sourceLength)
                    : visibleLocal
                for event in clip.midiEvents ?? [] where abs(event.beat - local) < 0.0125 {
                    switch event.kind.lowercased() {
                    case "cc":
                        let cc = UInt8(clamping: event.data1), value = UInt8(clamping: event.data2)
                        audioUnitHost.sendCC(cc, value: value)
                        desktopBridge.sendMIDI(status: 0xB0, data1: cc, data2: value)
                    case "pitchbend":
                        let value = max(0, min(16383, event.data1))
                        let lsb = UInt8(value & 0x7F), msb = UInt8((value >> 7) & 0x7F)
                        audioUnitHost.sendPitchBend(lsb: lsb, msb: msb)
                        desktopBridge.sendMIDI(status: 0xE0, data1: lsb, data2: msb)
                    default: break
                    }
                }
            }
        }
    }



    func pianoScalePitchClasses() -> Set<Int> {
        let root = ((project.keyRoot ?? 0) % 12 + 12) % 12
        let intervals: [Int]
        switch (project.scaleName ?? "Major").lowercased() {
        case "minor", "natural minor", "aeolian": intervals = [0, 2, 3, 5, 7, 8, 10]
        case "harmonic minor": intervals = [0, 2, 3, 5, 7, 8, 11]
        case "melodic minor": intervals = [0, 2, 3, 5, 7, 9, 11]
        case "dorian": intervals = [0, 2, 3, 5, 7, 9, 10]
        case "phrygian": intervals = [0, 1, 3, 5, 7, 8, 10]
        case "lydian": intervals = [0, 2, 4, 6, 7, 9, 11]
        case "mixolydian": intervals = [0, 2, 4, 5, 7, 9, 10]
        case "pentatonic", "major pentatonic": intervals = [0, 2, 4, 7, 9]
        case "minor pentatonic": intervals = [0, 3, 5, 7, 10]
        case "blues": intervals = [0, 3, 5, 6, 7, 10]
        default: intervals = [0, 2, 4, 5, 7, 9, 11]
        }
        return Set(intervals.map { ($0 + root) % 12 })
    }

    func nearestScaleNote(_ note: Int) -> Int {
        let clamped = max(0, min(127, note))
        let pcs = pianoScalePitchClasses()
        if pcs.contains(clamped % 12) { return clamped }
        for distance in 1...11 {
            let down = clamped - distance
            let up = clamped + distance
            if down >= 0, pcs.contains(down % 12) { return down }
            if up <= 127, pcs.contains(up % 12) { return up }
        }
        return clamped
    }

    func fitPianoNotesToScale(_ ids: Set<UUID>) {
        guard let loc = selectedMIDIClipLocation,
              project.tracks.indices.contains(loc.track),
              project.tracks[loc.track].clips.indices.contains(loc.clip),
              project.tracks[loc.track].clips[loc.clip].notes != nil else {
            statusMessage = "Select a MIDI clip first"
            return
        }

        var changed = 0
        for index in project.tracks[loc.track].clips[loc.clip].notes!.indices {
            let id = project.tracks[loc.track].clips[loc.clip].notes![index].id
            guard ids.isEmpty || ids.contains(id) else { continue }
            let old = project.tracks[loc.track].clips[loc.clip].notes![index].note
            let fitted = nearestScaleNote(old)
            if fitted != old {
                project.tracks[loc.track].clips[loc.clip].notes![index].note = fitted
                changed += 1
            }
        }
        let scope = ids.isEmpty ? "all notes" : "selected notes"
        statusMessage = "Fit \(scope) to \(project.keyName ?? "C") \(project.scaleName ?? "Major"): \(changed) moved"
    }

    func addPianoNote(note: Int, beat: Double, length: Double = 0.5, velocity: Int = 100) {
        guard let loc = selectedMIDIClipLocation else { statusMessage = "Select a MIDI clip first"; return }
        var n = VisionNote(note: max(0, min(127, note)), startBeat: max(0, snapped(beat)), lengthBeats: max(0.05, length), velocity: max(1, min(127, velocity)))
        n.id = UUID()
        if project.tracks[loc.track].clips[loc.clip].notes == nil { project.tracks[loc.track].clips[loc.clip].notes = [] }
        project.tracks[loc.track].clips[loc.clip].notes!.append(n)
        previewNote(UInt8(clamping: note))
    }

    func updatePianoNote(_ id: UUID, note: Int? = nil, beat: Double? = nil, length: Double? = nil, velocity: Int? = nil) {
        guard let loc = selectedMIDIClipLocation,
              let ni = project.tracks[loc.track].clips[loc.clip].notes?.firstIndex(where: { $0.id == id }) else { return }
        if let note { project.tracks[loc.track].clips[loc.clip].notes![ni].note = max(0, min(127, note)) }
        if let beat { project.tracks[loc.track].clips[loc.clip].notes![ni].startBeat = max(0, snapped(beat)) }
        if let length { project.tracks[loc.track].clips[loc.clip].notes![ni].lengthBeats = max(0.05, length) }
        if let velocity { project.tracks[loc.track].clips[loc.clip].notes![ni].velocity = max(1, min(127, velocity)) }
    }

    func deletePianoNotes(_ ids: Set<UUID>) {
        guard let loc = selectedMIDIClipLocation else { return }
        project.tracks[loc.track].clips[loc.clip].notes?.removeAll { ids.contains($0.id) }
    }

    func transposePianoNotes(_ ids: Set<UUID>, semitones: Int) {
        guard let loc = selectedMIDIClipLocation else { return }
        for i in project.tracks[loc.track].clips[loc.clip].notes?.indices ?? (0..<0) {
            guard ids.isEmpty || ids.contains(project.tracks[loc.track].clips[loc.clip].notes![i].id) else { continue }
            project.tracks[loc.track].clips[loc.clip].notes![i].note = max(0, min(127, project.tracks[loc.track].clips[loc.clip].notes![i].note + semitones))
        }
    }

    func quantizePianoNotes(_ ids: Set<UUID>) {
        guard let loc = selectedMIDIClipLocation else { return }
        for i in project.tracks[loc.track].clips[loc.clip].notes?.indices ?? (0..<0) {
            guard ids.isEmpty || ids.contains(project.tracks[loc.track].clips[loc.clip].notes![i].id) else { continue }
            project.tracks[loc.track].clips[loc.clip].notes![i].startBeat = snapped(project.tracks[loc.track].clips[loc.clip].notes![i].startBeat)
        }
    }

    func humanizePianoNotes(_ ids: Set<UUID>, timing: Double = 0.03, velocity: Int = 5) {
        guard let loc = selectedMIDIClipLocation else { return }
        for i in project.tracks[loc.track].clips[loc.clip].notes?.indices ?? (0..<0) {
            guard ids.isEmpty || ids.contains(project.tracks[loc.track].clips[loc.clip].notes![i].id) else { continue }
            let t = Double.random(in: -timing...timing)
            let v = Int.random(in: -velocity...velocity)
            project.tracks[loc.track].clips[loc.clip].notes![i].startBeat = max(0, project.tracks[loc.track].clips[loc.clip].notes![i].startBeat + t)
            project.tracks[loc.track].clips[loc.clip].notes![i].velocity = max(1, min(127, project.tracks[loc.track].clips[loc.clip].notes![i].velocity + v))
        }
    }

    func setExpressiveEvent(lane: PianoLane, beat: Double, normalized: Double) {
        guard let loc = selectedMIDIClipLocation else { return }
        if project.tracks[loc.track].clips[loc.clip].midiEvents == nil { project.tracks[loc.track].clips[loc.clip].midiEvents = [] }
        let b = max(0, snapped(beat))
        switch lane {
        case .velocity:
            return
        case .modWheel:
            project.tracks[loc.track].clips[loc.clip].midiEvents!.append(.init(beat: b, kind: "cc", data1: 1, data2: Int(max(0, min(1, normalized)) * 127)))
        case .pitchBend:
            project.tracks[loc.track].clips[loc.clip].midiEvents!.append(.init(beat: b, kind: "pitchBend", data1: Int(max(0, min(1, normalized)) * 16383), data2: 0))
        case .sustain:
            project.tracks[loc.track].clips[loc.clip].midiEvents!.append(.init(beat: b, kind: "cc", data1: 64, data2: normalized >= 0.5 ? 127 : 0))
        }
    }
}
