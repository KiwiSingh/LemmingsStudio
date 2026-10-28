import SwiftUI
import Observation
#if canImport(AppKit)
import AppKit
#endif

@Observable final class PianoRollState {
    static let shared = PianoRollState()
    var clipID: UUID? {
        didSet {
            if clipID != oldValue { selectedNoteIDs.removeAll() }
        }
    }
    var selectedNoteIDs: Set<UUID> = []
}

private struct PianoRollNotePill: View {
    let noteID: UUID
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let fillColor: Color
    let isSelected: Bool
    let select: () -> Void
    let delete: () -> Void

    var body: some View {
        let strokeColor: Color = isSelected ? Color.white.opacity(0.9) : Color.black.opacity(0.25)
        let strokeWidth: CGFloat = isSelected ? 1.5 : 0.5

        return RoundedRectangle(cornerRadius: 3)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .frame(width: width, height: height)
            .offset(x: x, y: y)
            .contentShape(Rectangle())
            .onTapGesture(perform: select)
            .contextMenu {
                Button("Select Note", action: select)
                Button("Delete Note", action: delete)
            }
    }
}

struct PianoRollView: View {
    @Environment(AppState.self) private var app
    @State private var pxPerBeat: CGFloat = 48
    @State private var marqueeStart: CGPoint? = nil
    @State private var marqueeCurrent: CGPoint? = nil
    @State private var marqueeDidMove: Bool = false
    private let rowHeight: CGFloat = 14
    private let lowPitch = 36
    private let highPitch = 84

    private var currentEventModifiers: EventModifiers {
        #if canImport(AppKit)
        let flags = NSEvent.modifierFlags
        var modifiers: EventModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
        #else
        return []
        #endif
    }

    private var clip: Clip? {
        let id = PianoRollState.shared.clipID
        return app.project.tracks.flatMap { $0.clips }.first { $0.id == id }
            ?? app.selectedTrack?.clips.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Piano Roll").font(.headline)
                if let c = clip { Text(c.name).foregroundStyle(.secondary).font(.caption) }
                Spacer()
                if let c = clip {
                    Button("Select All") { selectAllNotes(in: c) }.controlSize(.small)
                        .disabled(c.notes.isEmpty)
                    Button("Delete Selected") { deleteSelectedNotes(in: c) }.controlSize(.small)
                        .disabled(PianoRollState.shared.selectedNoteIDs.isEmpty)
                    Button("− Oct") { transposeSelectedNotes(in: c, semitones: -12) }
                        .controlSize(.small)
                        .keyboardShortcut(.downArrow, modifiers: [.shift])
                        .disabled(PianoRollState.shared.selectedNoteIDs.isEmpty)
                    Button("+ Oct") { transposeSelectedNotes(in: c, semitones: 12) }
                        .controlSize(.small)
                        .keyboardShortcut(.upArrow, modifiers: [.shift])
                        .disabled(PianoRollState.shared.selectedNoteIDs.isEmpty)
                    Button(PianoRollState.shared.selectedNoteIDs.isEmpty ? "Fit Clip to Scale" : "Fit Selected to Scale") { fitNotesToScale(in: c) }.controlSize(.small)
                    Menu("Generative Disco") {
                        Button("Generate New Pattern") {
                            app.selectedClipID = c.id
                            app.generativeDisco(on: c)
                        }
                        Button("New Random Seed") {
                            app.randomizeGenerativeDiscoSeed()
                            app.selectedClipID = c.id
                            app.generativeDisco(on: c)
                        }
                        Toggle(
                    "Lock Seed",
                    isOn: Binding(
                        get: { app.generativeDiscoSeedLocked },
                        set: { app.generativeDiscoSeedLocked = $0 }
                    )
                )
                        Divider()
                        Menu("Variation") {
                            Button("Tight · 25%") { app.generativeDiscoVariation = 0.25 }
                            Button("Balanced · 60%") { app.generativeDiscoVariation = 0.60 }
                            Button("Loose · 80%") { app.generativeDiscoVariation = 0.80 }
                            Button("Wild · 100%") { app.generativeDiscoVariation = 1.00 }
                        }
                        Menu("Chaos") {
                            Button("Low · 10%") { app.generativeDiscoChaos = 0.10 }
                            Button("Medium · 30%") { app.generativeDiscoChaos = 0.30 }
                            Button("High · 60%") { app.generativeDiscoChaos = 0.60 }
                            Button("Maximum · 100%") { app.generativeDiscoChaos = 1.00 }
                        }
                        Divider()
                        Button("Regenerate Bass Only") {
                            app.selectedClipID = c.id
                            app.generativeDisco(on: c, regenerating: [.bass])
                        }
                        Button("Regenerate Harmony Only") {
                            app.selectedClipID = c.id
                            app.generativeDisco(on: c, regenerating: [.harmony])
                        }
                        Button("Regenerate Accents Only") {
                            app.selectedClipID = c.id
                            app.generativeDisco(on: c, regenerating: [.accents])
                        }
                    }
                    .controlSize(.small)
                }
                Text(app.project.keySnapEnabled ? "Snap: \(app.project.key.displayName)" : "Snap off")
                    .font(.caption).foregroundStyle(app.project.keySnapEnabled ? Color.green : Color.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            if let clip = clip {
                VStack(spacing: 0) {
                    ScrollView([.vertical, .horizontal]) {
                        HStack(spacing: 0) {
                            keyboard
                            editor(clip)
                        }
                    }
                    Divider()
                    pitchBendLane(clip)
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "pianokeys").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("No MIDI clip selected").font(.headline)
                    Text("Drag across an empty MIDI lane in Arrangement to create a clip, or create one on the selected instrument track now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button {
                        _ = app.createMidiClip(on: app.selectedTrack, startBeat: app.engine.currentBeat, lengthBeats: Double(app.project.beatsPerBar), openPianoRoll: false)
                    } label: {
                        Label("Create MIDI Clip on Selected Track", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .disabled(app.selectedTrack == nil || app.selectedTrack?.kind == .audio)
                }
                Spacer()
            }
        }
        .background(PianoRollKeyCapture { command in
            guard let clip=clip else {return false}
            switch command {
            case .selectAll:selectAllNotes(in:clip)
            case .transpose(let delta):transposeSelectedNotes(in:clip,semitones:delta)
            }
            return true
        })
    }

    private var pitches: [Int] { Array(lowPitch...highPitch).reversed() }

    private var keyboard: some View {
        VStack(spacing: 0) {
            ForEach(pitches, id: \.self) { pitch in
                let inKey = app.project.key.contains(MIDINote(pitch))
                let isC = pitch % 12 == 0
                Text(isC ? MIDINote(pitch).name : "")
                    .font(.system(size: 8)).frame(width: 42, height: rowHeight, alignment: .trailing)
                    .padding(.trailing, 3)
                    .background(inKey ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.05))
                    .border(Color.secondary.opacity(0.1), width: 0.5)
            }
        }
    }

    private func editor(_ clip: Clip) -> some View {
        let beats = Int(clip.lengthBeats.rounded(.up))
        let width = CGFloat(beats) * pxPerBeat
        let height = CGFloat(pitches.count) * rowHeight
        return ZStack(alignment: .topLeading) {
            // Row backgrounds keyed to scale (Ableton fold-to-scale look)
            Canvas { ctx, size in
                for (row, pitch) in pitches.enumerated() {
                    let inKey = app.project.key.contains(MIDINote(pitch))
                    let y = CGFloat(row) * rowHeight
                    let color: Color = inKey ? .accentColor.opacity(0.07) : .secondary.opacity(0.03)
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: rowHeight)), with: .color(color))
                }
                // beat lines
                for b in 0...beats {
                    let x = CGFloat(b) * pxPerBeat
                    var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
                    for sub in 1..<4 {
                        let sx = x + CGFloat(sub) * pxPerBeat/4
                        var sp = Path(); sp.move(to: CGPoint(x: sx, y: 0)); sp.addLine(to: CGPoint(x: sx, y: size.height))
                        ctx.stroke(sp, with: .color(.secondary.opacity(0.07)), lineWidth: 0.5)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        app.focusPianoRollUndoContext()
                        let dx = value.location.x - value.startLocation.x
                        let dy = value.location.y - value.startLocation.y
                        let distance = hypot(dx, dy)

                        if marqueeStart == nil {
                            marqueeStart = value.startLocation
                            marqueeCurrent = value.location
                            marqueeDidMove = false
                        } else {
                            marqueeCurrent = value.location
                        }

                        // Desktop-style marquee selection: press on empty grid space,
                        // drag a rectangle across notes, then release to select whatever
                        // intersects it. Tiny mouse tremors still count as a click-to-add.
                        if distance >= 3 {
                            marqueeDidMove = true
                        }
                    }
                    .onEnded { value in
                        marqueeCurrent = value.location
                        if marqueeDidMove {
                            applyMarqueeSelection(in: clip, additive: currentEventModifiers.contains(.shift) || currentEventModifiers.contains(.command))
                        } else {
                            addNote(in: clip, at: value.location)
                        }
                        marqueeStart = nil
                        marqueeCurrent = nil
                        marqueeDidMove = false
                    }
            )
            // existing notes
            ForEach(clip.notes) { note in
                let row = highPitch - note.pitch
                let selectedIDs = PianoRollState.shared.selectedNoteIDs
                let isSelected = selectedIDs.contains(note.id)
                let noteFill: Color = isSelected ? Color.accentColor : (app.selectedTrack?.color ?? Color.blue)
                let noteX = CGFloat(note.start) * pxPerBeat
                let noteY = CGFloat(row) * rowHeight
                let noteWidth = max(CGFloat(4), CGFloat(note.length) * pxPerBeat - CGFloat(1))
                let noteHeight = rowHeight - CGFloat(1)
                let additive = currentEventModifiers.contains(.shift) || currentEventModifiers.contains(.command)

                PianoRollNotePill(
                    noteID: note.id,
                    x: noteX,
                    y: noteY,
                    width: noteWidth,
                    height: noteHeight,
                    fillColor: noteFill,
                    isSelected: isSelected,
                    select: { selectNote(note.id, additive: additive) },
                    delete: { deleteNotes([note.id], in: clip) }
                )
            }

            if let rect = marqueeRect {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(Rectangle().stroke(Color.accentColor.opacity(0.8), lineWidth: 1))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onAppear { app.focusPianoRollUndoContext() }
    }

    private var marqueeRect: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        return CGRect(x: minX, y: minY, width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    private func addNote(in clip: Clip, at location: CGPoint) {
        app.focusPianoRollUndoContext()
        let row = Int(location.y / rowHeight)
        guard row >= 0 && row < pitches.count else { return }
        let rawPitch = highPitch - row
        let pitch = app.project.snap(rawPitch)   // whole-song key-snap
        let rawBeat = Double(location.x / pxPerBeat)
        let snappedBeat = max(0, (rawBeat * 4).rounded(.down) / 4)   // 16th-note grid
        let before = clip.notes
        var after = clip.notes
        let created = ClipNote(pitch: pitch, start: snappedBeat, length: 0.25, velocity: 0.9)
        after.append(created)
        app.replaceMIDINotes(forClipID: clip.id, with: after, undoName: "Add Piano Roll Note", context: .pianoRoll)
        PianoRollState.shared.selectedNoteIDs = [created.id]
        _ = before // keeps the intent obvious; undo snapshot is captured by replaceMIDINotes.
        // audition
        if let track = app.selectedTrack {
            app.engine.audition(track: track, note: pitch, on: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                app.engine.audition(track: track, note: pitch, on: false)
            }
        }
    }

    private func selectNote(_ id: UUID, additive: Bool) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        app.focusPianoRollUndoContext()
        if additive {
            if PianoRollState.shared.selectedNoteIDs.contains(id) {
                PianoRollState.shared.selectedNoteIDs.remove(id)
            } else {
                PianoRollState.shared.selectedNoteIDs.insert(id)
            }
        } else {
            PianoRollState.shared.selectedNoteIDs = [id]
        }
    }

    private func selectAllNotes(in clip: Clip) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        app.focusPianoRollUndoContext()
        PianoRollState.shared.clipID = clip.id
        PianoRollState.shared.selectedNoteIDs = Set(clip.notes.map(\.id))
    }

    private func deleteSelectedNotes(in clip: Clip) {
        deleteNotes(PianoRollState.shared.selectedNoteIDs, in: clip)
    }

    private func deleteNotes<S: Sequence>(_ ids: S, in clip: Clip) where S.Element == UUID {
        app.focusPianoRollUndoContext()
        let doomed = Set(ids)
        guard !doomed.isEmpty else { return }
        let after = clip.notes.filter { !doomed.contains($0.id) }
        guard after.count != clip.notes.count else { return }
        app.replaceMIDINotes(forClipID: clip.id, with: after, undoName: doomed.count == 1 ? "Delete Piano Roll Note" : "Delete Piano Roll Notes", context: .pianoRoll)
        PianoRollState.shared.selectedNoteIDs.subtract(doomed)
    }

    private func transposeSelectedNotes(in clip: Clip, semitones: Int) {
        app.focusPianoRollUndoContext()
        let selected = PianoRollState.shared.selectedNoteIDs
        guard !selected.isEmpty else { return }
        let selectedNotes = clip.notes.filter { selected.contains($0.id) }
        guard !selectedNotes.isEmpty else { return }
        let lowest = selectedNotes.map(\.pitch).min() ?? 0
        let highest = selectedNotes.map(\.pitch).max() ?? 127
        let safeDelta = max(-lowest, min(127 - highest, semitones))
        guard safeDelta != 0 else { return }
        let after = clip.notes.map { note -> ClipNote in
            guard selected.contains(note.id) else { return note }
            var copy = note
            copy.pitch += safeDelta
            return copy
        }
        app.replaceMIDINotes(
            forClipID: clip.id,
            with: after,
            undoName: safeDelta > 0 ? "Transpose Notes Up an Octave" : "Transpose Notes Down an Octave",
            context: .pianoRoll
        )
    }

    private func pitchBendLane(_ clip: Clip) -> some View {
        let track = app.project.tracks.first { track in
            track.clips.contains { $0.id == clip.id }
        }
        let channel = 0
        let paramID = AutomationSpecialParam.midiPitchBend(channel: channel)
        let lane = track?.automationLanes.first {
            $0.nodeID == "instrument" && $0.paramID == paramID
        }
        let points = lane?.points ?? []
        let width = max(CGFloat(clip.lengthBeats) * pxPerBeat, 240)
        let laneHeight: CGFloat = 76

        return HStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("+")
                Spacer()
                Text("Pitch Bend").font(.caption2)
                Spacer()
                Text("−")
            }
            .foregroundStyle(.secondary)
            .frame(width: 45, height: laneHeight)
            .padding(.trailing, 3)

            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        let centerY = size.height / 2
                        var center = Path()
                        center.move(to: CGPoint(x: 0, y: centerY))
                        center.addLine(to: CGPoint(x: size.width, y: centerY))
                        context.stroke(center, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                        for beat in 0...Int(clip.lengthBeats.rounded(.up)) {
                            let x = CGFloat(beat) * pxPerBeat
                            var line = Path()
                            line.move(to: CGPoint(x: x, y: 0))
                            line.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(line, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
                        }
                        guard !points.isEmpty else { return }
                        var curve = Path()
                        for (index, point) in points.enumerated() {
                            let localBeat = point.beat - clip.startBeat
                            let x = CGFloat(max(0, min(clip.lengthBeats, localBeat))) * pxPerBeat
                            let y = (1 - CGFloat((point.value + 1) / 2)) * size.height
                            if index == 0 { curve.move(to: CGPoint(x: x, y: y)) }
                            else { curve.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        context.stroke(curve, with: .color(.accentColor), lineWidth: 2)
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        let localBeat = point.beat - clip.startBeat
                        let x = CGFloat(max(0, min(clip.lengthBeats, localBeat))) * pxPerBeat
                        let y = (1 - CGFloat((point.value + 1) / 2)) * laneHeight
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                            .offset(x: x - 3.5, y: y - 3.5)
                    }
                }
                .frame(width: width, height: laneHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        guard let track else { return }
                        let localBeat = max(0, min(clip.lengthBeats, Double(value.location.x / pxPerBeat)))
                        let bend = max(-1, min(1, 1 - (Double(value.location.y / laneHeight) * 2)))
                        let target = pitchBendLaneForEditing(track: track, channel: channel)
                        replacePitchBendPoint(in: target, beat: clip.startBeat + localBeat, value: bend)
                    }
                )
                .contextMenu {
                    Button("Clear Pitch Bend Automation", role: .destructive) {
                        lane?.points.removeAll()
                    }
                }
            }
        }
        .frame(height: laneHeight)
        .help("Drag to draw channel-1 pitch bend. Incoming 14-bit bend is recorded while Record or MIDI Overdub is active.")
    }

    private func pitchBendLaneForEditing(track: Track, channel: Int) -> AutomationLane {
        let paramID = AutomationSpecialParam.midiPitchBend(channel: channel)
        if let lane = track.automationLanes.first(where: {
            $0.nodeID == "instrument" && $0.paramID == paramID
        }) { return lane }
        let lane = AutomationLane(nodeID: "instrument", paramID: paramID)
        track.automationLanes.append(lane)
        return lane
    }

    private func replacePitchBendPoint(in lane: AutomationLane, beat: Double, value: Double) {
        let quantizedBeat = (beat * 64).rounded() / 64
        if let index = lane.points.indices.min(by: {
            abs(lane.points[$0].beat - quantizedBeat) < abs(lane.points[$1].beat - quantizedBeat)
        }), abs(lane.points[index].beat - quantizedBeat) <= (1.0 / 32.0) {
            lane.points[index] = AutomationPoint(beat: quantizedBeat, value: value)
        } else {
            lane.points.append(AutomationPoint(beat: quantizedBeat, value: value))
        }
        lane.points.sort { $0.beat < $1.beat }
    }

    private func fitNotesToScale(in clip: Clip) {
        app.focusPianoRollUndoContext()
        let selected = PianoRollState.shared.selectedNoteIDs
        let after = clip.notes.map { note -> ClipNote in
            guard selected.isEmpty || selected.contains(note.id) else { return note }
            var copy = note
            copy.pitch = app.project.snap(note.pitch)
            return copy
        }
        app.replaceMIDINotes(forClipID: clip.id, with: after, undoName: selected.isEmpty ? "Fit Clip to Scale" : "Fit Selected Notes to Scale", context: .pianoRoll)
    }

    private func applyMarqueeSelection(in clip: Clip, additive: Bool) {
        guard let rect = marqueeRect, rect.width > 2, rect.height > 2 else { return }
        var hits: Set<UUID> = []
        for note in clip.notes {
            let row = highPitch - note.pitch
            let noteRect = CGRect(
                x: CGFloat(note.start) * pxPerBeat,
                y: CGFloat(row) * rowHeight,
                width: max(4, CGFloat(note.length) * pxPerBeat - 1),
                height: rowHeight - 1
            )
            if rect.intersects(noteRect) { hits.insert(note.id) }
        }
        if additive { PianoRollState.shared.selectedNoteIDs.formUnion(hits) }
        else { PianoRollState.shared.selectedNoteIDs = hits }
    }
}
