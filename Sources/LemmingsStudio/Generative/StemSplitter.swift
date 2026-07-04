import Foundation

// MARK: - Stem splitter (Demucs)
//
// State-of-the-art open-source source separation via Demucs (Hybrid Transformer
// Demucs). The default `htdemucs` model splits drums/bass/other/vocals; the
// 6-source `htdemucs_6s` adds **guitar** and **piano** stems. Separation runs in
// a Python subprocess on the user's machine (models download on first use).
//
// Saxophone: there is no open-source SOTA model that isolates saxophone as a
// dedicated stem. The honest options are (a) take the `other` stem from a 4/6-
// source split, or (b) train/fine-tune a custom Demucs target — both surfaced to
// the user rather than pretending a "sax" button works.

public enum StemBackend: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case demucsPyTorch = "demucs-pytorch"
    case demucsMLX = "demucs-mlx"
    case htdemucsCoreML = "htdemucs-coreml"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: return "Auto — prefer Apple Silicon MLX, then Demucs"
        case .demucsPyTorch: return "Demucs / PyTorch — official-compatible"
        case .demucsMLX: return "Demucs MLX — Apple Silicon accelerated"
        case .htdemucsCoreML: return "HTDemucs Core ML — experimental Apple-native"
        }
    }

    public var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .demucsPyTorch: return "Demucs"
        case .demucsMLX: return "MLX Demucs"
        case .htdemucsCoreML: return "Core ML"
        }
    }

    public var note: String {
        switch self {
        case .auto:
            return "Chooses the fastest available backend on this Mac. On Apple Silicon, MLX Demucs is preferred when installed; otherwise official Demucs is used."
        case .demucsPyTorch:
            return "Most compatible path. Uses official Demucs models; Apple Silicon acceleration depends on the user's PyTorch/MPS install and can fall back to CPU."
        case .demucsMLX:
            return "Apple Silicon accelerated Demucs-compatible path. Supports the Demucs stem sets exposed by the installed MLX runner; if a runner lacks a model, Lemmings falls back or reports it."
        case .htdemucsCoreML:
            return "Experimental Apple-native alternative. Good for 4-stem HTDemucs-style splits when available; 6-source guitar/piano may not be supported by every Core ML package."
        }
    }
}

public enum StemModel: String, CaseIterable, Identifiable, Sendable {
    case htdemucs = "htdemucs"            // 4 stems, fast, SOTA default
    case htdemucs_ft = "htdemucs_ft"      // 4 stems, fine-tuned, higher quality/slower
    case htdemucs_6s = "htdemucs_6s"      // 6 stems incl. guitar + piano
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .htdemucs:    return "htdemucs — drums/bass/other/vocals (fast)"
        case .htdemucs_ft: return "htdemucs_ft — 4 stems, fine-tuned (best quality)"
        case .htdemucs_6s: return "htdemucs_6s — + guitar + piano (6 stems)"
        }
    }
    public var stems: [String] {
        switch self {
        case .htdemucs, .htdemucs_ft: return ["drums", "bass", "other", "vocals"]
        case .htdemucs_6s:            return ["drums", "bass", "other", "vocals", "guitar", "piano"]
        }
    }
    public var isolatesGuitar: Bool { self == .htdemucs_6s }
}

public struct StemResult: Sendable {
    public var stems: [String: URL] = [:]
    public var notes: [String] = []
}

public enum StemError: LocalizedError {
    case pythonNotFound, backendNotAvailable(String), demucsNotInstalled, runFailed(String)
    public var errorDescription: String? {
        switch self {
        case .pythonNotFound:   return "Couldn't find python3. Install Python 3 (python.org or Homebrew)."
        case .backendNotAvailable(let s): return s
        case .demucsNotInstalled: return "No stem-separation backend is available. Install official Demucs (`pip3 install demucs`) or an Apple Silicon MLX/Core ML backend."
        case .runFailed(let s): return "Separation failed: \(s)"
        }
    }
}

public final class StemSplitter {
    public init() {}

    private static let stemLogLock = NSLock()

    private static func stemLogFileURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["LS_STEM_LOG_FILE"], !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: explicit).expandingTildeInPath)
        }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        if FileManager.default.fileExists(atPath: desktop.path) {
            return desktop.appendingPathComponent("lemmingsstudio-stem-debug.log")
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("lemmingsstudio-stem-debug.log")
    }

    private static func stemDebugLog(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[LemmingsStudio StemSplit \(stamp)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        stemLogLock.lock()
        defer { stemLogLock.unlock() }

        // This is intentionally mirrored to stderr so launching
        // LemmingsStudio.app/Contents/MacOS/LemmingsStudio from Terminal shows it live.
        FileHandle.standardError.write(data)
        NSLog("%@", line.trimmingCharacters(in: .newlines))

        guard let url = stemLogFileURL() else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    private static func stemDebugLogMultiline(_ title: String, _ body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for line in trimmed.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            stemDebugLog("\(title): \(line)")
        }
    }

    public static func findPython() -> String? {
        let fm = FileManager.default

        // Prefer a bundled runtime inside LemmingsStudio.app. build.sh writes this
        // when it embeds Python for Demucs/stem splitting.
        if let bundled = bundledPythonPath(), fm.isExecutableFile(atPath: bundled) {
            return bundled
        }

        if let env = ProcessInfo.processInfo.environment["LEMMINGS_BUNDLED_PYTHON"], fm.isExecutableFile(atPath: env) {
            return env
        }

        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        if let p = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return p }
        // fall back to `which`
        let which = Process(); which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["python3"]; let pipe = Pipe(); which.standardOutput = pipe
        try? which.run(); which.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    private static func bundledPythonPath() -> String? {
        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        let marker = resourcesURL.appendingPathComponent("bundled-python-path.txt")
        if let raw = try? String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if raw.hasPrefix("@executable_path") {
                let executableDir = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS").path
                return raw.replacingOccurrences(of: "@executable_path", with: executableDir)
            }
            return raw
        }

        let frameworkPython = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/Python.framework/Versions/Current/bin/python3")
            .path
        if FileManager.default.isExecutableFile(atPath: frameworkPython) { return frameworkPython }

        let resourcePython = resourcesURL.appendingPathComponent("Python/bin/python3").path
        if FileManager.default.isExecutableFile(atPath: resourcePython) { return resourcePython }
        return nil
    }

    public func isAvailable(backend: StemBackend = .auto) async -> Bool {
        switch backend {
        case .auto:
            return await resolveBackend(preferred: .auto) != nil
        case .demucsPyTorch:
            return await officialDemucsAvailable()
        case .demucsMLX:
            if findExecutable(named: "demucs-mlx") != nil { return true }
            if findExecutable(named: "mlx-demucs") != nil { return true }
            if ProcessInfo.processInfo.environment["LEMMINGS_DEMUCS_MLX_BIN"].flatMap({ FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }) != nil { return true }
            return await pythonCanImport("demucs_mlx")
        case .htdemucsCoreML:
            if findExecutable(named: "htdemucs-coreml") != nil { return true }
            if ProcessInfo.processInfo.environment["LEMMINGS_HTDEMUCS_COREML_BIN"].flatMap({ FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }) != nil { return true }
            return await pythonCanImport("htdemucs_coreml")
        }
    }

    private func resolveBackend(preferred: StemBackend) async -> StemBackend? {
        if preferred != .auto { return await isAvailable(backend: preferred) ? preferred : nil }
#if arch(arm64)
        if await isAvailable(backend: .demucsMLX) { return .demucsMLX }
        if await isAvailable(backend: .htdemucsCoreML) { return .htdemucsCoreML }
#endif
        if await isAvailable(backend: .demucsPyTorch) { return .demucsPyTorch }
        return nil
    }

    private func officialDemucsAvailable() async -> Bool {
        guard let py = Self.findPython() else { return false }
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process(); p.executableURL = URL(fileURLWithPath: py)
                p.arguments = ["-c", "import demucs"]
                p.standardError = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice
                do { try p.run(); p.waitUntilExit(); cont.resume(returning: p.terminationStatus == 0) }
                catch { cont.resume(returning: false) }
            }
        }
    }

    private func pythonCanImport(_ module: String) async -> Bool {
        guard let py = Self.findPython() else { return false }
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process(); p.executableURL = URL(fileURLWithPath: py)
                p.arguments = ["-c", "import \(module)"]
                p.standardError = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice
                do { try p.run(); p.waitUntilExit(); cont.resume(returning: p.terminationStatus == 0) }
                catch { cont.resume(returning: false) }
            }
        }
    }

    private func findExecutable(named name: String) -> String? {
        let fm = FileManager.default
        let envKeys = ["LEMMINGS_STEM_BACKEND_BIN", "LEMMINGS_DEMUCS_MLX_BIN", "LEMMINGS_HTDEMUCS_COREML_BIN"]
        for key in envKeys {
            if let value = ProcessInfo.processInfo.environment[key], fm.isExecutableFile(atPath: value), URL(fileURLWithPath: value).lastPathComponent == name || key != "LEMMINGS_STEM_BACKEND_BIN" {
                return value
            }
        }
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("StemBackends/\(name)").path,
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ].compactMap { $0 }
        if let p = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return p }
        let which = Process(); which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [name]
        let pipe = Pipe(); which.standardOutput = pipe; which.standardError = FileHandle.nullDevice
        try? which.run(); which.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    /// Separate `input` into stems. `progress` receives 0…1 parsed from stderr/stdout.
    public func separate(input: URL, model: StemModel,
                         backend preferredBackend: StemBackend = .auto,
                         selectedStems: Set<String>? = nil,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> StemResult {
        Self.stemDebugLog("separate requested input=\(input.path) requestedBackend=\(preferredBackend.rawValue) requestedModel=\(model.rawValue) selectedStems=\((selectedStems ?? Set(model.stems)).sorted().joined(separator: ","))")
        if preferredBackend == .auto {
            let effectiveModel = Self.effectiveModel(for: model, selectedStems: selectedStems, backend: .auto)
            Self.stemDebugLog("auto mode effectiveModel=\(effectiveModel.rawValue)")
            let backends = await autoBackendOrder(for: effectiveModel)
            guard !backends.isEmpty else { throw StemError.demucsNotInstalled }

            var failures: [String] = []
            Self.stemDebugLog("auto backend order=\(backends.map { $0.rawValue }.joined(separator: ","))")
            for backend in backends {
                do {
                    Self.stemDebugLog("trying backend=\(backend.rawValue)")
                    progress(0.02)
                    var result = try await runResolvedBackend(backend, input: input, model: effectiveModel, selectedStems: selectedStems, progress: progress)
                    if effectiveModel != model {
                        result.notes.insert("Requested stems only needed the 4-stem model, so LemmingsStudio used htdemucs instead of fragile htdemucs_6s.", at: 0)
                    }
                    return result
                } catch {
                    Self.stemDebugLog("backend failed backend=\(backend.rawValue) error=\(error.localizedDescription)")
                    failures.append("\(backend.shortLabel): \(error.localizedDescription)")
                    progress(0.0)
                }
            }
            throw StemError.runFailed("Auto tried all available backends and none completed.\n" + failures.joined(separator: "\n\n"))
        }

        guard await isAvailable(backend: preferredBackend) else {
            throw StemError.backendNotAvailable("\(preferredBackend.shortLabel) was selected, but that backend is not available in this build/runtime.")
        }

        let effectiveModel = Self.effectiveModel(for: model, selectedStems: selectedStems, backend: preferredBackend)
        Self.stemDebugLog("manual backend=\(preferredBackend.rawValue) effectiveModel=\(effectiveModel.rawValue)")
        do {
            return try await runResolvedBackend(preferredBackend, input: input, model: effectiveModel, selectedStems: selectedStems, progress: progress)
        } catch {
            Self.stemDebugLog("manual backend failed backend=\(preferredBackend.rawValue) error=\(error.localizedDescription)")
            // MLX/Core ML are nice-to-have fast paths. They are not allowed to strand the user
            // with a mysterious backend error when official Demucs is available, especially for
            // 6-stem or selected-subset jobs where the official backend is the compatibility path.
            if preferredBackend != .demucsPyTorch, await isAvailable(backend: .demucsPyTorch), Self.shouldFallbackToOfficialDemucs(error: error) {
                progress(0.01)
                Self.stemDebugLog("falling back to official Demucs after \(preferredBackend.rawValue) failure")
                var result = try await runOfficialDemucs(input: input, model: effectiveModel, selectedStems: selectedStems, progress: progress, resolvedBackend: .demucsPyTorch)
                result.notes.insert("\(preferredBackend.shortLabel) failed, so LemmingsStudio automatically retried with official Demucs.", at: 0)
                return result
            }
            throw error
        }
    }

    private static func effectiveModel(for requestedModel: StemModel, selectedStems: Set<String>?, backend: StemBackend) -> StemModel {
        // The popup defaults to htdemucs_6s so guitar/piano are visible, but if the user only
        // wants normal 4-stem outputs there is no reason to force fragile 6-stem runners.
        // This avoids needless MLX/Core ML failures for common "vocals only" and "drums only" jobs.
        guard requestedModel == .htdemucs_6s else { return requestedModel }
        let selected = selectedStems ?? Set(requestedModel.stems)
        let needsSixStemTargets = selected.contains("guitar") || selected.contains("piano")
        return needsSixStemTargets ? .htdemucs_6s : .htdemucs
    }

    private static func shouldFallbackToOfficialDemucs(error: Error) -> Bool {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("No Stream(gpu") { return true }
        if text.localizedCaseInsensitiveContains("current thread") { return true }
        if text.localizedCaseInsensitiveContains("htdemucs_6s") { return true }
        if text.localizedCaseInsensitiveContains("unsupported") { return true }
        if text.localizedCaseInsensitiveContains("not found") { return true }
        if text.localizedCaseInsensitiveContains("stem backend exit") { return true }
        return false
    }

    private func autoBackendOrder(for model: StemModel) async -> [StemBackend] {
        var ordered: [StemBackend] = []
#if arch(arm64)
        // MLX is fast when it works, but current demucs-mlx builds can crash with
        // "There is no Stream(gpu, 1) in current thread." Prefer official Demucs in
        // Auto mode now that build.sh pre-caches its weights into the app bundle.
        ordered = [.demucsPyTorch, .demucsMLX, .htdemucsCoreML]
#else
        ordered = [.demucsPyTorch, .demucsMLX, .htdemucsCoreML]
#endif
        var available: [StemBackend] = []
        for backend in ordered {
            if await isAvailable(backend: backend) { available.append(backend) }
        }
        return available
    }

    private func runResolvedBackend(_ backend: StemBackend, input: URL, model: StemModel,
                                    selectedStems: Set<String>?,
                                    progress: @escaping @Sendable (Double) -> Void) async throws -> StemResult {
        switch backend {
        case .demucsPyTorch:
            return try await runOfficialDemucs(input: input, model: model, selectedStems: selectedStems, progress: progress, resolvedBackend: backend)
        case .demucsMLX:
            return try await runMLXDemucs(input: input, model: model, selectedStems: selectedStems, progress: progress)
        case .htdemucsCoreML:
            return try await runCoreMLHTDemucs(input: input, model: model, selectedStems: selectedStems, progress: progress)
        case .auto:
            return try await runOfficialDemucs(input: input, model: model, selectedStems: selectedStems, progress: progress, resolvedBackend: .demucsPyTorch)
        }
    }

    private func runOfficialDemucs(input: URL, model: StemModel,
                                   selectedStems: Set<String>?,
                                   progress: @escaping @Sendable (Double) -> Void,
                                   resolvedBackend: StemBackend) async throws -> StemResult {
        guard let py = Self.findPython() else { throw StemError.pythonNotFound }
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("LemmingsStems-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        // Modern torchaudio routes torchaudio.load through TorchCodec, which we do
        // not bundle — so `python -m demucs <file>` dies with
        // "ModuleNotFoundError: No module named 'torchcodec'" before it can even
        // read the input. We instead launch Demucs through an inline bootstrap that
        // monkeypatches torchaudio.load/save to use soundfile (libsndfile), which
        // reads/writes the WAV files involved here natively. Falls through to plain
        // `-m demucs` semantics either way (soundfile missing → clear message).
        let bootstrap = Self.demucsSoundfileBootstrap
        p.arguments = ["-c", bootstrap, "-n", model.rawValue, "-o", outDir.path, input.path]
        return try await runSeparationProcess(p, input: input, model: model, outDir: outDir, selectedStems: selectedStems, progress: progress, backendNote: "Backend: official Demucs / PyTorch (soundfile I/O).")
    }

    /// Inline Python that patches torchaudio I/O onto soundfile, then runs Demucs.
    /// sys.argv after `-c` is [<flags...>], so we prepend a fake program name.
    private static let demucsSoundfileBootstrap = """
import sys
try:
    import torch, torchaudio, soundfile as _sf
    def _ld(fp, frame_offset=0, num_frames=-1, normalize=True, channels_first=True, format=None, buffer_size=4096, backend=None):
        data, sr = _sf.read(str(fp), dtype='float32', always_2d=True)
        w = torch.from_numpy(data)
        if frame_offset or (num_frames is not None and num_frames > 0):
            end = (frame_offset + num_frames) if (num_frames is not None and num_frames > 0) else None
            w = w[frame_offset:end]
        if channels_first:
            w = w.t().contiguous()
        return w, sr
    def _sv(fp, src, sample_rate, channels_first=True, format=None, encoding=None, bits_per_sample=None, buffer_size=4096, backend=None, compression=None):
        t = src.detach().cpu().float()
        if channels_first:
            t = t.t()
        _sf.write(str(fp), t.contiguous().numpy(), int(sample_rate))
    torchaudio.load = _ld
    torchaudio.save = _sv
    try:
        import demucs.audio as _da
        _da.ta.load = _ld
        _da.ta.save = _sv
    except Exception:
        pass
    sys.stderr.write('[lemmings] torchaudio I/O routed through soundfile (torchcodec bypass)\\n')
except Exception as _e:
    sys.stderr.write('[lemmings] soundfile bypass unavailable (%r); rebuild the app to bundle soundfile\\n' % (_e,))
import runpy
sys.argv = ['demucs'] + sys.argv[1:]
runpy.run_module('demucs', run_name='__main__')
"""

    private func runMLXDemucs(input: URL, model: StemModel,
                              selectedStems: Set<String>?,
                              progress: @escaping @Sendable (Double) -> Void) async throws -> StemResult {
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("LemmingsStems-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let p = Process()
        if let bin = ProcessInfo.processInfo.environment["LEMMINGS_DEMUCS_MLX_BIN"], FileManager.default.isExecutableFile(atPath: bin) {
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["-n", model.rawValue, "-o", outDir.path, input.path]
        } else if let bin = findExecutable(named: "demucs-mlx") ?? findExecutable(named: "mlx-demucs") {
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["-n", model.rawValue, "-o", outDir.path, input.path]
        } else if let py = Self.findPython() {
            p.executableURL = URL(fileURLWithPath: py)
            p.arguments = ["-m", "demucs_mlx", "-n", model.rawValue, "-o", outDir.path, input.path]
        } else {
            throw StemError.backendNotAvailable("MLX Demucs was selected, but no `demucs-mlx`/`mlx-demucs` runner or Python module was found.")
        }
        return try await runSeparationProcess(p, input: input, model: model, outDir: outDir, selectedStems: selectedStems, progress: progress, backendNote: "Backend: MLX Demucs — Apple Silicon accelerated when the installed runner supports it.")
    }

    private func runCoreMLHTDemucs(input: URL, model: StemModel,
                                   selectedStems: Set<String>?,
                                   progress: @escaping @Sendable (Double) -> Void) async throws -> StemResult {
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("LemmingsStems-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        if model == .htdemucs_6s {
            // Continue, but include a disclaimer in the result; many Core ML packages expose only the 4-source HTDemucs model.
        }
        let p = Process()
        if let bin = ProcessInfo.processInfo.environment["LEMMINGS_HTDEMUCS_COREML_BIN"], FileManager.default.isExecutableFile(atPath: bin) {
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["--model", model.rawValue, "--out", outDir.path, input.path]
        } else if let bin = findExecutable(named: "htdemucs-coreml") {
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["--model", model.rawValue, "--out", outDir.path, input.path]
        } else if let py = Self.findPython() {
            p.executableURL = URL(fileURLWithPath: py)
            p.arguments = ["-m", "htdemucs_coreml", "--model", model.rawValue, "--out", outDir.path, input.path]
        } else {
            throw StemError.backendNotAvailable("HTDemucs Core ML was selected, but no `htdemucs-coreml` runner or Python module was found.")
        }
        return try await runSeparationProcess(p, input: input, model: model, outDir: outDir, selectedStems: selectedStems, progress: progress, backendNote: "Backend: experimental HTDemucs Core ML. 6-stem guitar/piano availability depends on the installed package.")
    }

    private func runSeparationProcess(_ p: Process, input: URL, model: StemModel, outDir: URL,
                                      selectedStems: Set<String>?,
                                      progress: @escaping @Sendable (Double) -> Void,
                                      backendNote: String) async throws -> StemResult {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let err = Pipe(); let out = Pipe()
                p.standardError = err; p.standardOutput = out
                var env = Self.stemBackendEnvironment(for: p.executableURL)
                env["PYTHONUNBUFFERED"] = "1"
                env["TOKENIZERS_PARALLELISM"] = "false"
                // MLX occasionally dies with "There is no Stream(gpu, 1) in current thread" in
                // subprocess runners. Keep the environment deterministic; if it still fails,
                // the caller can automatically retry official Demucs.
                if env["MLX_METAL_DEBUG"] == nil { env["MLX_METAL_DEBUG"] = "0" }
                p.environment = env
                let commandLine = ([p.executableURL?.path ?? "<unknown>"] + (p.arguments ?? [])).joined(separator: " ")
                Self.stemDebugLog("launch command=\(commandLine)")
                Self.stemDebugLog("input=\(input.path)")
                Self.stemDebugLog("outputDir=\(outDir.path)")
                Self.stemDebugLog("model=\(model.rawValue) requestedStems=\((selectedStems ?? Set(model.stems)).sorted().joined(separator: ","))")
                Self.stemDebugLog("logFile=\(Self.stemLogFileURL()?.path ?? "<none>")")

                let transcriptLock = NSLock()
                var transcript = ""
                func appendTranscript(_ s: String) {
                    guard !s.isEmpty else { return }
                    transcriptLock.lock()
                    transcript += s
                    if transcript.count > 20_000 { transcript = String(transcript.suffix(20_000)) }
                    transcriptLock.unlock()
                    Self.stemDebugLogMultiline("backend", s)
                    for token in s.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
                        if let pct = token.firstMatchPercent() { progress(pct / 100.0) }
                    }
                }
                let progressReader: (FileHandle) -> Void = { h in
                    let data = h.availableData
                    guard !data.isEmpty else { return }
                    appendTranscript(String(data: data, encoding: .utf8) ?? "")
                }
                err.fileHandleForReading.readabilityHandler = progressReader
                out.fileHandleForReading.readabilityHandler = progressReader
                do {
                    progress(0.03)
                    try p.run(); p.waitUntilExit()
                    err.fileHandleForReading.readabilityHandler = nil
                    out.fileHandleForReading.readabilityHandler = nil
                    appendTranscript(String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
                    appendTranscript(String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")

                    transcriptLock.lock()
                    let finalTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    transcriptLock.unlock()

                    Self.stemDebugLog("process exited status=\(p.terminationStatus)")
                    guard p.terminationStatus == 0 else {
                        let details = Self.failureSummary(exit: p.terminationStatus, command: commandLine, transcript: finalTranscript)
                        Self.stemDebugLogMultiline("failure", details)
                        cont.resume(throwing: StemError.runFailed(details))
                        return
                    }
                    var result = StemResult()
                    let base = input.deletingPathExtension().lastPathComponent
                    let wanted = selectedStems ?? Set(model.stems)
                    let searchRoots = [
                        outDir.appendingPathComponent(model.rawValue).appendingPathComponent(base),
                        outDir.appendingPathComponent(base),
                        outDir
                    ]
                    for stem in model.stems where wanted.contains(stem) {
                        let candidates = searchRoots.flatMap { root in [
                            root.appendingPathComponent("\(stem).wav"),
                            root.appendingPathComponent("\(stem).flac"),
                            root.appendingPathComponent("\(stem).m4a")
                        ] }
                        if let f = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { result.stems[stem] = f }
                    }
                    guard !result.stems.isEmpty else {
                        let roots = searchRoots.map(\.path).joined(separator: "\n")
                        let details = "Backend completed but produced no requested stem files.\nSearched:\n\(roots)\n\nCommand:\n\(commandLine)\n\nBackend output:\n\(finalTranscript.tailForUser())"
                        cont.resume(throwing: StemError.runFailed(details))
                        return
                    }
                    result.notes.append(backendNote)
                    if model.isolatesGuitar { result.notes.append("Guitar + piano requested via htdemucs_6s. If the selected backend only returns 4 stems, switch to official Demucs or an MLX runner with 6-source weights.") }
                    result.notes.append("Saxophone has no dedicated open-source model — the 'other' stem is the closest; a custom-trained Demucs target is the real path.")
                    Self.stemDebugLog("separation succeeded stems=\(result.stems.keys.sorted().joined(separator: ","))")
                    progress(1.0)
                    cont.resume(returning: result)
                } catch {
                    Self.stemDebugLog("process launch/capture error=\(error.localizedDescription)")
                    cont.resume(throwing: StemError.runFailed(error.localizedDescription))
                }
            }
        }
    }

    private static func stemBackendEnvironment(for executableURL: URL?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let fm = FileManager.default
        if let resources = Bundle.main.resourceURL {
            let cacheRoot = resources.appendingPathComponent("StemBackends/ModelCache", isDirectory: true)
            let torchHome = cacheRoot.appendingPathComponent("torch", isDirectory: true)
            env["XDG_CACHE_HOME"] = cacheRoot.path
            env["HF_HOME"] = cacheRoot.appendingPathComponent("huggingface", isDirectory: true).path
            env["HF_HUB_CACHE"] = cacheRoot.appendingPathComponent("huggingface/hub", isDirectory: true).path
            env["MLX_WEIGHTS_CACHE"] = cacheRoot.appendingPathComponent("mlx-weights", isDirectory: true).path
            env["TORCH_HOME"] = torchHome.path
        }
        if env["SSL_CERT_FILE"] == nil || env["REQUESTS_CA_BUNDLE"] == nil {
            if let cert = bundledCertifiPath(executableURL: executableURL), fm.fileExists(atPath: cert) {
                env["SSL_CERT_FILE"] = cert
                env["REQUESTS_CA_BUNDLE"] = cert
                env["CURL_CA_BUNDLE"] = cert
            }
        }
        return env
    }

    private static func bundledCertifiPath(executableURL: URL?) -> String? {
        var candidates: [URL] = []
        if let executableURL {
            let bin = executableURL.deletingLastPathComponent()
            candidates.append(bin.appendingPathComponent("python3"))
            candidates.append(executableURL)
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("PythonVenv/bin/python3"))
        }
        for py in candidates {
            guard FileManager.default.isExecutableFile(atPath: py.path) else { continue }
            let p = Process()
            p.executableURL = py
            p.arguments = ["-c", "import certifi; print(certifi.where())"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do {
                try p.run(); p.waitUntilExit()
                guard p.terminationStatus == 0 else { continue }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty { return path }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func failureSummary(exit: Int32, command: String, transcript: String) -> String {
        let tail = transcript.tailForUser()
        let hint: String
        if transcript.localizedCaseInsensitiveContains("No module named demucs") || transcript.localizedCaseInsensitiveContains("ModuleNotFoundError") {
            hint = "\n\nHint: the selected backend is installed incompletely. Use Auto, or rebuild with the bundled Demucs dependencies enabled."
        } else if transcript.localizedCaseInsensitiveContains("htdemucs_6s") && (transcript.localizedCaseInsensitiveContains("not found") || transcript.localizedCaseInsensitiveContains("unknown") || transcript.localizedCaseInsensitiveContains("unsupported")) {
            hint = "\n\nHint: this backend likely does not support htdemucs_6s. Auto will now try official Demucs first for 6-stem jobs."
        } else if transcript.localizedCaseInsensitiveContains("No Stream(gpu") || transcript.localizedCaseInsensitiveContains("current thread") {
            hint = "\n\nHint: the MLX Demucs runner hit an MLX GPU stream/thread bug. LemmingsStudio will automatically retry official Demucs when it is installed."
        } else if transcript.localizedCaseInsensitiveContains("No such file") || transcript.localizedCaseInsensitiveContains("does not exist") {
            hint = "\n\nHint: the selected clip source may have moved, or the temp rendered clip could not be read."
        } else {
            hint = ""
        }
        return "stem backend exit \(exit)\n\nCommand:\n\(command)\n\nBackend output:\n\(tail)\(hint)"
    }


}

private extension Substring {
    /// Pull a percentage (0…100) out of a tqdm-style token, if present.
    func firstMatchPercent() -> Double? {
        guard let pIdx = firstIndex(of: "%") else { return nil }
        var digits = ""
        var i = pIdx
        while i > startIndex {
            i = index(before: i)
            let c = self[i]
            if c.isNumber || c == "." { digits = String(c) + digits } else { break }
        }
        return Double(digits)
    }
}

private extension String {
    func tailForUser(maxCharacters: Int = 4_000) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "<no backend output captured>" }
        if trimmed.count <= maxCharacters { return trimmed }
        return "…" + trimmed.suffix(maxCharacters)
    }
}
