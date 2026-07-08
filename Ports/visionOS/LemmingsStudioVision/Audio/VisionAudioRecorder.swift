import AVFoundation
import Foundation

final class VisionAudioRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var node: AVAudioInputNode?
    private(set) var isRecording = false
    private(set) var currentURL: URL?

    func start(using input: AVAudioInputNode, destination: URL) throws {
        guard !isRecording else { return }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "LemmingsStudioVision", code: 41, userInfo: [NSLocalizedDescriptionKey: "No usable microphone input format is available."])
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let output = try AVAudioFile(forWriting: destination, settings: format.settings)
        lock.lock(); file = output; lock.unlock()
        node = input; currentURL = destination
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            try? self.file?.write(from: buffer)
        }
        isRecording = true
    }

    func stop() -> URL? {
        guard isRecording else { return currentURL }
        node?.removeTap(onBus: 0)
        node = nil
        lock.lock(); file = nil; lock.unlock()
        isRecording = false
        return currentURL
    }
}
