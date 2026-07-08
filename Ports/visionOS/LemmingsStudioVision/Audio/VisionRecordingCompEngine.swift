import AVFoundation
import Foundation

struct VisionRecordingSettings: Codable, Sendable {
    var countInBars: Int = 1
    var preRollBars: Int = 1
    var punchEnabled: Bool = false
    var punchInBeat: Double = 0
    var punchOutBeat: Double = 16
    var autoCreateTakeFolder: Bool = true
}

struct VisionCompRegion: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var takeID: UUID
    var startBeat: Double
    var endBeat: Double
    var sourceOffsetBeat: Double = 0
    var fadeInBeats: Double = 0.02
    var fadeOutBeats: Double = 0.02
}

enum VisionCompEngineError: LocalizedError {
    case noRegions
    case missingTake(UUID)
    case unreadableSource(String)

    var errorDescription: String? {
        switch self {
        case .noRegions: return "The comp has no regions."
        case .missingTake(let id): return "Missing take \(id.uuidString)."
        case .unreadableSource(let path): return "Could not read take audio at \(path)."
        }
    }
}

final class VisionRecordingCompEngine: @unchecked Sendable {
    func consolidate(folder: VisionTakeFolder, tempo: Double, destination: URL) throws -> URL {
        let regions = folder.compRegions.sorted { $0.startBeat < $1.startBeat }
        guard !regions.isEmpty else { throw VisionCompEngineError.noRegions }
        let takeMap = Dictionary(uniqueKeysWithValues: folder.takes.map { ($0.id, $0) })
        guard let firstTake = takeMap[regions[0].takeID] else { throw VisionCompEngineError.missingTake(regions[0].takeID) }
        let firstURL = URL(fileURLWithPath: firstTake.sourcePath)
        guard let firstFile = try? AVAudioFile(forReading: firstURL) else { throw VisionCompEngineError.unreadableSource(firstTake.sourcePath) }
        let format = firstFile.processingFormat
        let secondsPerBeat = 60.0 / max(20, tempo)
        let endBeat = regions.map(\.endBeat).max() ?? 0
        let totalFrames = AVAudioFramePosition(ceil(endBeat * secondsPerBeat * format.sampleRate))

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let out = try AVAudioFile(forWriting: destination, settings: format.settings)
        guard let mix = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, totalFrames))) else {
            throw VisionCompEngineError.unreadableSource(firstTake.sourcePath)
        }
        mix.frameLength = mix.frameCapacity
        zero(mix)

        for region in regions {
            guard let take = takeMap[region.takeID] else { throw VisionCompEngineError.missingTake(region.takeID) }
            let url = URL(fileURLWithPath: take.sourcePath)
            guard let file = try? AVAudioFile(forReading: url) else { throw VisionCompEngineError.unreadableSource(take.sourcePath) }
            let durationBeats = max(0, region.endBeat - region.startBeat)
            let frameCount = AVAudioFrameCount(durationBeats * secondsPerBeat * format.sampleRate)
            let sourceStart = AVAudioFramePosition(max(0, region.sourceOffsetBeat * secondsPerBeat * format.sampleRate))
            file.framePosition = min(sourceStart, file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, frameCount)) else { continue }
            try file.read(into: buffer, frameCount: min(frameCount, AVAudioFrameCount(max(0, file.length - file.framePosition))))
            let destStart = AVAudioFramePosition(region.startBeat * secondsPerBeat * format.sampleRate)
            mixInto(buffer, destination: mix, destinationStart: destStart, fadeInFrames: AVAudioFrameCount(region.fadeInBeats * secondsPerBeat * format.sampleRate), fadeOutFrames: AVAudioFrameCount(region.fadeOutBeats * secondsPerBeat * format.sampleRate))
        }
        try out.write(from: mix)
        return destination
    }

    private func zero(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        for c in 0..<Int(buffer.format.channelCount) {
            channels[c].initialize(repeating: 0, count: Int(buffer.frameLength))
        }
    }

    private func mixInto(_ source: AVAudioPCMBuffer, destination: AVAudioPCMBuffer, destinationStart: AVAudioFramePosition, fadeInFrames: AVAudioFrameCount, fadeOutFrames: AVAudioFrameCount) {
        guard let src = source.floatChannelData, let dst = destination.floatChannelData else { return }
        let maxFrames = min(Int(source.frameLength), Int(destination.frameLength) - Int(destinationStart))
        guard maxFrames > 0 else { return }
        let channels = min(Int(source.format.channelCount), Int(destination.format.channelCount))
        for frame in 0..<maxFrames {
            var gain: Float = 1
            if fadeInFrames > 0 && frame < Int(fadeInFrames) { gain *= Float(frame) / Float(max(1, fadeInFrames)) }
            let remaining = maxFrames - frame
            if fadeOutFrames > 0 && remaining < Int(fadeOutFrames) { gain *= Float(remaining) / Float(max(1, fadeOutFrames)) }
            for c in 0..<channels { dst[c][Int(destinationStart) + frame] += src[c][frame] * gain }
        }
    }
}
