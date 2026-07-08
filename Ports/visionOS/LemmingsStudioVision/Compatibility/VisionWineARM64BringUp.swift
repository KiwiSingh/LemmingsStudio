import Foundation
import Darwin

enum VisionWineProbePhase: String, Codable, CaseIterable, Identifiable, Sendable {
    case runtimeLayout = "Runtime Layout"
    case architecture = "Architecture"
    case prefix = "Wine Prefix"
    case loader = "Loader"
    case dllSearch = "DLL Search"
    case memoryPolicy = "mmap / Executable Memory"
    case executableSmoke = "Windows ARM64 Smoke Test"
    case vst3Enumeration = "VST3 Enumeration"
    case dspTransport = "DSP Callback Transport"
    case editorBridge = "Editor Surface Bridge"

    var id: String { rawValue }
}

struct VisionWineProbeFinding: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var phase: VisionWineProbePhase
    var passed: Bool
    var headline: String
    var detail: String
    var command: String?
    var exitCode: Int32?
    var timestamp = Date()
}

struct VisionWineBringUpReport: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var candidateName: String
    var runtimeRoot: String
    var startedAt = Date()
    var completedAt: Date?
    var findings: [VisionWineProbeFinding] = []
    var capturedLog = ""

    var passedCount: Int { findings.filter(\.passed).count }
    var failedCount: Int { findings.filter { !$0.passed }.count }
    var summary: String { "\(passedCount) passed • \(failedCount) blocked" }
}

struct VisionWineRuntimeLayout: Sendable {
    var root: URL
    var executable: URL?
    var wineserver: URL?
    var probe: URL?
    var prefix: URL
    var windowsSystem32: URL
    var windowsSysWOW64: URL
    var dllRoots: [URL]
}

extension VisionStudioModel {
    func runWineARM64BringUp(for candidate: VisionCompatibilityCandidate) {
        guard compatibilityLab.gojiraModeEnabled else {
            compatibilityLab.status = "Enable Gojira mode before starting Wine ARM64 bring-up."
            return
        }
        compatibilityLab.status = "Running Wine ARM64 bring-up for \(candidate.displayName)…"
        let state = compatibilityLab
        Task.detached(priority: .userInitiated) {
            let report = WineARM64BringUpRunner.run(candidate: candidate, state: state)
            await MainActor.run {
                self.compatibilityLab.wineReports.insert(report, at: 0)
                self.compatibilityLab.status = "Wine ARM64 bring-up finished for \(candidate.displayName): \(report.summary)."
                self.compatibilityLab.experiments.insert(.init(
                    title: "Wine ARM64 bring-up: \(candidate.displayName)",
                    backend: .experimentalWine,
                    commandPreview: "runtime-layout → arch → prefix → loader → DLL → mmap/RX → smoke → VST3 → DSP → editor",
                    risk: "Sideload-only runtime execution. No project mutation; probe output is captured for diagnosis.",
                    nextStep: report.failedCount == 0 ? "Move to real plugin DSP/editor validation on Vision Pro hardware." : "Open the bring-up report and fix the first blocked phase before repeating later phases."
                ), at: 0)
            }
        }
    }

    func runWineVST3Enumeration(for candidate: VisionCompatibilityCandidate) {
        runWineFocusedProbe(for: candidate, phase: .vst3Enumeration, arguments: ["--list", "--plugin", candidate.pathHint, "--json"])
    }

    func runWineDSPTransportExperiment(for candidate: VisionCompatibilityCandidate) {
        runWineFocusedProbe(for: candidate, phase: .dspTransport, arguments: ["--plugin", candidate.pathHint, "--dsp-smoke", "--block-size", "256", "--sample-rate", "48000", "--blocks", "128", "--transport", "shared-ring-v1"])
    }

    func runWineEditorBridgeExperiment(for candidate: VisionCompatibilityCandidate) {
        runWineFocusedProbe(for: candidate, phase: .editorBridge, arguments: ["--plugin", candidate.pathHint, "--editor", "offscreen", "--surface", "bgra8-shared-buffer", "--input-protocol", "lemmings-pointer-v1", "--frames", "60"])
    }

    private func runWineFocusedProbe(for candidate: VisionCompatibilityCandidate, phase: VisionWineProbePhase, arguments: [String]) {
        compatibilityLab.status = "Running \(phase.rawValue)…"
        let state = compatibilityLab
        Task.detached(priority: .userInitiated) {
            let layout = WineARM64BringUpRunner.resolveLayout(state: state)
            guard let wine = layout.executable, let probe = layout.probe else {
                await MainActor.run { self.compatibilityLab.status = "Wine runtime or vsthost-probe.exe is missing. Run full bring-up first." }
                return
            }
            var env = WineARM64BringUpRunner.environment(layout: layout)
            env["LEMMINGS_PROBE_PHASE"] = phase.rawValue
            let commandArguments = [wine.path, probe.path] + arguments
            let result = CapturedPosixProbe.run(executable: wine.path, arguments: commandArguments, environment: env, timeoutSeconds: 30)
            let finding = VisionWineProbeFinding(phase: phase, passed: result.exitCode == 0 && !result.timedOut, headline: result.exitCode == 0 ? "\(phase.rawValue) completed" : "\(phase.rawValue) blocked", detail: result.output.isEmpty ? result.summary : result.output, command: commandArguments.joined(separator: " "), exitCode: result.exitCode)
            var report = VisionWineBringUpReport(candidateName: candidate.displayName, runtimeRoot: layout.root.path)
            report.findings = [finding]
            report.capturedLog = result.output
            report.completedAt = Date()
            await MainActor.run {
                self.compatibilityLab.wineReports.insert(report, at: 0)
                self.compatibilityLab.status = "\(phase.rawValue): \(finding.passed ? "passed" : "blocked") (exit \(result.exitCode))."
            }
        }
    }
}

enum WineARM64BringUpRunner {
    static func run(candidate: VisionCompatibilityCandidate, state: VisionCompatibilityLabState) -> VisionWineBringUpReport {
        let layout = resolveLayout(state: state)
        var report = VisionWineBringUpReport(candidateName: candidate.displayName, runtimeRoot: layout.root.path)

        func add(_ phase: VisionWineProbePhase, _ passed: Bool, _ headline: String, _ detail: String, command: String? = nil, exitCode: Int32? = nil) {
            report.findings.append(.init(phase: phase, passed: passed, headline: headline, detail: detail, command: command, exitCode: exitCode))
        }

        let fm = FileManager.default
        let runtimeOK = layout.executable != nil && layout.probe != nil
        add(.runtimeLayout, runtimeOK,
            runtimeOK ? "Runtime layout is stageable" : "Runtime layout incomplete",
            runtimeLayoutDetail(layout))
        guard runtimeOK, let wine = layout.executable, let probe = layout.probe else {
            report.completedAt = Date(); return report
        }

        let wineHeader = VisionBinaryHeaderParser.parse(url: wine)
        let wineArchOK = wineHeader.architectures.contains("arm64")
        let pluginHeader = VisionBinaryHeaderParser.parse(url: URL(fileURLWithPath: candidate.pathHint))
        let pluginArchOK = pluginHeader.containerKind.contains("PE") && pluginHeader.architectures.contains("arm64")
        add(.architecture, wineArchOK && pluginArchOK,
            wineArchOK && pluginArchOK ? "ARM64 runtime and PE target confirmed" : "Architecture mismatch or unknown target",
            "Wine: \(wineHeader.summary). Candidate: \(pluginHeader.summary). Wine ARM64 lane requires an arm64 Mach-O runtime and PE/COFF arm64 target.")
        guard wineArchOK && pluginArchOK else { report.completedAt = Date(); return report }

        do {
            try fm.createDirectory(at: layout.prefix, withIntermediateDirectories: true)
            try fm.createDirectory(at: layout.prefix.appendingPathComponent("dosdevices", isDirectory: true), withIntermediateDirectories: true)
            add(.prefix, true, "Wine prefix is writable", "Prefix: \(layout.prefix.path)")
        } catch {
            add(.prefix, false, "Wine prefix cannot be prepared", error.localizedDescription)
            report.completedAt = Date(); return report
        }

        let env = environment(layout: layout)
        let loaderArgs = [wine.path, "--version"]
        let loader = CapturedPosixProbe.run(executable: wine.path, arguments: loaderArgs, environment: env, timeoutSeconds: 12)
        add(.loader, loader.exitCode == 0 && !loader.timedOut,
            loader.exitCode == 0 ? "Wine loader started" : "Wine loader failed",
            loader.output.isEmpty ? loader.summary : loader.output,
            command: loaderArgs.joined(separator: " "), exitCode: loader.exitCode)
        report.capturedLog += "\n[loader]\n\(loader.output)"
        guard loader.exitCode == 0 && !loader.timedOut else { report.completedAt = Date(); return report }

        let existingDLLRoots = layout.dllRoots.filter { fm.fileExists(atPath: $0.path) }
        let dllOK = !existingDLLRoots.isEmpty
        add(.dllSearch, dllOK,
            dllOK ? "DLL search roots found" : "No Wine DLL roots found",
            existingDLLRoots.isEmpty ? "Expected one of: \(layout.dllRoots.map(\.path).joined(separator: ", "))" : "Search roots: \(existingDLLRoots.map(\.path).joined(separator: ", "))\nWINEDLLPATH=\(env["WINEDLLPATH"] ?? "")")
        guard dllOK else { report.completedAt = Date(); return report }

        let memory = memoryPolicyProbe()
        add(.memoryPolicy, memory.passed, memory.passed ? "Memory policy probe passed" : "Executable-memory transition blocked", memory.detail)
        guard memory.passed else { report.completedAt = Date(); return report }

        let smokeArgs = [wine.path, probe.path, "--self-test", "--json"]
        let smoke = CapturedPosixProbe.run(executable: wine.path, arguments: smokeArgs, environment: env, timeoutSeconds: 20)
        add(.executableSmoke, smoke.exitCode == 0 && !smoke.timedOut,
            smoke.exitCode == 0 ? "ARM64 Windows probe started" : "ARM64 Windows probe failed",
            smoke.output.isEmpty ? smoke.summary : smoke.output,
            command: smokeArgs.joined(separator: " "), exitCode: smoke.exitCode)
        report.capturedLog += "\n[smoke]\n\(smoke.output)"
        guard smoke.exitCode == 0 && !smoke.timedOut else { report.completedAt = Date(); return report }

        let enumArgs = [wine.path, probe.path, "--list", "--plugin", candidate.pathHint, "--json"]
        let enumeration = CapturedPosixProbe.run(executable: wine.path, arguments: enumArgs, environment: env, timeoutSeconds: 30)
        add(.vst3Enumeration, enumeration.exitCode == 0 && !enumeration.timedOut,
            enumeration.exitCode == 0 ? "VST3 enumeration completed" : "VST3 enumeration blocked",
            enumeration.output.isEmpty ? enumeration.summary : enumeration.output,
            command: enumArgs.joined(separator: " "), exitCode: enumeration.exitCode)
        report.capturedLog += "\n[vst3]\n\(enumeration.output)"
        guard enumeration.exitCode == 0 && !enumeration.timedOut else { report.completedAt = Date(); return report }

        let dspArgs = [wine.path, probe.path, "--plugin", candidate.pathHint, "--dsp-smoke", "--block-size", "256", "--sample-rate", "48000", "--blocks", "128", "--transport", "shared-ring-v1"]
        let dsp = CapturedPosixProbe.run(executable: wine.path, arguments: dspArgs, environment: env, timeoutSeconds: 30)
        add(.dspTransport, dsp.exitCode == 0 && !dsp.timedOut,
            dsp.exitCode == 0 ? "DSP callback transport completed" : "DSP transport experiment blocked",
            dsp.output.isEmpty ? dsp.summary : dsp.output,
            command: dspArgs.joined(separator: " "), exitCode: dsp.exitCode)
        report.capturedLog += "\n[dsp]\n\(dsp.output)"

        let editorArgs = [wine.path, probe.path, "--plugin", candidate.pathHint, "--editor", "offscreen", "--surface", "bgra8-shared-buffer", "--input-protocol", "lemmings-pointer-v1", "--frames", "60"]
        let editor = CapturedPosixProbe.run(executable: wine.path, arguments: editorArgs, environment: env, timeoutSeconds: 30)
        add(.editorBridge, editor.exitCode == 0 && !editor.timedOut,
            editor.exitCode == 0 ? "Editor surface bridge completed" : "Editor surface bridge blocked",
            editor.output.isEmpty ? editor.summary : editor.output,
            command: editorArgs.joined(separator: " "), exitCode: editor.exitCode)
        report.capturedLog += "\n[editor]\n\(editor.output)"
        report.completedAt = Date()
        return report
    }

    static func resolveLayout(state: VisionCompatibilityLabState) -> VisionWineRuntimeLayout {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = resolveRuntimePath(state.wineRootHint, documents: documents)
        let wineCandidates = [
            root.appendingPathComponent("bin/wine64-arm64"),
            root.appendingPathComponent("bin/wine64"),
            root.appendingPathComponent("wine64-arm64"),
            root.appendingPathComponent("wine64")
        ]
        let serverCandidates = [root.appendingPathComponent("bin/wineserver"), root.appendingPathComponent("wineserver")]
        let probeCandidates = [root.appendingPathComponent("vsthost-probe.exe"), root.appendingPathComponent("tools/vsthost-probe.exe")]
        let prefix = root.appendingPathComponent("prefix", isDirectory: true)
        let system32 = prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = prefix.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)
        let dllRoots = [root.appendingPathComponent("lib/wine/aarch64-windows", isDirectory: true), root.appendingPathComponent("lib64/wine/aarch64-windows", isDirectory: true), system32]
        return .init(root: root,
                     executable: wineCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }),
                     wineserver: serverCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }),
                     probe: probeCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                     prefix: prefix,
                     windowsSystem32: system32,
                     windowsSysWOW64: syswow64,
                     dllRoots: dllRoots)
    }

    static func environment(layout: VisionWineRuntimeLayout) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = layout.prefix.path
        env["WINEARCH"] = "winarm64"
        env["WINEDEBUG"] = "+loaddll,+module,+seh,+virtual"
        env["WINEDLLPATH"] = layout.dllRoots.map(\.path).joined(separator: ":")
        env["LEMMINGS_WINE_RUNTIME_ROOT"] = layout.root.path
        env["LEMMINGS_VSTHOST_TRANSPORT"] = "shared-ring-v1"
        env["LEMMINGS_EDITOR_SURFACE"] = "bgra8-shared-buffer"
        return env
    }

    private static func resolveRuntimePath(_ hint: String, documents: URL) -> URL {
        if hint.hasPrefix("/") { return URL(fileURLWithPath: hint, isDirectory: true) }
        var relative = hint
        if relative.hasPrefix("Documents/") { relative.removeFirst("Documents/".count) }
        return documents.appendingPathComponent(relative, isDirectory: true)
    }

    private static func runtimeLayoutDetail(_ layout: VisionWineRuntimeLayout) -> String {
        [
            "root: \(layout.root.path)",
            "wine: \(layout.executable?.path ?? "MISSING")",
            "wineserver: \(layout.wineserver?.path ?? "optional/not found")",
            "probe: \(layout.probe?.path ?? "MISSING")",
            "prefix: \(layout.prefix.path)"
        ].joined(separator: "\n")
    }

    private static func memoryPolicyProbe() -> (passed: Bool, detail: String) {
        let pageSize = Int(getpagesize())
        guard let ptr = mmap(nil, pageSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0), ptr != MAP_FAILED else {
            return (false, "RW mmap failed with errno \(errno): \(String(cString: strerror(errno))).")
        }
        defer { munmap(ptr, pageSize) }
        memset(ptr, 0xC3, min(pageSize, 16))
        let rx = mprotect(ptr, pageSize, PROT_READ | PROT_EXEC)
        if rx != 0 {
            return (false, "RW→RX mprotect failed with errno \(errno): \(String(cString: strerror(errno))). Wine/JIT-related paths may require different entitlements or a non-JIT strategy.")
        }
        let back = mprotect(ptr, pageSize, PROT_READ | PROT_WRITE)
        return (back == 0, back == 0 ? "Anonymous page successfully transitioned RW→RX→RW without executing generated code." : "RX succeeded but RX→RW restore failed with errno \(errno).")
    }
}

private struct CapturedPosixResult: Sendable {
    var exitCode: Int32
    var output: String
    var timedOut: Bool
    var summary: String
}

private enum CapturedPosixProbe {
    static func run(executable: String, arguments: [String], environment: [String: String], timeoutSeconds: Int) -> CapturedPosixResult {
        let fm = FileManager.default
        let logURL = fm.temporaryDirectory.appendingPathComponent("lemmings-wine-probe-\(UUID().uuidString).log")
        let fd = open(logURL.path, O_CREAT | O_TRUNC | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return .init(exitCode: errno, output: "", timedOut: false, summary: "Unable to open probe log file.") }
        defer { close(fd); try? fm.removeItem(at: logURL) }

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, fd, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, fd, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, fd)
        defer { posix_spawn_file_actions_destroy(&actions) }

        var pid: pid_t = 0
        let argvStorage = arguments.map { strdup($0) }
        var argv = argvStorage + [nil]
        let envStorage = environment.map { strdup("\($0.key)=\($0.value)") }
        var envp = envStorage + [nil]
        defer {
            argvStorage.forEach { free($0) }
            envStorage.forEach { free($0) }
        }

        let spawnCode = executable.withCString { path in
            argv.withUnsafeMutableBufferPointer { argvBuffer in
                envp.withUnsafeMutableBufferPointer { envBuffer in
                    posix_spawn(&pid, path, &actions, nil, argvBuffer.baseAddress, envBuffer.baseAddress)
                }
            }
        }
        guard spawnCode == 0 else {
            return .init(exitCode: spawnCode, output: "posix_spawn failed: \(String(cString: strerror(spawnCode)))", timedOut: false, summary: "Process could not be spawned.")
        }

        let deadline = Date().addingTimeInterval(TimeInterval(max(1, timeoutSeconds)))
        var status: Int32 = 0
        var timedOut = false
        while true {
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid { break }
            if waited == -1 { break }
            if Date() >= deadline {
                timedOut = true
                kill(pid, SIGTERM)
                usleep(250_000)
                if waitpid(pid, &status, WNOHANG) == 0 { kill(pid, SIGKILL) }
                _ = waitpid(pid, &status, 0)
                break
            }
            usleep(100_000)
        }
        fsync(fd)
        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let signal = status & 0x7f
        let code: Int32 = timedOut ? 124 : (signal == 0 ? ((status >> 8) & 0xff) : (128 + signal))
        return .init(exitCode: code, output: String(output.prefix(200_000)), timedOut: timedOut, summary: timedOut ? "Probe timed out after \(timeoutSeconds)s." : (code == 0 ? "Probe completed successfully." : "Probe exited with status \(code)."))
    }
}
