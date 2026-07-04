import SwiftUI

// MARK: - Automation editor

struct AutomationView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlobalAutomationSection()

                Divider().padding(.vertical, 2)

                if let track = app.selectedTrack {
                    HStack {
                        Circle().fill(track.color).frame(width: 10, height: 10)
                        Text("\(track.name) — Clip / Track Automation").font(.headline)
                        Spacer()
                        addLaneMenu(track)
                    }
                    Text("Automation is drawn over the selected track’s Arrangement context, so breakpoints line up with clips, waveform peaks, and MIDI notes instead of floating blind.")
                        .font(.caption).foregroundStyle(.secondary)

                    if track.automationLanes.isEmpty {
                        Text("No automation yet. Add a lane, automate Device On/Off, or ask the AI Producer for “brilliant automation”.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    }
                    ForEach(track.automationLanes) { lane in
                        LaneRow(track: track, lane: lane)
                    }
                } else {
                    Text("Select a track to edit clip/device automation. Global automation stays available above.")
                        .foregroundStyle(.secondary).padding()
                }
            }
            .padding(14)
        }
    }

    private func nodes(_ track: Track) -> [(id: String, label: String, params: [ParamInfo])] {
        var out: [(String, String, [ParamInfo])] = []
        // Instrument params: prefer the live engine node, but fall back to a
        // factory-built instrument so the menu is populated even when the engine
        // hasn't instantiated this track yet (e.g. before playback). Without this,
        // a freshly added instrument track had an EMPTY "Add Lane" menu — which is
        // exactly why clicking it looked like it did nothing.
        let instNode: Automatable? = app.engine.liveNode(track: track, nodeID: "instrument")
            ?? (app.engine.makeInstrument(for: track) as? Automatable)
        if let instNode {
            let params = instNode.automatableParams
            if !params.isEmpty { out.append(("instrument", track.kind.rawValue, params)) }
        }
        for d in track.devices {
            var params: [ParamInfo] = [ParamInfo(AutomationSpecialParam.deviceOn, "Device On", 0, 1)]
            let p = (app.engine.liveNode(track: track, nodeID: d.nodeID) ?? DeviceFactory.make(d.kind)).automatableParams
            params.append(contentsOf: p)
            out.append((d.nodeID, d.kind.rawValue, params))
        }
        for slot in track.externalPluginSlots where slot.role != .instrument {
            var params: [ParamInfo] = [ParamInfo(AutomationSpecialParam.deviceOn, "Device On", 0, 1)]
            if let live = app.engine.liveNode(track: track, nodeID: slot.nodeID) {
                params.append(contentsOf: live.automatableParams)
            } else {
                #if canImport(AVFoundation) && canImport(AudioToolbox)
                if slot.format == .audioUnit, let probe = HostedAUAudioEffect(pluginName: slot.name, sampleRate: app.project.sampleRate) {
                    params.append(contentsOf: probe.automatableParams)
                }
                #endif
            }
            out.append((slot.nodeID, slot.name, params))
        }
        return out
    }

    private func addLaneMenu(_ track: Track) -> some View {
        Menu {
            let available = nodes(track)
            if available.isEmpty {
                Text("No automatable parameters on this track")
                Button("Add a device first…") { app.workspace = .devices }
            } else {
                ForEach(available, id: \.id) { node in
                    Menu(node.label) {
                        ForEach(node.params) { p in
                            Button(p.name) { _ = track.lane(nodeID: node.id, paramID: p.id) }
                        }
                    }
                }
            }
        } label: { Label("Add Lane", systemImage: "plus.circle") }
        .menuStyle(.borderlessButton).fixedSize()
    }
}

// MARK: - Global automation

private struct GlobalAutomationSection: View {
    @Environment(AppState.self) private var app
    @State private var beat = "0"
    @State private var bpm = "124"

    var body: some View {
        @Bindable var project = app.project
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Global Automation", systemImage: "globe.americas.fill").font(.headline)
                Spacer()
                Toggle("Tempo", isOn: $project.tempoAutomationEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: project.tempoAutomationEnabled) { _, _ in app.rebuildTempoMap() }
            }
            Text("Automates whole-project values. Tempo changes affect the transport globally and re-warp audio clips when edited.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Project Tempo").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(project.tempoAutomationEnabled ? "Enabled" : "Disabled")
                        .font(.caption2)
                        .foregroundStyle(project.tempoAutomationEnabled ? .green : .secondary)
                    Button { project.tempoPoints.removeAll(); app.rebuildTempoMap() } label: { Image(systemName: "eraser") }
                        .buttonStyle(.plain)
                    Button {
                        if project.tempoPoints.isEmpty {
                            project.tempoPoints = [TempoPoint(beat: 0, bpm: project.tempo), TempoPoint(beat: project.lengthBeats, bpm: project.tempo)]
                            app.rebuildTempoMap()
                        }
                    } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain)
                }
                TempoAutomationCanvas(points: $project.tempoPoints, enabled: $project.tempoAutomationEnabled, lengthBeats: project.lengthBeats, baseTempo: project.tempo)
                    .frame(height: 96)
                    .onChange(of: project.tempoPoints) { _, _ in app.rebuildTempoMap() }
                HStack {
                    TextField("Beat", text: $beat).frame(width: 62).textFieldStyle(.roundedBorder)
                    TextField("BPM", text: $bpm).frame(width: 62).textFieldStyle(.roundedBorder)
                    Button("Add point") {
                        if let b = Double(beat), let t = Double(bpm) {
                            project.tempoPoints.append(TempoPoint(beat: max(0, min(project.lengthBeats, b)), bpm: max(20, min(300, t))))
                            project.tempoPoints.sort { $0.beat < $1.beat }
                            project.tempoAutomationEnabled = true
                            app.rebuildTempoMap()
                        }
                    }.buttonStyle(.bordered)
                    Spacer()
                    Text("Tap the lane to add points; vertical position maps 40–220 BPM.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(project.tempoAutomationEnabled ? 1 : 0.72)
        }
    }
}

private struct TempoAutomationCanvas: View {
    @Environment(AppState.self) private var app
    @Binding var points: [TempoPoint]
    @Binding var enabled: Bool
    let lengthBeats: Double
    let baseTempo: Double
    @State private var selectedPointIndex: Int?
    @State private var activeDragPointIndex: Int?
    @State private var dragMoved = false
    private let minBPM = 40.0
    private let maxBPM = 220.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.15))
                ArrangementContextOverlay(tracks: app.project.tracks, lengthBeats: lengthBeats, projectTempo: app.project.tempo)
                    .opacity(0.32)
                    .allowsHitTesting(false)
                beatGrid(width: w, height: h)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                Path { path in
                    let pts = effectivePoints
                    guard !pts.isEmpty else { return }
                    func cg(_ p: TempoPoint) -> CGPoint {
                        let x = CGFloat(p.beat / max(lengthBeats, 1)) * w
                        let norm = (max(min(p.bpm, maxBPM), minBPM) - minBPM) / (maxBPM - minBPM)
                        let y = h - CGFloat(norm) * h
                        return CGPoint(x: x, y: y)
                    }
                    path.move(to: cg(pts[0]))
                    for p in pts.dropFirst() { path.addLine(to: cg(p)) }
                }
                .stroke(Color.accentColor, lineWidth: 2)
                ForEach(editablePointIndices, id: \.self) { idx in
                    let p = points[idx]
                    let x = CGFloat(p.beat / max(lengthBeats, 1)) * w
                    let norm = (max(min(p.bpm, maxBPM), minBPM) - minBPM) / (maxBPM - minBPM)
                    let y = h - CGFloat(norm) * h
                    Circle()
                        .fill(selectedPointIndex == idx ? Color.white : Color.accentColor)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: selectedPointIndex == idx ? 2 : 0))
                        .frame(width: selectedPointIndex == idx ? 11 : 8, height: selectedPointIndex == idx ? 11 : 8)
                        .position(x: x, y: y)
                        .contentShape(Rectangle())
                        .help("Click to select. Drag to move. Right-click to delete.")
                        .contextMenu {
                            Button("Delete Tempo Point", role: .destructive) {
                                deleteTempoPoint(at: idx)
                            }
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("220")
                    Spacer()
                    Text("40")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(4)
            }
            .coordinateSpace(name: "tempoAutomationCanvas")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("tempoAutomationCanvas"))
                    .onChanged { value in
                        if activeDragPointIndex == nil && !dragMoved {
                            activeDragPointIndex = tempoPointIndex(near: value.startLocation, width: w, height: h)
                        }
                        guard let idx = activeDragPointIndex else { return }
                        let distance = dragDistance(from: value.startLocation, to: value.location)
                        guard distance >= 4 else { return }
                        dragMoved = true
                        selectedPointIndex = idx
                        let beat = Double(value.location.x / max(w, 1)) * max(lengthBeats, 1)
                        let norm = Double(1 - value.location.y / max(h, 1))
                        let bpm = minBPM + max(0, min(1, norm)) * (maxBPM - minBPM)
                        updateTempoPoint(at: idx, beat: beat, bpm: bpm, sortNow: false)
                        enabled = true
                    }
                    .onEnded { value in
                        defer {
                            activeDragPointIndex = nil
                            dragMoved = false
                        }
                        if let idx = activeDragPointIndex, dragMoved {
                            let beat = Double(value.location.x / max(w, 1)) * max(lengthBeats, 1)
                            let norm = Double(1 - value.location.y / max(h, 1))
                            let bpm = minBPM + max(0, min(1, norm)) * (maxBPM - minBPM)
                            updateTempoPoint(at: idx, beat: beat, bpm: bpm, sortNow: true)
                            selectedPointIndex = nearestTempoPointIndex(beat: beat, bpm: bpm)
                            app.rebuildTempoMap()
                            return
                        }
                        if let existing = tempoPointIndex(near: value.location, width: w, height: h) {
                            selectedPointIndex = existing
                            return
                        }
                        let beat = Double(value.location.x / max(w, 1)) * max(lengthBeats, 1)
                        let norm = Double(1 - value.location.y / max(h, 1))
                        let bpm = minBPM + max(0, min(1, norm)) * (maxBPM - minBPM)
                        points.append(TempoPoint(beat: max(0, min(lengthBeats, beat)), bpm: bpm))
                        points.sort { $0.beat < $1.beat }
                        selectedPointIndex = nearestTempoPointIndex(beat: beat, bpm: bpm)
                        enabled = true
                        app.rebuildTempoMap()
                    }
            )
        }
    }

    private var effectivePoints: [TempoPoint] {
        points.isEmpty ? [TempoPoint(beat: 0, bpm: baseTempo), TempoPoint(beat: lengthBeats, bpm: baseTempo)] : points.sorted { $0.beat < $1.beat }
    }

    private var editablePointIndices: [Int] {
        points.indices.sorted { points[$0].beat < points[$1].beat }
    }

    private func tempoPointIndex(near loc: CGPoint, width w: CGFloat, height h: CGFloat) -> Int? {
        let hitRadius: CGFloat = 10
        return editablePointIndices.first { idx in
            let p = points[idx]
            let x = CGFloat(p.beat / max(lengthBeats, 1)) * w
            let norm = (max(min(p.bpm, maxBPM), minBPM) - minBPM) / (maxBPM - minBPM)
            let y = h - CGFloat(norm) * h
            let dx = x - loc.x
            let dy = y - loc.y
            return (dx * dx + dy * dy).squareRoot() <= hitRadius
        }
    }

    private func updateTempoPoint(at idx: Int, beat: Double, bpm: Double, sortNow: Bool) {
        guard points.indices.contains(idx) else { return }
        points[idx].beat = max(0, min(lengthBeats, beat))
        points[idx].bpm = max(minBPM, min(maxBPM, bpm))
        if sortNow { points.sort { $0.beat < $1.beat } }
    }

    private func deleteTempoPoint(at idx: Int) {
        guard points.indices.contains(idx) else { return }
        points.remove(at: idx)
        selectedPointIndex = nil
        app.rebuildTempoMap()
    }

    private func nearestTempoPointIndex(beat: Double, bpm: Double) -> Int? {
        guard !points.isEmpty else { return nil }
        return points.indices.min { a, b in
            let da = abs(points[a].beat - beat) + abs(points[a].bpm - bpm) / 20.0
            let db = abs(points[b].beat - beat) + abs(points[b].bpm - bpm) / 20.0
            return da < db
        }
    }

    private func beatGrid(width w: CGFloat, height h: CGFloat) -> Path {
        Path { path in
            let bars = max(1, Int(lengthBeats / Double(max(app.project.beatsPerBar, 1))))
            for bar in 0...bars {
                let beat = Double(bar * app.project.beatsPerBar)
                let x = CGFloat(beat / max(lengthBeats, 1)) * w
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: h))
            }
        }
    }
}

// MARK: - Track lanes

private struct LaneRow: View {
    @Environment(AppState.self) private var app
    let track: Track
    @Bindable var lane: AutomationLane

    private var param: ParamInfo? {
        if lane.paramID == AutomationSpecialParam.deviceOn { return ParamInfo(AutomationSpecialParam.deviceOn, "Device On", 0, 1) }
        let node = app.engine.liveNode(track: track, nodeID: lane.nodeID)
            ?? track.devices.first { $0.nodeID == lane.nodeID }.map { DeviceFactory.make($0.kind) }
        return node?.automatableParams.first { $0.id == lane.paramID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: $lane.enabled).toggleStyle(.switch).controlSize(.mini)
                Text(laneTitle).font(.system(size: 12, weight: .medium))
                if lane.paramID == AutomationSpecialParam.deviceOn {
                    Text("0 = Off, 1 = On")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { lane.points.removeAll() } label: { Image(systemName: "eraser") }.buttonStyle(.plain)
                Button { track.automationLanes.removeAll { $0.id == lane.id } } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if let p = param {
                LaneCanvas(track: track, lane: lane, param: p, lengthBeats: app.project.lengthBeats, projectTempo: app.project.tempo)
                    .frame(height: 104)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(lane.enabled ? 1 : 0.55)
    }

    private var laneTitle: String {
        let nodeLabel = lane.nodeID == "instrument" ? track.kind.rawValue
            : (track.devices.first { $0.nodeID == lane.nodeID }?.kind.rawValue ?? "Device")
        return "\(nodeLabel) · \(param?.name ?? lane.paramID)"
    }
}

private struct LaneCanvas: View {
    let track: Track
    @Bindable var lane: AutomationLane
    let param: ParamInfo
    let lengthBeats: Double
    let projectTempo: Double
    @State private var selectedPointIndex: Int?
    @State private var activeDragPointIndex: Int?
    @State private var dragMoved = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.15))
                ArrangementContextOverlay(tracks: [track], lengthBeats: lengthBeats, projectTempo: projectTempo)
                    .opacity(0.48)
                    .allowsHitTesting(false)
                grid(width: w, height: h).stroke(Color.white.opacity(0.10), lineWidth: 1)
                // curve
                Path { path in
                    let pts = lane.points
                    guard !pts.isEmpty else { return }
                    func point(_ p: AutomationPoint) -> CGPoint {
                        let x = CGFloat(p.beat / max(lengthBeats, 1)) * w
                        let y = h - CGFloat(param.normalize(p.value)) * h
                        return CGPoint(x: x, y: y)
                    }
                    path.move(to: point(pts[0]))
                    for p in pts.dropFirst() { path.addLine(to: point(p)) }
                }
                .stroke(Color.accentColor, lineWidth: 2.25)
                // dots
                ForEach(Swift.Array(0..<lane.points.count), id: \.self) { pointIndex in
                    let p = lane.points[pointIndex]
                    let x = CGFloat(p.beat / max(lengthBeats, 1)) * w
                    let y = h - CGFloat(param.normalize(p.value)) * h
                    Circle()
                        .fill(selectedPointIndex == pointIndex ? Color.white : Color.accentColor)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: selectedPointIndex == pointIndex ? 2 : 0))
                        .frame(width: selectedPointIndex == pointIndex ? 11 : 8, height: selectedPointIndex == pointIndex ? 11 : 8)
                        .position(x: x, y: y)
                        .contentShape(Rectangle())
                        .help("Click to select. Drag to move. Right-click to delete.")
                        .contextMenu {
                            Button("Delete Automation Point", role: .destructive) {
                                deleteAutomationPoint(at: pointIndex)
                            }
                        }
                }
            }
            .coordinateSpace(name: "trackAutomationCanvas")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("trackAutomationCanvas"))
                    .onChanged { value in
                        if activeDragPointIndex == nil && !dragMoved {
                            activeDragPointIndex = automationPointIndex(near: value.startLocation, width: w, height: h)
                        }
                        guard let idx = activeDragPointIndex else { return }
                        let distance = dragDistance(from: value.startLocation, to: value.location)
                        guard distance >= 4 else { return }
                        dragMoved = true
                        selectedPointIndex = idx
                        updateAutomationPoint(at: idx, location: value.location, width: w, height: h, sortNow: false)
                    }
                    .onEnded { value in
                        defer {
                            activeDragPointIndex = nil
                            dragMoved = false
                        }
                        if let idx = activeDragPointIndex, dragMoved {
                            let edited = automationPoint(for: value.location, width: w, height: h)
                            updateAutomationPoint(at: idx, location: value.location, width: w, height: h, sortNow: true)
                            selectedPointIndex = nearestAutomationPointIndex(beat: edited.beat, value: edited.value)
                            return
                        }
                        if let existing = automationPointIndex(near: value.location, width: w, height: h) {
                            selectedPointIndex = existing
                            return
                        }
                        let newPoint = automationPoint(for: value.location, width: w, height: h)
                        lane.addPoint(beat: newPoint.beat, value: newPoint.value)
                        selectedPointIndex = nearestAutomationPointIndex(beat: newPoint.beat, value: newPoint.value)
                    }
            )
        }
    }

    private func automationPointIndex(near loc: CGPoint, width w: CGFloat, height h: CGFloat) -> Int? {
        let hitRadius: CGFloat = 10
        return lane.points.indices.first { idx in
            let p = lane.points[idx]
            let x = CGFloat(p.beat / max(lengthBeats, 1)) * w
            let y = h - CGFloat(param.normalize(p.value)) * h
            let dx = x - loc.x
            let dy = y - loc.y
            return (dx * dx + dy * dy).squareRoot() <= hitRadius
        }
    }

    private func automationPoint(for loc: CGPoint, width w: CGFloat, height h: CGFloat) -> AutomationPoint {
        let beat = Double(loc.x / max(w, 1)) * max(lengthBeats, 1)
        let norm = Double(1 - loc.y / max(h, 1))
        var value = param.denormalize(min(max(norm, 0), 1))
        if lane.paramID == AutomationSpecialParam.deviceOn {
            value = value >= 0.5 ? 1 : 0
        }
        return AutomationPoint(beat: max(0, min(lengthBeats, beat)), value: max(param.min, min(param.max, value)))
    }

    private func updateAutomationPoint(at idx: Int, location: CGPoint, width w: CGFloat, height h: CGFloat, sortNow: Bool) {
        guard lane.points.indices.contains(idx) else { return }
        lane.points[idx] = automationPoint(for: location, width: w, height: h)
        if sortNow { lane.points.sort { $0.beat < $1.beat } }
    }

    private func deleteAutomationPoint(at idx: Int) {
        guard lane.points.indices.contains(idx) else { return }
        lane.points.remove(at: idx)
        selectedPointIndex = nil
    }

    private func nearestAutomationPointIndex(beat: Double, value: Double) -> Int? {
        guard !lane.points.isEmpty else { return nil }
        return lane.points.indices.min { a, b in
            let da = abs(lane.points[a].beat - beat) + abs(param.normalize(lane.points[a].value) - param.normalize(value))
            let db = abs(lane.points[b].beat - beat) + abs(param.normalize(lane.points[b].value) - param.normalize(value))
            return da < db
        }
    }

    private func grid(width w: CGFloat, height h: CGFloat) -> Path {
        Path { path in
            let bars = max(1, Int(lengthBeats / 4.0))
            for bar in 0...bars {
                let x = CGFloat(Double(bar * 4) / max(lengthBeats, 1)) * w
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: h))
            }
            path.move(to: CGPoint(x: 0, y: h / 2)); path.addLine(to: CGPoint(x: w, y: h / 2))
        }
    }
}

private func dragDistance(from start: CGPoint, to end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    return (dx * dx + dy * dy).squareRoot()
}

private struct ArrangementContextOverlay: View {
    let tracks: [Track]
    let lengthBeats: Double
    let projectTempo: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach(tracks) { track in
                    audioContext(track: track, width: w, height: h)
                    midiContext(track: track, width: w, height: h)
                }
            }
        }
    }

    private func audioContext(track: Track, width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(track.audioClips) { clip in
                let startX = CGFloat(clip.startBeat / max(lengthBeats, 1)) * w
                let clipBeats = clip.arrangementLengthBeats(projectTempo: projectTempo)
                let clipW = max(CGFloat(clipBeats / max(lengthBeats, 1)) * w, 1)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: clipW, height: h * 0.86)
                    .offset(x: startX, y: h * 0.07)
                waveformPath(clip: clip, width: clipW, height: h * 0.74)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    .frame(width: clipW, height: h * 0.74)
                    .offset(x: startX, y: h * 0.13)
            }
        }
    }

    private func midiContext(track: Track, width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(track.clips) { clip in
                let startX = CGFloat(clip.startBeat / max(lengthBeats, 1)) * w
                let clipW = max(CGFloat(clip.lengthBeats / max(lengthBeats, 1)) * w, 1)
                RoundedRectangle(cornerRadius: 4)
                    .fill(track.color.opacity(0.20))
                    .frame(width: clipW, height: h * 0.86)
                    .offset(x: startX, y: h * 0.07)
                ForEach(clip.notes) { note in
                    let nx = startX + CGFloat(note.start / max(lengthBeats, 1)) * w
                    let nw = max(CGFloat(note.length / max(lengthBeats, 1)) * w, 1.5)
                    let ny = h * (0.18 + CGFloat(1.0 - Double(note.pitch - 24) / 84.0) * 0.60)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.38))
                        .frame(width: nw, height: 3)
                        .offset(x: nx, y: max(4, min(h - 7, ny)))
                }
            }
        }
    }

    private func waveformPath(clip: AudioClip, width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let samples = clip.activeSamples
            guard !samples.isEmpty, width > 1, height > 1 else { return }
            let columns = max(1, Int(width.rounded(.up)))
            let stride = max(1, samples.count / columns)
            let center = height / 2
            let amp = height * 0.46
            var x: CGFloat = 0
            var i = 0
            while i < samples.count && x <= width {
                let end = min(samples.count, i + stride)
                var peak: Float = 0
                var j = i
                while j < end { peak = max(peak, abs(samples[j])); j += 1 }
                let y = CGFloat(min(1, peak)) * amp
                path.move(to: CGPoint(x: x, y: center - y))
                path.addLine(to: CGPoint(x: x, y: center + y))
                i += stride
                x += 1
            }
        }
    }
}
