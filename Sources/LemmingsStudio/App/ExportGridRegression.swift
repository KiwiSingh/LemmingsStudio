import Foundation
import AVFoundation

private enum ExportGridRegressionState { static var started = false }

extension AppState {
    @MainActor func runExportGridRegression() {
        guard !ExportGridRegressionState.started else { return }
        ExportGridRegressionState.started = true
        guard let index = CommandLine.arguments.firstIndex(of: "--validate-export-grid"), CommandLine.arguments.count > index + 1 else { return }
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var report: [String: Any] = ["status": "running", "physical_audio_output": false]
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ExportError.renderFailed(message) }
        }
        func finish(_ error: Error? = nil) {
            report["status"] = error == nil ? "passed" : "failed"
            if let error { report["error"] = error.localizedDescription }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: output.appendingPathComponent("report.json"))
            }
            engine.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exit(error == nil ? 0 : 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            do {
                project = Project(); project.tempo = 100; project.lengthBars = 1; project.tracks = []
                engine.attach(project: project); engine.playbackScope = .arrangement
                for enabled in [false, true] {
                    engine.metronomeEnabled = enabled
                    let silence = try offline.renderStereo(project: project)
                    try require(!silence.l.isEmpty && silence.peak == 0, "Metronome leaked into offline render")
                    try require(engine.metronomeEnabled == enabled, "Metronome preference was not restored")
                    let url = output.appendingPathComponent("silent-click-\(enabled).wav")
                    try offline.export(project: project, to: url, format: .wav)
                    let file = try AVAudioFile(forReading: url)
                    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                    try file.read(into: buffer)
                    try require((0..<Int(buffer.frameLength)).allSatisfy { buffer.floatChannelData![0][$0] == 0 }, "Click printed into WAV")
                }
                report["metronome_never_exported_on_or_off"] = true
                snapToGridEnabled = true; gridSubdivisionBeats = 0.25; autoWarpImportedAudio = true
                let fixture = output.appendingPathComponent("incorrect-detection-80bpm.wav")
                let rate = engine.sampleRate
                try autoreleasepool {
                    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
                    let count = Int(rate * 2)
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                    buffer.frameLength = AVAudioFrameCount(count)
                    for i in 0..<count { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 220 / rate)) * 0.15 }
                    let file = try AVAudioFile(forWriting: fixture, settings: format.settings)
                    try file.write(from: buffer)
                }
                let track = Track(name: "Audio timing", kind: .audio, color: .blue)
                project.tracks = [track]; selectedTrackID = track.id; engine.attach(project: project)
                engine.transport.setBeat(0.13)
                try importAudioFile(fixture, targetTrack: track)
                let audio = track.audioClips[0]
                try require(audio.startBeat == 0.25, "Finder/audio import placement not snapped")
                try require(abs(audio.arrangementLengthBeats(projectTempo: project.tempo) / 0.25 - (audio.arrangementLengthBeats(projectTempo: project.tempo) / 0.25).rounded()) < 0.00001, "Audio import end not snapped")
                setClipTempo(audio, bpm: 120, enableWarp: true)
                setProjectTempo(100)
                try require(audio.arrangementLengthBeats(projectTempo: 100) == 4, "Manual BPM correction retained the wrongly detected region length")
                audio.startBeat = 0; audio.lengthBeatsOverride = 12
                try require(audio.manualTempoOverride && audio.originalTempo == 120 && project.tempo == 100, "Manual tempo reverted")
                try require(audio.loopLengthBeats == 4, "Manual source BPM did not update musical loop")
                try require(audio.activeSamples.count == Int((Double(audio.samples.count) * 1.2).rounded()), "Warp padding changed musical duration")
                for offset in [0.125, 1.25, 3.75] {
                    try require(abs(audio.playbackSampleIndex(beatOffset: offset, projectTempo: 100) - audio.playbackSampleIndex(beatOffset: offset + 4, projectTempo: 100)) <= 1, "Audio extension repeat drift")
                }
                audio.lengthBeatsOverride = 20
                try require(audio.loopLengthBeats == 4 && audio.originalTempo == 120, "Second extension replaced source loop/tempo")
                audio.lengthBeatsOverride = 12
                report["audio_import_snap_manual_tempo_and_repeated_extension"] = true

                // An eight-beat MIDI file with an intentionally different embedded BPM.
                let midi = output.appendingPathComponent("source-80bpm.mid")
                let bytes: [UInt8] = [0x4d,0x54,0x68,0x64,0,0,0,6,0,0,0,1,1,0xe0, 0x4d,0x54,0x72,0x6b,0,0,0,20, 0,0xff,0x51,3,0x0b,0x71,0xb0, 0,0x90,60,100, 0x9e,0,0x80,60,0, 0,0xff,0x2f,0]
                try Data(bytes).write(to: midi)
                engine.transport.setBeat(0.13)
                importMIDIFileAsClip(midi, forceNewTrack: true)
                let midiTrack = selectedTrack!, clip = midiTrack.clips[0]
                try require(clip.startBeat == 0.25 && clip.lengthBeats == 8 && clip.loopLengthBeats == 8, "MIDI import grid/source length failed")
                clip.sourceTempo = 80
                clip.repeatNotes(sourceLength: clip.loopLengthBeats, targetLength: 24); clip.lengthBeats = 24
                try require(clip.notes.map(\.start) == [0,8,16] && project.tempo == 100, "MIDI repeat used source BPM instead of project beats")
                report["midi_import_and_extension_project_tempo"] = true
                let legacy = Clip(name: "Old import", startBeat: 0, lengthBeats: 8, notes: [ClipNote(pitch: 60, start: 0, length: 1), ClipNote(pitch: 64, start: 4, length: 1)])
                legacy.loopLengthBeats = 4
                try require(legacy.sourceLoopLengthForExtension(fallback: 8) == 8, "Legacy MIDI phrase incorrectly uses four-beat default")
                legacy.repeatNotes(sourceLength: 8, targetLength: 24)
                try require(legacy.sourceLoopLengthForExtension(fallback: 24) == 8, "Existing repeats lost original phrase length")
                let duplicate = duplicateMidiClip(clip, on: midiTrack)
                try require(duplicate.loopLengthBeats == 8 && duplicate.sourceTempo == 80, "MIDI duplication discarded source timing state")
                midiTrack.clips.removeAll { $0.id == duplicate.id }
                report["legacy_midi_loop_and_duplicate_state"] = true
                midiTrack.mute = true
                engine.attach(project: project); rebuildTempoMap()
                let doc = try ProjectDocument(project: project).encoded()
                try doc.write(to: output.appendingPathComponent("manual-tempo.lemmingsproject"))
                let restored = try JSONDecoder().decode(ProjectDocument.self, from: doc).makeProject()
                let restoredAudio = restored.tracks[0].audioClips[0]
                try require(restoredAudio.manualTempoOverride && restoredAudio.originalTempo == 120 && restoredAudio.loopLengthBeats == 4 && restored.tempo == 100, "Saved project lost manual tempo/loop")
                report["project_tempo_state_round_trip"] = true
                // Freeze no longer than three bars so format checks stay lightweight.
                project.lengthBars = 3
                engine.metronomeEnabled = true
                Task { @MainActor in
                    do {
                        for format in ExportFormat.allCases {
                            let url = output.appendingPathComponent("preview.\(format.ext)")
                            try offline.export(project: project, to: url, format: format)
                            let file = try AVAudioFile(forReading: url)
                            try require(file.length > 0 && file.fileFormat.channelCount == 2, "Invalid \(format.rawValue) audio container")
                            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
                            try file.read(into: buffer)
                            try require(buffer.frameLength > 0, "Cannot decode \(format.rawValue)")
                            let asset = AVURLAsset(url: url)
                            let playable = try await asset.load(.isPlayable)
                            let duration = try await asset.load(.duration)
                            try require(playable && duration.seconds > 7, "Apple preview/playback rejected \(format.rawValue)")
                            report[format.ext + "_apple_playable"] = true
                        }
                        finish()
                    } catch { finish(error) }
                }
            } catch { finish(error) }
        }
    }
}
