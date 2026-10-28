import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct ClipCreateDrag {
    var trackID: UUID
    var startX: CGFloat
    var endX: CGFloat
}

private struct ClipResizeStart {
    var startBeat: Double
    var lengthBeats: Double
    var trimStartBeats: Double
}

private enum ClipResizeEdge { case left, right }

private struct ArrangementMarquee {
    var start: CGPoint
    var current: CGPoint

    var rect: CGRect {
        CGRect(x: min(start.x, current.x),
               y: min(start.y, current.y),
               width: abs(current.x - start.x),
               height: abs(current.y - start.y))
    }
}

struct ArrangementView: View {
    @Environment(AppState.self) private var app
    @State private var pxPerBeat: CGFloat = 28
    @State private var waveformGain: CGFloat = 1.0
    @State private var dragStarts: [UUID: Double] = [:]
    @State private var dragLastSnapped: [UUID: Double] = [:]
    @State private var resizeStarts: [UUID: ClipResizeStart] = [:]
    @State private var resizingClipID: UUID?
    @State private var pluginDropTargetID: UUID?
    @State private var clipDragTargetTrackID: UUID?
    @State private var clipCreateDrag: ClipCreateDrag?
    @State private var marquee: ArrangementMarquee?
    @State private var stemSplitDialogClip: AudioClip?
    @State private var audioToMIDIRequest: AudioToMIDIRequest?
    @State private var stemSplitDialogModel: StemModel = .htdemucs
    @State private var stemSplitDialogBackend: StemBackend = .auto
    @State private var lastTrackpadMagnification: CGFloat = 1

    private let laneHeight: CGFloat = 72
    private let rulerHeight: CGFloat = 30
    private let trackHeaderWidth: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    grid
                    lanes
                    rulerScrubLayer
                    playhead
                    marqueeOverlay
                }
                .simultaneousGesture(marqueeGesture)
                .simultaneousGesture(trackpadZoomGesture)
                .contextMenu { arrangementBackgroundContextMenu }
                .coordinateSpace(name: "arrangement")
                .frame(width: trackHeaderWidth + CGFloat(app.project.lengthBeats) * pxPerBeat + 80,
                       height: rulerHeight + CGFloat(app.project.tracks.count) * laneHeight + 26)
                .onDrop(of: arrangementDropTypes, isTargeted: nil) { providers in
                    handleMediaOrPluginDrop(providers: providers, on: nil)
                }
            }
            .background(LSTheme.windowBackground)
        }
        .popover(item: $stemSplitDialogClip, arrowEdge: .top) { clip in
            StemSplitSelectedClipDialog(
                clip: clip,
                model: $stemSplitDialogModel,
                backend: $stemSplitDialogBackend
            )
        }
        .confirmationDialog(
            "Create MIDI from Audio",
            isPresented: Binding(
                get: { audioToMIDIRequest != nil },
                set: { if !$0 { audioToMIDIRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Melody to MIDI") { runAudioToMIDI(.melody) }
            Button("Harmony to MIDI") { runAudioToMIDI(.harmony) }
            Button("Drums to MIDI") { runAudioToMIDI(.drums) }
            Button("Cancel", role: .cancel) { audioToMIDIRequest = nil }
        } message: {
            if let request = audioToMIDIRequest {
                Text(
                    request.targetTrackID == nil
                        ? "Choose how ‘\(request.clip.displayName)’ should be transcribed. LemmingsStudio will create a suitable MIDI track."
                        : "Choose how ‘\(request.clip.displayName)’ should be transcribed onto the destination MIDI track."
                )
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Arrangement").font(.headline).foregroundStyle(LSTheme.text)
            Text("Drag empty MIDI lanes to create clips · drag clips across lanes to move tracks · click/drag ruler to scrub")
                .font(.caption2).foregroundStyle(LSTheme.dim)
            Toggle("Snap", isOn: Binding(
                get: { app.snapToGridEnabled },
                set: { app.snapToGridEnabled = $0; app.persistSettings() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Snap clip creation, dragging, resizing, imports, and prints to the Arrangement grid")
            Picker("Grid", selection: Binding(
                get: { app.gridSubdivisionBeats },
                set: { app.gridSubdivisionBeats = $0; app.persistSettings() }
            )) {
                Text("1 Bar").tag(4.0)
                Text("1/2").tag(2.0)
                Text("1/4").tag(1.0)
                Text("1/8").tag(0.5)
                Text("1/16").tag(0.25)
                Text("1/32").tag(0.125)
            }
            .labelsHidden()
            .frame(width: 86)
            Spacer()
            Menu {
                Button("Bhangra Architect → Chaal Clip") { app.quickBhangraArchitectInArrangement() }
                Button("2C → Guaracha Clip") { app.quick2CInArrangement() }
                Menu("Bailaton") {
                    Button("Dembow Clip") { app.quickBailatonInArrangement(.dembow) }
                    Button("Standard 3-3-2 Clip") { app.quickBailatonInArrangement(.reggaeton332) }
                    Button("Moombah Clip") { app.quickBailatonInArrangement(.moombah) }
                    Button("Moombahton Clip") { app.quickBailatonInArrangement(.moombahton) }
                }
                Divider()
                Button("Tech House Drum Kit") { app.quickDrumKitInArrangement(.techHouse) }
                Button("Guaracha Drum Kit") { app.quickDrumKitInArrangement(.guaracha) }
                Button("EDM Drum Kit") { app.quickDrumKitInArrangement(.edm) }
                Button("Lo-Fi Drum Kit") { app.quickDrumKitInArrangement(.lofi) }
                Button("Breakbeat Drum Kit") { app.quickDrumKitInArrangement(.breakbeat) }
                Divider()
                Button("Dembow Drum Kit") { app.quickDrumKitInArrangement(.dembow) }
                Button("Moombah Drum Kit") { app.quickDrumKitInArrangement(.moombah) }
                Divider()
                Button("Afro House Drum Kit") { app.quickDrumKitInArrangement(.afroHouse) }
                Button("Amapiano Drum Kit") { app.quickDrumKitInArrangement(.amapiano) }
                Button("Jersey Club Drum Kit") { app.quickDrumKitInArrangement(.jerseyClub) }
                Button("UK Garage Drum Kit") { app.quickDrumKitInArrangement(.ukGarage) }
                Button("Drum & Bass Drum Kit") { app.quickDrumKitInArrangement(.drumAndBass) }
                Button("Trap Drum Kit") { app.quickDrumKitInArrangement(.trap) }
                Button("Phonk Drum Kit") { app.quickDrumKitInArrangement(.phonk) }
                Button("Baile Funk Drum Kit") { app.quickDrumKitInArrangement(.baileFunk) }
            } label: {
                Label("Generators", systemImage: "wand.and.stars")
            }
            Button { _ = app.createMidiClip(on: app.selectedTrack, startBeat: app.engine.currentBeat, lengthBeats: Double(app.project.beatsPerBar), openPianoRoll: true) } label: { Label("New MIDI Clip", systemImage: "plus.rectangle") }
                .disabled(app.selectedTrack == nil || app.selectedTrack?.kind == .audio)
            Button { fillSelectedClip() } label: { Label("Generative Fill", systemImage: "sparkles") }
                .disabled(selectedMidiClip == nil)
            Button { openInPianoRoll() } label: { Label("Edit notes", systemImage: "pianokeys") }
                .disabled(selectedMidiClip == nil)
            Divider().frame(height: 18)
            Image(systemName: "minus.magnifyingglass")
            Slider(value: $pxPerBeat, in: 12...120).frame(width: 140)
            Image(systemName: "plus.magnifyingglass")
            Divider().frame(height: 18)
            Image(systemName: "waveform")
            Slider(value: $waveformGain, in: 0.5...6).frame(width: 110)
                .help("Waveform vertical zoom")
            Text(String(format: "%.1fx", waveformGain)).font(.caption2).foregroundStyle(LSTheme.dim)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }


    private var trackpadZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let current = max(0.05, CGFloat(value))
                let previous = max(0.05, lastTrackpadMagnification)
                let delta = current / previous
                guard delta.isFinite, delta > 0 else { return }
                pxPerBeat = min(220, max(8, pxPerBeat * delta))
                lastTrackpadMagnification = current
            }
            .onEnded { _ in
                lastTrackpadMagnification = 1
            }
    }

    private var arrangementDropTypes: [UTType] { [.fileURL, .audio, .movie, .text, .item] }

    private func handleMediaOrPluginDrop(providers: [NSItemProvider], on track: Track?) -> Bool {
        // Internal LemmingsStudio drags (plugins, samples and Splice rows) are
        // NSString/public.text providers. public.text also conforms to
        // public.item, so sending them through Finder import first causes the
        // media loader to claim the drop and silently discard the payload.
        for provider in providers {
            let isFileLike =
                provider.canLoadObject(ofClass: NSURL.self)
                || provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)

            let isTextLike =
                provider.canLoadObject(ofClass: NSString.self)
                || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || provider.hasItemConformingToTypeIdentifier("public.utf8-plain-text")
                || provider.hasItemConformingToTypeIdentifier("NSStringPboardType")

            if isTextLike && !isFileLike {
                return handlePluginDrop(providers: [provider], on: track)
            }
        }

        for provider in providers {
            if loadFinderFile(from: provider, on: track) { return true }
        }

        return handlePluginDrop(providers: providers, on: track)
    }

    private func loadFinderFile(from provider: NSItemProvider, on track: Track?) -> Bool {
        let importURL: (URL) -> Void = { url in
            let stableURL = stableFinderDropURL(url)
            DispatchQueue.main.async {
                app.importMediaFile(stableURL, targetTrack: track, forceNewTrack: track == nil)
            }
        }
        if provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let url = object as? URL { importURL(url) }
            }
            return true
        }
        for type in [UTType.fileURL.identifier, "public.file-url", "com.apple.finder.node"] {
            if provider.hasItemConformingToTypeIdentifier(type) {
                provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { importURL(url); return }
                    if let url = item as? URL { importURL(url); return }
                    if let str = item as? String {
                        let maybeURL = str.hasPrefix("file://") ? URL(string: str) : URL(fileURLWithPath: str)
                        if let maybeURL, maybeURL.isFileURL { importURL(maybeURL) }
                    }
                }
                return true
            }
        }
        for type in [UTType.audio.identifier, UTType.movie.identifier, UTType.item.identifier] {
            if provider.hasItemConformingToTypeIdentifier(type) {
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    guard let url else { return }
                    importURL(url)
                }
                return true
            }
        }
        return false
    }



    private func stableFinderDropURL(_ url: URL) -> URL {
        // `loadFileRepresentation` can hand SwiftUI a temp file that disappears
        // after the provider callback returns. Copy it immediately before we hop
        // back to the main actor; this avoids intermittent AVFAudio/CoreAudio
        // decode failures, especially while input hardware is warm for armed tracks.
        let fm = FileManager.default
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard ["wav", "wave", "aif", "aiff", "mp3", "m4a", "caf", "ogg", "flac", "ape", "mid", "midi", "mov", "mp4", "m4v", "avi", "mkv"].contains(ext) else { return url }
        let dropsDir = fm.temporaryDirectory.appendingPathComponent("LemmingsStudioFinderDrops", isDirectory: true)
        try? fm.createDirectory(at: dropsDir, withIntermediateDirectories: true)
        let safeBase = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let dest = dropsDir.appendingPathComponent(UUID().uuidString + "-" + safeBase).appendingPathExtension(url.pathExtension)
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }

    private var marqueeOverlay: some View {
        Group {
            if let marquee {
                let rect = marquee.rect
                RoundedRectangle(cornerRadius: 4)
                    .fill(LSTheme.focus.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(LSTheme.focus.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("arrangement"))
            .onChanged { value in
                guard value.startLocation.x >= trackHeaderWidth, value.startLocation.y >= rulerHeight else { return }
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > 10 || vertical > 10 else { return }
                marquee = ArrangementMarquee(start: value.startLocation, current: value.location)
                app.replaceArrangementClipSelection(keys: arrangementClipKeys(intersecting: marquee?.rect ?? .zero))
            }
            .onEnded { value in
                defer { marquee = nil }
                guard value.startLocation.x >= trackHeaderWidth, value.startLocation.y >= rulerHeight else { return }
                let keys = arrangementClipKeys(intersecting: ArrangementMarquee(start: value.startLocation, current: value.location).rect)
                app.replaceArrangementClipSelection(keys: keys)
            }
    }

    private func arrangementClipKeys(intersecting rect: CGRect) -> Set<String> {
        guard rect.width > 3 || rect.height > 3 else { return [] }
        var keys = Set<String>()
        for (trackIndex, track) in app.project.tracks.enumerated() {
            let laneTop = rulerHeight + CGFloat(trackIndex) * laneHeight
            for clip in track.clips {
                let clipRect = CGRect(x: trackHeaderWidth + CGFloat(clip.startBeat) * pxPerBeat,
                                      y: laneTop + 6,
                                      width: max(28, CGFloat(clip.lengthBeats) * pxPerBeat),
                                      height: laneHeight - 12)
                if rect.intersects(clipRect) { keys.insert("midi:\(clip.id.uuidString)") }
            }
            for clip in track.audioClips {
                let lengthBeats = clip.arrangementLengthBeats(projectTempo: app.project.tempo)
                let clipRect = CGRect(x: trackHeaderWidth + CGFloat(clip.startBeat) * pxPerBeat,
                                      y: laneTop + 6,
                                      width: max(28, CGFloat(lengthBeats) * pxPerBeat),
                                      height: laneHeight - 12)
                if rect.intersects(clipRect) { keys.insert("audio:\(clip.id.uuidString)") }
            }
        }
        return keys
    }

    private var selectedMidiClip: Clip? {
        guard let id = app.selectedClipID else { return nil }
        return app.project.tracks.flatMap { $0.clips }.first { $0.id == id }
    }

    private var grid: some View {
        Canvas { ctx, size in
            let totalBeats = app.project.lengthBeats
            let bars = app.project.lengthBars
            let startX = trackHeaderWidth

            // header strip
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: rulerHeight)), with: .color(LSTheme.panel.opacity(0.72)))
            ctx.fill(Path(CGRect(x: 0, y: 0, width: trackHeaderWidth, height: size.height)), with: .color(LSTheme.panel.opacity(0.64)))

            for bar in 0...bars {
                let x = startX + CGFloat(bar * app.project.beatsPerBar) * pxPerBeat
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(LSTheme.grid.opacity(1.0)), lineWidth: 1)
                ctx.draw(Text("\(bar + 1)").font(.system(size: 10, weight: .medium)).foregroundStyle(LSTheme.dim),
                         at: CGPoint(x: x + 12, y: 12))
                for beat in 1..<app.project.beatsPerBar {
                    let bx = x + CGFloat(beat) * pxPerBeat
                    var bp = Path()
                    bp.move(to: CGPoint(x: bx, y: rulerHeight))
                    bp.addLine(to: CGPoint(x: bx, y: size.height))
                    ctx.stroke(bp, with: .color(LSTheme.grid.opacity(0.45)), lineWidth: 1)
                }
            }

            for row in 0...app.project.tracks.count {
                let y = rulerHeight + CGFloat(row) * laneHeight
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(LSTheme.grid.opacity(0.65)), lineWidth: 1)
            }

            let endX = startX + CGFloat(totalBeats) * pxPerBeat
            var end = Path()
            end.move(to: CGPoint(x: endX, y: 0))
            end.addLine(to: CGPoint(x: endX, y: size.height))
            ctx.stroke(end, with: .color(LSTheme.record.opacity(0.50)), lineWidth: 2)
        }
    }

    private var lanes: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: rulerHeight)
            ForEach(app.project.tracks) { track in
                HStack(spacing: 0) {
                    arrangementTrackHeader(track)
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Color.clear)
                            .frame(width: CGFloat(app.project.lengthBeats) * pxPerBeat + 80, height: laneHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { location in createDefaultClip(to: track, atX: location.x) }
                            .gesture(clipCreateGesture(for: track))
                        if let preview = clipCreateDrag, preview.trackID == track.id {
                            clipCreatePreview(preview)
                        }
                        ForEach(track.clips) { clip in midiClipView(clip, track: track) }
                        ForEach(track.audioClips) { clip in audioClipView(clip, track: track) }
                    }
                    .frame(height: laneHeight)
                    .overlay {
                        if pluginDropTargetID == track.id || clipDragTargetTrackID == track.id {
                            RoundedRectangle(cornerRadius: 6).stroke(LSTheme.focus, lineWidth: 2).padding(3)
                        }
                    }
                    .onDrop(of: arrangementDropTypes, isTargeted: Binding(
                        get: { pluginDropTargetID == track.id },
                        set: { active in pluginDropTargetID = active ? track.id : nil }
                    )) { providers in
                        handleMediaOrPluginDrop(providers: providers, on: track)
                    }
                    .contextMenu { trackContextMenu(track) }
                }
                .frame(height: laneHeight)
            }
            HStack(spacing: 0) {
                Text("Drop here for new audio/MIDI track")
                    .font(.caption2.bold())
                    .foregroundStyle(LSTheme.dim)
                    .frame(width: trackHeaderWidth, height: 42)
                Rectangle()
                    .fill(LSTheme.panel2.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(pluginDropTargetID == nil ? LSTheme.grid.opacity(0.75) : LSTheme.focus.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4])).padding(4))
                    .frame(width: CGFloat(app.project.lengthBeats) * pxPerBeat + 80, height: 42)
            }
            .contentShape(Rectangle())
            .onDrop(of: arrangementDropTypes, isTargeted: nil) { providers in
                handleMediaOrPluginDrop(providers: providers, on: nil)
            }
        }
    }

    private func arrangementTrackHeader(_ track: Track) -> some View {
        let selected = app.selectedTrackID == track.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2).fill(track.color).frame(width: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(track.pluginTargetID ?? track.kind.rawValue).font(.system(size: 9)).foregroundStyle(LSTheme.dim).lineLimit(1)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Button("M") { app.toggleMute(track) }.buttonStyle(.plain).foregroundStyle(track.mute ? Color.orange : LSTheme.dim)
                Button("S") { app.toggleSolo(track) }.buttonStyle(.plain).foregroundStyle(track.solo ? Color.yellow : LSTheme.dim)
                Button(track.armed ? "● Arm" : "○ Arm") { app.toggleTrackArm(track) }
                    .buttonStyle(.plain)
                    .foregroundStyle(track.armed ? LSTheme.record : LSTheme.dim)
                    .help(track.armed ? "Disarm track" : "Arm track for recording")
                if track.kind == .audio {
                    Menu(track.audioInputMonitorMode.shortLabel) {
                        ForEach(AudioInputMonitorMode.allCases) { mode in
                            Button(mode.rawValue) { app.setAudioInputMonitorMode(mode, for: track) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 44)
                    .foregroundStyle(track.audioInputMonitorMode == .off ? LSTheme.dim : LSTheme.focus)
                    .help(track.audioInputMonitorMode.helpText)

                } else {
                    Button(track.loopDragEnabled ? "Loop" : "Trim") { track.loopDragEnabled.toggle() }
                        .buttonStyle(.plain)
                        .foregroundStyle(track.loopDragEnabled ? LSTheme.focus : LSTheme.dim)
                        .help(track.loopDragEnabled ? "Right-edge drag loops clips" : "Right-edge drag creates trim/padding only")
                }
                Spacer()
                if app.recorder.isRecording && track.kind == .audio && track.armed {
                    Text(String(format: "%.0f%%", app.recorder.level * 100)).font(.caption2).foregroundStyle(LSTheme.record)
                } else {
                    Text(String(format: "%.0f%%", track.volume * 100)).font(.caption2).foregroundStyle(LSTheme.dim)
                }
            }
            .font(.caption.bold())
            TrackRecordingInput(track:track)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(width: trackHeaderWidth, height: laneHeight, alignment: .leading)
        .background(selected ? LSTheme.focus.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { app.selectedTrackID = track.id }
        .onDrop(of: arrangementDropTypes, isTargeted: nil) { providers in
            handleMediaOrPluginDrop(providers: providers, on: track)
        }
        .contextMenu { trackContextMenu(track) }
    }

    @ViewBuilder
    private var arrangementBackgroundContextMenu: some View {
        Button("New Audio Track") { app.addTrack(kind: .audio) }
        Button("New MIDI Track") { app.addTrack(kind: .analog) }
        Button("New Sequencer Track") { app.addTrack(kind: .sequencer) }
        Divider()
        Button("New Drum Machine Track") { app.addTrack(kind: .drums) }
        Button("New Dubstep Wrangler Track") { app.addTrack(kind: .dubstepWrangler) }
    }

    private func shortInputDeviceLabel(_ track: Track) -> String {
        let name = track.audioInputDeviceName.isEmpty ? "Default" : track.audioInputDeviceName
        if name == "System Default" { return "Default" }
        let parts = name.split(separator: " ")
        if parts.count > 1 { return String(parts.prefix(2).joined(separator: " ")) }
        return String(name.prefix(10))
    }

    @ViewBuilder
    private func trackContextMenu(_ track: Track) -> some View {
        Button("Rename Track…") { app.promptRenameTrack(track) }
        Button("Duplicate Track") { app.duplicateTrack(track) }
        Button(track.frozen ? "Unfreeze Track" : "Freeze Track") { app.toggleFreeze(track) }
        Button("Bounce Track in Place") { app.bounceTrackInPlace(track) }
        if track.kind == .audio {
            Divider()
            Button(track.armed ? "Disarm Audio Input" : "Arm Audio Input") { app.toggleTrackArm(track) }
            Menu("Monitor Mode") {
                ForEach(AudioInputMonitorMode.allCases) { mode in
                    Button(mode.rawValue) { app.setAudioInputMonitorMode(mode, for: track) }
                }
            }
            Menu("Input Device") {
                Button("Refresh Inputs") { app.refreshAudioInputDevices() }
                Divider()
                ForEach(app.recorder.inputDevices) { device in
                    Button(device.name + " · \(device.channelCount)ch") { app.setAudioInputDevice(for: track, uid: device.uid) }
                }
            }
            Menu("Input Channel") {
                let uid = track.audioInputDeviceUID ?? AudioRecorder.systemDefaultDeviceUID
                ForEach(0..<app.recorder.channelCount(for: uid), id: \.self) { index in
                    Button(app.recorder.channelLabel(for: index, deviceUID: uid)) { app.setAudioInputChannel(for: track, channelIndex: index) }
                }
            }
        }
        Divider()
        Menu("Create Track") {
            Button("Audio Track") { app.addTrack(kind: .audio) }
            Button("MIDI Track") { app.addTrack(kind: .analog) }
            Button("Sequencer Track") { app.addTrack(kind: .sequencer) }
        }
        Divider()
        Button("Delete Track", role: .destructive) { app.deleteTrack(track) }
            .disabled(app.project.tracks.count <= 1)
    }

    private func midiClipView(_ clip: Clip, track: Track) -> some View {
        let w = max(28, CGFloat(clip.lengthBeats) * pxPerBeat)
        let x = CGFloat(clip.startBeat) * pxPerBeat
        return clipShell(name: clip.name, color: track.color, selected: app.isArrangementClipSelected(kind: "midi", id: clip.id), width: w) {
            Canvas { ctx, size in
                guard !clip.notes.isEmpty else { return }
                let pitches = clip.notes.map { $0.pitch }
                let lo = (pitches.min() ?? 60) - 1, hi = (pitches.max() ?? 72) + 1
                let span = max(1, hi - lo)
                for note in clip.notes {
                    let nx = CGFloat(note.start) * pxPerBeat
                    let nw = max(2, CGFloat(note.length) * pxPerBeat)
                    let ny = size.height - CGFloat(note.pitch - lo) / CGFloat(span) * size.height
                    ctx.fill(Path(roundedRect: CGRect(x: nx, y: ny - 2, width: nw, height: 3), cornerRadius: 1.5),
                             with: .color(.white.opacity(0.88)))
                }
            }
            .padding(.top, 18).padding(.horizontal, 3)
        }
        .overlay(alignment: .leading) { clipResizeHandle().gesture(midiResizeGesture(clip: clip, edge: .left)) }
        .overlay(alignment: .trailing) { clipResizeHandle().gesture(midiResizeGesture(clip: clip, edge: .right)) }
        .offset(x: x, y: 6)
        .onTapGesture(count: 2) { app.selectArrangementClip(kind: "midi", id: clip.id, trackID: track.id); openInPianoRoll() }
        .onTapGesture { app.selectArrangementClip(kind: "midi", id: clip.id, trackID: track.id, additive: NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift)) }
        .contextMenu {
            Button("Split at Playhead") { selectMidiClip(clip, track: track); app.splitSelectedClipAtPlayhead() }
            Button("Duplicate Clip") { duplicateMidiClip(clip, track: track) }
            Divider()
            Button("Copy") { selectMidiClip(clip, track: track); app.copySelectedClipToClipboard() }
            Button("Paste") { app.selectedTrackID = track.id; app.pasteClipToSelectedTrack(at: app.engine.currentBeat) }
                .disabled(!app.canPasteArrangementClip)
            Menu("Move to Track") {
                ForEach(app.project.tracks) { target in
                    Button(target.name) { selectMidiClip(clip, track: track); app.moveSelectedClip(to: target) }
                        .disabled(target.id == track.id)
                }
            }
            Button(clip.loopEnabled ? "Disable Edge-Loop" : "Enable Edge-Loop") { clip.loopEnabled.toggle(); app.engine.rebuild() }
            Button("Consolidate/Loop") { clip.lengthBeats = max(clip.lengthBeats, Double(app.project.beatsPerBar)); loopMidiClip(clip, sourceLength: max(0.25, clip.loopLengthBeats), targetLength: clip.lengthBeats); app.engine.rebuild() }
            Button(clip.isActive ? "Deactivate Clip" : "Activate Clip") { clip.isActive.toggle(); app.engine.rebuild() }
            Divider()
            Button("Delete Clip", role: .destructive) { selectMidiClip(clip, track: track); _ = app.deleteSelectedClip() }
            Divider()
            Button("Quantize") { app.selectedClipID = clip.id; app.quantizeSelectedClip() }
            Button("Fit to Scale") { app.selectedClipID = clip.id; app.fitSelectedClipToScale() }
            Menu("Generative Disco") {
                Button("Generate New Pattern") {
                    app.selectedClipID = clip.id
                    app.generativeDisco(on: clip)
                }
                Button("New Random Seed") {
                    app.randomizeGenerativeDiscoSeed()
                    app.selectedClipID = clip.id
                    app.generativeDisco(on: clip)
                }
                Toggle(
                    "Lock Seed",
                    isOn: Binding(
                        get: { app.generativeDiscoSeedLocked },
                        set: { app.generativeDiscoSeedLocked = $0 }
                    )
                )
                Divider()
                Button("Regenerate Bass Only") {
                    app.selectedClipID = clip.id
                    app.generativeDisco(on: clip, regenerating: [.bass])
                }
                Button("Regenerate Harmony Only") {
                    app.selectedClipID = clip.id
                    app.generativeDisco(on: clip, regenerating: [.harmony])
                }
                Button("Regenerate Accents Only") {
                    app.selectedClipID = clip.id
                    app.generativeDisco(on: clip, regenerating: [.accents])
                }
            }
            Button("Open in Piano Roll") { app.selectedClipID = clip.id; openInPianoRoll() }
        }
        .gesture(clipDragGesture(id: clip.id, currentStart: clip.startBeat, sourceTrack: track, kind: .midi) { clip.startBeat = $0 })
    }

    private func audioClipView(_ clip: AudioClip, track: Track) -> some View {
        let lengthBeats = clip.arrangementLengthBeats(projectTempo: app.project.tempo)
        let w = max(28, CGFloat(lengthBeats) * pxPerBeat)
        let x = CGFloat(clip.startBeat) * pxPerBeat
        return clipShell(name: clip.displayName, color: track.color, selected: app.isArrangementClipSelected(kind: "audio", id: clip.id), width: w, badge: clipFXBadge(clip)) {
            Canvas { ctx, size in
                let samples = clip.playbackPreviewSamples(projectTempo: app.project.tempo, maximumCount: max(2048, Int(size.width) * 8))
                guard !samples.isEmpty else { return }
                let columns = max(1, Int(size.width))
                let stride = max(1, samples.count / columns)
                let mid = size.height * 0.55
                for col in 0..<columns {
                    let start = min(samples.count - 1, col * stride)
                    let end = min(samples.count, start + stride)
                    var peak: Float = 0
                    var i = start
                    while i < end { peak = max(peak, abs(samples[i])); i += 1 }
                    let h = CGFloat(min(1, peak)) * waveformGain * (size.height * 0.36)
                    var path = Path()
                    let x = CGFloat(col)
                    path.move(to: CGPoint(x: x, y: mid - h))
                    path.addLine(to: CGPoint(x: x, y: mid + h))
                    ctx.stroke(path, with: .color(.white.opacity(0.82)), lineWidth: 1)
                }
            }
            .padding(.top, 18).padding(.horizontal, 3)
        }
        .overlay(alignment: .leading) { clipResizeHandle().gesture(audioResizeGesture(clip: clip, edge: .left)) }
        .overlay(alignment: .trailing) { clipResizeHandle().gesture(audioResizeGesture(clip: clip, edge: .right)) }
        .offset(x: x, y: 6)
        .onTapGesture {
            app.selectArrangementClip(kind: "audio", id: clip.id, trackID: track.id, additive: NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift))
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            handlePluginDrop(providers: providers, on: track, audioClip: clip)
        }
        .contextMenu {
            Button("Split at Playhead") { selectAudioClip(clip, track: track); app.splitSelectedClipAtPlayhead() }
            Button("Duplicate Clip") { duplicateAudioClip(clip, track: track) }
            Divider()
            Button("Copy") { selectAudioClip(clip, track: track); app.copySelectedClipToClipboard() }
            Button("Paste") { app.selectedTrackID = track.id; app.pasteClipToSelectedTrack(at: app.engine.currentBeat) }
                .disabled(!app.canPasteArrangementClip)
            Menu("Move to Track") {
                ForEach(app.project.tracks) { target in
                    Button(target.name) { selectAudioClip(clip, track: track); app.moveSelectedClip(to: target) }
                        .disabled(target.id == track.id)
                }
            }
            Button(clip.loopEnabled ? "Disable Loop" : "Enable Loop") { clip.loopEnabled.toggle(); app.engine.rebuild() }
            Button(clip.isActive ? "Deactivate Clip" : "Activate Clip") { clip.isActive.toggle(); app.engine.rebuild() }
            Divider()
            Button("Delete Clip", role: .destructive) { selectAudioClip(clip, track: track); _ = app.deleteSelectedClip() }
            Divider()
            Button("Warp On") { app.setWarp(clip, enabled: true) }
            Button("Warp Off") { app.setWarp(clip, enabled: false) }
            Menu("Warp Mode") {
                ForEach(WarpMode.allCases) { mode in
                    Button(mode.rawValue) { app.setWarp(clip, enabled: true, mode: mode) }
                }
            }
            Menu("Clip Tempo") {
                Button("Use Project Tempo (\(Int(app.project.tempo)) BPM)") { app.setClipTempo(clip, bpm: app.project.tempo, enableWarp: true) }
                if let detected = clip.detectedTempo {
                    Button("Use Detected Tempo (\(Int(detected)) BPM)") { app.resetClipTempoToDetected(clip) }
                }
                Button("Half Tempo") { app.setClipTempo(clip, bpm: max(40, clip.originalTempo / 2), enableWarp: true) }
                Button("Double Tempo") { app.setClipTempo(clip, bpm: min(300, clip.originalTempo * 2), enableWarp: true) }
            }
            Divider()
            Button("Create MIDI from Audio…") {
                requestAudioToMIDI(for: clip, targetTrack: nil)
            }
            Button("Slice to MIDI") { app.sliceAudioClipToMIDI(clip) }
            Button("Stem Split Selected Clip…") {
                selectAudioClip(clip, track: track)
                stemSplitDialogModel = .htdemucs
                stemSplitDialogBackend = app.selectedStemBackend
                if app.selectedStemOutputs.isEmpty {
                    app.selectedStemOutputs = Set(StemModel.htdemucs.stems)
                }
                stemSplitDialogClip = clip
            }
            Menu("Replicate Sonic Signature…") {
                Button("Use Stock Analog") {
                    Task { await app.replicateSonicSignature(from: clip, targetPluginName: nil) }
                }
                Menu("Use Third-Party Instrument") {
                    ForEach(KnownPlugins.synths.filter { $0.name != "Built-in Analog" }) { synth in
                        Button(synth.name) {
                            Task { await app.replicateSonicSignature(from: clip, targetPluginName: synth.name) }
                        }
                    }
                    if !app.discoveredPlugins.filter({ $0.role == .instrument }).isEmpty {
                        Divider()
                        ForEach(app.discoveredPlugins.filter { $0.role == .instrument }) { plugin in
                            Button(plugin.name) {
                                Task { await app.replicateSonicSignature(from: clip, targetPluginName: plugin.name) }
                            }
                        }
                    }
                }
            }
        }
        .gesture(clipDragGesture(id: clip.id, currentStart: clip.startBeat, sourceTrack: track, kind: .audio) { clip.startBeat = $0 })
    }

    private func clipResizeHandle() -> some View {
        // Keep the visible handle narrow, but make the hit target intentionally wide.
        // This prevents edge pulls from falling through to the clip body and becoming
        // a move gesture, which felt like resize was lagging/misbehaving.
        ZStack {
            Rectangle().fill(Color.clear)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.82))
                .frame(width: 7, height: laneHeight - 20)
        }
        .frame(width: 18, height: laneHeight - 10)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .help("Drag to resize clip")
    }

    private func clipShell<Content: View>(name: String, color: Color, selected: Bool, width: CGFloat, badge: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(selected ? 0.92 : 0.62))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.white : Color.black.opacity(0.18), lineWidth: selected ? 2 : 1))
            content()
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal").font(.system(size: 8))
                Text(name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.black.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.top, 4)
        }
        .frame(width: width, height: laneHeight - 12)
        .shadow(color: Color.black.opacity(selected ? 0.25 : 0.08), radius: selected ? 4 : 1, y: 1)
    }

    private var fineDragMultiplier: Double {
        let flags = NSEvent.modifierFlags
        // Hold Option for high-precision movement; Shift also works for users used
        // to "fine adjust" gestures in creative apps. This is intentionally runtime-
        // sampled so existing DragGesture code stays simple and responsive.
        return (flags.contains(.option) || flags.contains(.shift)) ? 0.20 : 1.0
    }

    private func snapBeat(_ beat: Double) -> Double {
        app.snapArrangementBeat(beat)
    }

    private func midiResizeGesture(clip: Clip, edge: ClipResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("arrangement"))
            .onChanged { value in
                resizingClipID = clip.id
                if resizeStarts[clip.id] == nil {
                    resizeStarts[clip.id] = ClipResizeStart(startBeat: clip.startBeat, lengthBeats: clip.lengthBeats, trimStartBeats: 0)
                }
                guard let base = resizeStarts[clip.id] else { return }
                let delta = Double(value.translation.width / pxPerBeat) * fineDragMultiplier
                var txn = Transaction()
                txn.animation = nil
                withTransaction(txn) {
                    switch edge {
                    case .left:
                        let end = base.startBeat + base.lengthBeats
                        let newStart = min(end - 0.25, max(0, snapBeat(base.startBeat + delta)))
                        let newLength = max(0.25, end - newStart)
                        guard abs(clip.startBeat - newStart) > 0.0001 || abs(clip.lengthBeats - newLength) > 0.0001 else { return }
                        clip.startBeat = newStart
                        clip.lengthBeats = newLength
                    case .right:
                        let newLength = max(0.25, snapBeat(base.lengthBeats + delta))
                        guard abs(clip.lengthBeats - newLength) > 0.0001 else { return }
                        clip.lengthBeats = newLength
                        // Never regenerate looped MIDI notes on every mouse frame. That was
                        // the hot path that made Ableton-style edge drags feel molasses-slow.
                        // We commit the expensive loop materialization once in onEnded.
                        if clip.loopEnabled && trackForClip(clip)?.loopDragEnabled != false {
                            // Preserve the clip's musical loop unit while dragging.
                            // Printed Step Sequencer clips set loopLengthBeats to the
                            // pattern/bar length. Replacing it with the drag-start
                            // length makes the repeat boundary drift after extension,
                            // which brings back the stray step-0 kick at clip edges.
                            clip.loopLengthBeats = canonicalMidiLoopLength(for: clip, fallback: base.lengthBeats)
                        }
                    }
                }
            }
            .onEnded { _ in
                let base = resizeStarts[clip.id]
                resizeStarts[clip.id] = nil
                resizingClipID = nil
                if let base,
                   edge == .right,
                   clip.loopEnabled,
                   trackForClip(clip)?.loopDragEnabled != false,
                   clip.lengthBeats > base.lengthBeats + 0.0001 {
                    loopMidiClip(clip, sourceLength: canonicalMidiLoopLength(for: clip, fallback: base.lengthBeats), targetLength: clip.lengthBeats)
                }
                app.ensureArrangementLength(coversBeat: clip.startBeat + clip.lengthBeats)
                finishRealtimeArrangementEdit()
            }
    }

    private func audioResizeGesture(clip: AudioClip, edge: ClipResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("arrangement"))
            .onChanged { value in
                resizingClipID = clip.id
                if resizeStarts[clip.id] == nil {
                    resizeStarts[clip.id] = ClipResizeStart(startBeat: clip.startBeat, lengthBeats: clip.arrangementLengthBeats(projectTempo: app.project.tempo), trimStartBeats: clip.trimStartBeats)
                }
                guard let base = resizeStarts[clip.id] else { return }
                let delta = Double(value.translation.width / pxPerBeat) * fineDragMultiplier
                var txn = Transaction()
                txn.animation = nil
                withTransaction(txn) {
                    switch edge {
                    case .left:
                        let end = base.startBeat + base.lengthBeats
                        let natural = clip.naturalLengthBeats(projectTempo: app.project.tempo) + base.trimStartBeats
                        let unclampedStart = snapBeat(base.startBeat + delta)
                        let newStart = min(end - 0.25, max(0, unclampedStart))
                        let trimDelta = max(-base.trimStartBeats, min(natural - 0.25, newStart - base.startBeat))
                        let finalStart = base.startBeat + trimDelta
                        let finalTrim = max(0, base.trimStartBeats + trimDelta)
                        let finalLength = max(0.25, end - finalStart)
                        guard abs(clip.startBeat - finalStart) > 0.0001 || abs(clip.trimStartBeats - finalTrim) > 0.0001 || abs((clip.lengthBeatsOverride ?? base.lengthBeats) - finalLength) > 0.0001 else { return }
                        clip.startBeat = finalStart
                        clip.trimStartBeats = finalTrim
                        clip.lengthBeatsOverride = finalLength
                    case .right:
                        let newLength = max(0.25, snapBeat(base.lengthBeats + delta))
                        guard abs((clip.lengthBeatsOverride ?? base.lengthBeats) - newLength) > 0.0001 else { return }
                        clip.lengthBeatsOverride = newLength
                        if clip.loopEnabled && trackForAudioClip(clip)?.loopDragEnabled != false {
                            clip.loopLengthBeats = max(0.25, base.lengthBeats)
                        }
                    }
                }
            }
            .onEnded { _ in
                resizeStarts[clip.id] = nil
                resizingClipID = nil
                app.ensureArrangementLength(coversBeat: clip.startBeat + clip.arrangementLengthBeats(projectTempo: app.project.tempo))
                finishRealtimeArrangementEdit()
            }
    }

    private enum ArrangementClipDragKind { case midi, audio }

    private func clipDragGesture(id: UUID, currentStart: Double, sourceTrack: Track, kind: ArrangementClipDragKind, setter: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("arrangement"))
            .onChanged { value in
                guard resizingClipID != id else { return }
                if dragStarts[id] == nil {
                    dragStarts[id] = currentStart
                    dragLastSnapped[id] = currentStart
                    clipDragTargetTrackID = sourceTrack.id
                }
                let base = dragStarts[id] ?? currentStart
                let rawBeat = base + Double(value.translation.width / pxPerBeat) * fineDragMultiplier
                let snapped = max(0, snapBeat(rawBeat))
                if abs((dragLastSnapped[id] ?? currentStart) - snapped) > 0.0001 {
                    dragLastSnapped[id] = snapped
                    setter(snapped)
                }
                if let target = trackAtArrangementY(value.location.y) {
                    clipDragTargetTrackID = target.id
                }
            }
            .onEnded { value in
                let target = trackAtArrangementY(value.location.y)
                dragStarts[id] = nil
                dragLastSnapped[id] = nil
                clipDragTargetTrackID = nil
                guard resizingClipID != id else { return }
                if let target, target.id != sourceTrack.id {
                    switch kind {
                    case .midi:
                        app.moveMidiClip(id, to: target)
                    case .audio:
                        if target.kind == .audio {
                            app.moveAudioClip(id, to: target)
                        } else if let clip = sourceTrack.audioClips.first(
                            where: { $0.id == id }
                        ) {
                            requestAudioToMIDI(for: clip, targetTrack: target)
                        }
                    }
                } else {
                    finishRealtimeArrangementEdit()
                }
            }
    }

    private struct AudioToMIDIRequest: Identifiable {
        let id = UUID()
        let clip: AudioClip
        let targetTrackID: UUID?
    }

    private func requestAudioToMIDI(
        for clip: AudioClip,
        targetTrack: Track?
    ) {
        audioToMIDIRequest = AudioToMIDIRequest(
            clip: clip,
            targetTrackID: targetTrack?.id
        )
    }

    private func runAudioToMIDI(_ mode: AudioToMIDIMode) {
        guard let request = audioToMIDIRequest else { return }
        audioToMIDIRequest = nil

        let target = request.targetTrackID.flatMap { id in
            app.project.tracks.first { $0.id == id }
        }

        app.createMIDIFromAudio(
            request.clip,
            mode: mode,
            targetTrack: target
        )
    }

    private func trackAtArrangementY(_ y: CGFloat) -> Track? {
        let row = Int(((y - rulerHeight) / laneHeight).rounded(.down))
        guard row >= 0, row < app.project.tracks.count else { return nil }
        return app.project.tracks[row]
    }

    private func finishRealtimeArrangementEdit() {
        app.writeRecoverySnapshot()
        // Playback reads the Observable clip objects directly, so resize/move edits
        // are already live while the transport is rolling. Do not stop/rebuild the
        // engine during playback; that makes the gesture feel laggy and can retrigger
        // hosted instruments. When stopped, keep the old rebuild for offline caches.
        if !app.engine.transport.isPlaying {
            app.engine.rebuild()
        }
    }

    private func trackForClip(_ clip: Clip) -> Track? {
        app.project.tracks.first { track in track.clips.contains { $0.id == clip.id } }
    }

    private func trackForAudioClip(_ clip: AudioClip) -> Track? {
        app.project.tracks.first { track in track.audioClips.contains { $0.id == clip.id } }
    }

    private func canonicalMidiLoopLength(for clip: Clip, fallback: Double) -> Double {
        // A clip's loop unit is not necessarily its current Arrangement length.
        // For printed Step Sequencer clips the source unit is the pattern/bar length
        // stored in loopLengthBeats. Edge-dragging must repeat that unit, not promote
        // the already-stretched clip length into the new loop source.
        let stored = clip.loopLengthBeats
        if stored.isFinite, stored > 0.03125, stored <= max(fallback, clip.lengthBeats) + 0.0001 {
            return max(0.03125, stored)
        }
        return max(0.03125, fallback)
    }

    private func loopMidiClip(_ clip: Clip, sourceLength: Double, targetLength: Double) {
        let sourceLength = canonicalMidiLoopLength(for: clip, fallback: sourceLength)
        let targetLength = max(sourceLength, targetLength)
        let epsilon = 0.000_001
        // Treat loop regions as half-open: [offset, offset + sourceLength).
        // This matches Step Sequencer print/export and prevents a note exactly on
        // the right edge from being copied as the final note of the previous bar.
        let seedNotes = clip.notes
            .filter { $0.start >= -epsilon && $0.start < sourceLength - epsilon }
            .map { note in
                ClipNote(pitch: note.pitch,
                         start: max(0, note.start),
                         length: min(note.length, max(0.03125, sourceLength - max(0, note.start))),
                         velocity: note.velocity)
            }
        guard !seedNotes.isEmpty, targetLength > sourceLength + epsilon else {
            clip.loopLengthBeats = sourceLength
            return
        }
        var out: [ClipNote] = []
        var offset = 0.0
        while offset < targetLength - epsilon {
            let loopEnd = min(targetLength, offset + sourceLength)
            for note in seedNotes {
                let start = offset + note.start
                guard start < loopEnd - epsilon, start < targetLength - epsilon else { continue }
                let available = min(targetLength - start, loopEnd - start)
                guard available > epsilon else { continue }
                // Adjacent loop repeats are half-open. Do not force a minimum
                // length that crosses the right edge, or the last hat/kick from
                // one repeat can bleed into the next repeat/print.
                let maxLength = min(note.length, available)
                out.append(ClipNote(pitch: note.pitch, start: start, length: max(0.001, maxLength), velocity: note.velocity))
            }
            offset += sourceLength
        }
        clip.notes = out
        clip.loopLengthBeats = sourceLength
    }

    private var rulerScrubLayer: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: CGFloat(app.project.lengthBeats) * pxPerBeat, height: rulerHeight)
            .offset(x: trackHeaderWidth, y: 0)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("arrangement"))
                .onChanged { value in scrub(x: value.location.x - trackHeaderWidth) })
    }

    private var playhead: some View {
        TimelineView(.animation) { _ in
            let beat = min(app.project.lengthBeats, max(0, app.engine.currentBeat))
            ZStack(alignment: .top) {
                Rectangle().fill(LSTheme.record).frame(width: 2)
                VStack(spacing: 0) {
                    Triangle().fill(LSTheme.record).frame(width: 12, height: 8)
                    Text(String(format: "%.1f", beat)).font(.system(size: 8, design: .monospaced)).foregroundStyle(.red)
                        .padding(.top, 1)
                }
                .offset(y: 1)
            }
            .frame(width: 36, height: rulerHeight + CGFloat(app.project.tracks.count) * laneHeight)
            .offset(x: trackHeaderWidth + CGFloat(beat) * pxPerBeat - 18, y: 0)
            .allowsHitTesting(false)
        }
    }

    private func selectMidiClip(_ clip: Clip, track: Track) {
        app.selectedTrackID = track.id
        app.selectedClipID = clip.id
        app.selectedAudioClipID = nil
        app.selectedAudioClipTrackID = nil
    }

    private func selectAudioClip(_ clip: AudioClip, track: Track) {
        app.selectedTrackID = track.id
        app.selectedClipID = nil
        app.selectedAudioClipID = clip.id
        app.selectedAudioClipTrackID = track.id
        app.detailDeck = .clip
    }

    private func duplicateMidiClip(_ clip: Clip, track: Track) {
        app.duplicateMidiClip(clip, on: track)
    }

    private func splitMidiClip(_ clip: Clip, track: Track) {
        let cut = app.engine.currentBeat - clip.startBeat
        guard cut > 0.05 && cut < clip.lengthBeats - 0.05 else { return }
        let right = Clip(name: clip.name + " B", startBeat: app.engine.currentBeat, lengthBeats: clip.lengthBeats - cut, notes: [], color: clip.color)
        var leftNotes: [ClipNote] = []
        for n in clip.notes {
            if n.start >= cut { right.notes.append(ClipNote(pitch: n.pitch, start: n.start - cut, length: n.length, velocity: n.velocity)) }
            else { leftNotes.append(n) }
        }
        clip.lengthBeats = cut
        clip.notes = leftNotes
        track.clips.append(right)
        app.selectedClipID = right.id
        app.engine.rebuild()
    }

    private func duplicateAudioClip(_ clip: AudioClip, track: Track) {
        app.duplicateAudioClip(clip, on: track)
    }

    private func splitAudioClip(_ clip: AudioClip, track: Track) {
        let cutBeat = app.engine.currentBeat - clip.startBeat
        let totalBeats = clip.arrangementLengthBeats(projectTempo: app.project.tempo)
        guard cutBeat > 0.05 && cutBeat < totalBeats - 0.05 else { return }
        let cutSample = max(1, min(clip.samples.count - 1, Int((cutBeat / totalBeats) * Double(clip.samples.count))))
        let rightSamples = Array(clip.samples[cutSample...])
        clip.samples = Array(clip.samples[..<cutSample])
        let right = AudioClip(startBeat: app.engine.currentBeat, samples: rightSamples, sampleRate: clip.sampleRate)
        right.displayName = clip.displayName + " B"
        right.originalTempo = clip.originalTempo
        right.detectedTempo = clip.detectedTempo
        right.gainDB = clip.gainDB
        right.pitchSemitones = clip.pitchSemitones
        right.pitchCents = clip.pitchCents
        right.warpEnabled = clip.warpEnabled
        right.warpMode = clip.warpMode
        if right.warpEnabled { WarpEngine.warp(right, projectTempo: app.project.tempo) }
        track.audioClips.append(right)
        app.selectedAudioClipID = right.id
        app.engine.rebuild()
    }

    private func handlePluginDrop(providers: [NSItemProvider], on track: Track?) -> Bool {
        handlePluginDrop(providers: providers, on: track, audioClip: nil)
    }

    private func handlePluginDrop(providers: [NSItemProvider], on track: Track?, audioClip: AudioClip?) -> Bool {
        guard let provider = providers.first else { return false }
        let consumeText: (String) -> Void = { text in
            DispatchQueue.main.async {
                let handled = app.handlePluginDropText(text, on: track, audioClip: audioClip)
                if !handled {
                    let preview = String(text.prefix(96))
                    app.spliceStatus = "⚠️ Drop was not recognized: \(preview)"
                    app.editStatus = "⚠️ Arrangement drop was not recognized"
                }
                pluginDropTargetID = nil
            }
        }

        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = object as? String else { return }
                consumeText(text)
            }
            return true
        }

        // AppKit-originated drags sometimes arrive as public.text/plain data
        // rather than an NSString object. Without this path, Splice rows would
        // show “FETCH ON DROP” but Arrangement would silently ignore them.
        for type in [UTType.text.identifier, UTType.plainText.identifier, "public.utf8-plain-text", "public.text", "NSStringPboardType"] {
            if provider.hasItemConformingToTypeIdentifier(type) {
                provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                    if let data = item as? Data, let text = String(data: data, encoding: .utf8) { consumeText(text); return }
                    if let text = item as? String { consumeText(text); return }
                    if let text = item as? NSString { consumeText(text as String); return }
                }
                return true
            }
        }
        return false
    }

    private func clipFXBadge(_ clip: AudioClip) -> String? {
        let count = clip.devices.count + clip.externalPluginSlots.count
        return count > 0 ? "FX \(count)" : nil
    }

    private func scrub(x: CGFloat) {
        let beat = Double(max(0, x) / pxPerBeat)
        app.scrub(to: beat)
    }

    private func createDefaultClip(to track: Track, atX x: CGFloat) {
        guard track.kind != .audio else { return }
        let rawBeat = Double(max(0, x) / pxPerBeat)
        let bar = Double(app.project.beatsPerBar)
        let beat = app.snapArrangementBeat(rawBeat, rule: .down)
        _ = app.createMidiClip(on: track, startBeat: beat, lengthBeats: bar, openPianoRoll: false)
    }

    private func clipCreateGesture(for track: Track) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard track.kind != .audio else { return }
                let start = min(value.startLocation.x, value.location.x)
                let end = max(value.startLocation.x, value.location.x)
                clipCreateDrag = ClipCreateDrag(trackID: track.id, startX: start, endX: end)
            }
            .onEnded { value in
                guard track.kind != .audio else { clipCreateDrag = nil; return }
                let startX = min(value.startLocation.x, value.location.x)
                let endX = max(value.startLocation.x, value.location.x)
                let rawStartBeat = Double(max(0, startX) / pxPerBeat)
                let rawEndBeat = Double(max(0, endX) / pxPerBeat)
                let startBeat = max(0, app.snapArrangementBeat(rawStartBeat, rule: .down))
                let endBeat = max(startBeat + app.arrangementSnapUnit, app.snapArrangementBeat(rawEndBeat, rule: .up))
                let length = max(app.arrangementSnapUnit, endBeat - startBeat)
                _ = app.createMidiClip(on: track, startBeat: startBeat, lengthBeats: length, openPianoRoll: true)
                clipCreateDrag = nil
            }
    }

    private func clipCreatePreview(_ preview: ClipCreateDrag) -> some View {
        let x = min(preview.startX, preview.endX)
        let w = max(12, abs(preview.endX - preview.startX))
        return RoundedRectangle(cornerRadius: 6)
            .fill(LSTheme.focus.opacity(0.24))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(LSTheme.focus, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
            .frame(width: w, height: laneHeight - 12)
            .offset(x: x, y: 6)
            .overlay(alignment: .topLeading) {
                Text("New MIDI Clip")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.top, 9)
                    .offset(x: x, y: 0)
            }
    }

    private func fillSelectedClip() {
        guard let clip = selectedMidiClip else { return }
        let endBeat = app.project.lengthBeats - clip.startBeat
        clip.notes = GenerativeFill(seed: UInt64(clip.id.hashValue & 0x7fffffff))
            .fill(clip: clip, project: app.project, untilBeat: endBeat)
        clip.lengthBeats = max(clip.lengthBeats, (clip.notes.map { $0.start + $0.length }.max() ?? clip.lengthBeats))
        app.engine.rebuild()
    }

    private func openInPianoRoll() {
        guard let clip = selectedMidiClip,
              let track = app.project.tracks.first(where: { $0.clips.contains { $0.id == clip.id } }) else { return }
        app.selectedTrackID = track.id
        PianoRollState.shared.clipID = clip.id
        app.workspace = .pianoRoll
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}


// MARK: - Stem split popup

private struct StemSplitSelectedClipDialog: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let clip: AudioClip
    @Binding var model: StemModel
    @Binding var backend: StemBackend

    private var selectedStemCount: Int {
        app.selectedStemOutputs.intersection(Set(model.stems)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(LSTheme.focus)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Stem Split Selected Clip")
                        .font(.title3.bold())
                    Text(clip.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            GroupBox("Backend") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Backend", selection: $backend) {
                        ForEach(StemBackend.allCases) { option in
                            Text(option.shortLabel).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(backend.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }

            GroupBox("Model and stems") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Model", selection: $model) {
                        ForEach(StemModel.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model) { _, newValue in
                        let allowed = Set(newValue.stems)
                        app.selectedStemOutputs = app.selectedStemOutputs.intersection(allowed)
                        if app.selectedStemOutputs.isEmpty { app.selectedStemOutputs = allowed }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(model.stems, id: \.self) { stem in
                            Toggle(stem.capitalized, isOn: Binding(
                                get: { app.selectedStemOutputs.contains(stem) },
                                set: { enabled in
                                    if enabled { app.selectedStemOutputs.insert(stem) }
                                    else { app.selectedStemOutputs.remove(stem) }
                                }
                            ))
                            .toggleStyle(.button)
                            .controlSize(.small)
                        }
                    }

                    HStack {
                        Button("All") { app.selectedStemOutputs = Set(model.stems) }
                        Button("None") { app.selectedStemOutputs.removeAll() }
                        Spacer()
                        Text("\(selectedStemCount) selected")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            GroupBox("Output") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Merge selected stems to one audio track", isOn: Binding(
                        get: { app.stemMergeToSingleAudioTrack },
                        set: { app.stemMergeToSingleAudioTrack = $0 }
                    ))
                    Toggle("Create submix group for stem tracks", isOn: Binding(
                        get: { app.stemCreateSubmixGroup },
                        set: { app.stemCreateSubmixGroup = $0 }
                    ))
                    Text("Finished stems will be imported into new Arrangement audio tracks automatically.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if app.stemProgress > 0 && app.stemProgress < 1 {
                ProgressView(value: app.stemProgress) {
                    Text("Extracting stems…")
                } currentValueLabel: {
                    Text("\(Int((app.stemProgress * 100).rounded()))%")
                }
            }
            if !app.stemStatus.isEmpty {
                Text(app.stemStatus)
                    .font(.caption)
                    .foregroundStyle(app.stemStatus.hasPrefix("⚠️") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button {
                    app.selectedStemBackend = backend
                    app.runStemSplit(on: clip, model: model, backend: backend)
                } label: {
                    Label("Start Stem Split", systemImage: "scissors")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedStemCount == 0 || (app.stemProgress > 0 && app.stemProgress < 1))
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear {
            if app.selectedStemOutputs.isEmpty { app.selectedStemOutputs = Set(model.stems) }
            backend = app.selectedStemBackend
        }
    }
}
