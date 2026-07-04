import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Startup sound
//
// Plays the bundled startup voiceover at launch. Prefer the user-provided
// Resources/LemmingsStartup.wav, keep Resources/startup.wav as a legacy alias,
// and fall back to AVSpeechSynthesizer only if neither bundled file is available.

public final class StartupSound {
    public static let shared = StartupSound()
    public static let line = "Lemmings Studio. When they fall like lemmings, that's where I come in."

    #if canImport(AVFoundation)
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    #endif

    private init() {}

    public func play() {
        #if canImport(AVFoundation)
        let candidates = startupSoundCandidates()
        for url in candidates {
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.volume = 0.9
                p.prepareToPlay()
                p.play()
                player = p
                return
            } catch {
                continue
            }
        }
        speakFallback()
        #endif
    }


    #if canImport(AVFoundation)
    private func startupSoundCandidates() -> [URL] {
        let names = ["LemmingsStartup", "startup"]
        var urls: [URL] = []

        // SwiftPM .copy("Resources") preserves the Resources/ subdirectory inside
        // LemmingsStudio_LemmingsStudio.bundle, so a flat Bundle.module lookup can
        // miss the WAV. Check both flat and nested resource locations, then the
        // app bundle Resources folder used by build.sh packaging.
        for name in names {
            if let url = Bundle.module.url(forResource: name, withExtension: "wav") { urls.append(url) }
            if let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Resources") { urls.append(url) }
            if let url = Bundle.main.url(forResource: name, withExtension: "wav") { urls.append(url) }
            if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Resources") { urls.append(url) }
        }

        let resourceRoots = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        ].compactMap { $0 }
        for root in resourceRoots {
            for file in ["LemmingsStartup.wav", "startup.wav"] {
                let direct = root.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: direct.path) { urls.append(direct) }
                let nested = root.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: nested.path) { urls.append(nested) }
            }
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func speakFallback() {
        let line = Self.line.replacingOccurrences(of: " - ", with: ", ")
        let u = AVSpeechUtterance(string: line)
        // ElevenLabs-ish fallback: pick the highest-quality human macOS voice
        // available, avoid novelty/robot voices, and use a relaxed narration pace.
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.72
        u.pitchMultiplier = 0.98
        u.volume = 0.72
        u.preUtteranceDelay = 0.08
        u.postUtteranceDelay = 0.03
        let blocked = ["Zarvox", "Trinoids", "Bubbles", "Cellos", "Good News", "Bad News", "Whisper", "Pipe Organ", "Bells"]
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.hasPrefix("en") && !blocked.contains { voice.name.localizedCaseInsensitiveContains($0) }
        }
        let preferredNames = ["Ava", "Samantha", "Allison", "Susan", "Daniel", "Karen", "Moira"]
        let chosen = preferredNames.compactMap { name in voices.first { $0.name.localizedCaseInsensitiveContains(name) } }.first
            ?? voices.first(where: { $0.quality == .premium })
            ?? voices.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: "en-US")
        if let chosen { u.voice = chosen }
        synth.speak(u)
    }
    #endif
}
