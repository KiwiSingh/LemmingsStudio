import Foundation
import Observation

public enum VoiceModelLicense: String, CaseIterable, Identifiable, Sendable {
    case consentVerified = "Consent-verified"
    case publicDomain = "Public domain"
    case userOwned = "User-owned import"
    case researchOnly = "Research-only"
    public var id: String { rawValue }
}

public struct SingingVoiceModel: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var style: String
    public var languageHints: [String]
    public var license: VoiceModelLicense
    public var sourceURL: String
    public var sha256: String?
    public var installedPath: String?
    public var notes: String

    public init(id: String, name: String, style: String, languageHints: [String], license: VoiceModelLicense, sourceURL: String, sha256: String? = nil, installedPath: String? = nil, notes: String) {
        self.id = id; self.name = name; self.style = style; self.languageHints = languageHints; self.license = license; self.sourceURL = sourceURL; self.sha256 = sha256; self.installedPath = installedPath; self.notes = notes
    }
}

@Observable public final class VoiceModelStore {
    public var repository: [SingingVoiceModel] = VoiceModelStore.ethicalStarterRepository
    public var imported: [SingingVoiceModel] = []
    public var status = "Voice model system ready"
    public var cloneConsentChecked = false
    public var cloneDatasetGuidanceAccepted = false

    public init() {}

    public static let ethicalStarterRepository: [SingingVoiceModel] = [
        SingingVoiceModel(id: "starter-neutral-pop", name: "Neutral Pop Guide", style: "clean pop guide vocal", languageHints: ["en"], license: .consentVerified, sourceURL: "builtin://neutral-pop-guide", notes: "Built-in catalogue slot only. Import a consent-cleared RVC .pth/.index model before rendering."),
        SingingVoiceModel(id: "starter-classical-a", name: "Classical Aakar Guide", style: "open vowel classical guide", languageHints: ["hi", "sa", "en"], license: .consentVerified, sourceURL: "builtin://classical-aakar-guide", notes: "Built-in catalogue slot only. Import a consent-cleared RVC .pth/.index model before rendering."),
        SingingVoiceModel(id: "starter-folk-dhol-vocal", name: "Folk Call Guide", style: "folk call-and-response", languageHints: ["pa", "hi"], license: .consentVerified, sourceURL: "builtin://folk-call-guide", notes: "Built-in catalogue slot only. Import a consent-cleared RVC .pth/.index model before rendering.")
    ]

    public func importModel(at url: URL) {
        let id = "user-" + url.deletingPathExtension().lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-")
        let model = SingingVoiceModel(id: id, name: url.deletingPathExtension().lastPathComponent, style: "Imported", languageHints: [], license: .userOwned, sourceURL: url.absoluteString, installedPath: url.path, notes: "User imported this model manually and is responsible for rights/consent.")
        imported.append(model)
        status = "Imported voice model: \(model.name)"
    }

    public func transform(inputAudio: URL, using model: SingingVoiceModel, outputDirectory: URL, bundledPython: URL?) async -> URL? {
        let out = outputDirectory.appendingPathComponent(inputAudio.deletingPathExtension().lastPathComponent + "_" + model.name.replacingOccurrences(of: " ", with: "_") + ".wav")
        let python = bundledPython ?? Bundle.main.url(forResource: "PythonVenv/bin/python3", withExtension: nil)
        guard let python else { status = "No bundled python3/RVC voice runtime found"; return nil }
        let script = Bundle.main.resourceURL?.appendingPathComponent("Services/voice_transform.py")
        guard let script else { status = "Voice transform service missing"; return nil }
        let p = Process()
        p.executableURL = python
        p.arguments = [script.path, "--input", inputAudio.path, "--model", model.installedPath ?? model.sourceURL, "--output", out.path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run(); p.waitUntilExit() } catch { status = error.localizedDescription; return nil }
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if p.terminationStatus == 0 {
            status = stderr.isEmpty ? "Rendered RVC voice transform: \(out.lastPathComponent)" : "Rendered RVC voice transform: \(out.lastPathComponent) — \(stderr)"
            return out
        }
        status = stderr.isEmpty ? "RVC voice transform failed" : stderr
        return nil
    }
}

public enum VoiceCloneGuide {
    public static let minimumGuidance = "Record at least 10 minutes of clean, consented singing; 30 minutes is recommended and 60 minutes is the practical upper target. Keep takes dry/mono, avoid reverb/delay/noise, include vowels, pitch ranges, dynamics, and label language/style."
    public static let requiredConsent = "Only clone your own voice or a vocalist who gave explicit, written permission for voice conversion and redistribution terms."
}
