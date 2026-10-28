import Foundation
import Observation
import AppKit

public enum RVCRuntimeState: String, Sendable {
    case notInstalled = "Not Installed"
    case installing = "Installing"
    case ready = "Ready"
    case broken = "Needs Repair"
    case converting = "Converting"
    case cancelled = "Cancelled"
}

public enum RVCF0Method: String, CaseIterable, Identifiable, Sendable {
    case rmvpe, crepe, harvest, dio
    public var id: String { rawValue }
    public var displayName: String { rawValue.uppercased() }
}

public struct RVCConversionOptions: Sendable {
    public var pitchShift = 0
    public var f0Method: RVCF0Method = .rmvpe
    public var indexRate = 0.75
    public var filterRadius = 3
    public var rmsMixRate = 0.25
    public var protect = 0.33
    public init() {}
}

public enum RVCRuntimeError: LocalizedError {
    case pythonMissing, workerMissing, runtimeNotReady(String), processFailed(String), outputMissing
    public var errorDescription: String? {
        switch self {
        case .pythonMissing: return "Python 3.10 or 3.11 was not found. Install python@3.11 with Homebrew, then repair the RVC runtime."
        case .workerMissing: return "The bundled RVC worker is missing."
        case .runtimeNotReady(let detail): return "RVC runtime is not ready: \(detail)"
        case .processFailed(let detail): return detail
        case .outputMissing: return "RVC finished without producing a valid WAV."
        }
    }
}

@MainActor
@Observable
public final class RVCRuntimeManager {
    public static let shared = RVCRuntimeManager()
    public private(set) var state: RVCRuntimeState = .notInstalled
    public private(set) var status = "RVC runtime has not been installed"
    public private(set) var detail = ""
    public private(set) var progress = 0.0
    public private(set) var lastLogURL: URL?
    public var selectedF0Method: RVCF0Method = .rmvpe
    public var pitchShift = 0
    public var indexRate = 0.75
    public var filterRadius = 3
    public var rmsMixRate = 0.25
    public var protect = 0.33
    @ObservationIgnored private var activeProcess: Process?

    public let rootURL: URL
    public let venvURL: URL
    public let modelsURL: URL
    public let cacheURL: URL
    public let logsURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = support.appendingPathComponent("LemmingsStudio/RVC", isDirectory: true)
        venvURL = rootURL.appendingPathComponent("venv", isDirectory: true)
        modelsURL = rootURL.appendingPathComponent("models", isDirectory: true)
        cacheURL = rootURL.appendingPathComponent("cache", isDirectory: true)
        logsURL = rootURL.appendingPathComponent("logs", isDirectory: true)
        refreshState()
    }

    public var pythonURL: URL { venvURL.appendingPathComponent("bin/python3") }
    public var isBusy: Bool { state == .installing || state == .converting }

    public func refreshState() {
        createDirectories()
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            state = .notInstalled; status = "RVC runtime has not been installed"; detail = rootURL.path; return
        }
        if FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(".runtime-ready").path) {
            state = .ready; status = "RVC runtime ready"; detail = pythonURL.path
        } else {
            state = .broken; status = "RVC runtime needs verification or repair"; detail = pythonURL.path
        }
    }

    public func installOrRepair() async {
        guard !isBusy else { return }
        state = .installing; status = "Preparing isolated RVC environment…"; progress = 0.02; createDirectories()
        do {
            let base = try locateBasePython()
            let log = makeLogURL(prefix: "install"); lastLogURL = log
            try await runLogged(base, ["-m","venv","--clear",venvURL.path], log, "Creating private venv", 0.12)
            try await runLogged(pythonURL, ["-m","pip","install","--upgrade","pip>=24","setuptools<81","wheel"], log, "Updating pip tools", 0.24)
            guard let req = Bundle.main.url(forResource: "rvc_requirements", withExtension: "txt", subdirectory: "Services") else { throw RVCRuntimeError.runtimeNotReady("requirements are missing") }
            try await runLogged(pythonURL, ["-m","pip","install","--prefer-binary","-r",req.path], log, "Installing RVC dependencies", 0.48)
            if let opt = Bundle.main.url(forResource: "rvc_optional_requirements", withExtension: "txt", subdirectory: "Services") {
                try? await runLogged(pythonURL, ["-m","pip","install","--prefer-binary","-r",opt.path], log, "Installing optional index acceleration", 0.78)
            }
            try await verifyRuntime(log)
            try Data(Date().description.utf8).write(to: rootURL.appendingPathComponent(".runtime-ready"), options: .atomic)
            state = .ready; status = "RVC runtime installed and verified"; detail = pythonURL.path; progress = 1
        } catch {
            state = error is CancellationError ? .cancelled : .broken
            status = error is CancellationError ? "RVC installation cancelled" : "RVC installation failed"
            detail = error.localizedDescription; progress = 0
        }
    }

    public func verify() async {
        guard !isBusy else { return }
        state = .installing; status = "Verifying RVC runtime…"; progress = 0.1
        do {
            guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else { throw RVCRuntimeError.runtimeNotReady("private Python venv does not exist") }
            let log = makeLogURL(prefix: "verify"); lastLogURL = log
            try await verifyRuntime(log)
            try Data(Date().description.utf8).write(to: rootURL.appendingPathComponent(".runtime-ready"), options: .atomic)
            state = .ready; status = "RVC runtime verified"; detail = pythonURL.path; progress = 1
        } catch {
            state = .broken; status = "RVC verification failed"; detail = error.localizedDescription; progress = 0
        }
    }

    public func cancelActiveOperation() { activeProcess?.terminate(); activeProcess = nil; state = .cancelled; status = "RVC operation cancelled"; progress = 0 }
    public func revealRuntimeFolder() { NSWorkspace.shared.open(rootURL) }
    public func revealLastLog() { if let lastLogURL { NSWorkspace.shared.activateFileViewerSelecting([lastLogURL]) } else { NSWorkspace.shared.open(logsURL) } }

    public func convert(inputAudio: URL, modelPath: URL, outputURL: URL, options: RVCConversionOptions) async throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else { throw RVCRuntimeError.runtimeNotReady("install the private runtime first") }
        guard let worker = workerURL else { throw RVCRuntimeError.workerMissing }
        state = .converting; status = "Running RVC voice conversion…"; detail = modelPath.lastPathComponent; progress = 0.08
        let log = makeLogURL(prefix: "convert"); lastLogURL = log; try? FileManager.default.removeItem(at: outputURL)
        do {
            try await runLogged(pythonURL, [worker.path,"--input",inputAudio.path,"--model",modelPath.path,"--output",outputURL.path,"--pitch",String(options.pitchShift),"--f0-method",options.f0Method.rawValue,"--index-rate",String(options.indexRate),"--filter-radius",String(options.filterRadius),"--rms-mix-rate",String(options.rmsMixRate),"--protect",String(options.protect)], log, "Converting \(inputAudio.lastPathComponent)", 0.35)
            let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard FileManager.default.fileExists(atPath: outputURL.path), size > 44 else { throw RVCRuntimeError.outputMissing }
            state = .ready; status = "RVC conversion complete"; detail = outputURL.lastPathComponent; progress = 1; return outputURL
        } catch {
            state = error is CancellationError ? .cancelled : .broken; status = "RVC conversion failed"; detail = error.localizedDescription; progress = 0; throw error
        }
    }

    private var workerURL: URL? { Bundle.main.url(forResource: "rvc_worker", withExtension: "py", subdirectory: "Services") }
    private func verifyRuntime(_ log: URL) async throws {
        guard let worker = workerURL else { throw RVCRuntimeError.workerMissing }
        try await runLogged(pythonURL, [worker.path,"--verify"], log, "Verifying imports and device support", 0.92)
    }
    private func locateBasePython() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        for p in [env["LEMMINGS_RVC_PYTHON"],"/opt/homebrew/bin/python3.11","/usr/local/bin/python3.11","/opt/homebrew/bin/python3.10","/usr/local/bin/python3.10","/opt/homebrew/bin/python3","/usr/local/bin/python3"].compactMap({$0}) where FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        throw RVCRuntimeError.pythonMissing
    }
    private func createDirectories() { for u in [rootURL,modelsURL,cacheURL,logsURL] { try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true) } }
    private func makeLogURL(prefix: String) -> URL { let f=DateFormatter(); f.dateFormat="yyyyMMdd-HHmmss"; return logsURL.appendingPathComponent("\(prefix)-\(f.string(from: Date())).log") }

    private func runLogged(_ executable: URL, _ arguments: [String], _ logURL: URL, _ phase: String, _ progressValue: Double) async throws {
        status = phase; progress = progressValue
        let root = rootURL; let cache = cacheURL
        let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
            let p=Process(); p.executableURL=executable; p.arguments=arguments; p.currentDirectoryURL=root
            var env=ProcessInfo.processInfo.environment; env["PYTHONNOUSERSITE"]="1"; env["LEMMINGS_RVC_ROOT"]=root.path; env["LEMMINGS_RVC_CACHE"]=cache.path; p.environment=env
            let out=Pipe(); let err=Pipe(); p.standardOutput=out; p.standardError=err
            await MainActor.run { self.activeProcess=p }
            try p.run(); p.waitUntilExit()
            let combined=out.fileHandleForReading.readDataToEndOfFile()+err.fileHandleForReading.readDataToEndOfFile()
            await MainActor.run { self.activeProcess=nil }
            try combined.write(to: logURL, options: .atomic)
            if p.terminationReason == .uncaughtSignal { throw CancellationError() }
            guard p.terminationStatus == 0 else { throw RVCRuntimeError.processFailed(String(data: combined, encoding: .utf8) ?? "RVC process failed") }
            return combined
        }.value
        if let text=String(data:data,encoding:.utf8), !text.isEmpty { detail=text.split(separator:"\n").suffix(3).joined(separator:"\n") }
    }
}
