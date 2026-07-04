import Foundation
import AVFoundation
import Darwin

// MARK: - Export formats

public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case wav = "WAV", flac = "FLAC", mp3 = "MP3", aac = "AAC (m4a)"
    public var id: String { rawValue }
    public var ext: String {
        switch self { case .wav: return "wav"; case .flac: return "flac"; case .mp3: return "mp3"; case .aac: return "m4a" }
    }
    /// True when AVFoundation can encode it natively (MP3 needs an external tool).
    public var nativelyEncodable: Bool { self != .mp3 }
}

public enum ExportError: LocalizedError {
    case renderFailed(String), noEncoder(String)
    public var errorDescription: String? {
        switch self {
        case .renderFailed(let s): return "Render failed: \(s)"
        case .noEncoder(let s): return s
        }
    }
}

public struct ExportRenderReport: Sendable {
    public var url: URL
    public var peak: Float
    public var clipped: Bool
    public var frames: Int

    public var peakDBFS: Double {
        guard peak > 0.000001 else { return -120 }
        return 20.0 * log10(Double(peak))
    }
}

// MARK: - Offline renderer

/// Renders the project (or a single track) offline using AVAudioEngine's manual
/// rendering mode, reusing the exact same per-track source nodes / effects /
/// automation as realtime playback — so a bounce sounds identical to what you hear.
public final class OfflineRenderer {
    private unowned let engine: AudioEngine
    public init(engine: AudioEngine) { self.engine = engine }

    private func lengthSeconds(_ project: Project) -> Double {
        if let map = engine.transport.tempoMap {
            // seconds at the final beat ≈ inverse lookup near the end
            var lo = 0.0, hi = 6000.0
            for _ in 0..<40 { let mid = (lo+hi)/2; if map.beat(atSeconds: mid) < project.lengthBeats { lo = mid } else { hi = mid } }
            return hi
        }
        return project.lengthBeats * 60.0 / project.tempo
    }

    /// Render to in-memory stereo float buffers and report progress/clipping.
    public func renderStereo(project: Project,
                             progress: (@Sendable (Double) -> Void)? = nil,
                             includeMetronome: Bool = true,
                             forcedPlaybackScope: PlaybackScope? = nil) throws -> (l: [Float], r: [Float], peak: Float, clipped: Bool) {
        let sr = engine.sampleRate
        let total = Int(lengthSeconds(project) * sr) + Int(sr) // +1s tail for reverbs
        let av = engine.avEngine
        let wasRunning = av.isRunning
        let savedMetronomeEnabled = engine.metronomeEnabled
        let savedPlaybackScope = engine.playbackScope
        let savedPlayStartBeat = engine.transport.playStartBeat
        let savedIsPlaying = engine.transport.isPlaying
        av.stop()
        engine.metronomeEnabled = includeMetronome
        if let forcedPlaybackScope { engine.playbackScope = forcedPlaybackScope }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else {
            throw ExportError.renderFailed("format")
        }
        let maxFrames: AVAudioFrameCount = 4096
        var outL = [Float](); outL.reserveCapacity(total)
        var outR = [Float](); outR.reserveCapacity(total)
        var peak: Float = 0
        var clipped = false
        progress?(0)

        do {
            try av.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
            try av.start()
            engine.transport.tempo = project.tempo
            engine.transport.stop(at: 0)
            engine.allNotesOff()
            engine.transport.play()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: av.manualRenderingFormat, frameCapacity: maxFrames) else {
                throw ExportError.renderFailed("buffer")
            }
            var rendered = 0
            while rendered < total {
                let n = AVAudioFrameCount(min(Int(maxFrames), total - rendered))
                let status = try av.renderOffline(n, to: buffer)
                if status == .success || status == .insufficientDataFromInputNode {
                    let frames = Int(buffer.frameLength)
                    if let ch = buffer.floatChannelData {
                        let rp = buffer.format.channelCount > 1 ? ch[1] : ch[0]
                        for i in 0..<frames {
                            let l = ch[0][i]
                            let r = rp[i]
                            outL.append(l)
                            outR.append(r)
                            let a = max(abs(l), abs(r))
                            if a > peak { peak = a }
                            if a >= 0.999 { clipped = true }
                        }
                    }
                    rendered += frames
                    progress?(min(0.92, Double(rendered) / Double(max(1, total)) * 0.92))
                    if frames == 0 { break }
                } else { break }
            }
        }
        engine.transport.stop(at: savedPlayStartBeat)
        engine.playbackScope = savedPlaybackScope
        engine.metronomeEnabled = savedMetronomeEnabled
        if savedIsPlaying { engine.transport.play() }
        av.stop()
        av.disableManualRenderingMode()
        if wasRunning { try? av.start() }
        progress?(0.92)
        return (outL, outR, peak, clipped)
    }

    // MARK: Export

    @discardableResult
    public func export(project: Project, to url: URL, format: ExportFormat) throws -> URL {
        try exportWithReport(project: project, to: url, format: format).url
    }

    @discardableResult
    public func exportWithReport(project: Project, to url: URL, format: ExportFormat, progress: (@Sendable (Double) -> Void)? = nil) throws -> ExportRenderReport {
        let rendered = try renderStereo(project: project, progress: progress)
        let finalURL: URL
        if format == .mp3 {
            let wav = url.deletingPathExtension().appendingPathExtension("wav")
            try writeFile(l: rendered.l, r: rendered.r, to: wav, settings: settings(.wav), project: project, format: .wav, progress: { p in progress?(0.92 + p * 0.04) })
            finalURL = try transcodeToMP3(from: wav, to: url, tempo: project.tempo, key: project.key.displayName)
        } else {
            try writeFile(l: rendered.l, r: rendered.r, to: url, settings: settings(format), project: project, format: format, progress: { p in progress?(0.92 + p * 0.08) })
            finalURL = url
        }
        progress?(1)
        return ExportRenderReport(url: finalURL, peak: rendered.peak, clipped: rendered.clipped, frames: min(rendered.l.count, rendered.r.count))
    }

    // MARK: Bounce / freeze

    /// Render a single track (in isolation) to a mono AudioClip and mark it frozen.
    public func bounce(track: Track, project: Project) throws {
        // Solo just this track for the render, then restore. The metronome is not
        // part of any track, so soloing alone is not enough: force Arrangement
        // playback and explicitly disable the click for freeze/bounce renders.
        let savedSolo = project.tracks.map { $0.solo }
        let savedLengthBars = project.lengthBars
        for t in project.tracks { t.solo = (t.id == track.id) }
        project.lengthBars = max(1, Int(ceil(trackContentEndBeat(track, project: project) / Double(max(1, project.beatsPerBar)))))
        defer {
            for (i, t) in project.tracks.enumerated() where i < savedSolo.count { t.solo = savedSolo[i] }
            project.lengthBars = savedLengthBars
        }

        let rendered = try renderStereo(project: project, includeMetronome: false, forcedPlaybackScope: .arrangement)
        let mono = zip(rendered.l, rendered.r).map { ($0 + $1) * 0.5 }
        let clip = AudioClip(startBeat: 0, samples: mono, sampleRate: engine.sampleRate)
        clip.displayName = "Frozen \(track.name)"
        track.bounced = clip
        track.frozen = true
    }

    private func trackContentEndBeat(_ track: Track, project: Project) -> Double {
        var endBeat = 0.0
        for clip in track.clips where clip.isActive {
            endBeat = max(endBeat, clip.startBeat + clip.lengthBeats)
        }
        for clip in track.audioClips where clip.isActive {
            endBeat = max(endBeat, clip.startBeat + clip.arrangementLengthBeats(projectTempo: project.tempo))
        }
        if track.useStepSequencer && track.kind.isStepEditable {
            let stepsPerBeat = max(1, track.stepPattern.stepsPerBeat)
            endBeat = max(endBeat, Double(track.stepPattern.stepCount) / Double(stepsPerBeat))
        }
        return max(Double(project.beatsPerBar), endBeat)
    }

    public func unfreeze(track: Track) { track.frozen = false; track.bounced = nil }

    // MARK: File writing

    private func settings(_ format: ExportFormat) -> [String: Any] {
        let sr = engine.sampleRate
        switch format {
        case .wav:
            return [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false]
        case .flac:
            return [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2]
        case .aac, .mp3:
            return [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 256000]
        }
    }

    private func writeFile(l: [Float], r: [Float], to url: URL, settings: [String: Any], project: Project, format: ExportFormat, progress: ((Double) -> Void)? = nil) throws {
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let fmt = file.processingFormat
        let chunk = 65536
        var pos = 0
        let n = min(l.count, r.count)
        while pos < n {
            let count = min(chunk, n - pos)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(count)),
                  let ch = buf.floatChannelData else { throw ExportError.renderFailed("write buffer") }
            for i in 0..<count { ch[0][i] = l[pos + i]; if fmt.channelCount > 1 { ch[1][i] = r[pos + i] } }
            buf.frameLength = AVAudioFrameCount(count)
            try file.write(from: buf)
            pos += count
            progress?(Double(pos) / Double(max(1, n)))
        }
        if format == .wav {
            try? writeWAVInfoMetadata(url: url, tempo: project.tempo, key: project.key.displayName, title: project.name)
        }
    }

    private func writeWAVInfoMetadata(url: URL, tempo: Double, key: String, title: String) throws {
        var data = try Data(contentsOf: url)
        guard data.count >= 12,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else { return }

        func chunk(_ id: String, _ text: String) -> Data {
            var out = Data(id.utf8.prefix(4))
            var payload = Data(text.utf8)
            payload.append(0)
            var size = UInt32(payload.count).littleEndian
            out.append(Data(bytes: &size, count: 4))
            out.append(payload)
            if payload.count % 2 == 1 { out.append(0) }
            return out
        }

        var infoPayload = Data("INFO".utf8)
        infoPayload.append(chunk("INAM", title.isEmpty ? url.deletingPathExtension().lastPathComponent : title))
        infoPayload.append(chunk("IBPM", String(Int(tempo.rounded()))))
        infoPayload.append(chunk("IKEY", key))
        infoPayload.append(chunk("ICMT", "Tempo=\(String(format: "%.3f", tempo)) BPM; Key=\(key)"))

        var list = Data("LIST".utf8)
        var listSize = UInt32(infoPayload.count).littleEndian
        list.append(Data(bytes: &listSize, count: 4))
        list.append(infoPayload)
        if infoPayload.count % 2 == 1 { list.append(0) }
        data.append(list)

        var riffSize = UInt32(data.count - 8).littleEndian
        data.replaceSubrange(4..<8, with: Data(bytes: &riffSize, count: 4))
        try data.write(to: url, options: .atomic)
    }

    /// MP3 isn't AVFoundation-encodable; transcode the WAV with ffmpeg or lame if present.
    private func transcodeToMP3(from wav: URL, to mp3: URL, tempo: Double, key: String) throws -> URL {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg",
                          "/opt/homebrew/bin/lame", "/usr/local/bin/lame", "/usr/bin/lame"]
        guard let tool = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ExportError.noEncoder("MP3 needs ffmpeg or lame installed (e.g. `brew install lame`). Your WAV was saved at \(wav.lastPathComponent); export FLAC/AAC for a native compressed file.")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tool)
        proc.arguments = tool.hasSuffix("lame")
            ? ["--tv", "TBPM=\(Int(tempo.rounded()))", "--tv", "TKEY=\(key)", "-V2", wav.path, mp3.path]
            : ["-y", "-i", wav.path, "-codec:a", "libmp3lame", "-qscale:a", "2", "-metadata", "BPM=\(Int(tempo.rounded()))", "-metadata", "TBPM=\(Int(tempo.rounded()))", "-metadata", "initial_key=\(key)", mp3.path]
        proc.standardError = FileHandle.nullDevice
        try proc.run(); proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw ExportError.noEncoder("MP3 transcode failed (\(tool)).") }
        try? FileManager.default.removeItem(at: wav)
        return mp3
    }
}
