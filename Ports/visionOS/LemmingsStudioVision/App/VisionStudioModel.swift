import Foundation
import Observation

@MainActor
@Observable
final class VisionStudioModel {
    enum PrimaryWorkspace: String, CaseIterable, Identifiable {
        case arrangement = "Arrangement"
        case pianoRoll = "Piano Roll"
        case stepSequencer = "Step Sequencer"
        case mixer = "Mixer"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .arrangement: return "rectangle.3.group"
            case .pianoRoll: return "pianokeys"
            case .stepSequencer: return "square.grid.4x3.fill"
            case .mixer: return "slider.horizontal.3"
            }
        }
    }

    enum SnapDivision: String, CaseIterable, Identifiable {
        case bar = "1 Bar"
        case quarter = "1/4"
        case eighth = "1/8"
        case sixteenth = "1/16"
        case thirtySecond = "1/32"
        case off = "Off"

        var id: String { rawValue }

        func beats(beatsPerBar: Int) -> Double? {
            switch self {
            case .bar: return Double(max(1, beatsPerBar))
            case .quarter: return 1
            case .eighth: return 0.5
            case .sixteenth: return 0.25
            case .thirtySecond: return 0.125
            case .off: return nil
            }
        }
    }

    var project: LemmingsProject = .empty
    var currentProjectURL: URL?
    var isPlaying = false
    var playheadBeat: Double = 0
    var metronomeEnabled: Bool = false
    private var lastTransportMetronomeBeatIndex: Int?
    var activePrimaryWorkspace: PrimaryWorkspace = .arrangement {
        didSet {
            if activePrimaryWorkspace != .stepSequencer { activeSequencerStep = nil }
        }
    }
    var selectedClipID: UUID?
    var selectedTrackID: UUID?
    var horizontalZoom: Double = 90
    var verticalZoom: Double = 1
    var snapDivision: SnapDivision = .sixteenth
    var statusMessage = "Ready"
    var hasCompletedStartupBranding = false
    var showImporter = false
    var showProjectExporter = false
    var recentProjects: [VisionRecentProject] = []
    var lastAutosaveDate: Date?
    var recoveryProjectAvailable = false
    private var autosaveTask: Task<Void, Never>?
    var bridgeStatus: DesktopBridgeStatus = .offline
    var visualTheme: VisionVisualTheme = VisionVisualTheme(rawValue: UserDefaults.standard.string(forKey: "visionVisualTheme") ?? "") ?? .liquidGlass
    var selectedInstrument: VisionAudioEngine.InstrumentKind = .oscillatron
    var lowEQ: Double = 0
    var midEQ: Double = 0
    var highEQ: Double = 0
    var delayMix: Double = 0
    var reverbMix: Double = 10
    var isRecordingAudio = false
    var isRecordingMIDI = false
    var midiRecordingStatus = "MIDI ready"
    var activeMIDINoteStarts: [UInt8: Double] = [:]
    var recordingStatus = "Ready to record"
    var audioEngineRunning = false
    var midiSourceSummary = "None"
    var spatialSelectedObjectID: UUID?
    var spatialUndoStack: [VisionSpatialUndoRecord] = []
    var spatialRedoStack: [VisionSpatialUndoRecord] = []
    var agentPrompt = "Make my selected clip feel wider and cleaner."
    var agentStatus = "Agent idle"
    var selectedAgentProvider: VisionAgentProviderKind = .claude
    var claudeAPIKeyDraft = ""
    var claudeModel = "claude-sonnet-4-5"
    var claudeMaxTokens = 2048
    var selectedMLXModel: VisionMLXModelPreset = .qwen25VL7B4Bit
    var lastAgentPlan: VisionAgentToolPlan?
    var spliceMCP = VisionSpliceMCPStatus()
    var spliceSearchQuery = "future rave bass"
    var spliceSearchResults: [VisionSpliceSampleCandidate] = []
    var selectedSpliceSampleID: String?
    var compatibilityLab = VisionCompatibilityLabState()
    var companionParity = VisionCompanionPluginParityState()
    var automationParity = VisionAutomationParityState()
    var bounceParity = VisionBounceParityState()
    var nativeExport = VisionNativeExportState()
    var mlxRuntime = VisionMLXRuntimeState()
    var virtualKeyboard = VisionVirtualMIDIKeyboardState()
    var sampleBrowserItems: [VisionSampleBrowserItem] = []
    var bluetoothMIDIDevices: [VisionMIDIDeviceSummary] = []
    var activeTakeFolderID: UUID?
    var recordingCountdownSeconds: Int?
    var isArmedForPunch = false
    var recordingStartBeat: Double?
    var selectedCompRegionID: UUID?

    private let transport = VisionTransportEngine()
    let audioEngine = VisionAudioEngine()
    let audioUnitHost: VisionAudioUnitHost
    let desktopBridge = VisionDesktopBridgeClient()
    private let audioRecorder = VisionAudioRecorder()
    private let recordingCompEngine = VisionRecordingCompEngine()
    private var punchStopTask: Task<Void, Never>?
    var mlxLoadTask: Task<Void, Never>?
    var mlxGenerationTask: Task<Void, Never>?
    let midiManager = VisionMIDIManager()
    private var activeProjectNotes: Set<UUID> = []
    var activeSequencerStep: Int? = nil

    init() {
        audioUnitHost = VisionAudioUnitHost(audioEngine: audioEngine)
        audioEngineRunning = false
        midiManager.onNoteOn = { [weak self] note, velocity in
            guard let self else { return }
            self.performMIDINoteOn(note: note, velocity: velocity)
            self.virtualKeyboard.lastEventSummary = "External note on \(note) velocity \(velocity)"
        }
        midiManager.onNoteOff = { [weak self] note in
            guard let self else { return }
            self.performMIDINoteOff(note: note)
            self.virtualKeyboard.activeNotes.remove(note)
            self.virtualKeyboard.lastEventSummary = "External note off \(note)"
        }
        midiManager.onCC = { [weak self] cc, value in
            guard let self else { return }
            if cc == 1 { self.audioEngine.setReverbMix(Float(Double(value) / 127.0 * 45.0)) }
            self.audioUnitHost.sendCC(cc, value: value)
            self.desktopBridge.sendMIDI(status: 0xB0, data1: cc, data2: value)
        }
        midiManager.onPitchBend = { [weak self] value in
            let lsb = UInt8(value & 0x7F)
            let msb = UInt8((value >> 7) & 0x7F)
            self?.audioUnitHost.sendPitchBend(lsb: lsb, msb: msb)
            self?.desktopBridge.sendMIDI(status: 0xE0, data1: lsb, data2: msb)
        }
        midiManager.start()
        desktopBridge.startDiscovery()
        bridgeStatus = desktopBridge.status
        midiSourceSummary = midiManager.sourceNames.isEmpty ? "None" : midiManager.sourceNames.joined(separator: ", ")
        bluetoothMIDIDevices = midiManager.deviceSummaries
        refreshBundledMLXModelState()
        loadRecentProjects()
        refreshRecoveryAvailability()
        startAutosaveLoop()
    }

    isolated deinit {
        autosaveTask?.cancel()
    }

    private func refreshBundledMLXModelState() {
        guard let resourceRoot = Bundle.main.resourceURL else { return }
        let modelsRoot = resourceRoot.appendingPathComponent("Models", isDirectory: true)
        for index in mlxRuntime.modelInstalls.indices {
            guard let directoryName = mlxRuntime.modelInstalls[index].preset.bundledDirectoryName else { continue }
            let directory = modelsRoot.appendingPathComponent(directoryName, isDirectory: true)
            let config = directory.appendingPathComponent("config.json")
            if FileManager.default.fileExists(atPath: config.path) {
                mlxRuntime.modelInstalls[index].isInstalled = true
                mlxRuntime.modelInstalls[index].localCachePath = directory.path
            }
        }
    }


    func completeStartupBranding() {
        hasCompletedStartupBranding = true
    }

    func replayStartupBranding() {
        hasCompletedStartupBranding = false
    }

    func ensureMixerDefaults() {
        if project.returnBuses == nil || project.returnBuses?.isEmpty == true { project.returnBuses = VisionReturnBus.defaults }
        if project.masterVolume == nil { project.masterVolume = 1 }
        if project.masterMuted == nil { project.masterMuted = false }
        for index in project.tracks.indices {
            if project.tracks[index].sends == nil { project.tracks[index].sends = [:] }
            if project.tracks[index].outputBusId == nil { project.tracks[index].outputBusId = "master" }
            if project.tracks[index].volume == nil { project.tracks[index].volume = 1 }
            if project.tracks[index].pan == nil { project.tracks[index].pan = 0 }
            if project.tracks[index].mute == nil { project.tracks[index].mute = false }
            if project.tracks[index].solo == nil { project.tracks[index].solo = false }
        }
        audioEngine.configureReturns(project.returnBuses ?? VisionReturnBus.defaults)
        audioEngine.setMasterVolume((project.masterMuted == true) ? 0 : (project.masterVolume ?? 1))
    }

    func setTrackVolume(index: Int, value: Float) {
        guard project.tracks.indices.contains(index) else { return }
        project.tracks[index].volume = value
        audioEngine.updateTrackMixer(index: index, volume: value, pan: project.tracks[index].pan ?? 0, muted: project.tracks[index].mute == true)
    }

    func setTrackPan(index: Int, value: Float) {
        guard project.tracks.indices.contains(index) else { return }
        project.tracks[index].pan = value
        audioEngine.updateTrackMixer(index: index, volume: project.tracks[index].volume ?? 1, pan: value, muted: project.tracks[index].mute == true)
    }

    func toggleTrackMute(index: Int) {
        guard project.tracks.indices.contains(index) else { return }
        project.tracks[index].mute = !(project.tracks[index].mute ?? false)
        audioEngine.updateTrackMixer(index: index, volume: project.tracks[index].volume ?? 1, pan: project.tracks[index].pan ?? 0, muted: project.tracks[index].mute == true)
    }

    func toggleTrackSolo(index: Int) {
        guard project.tracks.indices.contains(index) else { return }
        project.tracks[index].solo = !(project.tracks[index].solo ?? false)
        if isPlaying { let beat = playheadBeat; pause(); seek(to: beat); play() }
    }

    func setTrackSend(index: Int, busID: String, value: Float) {
        guard project.tracks.indices.contains(index) else { return }
        var sends = project.tracks[index].sends ?? [:]
        sends[busID] = value
        project.tracks[index].sends = sends
        audioEngine.updateTrackSend(index: index, busID: busID, value: value)
    }

    func setTrackOutput(index: Int, busID: String) {
        guard project.tracks.indices.contains(index) else { return }
        project.tracks[index].outputBusId = busID
        if isPlaying { let beat = playheadBeat; pause(); seek(to: beat); play() }
    }

    func updateReturnBus(_ bus: VisionReturnBus) {
        ensureMixerDefaults()
        guard let index = project.returnBuses?.firstIndex(where: { $0.id == bus.id }) else { return }
        project.returnBuses?[index] = bus
        audioEngine.configureReturns(project.returnBuses ?? VisionReturnBus.defaults)
    }

    func setMasterVolume(_ value: Float) { project.masterVolume = value; audioEngine.setMasterVolume(project.masterMuted == true ? 0 : value) }
    func toggleMasterMute() { project.masterMuted = !(project.masterMuted ?? false); audioEngine.setMasterVolume(project.masterMuted == true ? 0 : (project.masterVolume ?? 1)) }
    func meterSnapshot(_ key: String) -> (peak: Float, rms: Float) { audioEngine.meterSnapshot(key: key) }

    func setBridgeReturnVolume(_ value: Float) { desktopBridge.setAudioReturnVolume(value) }

    var selectedClipSummary: SelectedClipSummary? {
        for track in project.tracks {
            if let clip = track.clips.first(where: { $0.id == selectedClipID }) {
                return .init(id: clip.id, trackName: track.name, name: clip.name, startBeat: clip.startBeat, lengthBeats: clip.lengthBeats, kind: "MIDI")
            }
            if let clip = track.audioClips.first(where: { $0.id == selectedClipID }) {
                return .init(id: clip.id, trackName: track.name, name: clip.name, startBeat: clip.startBeat, lengthBeats: clip.lengthBeats, kind: "Audio")
            }
        }
        return nil
    }

    func newProject() {
        stop()
        audioUnitHost.unload()
        project = .empty
        ensureMixerDefaults()
        syncTrackStockFXRacksToAudioEngine()
        currentProjectURL = nil
        selectedClipID = nil
        selectedTrackID = project.tracks.first?.id
        playheadBeat = 0
        spatialSelectedObjectID = nil
        spatialUndoStack.removeAll()
        spatialRedoStack.removeAll()
        ensureSpatialScene()
        ensureProjectMemory()
        addSessionMemorySnapshot()
        rebuildSemanticGraph()
        restoreAutomationFromProject()
        statusMessage = "New project"
    }

    func prepareSaveAs() {
        captureAudioUnitState()
        compactProjectMemory()
        persistAutomationIntoProject()
        project.semanticGraph = VisionSemanticProjectGraphBuilder.build(from: project, compatibility: compatibilityLab)
        showProjectExporter = true
    }

    func projectDocumentForExport() -> VisionProjectPackageDocument {
        VisionProjectPackageDocument(project: project, sourceURL: currentProjectURL)
    }

    func completeSaveAs(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            openProject(at: url)
            statusMessage = "Saved As \(url.lastPathComponent)"
        case .failure(let error):
            statusMessage = "Save As failed: \(error.localizedDescription)"
        }
    }

    func openProject(at url: URL) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            audioUnitHost.unload()
            project = try VisionProjectPersistence.loadProject(at: url)
            ensureMixerDefaults()
            syncTrackStockFXRacksToAudioEngine()
            currentProjectURL = url
            addRecentProject(url)
            selectedClipID = nil
            selectedTrackID = project.tracks.first?.id
            playheadBeat = 0
            statusMessage = "Opened \(url.lastPathComponent)"
            audioUnitHost.scan()
            ensureSpatialScene()
            ensureProjectMemory()
            addMemoryEvent(kind: .session, title: "Opened project", detail: "Opened from \(url.lastPathComponent).", tags: ["open", "session"])
            if project.semanticGraph == nil { rebuildSemanticGraph() }
            restoreAutomationFromProject()
            if let saved = project.visionHostedAudioUnit {
                Task { await audioUnitHost.restore(saved) }
            }
        } catch {
            statusMessage = "Open failed: \(error.localizedDescription)"
        }
    }

    func saveProject() {
        guard let url = currentProjectURL else {
            prepareSaveAs()
            return
        }
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            statusMessage = "Legacy project imported — use Save As to create a .lemmingsproject package"
            prepareSaveAs()
            return
        }
        captureAudioUnitState()
        compactProjectMemory()
        persistAutomationIntoProject()
        project.semanticGraph = VisionSemanticProjectGraphBuilder.build(from: project, compatibility: compatibilityLab)
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            try VisionProjectPersistence.writePackage(project: project, to: url, sourceURL: currentProjectURL)
            addRecentProject(url)
            statusMessage = "Saved \(url.lastPathComponent)"
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func openRecentProject(_ recent: VisionRecentProject) {
        guard FileManager.default.fileExists(atPath: recent.path) else {
            recentProjects.removeAll { $0.id == recent.id }
            persistRecentProjects()
            statusMessage = "Recent project is no longer available"
            return
        }
        openProject(at: recent.url)
    }

    func recoverAutosave() {
        do {
            let url = try VisionProjectPersistence.recoveryURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                statusMessage = "No recovery project is available"
                return
            }
            project = try VisionProjectPersistence.loadProject(at: url)
            currentProjectURL = nil
            selectedClipID = nil
            selectedTrackID = project.tracks.first?.id
            playheadBeat = 0
            ensureMixerDefaults()
            syncTrackStockFXRacksToAudioEngine()
            ensureSpatialScene()
            ensureProjectMemory()
            restoreAutomationFromProject()
            rebuildSemanticGraph()
            statusMessage = "Recovered autosave — use Save As to keep it"
        } catch {
            statusMessage = "Recovery failed: \(error.localizedDescription)"
        }
    }

    private func startAutosaveLoop() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { break }
                self?.performAutosave()
            }
        }
    }

    private func performAutosave() {
        do {
            let url = try VisionProjectPersistence.recoveryURL()
            try VisionProjectPersistence.writePackage(project: project, to: url, sourceURL: currentProjectURL)
            lastAutosaveDate = Date()
            recoveryProjectAvailable = true
        } catch {
            statusMessage = "Autosave warning: \(error.localizedDescription)"
        }
    }

    private func refreshRecoveryAvailability() {
        recoveryProjectAvailable = ((try? VisionProjectPersistence.recoveryURL()).map {
            FileManager.default.fileExists(atPath: $0.path)
        }) ?? false
    }

    private func loadRecentProjects() {
        guard let data = UserDefaults.standard.data(forKey: "visionRecentProjects"),
              let decoded = try? JSONDecoder().decode([VisionRecentProject].self, from: data) else {
            recentProjects = []
            return
        }
        recentProjects = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func addRecentProject(_ url: URL) {
        let entry = VisionRecentProject(path: url.path, displayName: url.deletingPathExtension().lastPathComponent, lastOpened: Date())
        recentProjects.removeAll { $0.path == url.path }
        recentProjects.insert(entry, at: 0)
        recentProjects = Array(recentProjects.prefix(8))
        persistRecentProjects()
    }

    private func persistRecentProjects() {
        if let data = try? JSONEncoder().encode(recentProjects) {
            UserDefaults.standard.set(data, forKey: "visionRecentProjects")
        }
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        if !audioEngineRunning {
            do {
                try audioEngine.start()
                audioEngineRunning = true
            } catch {
                audioEngineRunning = false
                statusMessage = "Audio unavailable: \(error.localizedDescription)"
                return
            }
        }
        isPlaying = true
        lastTransportMetronomeBeatIndex = nil
        audioEngine.configureMetronome(
            enabled: false,
            tempo: project.effectiveTempo,
            beatsPerBar: project.beatsPerBar,
            fromBeat: playheadBeat
        )
        audioEngine.scheduleProjectAudio(project: project, projectURL: currentProjectURL, fromBeat: playheadBeat)
        transport.start(tempo: project.effectiveTempo, fromBeat: playheadBeat) { [weak self] beat in
            Task { @MainActor in
                guard let self else { return }
                self.playheadBeat = beat
                self.applyAutomation(at: beat)
                self.syncProjectNotes(at: beat)
                self.syncTransportMetronome(at: beat)
                self.syncSequencer(at: beat)
                self.syncExpressiveMIDI(at: beat)
                self.syncPunchRecording(at: beat)
            }
        }
    }

    func pause() {
        isPlaying = false
        transport.pause()
        audioEngine.stopProjectAudio()
        lastTransportMetronomeBeatIndex = nil
        audioEngine.configureMetronome(enabled: false, tempo: project.effectiveTempo, beatsPerBar: project.beatsPerBar, fromBeat: playheadBeat)
        panic()
    }

    func stop() {
        isPlaying = false
        transport.stop()
        audioEngine.stopProjectAudio()
        lastTransportMetronomeBeatIndex = nil
        audioEngine.configureMetronome(enabled: false, tempo: project.effectiveTempo, beatsPerBar: project.beatsPerBar, fromBeat: 0)
        panic()
        playheadBeat = 0
    }

    func seek(to beat: Double) {
        playheadBeat = max(0, min(beat, project.totalBeats))
        transport.seek(to: playheadBeat)
    }

    func snapped(_ beat: Double) -> Double {
        guard let step = snapDivision.beats(beatsPerBar: project.beatsPerBar), step > 0 else {
            return max(0, beat)
        }
        return max(0, (beat / step).rounded() * step)
    }

    func moveClip(id: UUID, proposedStartBeat: Double) {
        let start = snapped(proposedStartBeat)
        let projectEnd = project.totalBeats
        mutateClip(id: id) { midi in
            midi.startBeat = min(start, max(0, projectEnd - midi.lengthBeats))
        } audio: { audio in
            audio.startBeat = min(start, max(0, projectEnd - audio.lengthBeats))
        }
    }

    func trimClipLeft(id: UUID, proposedStartBeat: Double) {
        let target = snapped(proposedStartBeat)
        mutateClip(id: id) { midi in
            let oldEnd = midi.startBeat + midi.lengthBeats
            let newStart = min(max(0, target), oldEnd - 0.125)
            let delta = newStart - midi.startBeat
            midi.startBeat = newStart
            midi.lengthBeats = oldEnd - newStart
            if delta > 0 {
                midi.notes = midi.notes?.compactMap { note in
                    let newRelative = note.startBeat - delta
                    guard newRelative + note.lengthBeats > 0 else { return nil }
                    var copy = note
                    copy.startBeat = max(0, newRelative)
                    if newRelative < 0 { copy.lengthBeats = max(0.05, note.lengthBeats + newRelative) }
                    return copy
                }
            }
        } audio: { audio in
            let oldEnd = audio.startBeat + audio.lengthBeats
            let newStart = min(max(0, target), oldEnd - 0.125)
            let delta = newStart - audio.startBeat
            audio.startBeat = newStart
            audio.lengthBeats = oldEnd - newStart
            audio.sourceOffsetBeats = (audio.sourceOffsetBeats ?? 0) + max(0, delta)
        }
    }

    func trimClipRight(id: UUID, proposedEndBeat: Double) {
        let end = snapped(proposedEndBeat)
        let projectEnd = project.totalBeats
        mutateClip(id: id) { midi in
            if midi.loopLengthBeats == nil || (midi.loopLengthBeats ?? 0) <= 0 {
                midi.loopLengthBeats = midi.lengthBeats
            }
            midi.lengthBeats = max(0.125, min(projectEnd, end) - midi.startBeat)
        } audio: { audio in
            audio.lengthBeats = max(0.125, min(projectEnd, end) - audio.startBeat)
        }
    }

    func splitSelectedClip(at beat: Double? = nil) {
        guard let id = selectedClipID else { return }
        let splitBeat = snapped(beat ?? playheadBeat)

        for trackIndex in project.tracks.indices {
            if let clipIndex = project.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                let original = project.tracks[trackIndex].clips[clipIndex]
                let relative = splitBeat - original.startBeat
                guard relative > 0.125, relative < original.lengthBeats - 0.125 else {
                    statusMessage = "Split point must be inside the selected clip"
                    return
                }
                var left = original
                var right = original
                left.id = UUID()
                right.id = UUID()
                left.lengthBeats = relative
                right.startBeat = splitBeat
                right.lengthBeats = original.lengthBeats - relative
                left.notes = original.notes?.compactMap { note in
                    guard note.startBeat < relative else { return nil }
                    var copy = note
                    copy.lengthBeats = min(note.lengthBeats, max(0.05, relative - note.startBeat))
                    return copy
                }
                right.notes = original.notes?.compactMap { note in
                    guard note.startBeat + note.lengthBeats > relative else { return nil }
                    var copy = note
                    copy.startBeat = max(0, note.startBeat - relative)
                    if note.startBeat < relative { copy.lengthBeats = max(0.05, note.startBeat + note.lengthBeats - relative) }
                    return copy
                }
                project.tracks[trackIndex].clips.remove(at: clipIndex)
                project.tracks[trackIndex].clips.insert(contentsOf: [left, right], at: clipIndex)
                selectedClipID = right.id
                statusMessage = "Split MIDI clip"
                return
            }

            if let clipIndex = project.tracks[trackIndex].audioClips.firstIndex(where: { $0.id == id }) {
                let original = project.tracks[trackIndex].audioClips[clipIndex]
                let relative = splitBeat - original.startBeat
                guard relative > 0.125, relative < original.lengthBeats - 0.125 else {
                    statusMessage = "Split point must be inside the selected clip"
                    return
                }
                var left = original
                var right = original
                left.id = UUID()
                right.id = UUID()
                left.lengthBeats = relative
                right.startBeat = splitBeat
                right.lengthBeats = original.lengthBeats - relative
                right.sourceOffsetBeats = (original.sourceOffsetBeats ?? 0) + relative
                project.tracks[trackIndex].audioClips.remove(at: clipIndex)
                project.tracks[trackIndex].audioClips.insert(contentsOf: [left, right], at: clipIndex)
                selectedClipID = right.id
                statusMessage = "Split audio clip"
                return
            }
        }
    }

    func duplicateSelectedClip() {
        guard let id = selectedClipID else { return }
        for trackIndex in project.tracks.indices {
            if let clip = project.tracks[trackIndex].clips.first(where: { $0.id == id }) {
                var copy = clip
                copy.id = UUID()
                copy.name += " Copy"
                copy.startBeat = snapped(clip.startBeat + clip.lengthBeats)
                project.tracks[trackIndex].clips.append(copy)
                selectedClipID = copy.id
                statusMessage = "Duplicated MIDI clip"
                return
            }
            if let clip = project.tracks[trackIndex].audioClips.first(where: { $0.id == id }) {
                var copy = clip
                copy.id = UUID()
                copy.name += " Copy"
                copy.startBeat = snapped(clip.startBeat + clip.lengthBeats)
                project.tracks[trackIndex].audioClips.append(copy)
                selectedClipID = copy.id
                statusMessage = "Duplicated audio clip"
                return
            }
        }
    }

    func deleteSelectedClip() {
        guard let id = selectedClipID else { return }
        for index in project.tracks.indices {
            project.tracks[index].clips.removeAll { $0.id == id }
            project.tracks[index].audioClips.removeAll { $0.id == id }
        }
        selectedClipID = nil
        statusMessage = "Deleted clip"
    }


    func importSampleCandidateToArrangement(_ sample: VisionSpliceSampleCandidate, targetTrackIndex: Int? = nil) {
        let trackIndex: Int
        if let targetTrackIndex, project.tracks.indices.contains(targetTrackIndex) {
            trackIndex = targetTrackIndex
        } else if let selected = selectedClipSummary,
                  let index = project.tracks.firstIndex(where: { track in
                      track.clips.contains(where: { $0.id == selected.id }) || track.audioClips.contains(where: { $0.id == selected.id })
                  }) {
            trackIndex = index
        } else if let firstAudio = project.tracks.firstIndex(where: { $0.kind.localizedCaseInsensitiveContains("audio") }) {
            trackIndex = firstAudio
        } else {
            project.tracks.append(VisionTrack(name: "Splice Samples", kind: "Audio", clips: [], audioClips: []))
            trackIndex = project.tracks.count - 1
        }

        let startBeat = snapped(playheadBeat)
        let length = max(0.25, min(project.totalBeats - startBeat, sample.lengthBeats))
        let sourceBPM = sample.bpm
        let stretch = spliceMCP.autoStretchEnabled && sourceBPM != nil
        let rate = stretch ? (project.effectiveTempo / max(1, sourceBPM ?? project.effectiveTempo)) : 1
        let adjustedLength = length
        let clip = VisionAudioClip(
            id: UUID(),
            name: sample.title,
            startBeat: startBeat,
            lengthBeats: min(project.totalBeats - startBeat, adjustedLength),
            sourcePath: sample.localFilePath ?? sample.remoteURI,
            sourceOffsetBeats: 0,
            sourceBPM: sourceBPM,
            sourceKey: sample.key,
            autoStretchEnabled: stretch,
            playbackRate: rate
        )
        project.tracks[trackIndex].audioClips.append(clip)
        selectedClipID = clip.id
        statusMessage = "Inserted Splice sample: \(sample.title)" + (stretch ? " • auto-fit \(Int(sourceBPM ?? 0))→\(Int(project.effectiveTempo)) BPM" : "")
    }

    func importSampleCandidateToStepSequencer(_ sample: VisionSpliceSampleCandidate, layerIndex: Int? = nil) {
        if project.stepSequencer == nil { project.stepSequencer = .defaultPattern }
        guard var sequencer = project.stepSequencer else { return }
        let index = layerIndex ?? sequencer.layers.firstIndex(where: { $0.sourcePath == nil }) ?? sequencer.layers.count
        let layer = VisionSequencerLayer(
            name: sample.title,
            midiNote: 36 + min(index, 47),
            sourcePath: sample.localFilePath ?? sample.remoteURI,
            volume: 0.9,
            pan: 0,
            hits: Array(repeating: false, count: max(16, sequencer.stepCount))
        )
        if sequencer.layers.indices.contains(index) {
            sequencer.layers[index] = layer
        } else {
            sequencer.layers.append(layer)
        }
        project.stepSequencer = sequencer
        statusMessage = "Mapped Splice sample to Step Sequencer: \(sample.title)"
    }


    func persistTheme() {
        UserDefaults.standard.set(visualTheme.rawValue, forKey: "visionVisualTheme")
    }

    func selectInstrument(_ kind: VisionAudioEngine.InstrumentKind) {
        selectedInstrument = kind
        audioEngine.setInstrument(kind)
        statusMessage = "Selected \(kind.rawValue)"
    }

    func previewNote(_ note: UInt8) {
        if !audioUnitHost.hasActiveInstrument { audioEngine.noteOn(note: note, velocity: 104) }
        audioUnitHost.sendNoteOn(note: note, velocity: 104)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self else { return }
            if !self.audioUnitHost.hasActiveInstrument { self.audioEngine.noteOff(note: note) }
            self.audioUnitHost.sendNoteOff(note: note)
        }
    }

    func panic() {
        audioEngine.panic()
        audioUnitHost.sendCC(123, value: 0)
        audioUnitHost.sendCC(120, value: 0)
        desktopBridge.sendMIDI(status: 0xB0, data1: 123, data2: 0)
        desktopBridge.sendMIDI(status: 0xB0, data1: 120, data2: 0)
        activeProjectNotes.removeAll()
        activeSequencerStep = nil
    }

    func setLowEQ(_ value: Double) { lowEQ = value; audioEngine.setLowGain(Float(value)) }
    func setMidEQ(_ value: Double) { midEQ = value; audioEngine.setMidGain(Float(value)) }
    func setHighEQ(_ value: Double) { highEQ = value; audioEngine.setHighGain(Float(value)) }
    func setDelayMix(_ value: Double) { delayMix = value; audioEngine.setDelayMix(Float(value)) }
    func setReverbMix(_ value: Double) { reverbMix = value; audioEngine.setReverbMix(Float(value)) }

    var recordingSettings: VisionRecordingSettings {
        get { project.recordingSettings ?? VisionRecordingSettings() }
        set { project.recordingSettings = newValue }
    }

    func updateRecordingSettings(_ mutate: (inout VisionRecordingSettings) -> Void) {
        var settings = recordingSettings
        mutate(&settings)
        settings.countInBars = max(0, settings.countInBars)
        settings.preRollBars = max(0, settings.preRollBars)
        settings.punchInBeat = max(0, settings.punchInBeat)
        settings.punchOutBeat = max(settings.punchInBeat + 0.125, settings.punchOutBeat)
        project.recordingSettings = settings
    }

    func toggleAudioRecording() {
        if isRecordingAudio || isArmedForPunch {
            stopAudioRecordingSession(reason: "Recording stopped")
            return
        }
        Task { await beginRecordingSession() }
    }

    func beginRecordingSession() async {
        let settings = recordingSettings
        let beatsPerBar = Double(max(1, project.beatsPerBar))
        let countInBeats = Double(settings.countInBars) * beatsPerBar
        let preRollBeats = Double(settings.preRollBars) * beatsPerBar
        let targetBeat = settings.punchEnabled ? settings.punchInBeat : playheadBeat
        let transportStart = max(0, targetBeat - preRollBeats - countInBeats)
        seek(to: transportStart)
        if !isPlaying { play() }

        if countInBeats > 0 {
            let seconds = Int(ceil(countInBeats * 60.0 / max(20, project.effectiveTempo)))
            recordingStatus = "Count-in…"
            for remaining in stride(from: seconds, through: 1, by: -1) {
                recordingCountdownSeconds = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            recordingCountdownSeconds = nil
        }

        if settings.punchEnabled {
            isArmedForPunch = true
            recordingStatus = "Armed: punch at beat \(String(format: "%.2f", settings.punchInBeat))"
            statusMessage = recordingStatus
        } else {
            startRecorderNow()
        }
    }

    private func startRecorderNow() {
        guard !isRecordingAudio else { return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LemmingsStudio/Recordings", isDirectory: true)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = folder.appendingPathComponent("VisionRecording-\(formatter.string(from: Date())).caf")
        do {
            try audioRecorder.start(using: audioEngine.inputNode, destination: destination)
            recordingStartBeat = playheadBeat
            isRecordingAudio = true
            isArmedForPunch = false
            recordingStatus = "Recording microphone input…"
            statusMessage = recordingStatus
        } catch {
            recordingStatus = "Record failed: \(error.localizedDescription)"
            statusMessage = recordingStatus
        }
    }

    private func syncPunchRecording(at beat: Double) {
        let settings = recordingSettings
        guard settings.punchEnabled else { return }
        if isArmedForPunch && beat >= settings.punchInBeat { startRecorderNow() }
        if isRecordingAudio && beat >= settings.punchOutBeat { stopAudioRecordingSession(reason: "Punch recording complete") }
    }

    private func stopAudioRecordingSession(reason: String) {
        isArmedForPunch = false
        recordingCountdownSeconds = nil
        guard isRecordingAudio else {
            recordingStatus = reason
            statusMessage = reason
            return
        }
        let url = audioRecorder.stop()
        isRecordingAudio = false
        if let url {
            appendRecordedTake(url, startBeat: recordingStartBeat ?? playheadBeat)
            recordingStatus = "Saved \(url.lastPathComponent) as a take"
        } else {
            recordingStatus = reason
        }
        recordingStartBeat = nil
        statusMessage = recordingStatus
    }

    func appendRecordedTake(_ url: URL, startBeat: Double = 0) {
        if project.takeFolders == nil { project.takeFolders = [] }
        let trackID = project.tracks.first?.id
        if let activeTakeFolderID, let index = project.takeFolders?.firstIndex(where: { $0.id == activeTakeFolderID }) {
            let take = VisionTake(name: "Take \(project.takeFolders![index].takes.count + 1)", sourcePath: url.path)
            project.takeFolders![index].takes.append(take)
            project.takeFolders![index].selectedTakeID = take.id
            if project.takeFolders![index].compRegions.isEmpty {
                let end = recordingSettings.punchEnabled ? recordingSettings.punchOutBeat : max(startBeat + 4, playheadBeat)
                project.takeFolders![index].compRegions = [VisionCompRegion(takeID: take.id, startBeat: startBeat, endBeat: end)]
            }
        } else {
            let take = VisionTake(name: "Take 1", sourcePath: url.path)
            let end = recordingSettings.punchEnabled ? recordingSettings.punchOutBeat : max(startBeat + 4, playheadBeat)
            let region = VisionCompRegion(takeID: take.id, startBeat: startBeat, endBeat: end)
            let folder = VisionTakeFolder(name: "Recording Takes", trackID: trackID, takes: [take], selectedTakeID: take.id, isComping: true, compRegions: [region])
            project.takeFolders?.append(folder)
            activeTakeFolderID = folder.id
        }
        addMemoryEvent(kind: .recordingDecision, title: "Recorded a take", detail: url.lastPathComponent, tags: ["recording", "take-folder"])
    }

    func selectCompTake(folderID: UUID, takeID: UUID) {
        guard let index = project.takeFolders?.firstIndex(where: { $0.id == folderID }) else { return }
        project.takeFolders?[index].selectedTakeID = takeID
        project.takeFolders?[index].isComping = true
        statusMessage = "Selected comp take"
    }

    func createTakeFolder() {
        if project.takeFolders == nil { project.takeFolders = [] }
        let folder = VisionTakeFolder(name: "Take Folder \((project.takeFolders?.count ?? 0) + 1)", trackID: project.tracks.first?.id, takes: [], selectedTakeID: nil, isComping: true)
        project.takeFolders?.append(folder)
        activeTakeFolderID = folder.id
        statusMessage = "Created \(folder.name)"
    }

    func addCompRegion(folderID: UUID, takeID: UUID, startBeat: Double, endBeat: Double) {
        guard let index = project.takeFolders?.firstIndex(where: { $0.id == folderID }) else { return }
        let region = VisionCompRegion(takeID: takeID, startBeat: snapped(startBeat), endBeat: max(snapped(startBeat) + 0.125, snapped(endBeat)))
        project.takeFolders?[index].compRegions.append(region)
        selectedCompRegionID = region.id
        statusMessage = "Added comp region"
    }

    func swipeCompRegion(folderID: UUID, regionID: UUID, toTakeID takeID: UUID) {
        guard let folderIndex = project.takeFolders?.firstIndex(where: { $0.id == folderID }),
              let regionIndex = project.takeFolders?[folderIndex].compRegions.firstIndex(where: { $0.id == regionID }) else { return }
        project.takeFolders?[folderIndex].compRegions[regionIndex].takeID = takeID
        project.takeFolders?[folderIndex].selectedTakeID = takeID
        addMemoryEvent(kind: .recordingDecision, title: "Swiped comp region", detail: "Changed region to another take", tags: ["recording", "comping"])
        statusMessage = "Comp region switched to selected take"
    }

    func cycleCompTake(folderID: UUID, regionID: UUID, direction: Int) {
        guard let folderIndex = project.takeFolders?.firstIndex(where: { $0.id == folderID }),
              let regionIndex = project.takeFolders?[folderIndex].compRegions.firstIndex(where: { $0.id == regionID }) else { return }
        let takes = project.takeFolders![folderIndex].takes
        guard !takes.isEmpty else { return }
        let currentID = project.takeFolders![folderIndex].compRegions[regionIndex].takeID
        let currentIndex = takes.firstIndex(where: { $0.id == currentID }) ?? 0
        let delta = direction >= 0 ? 1 : -1
        let next = (currentIndex + delta + takes.count) % takes.count
        swipeCompRegion(folderID: folderID, regionID: regionID, toTakeID: takes[next].id)
    }

    func splitCompRegion(folderID: UUID, regionID: UUID, at beat: Double) {
        guard let folderIndex = project.takeFolders?.firstIndex(where: { $0.id == folderID }),
              let regionIndex = project.takeFolders?[folderIndex].compRegions.firstIndex(where: { $0.id == regionID }) else { return }
        let region = project.takeFolders![folderIndex].compRegions[regionIndex]
        let split = snapped(beat)
        guard split > region.startBeat + 0.125, split < region.endBeat - 0.125 else { return }
        var left = region; left.id = UUID(); left.endBeat = split
        var right = region; right.id = UUID(); right.startBeat = split; right.sourceOffsetBeat += split - region.startBeat
        project.takeFolders?[folderIndex].compRegions.remove(at: regionIndex)
        project.takeFolders?[folderIndex].compRegions.insert(contentsOf: [left, right], at: regionIndex)
        selectedCompRegionID = right.id
        statusMessage = "Split comp region at beat \(String(format: "%.2f", split))"
    }

    func consolidateComp(folderID: UUID) {
        guard let folderIndex = project.takeFolders?.firstIndex(where: { $0.id == folderID }) else { return }
        let folder = project.takeFolders![folderIndex]
        let exportRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Exports/Comps", isDirectory: true)
        let safeName = folder.name.replacingOccurrences(of: "/", with: "-")
        let destination = exportRoot.appendingPathComponent("\(safeName)-Comp.wav")
        do {
            let url = try recordingCompEngine.consolidate(folder: folder, tempo: project.effectiveTempo, destination: destination)
            project.takeFolders?[folderIndex].consolidatedCompPath = url.path
            statusMessage = "Consolidated comp: \(url.lastPathComponent)"
            addMemoryEvent(kind: .recordingDecision, title: "Consolidated a comp", detail: url.lastPathComponent, tags: ["recording", "comp", "export"])
        } catch {
            statusMessage = "Comp consolidation failed: \(error.localizedDescription)"
        }
    }

    private func syncProjectNotes(at beat: Double) {
        var shouldBeActive = Set<UUID>()
        for (trackIndex, track) in project.tracks.enumerated() where track.mute != true {
            for clip in track.clips {
                let visibleLocalBeat = beat - clip.startBeat
                guard visibleLocalBeat >= 0, visibleLocalBeat <= clip.lengthBeats else { continue }
                let sourceLength = max(0.000_001, clip.loopLengthBeats ?? clip.lengthBeats)
                let localBeat = clip.lengthBeats > sourceLength
                    ? visibleLocalBeat.truncatingRemainder(dividingBy: sourceLength)
                    : visibleLocalBeat
                for note in clip.notes ?? [] {
                    if localBeat >= note.startBeat && localBeat < note.startBeat + note.lengthBeats {
                        shouldBeActive.insert(note.id)
                        if !activeProjectNotes.contains(note.id) {
                            let midi = UInt8(clamping: note.note)
                            let velocity = UInt8(clamping: note.velocity)
                            if !audioUnitHost.hasActiveInstrument && desktopBridge.activeInstanceID == nil {
                                if track.kind.lowercased().contains("drum") || track.name.hasPrefix("SEQ ·") {
                                    audioEngine.triggerSequencerVoice(note: midi, velocity: velocity, pan: track.pan ?? 0)
                                } else {
                                    audioEngine.noteOn(trackIndex: trackIndex, note: midi, velocity: velocity)
                                }
                            }
                            audioUnitHost.sendNoteOn(note: midi, velocity: velocity)
                            desktopBridge.sendMIDI(status: 0x90, data1: midi, data2: velocity)
                        }
                    }
                }
            }
        }
        let released = activeProjectNotes.subtracting(shouldBeActive)
        if !released.isEmpty {
            // Notes are keyed by runtime UUID, so find their MIDI numbers before releasing.
            for (trackIndex, track) in project.tracks.enumerated() {
                for clip in track.clips {
                    for note in clip.notes ?? [] where released.contains(note.id) {
                        let midi = UInt8(clamping: note.note)
                        if !audioUnitHost.hasActiveInstrument && desktopBridge.activeInstanceID == nil { audioEngine.noteOff(trackIndex: trackIndex, note: midi) }
                        audioUnitHost.sendNoteOff(note: midi)
                        desktopBridge.sendMIDI(status: 0x80, data1: midi, data2: 0)
                    }
                }
            }
        }
        activeProjectNotes = shouldBeActive
    }

    private func syncTransportMetronome(at beat: Double) {
        guard metronomeEnabled else {
            lastTransportMetronomeBeatIndex = nil
            return
        }
        let beatIndex = Int(floor(beat + 0.000_001))
        guard beatIndex != lastTransportMetronomeBeatIndex else { return }
        lastTransportMetronomeBeatIndex = beatIndex
        audioEngine.triggerMetronome(accent: beatIndex % max(1, project.beatsPerBar) == 0)
    }

    func setMetronomeEnabled(_ enabled: Bool) {
        metronomeEnabled = enabled
        lastTransportMetronomeBeatIndex = nil
        // Click events are dispatched from the same transport callback that drives sequencer hits.
        // The audio engine only synthesizes the click itself.
        audioEngine.configureMetronome(
            enabled: false,
            tempo: project.effectiveTempo,
            beatsPerBar: project.beatsPerBar,
            fromBeat: playheadBeat
        )
        statusMessage = enabled ? "Metronome on" : "Metronome off"
    }

    func setSelectedClipStart(_ startBeat: Double) {
        guard let id = selectedClipID else { return }
        moveClip(id: id, proposedStartBeat: startBeat)
    }

    func setSelectedClipLength(_ lengthBeats: Double) {
        guard let id = selectedClipID else { return }
        let projectEnd = project.totalBeats
        mutateClip(id: id) { midi in
            midi.lengthBeats = max(0.125, min(lengthBeats, projectEnd - midi.startBeat))
        } audio: { audio in
            audio.lengthBeats = max(0.125, min(lengthBeats, projectEnd - audio.startBeat))
        }
    }

    private func mutateClip(
        id: UUID,
        midi: (inout VisionMIDIClip) -> Void,
        audio: (inout VisionAudioClip) -> Void
    ) {
        for trackIndex in project.tracks.indices {
            if let clipIndex = project.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                midi(&project.tracks[trackIndex].clips[clipIndex])
                return
            }
            if let clipIndex = project.tracks[trackIndex].audioClips.firstIndex(where: { $0.id == id }) {
                audio(&project.tracks[trackIndex].audioClips[clipIndex])
                return
            }
        }
    }

    func scanAudioUnits() {
        audioUnitHost.scan()
    }

    func loadAudioUnit(_ descriptor: VisionAudioUnitDescriptor) async {
        await audioUnitHost.instantiate(descriptor)
        captureAudioUnitState()
        statusMessage = audioUnitHost.statusMessage
    }

    func unloadAudioUnit() {
        audioUnitHost.unload()
        project.visionHostedAudioUnit = nil
        statusMessage = "Audio Unit unloaded"
    }

    func captureAudioUnitState() {
        project.visionHostedAudioUnit = audioUnitHost.snapshotState()
        statusMessage = project.visionHostedAudioUnit == nil
            ? "Audio Unit exposed no document state"
            : "Audio Unit state captured in project model"
    }

    func setAudioUnitParameter(id: UInt64, value: Float) {
        audioUnitHost.setParameter(id: id, value: value)
        project.visionHostedAudioUnit = audioUnitHost.snapshotState()
    }

}

struct SelectedClipSummary: Sendable {
    let id: UUID
    let trackName: String
    let name: String
    let startBeat: Double
    let lengthBeats: Double
    let kind: String
}
