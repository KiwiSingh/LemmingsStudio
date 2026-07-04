import Foundation
#if canImport(Network)
import Network
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Carla/JUCE-style plug-in bridge support.
///
/// LemmingsStudio hosts Audio Units natively where possible. For VST/VST3 and
/// cranky AU vendor editors, keep the heavy/fragile host work across a process
/// boundary, LMMS/Carla-style. The first beta path is intentionally pragmatic:
/// locate a bundled/cached/system Carla.app, optionally vendor-copy an installed
/// copy into Application Support, or start a Homebrew install in Terminal when
/// the user asks the app to prepare Carla automatically.
public enum CarlaBridgeSupport {
    public static var supportRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LemmingsStudio/PluginHosts", isDirectory: true)
    }

    public static var vendoredCarlaURL: URL { supportRoot.appendingPathComponent("Carla.app", isDirectory: true) }

    public static var bundledCarlaURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Helpers/Carla.app", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("Carla.app", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Carla.app", isDirectory: true)
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) && !isLemmingsCLIWrapperApp($0) }
    }

    public static var bundledCarlaExecutableURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Helpers/CarlaFormula/carla"),
            Bundle.main.resourceURL?.appendingPathComponent("Helpers/CarlaFormula/carla-launch"),
            Bundle.main.resourceURL?.appendingPathComponent("Helpers/carla"),
            Bundle.main.resourceURL?.appendingPathComponent("CarlaFormula/carla")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static var bundledCarlaSingleExecutableURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Helpers/CarlaFormula/carla-single"),
            Bundle.main.resourceURL?.appendingPathComponent("Helpers/carla-single"),
            Bundle.main.resourceURL?.appendingPathComponent("CarlaFormula/carla-single")
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static var installedCarlaCandidates: [URL] {
        [
            bundledCarlaURL,
            vendoredCarlaURL,
            URL(fileURLWithPath: "/Applications/Carla.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/KXStudio/Carla.app", isDirectory: true),
            URL(fileURLWithPath: ("~/Applications/Carla.app" as NSString).expandingTildeInPath, isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/Cellar/carla", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/Cellar/carla", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/Caskroom/carla", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/Caskroom/carla", isDirectory: true)
        ].compactMap { $0 }
    }

    public static var installedCarlaExecutableCandidates: [URL] {
        [
            bundledCarlaExecutableURL,
            cachedCarlaExecutableURL,
            URL(fileURLWithPath: "/opt/homebrew/bin/carla"),
            URL(fileURLWithPath: "/usr/local/bin/carla"),
            URL(fileURLWithPath: "/opt/homebrew/Cellar/carla", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/Cellar/carla", isDirectory: true)
        ].compactMap { $0 }
    }

    public static var installedCarlaSingleExecutableCandidates: [URL] {
        [
            bundledCarlaSingleExecutableURL,
            cachedCarlaSingleExecutableURL,
            URL(fileURLWithPath: "/opt/homebrew/bin/carla-single"),
            URL(fileURLWithPath: "/usr/local/bin/carla-single"),
            URL(fileURLWithPath: "/opt/homebrew/Cellar/carla", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/Cellar/carla", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/Caskroom/carla", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/Caskroom/carla", isDirectory: true)
        ].compactMap { $0 }
    }

    public static func locatedCarlaApp() -> URL? {
        let fm = FileManager.default
        for candidate in installedCarlaCandidates {
            if candidate.pathExtension == "app", fm.fileExists(atPath: candidate.path), !isLemmingsCLIWrapperApp(candidate) { return candidate }
            if candidate.lastPathComponent == "carla", let app = findFirstCarlaApp(under: candidate), !isLemmingsCLIWrapperApp(app) { return app }
        }
        return nil
    }

    public static func locatedCarlaExecutable() -> URL? {
        let fm = FileManager.default
        for candidate in installedCarlaExecutableCandidates {
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
            if candidate.lastPathComponent == "carla", let executable = findFirstCarlaExecutable(under: candidate, named: "carla") { return executable }
        }
        return nil
    }

    public static func locatedCarlaSingleExecutable() -> URL? {
        let fm = FileManager.default
        for candidate in installedCarlaSingleExecutableCandidates {
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
            if candidate.lastPathComponent == "carla", let executable = findFirstCarlaExecutable(under: candidate, named: "carla-single") { return executable }
        }
        if let carla = locatedCarlaExecutable() {
            let sibling = carla.deletingLastPathComponent().appendingPathComponent("carla-single")
            if fm.isExecutableFile(atPath: sibling.path) { return sibling }
        }
        for candidate in installedCarlaCandidates where candidate.pathExtension == "app" && fm.fileExists(atPath: candidate.path) {
            for relative in ["Contents/MacOS/carla-single", "Contents/Resources/carla-single", "Contents/MacOS/Carla/carla-single"] {
                let helper = candidate.appendingPathComponent(relative)
                if fm.isExecutableFile(atPath: helper.path) { return helper }
            }
            if let nested = findFirstCarlaExecutable(under: candidate, named: "carla-single") {
                return nested
            }
        }
        for candidate in installedCarlaCandidates where candidate.lastPathComponent == "carla" && fm.fileExists(atPath: candidate.path) {
            if let nested = findFirstCarlaExecutable(under: candidate, named: "carla-single") {
                return nested
            }
        }
        return nil
    }

    private static func findFirstCarlaApp(under root: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        for case let url as URL in e where url.lastPathComponent == "Carla.app" && !isLemmingsCLIWrapperApp(url) { return url }
        return nil
    }

    private static func findFirstCarlaExecutable(under root: URL, named executableName: String) -> URL? {
        guard let e = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isExecutableKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in e where url.lastPathComponent == executableName && FileManager.default.isExecutableFile(atPath: url.path) { return url }
        return nil
    }


    private static func isLemmingsCLIWrapperApp(_ appURL: URL) -> Bool {
        let info = appURL.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: info), let identifier = dict["CFBundleIdentifier"] as? String, identifier == "studio.lemmings.carla.launcher" {
            return true
        }
        let note = appURL.appendingPathComponent("Contents/LEMMINGS_BUNDLE_NOTE.txt")
        if let contents = try? String(contentsOf: note), contents.localizedCaseInsensitiveContains("wrapper app") {
            return true
        }
        return false
    }

    public static func statusLine() -> String {
        if let bundledCarlaURL { return "Bundled Carla bridge ready: \(bundledCarlaURL.path)" }
        if FileManager.default.fileExists(atPath: vendoredCarlaURL.path), !isLemmingsCLIWrapperApp(vendoredCarlaURL) { return "Cached Carla bridge ready: \(vendoredCarlaURL.path)" }
        if let single = locatedCarlaSingleExecutable() { return "Carla single-plugin host ready: \(single.path)" }
        if let app = locatedCarlaApp() { return "System Carla detected, but single-plug-in auto-load helper carla-single was not found: \(app.path)" }
        if let executable = locatedCarlaExecutable() { return "Carla CLI detected; Lemmings will launch it directly as an external bridge: \(executable.path)" }
        if brewExecutable() != nil { return "Carla bridge not installed yet. Homebrew is available; Lemmings can install Carla on request." }
        return "Carla bridge not installed. Install Carla manually or install Homebrew, then use Prepare Carla Bridge."
    }

    @discardableResult
    public static func vendorCopyInstalledCarlaIfPossible() throws -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: vendoredCarlaURL.path) {
            if isLemmingsCLIWrapperApp(vendoredCarlaURL) {
                try? fm.removeItem(at: vendoredCarlaURL)
            } else {
                return vendoredCarlaURL
            }
        }
        try fm.createDirectory(at: supportRoot, withIntermediateDirectories: true)
        if let source = locatedCarlaApp() {
            if source.path == vendoredCarlaURL.path { return source }
            try fm.copyItem(at: source, to: vendoredCarlaURL)
            return vendoredCarlaURL
        }
        if let executable = locatedCarlaExecutable() {
            try cacheCarlaExecutableLauncher(executable)
            return cachedCarlaExecutableURL
        }
        return nil
    }

    private static var cachedCarlaExecutableURL: URL { supportRoot.appendingPathComponent("CarlaFormula/carla", isDirectory: false) }
    private static var cachedCarlaSingleExecutableURL: URL { supportRoot.appendingPathComponent("CarlaFormula/carla-single", isDirectory: false) }


    // MARK: - Agent bridge session state

    private static let agentPortDefaultsPrefix = "CarlaAgentBridgePort."

    private static func agentKey(pluginName: String?, pluginPath: String?) -> String {
        let raw = "\(pluginName ?? "plugin")|\(pluginPath ?? "no-path")"
        return raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(abs(raw.hashValue))
    }

    private static func stableAgentPort(pluginName: String?, pluginPath: String?) -> Int {
        let key = agentKey(pluginName: pluginName, pluginPath: pluginPath)
        let defaultsKey = agentPortDefaultsPrefix + key
        let existing = UserDefaults.standard.integer(forKey: defaultsKey)
        if existing >= 19000 && existing <= 39000 { return existing }
        let seed = abs((pluginName ?? "plugin").hashValue ^ (pluginPath ?? "path").hashValue)
        let port = 19000 + (seed % 12000)
        UserDefaults.standard.set(port, forKey: defaultsKey)
        return port
    }

    public static func agentBridgePort(pluginName: String?, pluginPath: String?) -> Int {
        stableAgentPort(pluginName: pluginName, pluginPath: pluginPath)
    }

    public static func agenticParameters(for pluginName: String?) -> [PluginParam] {
        var params: [PluginParam] = [
            PluginParam(id: "macro_1", name: "Macro 1", min: 0, max: 1),
            PluginParam(id: "macro_2", name: "Macro 2", min: 0, max: 1),
            PluginParam(id: "macro_3", name: "Macro 3", min: 0, max: 1),
            PluginParam(id: "macro_4", name: "Macro 4", min: 0, max: 1),
            PluginParam(id: "macro_5", name: "Macro 5", min: 0, max: 1),
            PluginParam(id: "macro_6", name: "Macro 6", min: 0, max: 1),
            PluginParam(id: "macro_7", name: "Macro 7", min: 0, max: 1),
            PluginParam(id: "macro_8", name: "Macro 8", min: 0, max: 1)
        ]
        for i in 0..<64 { params.append(PluginParam(id: "param_\(i)", name: "Carla Param \(i)", min: 0, max: 1)) }
        return params
    }

    @discardableResult
    public static func applyAgenticParameters(pluginName: String?, pluginPath: String?, format: PluginFormat?, params: [String: Double]) -> String {
        let port = stableAgentPort(pluginName: pluginName, pluginPath: pluginPath)
        var sent = 0
        var skipped: [String] = []
        for (key, rawValue) in params.sorted(by: { $0.key < $1.key }) {
            guard let index = parameterIndex(from: key) else { skipped.append(key); continue }
            let value = max(0.0, min(1.0, rawValue))
            sendOSCParameterValue(port: port, pluginIndex: 0, parameterIndex: index, value: value)
            sent += 1
        }
        let url = writeAgentHandoff(pluginName: pluginName, pluginPath: pluginPath, format: format, port: port, params: params, skipped: skipped)
        var message = "Sent \(sent) Carla OSC parameter update(s) to \(pluginName ?? "bridged plug-in") on UDP port \(port)."
        if !skipped.isEmpty { message += " Skipped unnamed controls: \(skipped.prefix(6).joined(separator: ", "))\(skipped.count > 6 ? "…" : "")." }
        if let url { message += " Handoff: \(url.path)" }
        return message
    }

    private static func parameterIndex(from key: String) -> Int? {
        let lowered = key.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let macro = lowered.wholeNumber(afterPrefixes: ["macro_", "macro ", "m"]) { return max(0, min(63, macro - 1)) }
        if let index = lowered.wholeNumber(afterPrefixes: ["param_", "parameter_", "parameter ", "index_", "index ", "p"]) { return max(0, min(2047, index)) }
        if let direct = Int(lowered) { return max(0, min(2047, direct)) }
        return nil
    }

    private static func writeAgentHandoff(pluginName: String?, pluginPath: String?, format: PluginFormat?, port: Int, params: [String: Double], skipped: [String]) -> URL? {
        let dir = supportRoot.appendingPathComponent("AgentHandoffs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = (pluginName ?? "CarlaPlugin").replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent("\(safeName)-latest.json")
        let object: [String: Any] = [
            "pluginName": pluginName ?? "",
            "pluginPath": pluginPath ?? "",
            "format": format?.rawValue ?? "",
            "oscUDPPort": port,
            "carlaPluginIndex": 0,
            "params": params,
            "skippedUnnamedControls": skipped,
            "note": "LemmingsStudio sends numeric Carla parameters over OSC using /set_parameter_value. Use macro_1..macro_8 or param_0..param_63 for agent-safe VST/VST3 control."
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        try? data.write(to: url)
        return url
    }

    private static func oscString(_ string: String) -> Data {
        var data = Data(string.utf8)
        data.append(0)
        while data.count % 4 != 0 { data.append(0) }
        return data
    }

    private static func oscInt32(_ value: Int32) -> Data {
        var v = value.bigEndian
        return Data(bytes: &v, count: MemoryLayout<Int32>.size)
    }

    private static func oscFloat32(_ value: Float) -> Data {
        var bits = value.bitPattern.bigEndian
        return Data(bytes: &bits, count: MemoryLayout<UInt32>.size)
    }

    private static func oscMessage(address: String, ints: [Int32], floats: [Float]) -> Data {
        var data = Data()
        data.append(oscString(address))
        data.append(oscString("," + String(repeating: "i", count: ints.count) + String(repeating: "f", count: floats.count)))
        for i in ints { data.append(oscInt32(i)) }
        for f in floats { data.append(oscFloat32(f)) }
        return data
    }

    private static func sendOSCParameterValue(port: Int, pluginIndex: Int, parameterIndex: Int, value: Double) {
        #if canImport(Network)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(max(1, min(65535, port)))) else { return }
        let connection = NWConnection(host: "127.0.0.1", port: nwPort, using: .udp)
        let payload = oscMessage(address: "/set_parameter_value", ints: [Int32(pluginIndex), Int32(parameterIndex)], floats: [Float(value)])
        connection.start(queue: .global(qos: .utility))
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
        #endif
    }

    #if canImport(AppKit)
    @MainActor private static var launchedCarlaProcesses: [Process] = []
    #endif

    private static func cacheCarlaExecutableLauncher(_ executable: URL) throws {
        let fm = FileManager.default
        let dir = cachedCarlaExecutableURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let launcher = """
        #!/usr/bin/env bash
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        if [[ -x "\(executable.path)" ]]; then
          exec "\(executable.path)" "$@"
        fi
        if command -v carla >/dev/null 2>&1; then
          exec carla "$@"
        fi
        exit 127
        """
        try launcher.write(to: cachedCarlaExecutableURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cachedCarlaExecutableURL.path)

        let siblingSingle = executable.deletingLastPathComponent().appendingPathComponent("carla-single")
        if fm.isExecutableFile(atPath: siblingSingle.path) {
            let singleLauncher = """
            #!/usr/bin/env bash
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            if [[ -x "\(siblingSingle.path)" ]]; then
              exec "\(siblingSingle.path)" "$@"
            fi
            if command -v carla-single >/dev/null 2>&1; then
              exec carla-single "$@"
            fi
            exit 127
            """
            try singleLauncher.write(to: cachedCarlaSingleExecutableURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cachedCarlaSingleExecutableURL.path)
        }
    }

    public static func brewExecutable() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where FileManager.default.isExecutableFile(atPath: path) { return path }
        return nil
    }

    #if canImport(AppKit)
    @MainActor
    public static func prepareBridge(allowInstall: Bool, completion: @escaping (String) -> Void) {
        do {
            if let copied = try vendorCopyInstalledCarlaIfPossible() {
                completion("Carla bridge bundled for LemmingsStudio: \(copied.path)")
                return
            }
        } catch {
            completion("Could not cache/bundle Carla.app: \(error.localizedDescription)")
            return
        }
        guard allowInstall else { completion(statusLine()); return }
        guard let brew = brewExecutable() else {
            completion("Carla is not installed and Homebrew was not found. Install Carla.app manually, then press Prepare Carla Bridge again.")
            return
        }
        let cliLauncher = cachedCarlaExecutableURL
        let script = """
        \(brew.shellQuoted) install carla
        mkdir -p \(supportRoot.path.shellQuoted)
        rm -rf \(vendoredCarlaURL.path.shellQuoted)
        if [ -d /Applications/Carla.app ]; then
          ditto /Applications/Carla.app \(vendoredCarlaURL.path.shellQuoted)
        elif command -v carla >/dev/null 2>&1; then
          CARLA_BIN=$(command -v carla)
          mkdir -p \(cliLauncher.deletingLastPathComponent().path.shellQuoted)
          cat > \(cliLauncher.path.shellQuoted) <<SH
        #!/usr/bin/env bash
        export PATH="/opt/homebrew/bin:/usr/local/bin:\\$PATH"
        exec "$CARLA_BIN"
        SH
          chmod +x \(cliLauncher.path.shellQuoted)
        fi
        echo
        echo 'Carla bridge prep finished. You can close this window.'
        """
        runTerminalScript(script)
        completion("Started Homebrew Carla install in Terminal. When it finishes, press Scan/Prepare again; Lemmings will cache Carla.app or a direct CLI launcher for bridge launches.")
    }

    @MainActor
    public static func openBridge(forPluginName pluginName: String? = nil, pluginPath: String? = nil, format: PluginFormat? = nil, completion: @escaping (String) -> Void) {
        if let pluginPath, let format, let single = locatedCarlaSingleExecutable() {
            launchSinglePluginHost(single, pluginName: pluginName, pluginPath: pluginPath, format: format, completion: completion)
            return
        }

        if let pluginPath, let format, locatedCarlaSingleExecutable() == nil {
            // Main Carla cannot auto-load a .vst3 by receiving it as argv; it treats
            // argv as project files. Opening main Carla here creates exactly the
            // confusing failure mode buildfix82 is meant to prevent: an empty Carla
            // window with no Splice Sounds plug-in loaded. For plug-in-specific bridge
            // launches, fail loudly unless the single-plug-in helper exists.
            let hostStatus = statusLine()
            completion("Could not auto-load \(pluginName ?? "plug-in") in Carla: carla-single was not found. \(hostStatus). Install a Carla build that ships carla-single, run `brew install carla`, or set CARLA_SINGLE_BIN=/path/to/carla-single before rebuilding. Plug-in path: \(pluginPath) (\(format.rawValue))")
            return
        }

        openMainCarla(pluginName: pluginName, pluginPath: pluginPath, format: format, completion: completion)
    }

    @MainActor
    private static func launchSinglePluginHost(_ executable: URL, pluginName: String?, pluginPath: String, format: PluginFormat, completion: @escaping (String) -> Void) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: pluginPath, isDirectory: &isDirectory), fm.isReadableFile(atPath: pluginPath) || isDirectory.boolValue else {
            completion("Could not open Carla bridge for \(pluginName ?? "plug-in"): plug-in bundle is not readable at \(pluginPath)")
            return
        }

        let logURL = carlaBridgeLogURL(pluginName: pluginName, pluginPath: pluginPath)
        try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = executable
        // carla-single's documented shape is:
        //   carla-single [arch] [format] [filename/uri] [label] [uniqueId]
        // Passing the explicit native arch avoids Homebrew/Python wrapper ambiguity,
        // while the label makes the spawned bridge/window easier to identify.
        process.arguments = ["native", carlaSingleType(for: format), pluginPath, safeBridgeLabel(pluginName: pluginName, pluginPath: pluginPath)]
        process.currentDirectoryURL = executable.deletingLastPathComponent()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let agentPort = stableAgentPort(pluginName: pluginName, pluginPath: pluginPath)
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "CARLA_BRIDGE_UI": "1",
            "CARLA_BRIDGE_PLUGIN_BINARY_TYPE": "native",
            "CARLA_OSC_UDP_PORT": String(agentPort),
            "CARLA_CLIENT_NAME": safeBridgeLabel(pluginName: pluginName, pluginPath: pluginPath)
        ]) { current, _ in current }
        do {
            try process.run()
            retainAndFocus(process)
            var message = "Opened \(pluginName ?? "plug-in") in Carla single-plug-in bridge"
            message += " (\(format.rawValue))"
            message += " · agent OSC UDP \(agentPort)"
            message += " · \(pluginPath)"
            message += " · log: \(logURL.path)"
            completion(message)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let out = String(data: outPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
                appendBridgeLog(logURL, executable: executable, arguments: process.arguments ?? [], stdout: out, stderr: err, terminationStatus: process.isRunning ? nil : process.terminationStatus)
                if process.isRunning {
                    focusProcess(process)
                } else {
                    openMainCarla(pluginName: pluginName, pluginPath: pluginPath, format: format) { fallbackStatus in
                        let diagnostic = [err, out].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                        let short = diagnostic.isEmpty ? "carla-single exited before showing a window" : diagnostic.prefix(240)
                        completion("Carla single bridge exited before a plug-in window appeared: \(short). \(fallbackStatus)")
                    }
                }
            }
        } catch {
            completion("Could not launch Carla single-plug-in bridge: \(error.localizedDescription)")
        }
    }


    private static func safeBridgeLabel(pluginName: String?, pluginPath: String?) -> String {
        let base = pluginName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? pluginPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            ?? "Lemmings Plugin"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_()."))
        let cleaned = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.nilIfEmpty ?? "Lemmings Plugin"
    }

    private static func carlaBridgeLogURL(pluginName: String?, pluginPath: String?) -> URL {
        let label = safeBridgeLabel(pluginName: pluginName, pluginPath: pluginPath)
            .replacingOccurrences(of: " ", with: "_")
        return supportRoot.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("CarlaBridge-\(label).log", isDirectory: false)
    }

    private static func appendBridgeLog(_ url: URL, executable: URL, arguments: [String], stdout: String, stderr: String, terminationStatus: Int32?) {
        var text = "\n--- \(Date()) ---\n"
        text += "executable: \(executable.path)\n"
        text += "arguments: \(arguments.joined(separator: " | "))\n"
        if let terminationStatus { text += "terminationStatus: \(terminationStatus)\n" }
        if !stdout.isEmpty { text += "stdout:\n\(stdout)\n" }
        if !stderr.isEmpty { text += "stderr:\n\(stderr)\n" }
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    @MainActor
    private static func openMainCarla(pluginName: String?, pluginPath: String?, format: PluginFormat?, completion: @escaping (String) -> Void) {
        if let carla = locatedCarlaApp() {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.arguments = []
            NSWorkspace.shared.openApplication(at: carla, configuration: config) { app, error in
                DispatchQueue.main.async {
                    if let error { completion("Could not open Carla bridge: \(error.localizedDescription)"); return }
                    app?.activate(options: [.activateIgnoringOtherApps])
                    var message = "Opened Carla bridge"
                    if let pluginName { message += " for \(pluginName)" }
                    if let format { message += " (\(format.rawValue))" }
                    if let pluginPath { message += " · \(pluginPath)" }
                    completion(message)
                }
            }
            return
        }

        if let executable = locatedCarlaExecutable() {
            let process = Process()
            process.executableURL = executable
            process.arguments = []
            process.environment = ProcessInfo.processInfo.environment.merging(["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]) { current, _ in current }
            do {
                try process.run()
                retainAndFocus(process)
                var message = "Launched Carla CLI bridge"
                if let pluginName { message += " for \(pluginName)" }
                if let format { message += " (\(format.rawValue))" }
                if let pluginPath { message += " · \(pluginPath)" }
                completion(message)
            } catch {
                completion("Could not launch Carla CLI bridge: \(error.localizedDescription)")
            }
            return
        }

        prepareBridge(allowInstall: true, completion: completion)
    }

    private static func carlaSingleType(for format: PluginFormat) -> String {
        switch format {
        case .vst3: return "vst3"
        case .vst: return "vst"
        case .audioUnit: return "au"
        }
    }

    @MainActor
    private static func retainAndFocus(_ process: Process) {
        launchedCarlaProcesses.append(process)
        focusProcess(process)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focusProcess(process) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { focusProcess(process) }
        process.terminationHandler = { terminated in
            Task { @MainActor in
                launchedCarlaProcesses.removeAll { $0 === terminated }
            }
        }
    }

    @MainActor
    private static func focusProcess(_ process: Process) {
        guard process.isRunning else { return }
        if let app = NSRunningApplication(processIdentifier: process.processIdentifier) {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }

    private static func runTerminalScript(_ script: String) {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "tell application \"Terminal\" to do script \"\(escaped)\"\ntell application \"Terminal\" to activate"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        try? process.run()
    }
    #endif
}

private extension String {
    var shellQuoted: String { "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}


private extension String {
    func wholeNumber(afterPrefixes prefixes: [String]) -> Int? {
        for prefix in prefixes where hasPrefix(prefix) {
            let rest = String(dropFirst(prefix.count))
            if let value = Int(rest.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
        }
        return nil
    }
}
