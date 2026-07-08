import SwiftUI

struct VisionArrangementView: View {
    @Environment(VisionStudioModel.self) private var model
    @State private var createDrag: MIDICreateDrag?

    private struct MIDICreateDrag {
        var trackIndex: Int
        var startBeat: Double
        var endBeat: Double
    }
    private let headerWidth: CGFloat = 220
    private let baseRowHeight: CGFloat = 92

    private var rowHeight: CGFloat { baseRowHeight * CGFloat(model.verticalZoom) }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 0) {
                        trackHeaders
                        timeline(width: max(CGFloat(model.project.totalBeats * model.horizontalZoom), geo.size.width - headerWidth))
                    }
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let next = model.horizontalZoom * Double(value.magnification)
                            model.horizontalZoom = min(320, max(35, next))
                        }
                )
            }
            VisionArrangementAutomationDock()
        }
    }

    private var trackHeaders: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: headerWidth, height: 38)
            ForEach(Array(model.project.tracks.enumerated()), id: \.element.id) { index, track in
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.name).font(.headline).lineLimit(1)
                    HStack {
                        Text(track.kind).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if track.mute == true { Image(systemName: "speaker.slash.fill") }
                        if track.solo == true { Text("S").bold() }
                    }
                }
                .padding(12)
                .frame(width: headerWidth, height: rowHeight, alignment: .leading)
                .background(
                    model.selectedTrackID == track.id
                        ? VisionThemeCatalog.palette(for: model.visualTheme).accent.opacity(0.14)
                        : (index.isMultiple(of: 2) ? Color.white.opacity(0.035) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    model.selectedTrackID = track.id
                    model.statusMessage = "Selected track: \(track.name)"
                }
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }

    private func timeline(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ruler(width: width)
                ForEach(Array(model.project.tracks.enumerated()), id: \.element.id) { index, track in
                    trackLane(track, index: index, width: width)
                }
            }

            Rectangle()
                .fill(.red.opacity(0.9))
                .frame(width: 2)
                .offset(x: CGFloat(model.playheadBeat * model.horizontalZoom), y: 0)
                .allowsHitTesting(false)
        }
        .frame(width: width, alignment: .leading)
    }

    private func ruler(width: CGFloat) -> some View {
        Canvas { context, size in
            let beats = Int(ceil(model.project.totalBeats))
            for beat in 0...beats {
                let x = CGFloat(Double(beat) * model.horizontalZoom)
                let isBar = beat % max(1, model.project.beatsPerBar) == 0
                var path = Path()
                path.move(to: CGPoint(x: x, y: isBar ? 8 : 22))
                path.addLine(to: CGPoint(x: x, y: 38))
                context.stroke(path, with: .color(VisionThemeCatalog.palette(for: model.visualTheme).grid.opacity(isBar ? 0.95 : 0.45)), lineWidth: 1)
                if isBar {
                    context.draw(Text("\(beat / max(1, model.project.beatsPerBar) + 1)").font(.caption2), at: CGPoint(x: x + 8, y: 10), anchor: .topLeading)
                }
            }
        }
        .frame(width: width, height: 38)
        .contentShape(Rectangle())
        .onTapGesture { location in
            model.seek(to: Double(location.x) / model.horizontalZoom)
        }
    }

    private func trackLane(_ track: VisionTrack, index: Int, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.clear)
                .contentShape(Rectangle())
                .gesture(midiCreateGesture(track: track, index: index))
                .onTapGesture {
                    model.selectedTrackID = track.id
                    model.statusMessage = "Selected track: \(track.name)"
                }
            beatGrid(width: width)

            if let drag = createDrag, drag.trackIndex == index, model.isMIDICapableTrack(track) {
                let start = min(drag.startBeat, drag.endBeat)
                let end = max(drag.startBeat, drag.endBeat)
                RoundedRectangle(cornerRadius: 10)
                    .fill(VisionThemeCatalog.palette(for: model.visualTheme).accent.opacity(0.28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(VisionThemeCatalog.palette(for: model.visualTheme).accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    }
                    .frame(width: max(12, CGFloat((end - start) * model.horizontalZoom)), height: rowHeight - 20)
                    .offset(x: CGFloat(start * model.horizontalZoom), y: 10)
                    .allowsHitTesting(false)
            }

            ForEach(track.clips) { clip in
                editableClip(
                    name: clip.name,
                    startBeat: clip.startBeat,
                    lengthBeats: clip.lengthBeats,
                    id: clip.id,
                    isAudio: false,
                    midiNotes: clip.notes ?? [],
                    loopLengthBeats: clip.loopLengthBeats
                )
            }
            ForEach(track.audioClips) { clip in
                editableClip(name: clip.name, startBeat: clip.startBeat, lengthBeats: clip.lengthBeats, id: clip.id, isAudio: true)
            }
        }
        .frame(width: width, height: rowHeight)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let sample = model.spliceSearchResults.first(where: { $0.id == id }) else { return false }
            model.selectedSpliceSampleID = id
            if model.spliceMCP.fetchOnDropEnabled {
                model.fetchSpliceSample(sample, targetTrackIndex: index, insertToArrangement: true)
            } else if sample.localFilePath != nil {
                model.importSampleCandidateToArrangement(sample, targetTrackIndex: index)
            } else {
                model.statusMessage = "Fetch on Drop is off; download the Splice sample first"
            }
            return true
        }
        .overlay(alignment: .bottom) { Divider() }
    }


    private func midiCreateGesture(track: VisionTrack, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard model.isMIDICapableTrack(track) else { return }
                let start = model.snapped(Double(value.startLocation.x) / model.horizontalZoom)
                let current = model.snapped(Double(value.location.x) / model.horizontalZoom)
                model.selectedTrackID = track.id
                createDrag = MIDICreateDrag(trackIndex: index, startBeat: start, endBeat: current)
            }
            .onEnded { value in
                defer { createDrag = nil }
                guard model.isMIDICapableTrack(track) else {
                    model.statusMessage = "MIDI clips cannot be created on Audio tracks"
                    return
                }
                let rawStart = Double(value.startLocation.x) / model.horizontalZoom
                let rawEnd = Double(value.location.x) / model.horizontalZoom
                let start = model.snapped(min(rawStart, rawEnd))
                let end = model.snapped(max(rawStart, rawEnd))
                let minimum = model.snapDivision.beats(beatsPerBar: model.project.beatsPerBar) ?? 0.25
                let length = max(minimum, end - start)
                _ = model.createMIDIClip(onTrack: index, startBeat: start, lengthBeats: length, openPianoRoll: true)
            }
    }

    private func beatGrid(width: CGFloat) -> some View {
        Canvas { context, size in
            let beats = Int(ceil(model.project.totalBeats))
            for beat in 0...beats {
                let x = CGFloat(Double(beat) * model.horizontalZoom)
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(p, with: .color(VisionThemeCatalog.palette(for: model.visualTheme).grid.opacity(beat % max(1, model.project.beatsPerBar) == 0 ? 0.85 : 0.35)), lineWidth: 1)
            }
        }
        .frame(width: width, height: rowHeight)
    }

    private func editableClip(
        name: String,
        startBeat: Double,
        lengthBeats: Double,
        id: UUID,
        isAudio: Bool,
        midiNotes: [VisionNote] = [],
        loopLengthBeats: Double? = nil
    ) -> some View {
        let clipWidth = max(28, CGFloat(lengthBeats * model.horizontalZoom))
        let selected = model.selectedClipID == id

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isAudio ? VisionThemeCatalog.palette(for: model.visualTheme).secondaryAccent.opacity(0.62) : VisionThemeCatalog.palette(for: model.visualTheme).accent.opacity(0.62))

            if !isAudio && !midiNotes.isEmpty {
                midiNotePreview(
                    notes: midiNotes,
                    sourceLength: max(0.000_001, loopLengthBeats ?? lengthBeats),
                    visibleLength: lengthBeats
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 20)
                .allowsHitTesting(false)
            }

            HStack(spacing: 6) {
                Image(systemName: isAudio ? "waveform" : "pianokeys")
                Text(name).lineLimit(1)
                Spacer(minLength: 0)
                if !isAudio {
                    Button {
                        model.selectedClipID = id
                        if model.isRecordingMIDI { model.stopMIDIRecording() }
                        else { model.startMIDIRecording() }
                    } label: {
                        Image(systemName: model.isRecordingMIDI && model.selectedClipID == id ? "stop.circle.fill" : "record.circle")
                            .foregroundStyle(model.isRecordingMIDI && model.selectedClipID == id ? .red : .primary)
                    }
                    .buttonStyle(.plain)
                    .help(model.isRecordingMIDI && model.selectedClipID == id ? "Stop MIDI recording" : "Record into this MIDI clip")
                }
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)

            if selected {
                HStack {
                    trimHandle(edge: .left, id: id, startBeat: startBeat, lengthBeats: lengthBeats)
                    Spacer()
                    trimHandle(edge: .right, id: id, startBeat: startBeat, lengthBeats: lengthBeats)
                }
            }
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 12).stroke(VisionThemeCatalog.palette(for: model.visualTheme).accent, lineWidth: 3)
            }
        }
        .frame(width: clipWidth, height: rowHeight - 16)
        .offset(x: CGFloat(startBeat * model.horizontalZoom), y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { model.selectedClipID = id }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    model.selectedClipID = id
                    let beatDelta = Double(value.translation.width) / model.horizontalZoom
                    model.moveClip(id: id, proposedStartBeat: startBeat + beatDelta)
                }
        )
        .contextMenu {
            Button("Split at Playhead", systemImage: "scissors") {
                model.selectedClipID = id
                model.splitSelectedClip()
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                model.selectedClipID = id
                model.duplicateSelectedClip()
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.selectedClipID = id
                model.deleteSelectedClip()
            }
        }
        .hoverEffect(.lift)
    }

    private func midiNotePreview(notes: [VisionNote], sourceLength: Double, visibleLength: Double) -> some View {
        Canvas { context, size in
            guard !notes.isEmpty, sourceLength > 0, visibleLength > 0 else { return }

            let minPitch = notes.map(\.note).min() ?? 0
            let maxPitch = notes.map(\.note).max() ?? minPitch
            let pitchSpan = max(1, maxPitch - minPitch + 1)
            let cycleCount = max(1, Int(ceil(visibleLength / sourceLength)))
            let rowHeight = max(2.0, size.height / CGFloat(pitchSpan))

            for cycle in 0..<cycleCount {
                let cycleOffset = Double(cycle) * sourceLength
                for note in notes {
                    let visibleStart = cycleOffset + note.startBeat
                    guard visibleStart < visibleLength else { continue }
                    let clippedLength = min(note.lengthBeats, visibleLength - visibleStart)
                    guard clippedLength > 0 else { continue }

                    let x = CGFloat(visibleStart / visibleLength) * size.width
                    let width = max(2, CGFloat(clippedLength / visibleLength) * size.width)
                    let pitchIndex = note.note - minPitch
                    let y = size.height - CGFloat(pitchIndex + 1) * rowHeight
                    let rect = CGRect(x: x, y: max(0, y), width: width, height: max(2, rowHeight - 1))
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: min(2, rowHeight / 2)),
                        with: .color(.white.opacity(0.78))
                    )
                }

                if cycle > 0 {
                    let boundaryX = CGFloat(cycleOffset / visibleLength) * size.width
                    var boundary = Path()
                    boundary.move(to: CGPoint(x: boundaryX, y: 0))
                    boundary.addLine(to: CGPoint(x: boundaryX, y: size.height))
                    context.stroke(boundary, with: .color(.white.opacity(0.22)), lineWidth: 1)
                }
            }
        }
        .clipped()
    }

    private enum TrimEdge { case left, right }

    private func trimHandle(edge: TrimEdge, id: UUID, startBeat: Double, lengthBeats: Double) -> some View {
        Capsule()
            .fill(.white.opacity(0.95))
            .frame(width: 10, height: max(24, rowHeight - 34))
            .padding(.horizontal, 4)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let beatDelta = Double(value.translation.width) / model.horizontalZoom
                        switch edge {
                        case .left:
                            model.trimClipLeft(id: id, proposedStartBeat: startBeat + beatDelta)
                        case .right:
                            model.trimClipRight(id: id, proposedEndBeat: startBeat + lengthBeats + beatDelta)
                        }
                    }
            )
            .hoverEffect(.highlight)
    }
}
