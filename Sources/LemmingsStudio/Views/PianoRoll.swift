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
                    Button(PianoRollState.shared.selectedNoteIDs.isEmpty ? "Fit Clip to Scale" : "Fit Selected to Scale") { fitNotesToScale(in: c) }.controlSize(.small)
                    Button("Generative Disco") { app.selectedClipID = c.id; app.generativeDisco(on: c) }.controlSize(.small)
                }
                Text(app.project.keySnapEnabled ? "Snap: \(app.project.key.displayName)" : "Snap off")
                    .font(.caption).foregroundStyle(app.project.keySnapEnabled ? Color.green : Color.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            if let clip = clip {
                ScrollView([.vertical, .horizontal]) {
                    HStack(spacing: 0) {
                        keyboard
                        editor(clip)
                    }
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
