import SwiftUI

struct VisionPianoRollView: View {
    @Environment(VisionStudioModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var selectedNotes = Set<UUID>()
    @State private var lane: VisionStudioModel.PianoLane = .velocity
    @State private var beatsVisible: Double = 8
    @State private var lowNote = 36
    @State private var highNote = 84
    @State private var fitToScale = false

    private var clip: VisionMIDIClip? {
        guard let loc = model.selectedMIDIClipLocation else { return nil }
        return model.project.tracks[loc.track].clips[loc.clip]
    }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if let clip {
                GeometryReader { geo in
                    let laneHeight: CGFloat = 150
                    VStack(spacing: 8) {
                        pianoGrid(clip: clip, size: CGSize(width: geo.size.width, height: max(300, geo.size.height - laneHeight - 8)))
                        expressiveLane(clip: clip).frame(height: laneHeight)
                    }
                }
            } else {
                ContentUnavailableView("Select a MIDI clip", systemImage: "pianokeys", description: Text("Choose a MIDI clip in Arrangement View, then edit it here."))
            }
        }
        .padding(18)
        .onAppear { frameSelectedClip() }
        .onChange(of: model.selectedClipID) { _, _ in frameSelectedClip() }
        .background(VisionThemeBackground(theme: model.visualTheme))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack { Text("Piano Roll"); VisionWorkspaceQuickSwitcher() }.font(.title2.bold())
            Button("Quantize", systemImage: "grid") { model.quantizePianoNotes(selectedNotes) }
            Button("Humanize", systemImage: "wand.and.stars") { model.humanizePianoNotes(selectedNotes) }
            Toggle("Fit to Scale", isOn: $fitToScale)
                .toggleStyle(.button)
                .help("Constrain new and dragged notes to the project key and scale")
            Button("Fit Existing Notes", systemImage: "music.note.list") {
                model.fitPianoNotesToScale(selectedNotes)
            }
            Menu("Transpose") {
                Button("+1 semitone") { model.transposePianoNotes(selectedNotes, semitones: 1) }
                Button("-1 semitone") { model.transposePianoNotes(selectedNotes, semitones: -1) }
                Button("+12 semitones") { model.transposePianoNotes(selectedNotes, semitones: 12) }
                Button("-12 semitones") { model.transposePianoNotes(selectedNotes, semitones: -12) }
            }
            Picker("Lane", selection: $lane) {
                ForEach(VisionStudioModel.PianoLane.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)
            Spacer()
            Button("Frame Notes", systemImage: "arrow.up.left.and.arrow.down.right") {
                frameSelectedClip()
            }
            Button("Spatial Keyboard", systemImage: "pianokeys") {
                openWindow(id: "floating-midi-keyboard")
            }
            Text("\(model.project.keyName ?? "C") \(model.project.scaleName ?? "Major")").foregroundStyle(.secondary)
            Button("Delete", systemImage: "trash", role: .destructive) { model.deletePianoNotes(selectedNotes); selectedNotes.removeAll() }
                .disabled(selectedNotes.isEmpty)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func pianoGrid(clip: VisionMIDIClip, size: CGSize) -> some View {
        let range = max(1, highNote - lowNote + 1)
        let rowH = size.height / CGFloat(range)
        let beatW = size.width / beatsVisible
        return ZStack(alignment: .topLeading) {
            Canvas { context, canvas in
                for note in lowNote...highNote {
                    let y = CGFloat(highNote - note) * rowH
                    let pc = note % 12
                    let inScale = scalePitchClasses().contains(pc)
                    context.fill(Path(CGRect(x: 0, y: y, width: canvas.width, height: rowH)), with: .color(inScale ? .white.opacity(0.045) : .black.opacity(0.08)))
                }
                for i in 0...Int(ceil(beatsVisible * 4)) {
                    let beat = Double(i) / 4
                    let x = beat * beatW
                    var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: canvas.height))
                    context.stroke(p, with: .color(.white.opacity(i % 4 == 0 ? 0.22 : 0.08)), lineWidth: i % 4 == 0 ? 1.2 : 0.5)
                }
            }
            ForEach(Array(stride(from: lowNote, through: highNote, by: 1)).filter { $0 % 12 == 0 }, id: \.self) { pitch in
                Text(midiPitchName(pitch))
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .background(.thinMaterial, in: Capsule())
                    .offset(x: 6, y: CGFloat(highNote - pitch) * rowH + 2)
                    .allowsHitTesting(false)
            }
            ForEach(ghostNotes(excluding: clip.id)) { note in
                noteRect(note: note, rowH: rowH, beatW: beatW)
                    .fill(.white.opacity(0.10))
            }
            ForEach(clip.notes ?? []) { note in
                noteRect(note: note, rowH: rowH, beatW: beatW)
                    .fill(selectedNotes.contains(note.id) ? VisionThemeCatalog.palette(for: model.visualTheme).accent : VisionThemeCatalog.palette(for: model.visualTheme).accent.opacity(0.72))
                    .overlay(noteRect(note: note, rowH: rowH, beatW: beatW).stroke(.white.opacity(selectedNotes.contains(note.id) ? 0.9 : 0.28), lineWidth: selectedNotes.contains(note.id) ? 2 : 1))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedNotes.contains(note.id) { selectedNotes.remove(note.id) } else { selectedNotes.insert(note.id); model.previewNote(UInt8(clamping: note.note)) }
                    }
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            selectedNotes.insert(note.id)
                            let beat = note.startBeat + Double(value.translation.width / beatW)
                            let rawPitch = note.note - Int((value.translation.height / rowH).rounded())
                            let pitch = fitToScale ? model.nearestScaleNote(rawPitch) : rawPitch
                            model.updatePianoNote(note.id, note: pitch, beat: beat)
                        })
            }
        }
        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
            guard abs(value.translation.width) < 4, abs(value.translation.height) < 4 else { return }
            let beat = Double(value.location.x / beatW)
            let rawNote = highNote - Int(value.location.y / rowH)
            let note = fitToScale ? model.nearestScaleNote(rawNote) : rawNote
            model.addPianoNote(note: note, beat: beat)
        })
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func noteRect(note: VisionNote, rowH: CGFloat, beatW: CGFloat) -> Path {
        let x = note.startBeat * beatW
        let y = CGFloat(highNote - note.note) * rowH + 1
        let w = max(7, note.lengthBeats * beatW)
        return Path(roundedRect: CGRect(x: x, y: y, width: w, height: max(4, rowH - 2)), cornerRadius: 4)
    }

    private func expressiveLane(clip: VisionMIDIClip) -> some View {
        GeometryReader { geo in
            let beatW = geo.size.width / beatsVisible
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.16))
                Canvas { context, size in
                    for i in 0...Int(ceil(beatsVisible * 4)) {
                        let x = Double(i) / 4 * beatW
                        var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(.white.opacity(i % 4 == 0 ? 0.18 : 0.06)), lineWidth: 1)
                    }
                }
                if lane == .velocity {
                    ForEach(clip.notes ?? []) { note in
                        Rectangle()
                            .fill(VisionThemeCatalog.palette(for: model.visualTheme).accent.opacity(0.78))
                            .frame(width: max(5, note.lengthBeats * beatW * 0.4), height: CGFloat(note.velocity) / 127 * geo.size.height)
                            .offset(x: note.startBeat * beatW)
                            .onTapGesture { model.updatePianoNote(note.id, velocity: note.velocity >= 112 ? 64 : min(127, note.velocity + 16)) }
                    }
                } else {
                    ForEach(events(for: lane, clip: clip)) { event in
                        Circle().fill(VisionThemeCatalog.palette(for: model.visualTheme).accent)
                            .frame(width: 14, height: 14)
                            .position(x: event.beat * beatW, y: (1 - normalized(event, lane: lane)) * max(1, geo.size.height - 14) + 7)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                guard lane != .velocity else { return }
                let beat = Double(value.location.x / beatW)
                let norm = max(0, min(1, 1 - Double(value.location.y / geo.size.height)))
                model.setExpressiveEvent(lane: lane, beat: beat, normalized: norm)
            })
        }
        .overlay(alignment: .topLeading) { Text(lane.rawValue).font(.caption.bold()).padding(10) }
    }

    private func events(for lane: VisionStudioModel.PianoLane, clip: VisionMIDIClip) -> [VisionMIDIEvent] {
        let events = clip.midiEvents ?? []
        switch lane {
        case .modWheel: return events.filter { $0.kind.lowercased() == "cc" && $0.data1 == 1 }
        case .pitchBend: return events.filter { $0.kind.lowercased() == "pitchbend" }
        case .sustain: return events.filter { $0.kind.lowercased() == "cc" && $0.data1 == 64 }
        case .velocity: return []
        }
    }

    private func normalized(_ event: VisionMIDIEvent, lane: VisionStudioModel.PianoLane) -> Double {
        lane == .pitchBend ? Double(event.data1) / 16383 : Double(event.data2) / 127
    }

    private func ghostNotes(excluding clipID: UUID) -> [VisionNote] {
        model.project.tracks.flatMap(\.clips).filter { $0.id != clipID }.flatMap { $0.notes ?? [] }
    }

    private func frameSelectedClip() {
        guard let clip else { return }
        let notes = clip.notes ?? []
        if let minPitch = notes.map(\.note).min(), let maxPitch = notes.map(\.note).max() {
            let paddedLow = max(0, minPitch - 5)
            let paddedHigh = min(127, maxPitch + 5)
            if paddedHigh - paddedLow < 18 {
                let center = (paddedHigh + paddedLow) / 2
                lowNote = max(0, center - 9)
                highNote = min(127, lowNote + 18)
            } else {
                lowNote = paddedLow
                highNote = paddedHigh
            }
        } else {
            lowNote = 48
            highNote = 72
        }
        let contentEnd = notes.map { $0.startBeat + $0.lengthBeats }.max() ?? clip.lengthBeats
        beatsVisible = max(4, min(32, ceil(max(clip.lengthBeats, contentEnd))))
    }

    private func midiPitchName(_ note: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[(note % 12 + 12) % 12])\((note / 12) - 1)"
    }

    private func scalePitchClasses() -> Set<Int> {
        model.pianoScalePitchClasses()
    }
}
