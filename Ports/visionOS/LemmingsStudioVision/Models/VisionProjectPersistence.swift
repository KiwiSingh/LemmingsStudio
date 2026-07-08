import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct VisionRecentProject: Codable, Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var displayName: String
    var lastOpened: Date

    var url: URL { URL(fileURLWithPath: path) }
}

struct VisionProjectPackageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.lemmingsProject, .json] }

    var project: LemmingsProject
    var sourceURL: URL?

    init(project: LemmingsProject, sourceURL: URL?) {
        self.project = project
        self.sourceURL = sourceURL
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw VisionProjectPersistenceError.invalidPackage
        }
        self.project = try LemmingsProject.decode(data)
        self.sourceURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try VisionProjectPersistence.packageWrapper(project: project, sourceURL: sourceURL, recoveryData: nil)
    }
}

enum VisionProjectPersistenceError: LocalizedError {
    case invalidPackage
    case missingManifest

    var errorDescription: String? {
        switch self {
        case .invalidPackage: return "The selected LemmingsStudio project package is invalid."
        case .missingManifest: return "The project package does not contain project.json."
        }
    }
}

enum VisionProjectPersistence {
    static let manifestName = "project.json"
    static let packageVersion = 3

    static func loadProject(at url: URL) throws -> LemmingsProject {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let manifest = url.appendingPathComponent(manifestName)
            guard FileManager.default.fileExists(atPath: manifest.path) else {
                throw VisionProjectPersistenceError.missingManifest
            }
            return try LemmingsProject.decode(Data(contentsOf: manifest))
        }
        return try LemmingsProject.decode(Data(contentsOf: url))
    }

    static func packageBaseURL(for projectURL: URL?) -> URL? {
        guard let projectURL else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return projectURL
        }
        return projectURL.deletingLastPathComponent()
    }

    static func resolveAssetPath(_ path: String, projectURL: URL?) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if let base = packageBaseURL(for: projectURL) { return base.appendingPathComponent(path) }
        return URL(fileURLWithPath: path)
    }

    static func packageWrapper(
        project sourceProject: LemmingsProject,
        sourceURL: URL?,
        recoveryData: Data?
    ) throws -> FileWrapper {
        var project = sourceProject
        project.version = packageVersion

        var audioFiles: [String: FileWrapper] = [:]
        var sampleFiles: [String: FileWrapper] = [:]
        var takeFiles: [String: FileWrapper] = [:]
        var copiedSources: [String: String] = [:]

        func embeddedPath(for original: String, folder: String, prefix: String) -> String? {
            if let existing = copiedSources[original] { return existing }
            let source = resolveAssetPath(original, projectURL: sourceURL)
            guard FileManager.default.fileExists(atPath: source.path),
                  let data = try? Data(contentsOf: source) else { return nil }
            let safeName = source.lastPathComponent.replacingOccurrences(of: "/", with: "_")
            let filename = "\(prefix)-\(UUID().uuidString.prefix(8))-\(safeName)"
            let relative = "\(folder)/\(filename)"
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = filename
            switch folder {
            case "Audio": audioFiles[filename] = wrapper
            case "Samples": sampleFiles[filename] = wrapper
            default: takeFiles[filename] = wrapper
            }
            copiedSources[original] = relative
            return relative
        }

        for trackIndex in project.tracks.indices {
            for clipIndex in project.tracks[trackIndex].audioClips.indices {
                guard let path = project.tracks[trackIndex].audioClips[clipIndex].sourcePath,
                      let embedded = embeddedPath(for: path, folder: "Audio", prefix: "clip") else { continue }
                project.tracks[trackIndex].audioClips[clipIndex].sourcePath = embedded
            }
        }

        if project.stepSequencer != nil {
            for layerIndex in project.stepSequencer!.layers.indices {
                guard let path = project.stepSequencer!.layers[layerIndex].sourcePath,
                      let embedded = embeddedPath(for: path, folder: "Samples", prefix: "seq") else { continue }
                project.stepSequencer!.layers[layerIndex].sourcePath = embedded
            }
        }

        if project.takeFolders != nil {
            for folderIndex in project.takeFolders!.indices {
                for takeIndex in project.takeFolders![folderIndex].takes.indices {
                    let path = project.takeFolders![folderIndex].takes[takeIndex].sourcePath
                    if let embedded = embeddedPath(for: path, folder: "Takes", prefix: "take") {
                        project.takeFolders![folderIndex].takes[takeIndex].sourcePath = embedded
                    }
                }
                if let path = project.takeFolders![folderIndex].consolidatedCompPath,
                   let embedded = embeddedPath(for: path, folder: "Takes", prefix: "comp") {
                    project.takeFolders![folderIndex].consolidatedCompPath = embedded
                }
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(project)
        let manifest = FileWrapper(regularFileWithContents: manifestData)
        manifest.preferredFilename = manifestName

        var children: [String: FileWrapper] = [manifestName: manifest]
        children["Audio"] = FileWrapper(directoryWithFileWrappers: audioFiles)
        children["Samples"] = FileWrapper(directoryWithFileWrappers: sampleFiles)
        children["Takes"] = FileWrapper(directoryWithFileWrappers: takeFiles)
        children["Analysis"] = FileWrapper(directoryWithFileWrappers: [:])
        children["Metadata"] = FileWrapper(directoryWithFileWrappers: [:])

        if let recoveryData {
            let recoveryManifest = FileWrapper(regularFileWithContents: recoveryData)
            recoveryManifest.preferredFilename = "project.recovery.json"
            children["Recovery"] = FileWrapper(directoryWithFileWrappers: ["project.recovery.json": recoveryManifest])
        }

        return FileWrapper(directoryWithFileWrappers: children)
    }

    static func writePackage(project: LemmingsProject, to url: URL, sourceURL: URL?) throws {
        let fm = FileManager.default
        let oldManifest = url.appendingPathComponent(manifestName)
        let recoveryData = try? Data(contentsOf: oldManifest)
        let wrapper = try packageWrapper(project: project, sourceURL: sourceURL, recoveryData: recoveryData)
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".\(url.lastPathComponent).saving-\(UUID().uuidString)", isDirectory: true)
        try wrapper.write(to: staging, options: [], originalContentsURL: nil)

        if fm.fileExists(atPath: url.path) {
            let backup = parent.appendingPathComponent(".\(url.lastPathComponent).backup", isDirectory: true)
            try? fm.removeItem(at: backup)
            try fm.moveItem(at: url, to: backup)
            do {
                try fm.moveItem(at: staging, to: url)
                try? fm.removeItem(at: backup)
            } catch {
                try? fm.moveItem(at: backup, to: url)
                throw error
            }
        } else {
            try fm.moveItem(at: staging, to: url)
        }
    }

    static func recoveryURL() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LemmingsStudio/Autosave", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Recovery.lemmingsproject", isDirectory: true)
    }
}
