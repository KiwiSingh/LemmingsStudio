import SwiftUI

struct VisionFloatingMIDIKeyboardView: View {
    @Environment(VisionStudioModel.self) private var model

    private let whiteKeyWidth: CGFloat = 84
    private let whiteKeyHeight: CGFloat = 268
    private let keyGap: CGFloat = 2

    @State private var activeSpatialTouches: [AnyHashable: UInt8] = [:]

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 14) {
            controls

            ScrollView(.horizontal) {
                keybed
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .scrollIndicators(.visible)
            .frame(height: whiteKeyHeight + 54)
            .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            HStack {
                Label(routeSummary, systemImage: "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(model.virtualKeyboard.lastEventSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
        }
        .padding(18)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.black.opacity(0.99))
                    .offset(y: 22)
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(white: 0.085))
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.62), lineWidth: 2)
                    }
            }
        }
        .shadow(radius: 26, y: 18)
        .onDisappear {
            releaseAllSpatialTouches()
            model.allVirtualMIDINotesOff()
        }
    }

    private var controls: some View {
        @Bindable var model = model

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Label("Spatial MIDI Keyboard", systemImage: "pianokeys")
                    .font(.headline)
                Picker("Stock Instrument", selection: $model.selectedInstrument) {
                    ForEach(VisionAudioEngine.InstrumentKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: model.selectedInstrument) { _, newValue in
                    model.selectInstrument(newValue)
                }

                Spacer()

                Button(model.isRecordingMIDI ? "Stop MIDI" : "Record MIDI", systemImage: model.isRecordingMIDI ? "stop.circle.fill" : "record.circle") {
                    model.togglePrimaryRecord()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isRecordingMIDI ? .red : .accentColor)

                Button("All Notes Off", systemImage: "stop.circle") {
                    releaseAllSpatialTouches()
                    model.allVirtualMIDINotesOff()
                }
            }

            HStack(spacing: 12) {
                Stepper("Octave \(model.virtualKeyboard.baseOctave)", value: $model.virtualKeyboard.baseOctave, in: -1...7)
                    .frame(width: 190)
                Stepper("Range \(model.virtualKeyboard.visibleOctaves) oct", value: $model.virtualKeyboard.visibleOctaves, in: 1...4)
                    .frame(width: 210)

                Text("Velocity \(model.virtualKeyboard.velocity)")
                    .font(.caption.monospaced())
                Slider(value: Binding(
                    get: { Double(model.virtualKeyboard.velocity) },
                    set: { model.virtualKeyboard.velocity = UInt8(max(1, min(127, Int($0)))) }
                ), in: 1...127, step: 1)
                .frame(minWidth: 150, maxWidth: 270)

                Toggle("Latch", isOn: $model.virtualKeyboard.latch)
                    .toggleStyle(.button)
                Toggle("Scale Assist", isOn: $model.virtualKeyboard.scaleAssist)
                    .toggleStyle(.button)
            }
        }
        .padding(.horizontal, 4)
    }

    private var keybed: some View {
        let totalWidth = CGFloat(model.virtualKeyboard.visibleOctaves) * octaveWidth

        return ZStack(alignment: .topLeading) {
            ForEach(0..<model.virtualKeyboard.visibleOctaves, id: \.self) { octaveOffset in
                octaveVisual(startNote: Int(model.virtualKeyboard.firstNote) + octaveOffset * 12)
                    .offset(x: CGFloat(octaveOffset) * octaveWidth)
            }
        }
        .frame(width: totalWidth, height: whiteKeyHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            SpatialEventGesture(coordinateSpace: .local)
                .onChanged { events in
                    processSpatialEvents(events)
                }
                .onEnded { events in
                    processSpatialEvents(events)
                    releaseAllSpatialTouches()
                }
        )
    }

    private var octaveWidth: CGFloat { whiteKeyWidth * 7 }
    private var blackKeyWidth: CGFloat { whiteKeyWidth * 0.60 }
    private var blackKeyHeight: CGFloat { whiteKeyHeight * 0.62 }

    private func octaveVisual(startNote: Int) -> some View {
        let whitePitchClasses = [0, 2, 4, 5, 7, 9, 11]
        let blackPitchClasses = [1, 3, 6, 8, 10]

        return ZStack(alignment: .topLeading) {
            HStack(spacing: keyGap) {
                ForEach(Array(whitePitchClasses.enumerated()), id: \.offset) { _, pitchClass in
                    SpatialPianoKey(
                        isBlack: false,
                        isActive: model.virtualKeyboard.activeNotes.contains(UInt8(startNote + pitchClass)),
                        noteName: midiNoteName(startNote + pitchClass)
                    )
                    .frame(width: whiteKeyWidth - keyGap, height: whiteKeyHeight)
                }
            }

            ForEach(Array(blackPitchClasses.enumerated()), id: \.offset) { _, pitchClass in
                SpatialPianoKey(
                    isBlack: true,
                    isActive: model.virtualKeyboard.activeNotes.contains(UInt8(startNote + pitchClass)),
                    noteName: midiNoteName(startNote + pitchClass)
                )
                .frame(width: blackKeyWidth, height: blackKeyHeight)
                .offset(x: blackKeyX(pitchClass: pitchClass), y: 0)
                .zIndex(10)
            }
        }
        .frame(width: octaveWidth, height: whiteKeyHeight, alignment: .topLeading)
    }

    private func processSpatialEvents(_ events: SpatialEventCollection) {
        var ongoingIDs = Set<AnyHashable>()

        for event in events {
            let id = AnyHashable(event.id)
            switch event.phase {
            case .active:
                ongoingIDs.insert(id)
                guard let note = note(at: event.location) else {
                    releaseTouch(id)
                    continue
                }
                transitionTouch(id, to: note)
            case .ended, .cancelled:
                releaseTouch(id)
            @unknown default:
                break
            }
        }

        // SpatialEventCollection represents the currently ongoing events. If a
        // touch disappears from the collection, release the note it owned.
        // This keeps independent chord fingers and glissando transitions from
        // leaving orphaned notes behind.
        for staleID in activeSpatialTouches.keys where !ongoingIDs.contains(staleID) {
            releaseTouch(staleID)
        }
    }

    private func transitionTouch(_ id: AnyHashable, to note: UInt8) {
        let previous = activeSpatialTouches[id]
        guard previous != note else { return }

        if let previous {
            activeSpatialTouches.removeValue(forKey: id)
            if !activeSpatialTouches.values.contains(previous) {
                release(previous)
            }
        }

        if !activeSpatialTouches.values.contains(note) {
            press(note)
        }
        activeSpatialTouches[id] = note
    }

    private func releaseTouch(_ id: AnyHashable) {
        guard let previous = activeSpatialTouches.removeValue(forKey: id) else { return }
        if !activeSpatialTouches.values.contains(previous) {
            release(previous)
        }
    }

    private func releaseAllSpatialTouches() {
        let uniqueNotes = Set(activeSpatialTouches.values)
        activeSpatialTouches.removeAll()
        for note in uniqueNotes { release(note) }
    }

    private func note(at point: CGPoint) -> UInt8? {
        guard point.x >= 0, point.y >= 0,
              point.y <= whiteKeyHeight else { return nil }

        let octaveIndex = Int(point.x / octaveWidth)
        guard octaveIndex >= 0, octaveIndex < model.virtualKeyboard.visibleOctaves else { return nil }
        let localX = point.x - CGFloat(octaveIndex) * octaveWidth
        let startNote = Int(model.virtualKeyboard.firstNote) + octaveIndex * 12

        if point.y <= blackKeyHeight {
            for pitchClass in [1, 3, 6, 8, 10] {
                let minX = blackKeyX(pitchClass: pitchClass)
                let maxX = minX + blackKeyWidth
                if localX >= minX && localX <= maxX {
                    return UInt8(clamping: startNote + pitchClass)
                }
            }
        }

        let whitePitchClasses = [0, 2, 4, 5, 7, 9, 11]
        let whiteIndex = max(0, min(6, Int(localX / whiteKeyWidth)))
        return UInt8(clamping: startNote + whitePitchClasses[whiteIndex])
    }

    private func blackKeyX(pitchClass: Int) -> CGFloat {
        let boundaryIndex: Int
        switch pitchClass {
        case 1: boundaryIndex = 1
        case 3: boundaryIndex = 2
        case 6: boundaryIndex = 4
        case 8: boundaryIndex = 5
        default: boundaryIndex = 6
        }
        return CGFloat(boundaryIndex) * whiteKeyWidth - (whiteKeyWidth * 0.30)
    }

    private func press(_ note: UInt8) {
        if model.virtualKeyboard.latch {
            model.virtualMIDIToggleLatchedNote(note)
        } else {
            model.virtualMIDINoteDown(note)
        }
    }

    private func release(_ note: UInt8) {
        guard !model.virtualKeyboard.latch else { return }
        model.virtualMIDINoteUp(note)
    }

    private var routeSummary: String {
        var routes = [model.selectedInstrument.rawValue]
        if model.audioUnitHost.hasActiveInstrument { routes.append("AU Instrument") }
        if model.desktopBridge.activeInstanceID != nil { routes.append("Desktop Bridge") }
        return routes.joined(separator: " + ")
    }

    private func midiNoteName(_ note: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[note % 12])\((note / 12) - 1)"
    }
}

private struct SpatialPianoKey: View {
    let isBlack: Bool
    let isActive: Bool
    let noteName: String

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: isBlack ? 10 : 13, style: .continuous)
                .fill(keyFill)
                .overlay {
                    RoundedRectangle(cornerRadius: isBlack ? 10 : 13, style: .continuous)
                        .strokeBorder(
                            isActive ? Color.accentColor : borderColor,
                            lineWidth: isActive ? 5 : 1.5
                        )
                }
                .shadow(color: .black.opacity(isBlack ? 0.66 : 0.38), radius: isBlack ? 10 : 5, y: isBlack ? 9 : 5)

            Text(noteName)
                .font(.caption.bold())
                .foregroundStyle(isBlack ? Color.white : Color.black)
                .padding(.bottom, 11)
                .allowsHitTesting(false)
        }
        .scaleEffect(y: isActive ? 0.974 : 1, anchor: .top)
        .animation(.easeOut(duration: 0.055), value: isActive)
        .allowsHitTesting(false)
        .accessibilityLabel("MIDI note \(noteName)")
        .accessibilityValue(isActive ? "Playing" : "Idle")
    }

    private var keyFill: Color {
        if isBlack {
            return isActive ? Color(white: 0.30) : Color(white: 0.018)
        }
        return isActive ? Color(white: 0.78) : Color(white: 0.985)
    }

    private var borderColor: Color {
        isBlack ? Color.white.opacity(0.58) : Color.black.opacity(0.68)
    }
}

struct VisionInlineMIDIKeyboardView: View {
    @Environment(VisionStudioModel.self) private var model
    private let whitePitchClasses: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Label("MIDI Keyboard", systemImage: "pianokeys")
                    .font(.headline)
                Stepper("Octave \(model.virtualKeyboard.baseOctave)", value: Bindable(model).virtualKeyboard.baseOctave, in: -1...7)
                    .frame(maxWidth: 180)
                Text("Vel \(model.virtualKeyboard.velocity)")
                    .font(.caption.monospaced())
                Slider(value: Binding(
                    get: { Double(model.virtualKeyboard.velocity) },
                    set: { model.virtualKeyboard.velocity = UInt8(max(1, min(127, Int($0)))) }
                ), in: 1...127, step: 1)
                .frame(maxWidth: 220)
                Button("All Notes Off", systemImage: "stop.circle") { model.allVirtualMIDINotesOff() }
            }

            GeometryReader { proxy in
                compactKeyboard(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func compactKeyboard(width: CGFloat, height: CGFloat) -> some View {
        let start = Int(model.virtualKeyboard.firstNote)
        let notes = Array(start..<(start + 24))
        let whiteNotes = notes.filter { whitePitchClasses.contains($0 % 12) }
        let whiteWidth = width / CGFloat(max(1, whiteNotes.count))
        let blackWidth = whiteWidth * 0.62
        let whiteHeight = max(90, height)
        let blackHeight = whiteHeight * 0.6

        ZStack(alignment: .topLeading) {
            HStack(spacing: 2) {
                ForEach(whiteNotes, id: \.self) { note in
                    compactKey(UInt8(note), isBlack: false)
                        .frame(width: max(20, whiteWidth - 2), height: whiteHeight)
                }
            }
            ForEach(notes.filter { !whitePitchClasses.contains($0 % 12) }, id: \.self) { note in
                compactKey(UInt8(note), isBlack: true)
                    .frame(width: blackWidth, height: blackHeight)
                    .offset(x: blackOffset(note: note, whiteNotes: whiteNotes, whiteWidth: whiteWidth))
                    .zIndex(2)
            }
        }
    }

    private func compactKey(_ note: UInt8, isBlack: Bool) -> some View {
        SpatialPianoKey(
            isBlack: isBlack,
            isActive: model.virtualKeyboard.activeNotes.contains(note),
            noteName: ""
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !model.virtualKeyboard.activeNotes.contains(note) {
                        model.virtualMIDINoteDown(note)
                    }
                }
                .onEnded { _ in
                    model.virtualMIDINoteUp(note)
                }
        )
    }

    private func blackOffset(note: Int, whiteNotes: [Int], whiteWidth: CGFloat) -> CGFloat {
        CGFloat(whiteNotes.filter { $0 < note }.count) * whiteWidth - whiteWidth * 0.31
    }
}
