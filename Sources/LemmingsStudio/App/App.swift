import SwiftUI
import AppKit
import AVFoundation
import AVKit
import Observation
import CryptoKit
import Security
import UniformTypeIdentifiers
import Network
import CoreServices
import AuthenticationServices
import AudioToolbox
import CoreAudioKit
import WebKit


final class LemmingsOAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? NSWindow()
    }
}

enum GeneratorLaunchMode: String, CaseIterable, Identifiable {
    case midiClip = "MIDI Clip"
    case stepSequence = "Step Sequence"
    case deviceOnly = "Device Only"
    var id: String { rawValue }
}

struct GeneralChatMessage: Identifiable, Hashable {
    let id: UUID
    var role: String
    var text: String

    init(id: UUID = UUID(), role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}



private enum LemmingsLaunchServicesRegistrar {
    @discardableResult
    static func registerCurrentBundleForSpliceCallbacks() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let bundleURL = Bundle.main.bundleURL as CFURL
        let registerStatus = LSRegisterURL(bundleURL, true)
        let handlerStatus = LSSetDefaultHandlerForURLScheme("lemmingsstudio" as CFString, bundleID as CFString)
        return registerStatus == noErr && handlerStatus == noErr
    }
}

final class SpliceOAuthLoopbackServer {
    private var listener: NWListener?
    private var activePort: UInt16?
    private static let activePortLock = NSLock()
    private static var processActivePorts = Set<UInt16>()
    private let queue = DispatchQueue(label: "LemmingsStudio.SpliceOAuthLoopback")
    private let onCallback: @Sendable (URL) -> Void

    init(onCallback: @escaping @Sendable (URL) -> Void) {
        self.onCallback = onCallback
    }

    func start(preferredPorts: ClosedRange<UInt16> = 53682...53692) throws -> URL {
        stop()
        var lastError: Error?
        for rawPort in preferredPorts {
            guard let port = NWEndpoint.Port(rawValue: rawPort) else { continue }
            do {
                let listener = try NWListener(using: .tcp, on: port)
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: queue)
                self.listener = listener
                self.activePort = rawPort
                Self.activePortLock.lock()
                Self.processActivePorts.insert(rawPort)
                Self.activePortLock.unlock()
                return URL(string: "http://127.0.0.1:\(rawPort)/splice-oauth")!
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? SpliceError.badResponse("No localhost callback port was available.")
    }

    func stop() {
        if let activePort {
            Self.activePortLock.lock()
            Self.processActivePorts.remove(activePort)
            Self.activePortLock.unlock()
        }
        activePort = nil
        listener?.cancel()
        listener = nil
    }

    static func forwardCallbackToRunningInstance(_ url: URL, ports: ClosedRange<UInt16> = 53682...53692) -> Bool {
        guard url.scheme == "lemmingsstudio", url.host == "splice-oauth" || url.path.contains("splice-oauth") else { return false }
        activePortLock.lock()
        let localPorts = processActivePorts
        activePortLock.unlock()

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        for rawPort in ports where !localPorts.contains(rawPort) {
            var comps = URLComponents()
            comps.scheme = "http"
            comps.host = "127.0.0.1"
            comps.port = Int(rawPort)
            comps.path = "/splice-oauth"
            comps.percentEncodedQuery = query
            guard let target = comps.url else { continue }
            var request = URLRequest(url: target, timeoutInterval: 0.45)
            request.httpMethod = "GET"
            let semaphore = DispatchSemaphore(value: 0)
            var ok = false
            URLSession.shared.dataTask(with: request) { _, response, _ in
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) { ok = true }
                semaphore.signal()
            }.resume()
            _ = semaphore.wait(timeout: .now() + 0.55)
            if ok { return true }
        }
        return false
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            defer { connection.cancel() }
            guard let data, let request = String(data: data, encoding: .utf8) else { return }
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else { self.respond(connection, status: "400 Bad Request", body: "Bad OAuth callback."); return }
            let target = String(parts[1])
            guard let url = URL(string: "http://127.0.0.1\(target)") else {
                self.respond(connection, status: "400 Bad Request", body: "Invalid OAuth callback.")
                return
            }
            self.respond(connection, status: "200 OK", body: "Splice login received. You can return to LemmingsStudio.")
            self.onCallback(url)
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let html = """
        <!doctype html><html><head><meta charset=\"utf-8\"><title>LemmingsStudio Splice Login</title></head><body style=\"font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;background:#111;color:#eee\"><h2>Splice login received</h2><p>You can return to LemmingsStudio.</p><script>setTimeout(function(){window.close();}, 900);</script></body></html>
        """
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
    }
}

@main
struct LemmingsStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Lemmings Studio") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear {
                    appState.engine.start()
                    appState.rebuildTempoMap()
                    DesktopPluginBridgeServer.shared.start()
                    StartupSound.shared.play()
                }
                .onOpenURL { url in
                    Task { await appState.handleSpliceOAuthCallback(url) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .lemmingsStudioOpenURL)) { note in
                    guard let url = note.object as? URL else { return }
                    Task { await appState.handleSpliceOAuthCallback(url) }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { appState.newProject() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open Project…") { appState.openProject() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("Save Project") { appState.saveProject() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save Project As…") { appState.saveProjectAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Menu("Export Audio") {
                    ForEach(ExportFormat.allCases) { fmt in
                        Button("Export \(fmt.rawValue)…") { appState.export(format: fmt) }
                    }
                }
                Button("Export WAV…") { appState.export(format: .wav) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Host Mode") {
                Button("Start Integrated Host Mode") { DesktopPluginBridgeServer.shared.start() }
                Button("Stop Integrated Host Mode") { DesktopPluginBridgeServer.shared.stop() }
                Divider()
                Button("Show Host Mode Status & Pairing Code") { DesktopPluginBridgeServer.shared.showHostModeStatus() }
            }
            CommandMenu("Export") {
                ForEach(ExportFormat.allCases) { fmt in
                    Button("Export \(fmt.rawValue)…") { appState.export(format: fmt) }
                }
                Divider()
                Button("Show Studio Export Panel") {
                    appState.inspector = .studio
                }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { appState.undoLastAction() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { appState.redoLastAction() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Lemmings") {
                Button("Play/Pause") { appState.togglePlay() }
                Button("Delete Selected Item") { appState.deleteSelectedItem() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(appState.selectedTrack == nil && appState.selectedClipID == nil && appState.selectedAudioClipID == nil)
                Button("Copy Clip") { appState.copySelectedClipToClipboard() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(appState.selectedClipID == nil && appState.selectedAudioClipID == nil)
                Button("Paste Clip") { appState.pasteClipToSelectedTrack() }
                    .keyboardShortcut("v", modifiers: .command)
                    .disabled(!appState.canPasteArrangementClip)
                Button("Split Clip at Playhead") { appState.splitSelectedClipAtPlayhead() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(appState.selectedClipID == nil && appState.selectedAudioClipID == nil)
                Divider()
                Button("New Sequencer Track") { appState.createSequencerTrack() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("New Bhangra Architect") { appState.createBhangraArchitectTrack() }
                Button("New 2C Guaracha Device") { appState.create2CTrack() }
                Button("New Bailaton Device") { appState.createBailatonTrack() }
                Button("New Dubstep Wrangler") { appState.createDubstepWranglerTrack() }
                Button("New Oscillatron Track") { appState.addTrack(kind: .oscillatron) }
                Button("New LemmingBass Track") { appState.addTrack(kind: .lemmingBass) }
                Divider()
                Button("Quantize Selected Clip") { appState.quantizeSelectedClip() }
                    .keyboardShortcut("u", modifiers: .command)
                Button("Toggle Metronome") { appState.toggleMetronome() }
                    .keyboardShortcut("m", modifiers: .command)
                Button("Toggle Clip Active") { appState.toggleSelectedClipActive() }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Cycle View") { appState.cycleWorkspace() }
                    .keyboardShortcut("\t", modifiers: [])
                Divider()
                Button("Install/Check Homebrew + Ollama") { appState.bootstrapHomebrewAndOllama() }
                Button("Duplicate Selected Track") { appState.duplicateSelectedTrack() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Group Selected Tracks") { appState.groupSelectedTracks() }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Ungroup Selected Tracks") { appState.ungroupSelectedTracks() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Rescan Plug-ins") { appState.scanPlugins() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Rebuild Audio Engine") { appState.engine.rebuild() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            LemmingsSettingsView()
                .environment(appState)
                .frame(width: 720, height: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var globalShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = LemmingsLaunchServicesRegistrar.registerCurrentBundleForSpliceCallbacks()
        UserDefaults.standard.set(false, forKey: "LemmingsStudio.ProtectedTextEntryActive")
        installGlobalDAWShortcutMonitor()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    deinit {
        if let globalShortcutMonitor { NSEvent.removeMonitor(globalShortcutMonitor) }
    }

    private func installGlobalDAWShortcutMonitor() {
        guard globalShortcutMonitor == nil else { return }
        globalShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let noModifiers = flags.isEmpty

            if event.keyCode == 48 {
                let disallowedFlags: NSEvent.ModifierFlags = [.command, .option, .control]
                guard flags.intersection(disallowedFlags).isEmpty else { return event }
                let shiftTab = flags.contains(.shift)

                // Tab is a DAW-level workspace switch. Capture it before AppKit's
                // NSTextField/NSTextView field editor can convert it into focus
                // traversal or a literal tab. Do not hijack vendor/plugin/Splice
                // windows, sheets, or secondary app surfaces.
                guard Self.shouldRouteMainWindowDAWShortcut(event) else { return event }

                NotificationCenter.default.post(
                    name: .lemmingsStudioCycleWorkspaceFromGlobalTab,
                    object: nil,
                    userInfo: ["reverse": shiftTab]
                )
                return nil
            }

            if (event.keyCode == 51 || event.keyCode == 117) && noModifiers {
                // Backspace/Delete is an Arrangement edit command only. It must
                // not leak into Splice search, browser panels, plug-in editors,
                // sheets, or non-Arrangement workspaces. Tempo fields in the
                // Arrangement can still yield to clip/track deletion, matching
                // DAW behavior, but normal search/text contexts keep Backspace.
                guard Self.shouldRouteMainWindowArrangementDelete(event) else { return event }
                NotificationCenter.default.post(name: .lemmingsStudioDeleteSelectionFromGlobalKey, object: nil)
                return nil
            }

            return event
        }
    }

    private static func shouldRouteMainWindowDAWShortcut(_ event: NSEvent) -> Bool {
        guard let window = event.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        if let main = NSApp.mainWindow, window !== main { return false }
        if isProtectedWindowTitle(window.title) { return false }
        if window.attachedSheet != nil { return false }
        return true
    }

    private static func shouldRouteMainWindowArrangementDelete(_ event: NSEvent) -> Bool {
        guard shouldRouteMainWindowDAWShortcut(event) else { return false }
        guard UserDefaults.standard.string(forKey: "LemmingsStudio.ActiveWorkspace") == WorkspaceTab.arrangement.rawValue else { return false }
        guard UserDefaults.standard.bool(forKey: "LemmingsStudio.ProtectedTextEntryActive") == false else { return false }
        guard let window = event.window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        guard let responder = window.firstResponder else { return true }

        // Delete/Backspace must be an Arrangement editing command, not a global
        // text-editing override. SwiftUI multiline TextField/SecureField focus is
        // represented by AppKit's field editor (usually NSTextView) even when the
        // visible control is the AI prompt, chat box, search field, API-key field,
        // or models-directory field. If anything text-editable owns focus, let it
        // receive Backspace normally.
        if isFocusedTextEntryResponder(responder) { return false }

        // Embedded Splice/browser/search fields live inside the main window, so
        // window-title checks are not enough. Walk the responder/view hierarchy
        // and back off when the focused editor belongs to a protected surface.
        if viewHierarchyContainsProtectedEditor(from: responder) { return false }
        return true
    }

    private static func isFocusedTextEntryResponder(_ responder: NSResponder) -> Bool {
        var current: NSResponder? = responder
        while let node = current {
            if node is NSTextView || node is NSTextField { return true }
            if let control = node as? NSControl, control.currentEditor() != nil { return true }
            let className = String(describing: type(of: node)).lowercased()
            if className.contains("textfield") || className.contains("textview") || className.contains("fieldeditor") || className.contains("securefield") {
                return true
            }
            if let view = node as? NSView {
                current = view.superview ?? view.nextResponder
            } else {
                current = node.nextResponder
            }
        }
        return false
    }

    private static func isProtectedWindowTitle(_ title: String) -> Bool {
        let text = title.lowercased()
        return text.contains("splice") || text.contains("carla") || text.contains("bridge") || text.contains("plug-in") || text.contains("plugin")
    }

    private static func viewHierarchyContainsProtectedEditor(from responder: NSResponder) -> Bool {
        var current: NSResponder? = responder
        while let node = current {
            if node is WKWebView { return true }
            let className = String(describing: type(of: node)).lowercased()
            if className.contains("wk") || className.contains("webview") || className.contains("splice") || className.contains("auv") || className.contains("auview") {
                return true
            }
            if let view = node as? NSView {
                if containsProtectedSubview(view) { return true }
                current = view.superview ?? view.nextResponder
            } else {
                current = node.nextResponder
            }
        }
        return false
    }

    private static func containsProtectedSubview(_ view: NSView) -> Bool {
        if view is WKWebView { return true }
        let name = String(describing: type(of: view)).lowercased()
        if name.contains("wk") || name.contains("webview") || name.contains("splice") || name.contains("auv") || name.contains("auview") {
            return true
        }
        for child in view.subviews {
            if containsProtectedSubview(child) { return true }
        }
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        var forwardedToPrimary = false
        for url in urls {
            if SpliceOAuthLoopbackServer.forwardCallbackToRunningInstance(url) {
                forwardedToPrimary = true
                continue
            }
            NotificationCenter.default.post(name: .lemmingsStudioOpenURL, object: url)
        }
        if forwardedToPrimary {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if application.windows.count <= 1 { application.terminate(nil) }
            }
        } else {
            application.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first?.makeKeyAndOrderFront(nil) }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Notification.Name {
    static let lemmingsStudioOpenURL = Notification.Name("LemmingsStudioOpenURL")
    static let lemmingsStudioCycleWorkspaceFromGlobalTab = Notification.Name("LemmingsStudioCycleWorkspaceFromGlobalTab")
    static let lemmingsStudioDeleteSelectionFromGlobalKey = Notification.Name("LemmingsStudioDeleteSelectionFromGlobalKey")
}


public enum UserLibraryMediaKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case oneShot = "One-shots"
    case loop = "Loops"
    case midi = "MIDI"
    public var id: String { rawValue }
}

public struct UserLibraryItem: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var kind: UserLibraryMediaKind
    public var detectedTempo: Double?
    public var fileSize: Int64
    public var modifiedAt: TimeInterval

    public init(id: UUID = UUID(), url: URL, kind: UserLibraryMediaKind, detectedTempo: Double? = nil, fileSize: Int64 = 0, modifiedAt: TimeInterval = 0) {
        self.id = id
        self.name = url.deletingPathExtension().lastPathComponent
        self.url = url
        self.kind = kind
        self.detectedTempo = detectedTempo
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }
}

private struct UserLibraryCacheEnvelope: Codable, Sendable {
    var rootPath: String
    var signature: String
    var scannedAt: Date
    var items: [UserLibraryItem]
}

private struct UserLibraryFileCandidate: Sendable {
    var url: URL
    var ext: String
    var fileSize: Int64
    var modifiedAt: TimeInterval
}

// MARK: - App state

@Observable final class AppState {
    let engine: AudioEngine
    @ObservationIgnored private let discordRPC = DiscordRichPresenceClient()
    var project = Project()
    var currentProjectURL: URL?
    var projectDocumentStatus = "Unsaved project"

    var projectDisplayName: String {
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return currentProjectURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    var windowTitle: String { "\(projectDisplayName) — LemmingsStudio" }
    var selectedTrackID: UUID?
    var selectedTrackIDs: Set<UUID> = []
    @ObservationIgnored private var lastTrackSelectionAnchor: UUID? = nil
    var selectedClipID: UUID?
    var selectedAudioClipID: UUID?
    var selectedAudioClipTrackID: UUID?
    var selectedArrangementClipKeys: Set<String> = []
    var betaInstallStatus = "Ready for beta checks"
    var discordApplicationID = UserDefaults.standard.string(forKey: "discordApplicationID") ?? DiscordPresenceConfig.applicationID
    var discordRPCEnabled = UserDefaults.standard.object(forKey: "discordRPCEnabled") as? Bool ?? true
    var inspector: InspectorTab = .circle
    var workspace: WorkspaceTab = .session {
        didSet {
            UserDefaults.standard.set(workspace.rawValue, forKey: "LemmingsStudio.ActiveWorkspace")
            applyPlaybackScopeForWorkspace()
        }
    }
    var detailDeck: DetailDeckTab = .devices
    var visualTheme: LemmingsVisualTheme = LemmingsVisualTheme(rawValue: UserDefaults.standard.string(forKey: "visualTheme") ?? "") ?? .liquidGlass

    // Core DAW behavior
    var metronomeEnabled = UserDefaults.standard.object(forKey: "metronomeEnabled") as? Bool ?? true
    var countInEnabled = UserDefaults.standard.object(forKey: "countInEnabled") as? Bool ?? true
    var countInBeats = UserDefaults.standard.integer(forKey: "countInBeats") == 0 ? 4 : UserDefaults.standard.integer(forKey: "countInBeats")
    var tapTempoStatus = "Tap tempo"
    @ObservationIgnored private var tapTempoTimes: [Date] = []
    var snapToGridEnabled = UserDefaults.standard.object(forKey: "snapToGridEnabled") as? Bool ?? true
    var gridSubdivisionBeats = UserDefaults.standard.double(forKey: "gridSubdivisionBeats") == 0 ? 0.25 : UserDefaults.standard.double(forKey: "gridSubdivisionBeats")
    var recordQuantizationEnabled = UserDefaults.standard.object(forKey: "recordQuantizationEnabled") as? Bool ?? true
    var recordQuantizationBeats = UserDefaults.standard.double(forKey: "recordQuantizationBeats") == 0 ? 0.25 : UserDefaults.standard.double(forKey: "recordQuantizationBeats")
    var autoWarpImportedAudio = UserDefaults.standard.object(forKey: "autoWarpImportedAudio") as? Bool ?? true
    var multiArmEnabled = UserDefaults.standard.object(forKey: "multiArmEnabled") as? Bool ?? true
    var multiSoloEnabled = UserDefaults.standard.object(forKey: "multiSoloEnabled") as? Bool ?? true
    var multiMuteEnabled = UserDefaults.standard.object(forKey: "multiMuteEnabled") as? Bool ?? true
    var showProjectSetupSheet = UserDefaults.standard.object(forKey: "hasSeenProjectSetup") as? Bool != true
    var projectSetupStatus = "Choose project audio format before recording or importing media."
    var defaultWarpMode: WarpMode = WarpMode(rawValue: UserDefaults.standard.string(forKey: "defaultWarpMode") ?? "") ?? .beat
    var selectedSequencerLayerID: UUID? = nil
    var userLibraryFolder = UserDefaults.standard.string(forKey: "userLibraryFolder") ?? ""
    var userLibraryItems: [UserLibraryItem] = []
    var userLibraryScanStatus = "Choose a User Library folder to scan one-shots, loops, and MIDIs."
    var userLibraryScanInProgress = false
    @ObservationIgnored private var userLibraryScanTask: Task<Void, Never>? = nil
    var userLibraryPreviewStatus = "Preview ready. Drag samples/MIDI into Arrangement or onto a track."
    var userLibraryPreviewingID: UUID? = nil
    @ObservationIgnored private var userLibraryPreviewPlayer: AVAudioPlayer? = nil
    @ObservationIgnored private var userLibraryMIDIPreviewTask: Task<Void, Never>? = nil
    var openSampleStatus = "Open sample libraries are optional downloads. Pick a source and Lemmings will download into your User Library/Open Samples folder."
    var audioSignatureStatus = "No sample analysed yet"
    var bootstrapStatus = "Ollama / Homebrew not checked"
    let voiceModels = VoiceModelStore()
    var selectedVoiceModelID: String? = nil
    var voiceAIInputAudioPath = ""
    var voiceAIOutputFolder = UserDefaults.standard.string(forKey: "voiceAIOutputFolder") ?? ""
    var voiceAIStatus = "Choose a consented voice model and a dry vocal/singing input to render voice-to-voice."
    var voiceCloneTrainingFolder = ""
    var voiceAIRecording = false
    @ObservationIgnored private var voiceAIScratchRecorder: AVAudioRecorder?
    @ObservationIgnored private var voiceAIScratchURL: URL?

    // Record/overdub state. Audio capture is handled by AudioRecorder; MIDI
    // overdub is tracked here so the transport can keep scrubbing while new
    // notes are appended to armed clips.
    var midiOverdubRecording = false
    var recordStatus = "Record stopped"
    /// Latest recorder diagnostic (device binding result, silent-stream warnings,
    /// empty-take reasons). Mirrored from AudioRecorder via onDiagnostic so the
    /// status bar can show it. Empty string = nothing to report.
    var recorderStatus = ""
    @ObservationIgnored private var recordingMIDINotes: [String: (clipID: UUID, startBeat: Double, note: Int, velocity: Float)] = [:]
    @ObservationIgnored private var liveMIDINoteCounts: [String: Int] = [:]
    @ObservationIgnored private var stepSequencerRecordStarts: [UUID: Double] = [:]
    @ObservationIgnored private var arrangementClipboard: ArrangementClipboard? = nil
    var selectedMixerDeviceTrackID: UUID? = nil
    var selectedMixerDeviceIDs: Set<UUID> = []
    @ObservationIgnored private var countInWorkItem: DispatchWorkItem? = nil

    /// One source of truth for UI/recording timestamps. This deliberately uses
    /// the app-facing wall-clock transport clock, not render timestamps, so MIDI
    /// overdub records sequential notes while CoreAudio is still warming up.
    var transportBeat: Double { engine.currentBeat }

    /// Tempo currently heard by the transport. When tempo automation is enabled,
    /// the top BPM counter should display this automated value instead of the
    /// static project tempo so users can see exactly how far the tempo lane is
    /// pushing playback up or down.
    var audibleTempo: Double {
        if project.tempoAutomationEnabled, let map = engine.transport.tempoMap {
            return max(20, min(300, map.bpm(atBeat: engine.currentBeat)))
        }
        return project.tempo
    }

    // Lightweight app-level undo/redo for common editing moves. This is not a
    // full document-history engine yet, but it covers track deletion, device
    // insert/remove, plug-in drops, and clip-FX insert/remove.
    @ObservationIgnored private var undoStack: [UndoableEdit] = []
    @ObservationIgnored private var redoStack: [UndoableEdit] = []
    @ObservationIgnored private var focusedUndoContext: UndoContext = .general
    var canUndo = false
    var canRedo = false
    var editStatus = "Ready"

    // First-run visual polish. Fullscreen is a user-facing launch preference; default on for beta.
    var showSplashScreen = true
    var launchFullscreenEnabled = UserDefaults.standard.object(forKey: "launchFullscreenEnabled") as? Bool ?? true
    @ObservationIgnored private var didRequestInitialFullscreen = false
    @ObservationIgnored private var preSplashWindowController: MagmaVancePreSplashWindowController?
    @ObservationIgnored private var splashWindowController: LemmingsSplashWindowController?
    @ObservationIgnored private var pluginEditorWindows: [UUID: LemmingsPluginEditorWindowController] = [:]

    // Live input + integration
    let midi = MIDIInputManager()
    let recorder: AudioRecorder
    let midiMap = MIDIMappingStore()
    var discoveredPlugins: [DiscoveredPlugin] = []
    var pluginScanStatus = "Not scanned"
    var midiSourceNames: [String] = []

    // Preferences / settings
    var audioDriverName = UserDefaults.standard.string(forKey: "audioDriverName") ?? "CoreAudio"
    var audioInputDevice = UserDefaults.standard.string(forKey: "audioInputDevice") ?? "System Default"
    var audioInputDeviceUID = UserDefaults.standard.string(forKey: "audioInputDeviceUID") ?? AudioRecorder.systemDefaultDeviceUID
    var audioOutputDevice = UserDefaults.standard.string(forKey: "audioOutputDevice") ?? "System Default"
    var preferredSampleRate = UserDefaults.standard.double(forKey: "preferredSampleRate") == 0 ? 44100 : UserDefaults.standard.double(forKey: "preferredSampleRate")
    var preferredBufferSize = UserDefaults.standard.integer(forKey: "preferredBufferSize") == 0 ? 512 : UserDefaults.standard.integer(forKey: "preferredBufferSize")
    var midiInputEnabled = UserDefaults.standard.object(forKey: "midiInputEnabled") as? Bool ?? true
    var midiMappingMode = false
    var pendingMIDILearnTarget: MIDILearnTarget? = nil
    var midiLearnStatus = "MIDI learn idle"
    var midiMonitorEnabled = UserDefaults.standard.object(forKey: "midiMonitorEnabled") as? Bool ?? true
    var midiMonitorEvents: [String] = []
    var pluginScanFoldersText = UserDefaults.standard.string(forKey: "pluginScanFoldersText") ?? PluginScanner.defaultSearchPaths.joined(separator: "\n")

    // Expressive MIDI / MPE. Channels are stored zero-based internally, displayed 1-based in UI.
    var mpeMode: MPEMode = MPEMode(rawValue: UserDefaults.standard.string(forKey: "mpeMode") ?? "") ?? .singleChannel
    var mpePitchBendRange = UserDefaults.standard.integer(forKey: "mpePitchBendRange") == 0 ? 48 : UserDefaults.standard.integer(forKey: "mpePitchBendRange")
    var mpeMasterChannel = UserDefaults.standard.integer(forKey: "mpeMasterChannel")
    var mpeMemberChannelStart = UserDefaults.standard.integer(forKey: "mpeMemberChannelStart") == 0 ? 1 : UserDefaults.standard.integer(forKey: "mpeMemberChannelStart")
    var mpeMemberChannelEnd = UserDefaults.standard.integer(forKey: "mpeMemberChannelEnd") == 0 ? 15 : UserDefaults.standard.integer(forKey: "mpeMemberChannelEnd")
    var mpeMapCC74ToTimbre = UserDefaults.standard.object(forKey: "mpeMapCC74ToTimbre") as? Bool ?? true
    var mpePressureEnabled = UserDefaults.standard.object(forKey: "mpePressureEnabled") as? Bool ?? true
    var mpeStatus = "Pitch bend centered"

    // Drum-pad controller support for MPK Mini / ATOM / MPC-style grids.
    var drumPadPreset: DrumPadPreset = DrumPadPreset(rawValue: UserDefaults.standard.string(forKey: "drumPadPreset") ?? "") ?? .generalMIDI
    var drumPadTranspose = UserDefaults.standard.integer(forKey: "drumPadTranspose")
    var drumPadCustomMapText = UserDefaults.standard.string(forKey: "drumPadCustomMapText") ?? DrumPadMapper.defaultCustomMap
    var drumPadLearnMode = false
    var drumPadLearnVoice: DrumVoiceID = .kick
    var drumPadLastHit = "No pad hit yet"

    // Studio subsystems (export / stems / bounce / warp)
    let offline: OfflineRenderer
    let stems = StemSplitter()
    var exportStatus = ""
    var exportProgress = 0.0
    var exportIsActive = false
    var exportDidClip = false
    var exportPeakDBFS = -120.0
    var pendingTempoTextDraft: String? = nil
    var stemStatus = ""
    var stemProgress = 0.0
    var stemResults: [String: URL] = [:]
    var selectedStemOutputs: Set<String> = Set(["drums", "bass", "other", "vocals"])
    var selectedStemBackend: StemBackend = .auto
    var stemMergeToSingleAudioTrack = false
    var stemCreateSubmixGroup = false

    // Shared AI backend (used by describe-a-sound agent, AI Producer, and general chatbot).
    // The old deterministic/semantic fallback is intentionally not a selectable engine anymore.
    enum AIBackendChoice: String, CaseIterable, Identifiable { case claude = "Claude API", ollama = "Local (Ollama)"; var id: String { rawValue } }
    var aiBackend: AIBackendChoice = .ollama
    var claudeAPIKey = ""              // session only
    var assistantLog: [String] = []
    var generalChatLog: [GeneralChatMessage] = [GeneralChatMessage(role: "AI", text: "Ask me general production questions, key/mashup planning, arrangement ideas, mixing notes, or LemmingsStudio workflow help.")]

    // Splice MCP sample browser
    var spliceMCPURL = UserDefaults.standard.string(forKey: "spliceMCPURL") ?? "https://mcp.splice.com/mcp"
    var spliceBearerToken = UserDefaults.standard.string(forKey: "spliceBearerToken") ?? "" // debug/partner-only; official Splice MCP should normally browser-auth without pasted tokens
    var spliceLastAuthURL = UserDefaults.standard.string(forKey: "spliceLastAuthURL") ?? SpliceOfficialMCP.landing.absoluteString
    var spliceDownloadDirectory = UserDefaults.standard.string(forKey: "spliceDownloadDirectory") ?? (FileManager.default.homeDirectoryForCurrentUser.path + "/Music/Lemmings Studio/Splice")
    var spliceStatus = "Not connected"
    var spliceTools: [MCPTool] = []
    var spliceResults: [SpliceSample] = []
    var spliceAccountSummary = "Credits: unknown • Downloads: unknown"
    var spliceAccountStatus = "Credits preview has not been checked yet."
    var splicePluginFallbackStatus = "Splice Sounds/Bridge plug-in fallback has not been checked yet."
    var spliceDetectedPluginNames: [String] = []
    var carlaBridgeStatus = CarlaBridgeSupport.statusLine()
    var splicePreviewingID: String? = nil
    @ObservationIgnored var splicePreviewPlayer: AVPlayer? = nil
    @ObservationIgnored private var spliceWebPreviewWindow: LemmingsSpliceWebPreviewWindowController? = nil
    var spliceWebPreviewURL: URL? = nil
    var spliceWebPreviewTitle = "Splice Preview"

    // Legacy/manual OAuth fields kept only as a lab fallback. The supported Splice beta path is
    // remote streamable HTTP MCP at https://mcp.splice.com/mcp with browser login.
    var spliceOAuthClientID = UserDefaults.standard.string(forKey: "spliceOAuthClientID") ?? ""
    var spliceOAuthAuthorizationServer = UserDefaults.standard.string(forKey: "spliceOAuthAuthorizationServer") ?? SpliceOfficialMCP.authorizationServer.absoluteString
    var spliceOAuthAuthURL = UserDefaults.standard.string(forKey: "spliceOAuthAuthURL") ?? ""
    var spliceOAuthTokenURL = UserDefaults.standard.string(forKey: "spliceOAuthTokenURL") ?? ""
    var spliceOAuthRegistrationURL = UserDefaults.standard.string(forKey: "spliceOAuthRegistrationURL") ?? ""
    var spliceOAuthRedirectURI = UserDefaults.standard.string(forKey: "spliceOAuthRedirectURI") ?? "lemmingsstudio://splice-oauth"
    var spliceOAuthScope = UserDefaults.standard.string(forKey: "spliceOAuthScope") ?? SpliceOfficialMCP.defaultScope
    var spliceOAuthState = ""
    var spliceOAuthCodeVerifier = ""
    @ObservationIgnored private var spliceOAuthLoopbackServer: SpliceOAuthLoopbackServer?
    @ObservationIgnored private var spliceOAuthSession: ASWebAuthenticationSession?
    @ObservationIgnored private let spliceOAuthPresentationProvider = LemmingsOAuthPresentationProvider()

    var selectedTrack: Track? {
        guard let id = selectedTrackID else { return project.tracks.first }
        return project.tracks.first { $0.id == id }
    }
    var selectedTracks: [Track] {
        let ids = selectedTrackIDs.isEmpty ? Set(selectedTrackID.map { [$0] } ?? []) : selectedTrackIDs
        return project.tracks.filter { ids.contains($0.id) }
    }
    var armedOrSelected: Track? { project.tracks.first { $0.armed } ?? selectedTrack }

    func selectTrack(_ track: Track, extending: Bool = false) {
        if extending {
            if let anchor = lastTrackSelectionAnchor,
               let a = project.tracks.firstIndex(where: { $0.id == anchor }),
               let b = project.tracks.firstIndex(where: { $0.id == track.id }) {
                let range = min(a, b)...max(a, b)
                selectedTrackIDs = Set(project.tracks[range].map(\.id))
            } else {
                selectedTrackIDs.insert(track.id)
            }
        } else {
            selectedTrackIDs = [track.id]
            lastTrackSelectionAnchor = track.id
        }
        selectedTrackID = track.id
        selectedClipID = nil
        selectedAudioClipID = nil
    }

    var selectedAudioClip: AudioClip? {
        guard let id = selectedAudioClipID else { return nil }
        return project.tracks.flatMap { $0.audioClips }.first { $0.id == id }
    }


    private func applyPlaybackScopeForWorkspace() {
        let next: PlaybackScope
        switch workspace {
        case .step:
            next = .stepSequencer
        case .pianoRoll:
            next = .pianoRoll
        default:
            next = .arrangement
        }
        if engine.playbackScope != next {
            engine.playbackScope = next
            engine.allNotesOff()
        }
    }

    init() {
        let engine = AudioEngine()
        self.engine = engine
        self.recorder = AudioRecorder(engine: engine)
        self.offline = OfflineRenderer(engine: engine)

        seedDemoProject()
        engine.attach(project: project)
        engine.metronomeEnabled = metronomeEnabled
        UserDefaults.standard.set(workspace.rawValue, forKey: "LemmingsStudio.ActiveWorkspace")
        applyPlaybackScopeForWorkspace()
        setupMIDI()
        recorder.selectInputDevice(uid: audioInputDeviceUID)
        audioInputDevice = recorder.selectedInputDeviceName
        recorder.onDiagnostic = { [weak self] message in
            // Already delivered on the main queue by the recorder.
            self?.recorderStatus = message
            self?.editStatus = message
        }
        scanPlugins()
        NotificationCenter.default.addObserver(forName: .lemmingsStudioCycleWorkspaceFromGlobalTab, object: nil, queue: .main) { [weak self] note in
            let reverse = (note.userInfo?["reverse"] as? Bool) ?? false
            self?.cycleWorkspace(reverse: reverse)
        }
        NotificationCenter.default.addObserver(forName: .lemmingsStudioDeleteSelectionFromGlobalKey, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.workspace == .arrangement else { return }
            self.deleteSelectedItem()
        }
    }


    func requestInitialFullscreenIfNeeded() {
        guard launchFullscreenEnabled, !didRequestInitialFullscreen else { return }
        didRequestInitialFullscreen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
    }

    func showStartupSplashIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.showStartupSplashIfNeeded() }
            return
        }
        guard showSplashScreen, preSplashWindowController == nil, splashWindowController == nil else { return }

        let parent = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })
        if let preSplashURL = MagmaVancePreSplashAsset.url {
            let controller = MagmaVancePreSplashWindowController(videoURL: preSplashURL)
            preSplashWindowController = controller
            controller.show(relativeTo: parent)
            let delay = MagmaVancePreSplashAsset.displayDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak controller] in
                guard let self, self.showSplashScreen else { return }
                controller?.dismiss()
                self.preSplashWindowController = nil
                self.showLemmingsSplashPanel(relativeTo: parent)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { [weak self] in
                    self?.finishSplashScreen()
                }
            }
        } else {
            showLemmingsSplashPanel(relativeTo: parent)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { [weak self] in
                self?.finishSplashScreen()
            }
        }
    }

    private func showLemmingsSplashPanel(relativeTo parent: NSWindow?) {
        guard showSplashScreen, splashWindowController == nil else { return }
        let controller = LemmingsSplashWindowController()
        splashWindowController = controller
        controller.show(relativeTo: parent ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }))
    }

    func finishSplashScreen() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.finishSplashScreen() }
            return
        }
        guard showSplashScreen else { return }
        showSplashScreen = false
        preSplashWindowController?.dismiss()
        preSplashWindowController = nil
        splashWindowController?.dismiss()
        splashWindowController = nil
    }


    func setMetronome(_ enabled: Bool) {
        metronomeEnabled = enabled
        engine.metronomeEnabled = enabled
        persistSettings()
        editStatus = enabled ? "Metronome on" : "Metronome off"
    }

    func toggleMetronome() {
        setMetronome(!metronomeEnabled)
    }

    func cycleWorkspace(reverse: Bool = false) {
        let tabs = WorkspaceTab.allCases
        guard let idx = tabs.firstIndex(of: workspace) else { workspace = .arrangement; return }
        let delta = reverse ? -1 : 1
        let next = (idx + delta + tabs.count) % tabs.count
        workspace = tabs[next]
        editStatus = "View: \(workspace.rawValue)"
    }


    func toggleSelectedClipActive() {
        if let audio = selectedAudioClip {
            audio.isActive.toggle()
            editStatus = audio.isActive ? "Activated audio clip" : "Deactivated audio clip"
            return
        }
        guard let id = selectedClipID else { return }
        for track in project.tracks {
            if let clip = track.clips.first(where: { $0.id == id }) {
                clip.isActive.toggle()
                editStatus = clip.isActive ? "Activated MIDI clip" : "Deactivated MIDI clip"
                return
            }
        }
    }

    func setTrackSendsOnly(_ track: Track, _ sendsOnly: Bool) {
        track.outputMode = sendsOnly ? .sendsOnly : .master
        engine.rebuild()
        editStatus = sendsOnly ? "Set ‘\(track.name)’ to Sends Only" : "Set ‘\(track.name)’ to Master output"
    }

    func assignSidechain(device: DeviceModel, sourceTrackID: UUID?) {
        device.sidechainInputTrackID = sourceTrackID
        device.sidechainEnabled = sourceTrackID != nil
        if let track = selectedTrack { engine.refreshDevices(for: track) }
        editStatus = sourceTrackID == nil ? "Sidechain cleared" : "Sidechain source assigned"
    }

    func createOscillatronTrack() {
        addTrack(kind: .oscillatron)
        if let track = selectedTrack { ensureBuiltInInstrumentDevice(.oscillatron, on: track) }
    }
    func createLemmingBassTrack() {
        addTrack(kind: .lemmingBass)
        if let track = selectedTrack { ensureBuiltInInstrumentDevice(.lemmingBass, on: track) }
    }
    func createDubstepWranglerTrack() {
        addTrack(kind: .dubstepWrangler)
        guard let track = selectedTrack else { return }
        track.name = "Dubstep Wrangler"
        prepareStepTrackForBuiltInKit(track)
        track.kind = .dubstepWrangler
        track.drumGenre = .dubstep
        track.useStepSequencer = true
        track.sequencerLayers = DrumKitLibrary.kitLayers(for: .dubstep)
        track.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: .dubstep))
        track.devices.append(DeviceModel(kind: .arpeggiator))
        syncSequencerLayerCells(from: track.stepPattern, on: track)
        workspace = .step
        detailDeck = .clip
        engine.rebuild()
        editStatus = "Dubstep Wrangler ready — half-time drums, wobble sub, and Pattern Arp loaded"
    }
    func createBailatonTrack(genre: DrumGenre = .dembow) {
        addTrack(kind: .bailaton)
        guard let track = selectedTrack else { return }
        track.name = "Bailaton"
        track.drumGenre = genre
        track.useStepSequencer = true
        track.sequencerLayers = DrumKitLibrary.kitLayers(for: genre)
        track.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: genre))
        syncSequencerLayerCells(from: track.stepPattern, on: track)
        assistantLog.append("agent: Bailaton ready — ask for dembow, moombah, moombahton, or 3-3-2 reggaeton grooves")
        workspace = .step
        detailDeck = .clip
        engine.rebuild()
    }

    func refreshDiscordPresence() {
        guard discordRPCEnabled else {
            discordRPC.disconnect()
            return
        }
        let p = discordPresencePayload()
        let ok = discordRPC.updatePresence(p)
        betaInstallStatus = ok
            ? "Discord RPC live: \(p.state) · \(p.details)"
            : "Discord RPC waiting for Discord/Vesktop socket — \(p.details)"
    }

    func addReturnBus(named name: String = "Return") {
        project.returnBuses.append(ReturnBus(name: "\(name) \(project.returnBuses.count + 1)"))
        engine.rebuild()
    }

    func groupSelectedTracks() {
        let tracks = selectedTracks.isEmpty ? selectedTrack.map { [$0] } ?? [] : selectedTracks
        guard !tracks.isEmpty else { return }
        let group = TrackGroup(name: "Group \(project.groups.count + 1)", trackIDs: tracks.map(\.id))
        project.groups.append(group)
        for t in tracks { t.groupID = group.id }
        selectedTrackIDs = Set(tracks.map(\.id))
        editStatus = "Grouped \(tracks.count) track" + (tracks.count == 1 ? "" : "s")
        engine.rebuild()
    }

    func ungroupSelectedTracks() {
        let tracks = selectedTracks.isEmpty ? selectedTrack.map { [$0] } ?? [] : selectedTracks
        let affected = Set(tracks.compactMap(\.groupID))
        for t in tracks { t.groupID = nil }
        project.groups.removeAll { group in
            affected.contains(group.id) || group.trackIDs.allSatisfy { id in !project.tracks.contains { $0.id == id } }
        }
        editStatus = "Ungrouped selected tracks"
        engine.rebuild()
    }

    func deleteSelectedTracks() {
        let targets = selectedTracks
        guard !targets.isEmpty, project.tracks.count > targets.count else { return }
        let ids = Set(targets.map(\.id))
        project.tracks.removeAll { ids.contains($0.id) }
        for group in project.groups { group.trackIDs.removeAll { ids.contains($0) } }
        project.groups.removeAll { $0.trackIDs.isEmpty }
        selectedTrackIDs.removeAll()
        selectedTrackID = project.tracks.first?.id
        editStatus = "Deleted \(targets.count) track" + (targets.count == 1 ? "" : "s")
        engine.rebuild()
    }

    func duplicateSelectedTrack() {
        guard let t = selectedTrack else { return }
        let copy = Track(name: t.name + " Copy", kind: t.kind, color: t.color)
        copy.devices = t.devices.map { DeviceModel(kind: $0.kind, params: $0.params) }
        copy.volume = t.volume; copy.pan = t.pan; copy.sends = t.sends
        project.tracks.append(copy)
        selectedTrackID = copy.id
        engine.rebuild()
    }

    // MARK: Backend resolution

    func currentBackend() -> LLMBackend {
        switch aiBackend {
        case .claude:
            let key = claudeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? .offline : .claude(apiKey: key)
        case .ollama:
            let dir = UserDefaults.standard.string(forKey: "ollamaModelsDir")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedTag = UserDefaults.standard.string(forKey: "ollamaModelTag")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let tag = (storedTag?.isEmpty == false) ? storedTag! : OllamaCatalog.recommendedForThisMac.tag
            if storedTag?.isEmpty != false {
                UserDefaults.standard.set(tag, forKey: "ollamaModelTag")
            }
            let client = OllamaClient(modelsDirectory: (dir?.isEmpty == false) ? dir : nil)
            return .ollama(client: client, model: tag)
        }
    }

    /// General Chat deliberately uses a chat-tuned model separate from the
    /// multimodal/agentic model used by Sound Agent and AI Producer.
    func currentChatBackend() -> LLMBackend {
        switch aiBackend {
        case .claude:
            let key = claudeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? .offline : .claude(apiKey: key)
        case .ollama:
            let dir = UserDefaults.standard.string(forKey: "ollamaModelsDir")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedTag = UserDefaults.standard.string(forKey: "ollamaChatModelTag")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let tag = (storedTag?.isEmpty == false) ? storedTag! : OllamaChatCatalog.recommendedForThisMac.tag
            if storedTag?.isEmpty != false { UserDefaults.standard.set(tag, forKey: "ollamaChatModelTag") }
            return .ollama(client: OllamaClient(modelsDirectory: (dir?.isEmpty == false) ? dir : nil), model: tag)
        }
    }

    /// The sound-agent target for the selected track.
    func currentTarget() -> InstrumentTarget? {
        guard let t = selectedTrack else { return nil }
        switch t.pluginTargetID {
        case nil, "Built-in Analog":
            if let s = engine.liveStockAnalog(for: t) { return BuiltinAnalogTarget(synth: s) }
            if let s = engine.liveAnalog(for: t) { return BuiltinAnalogTarget(synth: s) }
            return nil
        case "Vital": return VitalTarget()
        case let other?:
            if let hosted = engine.liveInstrument(for: t) as? InstrumentTarget {
                return hosted
            }
            // If a known synth such as "Serum 2" was chosen before the engine had
            // created the hosted instrument, force one rebuild and check again.
            if discoveredPlugins.contains(where: { pluginsEquivalent($0.name, other) || pluginsEquivalent($0.id, other) }) {
                engine.rebuild()
                if let hosted = engine.liveInstrument(for: t) as? InstrumentTarget {
                    return hosted
                }
            }
            if let slot = t.externalPluginSlots.first(where: { pluginsEquivalent($0.name, other) || pluginsEquivalent($0.pluginID, other) }), slot.format != .audioUnit {
                return CarlaBridgedPluginTarget(name: slot.name, pluginPath: slot.path, format: slot.format)
            }
            if let plugin = bestDiscoveredInstrument(named: other), plugin.format != .audioUnit {
                return CarlaBridgedPluginTarget(name: plugin.name, pluginPath: plugin.path, format: plugin.format)
            }
            let hint = KnownPlugins.synths.first { pluginsEquivalent($0.name, other) }?.presetFolderHint
                ?? bestDiscoveredInstrument(named: other)?.path
            return GenericPluginTarget(name: other, presetFolderHint: hint)
        }
    }

    /// Sound Agent entry point: make the user's selected AU synth real before the
    /// LLM writes a patch. Earlier builds fell back to `GenericPluginTarget`, which
    /// saved a handoff note and reported success even though Serum 2 was never
    /// inserted. This function intentionally creates/uses a real instrument track,
    /// rebuilds the engine, and opens the AU editor before returning the live target.
    @MainActor
    func prepareSoundAgentTarget(resetForNewPatch: Bool = false) -> InstrumentTarget? {
        guard let selected = selectedTrack else { return nil }
        let requested = selected.pluginTargetID ?? "Built-in Analog"
        if requested == "Built-in Analog" {
            if resetForNewPatch { engine.rebuild() }
            return currentTarget()
        }
        if requested == "Vital" { return currentTarget() }

        let selectedAlreadyHostsRequestedAU = selected.externalPluginSlots.contains { slot in
            slot.format == .audioUnit && pluginsEquivalent(slot.name, requested)
        }
        if selectedAlreadyHostsRequestedAU {
            if resetForNewPatch {
                engine.resetHostedAudioUnit(for: selected, pluginName: requested)
                engine.rebuild()
                engine.start()
                if let slot = selected.externalPluginSlots.first(where: { $0.format == .audioUnit && pluginsEquivalent($0.name, requested) }) {
                    openPluginGUI(slot)
                }
                pluginScanStatus = "Reset \(requested) to Init/default before applying a new AI Sound Agent patch."
            }
            if let live = currentTarget(), !(live is GenericPluginTarget) { return live }
        }

        if discoveredPlugins.isEmpty || bestDiscoveredInstrument(named: requested) == nil {
            scanPlugins()
        }

        guard let auPlugin = bestDiscoveredAudioUnitInstrument(named: requested) ?? audioUnitPlaceholder(named: requested) else {
            return currentTarget()
        }

        let trackAlreadyHostsRequestedAU = selected.externalPluginSlots.contains { slot in
            slot.format == .audioUnit && (pluginsEquivalent(slot.name, auPlugin.name) || pluginsEquivalent(slot.pluginID, auPlugin.id))
        }
        let targetTrack: Track = trackAlreadyHostsRequestedAU ? selected : dropPlugin(auPlugin, on: nil)
        if resetForNewPatch && trackAlreadyHostsRequestedAU {
            engine.resetHostedAudioUnit(for: targetTrack, pluginName: auPlugin.name)
        }
        targetTrack.kind = .analog
        targetTrack.pluginTargetID = auPlugin.name
        selectedTrackID = targetTrack.id

        if !targetTrack.externalPluginSlots.contains(where: { pluginsEquivalent($0.name, auPlugin.name) || pluginsEquivalent($0.pluginID, auPlugin.id) }) {
            targetTrack.externalPluginSlots.insert(ExternalPluginSlot(plugin: auPlugin, hosted: true), at: 0)
        }

        engine.rebuild()
        // Keep CoreAudio pulling silence from source nodes so synths such as
        // Serum 2 do not sit in a "DAW suspended processing" state while the
        // Sound Agent is trying to set parameters with the editor open.
        engine.start()
        if let hosted = engine.liveInstrument(for: targetTrack) as? InstrumentTarget {
            if let slot = targetTrack.externalPluginSlots.first(where: { pluginsEquivalent($0.name, auPlugin.name) || pluginsEquivalent($0.pluginID, auPlugin.id) }) {
                openPluginGUI(slot)
            }
            pluginScanStatus = "Loaded \(auPlugin.name) as an Audio Unit on ‘\(targetTrack.name)’ for the Sound Agent."
            return hosted
        }

        if let slot = targetTrack.externalPluginSlots.first(where: { pluginsEquivalent($0.name, auPlugin.name) || pluginsEquivalent($0.pluginID, auPlugin.id) }) {
            openPluginGUI(slot)
        }
        return currentTarget()
    }

    private func bestDiscoveredInstrument(named requested: String) -> DiscoveredPlugin? {
        let candidates = discoveredPlugins.filter { $0.role == .instrument || $0.role == .unknown }
        if let exact = candidates.first(where: { pluginsEquivalent($0.name, requested) || pluginsEquivalent($0.id, requested) }) { return exact }
        let compactRequested = pluginComparableName(requested)
        return candidates.first { plugin in
            let compactName = pluginComparableName(plugin.name)
            return compactName.contains(compactRequested) || compactRequested.contains(compactName)
        }
    }

    private func bestDiscoveredAudioUnitInstrument(named requested: String) -> DiscoveredPlugin? {
        let candidates = discoveredPlugins.filter { ($0.role == .instrument || $0.role == .unknown) && $0.format == .audioUnit }
        if let exact = candidates.first(where: { pluginsEquivalent($0.name, requested) || pluginsEquivalent($0.id, requested) }) { return exact }
        let compactRequested = pluginComparableName(requested)
        return candidates.first { plugin in
            let compactName = pluginComparableName(plugin.name)
            return compactName.contains(compactRequested) || compactRequested.contains(compactName)
        }
    }

    private func audioUnitPlaceholder(named requested: String) -> DiscoveredPlugin? {
        guard KnownPlugins.synths.contains(where: { pluginsEquivalent($0.name, requested) }) else { return nil }
        return DiscoveredPlugin(id: "AU.placeholder.\(requested)",
                                name: requested,
                                manufacturer: "Audio Unit",
                                isKnownSynth: true,
                                format: .audioUnit,
                                role: .instrument,
                                path: nil)
    }

    private func pluginsEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        pluginComparableName(lhs) == pluginComparableName(rhs)
    }

    private func pluginComparableName(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "audio unit", with: "")
            .replacingOccurrences(of: "vst3", with: "")
            .replacingOccurrences(of: "vst", with: "")
            .replacingOccurrences(of: "au", with: "")
            .replacingOccurrences(of: "xfer", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    var soundTargetNames: [String] {
        var names = ["Built-in Analog"]
        names.append(contentsOf: KnownPlugins.synths.map(\.name).filter { $0 != "Built-in Analog" })
        names.append(contentsOf: discoveredPlugins.filter { $0.role == .instrument || $0.role == .unknown }.map(\.name))
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    var mpeSettings: MPEZoneSettings {
        MPEZoneSettings(mode: mpeMode,
                        bendRangeSemitones: mpePitchBendRange,
                        masterChannel: mpeMasterChannel,
                        memberChannelStart: mpeMemberChannelStart,
                        memberChannelEnd: mpeMemberChannelEnd,
                        mapCC74ToTimbre: mpeMapCC74ToTimbre,
                        pressureEnabled: mpePressureEnabled)
    }


    // MARK: Project documents + clip creation

    func newProject() {
        showProjectSetupSheet = true
        let fresh = Project()
        fresh.name = "Untitled"
        fresh.tempo = 124
        fresh.lengthBars = 32
        let drums = Track(name: "Drum Machine", kind: .drums, color: .orange)
        let bass = Track(name: "Sub Bass", kind: .analog, color: .blue)
        fresh.tracks = [drums, bass]
        project = fresh
        currentProjectURL = nil
        selectedTrackID = fresh.tracks.first?.id
        selectedClipID = nil
        selectedAudioClipID = nil
        PianoRollState.shared.clipID = nil
        projectDocumentStatus = "New unsaved project"
        engine.attach(project: project)
        rebuildTempoMap()
        engine.rebuild()
        refreshDiscordPresence()
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(from: url)
    }

    private func projectName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled" : name
    }

    private func syncProjectName(from url: URL, force: Bool = false) {
        let fileName = projectName(for: url)
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if force || trimmed.isEmpty || trimmed == "Untitled" {
            project.name = fileName
        }
    }

    func noteTempoEditorDraft(_ text: String) {
        pendingTempoTextDraft = text
    }

    func commitPendingProjectMetadataEdits() {
        if let draft = pendingTempoTextDraft {
            let cleaned = draft.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(cleaned), value.isFinite {
                let clamped = max(20, min(300, value))
                if abs(project.tempo - clamped) > 0.0001 {
                    project.tempo = clamped
                    engine.transport.tempo = clamped
                    rebuildTempoMap()
                }
            }
        }
        pendingTempoTextDraft = nil
    }

    func saveProject() {
        commitPendingProjectMetadataEdits()
        if let url = currentProjectURL { saveProject(to: url) }
        else { saveProjectAs() }
    }

    func saveProjectAs() {
        commitPendingProjectMetadataEdits()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = project.name.isEmpty ? "Untitled.lemmingsproject" : "\(project.name).lemmingsproject"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveProject(to: url)
    }

    func saveProject(to url: URL) {
        do {
            commitPendingProjectMetadataEdits()
            syncProjectName(from: url, force: true)
            let data = try ProjectDocument(project: project).encoded()
            try data.write(to: url, options: [.atomic])
            currentProjectURL = url
            projectDocumentStatus = "Saved → \(url.lastPathComponent)"
            editStatus = projectDocumentStatus
            refreshDiscordPresence()
        } catch {
            projectDocumentStatus = "⚠️ Save failed: \(error.localizedDescription)"
            editStatus = projectDocumentStatus
        }
    }

    func loadProject(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let loaded = try ProjectDocument.decode(data).makeProject()
            project = loaded
            currentProjectURL = url
            syncProjectName(from: url)
            selectedTrackID = loaded.tracks.first?.id
            selectedClipID = nil
            selectedAudioClipID = nil
            selectedAudioClipTrackID = nil
            PianoRollState.shared.clipID = nil
            projectDocumentStatus = "Loaded → \(url.lastPathComponent)"
            editStatus = projectDocumentStatus
            rebuildTempoMap()
            engine.attach(project: project)
            engine.rebuild()
            refreshDiscordPresence()
        } catch {
            projectDocumentStatus = "⚠️ Open failed: \(error.localizedDescription)"
            editStatus = projectDocumentStatus
        }
    }

    @discardableResult
    func createMidiClip(on track: Track? = nil, startBeat rawStart: Double? = nil, lengthBeats rawLength: Double? = nil, openPianoRoll: Bool = true) -> Clip? {
        let target = track ?? selectedTrack
        guard let target, target.kind != .audio else {
            editStatus = "Select an instrument/MIDI track before creating a clip."
            return nil
        }
        let snap = arrangementSnapUnit
        let start = max(0, ((rawStart ?? engine.currentBeat) / snap).rounded(.down) * snap)
        let minLength = snap
        let length = max(minLength, ((rawLength ?? Double(project.beatsPerBar)) / snap).rounded() * snap)
        let clip = Clip(name: "MIDI Clip", startBeat: start, lengthBeats: length, color: target.color)
        target.clips.append(clip)
        selectedTrackID = target.id
        selectedClipID = clip.id
        selectedAudioClipID = nil
        selectedAudioClipTrackID = nil
        PianoRollState.shared.clipID = clip.id
        detailDeck = .clip
        if openPianoRoll { workspace = .pianoRoll }
        editStatus = "Created MIDI clip on \(target.name)"
        registerUndo(UndoableEdit(name: "Create MIDI Clip", undo: { [weak self, weak target] in
            target?.clips.removeAll { $0.id == clip.id }
            if self?.selectedClipID == clip.id { self?.selectedClipID = nil; PianoRollState.shared.clipID = nil }
            self?.engine.rebuild()
        }, redo: { [weak self, weak target] in
            target?.clips.append(clip)
            self?.selectedTrackID = target?.id
            self?.selectedClipID = clip.id
            PianoRollState.shared.clipID = clip.id
            self?.engine.rebuild()
        }))
        engine.rebuild()
        return clip
    }

    // MARK: Live input

    func setupMIDI() {
        midi.onEvent = { [weak self] msg in
            DispatchQueue.main.async { self?.handleMIDI(msg) }
        }
        midi.learnControl = { [weak self] control in
            DispatchQueue.main.async { self?.completeMIDILearn(control) }
        }
        midi.onDebugEvent = { [weak self] line in
            DispatchQueue.main.async { self?.recordMIDIMonitorEvent(line) }
        }
        midi.start()
        midiSourceNames = midi.sourceNames
    }

    func beginMIDILearn(track: Track, nodeID: String, paramID: String, paramName: String) {
        pendingMIDILearnTarget = MIDILearnTarget(trackID: track.id, trackName: track.name, nodeID: nodeID, paramID: paramID, paramName: paramName)
        midiMappingMode = true
        midiLearnStatus = "Move a MIDI knob/slider or pitch-bend wheel for ‘\(paramName)’"
        editStatus = midiLearnStatus
    }

    func cancelMIDILearn() {
        pendingMIDILearnTarget = nil
        midiMappingMode = false
        midiLearnStatus = "MIDI learn cancelled"
        editStatus = midiLearnStatus
    }

    private func completeMIDILearn(_ control: MIDIControlDescriptor) {
        guard midiMappingMode, let target = pendingMIDILearnTarget else { return }
        let mapping: MIDIMapping
        switch control.kind {
        case .cc:
            mapping = MIDIMapping(cc: control.number ?? 0, channel: control.channel, trackName: target.trackName, nodeID: target.nodeID, paramID: target.paramID, source: "learn")
        case .pitchBend:
            mapping = MIDIMapping(pitchBendChannel: control.channel, trackName: target.trackName, nodeID: target.nodeID, paramID: target.paramID, source: "learn")
        }
        midiMap.add(mapping)
        pendingMIDILearnTarget = nil
        midiMappingMode = false
        midiLearnStatus = "Mapped \(control.displayName) → \(target.trackName) · \(target.paramName)"
        editStatus = midiLearnStatus
    }

    private func recordMIDIMonitorEvent(_ line: String) {
        guard midiMonitorEnabled else { return }
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        midiMonitorEvents.insert("\(stamp)  \(line)", at: 0)
        if midiMonitorEvents.count > 24 { midiMonitorEvents.removeLast(midiMonitorEvents.count - 24) }
    }

    private func liveMIDIKey(track: Track, note: Int, channel: Int) -> String {
        "\(track.id.uuidString):\(channel):\(note)"
    }

    private func applyMIDIMapping(_ mapping: MIDIMapping, normalizedValue: Float, channel: Int) {
        let track = mapping.trackName.flatMap { name in project.tracks.first { $0.name == name } } ?? selectedTrack
        guard let track,
              let node = engine.liveNode(track: track, nodeID: mapping.nodeID),
              let info = node.automatableParams.first(where: { $0.id == mapping.paramID }) else { return }
        let norm = Double(max(0, min(1, normalizedValue)))
        let value = info.denormalize(norm)
        node.setParam(mapping.paramID, value)
        if recorder.isRecording || midiOverdubRecording {
            let lane = automationLane(on: track, nodeID: mapping.nodeID, paramID: mapping.paramID)
            lane.addPoint(beat: transportBeat, value: value)
            editStatus = "Wrote automation: \(track.name) · \(info.name)"
        }
    }

    private func automationLane(on track: Track, nodeID: String, paramID: String) -> AutomationLane {
        if let existing = track.automationLanes.first(where: { $0.nodeID == nodeID && $0.paramID == paramID }) { return existing }
        let lane = AutomationLane(nodeID: nodeID, paramID: paramID)
        track.automationLanes.append(lane)
        return lane
    }

    func handleMIDI(_ msg: MIDIMessage) {
        guard midiInputEnabled else { return }
        switch msg {
        case .noteOn(let n, let v, let ch):
            if drumPadLearnMode {
                learnDrumPad(note: n, voice: drumPadLearnVoice)
                drumPadLearnMode = false
            }
            if let t = armedOrSelected, mpeSettings.accepts(channel: ch) {
                let note = routedMIDINote(n, for: t)
                let key = liveMIDIKey(track: t, note: note, channel: ch)
                liveMIDINoteCounts[key, default: 0] += 1
                engine.sendNote(to: t, note: note, velocity: v, on: true, channel: ch)
                // Recording stays de-duped per track/channel/note so daisy-chained
                // keyboards can layer the live instrument without printing doubled
                // notes into the take.
                if liveMIDINoteCounts[key] == 1 {
                    overdubNoteOn(track: t, note: note, velocity: v, channel: ch)
                }
            }
        case .noteOff(let n, let ch):
            if let t = armedOrSelected, mpeSettings.accepts(channel: ch) {
                let note = routedMIDINote(n, for: t)
                let key = liveMIDIKey(track: t, note: note, channel: ch)
                let remaining = max(0, (liveMIDINoteCounts[key] ?? 1) - 1)
                if remaining == 0 {
                    liveMIDINoteCounts.removeValue(forKey: key)
                    engine.sendNote(to: t, note: note, velocity: 0, on: false, channel: ch)
                    overdubNoteOff(track: t, note: note, channel: ch)
                } else {
                    liveMIDINoteCounts[key] = remaining
                }
            }
        case .cc(let num, let val, let ch):
            if num == 74, mpeSettings.mapCC74ToTimbre, let t = armedOrSelected, mpeSettings.accepts(channel: ch) {
                engine.sendTimbre(to: t, value: val, channel: ch)
                mpeStatus = "CC74 timbre ch \(ch + 1): \(Int(val * 127))"
            }
            for m in midiMap.matches(cc: num, channel: ch) {
                applyMIDIMapping(m, normalizedValue: val, channel: ch)
            }
        case .pitchBend(let value, let ch):
            let mappedNorm = (value + 1.0) * 0.5
            for m in midiMap.matchesPitchBend(channel: ch) {
                applyMIDIMapping(m, normalizedValue: mappedNorm, channel: ch)
            }
            guard let t = armedOrSelected, mpeSettings.accepts(channel: ch), mpeMode != .off else { return }
            engine.sendPitchBend(to: t, value: value, channel: ch, rangeSemitones: mpePitchBendRange)
            let cents = Int(value * Float(mpePitchBendRange) * 100)
            mpeStatus = "Pitch bend ch \(ch + 1): \(cents) cents"
        case .channelPressure(let value, let ch):
            guard mpePressureEnabled, let t = armedOrSelected, mpeSettings.accepts(channel: ch) else { return }
            engine.sendPressure(to: t, value: value, channel: ch)
            mpeStatus = "Pressure ch \(ch + 1): \(Int(value * 127))"
        case .polyPressure(let note, let value, let ch):
            guard mpePressureEnabled, let t = armedOrSelected, mpeSettings.accepts(channel: ch) else { return }
            engine.sendPressure(to: t, value: value, note: note, channel: ch)
            mpeStatus = "Poly pressure ch \(ch + 1) note \(note): \(Int(value * 127))"
        }
    }


    func routedMIDINote(_ incoming: Int, for track: Track) -> Int {
        guard track.kind == .drums else { return project.snap(incoming) }
        if let voice = drumPadVoice(for: incoming) {
            drumPadLastHit = "Pad \(incoming) → \(voice.label)"
            return voice.midiNote
        }
        drumPadLastHit = "Pad \(incoming) → unmapped"
        return incoming
    }

    func drumPadVoice(for note: Int) -> DrumVoiceID? {
        DrumPadMapper.voice(for: note, preset: drumPadPreset, customText: drumPadCustomMapText, transpose: drumPadTranspose)
    }

    var drumPadAssignments: [DrumPadAssignment] {
        DrumPadMapper.assignments(preset: drumPadPreset, customText: drumPadCustomMapText, transpose: drumPadTranspose)
    }

    func learnDrumPad(note: Int, voice: DrumVoiceID) {
        var map = DrumPadMapper.parseCustomMap(drumPadCustomMapText)
        map[note - drumPadTranspose] = voice
        drumPadCustomMapText = map
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.debugName)" }
            .joined(separator: "\n")
        drumPadPreset = .custom
        drumPadLastHit = "Learned pad \(note) → \(voice.label)"
        persistSettings()
    }

    func triggerDrumPad(_ voice: DrumVoiceID, velocity: Float = 1.0) {
        let drums = selectedTrack?.kind == .drums ? selectedTrack : (project.tracks.first { $0.kind == .drums })
        guard let track = drums else { return }
        selectedTrackID = track.id
        drumPadLastHit = "Preview → \(voice.label)"
        engine.sendNote(to: track, note: voice.midiNote, velocity: velocity, on: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak track] in
            guard let self, let track else { return }
            self.engine.sendNote(to: track, note: voice.midiNote, velocity: 0, on: false)
        }
    }

    func toggleRecord() {
        let armed = project.tracks.filter { $0.armed }
        let targets = armed.isEmpty ? selectedTrack.map { [$0] } ?? [] : armed
        guard !targets.isEmpty else { editStatus = "Arm or select a track before recording"; return }

        if let pending = countInWorkItem {
            pending.cancel()
            countInWorkItem = nil
            engine.stopCountInClick()
            engine.transport.stop(at: transportBeat)
            engine.allNotesOff()
            liveMIDINoteCounts.removeAll()
            recordStatus = "Count-in cancelled"
            editStatus = recordStatus
            return
        }

        if recorder.isRecording || midiOverdubRecording {
            let stopBeat = transportBeat
            var audioTakeNote: String? = nil
            if recorder.isRecording, let audioTarget = targets.first(where: { $0.kind == .audio }) ?? selectedTrack {
                if let clip = recorder.stop(commitTo: audioTarget) {
                    let owner = trackContainingAudioClip(id: clip.id) ?? audioTarget
                    selectedTrackID = owner.id
                    selectedAudioClipID = clip.id
                    selectedAudioClipTrackID = owner.id
                    registerAudioClipCreationUndo(clip, on: owner, name: "Record Audio Clip")
                } else if let recErr = recorder.lastError, !recErr.isEmpty {
                    audioTakeNote = recErr
                }
            }
            finalizeStepSequencerRecordings(at: stopBeat)
            midiOverdubRecording = false
            recordingMIDINotes.removeAll()
            liveMIDINoteCounts.removeAll()
            stepSequencerRecordStarts.removeAll()
            engine.allNotesOff()
            recordStatus = audioTakeNote ?? "Record stopped at beat \(String(format: "%.2f", stopBeat))"
            editStatus = recordStatus
            return
        }

        guard ensureAudioInputPermissionIfNeeded(for: targets) else { return }

        engine.start()
        engine.warmUpHostedAudioUnits()
        engine.transport.tempo = project.tempo
        let wasPlaying = engine.transport.isPlaying

        if countInEnabled && metronomeEnabled && !wasPlaying {
            startRecordCountIn(targets: targets)
            return
        }

        if !engine.transport.isPlaying { engine.transport.play() }
        beginRecording(targets: targets)
    }

    @discardableResult
    private func ensureAudioInputPermissionIfNeeded(for targets: [Track]) -> Bool {
        guard targets.contains(where: { $0.kind == .audio }) else { return true }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            recordStatus = "Waiting for microphone permission…"
            editStatus = "Allow microphone access, then press Record again."
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.recordStatus = granted ? "Microphone access granted — press Record again" : "Microphone access denied"
                    self.editStatus = self.recordStatus
                }
            }
            return false
        default:
            recordStatus = "Microphone access denied in macOS Privacy settings"
            editStatus = "Enable Microphone access for LemmingsStudio in System Settings → Privacy & Security."
            return false
        }
    }

    func refreshAudioInputDevices() {
        recorder.refreshInputDevices()
        if audioInputDeviceUID != AudioRecorder.systemDefaultDeviceUID,
           !recorder.inputDevices.contains(where: { $0.uid == audioInputDeviceUID }) {
            audioInputDeviceUID = AudioRecorder.systemDefaultDeviceUID
        }
        recorder.selectInputDevice(uid: audioInputDeviceUID)
        audioInputDevice = recorder.selectedInputDeviceName
        for track in project.tracks where track.kind == .audio {
            if let uid = track.audioInputDeviceUID,
               let dev = recorder.inputDevices.first(where: { $0.uid == uid }) {
                track.audioInputDeviceName = dev.name
            }
        }
    }

    func setDefaultAudioInputDevice(uid: String) {
        audioInputDeviceUID = uid
        let selected = recorder.selectInputDevice(uid: uid)
        audioInputDevice = selected.name
        editStatus = "Selected audio input: \(selected.name)"
        persistSettings()
    }

    func setAudioInputDevice(for track: Track, uid: String) {
        guard track.kind == .audio else { return }
        let selected = recorder.device(for: uid)
        track.audioInputDeviceUID = selected.uid == AudioRecorder.systemDefaultDeviceUID ? nil : selected.uid
        track.audioInputDeviceName = selected.name
        let maxIndex = max(0, selected.channelCount - 1)
        track.audioInputChannelIndex = min(max(0, track.audioInputChannelIndex), maxIndex)
        selectedTrackID = track.id
        editStatus = "Set ‘\(track.name)’ input device to \(selected.name)"
    }

    func setAudioInputChannel(for track: Track, channelIndex: Int) {
        guard track.kind == .audio else { return }
        let selected = recorder.device(for: track.audioInputDeviceUID ?? AudioRecorder.systemDefaultDeviceUID)
        let maxIndex = max(0, selected.channelCount - 1)
        track.audioInputChannelIndex = min(max(0, channelIndex), maxIndex)
        selectedTrackID = track.id
        editStatus = "Set ‘\(track.name)’ input to \(recorder.channelLabel(for: track.audioInputChannelIndex, deviceUID: track.audioInputDeviceUID))"
    }

    func setAudioInputMonitorMode(_ mode: AudioInputMonitorMode, for track: Track) {
        guard track.kind == .audio else { return }
        track.audioInputMonitorMode = mode
        // Keep the old boolean field meaningful for older UI/project files.
        track.inputMonitor = mode != .off
        selectedTrackID = track.id
        switch mode {
        case .monitorIn:
            editStatus = "‘\(track.name)’ monitor mode: In — hardware/direct monitoring; software loopback disabled to avoid echo"
        case .auto:
            editStatus = "‘\(track.name)’ monitor mode: Auto — input is record-ready; loopback muted while recording"
        case .off:
            editStatus = "‘\(track.name)’ monitor mode: Off"
        }
    }

    func toggleInputMonitor(_ track: Track) {
        guard track.kind == .audio else { return }
        let next: AudioInputMonitorMode
        switch track.audioInputMonitorMode {
        case .off: next = .auto
        case .auto: next = .monitorIn
        case .monitorIn: next = .off
        }
        setAudioInputMonitorMode(next, for: track)
    }

    private func shouldSoftwareMonitorAudioInput(for track: Track) -> Bool {
        // Lemmings deliberately avoids loopback monitoring during record takes.
        // Multi-channel interfaces and USB mics often already provide direct monitoring;
        // software monitoring on top of that causes slapback/echo.
        switch track.audioInputMonitorMode {
        case .monitorIn:
            return false
        case .auto:
            return false
        case .off:
            return false
        }
    }

    private func startRecordCountIn(targets: [Track]) {
        countInWorkItem?.cancel()
        let beats = max(1, countInBeats)
        let seconds = Double(beats) * 60.0 / max(20.0, project.tempo)
        engine.transport.tempo = project.tempo
        engine.stopCountInClick()
        engine.startCountInClick(beats: beats, tempo: project.tempo)
        engine.allNotesOff()
        liveMIDINoteCounts.removeAll()
        recordStatus = "Count-in: \(beats) beats…"
        editStatus = "Metronome count-in before recording"
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.countInWorkItem = nil
            self.engine.stopCountInClick()
            // Do NOT clear liveMIDINotesDown here. If the player presses/holds
            // notes during the count-in, clearing the guard at the record boundary
            // lets duplicate CoreMIDI callbacks retrigger the same AU voice, which
            // sounds like stacked notes even though the clip records only one note.
            self.beginRecording(targets: targets)
        }
        countInWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func beginRecording(targets: [Track]) {
        engine.start()
        if !engine.transport.isPlaying { engine.transport.play() }
        engine.warmUpHostedAudioUnits()
        if let audioTarget = targets.first(where: { $0.kind == .audio }) {
            recorder.start(into: audioTarget, monitor: shouldSoftwareMonitorAudioInput(for: audioTarget))
        }
        if targets.contains(where: { $0.kind != .audio }) {
            midiOverdubRecording = true
            prepareStepSequencerRecordings(targets: targets)
            prepareArmedClipsForOverdub(targets: targets)
        }
        recordStatus = "Recording / overdubbing on \(targets.map { $0.name }.joined(separator: ", "))"
        if let recorderWarning = recorder.lastError, !recorderWarning.isEmpty {
            recordStatus += " — \(recorderWarning)"
        }
        editStatus = recordStatus
    }

    func importDAWConfigs() -> String {
        let r = DAWConfigImporter.importAll()
        midiMap.merge(r.mappings)
        return r.notes.joined(separator: "\n")
    }

    func scanPlugins() {
        pluginScanStatus = "Scanning AU/VST/VST3…"
        let customPaths = pluginScanFoldersText.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        discoveredPlugins = PluginScanner.scanAllPlugins(extraSearchPaths: customPaths)
        let instruments = discoveredPlugins.filter { $0.role == .instrument || $0.role == .unknown }.count
        let effects = discoveredPlugins.filter { $0.role == .effect }.count
        pluginScanStatus = "Found \(discoveredPlugins.count) plugin(s): \(instruments) instruments/unknown, \(effects) effects"
    }

    // MARK: Export / bounce / warp / tempo

    func export(format: ExportFormat) {
        commitPendingProjectMetadataEdits()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(projectDisplayName).\(format.ext)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportIsActive = true
        exportProgress = 0
        exportDidClip = false
        exportPeakDBFS = -120
        exportStatus = "Rendering \(format.rawValue)… 0%"
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let report = try self.offline.exportWithReport(project: self.project, to: url, format: format) { progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.exportProgress = max(0, min(1, progress))
                        self.exportStatus = "Rendering \(format.rawValue)… \(Int((self.exportProgress * 100).rounded()))%"
                    }
                }
                await MainActor.run {
                    self.exportIsActive = false
                    self.exportProgress = 1
                    self.exportDidClip = report.clipped
                    self.exportPeakDBFS = report.peakDBFS
                    let peakText = String(format: "%.1f dBFS", report.peakDBFS)
                    let clipText = report.clipped ? " ⚠️ Clipping detected" : " ✓ No clipping"
                    self.exportStatus = "Exported → \(report.url.lastPathComponent) · Peak \(peakText) ·\(clipText)"
                }
            } catch {
                await MainActor.run {
                    self.exportIsActive = false
                    self.exportStatus = "⚠️ \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleFreeze(_ track: Track) {
        if track.frozen { offline.unfreeze(track: track); exportStatus = "Unfroze \(track.name)"; return }
        exportStatus = "Freezing \(track.name)…"
        Task.detached { [weak self] in
            guard let self else { return }
            do { try self.offline.bounce(track: track, project: self.project)
                 await MainActor.run { self.exportStatus = "Froze \(track.name) (CPU freed)" } }
            catch { await MainActor.run { self.exportStatus = "⚠️ \(error.localizedDescription)" } }
        }
    }

    /// Recompute a clip's warped buffer for the current project tempo.
    func applyWarp(to clip: AudioClip) {
        WarpEngine.warp(clip, projectTempo: project.tempo)
    }

    /// Rebuild the transport tempo map from the project's tempo automation.
    func rebuildTempoMap() {
        if project.tempoAutomationEnabled && !project.tempoPoints.isEmpty {
            engine.transport.tempoMap = TempoMap(points: project.tempoPoints, lengthBeats: project.lengthBeats)
        } else {
            engine.transport.tempoMap = nil
        }
        // Re-warp all audio clips to the (possibly new) tempo.
        for t in project.tracks { for c in t.audioClips { WarpEngine.warp(c, projectTempo: project.tempo) } }
    }

    func runStemSplit(model: StemModel, backend: StemBackend? = nil) {
        guard let clip = selectedAudioClip else {
            stemStatus = "Select an audio clip in Arrangement first, then run Stem Splitter."
            workspace = .arrangement
            return
        }
        runStemSplit(on: clip, model: model, backend: backend)
    }

    func runStemSplit(on clip: AudioClip, model: StemModel, backend: StemBackend? = nil) {
        let requested = selectedStemOutputs.isEmpty ? Set(model.stems) : selectedStemOutputs
        let chosenBackend = backend ?? selectedStemBackend
        stemStatus = "Preparing \(clip.displayName) for stem split…"
        stemProgress = 0
        stemResults = [:]
        Task.detached { [weak self, weak clip] in
            guard let self, let clip else { return }
            do {
                let input = try self.stemInputURL(for: clip)
                await MainActor.run {
                    self.stemStatus = "Separating \(requested.sorted().joined(separator: ", ")) from \(clip.displayName) with \(model.rawValue) via \(chosenBackend.shortLabel)…"
                }
                let res = try await self.stems.separate(input: input, model: model, backend: chosenBackend, selectedStems: requested) { p in
                    Task { @MainActor [weak self] in
                        self?.stemProgress = max(0, min(1, p))
                    }
                }
                await MainActor.run {
                    self.stemProgress = 1
                    self.stemResults = res.stems
                    self.importStemResultsToTracks(res.stems, sourceName: clip.displayName)
                    self.stemStatus = "Done — imported \(res.stems.count) selected stem(s) to new audio track(s). " + res.notes.joined(separator: " ")
                }
            } catch {
                await MainActor.run {
                    self.stemProgress = 0
                    self.stemStatus = "⚠️ \(error.localizedDescription)"
                }
            }
        }
    }

    private func stemInputURL(for clip: AudioClip) throws -> URL {
        if let raw = clip.sourceURL, !raw.isEmpty {
            let source = URL(fileURLWithPath: raw)
            if FileManager.default.fileExists(atPath: source.path) { return source }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LemmingsSelectedClipStems", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = clip.displayName.replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
        let out = dir.appendingPathComponent("\(safeName)-\(clip.id.uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: clip.activeSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: out, settings: settings)
        let format = file.processingFormat
        let samples = clip.activeSamples
        var pos = 0
        let chunk = 65536
        while pos < samples.count {
            let count = min(chunk, samples.count - pos)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let ch = buffer.floatChannelData else { break }
            for i in 0..<count { ch[0][i] = samples[pos + i] }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            pos += count
        }
        return out
    }

    func importStemResultsToTracks(_ stems: [String: URL], sourceName: String) {
        guard !stems.isEmpty else { return }
        var newTrackIDs: [UUID] = []
        if stemMergeToSingleAudioTrack {
            let t = Track(name: "Stems · \(sourceName)", kind: .audio, color: .teal)
            project.tracks.append(t)
            newTrackIDs.append(t.id)
            selectedTrackID = t.id
            for (stem, url) in stems.sorted(by: { $0.key < $1.key }) {
                do { try importAudioFile(url, name: stem.capitalized) } catch { assistantLog.append("⚠️ stem import failed: \(stem) — \(error.localizedDescription)") }
            }
        } else {
            for (stem, url) in stems.sorted(by: { $0.key < $1.key }) {
                let t = Track(name: "\(stem.capitalized) · \(sourceName)", kind: .audio, color: .teal)
                project.tracks.append(t)
                newTrackIDs.append(t.id)
                selectedTrackID = t.id
                do { try importAudioFile(url, name: stem.capitalized) } catch { assistantLog.append("⚠️ stem import failed: \(stem) — \(error.localizedDescription)") }
            }
        }
        if stemCreateSubmixGroup, !newTrackIDs.isEmpty {
            let g = TrackGroup(name: "Stem Submix · \(sourceName)", trackIDs: newTrackIDs)
            project.groups.append(g)
            for t in project.tracks where newTrackIDs.contains(t.id) { t.groupID = g.id }
        }
        engine.rebuild()
    }

    // MARK: AI assistant

    func runAssistant(_ prompt: String) async {
        do {
            let result = try await AIAssistant(backend: currentBackend()).run(prompt: prompt, project: project)
            let log = await MainActor.run { AssistantExecutor.apply(result.ops, project: project, engine: engine) }
            await MainActor.run {
                assistantLog.append("you: \(prompt)")
                assistantLog.append("AI: \(result.text)")
                assistantLog.append(contentsOf: log.map { "  • \($0)" })
            }
        } catch {
            await MainActor.run { assistantLog.append("⚠️ \(error.localizedDescription)") }
        }
    }


    func runGeneralChat(_ prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let backend = currentChatBackend()
        let pendingID = UUID()
        await MainActor.run {
            generalChatLog.append(GeneralChatMessage(role: "You", text: trimmed))
        }
        guard !backend.isOffline else {
            await MainActor.run {
                generalChatLog.append(GeneralChatMessage(role: "AI", text: "Pick Local Ollama, or enter a Claude API key, then ask again."))
            }
            return
        }
        await MainActor.run {
            generalChatLog.append(GeneralChatMessage(id: pendingID, role: "AI", text: "Thinking…"))
        }
        let system = """
        You are the general music-production chat assistant inside LemmingsStudio. Answer conversationally,
        practically, and with enough technical detail to be useful in a real studio session. You may help with
        music theory, harmony, chord progressions, synthesis, sound design, plugin choices, MIDI, recording,
        arrangement, mixing, mastering, acoustics, loudness, workflow, troubleshooting, and production history.
        Ask for missing context only when it materially changes the recommendation. Prefer actionable settings,
        ranges, signal-chain order, and listening tests over vague advice. Do not emit project-edit JSON unless
        the user explicitly asks to modify the project; this chat is for normal conversation and guidance.
        """
        let projectContext = AIAssistant.projectSummary(project)
        let recent = generalChatLog.suffix(10).map { "\($0.role): \($0.text)" }.joined(separator: "\n")
        let user = """
        CURRENT PROJECT SNAPSHOT:
        \(projectContext)

        RECENT CHAT:
        \(recent)

        USER QUESTION:
        \(trimmed)
        """
        do {
            let text = try await LLMClient(backend: backend).complete(system: system, user: user, jsonOnly: false)
            await MainActor.run {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let reply = clean.isEmpty ? "⚠️ The model returned an empty response." : clean
                if let idx = generalChatLog.firstIndex(where: { $0.id == pendingID }) {
                    generalChatLog[idx].text = reply
                } else {
                    generalChatLog.append(GeneralChatMessage(role: "AI", text: reply))
                }
            }
        } catch {
            await MainActor.run {
                let message = "⚠️ \(error.localizedDescription)"
                if let idx = generalChatLog.firstIndex(where: { $0.id == pendingID }) {
                    generalChatLog[idx].text = message
                } else {
                    generalChatLog.append(GeneralChatMessage(role: "AI", text: message))
                }
            }
        }
    }

    // MARK: Splice MCP

    private func prepareSpliceLocalOAuthCallback() {
        let registeredCurrentBundle = LemmingsLaunchServicesRegistrar.registerCurrentBundleForSpliceCallbacks()
        do {
            let server = SpliceOAuthLoopbackServer { [weak self] url in
                guard let self else { return }
                Task { await self.handleSpliceOAuthCallback(url) }
            }
            _ = try server.start()
            spliceOAuthLoopbackServer = server
            if spliceOAuthRedirectURI.hasPrefix("http://127.0.0.1") || spliceOAuthRedirectURI.hasPrefix("http://localhost") {
                spliceOAuthRedirectURI = "lemmingsstudio://splice-oauth"
                spliceOAuthClientID = ""
                UserDefaults.standard.set(spliceOAuthRedirectURI, forKey: "spliceOAuthRedirectURI")
                UserDefaults.standard.removeObject(forKey: "spliceOAuthClientID")
                spliceStatus = registeredCurrentBundle ? "Using Splice app callback registered to this running app. Re-registering OAuth client…" : "Using Splice app callback with localhost handoff guard. Re-registering OAuth client…"
            }
        } catch {
            spliceStatus = "⚠️ Local handoff guard failed: \(error.localizedDescription). Login callback may open a second copy."
        }
    }

    func resetSpliceToOfficialRemoteMCP() {
        spliceMCPURL = SpliceOfficialMCP.endpoint.absoluteString
        spliceBearerToken = ""
        spliceLastAuthURL = SpliceOfficialMCP.landing.absoluteString
        UserDefaults.standard.set(spliceMCPURL, forKey: "spliceMCPURL")
        UserDefaults.standard.removeObject(forKey: "spliceBearerToken")
        UserDefaults.standard.set(spliceLastAuthURL, forKey: "spliceLastAuthURL")
        spliceStatus = "Using official Splice remote MCP endpoint"
    }

    func openSpliceMCPLoginPage() {
        Task { await prepareSpliceMCPBrowserLogin(openWhenReady: true) }
    }

    func prepareSpliceMCPBrowserLogin(openWhenReady: Bool) async {
        await MainActor.run {
            prepareSpliceLocalOAuthCallback()
            spliceStatus = spliceStatus.hasPrefix("Using localhost") ? spliceStatus : "Discovering Splice MCP OAuth metadata…"
        }
        do {
            let resource = try await fetchSpliceProtectedResourceMetadata()
            let servers = (resource["authorization_servers"] as? [String]) ?? []
            let authServer = servers.first ?? SpliceOfficialMCP.authorizationServer.absoluteString
            await MainActor.run {
                spliceOAuthAuthorizationServer = authServer
                UserDefaults.standard.set(authServer, forKey: "spliceOAuthAuthorizationServer")
                spliceLastAuthURL = authServer
                UserDefaults.standard.set(authServer, forKey: "spliceLastAuthURL")
                if let scopes = resource["scopes_supported"] as? [String], !scopes.isEmpty {
                    spliceOAuthScope = scopes.joined(separator: " ")
                }
            }

            if let metadata = try await fetchSpliceAuthorizationServerMetadata(authServer: authServer) {
                await MainActor.run { applySpliceAuthorizationMetadata(metadata) }
                if spliceOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await registerSpliceMCPClientIfPossible(metadata: metadata)
                }
            }

            await MainActor.run {
                if openWhenReady {
                    if spliceOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || spliceOAuthAuthURL.isEmpty || spliceOAuthTokenURL.isEmpty {
                        let url = URL(string: spliceOAuthAuthorizationServer) ?? SpliceOfficialMCP.authorizationServer
                        spliceLastAuthURL = url.absoluteString
                        UserDefaults.standard.set(spliceLastAuthURL, forKey: "spliceLastAuthURL")
                        NSWorkspace.shared.open(url)
                        spliceStatus = "Splice returned protected-resource metadata, but no public dynamic client registration was advertised. Opened the Splice authorization server; use the Splice Sounds plug-in or partner credentials until Splice exposes native-app registration."
                    } else {
                        beginSpliceOAuthLogin()
                    }
                } else {
                    spliceStatus = "Splice MCP auth metadata discovered."
                }
            }
        } catch {
            await MainActor.run {
                spliceStatus = "⚠️ Could not auto-discover Splice MCP auth metadata: \(error.localizedDescription). Opening Splice MCP page instead."
                let url = URL(string: spliceLastAuthURL) ?? SpliceOfficialMCP.landing
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func fetchSpliceProtectedResourceMetadata() async throws -> [String: Any] {
        let url = URL(string: spliceMCPURL) ?? SpliceOfficialMCP.endpoint
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["authorization_servers"] != nil {
            return json
        }
        if let http = response as? HTTPURLResponse,
           let raw = Self.header("www-authenticate", in: http) ?? Self.header("WWW-Authenticate", in: http),
           let metadataURL = Self.firstURL(in: raw) {
            return try await fetchJSON(metadataURL)
        }
        throw SpliceError.badResponse("Splice MCP did not return OAuth protected-resource metadata.")
    }

    private func fetchSpliceAuthorizationServerMetadata(authServer: String) async throws -> [String: Any]? {
        guard let base = URL(string: authServer) else { return nil }
        let candidates = [
            base.appendingPathComponent(".well-known/oauth-authorization-server"),
            base.appendingPathComponent(".well-known/openid-configuration")
        ]
        for url in candidates {
            if let json = try? await fetchJSON(url), json["authorization_endpoint"] != nil { return json }
        }
        return nil
    }

    @MainActor
    private func applySpliceAuthorizationMetadata(_ metadata: [String: Any]) {
        if let auth = metadata["authorization_endpoint"] as? String { spliceOAuthAuthURL = auth }
        if let token = metadata["token_endpoint"] as? String { spliceOAuthTokenURL = token }
        if let reg = metadata["registration_endpoint"] as? String { spliceOAuthRegistrationURL = reg }
        if let scopes = metadata["scopes_supported"] as? [String], !scopes.isEmpty {
            let wanted = ["openid", "profile", "email", "offline_access"].filter { scopes.contains($0) }
            spliceOAuthScope = wanted.isEmpty ? scopes.joined(separator: " ") : wanted.joined(separator: " ")
        }
        persistSpliceOAuthSettings()
    }

    private func registerSpliceMCPClientIfPossible(metadata: [String: Any]) async throws {
        let registration = (metadata["registration_endpoint"] as? String) ?? spliceOAuthRegistrationURL
        guard let url = URL(string: registration), !registration.isEmpty else { return }
        await MainActor.run { spliceStatus = "Registering LemmingsStudio as a Splice MCP OAuth client…" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "client_name": "LemmingsStudio",
            "redirect_uris": [spliceOAuthRedirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
            "scope": spliceOAuthScope
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw SpliceError.badResponse("Dynamic client registration HTTP \(http.statusCode): \(text)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientID = json["client_id"] as? String, !clientID.isEmpty else {
            throw SpliceError.badResponse("Dynamic client registration did not return client_id.")
        }
        await MainActor.run {
            spliceOAuthClientID = clientID
            UserDefaults.standard.set(clientID, forKey: "spliceOAuthClientID")
            spliceStatus = "Splice MCP OAuth client registered. Opening browser login…"
        }
    }

    private func fetchJSON(_ url: URL) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw SpliceError.badResponse("HTTP \(http.statusCode) for \(url.absoluteString): \(text)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpliceError.badResponse("Expected JSON from \(url.absoluteString).")
        }
        return json
    }

    private static func header(_ key: String, in http: HTTPURLResponse) -> String? {
        for (k, v) in http.allHeaderFields {
            if String(describing: k).lowercased() == key.lowercased() { return String(describing: v) }
        }
        return nil
    }

    private static func firstURL(in text: String) -> URL? {
        let pattern = #"https?://[^\s<>\"]+"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var raw = ns.substring(with: match.range)
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\",;'<>))"))
        return URL(string: raw)
    }

    // MARK: Splice OAuth

    func beginSpliceOAuthLogin() {
        prepareSpliceLocalOAuthCallback()
        if spliceOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || spliceOAuthAuthURL.isEmpty || spliceOAuthTokenURL.isEmpty {
            Task { await prepareSpliceMCPBrowserLogin(openWhenReady: true) }
            return
        }
        guard let base = URL(string: spliceOAuthAuthURL) else {
            spliceStatus = "⚠️ OAuth authorize URL is invalid."
            return
        }
        let verifier = Self.randomBase64URL(byteCount: 32)
        let challenge = Self.pkceChallenge(for: verifier)
        let state = Self.randomBase64URL(byteCount: 16)
        spliceOAuthCodeVerifier = verifier
        spliceOAuthState = state
        persistSpliceOAuthSettings()

        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: spliceOAuthClientID),
            URLQueryItem(name: "redirect_uri", value: spliceOAuthRedirectURI),
            URLQueryItem(name: "scope", value: spliceOAuthScope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = comps?.url else { spliceStatus = "⚠️ Could not build OAuth login URL."; return }
        _ = LemmingsLaunchServicesRegistrar.registerCurrentBundleForSpliceCallbacks()
        spliceStatus = "Opening Splice OAuth login…"

        // Keep the OAuth callback inside this already-running process. Opening
        // the URL directly with NSWorkspace hands lemmingsstudio:// back to
        // LaunchServices, which can visibly spawn another copied app bundle.
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lemmingsstudio") { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.spliceOAuthSession = nil
                if let callbackURL {
                    await self.handleSpliceOAuthCallback(callbackURL)
                } else if let error {
                    self.spliceStatus = "⚠️ Splice OAuth cancelled or failed: \(error.localizedDescription)"
                } else {
                    self.spliceStatus = "⚠️ Splice OAuth ended without a callback."
                }
            }
        }
        session.presentationContextProvider = spliceOAuthPresentationProvider
        session.prefersEphemeralWebBrowserSession = false
        spliceOAuthSession = session
        if !session.start() {
            spliceStatus = "⚠️ Could not start Splice OAuth browser session."
        }
    }

    func handleSpliceOAuthCallback(_ url: URL) async {
        guard let expected = URL(string: spliceOAuthRedirectURI) else { return }
        if expected.scheme == "http" || expected.scheme == "https" {
            guard url.scheme == expected.scheme, url.host == expected.host, url.path == expected.path else { return }
        } else {
            guard url.scheme == expected.scheme else { return }
        }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if let error = comps.queryItems?.first(where: { $0.name == "error" })?.value {
            await MainActor.run { spliceStatus = "⚠️ OAuth error: \(error)" }
            return
        }
        let code = comps.queryItems?.first(where: { $0.name == "code" })?.value ?? ""
        let returnedState = comps.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
        guard !code.isEmpty else { await MainActor.run { spliceStatus = "⚠️ OAuth callback had no code." }; return }
        guard spliceOAuthState.isEmpty || returnedState == spliceOAuthState else {
            await MainActor.run { spliceStatus = "⚠️ OAuth state mismatch." }
            return
        }
        await exchangeSpliceOAuthCode(code)
    }

    func exchangeSpliceOAuthCode(_ code: String) async {
        persistSpliceOAuthSettings()
        guard let url = URL(string: spliceOAuthTokenURL) else {
            await MainActor.run { spliceStatus = "⚠️ OAuth token URL is invalid." }
            return
        }
        await MainActor.run { spliceStatus = "Exchanging OAuth code…" }
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let fields = [
                "grant_type": "authorization_code",
                "client_id": spliceOAuthClientID,
                "code": code,
                "redirect_uri": spliceOAuthRedirectURI,
                "code_verifier": spliceOAuthCodeVerifier
            ]
            req.httpBody = Self.formURLEncoded(fields).data(using: .utf8)
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw SpliceError.badResponse("OAuth token HTTP \(http.statusCode): \(text)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["access_token"] as? String, !access.isEmpty else {
                throw SpliceError.badResponse("OAuth token response did not contain access_token.")
            }
            await MainActor.run {
                spliceBearerToken = access
                UserDefaults.standard.set(access, forKey: "spliceBearerToken")
                spliceStatus = "OAuth connected — token saved for MCP requests"
            }
            await connectSplice()
        } catch {
            await MainActor.run { spliceStatus = "⚠️ \(error.localizedDescription)" }
        }
    }

    func persistSpliceOAuthSettings() {
        UserDefaults.standard.set(spliceOAuthClientID, forKey: "spliceOAuthClientID")
        UserDefaults.standard.set(spliceOAuthAuthorizationServer, forKey: "spliceOAuthAuthorizationServer")
        UserDefaults.standard.set(spliceOAuthAuthURL, forKey: "spliceOAuthAuthURL")
        UserDefaults.standard.set(spliceOAuthTokenURL, forKey: "spliceOAuthTokenURL")
        UserDefaults.standard.set(spliceOAuthRegistrationURL, forKey: "spliceOAuthRegistrationURL")
        UserDefaults.standard.set(spliceOAuthRedirectURI, forKey: "spliceOAuthRedirectURI")
        UserDefaults.standard.set(spliceOAuthScope, forKey: "spliceOAuthScope")
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        bytes.withUnsafeMutableBytes { raw in
            _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, raw.baseAddress!)
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func pkceChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formURLEncoded(_ fields: [String: String]) -> String {
        fields.map { key, value in
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    func makeSpliceClient() throws -> SpliceClient {
        guard let url = URL(string: spliceMCPURL), url.scheme?.hasPrefix("http") == true else { throw SpliceError.invalidEndpoint }
        UserDefaults.standard.set(spliceMCPURL, forKey: "spliceMCPURL")
        UserDefaults.standard.set(spliceBearerToken, forKey: "spliceBearerToken")
        UserDefaults.standard.set(spliceDownloadDirectory, forKey: "spliceDownloadDirectory")
        return SpliceClient(endpoint: url, bearerToken: spliceBearerToken)
    }

    func refreshSplicePluginFallbacks() {
        let plugins = discoverSpliceDesktopPlugins()
        spliceDetectedPluginNames = plugins.map { "\($0.name) (\($0.format.rawValue))" }
        if spliceDetectedPluginNames.isEmpty {
            splicePluginFallbackStatus = "Splice Sounds/Bridge plug-in not detected. Install it from the Splice desktop app, then rescan plug-ins."
        } else {
            splicePluginFallbackStatus = "Detected: " + spliceDetectedPluginNames.joined(separator: " · ")
        }
    }


    @MainActor
    func prepareCarlaBridge() {
        CarlaBridgeSupport.prepareBridge(allowInstall: true) { [weak self] status in
            self?.carlaBridgeStatus = status
            self?.splicePluginFallbackStatus = status
            self?.spliceStatus = status
        }
    }

    @MainActor
    func openCarlaBridge() {
        CarlaBridgeSupport.openBridge { [weak self] status in
            self?.carlaBridgeStatus = status
            self?.editStatus = status
        }
    }

    @MainActor
    func openSplicePluginFallback(preferBridge: Bool = false) {
        let plugins = discoverSpliceDesktopPlugins()
        guard !plugins.isEmpty else {
            refreshSplicePluginFallbacks()
            return
        }

        func score(_ plugin: DiscoveredPlugin) -> Int {
            let name = plugin.name.lowercased()
            let path = (plugin.path ?? "").lowercased()
            let isBridge = name.contains("bridge") || path.contains("bridge")
            let isSounds = name.contains("sounds") || path.contains("sounds") || name.contains("splice")
            var value = 0
            if preferBridge ? isBridge : (isSounds && !isBridge) { value += 1000 }
            // Prefer the Audio Unit. Lemmings hosts AUs OUT OF PROCESS
            // (`.loadOutOfProcess`), which already sandboxes the crashy Splice
            // WebKit/JUCE/tokio process — a plug-in segfault can't take Lemmings
            // down. AU needs no external Carla dependency and opens a proper editor
            // window owned by Lemmings. VST3/VST only win when there is no AU at all,
            // because hosting those requires Carla (often missing `carla-single`),
            // which is exactly the fragile path that wasn't instantiating.
            if plugin.format == .audioUnit { value += 300 }
            if plugin.format == .vst3 { value += 80 }
            if plugin.format == .vst { value += 60 }
            if plugin.path != nil { value += 25 }
            if name.contains("splice") { value += 10 }
            return value
        }

        let chosen = plugins.max { score($0) < score($1) } ?? plugins[0]
        let track = dropPlugin(chosen, on: nil)
        if let slot = track.externalPluginSlots.first(where: { $0.name == chosen.name || $0.pluginID == chosen.id }) {
            openPluginGUI(slot)
        }
        let bridgeNote = chosen.format == .audioUnit ? "sandboxed AU host" : "Carla bridge (no AU counterpart found)"
        splicePluginFallbackStatus = "Loaded \(chosen.name) (\(chosen.format.rawValue), \(bridgeNote)) on ‘\(track.name)’ and opened its plug-in editor when available. Use it for official preview/drag workflows while MCP handles authenticated downloads when available."
        spliceStatus = splicePluginFallbackStatus
        refreshSplicePluginFallbacks()
    }

    private func discoverSpliceDesktopPlugins() -> [DiscoveredPlugin] {
        var byID: [String: DiscoveredPlugin] = [:]
        for plugin in discoveredPlugins {
            let hay = (plugin.name + " " + plugin.manufacturer + " " + (plugin.path ?? "")).lowercased()
            guard hay.contains("splice") && (hay.contains("bridge") || hay.contains("sounds") || hay.contains("listener")) else { continue }
            byID[plugin.id] = plugin
        }

        let fm = FileManager.default
        let candidates: [(String, PluginFormat, PluginRole)] = [
            ("/Library/Audio/Plug-Ins/Components", .audioUnit, .effect),
            (("~/Library/Audio/Plug-Ins/Components" as NSString).expandingTildeInPath, .audioUnit, .effect),
            ("/Library/Audio/Plug-Ins/VST3", .vst3, .effect),
            (("~/Library/Audio/Plug-Ins/VST3" as NSString).expandingTildeInPath, .vst3, .effect),
            ("/Library/Audio/Plug-Ins/VST", .vst, .effect),
            (("~/Library/Audio/Plug-Ins/VST" as NSString).expandingTildeInPath, .vst, .effect)
        ]

        for (folder, format, role) in candidates {
            guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for item in items {
                let lower = item.lowercased()
                guard lower.contains("splice") && (lower.contains("bridge") || lower.contains("sounds") || lower.contains("listener")) else { continue }
                let name = item
                    .replacingOccurrences(of: ".component", with: "", options: [.caseInsensitive])
                    .replacingOccurrences(of: ".vst3", with: "", options: [.caseInsensitive])
                    .replacingOccurrences(of: ".vst", with: "", options: [.caseInsensitive])
                let path = URL(fileURLWithPath: folder).appendingPathComponent(item).path
                let id = "splice-plugin-\(path.hashValue)"
                if byID[id] == nil {
                    byID[id] = DiscoveredPlugin(id: id, name: name, manufacturer: "Splice", isKnownSynth: false, format: format, role: role, path: path)
                }
            }
        }

        return byID.values.sorted { lhs, rhs in
            func rank(_ p: DiscoveredPlugin) -> Int {
                let n = p.name.lowercased()
                if n.contains("sounds") { return 0 }
                if n.contains("bridge") { return 1 }
                return 2
            }
            let lr = rank(lhs), rr = rank(rhs)
            return lr == rr ? lhs.name < rhs.name : lr < rr
        }
    }

    func connectSplice() async {
        do {
            await MainActor.run { spliceStatus = "Connecting to Splice MCP…" }
            let tools = try await makeSpliceClient().connect()
            await MainActor.run {
                spliceTools = tools
                spliceStatus = "Connected — \(tools.count) MCP tool\(tools.count == 1 ? "" : "s") available"
            }
            await refreshSpliceAccountPreview()
        } catch {
            await handleSpliceMCPError(error)
        }
    }


    func refreshSpliceAccountPreview() async {
        do {
            await MainActor.run { spliceAccountStatus = "Checking Splice credits/download quota…" }
            let snapshot = try await makeSpliceClient().accountSnapshot()
            await MainActor.run {
                spliceAccountSummary = snapshot.displayText
                spliceAccountStatus = snapshot.statusText + (snapshot.toolName.map { " (via \($0))" } ?? "")
            }
        } catch {
            await MainActor.run {
                spliceAccountSummary = "Credits: unavailable • Downloads: unavailable"
                spliceAccountStatus = "Could not check credits/download quota: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func handleSpliceMCPError(_ error: Error) {
        if case SpliceError.authRequired(let message, let loginURL) = error {
            if let loginURL {
                spliceLastAuthURL = loginURL.absoluteString
                UserDefaults.standard.set(spliceLastAuthURL, forKey: "spliceLastAuthURL")
            }
            spliceStatus = "⚠️ \(message)"
            return
        }
        spliceStatus = "⚠️ \(error.localizedDescription)"
    }

    func searchSplice(query: String) async {
        await searchSplice(query: query, type: nil, bpmMin: nil, bpmMax: nil)
    }

    /// `type` is "loop", "oneshot", or nil for no filter.
    func searchSplice(query: String, type: String?, bpmMin: Int?, bpmMax: Int?) async {
        do {
            await MainActor.run { spliceStatus = "Searching Splice…" }
            let found = try await makeSpliceClient().search(query: query, limit: 12, type: type, bpmMin: bpmMin, bpmMax: bpmMax)
            await MainActor.run {
                spliceResults = found.map { $0.withHiddenAssetUUIDFromPageURL }
                let resolved = spliceResults.filter { $0.hiddenAssetUUID != nil }.count
                let typeNote = type.map { " · \($0 == "oneshot" ? "one-shots" : "loops")" } ?? ""
                spliceStatus = "Found \(found.count) result\(found.count == 1 ? "" : "s")\(typeNote)" + (resolved > 0 ? " · \(resolved) fetchable" : " · Web preview only")
            }
        } catch {
            await handleSpliceMCPError(error)
        }
    }


    @MainActor
    func previewSplice(_ sample: SpliceSample) {
        if splicePreviewingID == sample.id {
            splicePreviewPlayer?.pause()
            splicePreviewPlayer = nil
            splicePreviewingID = nil
            return
        }
        guard let url = sample.previewURL ?? sample.downloadURL ?? sample.localFileURL else {
            if sample.hiddenAssetUUID != nil {
                let resolved = rememberSpliceHiddenAsset(sample)
                spliceStatus = "Fetching preview/download for ‘\(resolved.name)’…"
                Task { await downloadPreviewSplice(resolved) }
                return
            }
            if let page = sample.pageURL {
                // Open the in-app WebView preview. While it loads the Splice page,
                // captureSpliceWebPreviewHTML scrapes for a real playable audio URL
                // and, if found, switches to native AVPlayer playback (no credit) and
                // closes the browser. If the page only exposes gated/blob streams we
                // keep the WebView. This is strictly better than bouncing the user out
                // to an external browser (which also skipped the native-audio path).
                openSpliceWebPreview(sample)
            } else {
                spliceStatus = "Splice did not return a preview, download, page URL, or asset UUID for ‘\(sample.name)’ yet."
            }
            return
        }
        playSplicePreview(sample, from: url)
    }

    @MainActor
    func openSpliceWebPreview(_ sample: SpliceSample) {
        guard let page = sample.pageURL else {
            spliceStatus = "Splice did not return a web preview page for ‘\(sample.name)’ yet."
            return
        }
        splicePreviewPlayer?.pause()
        splicePreviewPlayer = nil
        splicePreviewingID = nil
        let resolved = rememberSpliceHiddenAsset(sample)
        spliceWebPreviewTitle = resolved.name
        spliceWebPreviewURL = page
        spliceWebPreviewWindow = LemmingsSpliceWebPreviewWindowController(app: self, url: page, title: resolved.name)
        spliceWebPreviewWindow?.show()
        spliceStatus = resolved.hiddenAssetUUID == nil
            ? "Showing Splice web preview for ‘\(resolved.name)’ in an isolated browser window · drag/download will unlock if the page exposes a sample UUID"
            : "Showing Splice web preview for ‘\(resolved.name)’ in an isolated browser window · hidden asset resolved for MCP download"
    }

    @discardableResult
    func rememberSpliceHiddenAsset(_ sample: SpliceSample) -> SpliceSample {
        let resolved = sample.withHiddenAssetUUIDFromPageURL
        guard resolved.hiddenAssetUUID != nil else { return sample }
        if let i = spliceResults.firstIndex(where: { $0.id == sample.id || $0.pageURL == sample.pageURL || $0.name == sample.name }) {
            spliceResults[i] = resolved
        }
        return resolved
    }

    @MainActor
    func captureSpliceWebPreviewURL(_ url: URL) {
        guard let uuid = SpliceSample.assetUUID(fromSpliceURL: url) else { return }
        var updated = false
        for i in spliceResults.indices {
            let row = spliceResults[i]
            guard row.hiddenAssetUUID == nil else { continue }
            let samePage = row.pageURL?.absoluteString == url.absoluteString
            let previewPage = spliceWebPreviewURL?.absoluteString == row.pageURL?.absoluteString
            guard samePage || previewPage else { continue }
            var raw = row.raw
            raw["asset_uuid"] = uuid
            raw["page_url"] = url.absoluteString
            spliceResults[i] = SpliceSample(id: uuid,
                                            name: row.name,
                                            bpm: row.bpm,
                                            key: row.key,
                                            previewURL: row.previewURL,
                                            pageURL: row.pageURL ?? url,
                                            downloadURL: row.downloadURL,
                                            localFileURL: row.localFileURL,
                                            artworkURL: row.artworkURL,
                                            waveformURL: row.waveformURL,
                                            packName: row.packName,
                                            creatorName: row.creatorName,
                                            instrument: row.instrument,
                                            soundType: row.soundType,
                                            durationSeconds: row.durationSeconds,
                                            tags: row.tags,
                                            raw: raw)
            updated = true
        }
        if updated { spliceStatus = "Resolved hidden Splice asset UUID from web preview. Drag/download is now available." }
    }

    @MainActor
    func captureSpliceWebPreviewHTML(_ html: String, url: URL?) {
        // Opportunistically pull a *playable* audio URL out of the page so we can
        // preview natively (AVPlayer) instead of leaving the user in the browser.
        // Splice usually gates preview audio, so this frequently finds nothing —
        // in that case we just keep the WebView as the fallback.
        if let audio = SpliceSample.previewAudioURL(fromSplicePageHTML: html) {
            captureSplicePreviewAudioURL(audio, pageURL: url ?? spliceWebPreviewURL)
        }
        guard let uuid = SpliceSample.assetUUID(fromSplicePageHTML: html, preferredPageURL: url ?? spliceWebPreviewURL) else { return }
        var updated = false
        for i in spliceResults.indices {
            let row = spliceResults[i]
            guard row.hiddenAssetUUID == nil else { continue }
            let samePage = url != nil && row.pageURL?.absoluteString == url?.absoluteString
            let previewPage = spliceWebPreviewURL?.absoluteString == row.pageURL?.absoluteString
            guard samePage || previewPage else { continue }
            var raw = row.raw
            raw["asset_uuid"] = uuid
            if let url { raw["web_preview_url"] = url.absoluteString }
            spliceResults[i] = SpliceSample(id: uuid,
                                            name: row.name,
                                            bpm: row.bpm,
                                            key: row.key,
                                            previewURL: row.previewURL,
                                            pageURL: row.pageURL ?? url,
                                            downloadURL: row.downloadURL,
                                            localFileURL: row.localFileURL,
                                            artworkURL: row.artworkURL,
                                            waveformURL: row.waveformURL,
                                            packName: row.packName,
                                            creatorName: row.creatorName,
                                            instrument: row.instrument,
                                            soundType: row.soundType,
                                            durationSeconds: row.durationSeconds,
                                            tags: row.tags,
                                            raw: raw)
            updated = true
        }
        if updated { spliceStatus = "Resolved hidden Splice asset UUID from Web Preview page content. Drag/download is now available." }
    }

    /// When the Web Preview page exposes a real audio URL, attach it to the
    /// matching row(s), close the browser, and play it natively via AVPlayer.
    @MainActor
    private func captureSplicePreviewAudioURL(_ audio: URL, pageURL: URL?) {
        var played = false
        for i in spliceResults.indices {
            let row = spliceResults[i]
            guard row.previewURL == nil else { continue }
            let samePage = pageURL != nil && row.pageURL?.absoluteString == pageURL?.absoluteString
            let previewPage = spliceWebPreviewURL?.absoluteString == row.pageURL?.absoluteString
            guard samePage || previewPage else { continue }
            let updatedRow = row.withPreviewURL(audio)
            spliceResults[i] = updatedRow
            if !played {
                closeSpliceWebPreview()
                playSplicePreview(updatedRow, from: audio)
                spliceStatus = "Previewing ‘\(updatedRow.name)’ natively (captured from the Splice page — no credit used)"
                played = true
            }
        }
    }

    @MainActor
    func closeSpliceWebPreview() {
        spliceWebPreviewWindow?.close()
        spliceWebPreviewWindow = nil
        spliceWebPreviewURL = nil
    }

    @MainActor
    private func playSplicePreview(_ sample: SpliceSample, from url: URL) {
        splicePreviewPlayer?.pause()
        splicePreviewPlayer = AVPlayer(url: url)
        splicePreviewingID = sample.id
        spliceStatus = "Previewing ‘\(sample.name)’"
        splicePreviewPlayer?.play()
    }

    @MainActor
    func downloadPreviewSplice(_ sample: SpliceSample) async {
        do {
            let dir = URL(fileURLWithPath: spliceDownloadDirectory, isDirectory: true)
            let file = try await makeSpliceClient().download(sample, to: dir)
            playSplicePreview(sample, from: file)
        } catch {
            // Surface auth problems clearly (the official Splice MCP needs OAuth),
            // then fall back to the in-app WebView preview rather than ejecting the
            // user to an external browser — the WebView path can still capture a
            // playable audio URL and preview it natively without spending a credit.
            handleSpliceMCPError(error)
            if sample.pageURL != nil { openSpliceWebPreview(sample) }
        }
    }

    func stopSplicePreview() {
        splicePreviewPlayer?.pause()
        splicePreviewPlayer = nil
        splicePreviewingID = nil
    }

    func downloadAndImportSplice(_ sample: SpliceSample) async {
        do {
            await MainActor.run { spliceStatus = "Downloading ‘\(sample.name)’…" }
            let dir = URL(fileURLWithPath: spliceDownloadDirectory, isDirectory: true)
            let file = try await makeSpliceClient().download(sample, to: dir)
            try await MainActor.run { try importAudioFile(file, name: sample.name, originalTempo: sample.bpm.map(Double.init)) }
            await MainActor.run { spliceStatus = "Imported → \(file.lastPathComponent)" }
        } catch {
            await handleSpliceMCPError(error)
        }
    }

    func importAudioFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["wav", "wave", "aif", "aiff", "mp3", "m4a", "caf", "ogg", "flac", "ape", "mov", "mp4", "m4v", "avi", "mkv"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importMediaFile(url)
    }

    func importSequencerSampleLayerFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addSampleLayer(url, to: selectedTrack, step: nil)
    }

    @discardableResult
    func addSampleLayer(_ url: URL, to targetTrack: Track? = nil, step: Int? = nil, preferredNote: Int? = nil) -> Track? {
        let target: Track
        if let selected = targetTrack ?? selectedTrack, selected.kind.isStepEditable || selected.kind == .sequencer {
            target = selected
        } else {
            addTrack(kind: .sequencer)
            guard let created = selectedTrack else { return nil }
            target = created
        }
        target.useStepSequencer = true
        let existingNotes = Set(target.sequencerLayers.map(\.note))
        let note = preferredNote ?? (60...96).first { !existingNotes.contains($0) } ?? (target.sequencerLayers.map(\.note).max() ?? 63) + 1
        let layerName = url.deletingPathExtension().lastPathComponent
        let layerID: UUID
        if let preferredNote, let existing = target.sequencerLayers.firstIndex(where: { $0.note == preferredNote }) {
            target.sequencerLayers[existing].name = layerName
            target.sequencerLayers[existing].source = .splice
            target.sequencerLayers[existing].samplePath = url.path
            target.sequencerLayers[existing].velocity = 0.95
            if target.sequencerLayers[existing].steps.count != target.stepPattern.stepCount {
                target.sequencerLayers[existing].steps = Array(repeating: false, count: target.stepPattern.stepCount)
            }
            if let step, target.sequencerLayers[existing].steps.indices.contains(step) {
                // Dropping a one-shot onto a cell replaces that lane's sound and
                // turns on only that exact cell. Other cells in the lane remain
                // untouched, which is the expected FL-style workflow.
                target.sequencerLayers[existing].steps[step] = true
                target.stepPattern.setHit(step: step, note: preferredNote, enabled: true, velocity: 0.95)
            }
            layerID = target.sequencerLayers[existing].id
        } else {
            var layer = SequencerLayer(name: layerName, source: .splice, note: note, stepCount: target.stepPattern.stepCount, velocity: 0.95, samplePath: url.path)
            if let step, layer.steps.indices.contains(step) {
                layer.steps[step] = true
                target.stepPattern.setHit(step: step, note: note, enabled: true, velocity: layer.velocity)
            }
            layerID = layer.id
            target.sequencerLayers.append(layer)
        }
        selectedTrackID = target.id
        selectedSequencerLayerID = layerID
        workspace = .step
        detailDeck = .clip
        refreshStepSequencerClips(on: target, fallbackName: "Generated Groove")
        editStatus = step == nil
            ? "Replaced lane sound with one-shot ‘\(layerName)’ on \(target.name)"
            : "Dropped one-shot ‘\(layerName)’ onto step \((step ?? 0) + 1)"
        engine.resetStepSequencerState(for: target)
        engine.rebuild()
        return target
    }

    func handleSampleDropText(_ text: String, on track: Track?, step: Int? = nil, note: Int? = nil) -> Bool {
        if let path = PluginDragPasteboard.samplePath(from: text) {
            _ = addSampleLayer(URL(fileURLWithPath: path), to: track, step: step, preferredNote: note)
            return true
        }
        if let url = URL(string: text), url.isFileURL {
            _ = addSampleLayer(url, to: track, step: step, preferredNote: note)
            return true
        }
        if FileManager.default.fileExists(atPath: text) {
            _ = addSampleLayer(URL(fileURLWithPath: text), to: track, step: step, preferredNote: note)
            return true
        }
        if let spliceID = PluginDragPasteboard.spliceSampleID(from: text), let sample = spliceResults.first(where: { $0.id == spliceID }) {
            let resolved = rememberSpliceHiddenAsset(sample)
            spliceStatus = "Fetch-on-drop: asking official Splice MCP to license/download ‘\(resolved.name)’…"
            Task { await downloadSpliceAsSequencerLayer(resolved, to: track, step: step, preferredNote: note) }
            return true
        }
        return false
    }

    @MainActor
    func downloadSpliceAsSequencerLayer(_ sample: SpliceSample, to track: Track?, step: Int? = nil, preferredNote: Int? = nil) async {
        do {
            let resolved = rememberSpliceHiddenAsset(sample)
            spliceStatus = "Fetch-on-drop: resolving/licensing ‘\(resolved.name)’ for sequencer via official MCP…"
            let dir = URL(fileURLWithPath: spliceDownloadDirectory, isDirectory: true)
            let file = try await makeSpliceClient().download(resolved, to: dir)
            _ = addSampleLayer(file, to: track, step: step, preferredNote: preferredNote)
            spliceStatus = "Loaded one-shot → \(sample.name)"
        } catch {
            spliceStatus = "⚠️ \(error.localizedDescription)"
        }
    }

    private func readImportableAudioAsMono(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            // Try an explicit Float32/non-interleaved decode before surfacing the
            // famously unhelpful com.apple.coreaudio.avfaudio 2003334207 error.
            do {
                file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            } catch {
                throw SpliceError.badResponse("Could not decode ‘\(url.lastPathComponent)’ as audio. If this came from Finder, try dropping again; Lemmings now stabilizes Finder temp files before importing.")
            }
        }

        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { throw SpliceError.badResponse("\(url.lastPathComponent) has no readable audio frames.") }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw SpliceError.badResponse("Could not allocate an audio buffer for \(url.lastPathComponent).")
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else {
            throw SpliceError.badResponse("\(url.lastPathComponent) is not readable as floating-point PCM.")
        }
        let frames = Int(buffer.frameLength)
        let channelCount = max(1, Int(format.channelCount))
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for ch in 0..<channelCount { sum += channels[ch][frame] }
            mono[frame] = sum / Float(channelCount)
        }
        return (mono, format.sampleRate)
    }

    func importAudioFile(_ url: URL, name: String? = nil, originalTempo: Double? = nil, targetTrack: Track? = nil, forceNewTrack: Bool = false) throws {
        let decoded = try readImportableAudioAsMono(url)
        let mono = decoded.samples
        let sampleRate = decoded.sampleRate

        let target: Track
        if !forceNewTrack, let explicit = targetTrack, explicit.kind == .audio {
            target = explicit
        } else if !forceNewTrack, let selected = selectedTrack, selected.kind == .audio {
            target = selected
        } else {
            let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .yellow]
            let baseName = name ?? url.deletingPathExtension().lastPathComponent
            target = Track(name: baseName, kind: .audio, color: colors[project.tracks.count % colors.count])
            project.tracks.append(target)
            selectedTrackID = target.id
        }
        let naturalStart = target.audioClips.map { $0.startBeat + (Double($0.samples.count) / $0.sampleRate) * project.tempo / 60.0 }.max() ?? engine.currentBeat
        let startBeat = max(0, snapArrangementBeat(naturalStart))
        let clip = AudioClip(startBeat: startBeat, samples: mono, sampleRate: sampleRate)
        clip.displayName = name ?? url.deletingPathExtension().lastPathComponent
        clip.sourceURL = url.path
        let detected = originalTempo ?? TempoDetector.detectTempoHint(from: url, samples: mono, sampleRate: sampleRate)
        clip.detectedTempo = detected
        if let detected, detected > 0 {
            clip.originalTempo = detected
            clip.warpEnabled = autoWarpImportedAudio && abs(detected - project.tempo) > 0.01
            clip.warpMode = defaultWarpMode
            WarpEngine.warp(clip, projectTempo: project.tempo)
        }
        target.name = (target.name == "Splice" || target.name == "Audio") ? clip.displayName : target.name
        target.audioClips.append(clip)
        selectedTrackID = target.id
        selectedClipID = nil
        selectedAudioClipID = clip.id
        selectedAudioClipTrackID = target.id
        detailDeck = .clip
        editStatus = "Imported audio clip ‘\(clip.displayName)’" + (clip.detectedTempo.map { " — detected \(Int($0)) BPM" } ?? "")
        registerAudioClipCreationUndo(clip, on: target, name: "Import Audio Clip")
        engine.rebuild()
    }

    func chooseAndScanUserLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        userLibraryFolder = url.path
        UserDefaults.standard.set(url.path, forKey: "userLibraryFolder")
        scanUserLibrary()
    }

    private func classifyUserLibraryAudio(url: URL) -> (kind: UserLibraryMediaKind, tempo: Double?) {
        Self.classifyUserLibraryAudioCandidate(url: url)
    }

    private static func classifyUserLibraryAudioCandidate(url: URL) -> (kind: UserLibraryMediaKind, tempo: Double?) {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
        let path = url.path.lowercased()
        let tempo = TempoDetector.detectTempoHint(from: url, samples: [], sampleRate: 44100)
        let loopTokens = ["loop", "loops", "_lp", "-lp", " lp", "bpm", "groove", "rhythm", "riff", "phrase", "melody", "chord", "toploop", "top_loop", "drumloop", "drum_loop", "bhangra"]
        let oneShotTokens = ["one shot", "one-shot", "oneshot", "one_shot", "kick", "snare", "clap", "rim", "snap", "hat", "hihat", "hi-hat", "crash", "ride", "tom", "hit", "stab", "foley", "impact"]
        let saysLoop = loopTokens.contains { stem.contains($0) || parent.contains($0) || path.contains("/\($0)/") }
        let saysOneShot = oneShotTokens.contains { stem.contains($0) || parent.contains($0) }
        var durationSeconds: Double? = nil
        if let audioFile = try? AVAudioFile(forReading: url) {
            durationSeconds = Double(audioFile.length) / max(1.0, audioFile.fileFormat.sampleRate)
        }
        if saysLoop { return (.loop, tempo) }
        if let tempo { return (.loop, tempo) }
        if let durationSeconds {
            if durationSeconds >= 1.5 && !saysOneShot { return (.loop, tempo) }
            if durationSeconds >= 3.0 { return (.loop, tempo) }
        }
        return (.oneShot, tempo)
    }

    private var userLibraryCacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("LemmingsStudio", isDirectory: true)
            .appendingPathComponent("UserLibraryIndex.json")
    }

    private func loadUserLibraryCache(for root: URL) -> UserLibraryCacheEnvelope? {
        let cacheURL = userLibraryCacheURL
        guard let data = try? Data(contentsOf: cacheURL),
              let envelope = try? JSONDecoder().decode(UserLibraryCacheEnvelope.self, from: data),
              envelope.rootPath == root.standardizedFileURL.path else { return nil }
        return envelope
    }

    private func saveUserLibraryCache(_ envelope: UserLibraryCacheEnvelope) {
        let cacheURL = userLibraryCacheURL
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(envelope) {
            try? data.write(to: cacheURL, options: [.atomic])
        }
    }

    private static let userLibraryAudioExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "mp3", "m4a", "flac", "ape", "caf", "ogg"]
    private static let userLibraryMIDIExtensions: Set<String> = ["mid", "midi"]
    private static let userLibraryBatchSize = 48

    private static func makeUserLibraryCandidate(url: URL, values: URLResourceValues?) -> UserLibraryFileCandidate? {
        let ext = url.pathExtension.lowercased()
        guard userLibraryAudioExtensions.contains(ext) || userLibraryMIDIExtensions.contains(ext) else { return nil }
        if values?.isRegularFile == false { return nil }
        return UserLibraryFileCandidate(
            url: url,
            ext: ext,
            fileSize: Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }

    private static func userLibraryCandidates(root: URL) -> [UserLibraryFileCandidate]? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var out: [UserLibraryFileCandidate] = []
        for case let url as URL in en {
            if Task.isCancelled { return out }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if let candidate = makeUserLibraryCandidate(url: url, values: values) { out.append(candidate) }
        }
        return out
    }

    private static func userLibrarySignature(_ candidates: [UserLibraryFileCandidate], root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        var hasher = Hasher()
        hasher.combine(rootPath)
        for item in candidates.sorted(by: { $0.url.path < $1.url.path }) {
            hasher.combine(item.url.path)
            hasher.combine(item.fileSize)
            hasher.combine(Int(item.modifiedAt.rounded()))
        }
        return String(hasher.finalize())
    }

    private static func sortUserLibraryItems(_ items: [UserLibraryItem]) -> [UserLibraryItem] {
        items.sorted {
            let folderA = $0.url.deletingLastPathComponent().path
            let folderB = $1.url.deletingLastPathComponent().path
            let folderCompare = folderA.localizedCaseInsensitiveCompare(folderB)
            if folderCompare != .orderedSame { return folderCompare == .orderedAscending }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func buildUserLibraryItem(from candidate: UserLibraryFileCandidate) -> UserLibraryItem? {
        if userLibraryMIDIExtensions.contains(candidate.ext) {
            return UserLibraryItem(url: candidate.url, kind: .midi, fileSize: candidate.fileSize, modifiedAt: candidate.modifiedAt)
        }
        let classified = classifyUserLibraryAudioCandidate(url: candidate.url)
        return UserLibraryItem(url: candidate.url, kind: classified.kind, detectedTempo: classified.tempo, fileSize: candidate.fileSize, modifiedAt: candidate.modifiedAt)
    }

    private static func buildUserLibraryItems(from candidates: [UserLibraryFileCandidate]) -> [UserLibraryItem] {
        sortUserLibraryItems(candidates.compactMap { buildUserLibraryItem(from: $0) })
    }

    private func publishUserLibraryItems(_ items: [UserLibraryItem], statusPrefix: String, finished: Bool = false) {
        userLibraryItems = Self.sortUserLibraryItems(items)
        let ones = userLibraryItems.filter { $0.kind == .oneShot }.count
        let loops = userLibraryItems.filter { $0.kind == .loop }.count
        let midis = userLibraryItems.filter { $0.kind == .midi }.count
        userLibraryScanInProgress = !finished
        userLibraryScanStatus = "\(statusPrefix) \(userLibraryItems.count) files — \(ones) one-shots, \(loops) loops, \(midis) MIDIs"
    }

    func scanUserLibrary() {
        guard !userLibraryFolder.isEmpty else {
            userLibraryScanStatus = "Choose a User Library folder first."
            return
        }
        let root = URL(fileURLWithPath: userLibraryFolder, isDirectory: true).standardizedFileURL
        userLibraryScanTask?.cancel()

        let cachedEnvelope = loadUserLibraryCache(for: root)
        if let cached = cachedEnvelope, !cached.items.isEmpty {
            userLibraryItems = cached.items
            let ones = cached.items.filter { $0.kind == .oneShot }.count
            let loops = cached.items.filter { $0.kind == .loop }.count
            let midis = cached.items.filter { $0.kind == .midi }.count
            userLibraryScanStatus = "Loaded cached library — \(cached.items.count) files (checking for changes in background…) · \(ones) one-shots, \(loops) loops, \(midis) MIDIs"
        } else {
            userLibraryItems = []
            userLibraryScanStatus = "Scanning User Library in background…"
        }
        userLibraryScanInProgress = true

        let cachedSignature = cachedEnvelope?.signature
        userLibraryScanTask = Task.detached(priority: .utility) { [weak self, root, cachedSignature] in
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                await MainActor.run {
                    self?.userLibraryScanInProgress = false
                    self?.userLibraryScanStatus = "⚠️ Could not scan \(root.path)"
                }
                return
            }

            var candidates: [UserLibraryFileCandidate] = []
            var liveItems: [UserLibraryItem] = []
            var batch: [UserLibraryFileCandidate] = []
            var discoveredCount = 0
            let progressive = cachedSignature == nil

            func flushProgressBatch(final: Bool = false) async {
                guard progressive, !batch.isEmpty else { return }
                let currentBatch = batch
                batch.removeAll(keepingCapacity: true)
                let newItems = Self.buildUserLibraryItems(from: currentBatch)
                liveItems.append(contentsOf: newItems)
                await MainActor.run {
                    self?.publishUserLibraryItems(liveItems, statusPrefix: final ? "Scanned" : "Scanning… found", finished: final)
                }
            }

            for case let url as URL in en {
                if Task.isCancelled { return }
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard let candidate = Self.makeUserLibraryCandidate(url: url, values: values) else { continue }
                candidates.append(candidate)
                discoveredCount += 1

                if progressive {
                    batch.append(candidate)
                    if batch.count >= Self.userLibraryBatchSize {
                        await flushProgressBatch()
                    }
                } else if discoveredCount % 256 == 0 {
                    await MainActor.run {
                        self?.userLibraryScanStatus = "Checking User Library for changes… \(discoveredCount) files seen"
                    }
                }
            }

            if Task.isCancelled { return }
            let signature = Self.userLibrarySignature(candidates, root: root)

            if !progressive, let cachedSignature, cachedSignature == signature, let cached = await self?.loadUserLibraryCache(for: root) {
                await MainActor.run {
                    self?.userLibraryItems = cached.items
                    self?.userLibraryScanInProgress = false
                    self?.userLibraryScanStatus = "User Library unchanged — using cached index (\(cached.items.count) files)."
                }
                return
            }

            if progressive {
                await flushProgressBatch(final: true)
                let envelope = UserLibraryCacheEnvelope(rootPath: root.path, signature: signature, scannedAt: Date(), items: Self.sortUserLibraryItems(liveItems))
                await MainActor.run {
                    self?.saveUserLibraryCache(envelope)
                    self?.publishUserLibraryItems(envelope.items, statusPrefix: "Scanned", finished: true)
                }
                return
            }

            await MainActor.run {
                self?.userLibraryItems = []
                self?.userLibraryScanStatus = "Library changed — indexing \(candidates.count) files in background…"
            }

            var indexed: [UserLibraryItem] = []
            var reindexBatch: [UserLibraryFileCandidate] = []
            for candidate in candidates {
                if Task.isCancelled { return }
                reindexBatch.append(candidate)
                if reindexBatch.count >= Self.userLibraryBatchSize {
                    indexed.append(contentsOf: Self.buildUserLibraryItems(from: reindexBatch))
                    reindexBatch.removeAll(keepingCapacity: true)
                    await MainActor.run {
                        self?.publishUserLibraryItems(indexed, statusPrefix: "Indexing… found")
                    }
                }
            }
            if !reindexBatch.isEmpty {
                indexed.append(contentsOf: Self.buildUserLibraryItems(from: reindexBatch))
            }
            let finalItems = Self.sortUserLibraryItems(indexed)
            let envelope = UserLibraryCacheEnvelope(rootPath: root.path, signature: signature, scannedAt: Date(), items: finalItems)
            await MainActor.run {
                self?.saveUserLibraryCache(envelope)
                self?.publishUserLibraryItems(finalItems, statusPrefix: "Scanned", finished: true)
            }
        }
    }

    func previewUserLibraryItem(_ item: UserLibraryItem) {
        stopUserLibraryPreview()
        userLibraryPreviewingID = item.id
        switch item.kind {
        case .oneShot, .loop:
            do {
                let player = try AVAudioPlayer(contentsOf: item.url)
                player.prepareToPlay()
                player.play()
                userLibraryPreviewPlayer = player
                userLibraryPreviewStatus = "Previewing ‘\(item.name)’"
            } catch {
                userLibraryPreviewingID = nil
                userLibraryPreviewStatus = "⚠️ Could not preview ‘\(item.name)’ — \(error.localizedDescription)"
            }
        case .midi:
            previewMIDIUserLibraryItem(item)
        }
    }

    func stopUserLibraryPreview() {
        userLibraryPreviewPlayer?.stop()
        userLibraryPreviewPlayer = nil
        userLibraryMIDIPreviewTask?.cancel()
        userLibraryMIDIPreviewTask = nil
        if let track = selectedTrack, track.kind != .audio {
            for note in 0...127 { engine.audition(track: track, note: note, on: false) }
        }
        userLibraryPreviewingID = nil
        userLibraryPreviewStatus = "Preview stopped."
    }

    private func previewMIDIUserLibraryItem(_ item: UserLibraryItem) {
        let parsed = (try? StandardMIDIImporter.parse(url: item.url)) ?? StandardMIDIImporter.Parsed(notes: [], lengthBeats: Double(project.beatsPerBar))
        let notes = Array(parsed.notes.sorted { $0.start == $1.start ? $0.pitch < $1.pitch : $0.start < $1.start }.prefix(48))
        guard !notes.isEmpty else {
            userLibraryPreviewingID = nil
            userLibraryPreviewStatus = "⚠️ ‘\(item.name)’ has no readable MIDI notes to preview."
            return
        }
        guard let track = selectedTrack ?? project.tracks.first(where: { $0.kind != .audio }), track.kind != .audio else {
            userLibraryPreviewingID = nil
            userLibraryPreviewStatus = "⚠️ Select an instrument/MIDI track before previewing MIDI."
            return
        }
        selectedTrackID = track.id
        userLibraryPreviewStatus = "Previewing MIDI ‘\(item.name)’ on \(track.name)"
        let tempo = max(40.0, min(240.0, project.tempo))
        let secondsPerBeat = 60.0 / tempo
        userLibraryMIDIPreviewTask = Task { [weak self, weak track] in
            var lastStart = 0.0
            for note in notes {
                if Task.isCancelled { break }
                let wait = max(0, note.start - lastStart) * secondsPerBeat
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                lastStart = note.start
                await MainActor.run { [weak self, weak track] in
                    guard let self, let track else { return }
                    self.engine.audition(track: track, note: note.pitch, on: true)
                }
                let duration = max(0.08, min(0.45, note.length * secondsPerBeat))
                Task { [weak self, weak track] in
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    await MainActor.run { [weak self, weak track] in
                        guard let self, let track else { return }
                        self.engine.audition(track: track, note: note.pitch, on: false)
                    }
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.userLibraryPreviewingID = nil
                self.userLibraryPreviewStatus = "Preview finished: ‘\(item.name)’"
            }
        }
    }

    func seedDemoProject() {
        // Real DAW default: clean starter tracks, no surprise demo playback.
        let lead = Track(name: "Instrument 1", kind: .analog, color: .blue)
        let drums = Track(name: "Drum Machine", kind: .drums, color: .purple)
        let seq = Track(name: "Sequencer 1", kind: .sequencer, color: .orange)
        seq.useStepSequencer = true
        let audio = Track(name: "Audio 1", kind: .audio, color: .green)
        project.tracks = [lead, drums, seq, audio]
        project.keyRoot = 0
        project.scale = ScaleLibrary.major
        selectedTrackID = lead.id
    }


    func plugin(withID id: String) -> DiscoveredPlugin? {
        discoveredPlugins.first { $0.id == id }
    }

    private func isSpliceDesktopPlugin(_ plugin: DiscoveredPlugin) -> Bool {
        let hay = (plugin.name + " " + plugin.manufacturer + " " + (plugin.path ?? "")).lowercased()
        return hay.contains("splice") && (hay.contains("sounds") || hay.contains("bridge") || hay.contains("listener"))
    }

    private func bestHostablePlugin(for plugin: DiscoveredPlugin) -> DiscoveredPlugin {
        // Splice's AU has been crash-prone in the field. When the user explicitly
        // selects a VST/VST3 Splice build, do NOT silently substitute the AU just
        // because it has the same marketing name. Keep the bridge boundary intact.
        if isSpliceDesktopPlugin(plugin), plugin.format != .audioUnit { return plugin }
        if plugin.format == .audioUnit { return plugin }
        if let au = discoveredPlugins.first(where: { other in
            other.format == .audioUnit
            && other.role == plugin.role
            && other.name.localizedCaseInsensitiveCompare(plugin.name) == .orderedSame
        }) { return au }
        return plugin
    }

    @discardableResult
    func dropPlugin(_ plugin: DiscoveredPlugin, on targetTrack: Track?) -> Track {
        let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .yellow]
        let track: Track
        if let targetTrack {
            track = targetTrack
        } else {
            track = Track(name: plugin.role == .effect ? "Audio FX" : plugin.name, kind: .analog, color: colors[project.tracks.count % colors.count])
            project.tracks.append(track)
        }

        selectedTrackID = track.id
        let hostable = bestHostablePlugin(for: plugin)
        let isInstrument = plugin.role == .instrument || plugin.role == .unknown

        if isInstrument {
            track.pluginTargetID = hostable.name
            if !track.externalPluginSlots.contains(where: { $0.pluginID == plugin.id || $0.name == plugin.name }) {
                track.externalPluginSlots.insert(ExternalPluginSlot(plugin: plugin, hosted: hostable.format == .audioUnit), at: 0)
            }
            assistantLog.append("plugin: loaded \(hostable.name) on \(track.name)" + (hostable.id == plugin.id ? "" : " via AU match"))
            registerUndo(UndoableEdit(name: "Load \(plugin.name)", undo: { [weak self, weak track] in
                guard let self, let track else { return }
                track.externalPluginSlots.removeAll { $0.pluginID == plugin.id || $0.name == plugin.name }
                if track.pluginTargetID == hostable.name { track.pluginTargetID = nil }
                self.engine.rebuild()
            }, redo: { [weak self, weak track] in
                guard let self, let track else { return }
                _ = self.dropPlugin(plugin, on: track)
            }))
            engine.rebuild()
            engine.start()
            engine.warmUpHostedAudioUnits()
            editStatus = "Loaded \(hostable.name) on ‘\(track.name)’"
        } else {
            if !track.externalPluginSlots.contains(where: { $0.pluginID == plugin.id }) {
                track.externalPluginSlots.append(ExternalPluginSlot(plugin: plugin, hosted: false))
                registerUndo(UndoableEdit(name: "Add \(plugin.name)", undo: { [weak self, weak track] in
                    guard let self, let track else { return }
                    track.externalPluginSlots.removeAll { $0.pluginID == plugin.id }
                    self.engine.refreshDevices(for: track)
                }, redo: { [weak self, weak track] in
                    guard let self, let track else { return }
                    _ = self.dropPlugin(plugin, on: track)
                }))
            }
            assistantLog.append("plugin: added \(plugin.name) to \(track.name) as an external FX slot. Direct AU/VST insert hosting is marked in the rack until the audio bridge is expanded.")
        }
        workspace = .arrangement
        return track
    }

    @discardableResult
    func handlePluginDropText(_ text: String, on targetTrack: Track?) -> Bool {
        handlePluginDropText(text, on: targetTrack, audioClip: nil)
    }

    @discardableResult
    func handlePluginDropText(_ text: String, on targetTrack: Track?, audioClip: AudioClip?) -> Bool {
        if let path = PluginDragPasteboard.samplePath(from: text) {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()
            if ["mid", "midi"].contains(ext) { importMIDIFileAsClip(url, on: targetTrack, forceNewTrack: targetTrack == nil); return true }
            if ["wav", "wave", "aif", "aiff", "mp3", "m4a", "flac", "caf", "ogg"].contains(ext) {
                do {
                    try importAudioFile(url, targetTrack: targetTrack, forceNewTrack: targetTrack == nil)
                } catch { editStatus = "⚠️ Audio import failed: \(error.localizedDescription)" }
                return true
            }
            _ = addSampleLayer(url, to: targetTrack)
            return true
        }
        if let spliceID = PluginDragPasteboard.spliceSampleID(from: text), let sample = spliceResults.first(where: { $0.id == spliceID }) {
            let resolved = rememberSpliceHiddenAsset(sample)
            spliceStatus = "Fetch-on-drop: asking official Splice MCP to license/download ‘\(resolved.name)’ into Arrangement…"
            Task { await downloadAndImportSplice(resolved) }
            return true
        }
        if let pluginID = PluginDragPasteboard.pluginID(from: text), let plugin = plugin(withID: pluginID) {
            if let audioClip, plugin.role == .effect || plugin.role == .unknown {
                if !audioClip.externalPluginSlots.contains(where: { $0.pluginID == plugin.id }) {
                    audioClip.externalPluginSlots.append(ExternalPluginSlot(plugin: plugin, hosted: plugin.format == .audioUnit))
                    editStatus = "Added \(plugin.name) to clip FX"
                    registerUndo(UndoableEdit(name: "Add \(plugin.name) to Clip", undo: { [weak self, weak audioClip] in
                        audioClip?.externalPluginSlots.removeAll { $0.pluginID == plugin.id }
                        self?.editStatus = "Removed \(plugin.name) from clip"
                    }, redo: { [weak self, weak audioClip] in
                        guard let audioClip else { return }
                        audioClip.externalPluginSlots.append(ExternalPluginSlot(plugin: plugin, hosted: plugin.format == .audioUnit))
                        self?.editStatus = "Added \(plugin.name) to clip FX"
                    }))
                }
                return true
            }
            let track = dropPlugin(plugin, on: targetTrack)
            if let slot = track.externalPluginSlots.first(where: { existing in
                pluginsEquivalent(existing.pluginID, plugin.id) || pluginsEquivalent(existing.name, plugin.name)
            }) {
                // Drag/drop handlers can be invoked from nonisolated SwiftUI/AppKit
                // callbacks. Opening plug-in editors is UI work, so hop to the
                // main actor explicitly instead of synchronously crossing actor
                // isolation and breaking Swift 6/Xcode beta builds.
                Task { @MainActor [weak self] in
                    self?.openPluginGUI(slot)
                }
            }
            return true
        }
        if let kind = PluginDragPasteboard.effectKind(from: text) {
            if let audioClip {
                addEffect(kind, to: audioClip)
                return true
            }
            let track = targetTrack ?? selectedTrack
            guard let track else { return false }
            addEffect(kind, to: track)
            return true
        }
        return false
    }


    @discardableResult
    func handlePluginDropTextOnStepSequencer(_ text: String, on track: Track, step: Int?, laneNote: Int?) -> Bool {
        guard let pluginID = PluginDragPasteboard.pluginID(from: text), let plugin = plugin(withID: pluginID) else {
            return false
        }
        let hostable = bestHostablePlugin(for: plugin)
        let isInstrument = plugin.role == .instrument || plugin.role == .unknown
        guard isInstrument else {
            _ = dropPlugin(plugin, on: track)
            return true
        }

        track.kind = .sequencer
        track.useStepSequencer = true
        track.pluginTargetID = hostable.name
        if !track.externalPluginSlots.contains(where: { $0.pluginID == plugin.id || $0.name == plugin.name }) {
            track.externalPluginSlots.insert(ExternalPluginSlot(plugin: plugin, hosted: hostable.format == .audioUnit), at: 0)
        }

        let note: Int
        if let laneNote {
            note = laneNote
        } else {
            let used = Set(track.sequencerLayers.map(\.note))
            note = (72...96).first { !used.contains($0) } ?? ((track.sequencerLayers.map(\.note).max() ?? 71) + 1)
        }
        let rootName = project.key.displayName
        let layerName = "\(plugin.name) · Root"
        if let idx = track.sequencerLayers.firstIndex(where: { $0.note == note }) {
            track.sequencerLayers[idx].name = layerName
            track.sequencerLayers[idx].source = .plugin
            track.sequencerLayers[idx].pluginTargetID = hostable.name
            track.sequencerLayers[idx].samplePath = nil
            track.sequencerLayers[idx].velocity = 0.9
            if track.sequencerLayers[idx].steps.count != track.stepPattern.stepCount {
                track.sequencerLayers[idx].steps = Array(repeating: false, count: track.stepPattern.stepCount)
            }
            if let step, track.sequencerLayers[idx].steps.indices.contains(step) {
                track.sequencerLayers[idx].steps[step] = true
                track.stepPattern.setHit(step: step, note: note, enabled: true, velocity: 0.9)
            }
        } else {
            var layer = SequencerLayer(name: layerName, source: .plugin, note: note, stepCount: track.stepPattern.stepCount, velocity: 0.9, pluginTargetID: hostable.name)
            if let step, layer.steps.indices.contains(step) {
                layer.steps[step] = true
                track.stepPattern.setHit(step: step, note: note, enabled: true, velocity: 0.9)
            }
            track.sequencerLayers.append(layer)
        }
        selectedTrackID = track.id
        workspace = .step
        editStatus = "Loaded \(plugin.name) into Step Sequencer · steps play \(rootName) root by default"
        muteStepSequencerPreviewClips(on: track)
        engine.resetStepSequencerState(for: track)
        engine.rebuild()
        return true
    }

    @MainActor
    func usePluginSlot(_ slot: ExternalPluginSlot, on track: Track) {
        track.pluginTargetID = slot.name
        if slot.role != .effect { track.kind = .analog }
        selectedTrackID = track.id
        engine.rebuild()
        openPluginGUI(slot)
    }

    @MainActor
    func openPluginGUI(_ slot: ExternalPluginSlot) {
        // Prefer hosting an Audio Unit whenever one exists for this plug-in — even
        // if the user picked the VST/VST3 variant. AU hosting is sandboxed
        // (out-of-process), needs no external Carla install, opens an editor window
        // owned by Lemmings, and is the path that actually works for Splice Sounds.
        // Carla is only for plug-ins with no AU at all.
        if slot.hosted || slot.format == .audioUnit || audioUnitComponent(for: slot) != nil {
            openHostedAudioUnitEditor(for: slot)
            return
        }
        CarlaBridgeSupport.openBridge(forPluginName: slot.name, pluginPath: slot.path, format: slot.format) { [weak self] status in
            self?.carlaBridgeStatus = status
            self?.editStatus = status
            self?.pluginScanStatus = status
        }
    }

    @MainActor
    private func openHostedAudioUnitEditor(for slot: ExternalPluginSlot) {
        guard let component = audioUnitComponent(for: slot) else {
            if let path = slot.path {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                editStatus = "Could not find an installed AU component for \(slot.name); revealed the bundle instead."
            } else {
                editStatus = "Could not find an installed Audio Unit editor for \(slot.name). Try rescanning plug-ins."
            }
            return
        }

        if let liveUnit = liveHostedAudioUnit(for: slot) {
            showHostedAudioUnitEditor(title: slot.name, audioUnit: liveUnit, windowKey: slot.id)
            editStatus = "Opened live \(slot.name) Audio Unit window — this is the same instance the Sound Agent will automate and record."
            return
        }

        // Instruments must never open as detached editor-only AUs. If the rack row
        // came from drag/drop, a VST3 browser entry, or a stale selection, attach it
        // to a real instrument track automatically and open that live engine AU.
        if slot.role == .instrument || component.audioComponentDescription.componentType == kAudioUnitType_MusicDevice {
            let track = ensureHostedAudioUnitTrack(for: slot, component: component)
            engine.rebuild()
            engine.start()
            engine.warmUpHostedAudioUnits()
            if let liveUnit = liveHostedAudioUnit(for: slot, on: track) {
                showHostedAudioUnitEditor(title: slot.name, audioUnit: liveUnit, windowKey: slot.id)
                editStatus = "Loaded \(slot.name) on ‘\(track.name)’ and opened its live Audio Unit editor."
                return
            }

            // Some vendors expose slightly different AU names than their VST row
            // (Serum2 vs Serum 2). Retarget to the exact AU component name and try
            // once more before reporting a genuine instantiation failure.
            track.pluginTargetID = component.name
            engine.resetHostedAudioUnit(for: track)
            engine.rebuild()
            engine.start()
            engine.warmUpHostedAudioUnits()
            if let liveUnit = liveHostedAudioUnit(for: slot, on: track) {
                showHostedAudioUnitEditor(title: component.name, audioUnit: liveUnit, windowKey: slot.id)
                editStatus = "Loaded \(component.name) on ‘\(track.name)’ and opened its live Audio Unit editor."
                return
            }
            editStatus = "Could not load \(slot.name) as a live Audio Unit. The plug-in may have failed AU instantiation; try opening it once in another DAW or rescanning Audio Units."
            return
        }

        editStatus = "Loading \(slot.name) Audio Unit effect editor…"
        let desc = component.audioComponentDescription
        // IMPORTANT: load third-party Audio Units OUT OF PROCESS.
        //
        // Some plugins (notably "Splice Sounds", which embeds WebKit + a Rust/tokio
        // runtime + JUCE) crash inside their own worker/preview threads — e.g.
        // `splice::toBufferView(...)` null-derefs while you scroll its browser after
        // a search. With `.loadInProcess` that segfault happens in OUR address space
        // and takes Lemmings down with it. Hosting out-of-process puts the plugin in
        // a separate audio-component host process, so if it crashes, the worst case
        // is the plugin window dies — Lemmings stays alive. This is the same
        // isolation Logic/GarageBand use for flaky AUs.
        instantiateHostedAudioUnit(desc: desc, name: slot.name) { [weak self] unit, error, sandboxed in
            guard let self else { return }
            if let error {
                self.editStatus = "Could not load \(slot.name): \(error.localizedDescription)"
                return
            }
            guard let unit else {
                self.editStatus = "Audio Unit instantiation returned nil for \(slot.name)."
                return
            }
            let controller = LemmingsPluginEditorWindowController(title: slot.name, audioUnit: unit.auAudioUnit)
            self.pluginEditorWindows[slot.id] = controller
            controller.show { [weak self] in
                Task { @MainActor in self?.pluginEditorWindows.removeValue(forKey: slot.id) }
            }
            self.editStatus = sandboxed
                ? "Opened \(slot.name) (sandboxed — if the plug-in crashes, Lemmings stays up)"
                : "Opened \(slot.name) Audio Unit window (in-process — a plug-in crash can still affect Lemmings)"
        }
    }

    @MainActor
    private func liveHostedAudioUnit(for slot: ExternalPluginSlot) -> AUAudioUnit? {
        if let selected = selectedTrack, let unit = liveHostedAudioUnit(for: slot, on: selected) { return unit }
        for track in project.tracks {
            if let unit = liveHostedAudioUnit(for: slot, on: track) { return unit }
        }
        return nil
    }

    @MainActor
    private func liveHostedAudioUnit(for slot: ExternalPluginSlot, on track: Track) -> AUAudioUnit? {
        let trackHostsSlot = track.externalPluginSlots.contains { existing in
            existing.id == slot.id
            || pluginsEquivalent(existing.name, slot.name)
            || pluginsEquivalent(existing.pluginID, slot.pluginID)
        }
        let trackTargetsSlot = track.pluginTargetID.map { pluginsEquivalent($0, slot.name) || pluginsEquivalent($0, slot.pluginID) } ?? false
        guard trackHostsSlot || trackTargetsSlot else { return nil }
        guard let hosted = engine.liveInstrument(for: track) as? HostedAUInstrument else { return nil }
        let hostedName = hosted.displayName
        let targetName = track.pluginTargetID ?? slot.name
        guard pluginsEquivalent(hostedName, targetName) || pluginsEquivalent(hostedName, slot.name) || pluginsEquivalent(targetName, slot.name) else { return nil }
        return hosted.hostedAudioUnit
    }

    @MainActor
    private func ensureHostedAudioUnitTrack(for slot: ExternalPluginSlot, component: AVAudioUnitComponent) -> Track {
        if let track = project.tracks.first(where: { track in
            track.externalPluginSlots.contains(where: { existing in
                existing.id == slot.id
                || pluginsEquivalent(existing.name, slot.name)
                || pluginsEquivalent(existing.pluginID, slot.pluginID)
            })
        }) {
            configure(track: track, toHost: slot, component: component)
            selectedTrackID = track.id
            return track
        }

        if let selected = selectedTrack, selected.kind != .audio || slot.role != .instrument {
            configure(track: selected, toHost: slot, component: component)
            selectedTrackID = selected.id
            return selected
        }

        let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .yellow]
        let track = Track(name: component.name.isEmpty ? slot.name : component.name, kind: .analog, color: colors[project.tracks.count % colors.count])
        project.tracks.append(track)
        configure(track: track, toHost: slot, component: component)
        selectedTrackID = track.id
        workspace = .arrangement
        return track
    }

    @MainActor
    private func configure(track: Track, toHost slot: ExternalPluginSlot, component: AVAudioUnitComponent) {
        track.kind = .analog
        track.pluginTargetID = component.name.isEmpty ? slot.name : component.name
        if !track.externalPluginSlots.contains(where: { existing in
            existing.id == slot.id
            || pluginsEquivalent(existing.name, slot.name)
            || pluginsEquivalent(existing.pluginID, slot.pluginID)
        }) {
            var hostedSlot = slot
            hostedSlot.name = component.name.isEmpty ? slot.name : component.name
            hostedSlot.format = .audioUnit
            hostedSlot.role = .instrument
            hostedSlot.hosted = true
            track.externalPluginSlots.insert(hostedSlot, at: 0)
        }
    }

    @MainActor
    private func showHostedAudioUnitEditor(title: String, audioUnit: AUAudioUnit, windowKey: UUID) {
        let controller = LemmingsPluginEditorWindowController(title: title, audioUnit: audioUnit)
        pluginEditorWindows[windowKey] = controller
        controller.show { [weak self] in
            Task { @MainActor in self?.pluginEditorWindows.removeValue(forKey: windowKey) }
        }
    }

    /// Instantiate an Audio Unit out-of-process first (crash isolation), falling
    /// back to in-process only if the sandbox load fails (some AUv2-only plug-ins
    /// can't be hosted out-of-process). The completion reports whether we ended up
    /// sandboxed so the UI can be honest about the safety guarantee.
    @MainActor
    private func instantiateHostedAudioUnit(desc: AudioComponentDescription,
                                            name: String,
                                            completion: @escaping (AVAudioUnit?, Error?, Bool) -> Void) {
        AVAudioUnit.instantiate(with: desc, options: [.loadOutOfProcess]) { unit, error in
            DispatchQueue.main.async {
                if let unit {
                    completion(unit, nil, true)
                    return
                }
                // Out-of-process failed — fall back to in-process so the user still
                // gets an editor, but flag that it isn't sandboxed.
                AVAudioUnit.instantiate(with: desc, options: []) { inUnit, inError in
                    DispatchQueue.main.async {
                        completion(inUnit, inUnit == nil ? (inError ?? error) : nil, false)
                    }
                }
            }
        }
    }

    private func audioUnitComponent(for slot: ExternalPluginSlot) -> AVAudioUnitComponent? {
        let manager = AVAudioUnitComponentManager.shared()
        let roleRoles: [OSType]
        switch slot.role {
        case .instrument:
            roleRoles = [kAudioUnitType_MusicDevice, kAudioUnitType_MusicEffect]
        case .effect:
            roleRoles = [kAudioUnitType_Effect, kAudioUnitType_MusicEffect]
        case .unknown:
            roleRoles = [kAudioUnitType_MusicDevice, kAudioUnitType_MusicEffect, kAudioUnitType_Effect]
        }
        // Try the role-appropriate types first, then fall back to ALL AU types.
        // This matters for the AU-counterpart check: a VST3 slot is often tagged
        // `.effect` during discovery, but Splice Sounds is actually a MusicDevice
        // (instrument) AU — without the broad fallback we'd miss its AU and wrongly
        // fall through to the fragile Carla/VST3 path.
        let allRoles = [kAudioUnitType_MusicDevice, kAudioUnitType_MusicEffect, kAudioUnitType_Effect]
        let roles = roleRoles + allRoles.filter { !roleRoles.contains($0) }
        let needles = [slot.name, slot.pluginID]
            .map { $0.lowercased().replacingOccurrences(of: " ", with: "") }
            .filter { !$0.isEmpty }
        for type in roles {
            var desc = AudioComponentDescription()
            desc.componentType = type
            for component in manager.components(matching: desc) {
                let hay = [component.name, component.manufacturerName]
                    .joined(separator: " ")
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "")
                if needles.contains(where: { hay.contains($0) || $0.contains(hay) }) {
                    return component
                }
            }
        }
        return nil
    }

    enum OpenSampleSource: String, CaseIterable, Identifiable {
        case vscoOrchestra = "VSCO 2 CE Orchestra"
        case vcslWorld = "VCSL World / Acoustic"
        case openSamples = "Open Samples Community"
        case infiniteState = "Infinite State Synths + Loops"
        case bhangraGuide = "Bhangra / Indian Percussion Sources"
        var id: String { rawValue }
        var url: URL? {
            switch self {
            case .vscoOrchestra: return URL(string: "https://github.com/sgossner/VSCO-2-CE/archive/refs/heads/master.zip")
            case .vcslWorld: return URL(string: "https://github.com/sgossner/VCSL/archive/refs/heads/master.zip")
            case .openSamples: return URL(string: "https://github.com/pumodi/open-samples/archive/refs/heads/master.zip")
            case .infiniteState: return URL(string: "https://github.com/kennethreitz/infinite-state-sample-pack/archive/refs/heads/master.zip")
            case .bhangraGuide: return nil
            }
        }
        var licenseNote: String {
            switch self {
            case .vscoOrchestra: return "VSCO 2 CE is CC0/public-domain style; excellent orchestral base."
            case .vcslWorld: return "VCSL is CC0 and includes world/acoustic/percussion material."
            case .openSamples: return "Community open samples; verify individual pack metadata before redistribution."
            case .infiniteState: return "Open-source synth/drum-loop pack; verify bundled license text before redistribution."
            case .bhangraGuide: return "No verified CC0 Bhangra pack found yet; use Splice/owned samples or VCSL world percussion until a verified pack is added."
            }
        }
    }

    func applyProjectKey(root: PitchClass? = nil, scale: Scale? = nil) {
        let requestedRoot = root ?? project.keyRoot
        project.keyRoot = ((requestedRoot % 12) + 12) % 12
        if let scale { project.scale = scale }
        editStatus = "Project key set to \(project.key.displayName)"
        engine.rebuild()
        refreshDiscordPresence()
    }


    func startVoiceAIRecording() {
        guard !voiceAIRecording else { return }
        let folder = URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + "/Music/Lemmings Studio/Voice Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent("voice-capture-\(stamp).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else {
                voiceAIStatus = "Microphone capture could not start. Check macOS microphone permission for LemmingsStudio."
                return
            }
            voiceAIScratchRecorder = recorder
            voiceAIScratchURL = url
            voiceAIRecording = true
            voiceAIStatus = "Recording dry vocal input inside LemmingsStudio… sing close to the mic, avoid reverb/noise, then Stop + Use."
        } catch {
            voiceAIStatus = "Voice recording failed: \(error.localizedDescription)"
        }
    }

    func stopVoiceAIRecording(useAsInput: Bool = true) {
        guard voiceAIRecording else { return }
        voiceAIScratchRecorder?.stop()
        voiceAIScratchRecorder = nil
        voiceAIRecording = false
        guard let url = voiceAIScratchURL, FileManager.default.fileExists(atPath: url.path) else {
            voiceAIStatus = "Recording stopped, but no capture file was created."
            return
        }
        if useAsInput {
            voiceAIInputAudioPath = url.path
            voiceAIStatus = "Recorded input vocal: \(url.lastPathComponent). Ready for Render + Import."
        } else {
            voiceAIStatus = "Recorded vocal saved: \(url.lastPathComponent)."
        }
    }

    func cancelVoiceAIRecording() {
        guard voiceAIRecording else { return }
        voiceAIScratchRecorder?.stop()
        voiceAIScratchRecorder = nil
        voiceAIRecording = false
        if let url = voiceAIScratchURL { try? FileManager.default.removeItem(at: url) }
        voiceAIScratchURL = nil
        voiceAIStatus = "Voice recording cancelled."
    }

    func selectVoiceAIInputAudio() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["wav", "wave", "aif", "aiff", "mp3", "m4a", "caf", "flac"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        voiceAIInputAudioPath = url.path
        voiceAIStatus = "Selected input: \(url.lastPathComponent)"
    }

    func chooseVoiceAIOutputFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        voiceAIOutputFolder = url.path
        UserDefaults.standard.set(url.path, forKey: "voiceAIOutputFolder")
        voiceAIStatus = "Voice renders will go to \(url.lastPathComponent)"
    }

    func importVoiceModelFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        voiceModels.importModel(at: url)
        selectedVoiceModelID = voiceModels.imported.last?.id ?? selectedVoiceModelID
        voiceAIStatus = voiceModels.status
    }

    func selectVoiceCloneTrainingFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        voiceCloneTrainingFolder = url.path
        voiceAIStatus = "Training dataset selected: \(url.lastPathComponent). Training/export wiring is scaffolded; use only consented dry vocals."
    }

    func renderVoiceToVoice() {
        guard !voiceAIInputAudioPath.isEmpty else {
            voiceAIStatus = "Pick an input vocal first."
            return
        }
        let input = URL(fileURLWithPath: voiceAIInputAudioPath)
        guard FileManager.default.fileExists(atPath: input.path) else {
            voiceAIStatus = "Input vocal does not exist."
            return
        }
        let allModels = voiceModels.repository + voiceModels.imported
        guard let model = allModels.first(where: { $0.id == selectedVoiceModelID }) ?? allModels.first else {
            voiceAIStatus = "Import or select a voice model first."
            return
        }
        let outputRoot = voiceAIOutputFolder.isEmpty
            ? URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.path + "/Music/Lemmings Studio/Voice Renders", isDirectory: true)
            : URL(fileURLWithPath: voiceAIOutputFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        voiceAIStatus = "Rendering voice-to-voice with \(model.name)…"
        Task { [weak self] in
            guard let self else { return }
            let result = await self.voiceModels.transform(inputAudio: input, using: model, outputDirectory: outputRoot, bundledPython: nil)
            await MainActor.run {
                if let result {
                    self.voiceAIStatus = "Rendered singing voice conversion → \(result.lastPathComponent)"
                    self.importMediaFile(result)
                } else {
                    self.voiceAIStatus = self.voiceModels.status
                }
            }
        }
    }

    func downloadOpenSampleLibrary(_ source: OpenSampleSource) {
        guard let url = source.url else {
            openSampleStatus = "Bhangra downloader is metadata-only for now: no verified CC0 Bhangra sample repository has been bundled. Use Splice/owned packs or VCSL world percussion."
            return
        }
        let libraryRoot = userLibraryFolder.isEmpty ? (FileManager.default.homeDirectoryForCurrentUser.path + "/Music/Lemmings Studio/User Library") : userLibraryFolder
        let base = URL(fileURLWithPath: libraryRoot, isDirectory: true)
            .appendingPathComponent("Open Samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let dest = base.appendingPathComponent(source.rawValue.replacingOccurrences(of: " / ", with: "-").replacingOccurrences(of: " ", with: "_") + ".zip")
        openSampleStatus = "Downloading \(source.rawValue)…"
        Task { [weak self] in
            do {
                let (tmp, _) = try await URLSession.shared.download(from: url)
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.moveItem(at: tmp, to: dest)
                self?.openSampleStatus = "Downloaded \(source.rawValue) → \(dest.lastPathComponent). Unzip/import from your User Library when ready."
                self?.scanUserLibrary()
            } catch {
                self?.openSampleStatus = "⚠️ Download failed for \(source.rawValue): \(error.localizedDescription)"
            }
        }
    }

    private func builtInInstrumentKind(for deviceKind: DeviceKind) -> InstrumentKind? {
        switch deviceKind {
        case .analog, .drift, .operatorSynth, .poli, .wavetable, .meld, .emit, .vectorFM, .vectorGrain, .treeTone, .collision, .tension, .electric:
            return .analog
        case .bass, .lemmingBass:
            return .lemmingBass
        case .oscillatron:
            return .oscillatron
        case .bhangraArchitect:
            return .bhangraArchitect
        case .guaracha2C:
            return .guaracha2C
        case .bailaton:
            return .bailaton
        case .dubstepWrangler:
            return .dubstepWrangler
        case .drumRack, .impulse, .dsClap, .dsClang, .dsCymbal, .dsHH, .dsKick, .dsSnare, .dsTone:
            return .drums
        default:
            return nil
        }
    }

    @discardableResult
    private func loadBuiltInInstrumentDevice(_ kind: DeviceKind, on track: Track, recordsUndo: Bool = true) -> Bool {
        guard let instrumentKind = builtInInstrumentKind(for: kind) else { return false }
        let oldKind = track.kind
        let oldName = track.name
        let oldUseStepSequencer = track.useStepSequencer
        let oldDevices = track.devices.map { cloneDevice($0) }
        track.kind = instrumentKind
        if oldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || oldName == oldKind.rawValue || oldName == "Audio" || oldName == "Audio Track" {
            track.name = kind.rawValue
        }
        // Oscillatron and LemmingBass are real keyboard instruments, not insert FX
        // and not hidden step sequencer shells. Step/generator devices keep their
        // grid behavior; synth/bass devices stay piano-roll/MIDI driven.
        track.useStepSequencer = instrumentKind.isStepEditable
        ensureBuiltInInstrumentDevice(kind, on: track)
        selectedTrackID = track.id
        detailDeck = .devices
        workspace = .arrangement
        editStatus = "Loaded built-in instrument \(kind.rawValue) on ‘\(track.name)’"
        if recordsUndo {
            registerUndo(UndoableEdit(name: "Load \(kind.rawValue)", undo: { [weak self, weak track] in
                guard let self, let track else { return }
                track.kind = oldKind
                track.name = oldName
                track.useStepSequencer = oldUseStepSequencer
                track.devices = oldDevices.map { self.cloneDevice($0) }
                self.engine.rebuild()
            }, redo: { [weak self, weak track] in
                guard let self, let track else { return }
                _ = self.loadBuiltInInstrumentDevice(kind, on: track, recordsUndo: false)
            }))
        }
        engine.rebuild()
        return true
    }

    func ensureBuiltInInstrumentDevice(_ kind: DeviceKind, on track: Track) {
        guard builtInInstrumentKind(for: kind) != nil else { return }
        track.devices.removeAll { builtInInstrumentKind(for: $0.kind) != nil }
        let model = DeviceModel(kind: kind)
        track.devices.insert(model, at: 0)
    }

    func ensureVisibleInstrumentDevice(on track: Track) {
        guard track.devices.allSatisfy({ builtInInstrumentKind(for: $0.kind) == nil }) else { return }
        switch track.kind {
        case .oscillatron: ensureBuiltInInstrumentDevice(.oscillatron, on: track)
        case .lemmingBass: ensureBuiltInInstrumentDevice(.lemmingBass, on: track)
        default: return
        }
        engine.refreshDevices(for: track)
    }

    func addEffect(_ kind: DeviceKind, to track: Track) {
        if loadBuiltInInstrumentDevice(kind, on: track) { return }
        let device = DeviceModel(kind: kind)
        track.devices.append(device)
        selectedTrackID = track.id
        detailDeck = .devices
        workspace = .arrangement
        editStatus = "Added \(kind.rawValue) to track ‘\(track.name)’"
        registerUndo(UndoableEdit(name: "Add \(kind.rawValue)", undo: { [weak self, weak track] in
            guard let self, let track else { return }
            track.devices.removeAll { $0.id == device.id }
            self.engine.refreshDevices(for: track)
        }, redo: { [weak self, weak track] in
            guard let self, let track else { return }
            track.devices.append(device)
            self.engine.refreshDevices(for: track)
        }))
        engine.refreshDevices(for: track)
    }

    func addEffect(_ kind: DeviceKind, to clip: AudioClip) {
        if builtInInstrumentKind(for: kind) != nil {
            editStatus = "\(kind.rawValue) is an instrument. Add it to a MIDI/instrument track, not as a clip insert."
            return
        }
        let device = DeviceModel(kind: kind)
        clip.devices.append(device)
        selectedAudioClipID = clip.id
        editStatus = "Added \(kind.rawValue) to selected clip"
        registerUndo(UndoableEdit(name: "Add \(kind.rawValue) to Clip", undo: { [weak self, weak clip] in
            clip?.devices.removeAll { $0.id == device.id }
            self?.editStatus = "Removed \(kind.rawValue) from clip"
        }, redo: { [weak self, weak clip] in
            clip?.devices.append(device)
            self?.editStatus = "Added \(kind.rawValue) to selected clip"
        }))
    }

    func addEffect(_ kind: DeviceKind, to group: TrackGroup) {
        if builtInInstrumentKind(for: kind) != nil {
            editStatus = "\(kind.rawValue) is an instrument. Create/load it on a track instead of a group bus."
            return
        }
        let device = DeviceModel(kind: kind)
        group.devices.append(device)
        editStatus = "Added \(kind.rawValue) to group ‘\(group.name)’"
        engine.rebuild()
    }

    func addEffect(_ kind: DeviceKind, to returnBus: ReturnBus) {
        if builtInInstrumentKind(for: kind) != nil {
            editStatus = "\(kind.rawValue) is an instrument. Create/load it on a track instead of a return bus."
            return
        }
        returnBus.devices.append(DeviceModel(kind: kind))
        editStatus = "Added \(kind.rawValue) to bus ‘\(returnBus.name)’"
        engine.rebuild()
    }

    func makeFXChain(on track: Track, deviceIDs: Set<UUID>, name: String = "FX Chain") {
        let selected = track.devices.filter { deviceIDs.contains($0.id) }
        guard selected.count > 1 else { return }
        track.devices.removeAll { deviceIDs.contains($0.id) }
        let rack = DeviceModel(kind: .audioEffectRack, params: ["chains": Double(selected.count), "macro1": 0.5])
        track.devices.append(rack)
        for d in selected { track.devices.append(d) }
        editStatus = "Created \(name) from \(selected.count) FX on \(track.name)"
        engine.refreshDevices(for: track)
    }

    func moveDevice(on track: Track, from source: IndexSet, to destination: Int) {
        track.devices.move(fromOffsets: source, toOffset: destination)
        editStatus = "Reordered FX on \(track.name)"
        engine.refreshDevices(for: track)
    }


    func insertEffect(_ kind: DeviceKind, to track: Track, at index: Int) {
        if loadBuiltInInstrumentDevice(kind, on: track) { return }
        let device = DeviceModel(kind: kind)
        let target = max(0, min(index, track.devices.count))
        track.devices.insert(device, at: target)
        selectedTrackID = track.id
        selectedMixerDeviceTrackID = track.id
        selectedMixerDeviceIDs = [device.id]
        editStatus = "Inserted \(kind.rawValue) at slot \(target + 1) on \(track.name)"
        registerUndo(UndoableEdit(name: "Insert \(kind.rawValue)", undo: { [weak self, weak track] in
            guard let self, let track else { return }
            track.devices.removeAll { $0.id == device.id }
            self.engine.refreshDevices(for: track)
        }, redo: { [weak self, weak track] in
            guard let self, let track else { return }
            let redoIndex = max(0, min(target, track.devices.count))
            track.devices.insert(device, at: redoIndex)
            self.engine.refreshDevices(for: track)
        }))
        engine.refreshDevices(for: track)
    }

    func insertEffect(_ kind: DeviceKind, to group: TrackGroup, at index: Int) {
        if builtInInstrumentKind(for: kind) != nil {
            editStatus = "\(kind.rawValue) is an instrument. Create/load it on a track instead of a group bus."
            return
        }
        let device = DeviceModel(kind: kind)
        group.devices.insert(device, at: max(0, min(index, group.devices.count)))
        editStatus = "Inserted \(kind.rawValue) on group ‘\(group.name)’"
        engine.rebuild()
    }

    func insertEffect(_ kind: DeviceKind, to returnBus: ReturnBus, at index: Int) {
        if builtInInstrumentKind(for: kind) != nil {
            editStatus = "\(kind.rawValue) is an instrument. Create/load it on a track instead of a return bus."
            return
        }
        let device = DeviceModel(kind: kind)
        returnBus.devices.insert(device, at: max(0, min(index, returnBus.devices.count)))
        editStatus = "Inserted \(kind.rawValue) on bus ‘\(returnBus.name)’"
        engine.rebuild()
    }

    @discardableResult
    func handleMixerDeviceDropText(_ text: String, on track: Track, at index: Int) -> Bool {
        if let source = PluginDragPasteboard.mixerDevice(from: text) {
            return moveMixerDevice(source, toOwnerKind: "track", toOwnerID: track.id, at: index)
        }
        if let kind = PluginDragPasteboard.effectKind(from: text) {
            insertEffect(kind, to: track, at: index)
            return true
        }
        if let pluginID = PluginDragPasteboard.pluginID(from: text), let plugin = plugin(withID: pluginID) {
            // External plug-ins do not yet have reorderable insert slots in the compact mixer;
            // adding them here still respects the user's drop target strip.
            dropPlugin(plugin, on: track)
            return true
        }
        return false
    }

    @discardableResult
    func handleMixerDeviceDropText(_ text: String, on group: TrackGroup, at index: Int) -> Bool {
        if let source = PluginDragPasteboard.mixerDevice(from: text) {
            return moveMixerDevice(source, toOwnerKind: "group", toOwnerID: group.id, at: index)
        }
        if let kind = PluginDragPasteboard.effectKind(from: text) {
            insertEffect(kind, to: group, at: index)
            return true
        }
        return false
    }

    @discardableResult
    func handleMixerDeviceDropText(_ text: String, on returnBus: ReturnBus, at index: Int) -> Bool {
        if let source = PluginDragPasteboard.mixerDevice(from: text) {
            return moveMixerDevice(source, toOwnerKind: "bus", toOwnerID: returnBus.id, at: index)
        }
        if let kind = PluginDragPasteboard.effectKind(from: text) {
            insertEffect(kind, to: returnBus, at: index)
            return true
        }
        return false
    }

    @discardableResult
    private func moveMixerDevice(_ source: (ownerKind: String, ownerID: UUID, deviceID: UUID), toOwnerKind: String, toOwnerID: UUID, at rawIndex: Int) -> Bool {
        guard let device = removeMixerDevice(ownerKind: source.ownerKind, ownerID: source.ownerID, deviceID: source.deviceID) else { return false }
        var targetIndex = rawIndex
        if source.ownerKind == toOwnerKind && source.ownerID == toOwnerID, let oldIndex = device.lastKnownIndex, oldIndex < rawIndex {
            targetIndex -= 1
        }
        insertMixerDevice(device.model, ownerKind: toOwnerKind, ownerID: toOwnerID, at: targetIndex)
        editStatus = "Moved \(device.model.kind.rawValue) to slot \(max(0, targetIndex) + 1)"
        if toOwnerKind == "track", let track = project.tracks.first(where: { $0.id == toOwnerID }) {
            selectedTrackID = track.id
            selectedMixerDeviceTrackID = track.id
            selectedMixerDeviceIDs = [device.model.id]
            engine.refreshDevices(for: track)
        } else {
            engine.rebuild()
        }
        return true
    }

    private func removeMixerDevice(ownerKind: String, ownerID: UUID, deviceID: UUID) -> (model: DeviceModel, lastKnownIndex: Int?)? {
        switch ownerKind {
        case "track":
            guard let track = project.tracks.first(where: { $0.id == ownerID }), let idx = track.devices.firstIndex(where: { $0.id == deviceID }) else { return nil }
            return (track.devices.remove(at: idx), idx)
        case "group":
            guard let group = project.groups.first(where: { $0.id == ownerID }), let idx = group.devices.firstIndex(where: { $0.id == deviceID }) else { return nil }
            return (group.devices.remove(at: idx), idx)
        case "bus":
            guard let bus = project.returnBuses.first(where: { $0.id == ownerID }), let idx = bus.devices.firstIndex(where: { $0.id == deviceID }) else { return nil }
            return (bus.devices.remove(at: idx), idx)
        default:
            return nil
        }
    }

    private func insertMixerDevice(_ device: DeviceModel, ownerKind: String, ownerID: UUID, at index: Int) {
        switch ownerKind {
        case "track":
            guard let track = project.tracks.first(where: { $0.id == ownerID }) else { return }
            track.devices.insert(device, at: max(0, min(index, track.devices.count)))
        case "group":
            guard let group = project.groups.first(where: { $0.id == ownerID }) else { return }
            group.devices.insert(device, at: max(0, min(index, group.devices.count)))
        case "bus":
            guard let bus = project.returnBuses.first(where: { $0.id == ownerID }) else { return }
            bus.devices.insert(device, at: max(0, min(index, bus.devices.count)))
        default:
            break
        }
    }

    func importMIDIFileAsClip(_ url: URL, on targetTrack: Track? = nil, forceNewTrack: Bool = false) {
        let target: Track
        if !forceNewTrack, let existing = targetTrack ?? selectedTrack, existing.kind != .audio {
            target = existing
        } else {
            addTrack(kind: .analog)
            guard let created = selectedTrack else { return }
            created.name = url.deletingPathExtension().lastPathComponent
            target = created
        }
        let parsed = (try? StandardMIDIImporter.parse(url: url)) ?? StandardMIDIImporter.Parsed(notes: [], lengthBeats: Double(project.beatsPerBar * 4))
        let startBeat = max(0, snapArrangementBeat(engine.currentBeat))
        let lengthBeats = max(arrangementSnapUnit, snapArrangementBeat(max(Double(project.beatsPerBar), parsed.lengthBeats)))
        let clip = Clip(name: url.deletingPathExtension().lastPathComponent, startBeat: startBeat, lengthBeats: lengthBeats, color: target.color)
        clip.notes = parsed.notes.isEmpty ? [ClipNote(pitch: project.snap(60), start: 0, length: 1, velocity: 0.85)] : parsed.notes
        target.clips.append(clip)
        selectedTrackID = target.id
        selectedClipID = clip.id
        workspace = .arrangement
        detailDeck = .clip
        editStatus = "Imported MIDI clip ‘\(clip.name)’ — \(clip.notes.count) notes"
        engine.rebuild()
    }

    func addTrack(kind: InstrumentKind) {
        let colors: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .yellow]
        let t = Track(name: kind.rawValue, kind: kind, color: colors[project.tracks.count % colors.count])
        switch kind {
        case .oscillatron:
            t.devices.append(DeviceModel(kind: .oscillatron))
        case .lemmingBass:
            t.devices.append(DeviceModel(kind: .lemmingBass))
        default:
            break
        }
        project.tracks.append(t)
        engine.rebuild()
        selectedTrackID = t.id
    }

    func promptRenameTrack(_ track: Track) {
        let alert = NSAlert()
        alert.messageText = "Rename Track"
        alert.informativeText = "Enter a new name for this track."
        let field = NSTextField(string: track.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let next = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !next.isEmpty else { return }
            let oldName = track.name
            track.name = next
            editStatus = "Renamed ‘\(oldName)’ → ‘\(next)’"
            engine.rebuild()
        }
    }

    func duplicateTrack(_ track: Track) {
        guard let index = project.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let copy = Track(name: "\(track.name) Copy", kind: track.kind, color: track.color)
        copy.useStepSequencer = track.useStepSequencer
        copy.stepPattern = cloneStepPattern(track.stepPattern)
        copy.sequencerLayers = track.sequencerLayers.map { cloneSequencerLayer($0, stepCount: track.stepPattern.stepCount) }
        copy.drumGenre = track.drumGenre
        copy.volume = track.volume
        copy.pan = track.pan
        copy.mute = track.mute
        copy.solo = false
        copy.armed = false
        copy.inputMonitor = track.inputMonitor
        copy.audioInputMonitorMode = track.audioInputMonitorMode
        copy.audioInputDeviceUID = track.audioInputDeviceUID
        copy.audioInputDeviceName = track.audioInputDeviceName
        copy.audioInputChannelIndex = track.audioInputChannelIndex
        copy.loopDragEnabled = track.loopDragEnabled
        copy.pluginTargetID = track.pluginTargetID
        copy.externalPluginSlots = track.externalPluginSlots
        copy.devices = track.devices.map { cloneDevice($0) }
        copy.audioClips = track.audioClips.map { cloneAudioClip($0) }
        copy.clips = track.clips.map { cloneMidiClip($0) }
        project.tracks.insert(copy, at: min(project.tracks.count, index + 1))
        selectedTrackID = copy.id
        editStatus = "Duplicated track ‘\(track.name)’"
        engine.rebuild()
    }

    func bounceTrackInPlace(_ track: Track) {
        exportStatus = "Bouncing \(track.name) in place…"
        Task.detached { [weak self, weak track] in
            guard let self, let track else { return }
            do {
                try self.offline.bounce(track: track, project: self.project)
                guard let bounced = track.bounced else { throw SpliceError.badResponse("Bounce produced no audio clip.") }
                await MainActor.run {
                    let audioTrack = Track(name: "\(track.name) Bounce", kind: .audio, color: track.color)
                    audioTrack.audioClips = [self.cloneAudioClip(bounced)]
                    audioTrack.volume = track.volume
                    audioTrack.pan = track.pan
                    self.project.tracks.append(audioTrack)
                    self.selectedTrackID = audioTrack.id
                    self.exportStatus = "Bounced \(track.name) → new audio track"
                    self.engine.rebuild()
                }
            } catch {
                await MainActor.run { self.exportStatus = "⚠️ \(error.localizedDescription)" }
            }
        }
    }

    private func cloneStepPattern(_ pattern: StepPattern) -> StepPattern {
        let copy = StepPattern(stepCount: pattern.stepCount, stepsPerBeat: pattern.stepsPerBeat)
        copy.steps = pattern.steps
        return copy
    }


    private func cloneSequencerLayer(_ layer: SequencerLayer, stepCount: Int) -> SequencerLayer {
        var copy = SequencerLayer(name: layer.name,
                                  source: layer.source,
                                  note: layer.note,
                                  stepCount: stepCount,
                                  velocity: layer.velocity,
                                  samplePath: layer.samplePath,
                                  pluginTargetID: layer.pluginTargetID,
                                  octaveOffset: layer.octaveOffset,
                                  pan: layer.pan,
                                  volume: layer.volume)
        copy.steps = layer.steps
        return copy
    }

    private func cloneDevice(_ device: DeviceModel) -> DeviceModel {
        let copy = DeviceModel(kind: device.kind, params: device.params)
        copy.bypassed = device.bypassed
        copy.mono = device.mono
        copy.sidechainEnabled = device.sidechainEnabled
        copy.sidechainInputTrackID = device.sidechainInputTrackID
        return copy
    }

    private func cloneMidiClip(_ clip: Clip) -> Clip {
        let copy = Clip(name: clip.name, startBeat: clip.startBeat, lengthBeats: clip.lengthBeats, notes: clip.notes, color: clip.color)
        copy.isActive = clip.isActive
        copy.loopEnabled = clip.loopEnabled
        copy.loopLengthBeats = clip.loopLengthBeats
        copy.swingAmount = clip.swingAmount
        return copy
    }

    private func cloneAudioClip(_ clip: AudioClip) -> AudioClip {
        let copy = AudioClip(startBeat: clip.startBeat, samples: clip.samples, sampleRate: clip.sampleRate)
        copy.isActive = clip.isActive
        copy.displayName = clip.displayName
        copy.sourceURL = clip.sourceURL
        copy.detectedTempo = clip.detectedTempo
        copy.loopEnabled = clip.loopEnabled
        copy.loopLengthBeats = clip.loopLengthBeats
        copy.lengthBeatsOverride = clip.lengthBeatsOverride
        copy.trimStartBeats = clip.trimStartBeats
        copy.swingAmount = clip.swingAmount
        copy.gainDB = clip.gainDB
        copy.pitchSemitones = clip.pitchSemitones
        copy.pitchCents = clip.pitchCents
        copy.devices = clip.devices.map { cloneDevice($0) }
        copy.externalPluginSlots = clip.externalPluginSlots
        copy.warpEnabled = clip.warpEnabled
        copy.warpMode = clip.warpMode
        copy.originalTempo = clip.originalTempo
        copy.warpedSamples = clip.warpedSamples
        return copy
    }

    func deleteTrack(_ track: Track) {
        guard let index = project.tracks.firstIndex(where: { $0.id == track.id }) else { return }
        project.tracks.remove(at: index)
        if selectedTrackID == track.id { selectedTrackID = project.tracks[safe: min(index, project.tracks.count - 1)]?.id }
        editStatus = "Deleted track ‘\(track.name)’"
        registerUndo(UndoableEdit(name: "Delete Track", undo: { [weak self, weak track] in
            guard let self, let track else { return }
            self.project.tracks.insert(track, at: min(index, self.project.tracks.count))
            self.selectedTrackID = track.id
            self.engine.rebuild()
        }, redo: { [weak self, weak track] in
            guard let self, let track else { return }
            self.deleteTrack(track)
        }))
        engine.rebuild()
    }

    func deleteSelectedTrack() {
        guard let track = selectedTrack else { return }
        deleteTrack(track)
    }

    @discardableResult
    func deleteSelectedPianoRollNotes() -> Bool {
        guard workspace == .pianoRoll,
              !PianoRollState.shared.selectedNoteIDs.isEmpty,
              let clipID = PianoRollState.shared.clipID ?? selectedClipID,
              let clip = project.tracks.flatMap({ $0.clips }).first(where: { $0.id == clipID }) else { return false }
        let selected = PianoRollState.shared.selectedNoteIDs
        let after = clip.notes.filter { !selected.contains($0.id) }
        guard after.count != clip.notes.count else { return false }
        replaceMIDINotes(forClipID: clipID, with: after, undoName: selected.count == 1 ? "Delete Piano Roll Note" : "Delete Piano Roll Notes", context: .pianoRoll)
        PianoRollState.shared.selectedNoteIDs.removeAll()
        return true
    }

    func deleteSelectedItem() {
        if deleteSelectedPianoRollNotes() { return }
        if deleteSelectedClip() { return }
        if selectedTrackIDs.count > 1 { deleteSelectedTracks(); return }
        deleteSelectedTrack()
    }

    @discardableResult
    func deleteSelectedClip() -> Bool {
        if let audioID = selectedAudioClipID {
            for track in project.tracks {
                if let index = track.audioClips.firstIndex(where: { $0.id == audioID }) {
                    let removed = track.audioClips.remove(at: index)
                    let trackID = track.id
                    selectedAudioClipID = nil
                    selectedAudioClipTrackID = nil
                    editStatus = "Deleted audio clip ‘\(removed.displayName)’"
                    registerUndo(UndoableEdit(name: "Delete Audio Clip", undo: { [weak self, weak track] in
                        guard let self, let track else { return }
                        let insertIndex = min(index, track.audioClips.count)
                        if !track.audioClips.contains(where: { $0.id == removed.id }) { track.audioClips.insert(removed, at: insertIndex) }
                        self.selectedTrackID = trackID
                        self.selectedAudioClipID = removed.id
                        self.selectedAudioClipTrackID = trackID
                        self.engine.rebuild()
                    }, redo: { [weak self, weak track] in
                        guard let self, let track else { return }
                        track.audioClips.removeAll { $0.id == removed.id }
                        if self.selectedAudioClipID == removed.id { self.selectedAudioClipID = nil; self.selectedAudioClipTrackID = nil }
                        self.engine.rebuild()
                    }))
                    engine.rebuild()
                    return true
                }
            }
        }
        if let clipID = selectedClipID {
            for track in project.tracks {
                if let index = track.clips.firstIndex(where: { $0.id == clipID }) {
                    let removed = track.clips.remove(at: index)
                    let trackID = track.id
                    selectedClipID = nil
                    if PianoRollState.shared.clipID == clipID { PianoRollState.shared.clipID = nil }
                    editStatus = "Deleted MIDI clip ‘\(removed.name)’"
                    registerUndo(UndoableEdit(name: "Delete MIDI Clip", undo: { [weak self, weak track] in
                        guard let self, let track else { return }
                        let insertIndex = min(index, track.clips.count)
                        if !track.clips.contains(where: { $0.id == removed.id }) { track.clips.insert(removed, at: insertIndex) }
                        self.selectedTrackID = trackID
                        self.selectedClipID = removed.id
                        PianoRollState.shared.clipID = removed.id
                        self.engine.rebuild()
                    }, redo: { [weak self, weak track] in
                        guard let self, let track else { return }
                        track.clips.removeAll { $0.id == removed.id }
                        if self.selectedClipID == removed.id { self.selectedClipID = nil; PianoRollState.shared.clipID = nil }
                        self.engine.rebuild()
                    }))
                    engine.rebuild()
                    return true
                }
            }
        }
        return false
    }



    @discardableResult
    func duplicateMidiClip(_ clip: Clip, on track: Track) -> Clip {
        let copy = Clip(name: clip.name + " copy", startBeat: clip.startBeat + clip.lengthBeats, lengthBeats: clip.lengthBeats, notes: clip.notes, color: clip.color)
        track.clips.append(copy)
        selectedTrackID = track.id
        selectedClipID = copy.id
        selectedAudioClipID = nil
        selectedAudioClipTrackID = nil
        PianoRollState.shared.clipID = copy.id
        editStatus = "Duplicated MIDI clip ‘\(clip.name)’"
        registerUndo(UndoableEdit(name: "Duplicate MIDI Clip", undo: { [weak self, weak track, weak copy] in
            guard let self, let track, let copy else { return }
            track.clips.removeAll { $0.id == copy.id }
            if self.selectedClipID == copy.id { self.selectedClipID = nil; PianoRollState.shared.clipID = nil }
            self.engine.rebuild()
        }, redo: { [weak self, weak track, weak copy] in
            guard let self, let track, let copy else { return }
            if !track.clips.contains(where: { $0.id == copy.id }) { track.clips.append(copy) }
            self.selectedTrackID = track.id
            self.selectedClipID = copy.id
            PianoRollState.shared.clipID = copy.id
            self.engine.rebuild()
        }))
        engine.rebuild()
        return copy
    }

    @discardableResult
    func duplicateAudioClip(_ clip: AudioClip, on track: Track) -> AudioClip {
        let copy = cloneAudioClip(clip)
        copy.displayName = clip.displayName + " copy"
        copy.startBeat = clip.startBeat + clip.arrangementLengthBeats(projectTempo: project.tempo)
        track.audioClips.append(copy)
        selectedTrackID = track.id
        selectedClipID = nil
        selectedAudioClipID = copy.id
        selectedAudioClipTrackID = track.id
        detailDeck = .clip
        editStatus = "Duplicated audio clip ‘\(clip.displayName)’"
        registerAudioClipCreationUndo(copy, on: track, name: "Duplicate Audio Clip")
        engine.rebuild()
        return copy
    }

    var canPasteArrangementClip: Bool { arrangementClipboard != nil }

    func copySelectedClipToClipboard() {
        if let audioID = selectedAudioClipID {
            for track in project.tracks {
                if let clip = track.audioClips.first(where: { $0.id == audioID }) {
                    arrangementClipboard = .audio(clip: cloneAudioClip(clip), sourceTrackID: track.id)
                    editStatus = "Copied audio clip ‘\(clip.displayName)’"
                    return
                }
            }
        }
        if let midiID = selectedClipID {
            for track in project.tracks {
                if let clip = track.clips.first(where: { $0.id == midiID }) {
                    arrangementClipboard = .midi(clip: cloneMidiClip(clip), sourceTrackID: track.id)
                    editStatus = "Copied MIDI clip ‘\(clip.name)’"
                    return
                }
            }
        }
    }

    func pasteClipToSelectedTrack(at beat: Double? = nil) {
        guard let item = arrangementClipboard else { return }
        let target = selectedTrack ?? project.tracks.first(where: { $0.id == item.sourceTrackID }) ?? project.tracks.first
        guard let target else { return }
        let pasteBeat = max(0, beat ?? engine.currentBeat)
        switch item {
        case .midi(let source, _):
            if target.kind == .audio { target.kind = .analog }
            let clip = cloneMidiClip(source)
            clip.name = source.name.hasSuffix("copy") ? source.name : source.name + " copy"
            clip.startBeat = pasteBeat
            target.clips.append(clip)
            selectedTrackID = target.id
            selectedClipID = clip.id
            selectedAudioClipID = nil
            selectedAudioClipTrackID = nil
            PianoRollState.shared.clipID = clip.id
            registerUndo(UndoableEdit(name: "Paste MIDI Clip", undo: { [weak self, weak target, weak clip] in
                guard let self, let target, let clip else { return }
                target.clips.removeAll { $0.id == clip.id }
                if self.selectedClipID == clip.id { self.selectedClipID = nil; PianoRollState.shared.clipID = nil }
                self.engine.rebuild()
            }, redo: { [weak self, weak target, weak clip] in
                guard let self, let target, let clip else { return }
                if !target.clips.contains(where: { $0.id == clip.id }) { target.clips.append(clip) }
                target.kind = target.kind == .audio ? .analog : target.kind
                self.selectedTrackID = target.id
                self.selectedClipID = clip.id
                self.selectedAudioClipID = nil
                self.selectedAudioClipTrackID = nil
                PianoRollState.shared.clipID = clip.id
                self.engine.rebuild()
            }))
            editStatus = "Pasted MIDI clip on ‘\(target.name)’"
        case .audio(let source, _):
            if target.kind != .audio { target.kind = .audio }
            let clip = cloneAudioClip(source)
            clip.displayName = source.displayName.hasSuffix("copy") ? source.displayName : source.displayName + " copy"
            clip.startBeat = pasteBeat
            target.audioClips.append(clip)
            selectedTrackID = target.id
            selectedClipID = nil
            selectedAudioClipID = clip.id
            selectedAudioClipTrackID = target.id
            PianoRollState.shared.clipID = nil
            registerUndo(UndoableEdit(name: "Paste Audio Clip", undo: { [weak self, weak target, weak clip] in
                guard let self, let target, let clip else { return }
                target.audioClips.removeAll { $0.id == clip.id }
                if self.selectedAudioClipID == clip.id { self.selectedAudioClipID = nil; self.selectedAudioClipTrackID = nil }
                self.engine.rebuild()
            }, redo: { [weak self, weak target, weak clip] in
                guard let self, let target, let clip else { return }
                if !target.audioClips.contains(where: { $0.id == clip.id }) { target.audioClips.append(clip) }
                target.kind = .audio
                self.selectedTrackID = target.id
                self.selectedClipID = nil
                self.selectedAudioClipID = clip.id
                self.selectedAudioClipTrackID = target.id
                self.engine.rebuild()
            }))
            editStatus = "Pasted audio clip on ‘\(target.name)’"
        }
        ensureArrangementLength(coversBeat: pasteBeat + 4)
        engine.rebuild()
    }

    func moveSelectedClip(to target: Track) {
        if let audioID = selectedAudioClipID {
            moveAudioClip(audioID, to: target)
            return
        }
        if let midiID = selectedClipID {
            moveMidiClip(midiID, to: target)
        }
    }

    func moveMidiClip(_ clipID: UUID, to target: Track) {
        guard let source = project.tracks.first(where: { $0.clips.contains { $0.id == clipID } }),
              let index = source.clips.firstIndex(where: { $0.id == clipID }) else { return }
        let oldKind = target.kind
        let clip = source.clips.remove(at: index)
        clip.isActive = true
        if target.kind == .audio { target.kind = .analog }
        target.clips.append(clip)
        selectedTrackID = target.id
        selectedClipID = clip.id
        selectedAudioClipID = nil
        selectedAudioClipTrackID = nil
        PianoRollState.shared.clipID = clip.id
        registerUndo(UndoableEdit(name: "Move MIDI Clip", undo: { [weak self, weak source, weak target, weak clip] in
            guard let self, let source, let target, let clip else { return }
            target.clips.removeAll { $0.id == clip.id }
            target.kind = oldKind
            source.clips.insert(clip, at: min(index, source.clips.count))
            self.selectedTrackID = source.id
            self.selectedClipID = clip.id
            PianoRollState.shared.clipID = clip.id
            self.engine.rebuild()
        }, redo: { [weak self, weak target, weak clip] in
            guard let self, let target, let clip else { return }
            self.project.tracks.forEach { $0.clips.removeAll { $0.id == clip.id } }
            if target.kind == .audio { target.kind = .analog }
            target.clips.append(clip)
            self.selectedTrackID = target.id
            self.selectedClipID = clip.id
            PianoRollState.shared.clipID = clip.id
            self.engine.rebuild()
        }))
        editStatus = "Moved MIDI clip to ‘\(target.name)’"
        engine.rebuild()
    }

    func moveAudioClip(_ clipID: UUID, to target: Track) {
        guard let source = project.tracks.first(where: { $0.audioClips.contains { $0.id == clipID } }),
              let index = source.audioClips.firstIndex(where: { $0.id == clipID }) else { return }
        let oldKind = target.kind
        let clip = source.audioClips.remove(at: index)
        clip.isActive = true
        if target.kind != .audio { target.kind = .audio }
        target.audioClips.append(clip)
        selectedTrackID = target.id
        selectedClipID = nil
        selectedAudioClipID = clip.id
        selectedAudioClipTrackID = target.id
        PianoRollState.shared.clipID = nil
        registerUndo(UndoableEdit(name: "Move Audio Clip", undo: { [weak self, weak source, weak target, weak clip] in
            guard let self, let source, let target, let clip else { return }
            target.audioClips.removeAll { $0.id == clip.id }
            target.kind = oldKind
            source.audioClips.insert(clip, at: min(index, source.audioClips.count))
            self.selectedTrackID = source.id
            self.selectedAudioClipID = clip.id
            self.selectedAudioClipTrackID = source.id
            self.engine.rebuild()
        }, redo: { [weak self, weak target, weak clip] in
            guard let self, let target, let clip else { return }
            self.project.tracks.forEach { $0.audioClips.removeAll { $0.id == clip.id } }
            target.kind = .audio
            target.audioClips.append(clip)
            self.selectedTrackID = target.id
            self.selectedAudioClipID = clip.id
            self.selectedAudioClipTrackID = target.id
            self.engine.rebuild()
        }))
        editStatus = "Moved audio clip to ‘\(target.name)’"
        engine.rebuild()
    }

    func splitSelectedClipAtPlayhead() {
        if let audioID = selectedAudioClipID {
            splitAudioClipAtPlayhead(audioID)
            return
        }
        if let midiID = selectedClipID {
            splitMidiClipAtPlayhead(midiID)
        }
    }

    func splitMidiClipAtPlayhead(_ clipID: UUID) {
        guard let track = project.tracks.first(where: { $0.clips.contains { $0.id == clipID } }),
              let clip = track.clips.first(where: { $0.id == clipID }) else { return }
        let cut = engine.currentBeat - clip.startBeat
        guard cut > 0.05 && cut < clip.lengthBeats - 0.05 else { editStatus = "Playhead is outside selected MIDI clip"; return }
        let originalLength = clip.lengthBeats
        let originalNotes = clip.notes
        let right = Clip(name: clip.name + " B", startBeat: engine.currentBeat, lengthBeats: clip.lengthBeats - cut, notes: [], color: clip.color)
        var leftNotes: [ClipNote] = []
        for n in clip.notes {
            if n.start >= cut { right.notes.append(ClipNote(pitch: n.pitch, start: n.start - cut, length: n.length, velocity: n.velocity)) }
            else { leftNotes.append(n) }
        }
        clip.lengthBeats = cut
        clip.notes = leftNotes
        track.clips.append(right)
        selectedTrackID = track.id
        selectedClipID = right.id
        registerUndo(UndoableEdit(name: "Split MIDI Clip", undo: { [weak self, weak track, weak clip, weak right] in
            guard let self, let track, let clip, let right else { return }
            track.clips.removeAll { $0.id == right.id }
            clip.lengthBeats = originalLength
            clip.notes = originalNotes
            self.selectedClipID = clip.id
            self.engine.rebuild()
        }, redo: { [weak self, weak track, weak clip, weak right] in
            guard let self, let track, let clip, let right else { return }
            clip.lengthBeats = cut
            clip.notes = leftNotes
            if !track.clips.contains(where: { $0.id == right.id }) { track.clips.append(right) }
            self.selectedClipID = right.id
            self.engine.rebuild()
        }))
        editStatus = "Split MIDI clip at playhead"
        engine.rebuild()
    }

    func splitAudioClipAtPlayhead(_ clipID: UUID) {
        guard let track = project.tracks.first(where: { $0.audioClips.contains { $0.id == clipID } }),
              let clip = track.audioClips.first(where: { $0.id == clipID }) else { return }
        let totalBeats = clip.arrangementLengthBeats(projectTempo: project.tempo)
        let cutBeat = engine.currentBeat - clip.startBeat
        guard cutBeat > 0.05 && cutBeat < totalBeats - 0.05 else { editStatus = "Playhead is outside selected audio clip"; return }
        let cutSample = max(1, min(clip.samples.count - 1, Int((cutBeat / totalBeats) * Double(clip.samples.count))))
        let originalSamples = clip.samples
        let originalLength = clip.lengthBeatsOverride
        let rightSamples = Array(clip.samples[cutSample...])
        clip.samples = Array(clip.samples[..<cutSample])
        clip.lengthBeatsOverride = cutBeat
        let right = cloneAudioClip(clip)
        right.samples = rightSamples
        right.displayName = clip.displayName + " B"
        right.startBeat = engine.currentBeat
        right.lengthBeatsOverride = totalBeats - cutBeat
        if right.warpEnabled { WarpEngine.warp(right, projectTempo: project.tempo) }
        track.audioClips.append(right)
        selectedTrackID = track.id
        selectedAudioClipID = right.id
        selectedAudioClipTrackID = track.id
        registerUndo(UndoableEdit(name: "Split Audio Clip", undo: { [weak self, weak track, weak clip, weak right] in
            guard let self, let track, let clip, let right else { return }
            track.audioClips.removeAll { $0.id == right.id }
            clip.samples = originalSamples
            clip.lengthBeatsOverride = originalLength
            self.selectedAudioClipID = clip.id
            self.selectedAudioClipTrackID = track.id
            self.engine.rebuild()
        }, redo: { [weak self, weak track, weak clip, weak right] in
            guard let self, let track, let clip, let right else { return }
            clip.samples = Array(originalSamples[..<cutSample])
            clip.lengthBeatsOverride = cutBeat
            if !track.audioClips.contains(where: { $0.id == right.id }) { track.audioClips.append(right) }
            self.selectedAudioClipID = right.id
            self.selectedAudioClipTrackID = track.id
            self.engine.rebuild()
        }))
        editStatus = "Split audio clip at playhead"
        engine.rebuild()
    }

    func toggleTrackArm(_ track: Track, exclusive: Bool? = nil) {
        let exclusive = exclusive ?? !multiArmEnabled
        if exclusive {
            for t in project.tracks where t.id != track.id { t.armed = false }
        }
        track.armed.toggle()
        selectedTrackID = track.id
        editStatus = track.armed ? "Armed ‘\(track.name)’ for recording" : "Disarmed ‘\(track.name)’"
    }

    func armSelectedTrack() {
        guard let track = selectedTrack else { return }
        toggleTrackArm(track)
    }

    private func prepareStepSequencerRecordings(targets: [Track]) {
        let beat = transportBeat
        for track in targets where track.kind.isStepEditable && track.useStepSequencer {
            stepSequencerRecordStarts[track.id] = beat
        }
    }

    private func finalizeStepSequencerRecordings(at stopBeat: Double) {
        guard !stepSequencerRecordStarts.isEmpty else { return }
        for (trackID, startBeat) in stepSequencerRecordStarts {
            guard let track = project.tracks.first(where: { $0.id == trackID }),
                  track.kind.isStepEditable,
                  track.useStepSequencer else { continue }
            let endBeat = max(stopBeat, startBeat + 0.03125)
            let clip = createArrangementClipFromStepPattern(on: track,
                                                            name: "Recorded Step Sequence",
                                                            startBeat: startBeat,
                                                            endBeat: endBeat,
                                                            disableLiveSequencer: true,
                                                            openArrangement: false)
            selectedTrackID = track.id
            selectedClipID = clip.id
        }
        stepSequencerRecordStarts.removeAll()
    }

    private func prepareArmedClipsForOverdub(targets: [Track]) {
        let beat = transportBeat
        let bar = Double(project.beatsPerBar)
        for track in targets where track.kind != .audio {
            // A live step-sequencer track records itself by printing the played
            // pattern to MIDI at record stop. Do not create a blank overdub clip
            // on record start, because that looks like empty padding in Arrangement.
            if track.kind.isStepEditable && track.useStepSequencer { continue }
            if clipForOverdub(track: track, beat: beat) == nil {
                let start = (beat / bar).rounded(.down) * bar
                _ = createMidiClip(on: track, startBeat: start, lengthBeats: bar, openPianoRoll: false)
            }
        }
    }

    private func clipForOverdub(track: Track, beat: Double) -> Clip? {
        // For recording, the selected/armed clip should keep growing as the
        // transport passes its old right edge. Do not fall back to "nearest" in a
        // way that collapses the take or jumps to an unrelated clip.
        if let selected = selectedClipID,
           let clip = track.clips.first(where: { $0.id == selected && $0.isActive && beat >= $0.startBeat }) {
            return clip
        }
        if let containing = track.clips.first(where: { $0.isActive && beat >= $0.startBeat && beat < $0.startBeat + $0.lengthBeats }) {
            return containing
        }
        return track.clips
            .filter { $0.isActive && $0.startBeat <= beat }
            .max { $0.startBeat < $1.startBeat }
    }

    var arrangementSnapUnit: Double {
        snapToGridEnabled ? max(0.03125, gridSubdivisionBeats) : 0.03125
    }

    func snapArrangementBeat(_ beat: Double, rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Double {
        let snap = arrangementSnapUnit
        guard snap > 0 else { return beat }
        return (beat / snap).rounded(rule) * snap
    }

    func ensureArrangementLength(coversBeat beat: Double) {
        let bar = Double(max(1, project.beatsPerBar))
        if beat > project.lengthBeats - bar {
            project.lengthBars = max(project.lengthBars, Int(ceil((beat + bar) / bar)))
            rebuildTempoMap()
        }
    }

    private func growClip(_ clip: Clip, through absoluteBeat: Double) {
        let required = max(0.25, absoluteBeat - clip.startBeat)
        if required > clip.lengthBeats {
            let snap = snapToGridEnabled ? max(0.03125, gridSubdivisionBeats) : 0.03125
            clip.lengthBeats = max(clip.lengthBeats, (required / snap).rounded(.up) * snap)
        }
        ensureArrangementLength(coversBeat: clip.startBeat + clip.lengthBeats)
    }

    private func overdubNoteOn(track: Track, note: Int, velocity: Float, channel: Int) {
        guard midiOverdubRecording, track.kind != .audio else { return }
        let beat = transportBeat
        let bar = Double(project.beatsPerBar)
        let clip = clipForOverdub(track: track, beat: beat) ?? createMidiClip(on: track, startBeat: (beat / bar).rounded(.down) * bar, lengthBeats: bar, openPianoRoll: false)
        guard let clip else { return }
        growClip(clip, through: beat + 0.03125)
        let key = "\(track.id.uuidString)-\(channel)-\(note)"
        recordingMIDINotes[key] = (clip.id, beat, note, velocity)
        selectedClipID = clip.id
    }

    private func overdubNoteOff(track: Track, note: Int, channel: Int) {
        guard midiOverdubRecording, track.kind != .audio else { return }
        let key = "\(track.id.uuidString)-\(channel)-\(note)"
        guard let rec = recordingMIDINotes.removeValue(forKey: key),
              let clip = track.clips.first(where: { $0.id == rec.clipID }) else { return }
        let endBeat = max(transportBeat, rec.startBeat + 0.03125)
        let grid = recordQuantizationEnabled ? max(0.03125, recordQuantizationBeats) : 0
        var start = max(0, rec.startBeat - clip.startBeat)
        var length = max(0.03125, endBeat - rec.startBeat)
        if grid > 0 {
            start = (start / grid).rounded() * grid
            length = max(grid, (length / grid).rounded() * grid)
        }
        clip.notes.append(ClipNote(pitch: rec.note, start: start, length: length, velocity: rec.velocity))
        growClip(clip, through: clip.startBeat + start + length)
        editStatus = "Overdubbed note into ‘\(clip.name)’"
        // Do not rebuild the audio engine for every recorded note. Rebuilding
        // tears down source nodes/instruments while transport is running, which
        // caused live MIDI to lag after a few bars and could leave voices hanging.
        // The render thread already references the same Track/Clip objects, so
        // newly recorded notes are visible without a graph rebuild.
    }

    func togglePlay() {
        engine.start()
        engine.warmUpHostedAudioUnits()
        engine.transport.tempo = project.tempo
        if engine.transport.isPlaying {
            engine.transport.stop(at: transportBeat)
            engine.allNotesOff()
            recordStatus = midiOverdubRecording || recorder.isRecording ? "Recording paused" : "Playback stopped"
        } else {
            engine.transport.play()
            recordStatus = midiOverdubRecording || recorder.isRecording ? "Recording / overdubbing" : "Playback"
        }
        refreshDiscordPresence()
    }

    func stopTransport() {
        let beat = transportBeat
        countInWorkItem?.cancel()
        countInWorkItem = nil
        engine.stopCountInClick()
        engine.transport.stop(at: beat)
        finalizeStepSequencerRecordings(at: beat)
        midiOverdubRecording = false
        recordingMIDINotes.removeAll()
        liveMIDINoteCounts.removeAll()
        stepSequencerRecordStarts.removeAll()
        engine.allNotesOff()
        recordStatus = "Stopped at beat \(String(format: "%.2f", beat))"
        refreshDiscordPresence()
    }

    func returnToStart() {
        scrub(to: 0)
    }

    func scrub(to beat: Double) {
        engine.setCurrentBeat(min(max(0, beat), project.lengthBeats))
    }

    func launchClip(_ clip: Clip, on track: Track) {
        selectedTrackID = track.id
        scrub(to: clip.startBeat)
        engine.transport.tempo = project.tempo
        if !engine.transport.isPlaying { engine.transport.play() }
    }

    func launchAudioClip(_ clip: AudioClip, on track: Track) {
        selectedTrackID = track.id
        scrub(to: clip.startBeat)
        engine.transport.tempo = project.tempo
        if !engine.transport.isPlaying { engine.transport.play() }
    }

    func launchScene(_ sceneIndex: Int) {
        let beat = Double(sceneIndex * project.beatsPerBar * 4)
        scrub(to: beat)
        engine.transport.tempo = project.tempo
        if !engine.transport.isPlaying { engine.transport.play() }
    }

    func snappedBeat(_ beat: Double) -> Double {
        guard snapToGridEnabled, gridSubdivisionBeats > 0 else { return beat }
        return (beat / gridSubdivisionBeats).rounded() * gridSubdivisionBeats
    }

    func quantizeSelectedClip() {
        guard let clipID = selectedClipID,
              let clip = project.tracks.flatMap({ $0.clips }).first(where: { $0.id == clipID }) else {
            editStatus = "Select a MIDI clip to quantize."
            return
        }
        let grid = max(0.03125, recordQuantizationBeats)
        for i in clip.notes.indices {
            clip.notes[i].start = (clip.notes[i].start / grid).rounded() * grid
            clip.notes[i].length = max(grid, (clip.notes[i].length / grid).rounded() * grid)
        }
        editStatus = "Quantized ‘\(clip.name)’ to \(grid) beat grid"
        engine.rebuild()
    }


    func launchGeneratorDevice(_ kind: InstrumentKind, mode: GeneratorLaunchMode) {
        let target: Track
        switch kind {
        case .bhangraArchitect: createBhangraArchitectTrack(); target = selectedTrack!
        case .guaracha2C: create2CTrack(); target = selectedTrack!
        case .bailaton: createBailatonTrack(); target = selectedTrack!
        case .dubstepWrangler: createDubstepWranglerTrack(); target = selectedTrack!
        case .lemmingBass: createLemmingBassTrack(); target = selectedTrack!
        case .oscillatron: createOscillatronTrack(); target = selectedTrack!
        case .drums, .sequencer: createSequencerTrack(named: kind == .sequencer ? "Sequencer" : "Drum Machine"); target = selectedTrack!
        default: addTrack(kind: kind); target = selectedTrack!
        }
        switch mode {
        case .midiClip:
            if target.kind == .bhangraArchitect || target.kind == .bhangraDhol || target.kind == .indianPercussion {
                target.stepPattern.loadGroove(BhangraToolkit.chaal); addBhangraMelodicHooks(on: target); syncSequencerLayerCells(from: target.stepPattern, on: target); _ = createArrangementClipFromStepPattern(on: target, name: "Bhangra Architect Clip")
            } else if target.kind == .guaracha2C {
                target.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: .guaracha)); syncSequencerLayerCells(from: target.stepPattern, on: target); _ = createArrangementClipFromStepPattern(on: target, name: "2C Guaracha Clip")
            } else if target.kind == .dubstepWrangler {
                target.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: .dubstep)); syncSequencerLayerCells(from: target.stepPattern, on: target); _ = createArrangementClipFromStepPattern(on: target, name: "Dubstep Wrangler Clip")
            } else if target.kind == .bailaton {
                target.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: target.drumGenre)); syncSequencerLayerCells(from: target.stepPattern, on: target); _ = createArrangementClipFromStepPattern(on: target, name: "Bailaton Groove Clip")
            } else if target.kind.isStepEditable {
                target.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: target.drumGenre)); syncSequencerLayerCells(from: target.stepPattern, on: target); _ = createArrangementClipFromStepPattern(on: target, name: "Generated Groove")
            } else {
                _ = createMidiClip(on: target, startBeat: engine.currentBeat, lengthBeats: Double(project.beatsPerBar * 4), openPianoRoll: true)
            }
        case .stepSequence:
            target.useStepSequencer = true
            if target.kind == .bhangraArchitect || target.kind == .bhangraDhol || target.kind == .indianPercussion { target.sequencerLayers = BhangraToolkit.layers; target.stepPattern.loadGroove(BhangraToolkit.chaal); addBhangraMelodicHooks(on: target) }
            else if target.kind == .guaracha2C { target.sequencerLayers = DrumKitLibrary.kitLayers(for: .guaracha); target.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: .guaracha)) }
            else if target.kind == .dubstepWrangler { target.sequencerLayers = DrumKitLibrary.kitLayers(for: .dubstep); target.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: .dubstep)) }
            else if target.kind == .bailaton { target.sequencerLayers = DrumKitLibrary.kitLayers(for: target.drumGenre); target.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: target.drumGenre)) }
            syncSequencerLayerCells(from: target.stepPattern, on: target); workspace = .step; detailDeck = .clip
        case .deviceOnly:
            target.useStepSequencer = target.kind.isStepEditable; detailDeck = .devices
        }
        selectedTrackID = target.id; editStatus = "Loaded \(target.name) as \(mode.rawValue)"; refreshDiscordPresence(); engine.rebuild()
    }

    func currentTrackForPresence() -> Track? { selectedTrack ?? project.tracks.first(where: { $0.armed }) ?? project.tracks.first }

    func discordPresencePayload() -> DiscordRichPresencePayload {
        let track = currentTrackForPresence()
        let pluginSummary: String = {
            guard let track else { return "No track" }
            let all = track.devices.prefix(2).map { $0.kind.rawValue } + track.externalPluginSlots.prefix(2).map { $0.name }
            return all.isEmpty ? "No inserts" : all.joined(separator: ", ")
        }()
        return DiscordRichPresenceGuide.payload(projectName: project.name, tempo: project.tempo, key: project.key.displayName, workspace: workspace.rawValue, playing: engine.transport.isPlaying, recording: recorder.isRecording, trackName: track?.name ?? "No track", trackKind: track?.kind.rawValue ?? "None", pluginSummary: pluginSummary)
    }

    func fitSelectedClipToScale() {
        guard let clipID = selectedClipID,
              let clip = project.tracks.flatMap({ $0.clips }).first(where: { $0.id == clipID }) else {
            editStatus = "Select a MIDI clip to fit to scale."
            return
        }
        let after = clip.notes.map { note -> ClipNote in
            var copy = note
            copy.pitch = project.snap(note.pitch)
            return copy
        }
        replaceMIDINotes(forClipID: clipID, with: after, undoName: "Fit ‘\(clip.name)’ to \(project.key.displayName)", context: .pianoRoll)
    }

    func generativeDisco(on clip: Clip? = nil) {
        guard let target = clip ?? (selectedClipID.flatMap { id in project.tracks.flatMap({ $0.clips }).first { $0.id == id } }) else {
            editStatus = "Select a MIDI clip for Generative Disco."
            return
        }
        let root = project.key.root
        let scale = project.key.scale.notes(root: root, from: 48, to: 84).map(\.number)
        let bass = scale.first(where: { $0 >= 48 }) ?? 48
        let chord = [0, 2, 4].compactMap { idx in scale.dropFirst(idx).first }.prefix(3)
        var notes: [ClipNote] = []
        let len = max(4, target.lengthBeats)
        var beat = 0.0
        while beat < len {
            notes.append(ClipNote(pitch: bass, start: beat, length: 0.45, velocity: 0.9))
            notes.append(ClipNote(pitch: bass + 12, start: beat + 0.75, length: 0.18, velocity: 0.55))
            if Int(beat) % 2 == 1 {
                for p in chord { notes.append(ClipNote(pitch: p + 12, start: beat, length: 0.25, velocity: 0.72)) }
            }
            beat += 1.0
        }
        target.notes = notes
        editStatus = "Generated disco riff in ‘\(target.name)’"
        engine.rebuild()
    }


    private func performStepSequencerMutation(_ body: () -> Void) {
        // Step Sequencer kit/groove changes replace lane arrays, track kinds,
        // plug-in targets, and clips. Those same objects are read by the
        // AVAudioSourceNode render callback, so mutating them while CoreAudio is
        // pulling audio can crash the app. Pause the audio engine for the tiny
        // mutation window, then rebuild/restart at the call site. The transport
        // state is left alone so playback can continue after the engine restart.
        let restartAudio = engine.isRunning
        if restartAudio { engine.stop() }
        body()
        engine.rebuild()
        if restartAudio { engine.start() }
    }

    private func prepareStepTrackForBuiltInKit(_ track: Track) {
        // Switching from a plug-in lane/generator back to a built-in drum kit
        // must fully detach the AU/instrument target. Otherwise the next kit's
        // Kick/Snare/Hat MIDI routing goes into the old synth plug-in, which is
        // why Tech House/EDM could turn into bass notes on every lane and even
        // crash when the stale AU was rebuilt while the step engine was playing.
        engine.allNotesOff()
        engine.resetStepSequencerState(for: track)
        track.pluginTargetID = nil
        track.externalPluginSlots.removeAll { $0.role == .instrument }
        track.stepPattern.clearAll()
        clearStepSequencerClips(on: track)
        if let selectedClipID, !track.clips.contains(where: { $0.id == selectedClipID }) {
            self.selectedClipID = nil
        }
    }

    private func normalizeStepTrackKind(_ track: Track, for genre: DrumGenre) {
        // A previous generator kind must not survive kit switching. Leaving a
        // Tech House/EDM kit on .dubstepWrangler makes the engine pick the
        // Dubstep instrument path and every drum lane becomes bass.
        if genre == .guaracha {
            track.kind = .guaracha2C
        } else if [.reggaeton332, .moombah, .moombahton, .dembow].contains(genre) {
            track.kind = .bailaton
        } else if genre == .dubstep {
            track.kind = .dubstepWrangler
        } else {
            track.kind = .drums
        }
    }

    func applyDrumKit(_ genre: DrumGenre, to track: Track? = nil, loadGroove: Bool = true) {
        let target: Track
        if let track {
            target = track
        } else {
            addTrack(kind: genre == .guaracha ? .guaracha2C : ([.reggaeton332, .moombah, .moombahton, .dembow].contains(genre) ? .bailaton : (genre == .dubstep ? .dubstepWrangler : .drums)))
            guard let created = selectedTrack else { return }
            target = created
        }
        performStepSequencerMutation {
            prepareStepTrackForBuiltInKit(target)
            normalizeStepTrackKind(target, for: genre)
            target.drumGenre = genre
            target.useStepSequencer = true
            target.pluginTargetID = nil
            target.externalPluginSlots.removeAll { $0.role == .instrument }
            target.devices.removeAll { $0.kind == .arpeggiator && genre != .dubstep }
            target.sequencerLayers = DrumKitLibrary.kitLayers(for: genre)
            muteStepSequencerPreviewClips(on: target)
            if loadGroove {
                target.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: genre))
                syncSequencerLayerCells(from: target.stepPattern, on: target)
                refreshSelectedGeneratedClipIfNeeded(on: target, fallbackName: "\(genre.rawValue) Groove")
            }
            selectedTrackID = target.id
            workspace = .step
            detailDeck = .clip
            editStatus = "Loaded real \(genre.rawValue) drum kit on ‘\(target.name)’"
        }
    }

    func applyDrumGroove(_ genre: DrumGenre, to track: Track) {
        performStepSequencerMutation {
            prepareStepTrackForBuiltInKit(track)
            normalizeStepTrackKind(track, for: genre)
            track.drumGenre = genre
            track.useStepSequencer = true
            track.pluginTargetID = nil
            track.externalPluginSlots.removeAll { $0.role == .instrument }
            track.devices.removeAll { $0.kind == .arpeggiator && genre != .dubstep }
            muteStepSequencerPreviewClips(on: track)
            track.sequencerLayers = DrumKitLibrary.kitLayers(for: genre)
            track.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: genre))
            syncSequencerLayerCells(from: track.stepPattern, on: track)
            refreshSelectedGeneratedClipIfNeeded(on: track, fallbackName: "\(genre.rawValue) Groove")
            selectedTrackID = track.id
            editStatus = "Step sequencer groove → \(genre.rawValue)"
            engine.allNotesOff()
        }
    }

    func applyBhangraGroove(_ groove: BhangraToolkit.Groove, to track: Track) {
        performStepSequencerMutation {
            prepareStepTrackForBuiltInKit(track)
            if track.kind == .audio { track.kind = .bhangraArchitect }
            track.kind = track.kind == .bhangraDhol ? .bhangraDhol : .bhangraArchitect
            track.useStepSequencer = true
            track.pluginTargetID = nil
            track.externalPluginSlots.removeAll { $0.role == .instrument }
            muteStepSequencerPreviewClips(on: track)
            track.sequencerLayers = BhangraToolkit.layers
            track.stepPattern.loadGroove(groove)
            addBhangraMelodicHooks(on: track)
            syncSequencerLayerCells(from: track.stepPattern, on: track)
            // Loading a groove should change the rhythm, not hijack the user's session tempo.
            // Earlier builds forced Chaal/Dhamaal/Kaharva BPM here, which made the
            // sequencer feel like it was ignoring the transport tempo. Keep the current
            // project tempo and only expose the groove BPM as a suggestion in the status.
            engine.transport.tempo = project.tempo
            refreshStepSequencerClips(on: track, fallbackName: groove.name)
            selectedTrackID = track.id
            editStatus = "Bhangra Architect groove → \(groove.name) · suggested \(groove.bpm) BPM · playing at \(Int(project.tempo)) BPM"
            engine.resetStepSequencerState(for: track)
        }
    }

    func setStepHit(on track: Track, step: Int, note: Int, enabled: Bool) {
        guard track.stepPattern.steps.indices.contains(step) else { return }
        // FL-style cell editing: mutate exactly one lane/cell intersection.
        // Do not toggle the whole lane, do not drop other hits that share this
        // step, and immediately invalidate the render-side step cursor so a
        // removed hit cannot keep playing as a stale kit voice.
        track.stepPattern.setHit(step: step, note: note, enabled: enabled)
        if let index = track.sequencerLayers.firstIndex(where: { $0.note == note }) {
            if track.sequencerLayers[index].steps.count != track.stepPattern.stepCount {
                track.sequencerLayers[index].steps = Array(repeating: false, count: track.stepPattern.stepCount)
            }
            track.sequencerLayers[index].steps[step] = enabled
        } else if enabled {
            let friendly = SequencerLayer.friendlyName(for: note, source: .builtIn, project: project)
            var layer = SequencerLayer(name: friendly, source: .builtIn, note: note, stepCount: track.stepPattern.stepCount, velocity: 0.9)
            layer.steps[step] = true
            track.sequencerLayers.append(layer)
        }
        // Editing a cell is a live Step Sequencer action. Keep the generated
        // Arrangement preview from doubling the live sequencer, but do not touch
        // explicitly printed tracks because those live on their own track.
        track.useStepSequencer = true
        muteStepSequencerPreviewClips(on: track)
        refreshStepSequencerClips(on: track, fallbackName: "Generated Groove")
        engine.resetStepSequencerState(for: track)
        engine.rebuild()
    }

    func clearStepHit(on track: Track, step: Int, note: Int) {
        setStepHit(on: track, step: step, note: note, enabled: false)
        editStatus = "Cleared step \(step + 1) on ‘\(track.name)’"
    }

    func addStepHit(on track: Track, step: Int, note: Int) {
        setStepHit(on: track, step: step, note: note, enabled: true)
        editStatus = "Added step \(step + 1) on ‘\(track.name)’"
    }

    func clearStepPattern(on track: Track) {
        track.stepPattern.clearAll()
        // FL-style clear means every cell in every lane becomes empty. Keep the
        // loaded kit/sample assignment intact, but zero the per-lane step flags too.
        for index in track.sequencerLayers.indices {
            track.sequencerLayers[index].steps = Array(repeating: false, count: track.stepPattern.stepCount)
        }
        clearStepSequencerClips(on: track)
        track.useStepSequencer = true
        editStatus = "Cleared all step hits on ‘\(track.name)’"
        engine.resetStepSequencerState(for: track)
        engine.allNotesOff()
        engine.rebuild()
    }

    private func addBhangraMelodicHooks(on track: Track) {
        for step in [3, 7, 11, 15] where step < track.stepPattern.stepCount { track.stepPattern.setHit(step: step, note: 84, enabled: true, velocity: 0.72) }
        for step in [6, 14] where step < track.stepPattern.stepCount { track.stepPattern.setHit(step: step, note: 86, enabled: true, velocity: 0.50) }
    }

    private func syncSequencerLayerCells(from pattern: StepPattern, on track: Track) {
        guard !track.sequencerLayers.isEmpty else { return }
        for index in track.sequencerLayers.indices {
            let note = track.sequencerLayers[index].note
            if track.sequencerLayers[index].steps.count != pattern.stepCount {
                track.sequencerLayers[index].steps = Array(repeating: false, count: pattern.stepCount)
            }
            for step in 0..<pattern.stepCount {
                track.sequencerLayers[index].steps[step] = pattern.isOn(step: step, note: note)
            }
        }
    }

    private func refreshSelectedGeneratedClipIfNeeded(on track: Track, fallbackName: String, keepSelectionOnly: Bool = false) {
        guard let clipID = selectedClipID, let clip = track.clips.first(where: { $0.id == clipID }) else { return }
        guard isStepSequencerGeneratedClip(clip, on: track) else { return }
        rewriteClip(clip, from: track.stepPattern, fallbackName: keepSelectionOnly ? clip.name : fallbackName)
    }

    private func isStepSequencerGeneratedClip(_ clip: Clip, on track: Track) -> Bool {
        let lower = clip.name.lowercased()
        if lower.contains("generated") || lower.contains("groove") || lower.contains("step") || lower.contains("printed") { return true }
        if lower.contains("bhangra") || lower.contains("chaal") || lower.contains("dhamaal") || lower.contains("kaharva") { return true }
        if lower.contains("guaracha") || lower.contains("2c") || lower.contains("bailaton") || lower.contains("dembow") { return true }
        // Buildfix183: selection is not identity. A user-selected Arrangement clip
        // on a step-editable track is still Arrangement material, not sequencer
        // source state. Treating selected clips as generated let delete/cleanup
        // paths erase the only audible representation and made the Step Sequencer
        // appear to go silent after deleting an Arrangement clip.
        return false
    }

    private func refreshStepSequencerClips(on track: Track, fallbackName: String) {
        var refreshedAny = false
        for clip in track.clips where isStepSequencerGeneratedClip(clip, on: track) {
            rewriteClip(clip, from: track.stepPattern, fallbackName: fallbackName)
            refreshedAny = true
        }
        if !refreshedAny { refreshSelectedGeneratedClipIfNeeded(on: track, fallbackName: fallbackName) }
    }

    private func clearStepSequencerClips(on track: Track) {
        // Arrangement clips and live Step Sequencer state are separate domains.
        // Clearing or refreshing the live grid may remove auto-generated preview
        // clips, but it must never deactivate/empty user Arrangement clips. The
        // Step Sequencer sound comes from track.stepPattern + useStepSequencer,
        // not from clips in Arrangement view.
        track.clips.removeAll { isStepSequencerGeneratedClip($0, on: track) }
    }

    /// When the Step Sequencer is being used live, old generated/preview clips on
    /// the same track must not keep playing underneath the new kit or groove.
    /// This was the source of the ugly overlap after Clear → load another kit:
    /// the live pattern had changed, but the old Arrangement preview clip was
    /// still active and continued to trigger the previous kit notes.
    private func muteStepSequencerPreviewClips(on track: Track) {
        guard track.kind.isStepEditable else { return }
        // Loading a new kit/groove should never stack with the last generated
        // preview from the same live sequencer track. Delete only recognized
        // preview clips. Do not touch user clips, and do not change the live
        // sequencer flag; deleting Arrangement material must not silence the grid.
        track.clips.removeAll { isStepSequencerGeneratedClip($0, on: track) }
    }

    private func rewriteClip(_ clip: Clip, from pattern: StepPattern, fallbackName: String) {
        let stepLen = 1.0 / Double(pattern.stepsPerBeat)
        let length = Double(pattern.stepCount) * stepLen
        clip.lengthBeats = max(length, stepLen)
        clip.name = fallbackName
        clip.notes = pattern.steps.enumerated().flatMap { i, step -> [ClipNote] in
            let beat = Double(i) * stepLen
            return step.activeNotes.map { ClipNote(pitch: $0, start: beat, length: max(0.08, stepLen * 0.92), velocity: step.velocity) }
        }
        project.lengthBars = max(project.lengthBars, Int(ceil((clip.startBeat + clip.lengthBeats) / Double(project.beatsPerBar))))
    }

    private func sequencerClipNotes(from pattern: StepPattern, startBeat: Double, endBeat: Double) -> (notes: [ClipNote], length: Double) {
        let stepLen = 1.0 / Double(max(1, pattern.stepsPerBeat))
        let length = max(stepLen, endBeat - startBeat)
        let epsilon = 0.000_001
        // Step-pattern prints are a half-open musical range: [startBeat, endBeat).
        // Buildfix183 accidentally used `endBeat + epsilon`, which rendered the
        // downbeat at exactly the clip end as if it belonged to the previous bar.
        // In a 16-step EDM pattern that meant step 0/kick appeared again at beat 4
        // when printing/extending a one-bar loop, creating a stray tail kick.
        // Quantize the first rendered boundary up to the first step at/after the
        // clip start, then strictly exclude the end boundary.
        let firstBoundary = max(startBeat, (startBeat / stepLen).rounded(.up) * stepLen)
        var beat = firstBoundary
        var notes: [ClipNote] = []
        while beat < endBeat - epsilon {
            let rel = max(0, beat - startBeat)
            // Use the clip-relative step index, never the absolute project beat.
            // Using rounded absolute beats can turn a floating-point value such
            // as 3.999999999 into step 16, which wraps to pattern step 0 and
            // recreates the stray kick/hat at the right edge. A print/loop clip
            // must restart its pattern at the clip start and remain half-open.
            let relativeStep = Int(floor((rel + epsilon) / stepLen))
            guard relativeStep >= 0 else { beat += stepLen; continue }
            let index = ((relativeStep % max(1, pattern.stepCount)) + max(1, pattern.stepCount)) % max(1, pattern.stepCount)
            guard pattern.steps.indices.contains(index) else { break }
            let step = pattern.steps[index]
            for pitch in step.activeNotes {
                let remaining = max(0.0, length - rel)
                // Never let a printed step note cross the clip's right edge. A
                // forced minimum length here could bleed a hat/kick from the
                // previous print into the next adjacent print.
                let noteLength = min(max(0.001, stepLen * 0.92), remaining)
                guard noteLength > epsilon else { continue }
                notes.append(ClipNote(pitch: pitch,
                                      start: rel,
                                      length: noteLength,
                                      velocity: step.velocity))
            }
            beat += stepLen
        }
        return (notes, length)
    }

    @discardableResult
    func createArrangementClipFromStepPattern(on track: Track,
                                              name: String? = nil,
                                              startBeat: Double? = nil,
                                              endBeat: Double? = nil,
                                              disableLiveSequencer: Bool = true,
                                              openArrangement: Bool = true) -> Clip {
        let pattern = track.stepPattern
        let stepLen = 1.0 / Double(max(1, pattern.stepsPerBeat))
        let patternLength = Double(pattern.stepCount) * stepLen
        let start = snappedBeat(startBeat ?? engine.currentBeat)
        let end = endBeat.map { max(start + stepLen, $0) } ?? (start + patternLength)
        let rendered = sequencerClipNotes(from: pattern, startBeat: start, endBeat: end)
        let clip = Clip(name: name ?? "Printed Step Pattern", startBeat: start, lengthBeats: rendered.length, notes: rendered.notes, color: track.color)
        clip.loopEnabled = true
        clip.loopLengthBeats = max(stepLen, patternLength)
        track.clips.append(clip)
        if disableLiveSequencer { track.useStepSequencer = false }
        selectedTrackID = track.id
        selectedClipID = clip.id
        selectedAudioClipID = nil
        if openArrangement { workspace = .arrangement }
        detailDeck = .clip
        project.lengthBars = max(project.lengthBars, Int(ceil((clip.startBeat + clip.lengthBeats) / Double(project.beatsPerBar))))
        engine.rebuild()
        return clip
    }

    private func sequencerPrintOriginID(for source: Track) -> UUID {
        source.sequencerPrintSourceTrackID ?? source.id
    }

    private func removeLiveSequencerPreviewClipsBeforePrinting(on source: Track) {
        // Printing should only silence the live/preview source that would otherwise
        // double the newly printed clip. It must never mute, deactivate, or rewrite
        // older Arrangement prints: those are user arrangement material once created.
        guard source.kind.isStepEditable else { return }
        source.clips.removeAll { isStepSequencerGeneratedClip($0, on: source) }
    }

    private func reactivateLegacySequencerPrints(from source: Track) {
        // Buildfix181 muted old prints to prevent doubling, but that made printed
        // Arrangement material feel corrupted even after users hit Unmute or moved
        // clips to another lane. Repair that state non-destructively on the next
        // print; the only source we silence now is the live sequencer preview.
        let originID = sequencerPrintOriginID(for: source)
        for track in project.tracks {
            let isKnownPriorPrint = track.sequencerPrintSourceTrackID == originID
            let isLegacyPriorPrint = source.sequencerPrintTargetTrackID == track.id
            guard isKnownPriorPrint || isLegacyPriorPrint else { continue }
            track.useStepSequencer = false
            let hadBuildfix181Poison = track.clips.contains { !$0.isActive } || track.audioClips.contains { !$0.isActive }
            if hadBuildfix181Poison { track.mute = false }
            for clip in track.clips { clip.isActive = true }
            for clip in track.audioClips { clip.isActive = true }
        }
    }

    private func compatibleStepPrintDestination(for source: Track) -> Track? {
        // If the user explicitly selected an Arrangement track, print into that
        // lane. Otherwise append to the last print lane made from this sequencer.
        // Never print back onto the live Step Sequencer source: that reintroduces
        // live-grid/Arrangement coupling and makes deletes feel destructive.
        if let selected = selectedTrack,
           selected.id != source.id,
           selected.kind == source.kind {
            return selected
        }
        if let targetID = source.sequencerPrintTargetTrackID,
           let remembered = project.tracks.first(where: { $0.id == targetID }),
           remembered.id != source.id,
           remembered.kind == source.kind {
            return remembered
        }
        return nil
    }

    private func endBeatOfArrangementMaterial(on track: Track) -> Double {
        let midiEnd = track.clips.filter(\.isActive).map { $0.startBeat + $0.lengthBeats }.max() ?? 0
        let audioEnd = track.audioClips.filter(\.isActive).map { $0.startBeat + $0.arrangementLengthBeats(projectTempo: project.tempo) }.max() ?? 0
        return max(midiEnd, audioEnd)
    }

    @discardableResult
    func printStepPatternToNewArrangementTrack(from source: Track) -> Track {
        reactivateLegacySequencerPrints(from: source)
        removeLiveSequencerPreviewClipsBeforePrinting(on: source)
        let originID = sequencerPrintOriginID(for: source)
        let printed: Track
        if let destination = compatibleStepPrintDestination(for: source) {
            printed = destination
            printed.sequencerPrintSourceTrackID = originID
            if printed.devices.isEmpty { printed.devices = source.devices }
            if printed.externalPluginSlots.isEmpty { printed.externalPluginSlots = source.externalPluginSlots }
            printed.stepPattern = source.stepPattern
            printed.sequencerLayers = source.sequencerLayers
            printed.drumGenre = source.drumGenre
            printed.useStepSequencer = false
        } else {
            let fresh = Track(name: "\(source.name) Print", kind: source.kind, color: source.color)
            fresh.sequencerPrintSourceTrackID = originID
            fresh.devices = source.devices
            fresh.externalPluginSlots = source.externalPluginSlots
            fresh.stepPattern = source.stepPattern
            fresh.sequencerLayers = source.sequencerLayers
            fresh.drumGenre = source.drumGenre
            fresh.useStepSequencer = false
            project.tracks.append(fresh)
            printed = fresh
        }
        // Keep the source Step Sequencer live. Printing is a non-destructive copy
        // operation; switching to Arrangement playback prevents doubling there,
        // while returning to the Step Sequencer should still play the grid.
        source.useStepSequencer = true
        source.sequencerPrintTargetTrackID = printed.id
        selectedTrackID = printed.id
        let patternBeats = Double(source.stepPattern.stepCount) / Double(max(1, source.stepPattern.stepsPerBeat))
        let existingEnd = endBeatOfArrangementMaterial(on: printed)
        let requestedStart = max(0, snapArrangementBeat(engine.currentBeat))
        let printStart = max(requestedStart, snapArrangementBeat(existingEnd, rule: .up))
        let printLength = max(arrangementSnapUnit, snapArrangementBeat(patternBeats, rule: .up))
        _ = createArrangementClipFromStepPattern(on: printed,
                                                 name: "Printed \(source.name)",
                                                 startBeat: printStart,
                                                 endBeat: printStart + printLength,
                                                 disableLiveSequencer: true,
                                                 openArrangement: true)
        engine.resetStepSequencerState(for: source)
        engine.allNotesOff()
        editStatus = "Printed ‘\(source.name)’ to Arrangement · appended to ‘\(printed.name)’ without touching prior clips"
        return printed
    }


    func quickBhangraArchitectInArrangement() {
        createBhangraArchitectTrack()
        guard let track = selectedTrack else { return }
        track.stepPattern.loadGroove(BhangraToolkit.chaal)
        addBhangraMelodicHooks(on: track)
        syncSequencerLayerCells(from: track.stepPattern, on: track)
        project.tempo = Double(BhangraToolkit.chaal.bpm)
        engine.transport.tempo = project.tempo
        _ = createArrangementClipFromStepPattern(on: track, name: "Bhangra Chaal")
        assistantLog.append("agent: Bhangra Architect generated an editable arrangement chaal clip")
    }

    func quick2CInArrangement() {
        create2CTrack()
        guard let track = selectedTrack else { return }
        track.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: .guaracha))
        project.tempo = 128
        engine.transport.tempo = project.tempo
        _ = createArrangementClipFromStepPattern(on: track, name: "2C Guaracha Groove")
        assistantLog.append("agent: 2C generated an editable guaracha arrangement clip")
    }


    func quickBailatonInArrangement(_ genre: DrumGenre = .dembow) {
        createBailatonTrack(genre: genre)
        guard let track = selectedTrack else { return }
        project.tempo = genre == .moombah || genre == .moombahton ? 108 : 96
        engine.transport.tempo = project.tempo
        _ = createArrangementClipFromStepPattern(on: track, name: "Bailaton \(genre.rawValue) Groove")
        assistantLog.append("agent: Bailaton generated an editable \(genre.rawValue) arrangement clip")
    }

    func quickDrumKitInArrangement(_ genre: DrumGenre = .techHouse) {
        addTrack(kind: genre == .guaracha ? .guaracha2C : ([.reggaeton332, .moombah, .moombahton, .dembow].contains(genre) ? .bailaton : (genre == .dubstep ? .dubstepWrangler : .drums)))
        guard let track = selectedTrack else { return }
        track.name = "\(genre.rawValue) Kit"
        applyDrumKit(genre, to: track, loadGroove: true)
        _ = createArrangementClipFromStepPattern(on: track, name: "\(genre.rawValue) Groove")
    }

    func createSequencerTrack(named name: String = "Sequencer") {
        let restartAudio = engine.isRunning
        if restartAudio { engine.stop() }
        addTrack(kind: .sequencer)
        guard let track = selectedTrack else {
            if restartAudio { engine.start() }
            return
        }
        track.name = name
        track.kind = .sequencer
        track.drumGenre = .techHouse
        track.pluginTargetID = nil
        track.externalPluginSlots.removeAll { $0.role == .instrument }
        track.devices.removeAll { $0.kind == .arpeggiator }
        track.useStepSequencer = true
        track.stepPattern.clearAll()
        clearStepSequencerClips(on: track)
        track.sequencerLayers = DrumKitLibrary.kitLayers(for: .techHouse)
        track.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: .techHouse))
        syncSequencerLayerCells(from: track.stepPattern, on: track)
        engine.resetStepSequencerState(for: track)
        workspace = .step
        detailDeck = .clip
        editStatus = "Created multi-layer Sequencer track"
        engine.rebuild()
        if restartAudio { engine.start() }
    }

    func createBhangraArchitectTrack() {
        addTrack(kind: .bhangraArchitect)
        selectedTrack?.name = "Bhangra Architect"
        selectedTrack?.useStepSequencer = true
        selectedTrack?.sequencerLayers = BhangraToolkit.layers
        selectedTrack?.stepPattern.loadGroove(BhangraToolkit.chaal)
        if let t = selectedTrack { addBhangraMelodicHooks(on: t); syncSequencerLayerCells(from: t.stepPattern, on: t) }
        assistantLog.append("agent: Bhangra Architect ready — ask for chaal, dholki, tumbi, or modern Punjabi grooves")
    }

    func create2CTrack() {
        addTrack(kind: .guaracha2C)
        selectedTrack?.name = "2C"
        selectedTrack?.useStepSequencer = true
        selectedTrack?.drumGenre = .guaracha
        selectedTrack?.sequencerLayers = DrumKitLibrary.kitLayers(for: .guaracha)
        selectedTrack?.stepPattern.loadDrumGroove(DrumKitLibrary.groove(for: .guaracha))
        if let t = selectedTrack { syncSequencerLayerCells(from: t.stepPattern, on: t) }
        assistantLog.append("agent: 2C ready — ask for guaracha bounce, offbeat bass, zap fills, or club edits")
    }

    func printSequencerToAudio(_ track: Track) {
        // The offline renderer is the right long-term path. For now this creates a target
        // audio track and records the routing intent without destructively flattening the sequencer.
        let audio = Track(name: "Printed - \(track.name)", kind: .audio, color: track.color)
        project.tracks.append(audio)
        track.sequencerPrintTargetTrackID = audio.id
        selectedTrackID = audio.id
        editStatus = "Prepared audio print target for ‘\(track.name)’"
    }

    @MainActor
    func replicateSonicSignature(from clip: AudioClip, targetPluginName: String?) async {
        let requestedTarget = targetPluginName ?? "Built-in Analog"
        guard let track = selectedTrack else {
            audioSignatureStatus = "Select an instrument track before replicating a sonic signature."
            return
        }
        track.pluginTargetID = requestedTarget
        audioSignatureStatus = "Analysing ‘\(clip.displayName)’ for \(requestedTarget)…"

        guard let target = prepareSoundAgentTarget(resetForNewPatch: true) else {
            audioSignatureStatus = "Could not prepare \(requestedTarget) as a writable target."
            assistantLog.append("⚠️ audio-signature: target unavailable — \(requestedTarget)")
            return
        }

        let tempoHint = clip.detectedTempo.map { "Detected tempo: \(Int($0)) BPM." } ?? "Tempo unknown."
        let prompt = """
        Replicate the sonic signature of the reference audio clip “\(clip.displayName)” on \(target.displayName).
        \(tempoHint) Clip length: \(String(format: "%.2f", clip.arrangementLengthBeats(projectTempo: project.tempo))) beats.

        Recreate the perceived timbre, envelope, brightness, harmonic density, stereo character, transient shape,
        movement, and FX character as closely as the available target allows. Set every parameter you can actually
        access through the host. For any important knob, mode, wavetable, routing switch, matrix assignment, FX
        setting, or modulation connection that the host cannot access or map reliably, DO NOT pretend it was changed.
        Put explicit manual instructions in the notes: exact control name/path, direction or approximate value/range,
        and the listening goal. Keep those instructions concise and ordered so the user can finish the patch by hand.
        """

        let design = await SoundAgent(backend: currentBackend()).design(description: prompt, for: target)
        do {
            let summary = try target.apply(design)
            audioSignatureStatus = "Replicated ‘\(clip.displayName)’ on \(target.displayName)."
            assistantLog.append("audio-signature: \(summary)")
            if !design.notes.isEmpty {
                assistantLog.append("audio-signature manual/agent notes: \(design.notes)")
            }
        } catch {
            audioSignatureStatus = "Sonic-signature replication failed: \(error.localizedDescription)"
            assistantLog.append("⚠️ audio-signature: \(error.localizedDescription)")
        }
    }

    func bootstrapHomebrewAndOllama() {
        bootstrapStatus = "Checking Homebrew and Ollama…"
        Task.detached { [weak self] in
            let result = BootstrapInstaller.ensureHomebrewAndOllama()
            await MainActor.run { self?.bootstrapStatus = result }
        }
    }

    func setWarp(_ clip: AudioClip, enabled: Bool, mode: WarpMode? = nil, originalTempo: Double? = nil) {
        clip.warpEnabled = enabled
        if let mode { clip.warpMode = mode }
        if let originalTempo, originalTempo > 0 {
            clip.originalTempo = originalTempo
            clip.manualTempoOverride = true
        }
        if enabled { WarpEngine.warp(clip, projectTempo: project.tempo) } else { clip.warpedSamples = nil }
        let modeText = enabled ? " · \(clip.warpMode.rawValue) · \(Int(clip.originalTempo)) BPM" : ""
        editStatus = enabled ? "Warp enabled for ‘\(clip.displayName)’\(modeText)" : "Warp disabled for ‘\(clip.displayName)’"
        engine.rebuild()
    }

    func setClipTempo(_ clip: AudioClip, bpm: Double, enableWarp: Bool? = nil) {
        let safe = min(300, max(40, bpm))
        clip.originalTempo = safe
        clip.manualTempoOverride = true
        if let enableWarp { clip.warpEnabled = enableWarp }
        if clip.warpEnabled { WarpEngine.warp(clip, projectTempo: project.tempo) } else { clip.warpedSamples = nil }
        editStatus = "Clip tempo for ‘\(clip.displayName)’ set to \(Int(safe)) BPM"
        engine.rebuild()
    }

    func resetClipTempoToDetected(_ clip: AudioClip) {
        guard let detected = clip.detectedTempo, detected > 0 else {
            editStatus = "No detected tempo stored for ‘\(clip.displayName)’"
            return
        }
        clip.originalTempo = detected
        clip.manualTempoOverride = false
        if clip.warpEnabled { WarpEngine.warp(clip, projectTempo: project.tempo) } else { clip.warpedSamples = nil }
        editStatus = "Clip tempo reset to detected \(Int(detected)) BPM"
        engine.rebuild()
    }

    func persistSettings() {
        UserDefaults.standard.set(visualTheme.rawValue, forKey: "visualTheme")
        UserDefaults.standard.set(audioDriverName, forKey: "audioDriverName")
        UserDefaults.standard.set(audioInputDevice, forKey: "audioInputDevice")
        UserDefaults.standard.set(audioInputDeviceUID, forKey: "audioInputDeviceUID")
        UserDefaults.standard.set(audioOutputDevice, forKey: "audioOutputDevice")
        UserDefaults.standard.set(preferredSampleRate, forKey: "preferredSampleRate")
        UserDefaults.standard.set(preferredBufferSize, forKey: "preferredBufferSize")
        UserDefaults.standard.set(midiInputEnabled, forKey: "midiInputEnabled")
        UserDefaults.standard.set(midiMonitorEnabled, forKey: "midiMonitorEnabled")
        UserDefaults.standard.set(mpeMode.rawValue, forKey: "mpeMode")
        UserDefaults.standard.set(mpePitchBendRange, forKey: "mpePitchBendRange")
        UserDefaults.standard.set(mpeMasterChannel, forKey: "mpeMasterChannel")
        UserDefaults.standard.set(mpeMemberChannelStart, forKey: "mpeMemberChannelStart")
        UserDefaults.standard.set(mpeMemberChannelEnd, forKey: "mpeMemberChannelEnd")
        UserDefaults.standard.set(mpeMapCC74ToTimbre, forKey: "mpeMapCC74ToTimbre")
        UserDefaults.standard.set(mpePressureEnabled, forKey: "mpePressureEnabled")
        UserDefaults.standard.set(pluginScanFoldersText, forKey: "pluginScanFoldersText")
        UserDefaults.standard.set(userLibraryFolder, forKey: "userLibraryFolder")
        UserDefaults.standard.set(drumPadPreset.rawValue, forKey: "drumPadPreset")
        UserDefaults.standard.set(drumPadTranspose, forKey: "drumPadTranspose")
        UserDefaults.standard.set(drumPadCustomMapText, forKey: "drumPadCustomMapText")
        UserDefaults.standard.set(metronomeEnabled, forKey: "metronomeEnabled")
        UserDefaults.standard.set(countInEnabled, forKey: "countInEnabled")
        UserDefaults.standard.set(countInBeats, forKey: "countInBeats")
        UserDefaults.standard.set(snapToGridEnabled, forKey: "snapToGridEnabled")
        UserDefaults.standard.set(gridSubdivisionBeats, forKey: "gridSubdivisionBeats")
        UserDefaults.standard.set(recordQuantizationEnabled, forKey: "recordQuantizationEnabled")
        UserDefaults.standard.set(multiArmEnabled, forKey: "multiArmEnabled")
        UserDefaults.standard.set(multiSoloEnabled, forKey: "multiSoloEnabled")
        UserDefaults.standard.set(multiMuteEnabled, forKey: "multiMuteEnabled")
        UserDefaults.standard.set(launchFullscreenEnabled, forKey: "launchFullscreenEnabled")
        UserDefaults.standard.set(recordQuantizationBeats, forKey: "recordQuantizationBeats")
        UserDefaults.standard.set(autoWarpImportedAudio, forKey: "autoWarpImportedAudio")
        UserDefaults.standard.set(defaultWarpMode.rawValue, forKey: "defaultWarpMode")
        editStatus = "Settings saved"
    }


    private func registerAudioClipCreationUndo(_ clip: AudioClip, on track: Track, name: String) {
        let trackID = track.id
        registerUndo(UndoableEdit(name: name, undo: { [weak self, weak track, weak clip] in
            guard let self, let track, let clip else { return }
            track.audioClips.removeAll { $0.id == clip.id }
            if self.selectedAudioClipID == clip.id { self.selectedAudioClipID = nil; self.selectedAudioClipTrackID = nil }
            self.engine.rebuild()
        }, redo: { [weak self, weak track, weak clip] in
            guard let self, let track, let clip else { return }
            if !track.audioClips.contains(where: { $0.id == clip.id }) { track.audioClips.append(clip) }
            self.selectedTrackID = trackID
            self.selectedClipID = nil
            self.selectedAudioClipID = clip.id
            self.selectedAudioClipTrackID = trackID
            self.engine.rebuild()
        }))
    }

    private func trackContainingAudioClip(id clipID: UUID) -> Track? {
        project.tracks.first { track in track.audioClips.contains(where: { $0.id == clipID }) }
    }

    private func registerUndo(_ edit: UndoableEdit) {
        undoStack.append(edit)
        redoStack.removeAll()
        canUndo = !undoStack.isEmpty
        canRedo = false
    }

    func focusPianoRollUndoContext() {
        focusedUndoContext = .pianoRoll
    }

    func focusGeneralUndoContext() {
        focusedUndoContext = .general
    }

    /// Replaces the notes in a MIDI clip as one contextual undoable edit.
    /// Piano Roll uses this instead of mutating `clip.notes` directly, so Cmd+Z
    /// stays local to note edits and cannot accidentally jump to an older plug-in
    /// operation such as recreating Serum from Init.
    func replaceMIDINotes(forClipID clipID: UUID, with newNotes: [ClipNote], undoName: String, context: UndoContext = .pianoRoll) {
        guard let clip = project.tracks.flatMap({ $0.clips }).first(where: { $0.id == clipID }) else { return }
        let before = clip.notes
        let after = newNotes
        guard before != after else { return }
        clip.notes = after
        selectedClipID = clipID
        selectedAudioClipID = nil
        PianoRollState.shared.clipID = clipID
        focusedUndoContext = context
        registerUndo(UndoableEdit(name: undoName, context: context, undo: { [weak self, weak clip] in
            clip?.notes = before
            self?.selectedClipID = clipID
            PianoRollState.shared.clipID = clipID
            PianoRollState.shared.selectedNoteIDs = Set(before.map(\.id))
            self?.engine.rebuild()
        }, redo: { [weak self, weak clip] in
            clip?.notes = after
            self?.selectedClipID = clipID
            PianoRollState.shared.clipID = clipID
            PianoRollState.shared.selectedNoteIDs = Set(after.map(\.id))
            self?.engine.rebuild()
        }))
        editStatus = undoName
        engine.rebuild()
    }

    private func preferredUndoIndex(in stack: [UndoableEdit]) -> Int? {
        if focusedUndoContext != .general, let contextual = stack.lastIndex(where: { $0.context == focusedUndoContext }) {
            return contextual
        }
        return stack.indices.last
    }

    func undoLastAction() {
        guard let index = preferredUndoIndex(in: undoStack) else { return }
        let edit = undoStack.remove(at: index)
        edit.undo()
        redoStack.append(edit)
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        editStatus = "Undid: \(edit.name)"
    }

    func redoLastAction() {
        guard let index = preferredUndoIndex(in: redoStack) else { return }
        let edit = redoStack.remove(at: index)
        edit.redo()
        undoStack.append(edit)
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        editStatus = "Redid: \(edit.name)"
    }

    func moveTrack(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = project.tracks.firstIndex(where: { $0.id == id }),
              let to = project.tracks.firstIndex(where: { $0.id == targetID }) else { return }
        let beforeOrder = project.tracks.map(\.id)
        let moving = project.tracks.remove(at: from)
        let insertIndex = from < to ? max(0, to - 1) : to
        project.tracks.insert(moving, at: insertIndex)
        selectedTrackID = moving.id
        engine.rebuild()
        let afterOrder = project.tracks.map(\.id)
        guard beforeOrder != afterOrder else { return }
        registerUndo(UndoableEdit(name: "Move Track", undo: { [weak self] in
            self?.reorderTracks(to: beforeOrder)
        }, redo: { [weak self] in
            self?.reorderTracks(to: afterOrder)
        }))
    }

    /// Reorders `project.tracks` to match a saved ID order (used by undo/redo).
    private func reorderTracks(to order: [UUID]) {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        project.tracks.sort { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
        engine.rebuild()
    }

    func setProjectTempo(_ tempo: Double) {
        let oldBeat = transportBeat
        project.tempo = max(20, min(300, tempo))
        engine.transport.tempo = project.tempo
        if engine.transport.isPlaying { engine.transport.setBeat(oldBeat) }
        rebuildTempoMap()
        editStatus = "Tempo set to \(Int(project.tempo)) BPM — warped audio/MIDI follows project time"
        refreshDiscordPresence()
    }

    func toggleRecordQuantization() {
        recordQuantizationEnabled.toggle()
        persistSettings()
        editStatus = recordQuantizationEnabled ? "Record quantization on" : "Record quantization off"
    }

    func confirmProjectSetup() {
        engine.setSampleRate(project.sampleRate)
        preferredSampleRate = project.sampleRate
        UserDefaults.standard.set(true, forKey: "hasSeenProjectSetup")
        showProjectSetupSheet = false
        persistSettings()
        projectSetupStatus = "Project format: \(Int(project.sampleRate)) Hz · \(project.bitDepth.rawValue) · \(project.channelFormat.rawValue)"
        engine.rebuild()
    }

    func toggleSolo(_ track: Track) {
        let before = soloSnapshot()
        if !multiSoloEnabled { for t in project.tracks where t.id != track.id { t.solo = false } }
        track.solo.toggle()
        let after = soloSnapshot()
        guard before != after else { return }
        registerUndo(UndoableEdit(name: track.solo ? "Solo Track" : "Unsolo Track", undo: { [weak self] in
            self?.applySoloSnapshot(before)
        }, redo: { [weak self] in
            self?.applySoloSnapshot(after)
        }))
    }

    func toggleMute(_ track: Track) {
        let before = muteSnapshot()
        if !multiMuteEnabled { for t in project.tracks where t.id != track.id { t.mute = false } }
        track.mute.toggle()
        let after = muteSnapshot()
        guard before != after else { return }
        registerUndo(UndoableEdit(name: track.mute ? "Mute Track" : "Unmute Track", undo: { [weak self] in
            self?.applyMuteSnapshot(before)
        }, redo: { [weak self] in
            self?.applyMuteSnapshot(after)
        }))
    }

    private func soloSnapshot() -> [UUID: Bool] {
        Dictionary(project.tracks.map { ($0.id, $0.solo) }, uniquingKeysWith: { a, _ in a })
    }
    private func muteSnapshot() -> [UUID: Bool] {
        Dictionary(project.tracks.map { ($0.id, $0.mute) }, uniquingKeysWith: { a, _ in a })
    }
    private func applySoloSnapshot(_ snap: [UUID: Bool]) {
        for t in project.tracks { if let v = snap[t.id] { t.solo = v } }
        engine.rebuild()
    }
    private func applyMuteSnapshot(_ snap: [UUID: Bool]) {
        for t in project.tracks { if let v = snap[t.id] { t.mute = v } }
        engine.rebuild()
    }


    func tapTempo() {
        let now = Date()
        tapTempoTimes.append(now)
        tapTempoTimes = tapTempoTimes.filter { now.timeIntervalSince($0) < 3.0 }
        guard tapTempoTimes.count >= 2 else { tapTempoStatus = "Tap again"; return }
        let intervals = zip(tapTempoTimes.dropFirst(), tapTempoTimes).map { $0.timeIntervalSince($1) }.filter { $0 > 0.12 && $0 < 2.0 }
        guard !intervals.isEmpty else { return }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        setProjectTempo(60.0 / avg)
        tapTempoStatus = "Tap: \(Int(project.tempo)) BPM"
    }

    func sliceAudioClipToMIDI(_ clip: AudioClip, targetTrack: Track? = nil) {
        let samples = clip.activeSamples
        guard !samples.isEmpty else { editStatus = "No audio to slice."; return }
        let sr = clip.activeSampleRate
        let hop = max(1, Int(sr * 0.035))
        let minGapBeats = 0.25
        let threshold: Float = 0.18
        var notes: [ClipNote] = []
        var lastBeat = -999.0
        var i = 0
        while i < samples.count {
            let end = min(samples.count, i + hop)
            var peak: Float = 0
            var j = i
            while j < end { peak = max(peak, abs(samples[j])); j += 1 }
            let beat = (Double(i) / sr) * project.tempo / 60.0
            if peak > threshold && beat - lastBeat >= minGapBeats {
                notes.append(ClipNote(pitch: 60 + min(24, Int(peak * 24)), start: beat, length: 0.22, velocity: min(1, max(0.25, peak))))
                lastBeat = beat
            }
            i += hop
        }
        guard !notes.isEmpty else { editStatus = "Slice to MIDI found no clear transients."; return }
        let t = targetTrack ?? Track(name: "Slices · \(clip.displayName)", kind: .sequencer, color: .purple)
        if targetTrack == nil { project.tracks.append(t) }
        let midi = Clip(name: "Slice MIDI · \(clip.displayName)", startBeat: clip.startBeat, lengthBeats: max(1, clip.arrangementLengthBeats(projectTempo: project.tempo)), notes: notes, color: t.color)
        t.clips.append(midi)
        selectedTrackID = t.id
        selectedClipID = midi.id
        selectedAudioClipID = nil
        workspace = .pianoRoll
        detailDeck = .clip
        editStatus = "Sliced \(clip.displayName) to \(notes.count) MIDI note(s)."
        engine.rebuild()
    }

    func supportedMediaKind(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if ["wav", "wave", "aif", "aiff", "mp3", "m4a", "caf", "ogg", "flac", "ape"].contains(ext) { return "audio" }
        if ["mid", "midi"].contains(ext) { return "midi" }
        if ["mov", "mp4", "m4v", "avi", "mkv"].contains(ext) { return "video" }
        return nil
    }

    func importMediaFile(_ url: URL, targetTrack: Track? = nil, forceNewTrack: Bool = false) {
        switch supportedMediaKind(for: url) {
        case "audio":
            do { try importAudioFile(url, targetTrack: targetTrack, forceNewTrack: forceNewTrack) }
            catch { editStatus = "⚠️ Audio import failed: \(error.localizedDescription)" }
        case "video":
            importVideoFile(url)
        case "midi":
            importMIDIFileAsClip(url, on: targetTrack, forceNewTrack: forceNewTrack)
        default:
            editStatus = "Unsupported media: \(url.lastPathComponent)"
        }
    }

    func importVideoFile(_ url: URL) {
        let asset = AVURLAsset(url: url)
        guard !asset.tracks(withMediaType: .audio).isEmpty else { editStatus = "⚠️ Video has no audio track"; return }
        do { try importAudioFile(url, name: url.deletingPathExtension().lastPathComponent) }
        catch { editStatus = "Video linked; audio extraction needs AVAssetReader decode for \(url.lastPathComponent)" }
        videoPreviewURL = url.path
        workspace = .arrangement
    }


    func clearArrangementClipSelection() {
        selectedArrangementClipKeys.removeAll()
    }

    func selectArrangementClip(kind: String, id: UUID, trackID: UUID, additive: Bool = false) {
        if !additive { selectedArrangementClipKeys.removeAll() }
        let key = "\(kind):\(id.uuidString)"
        if additive, selectedArrangementClipKeys.contains(key) {
            selectedArrangementClipKeys.remove(key)
        } else {
            selectedArrangementClipKeys.insert(key)
        }
        selectedTrackID = trackID
        if kind == "midi" {
            selectedClipID = id
            selectedAudioClipID = nil
            selectedAudioClipTrackID = nil
        } else {
            selectedClipID = nil
            selectedAudioClipID = id
            selectedAudioClipTrackID = trackID
            detailDeck = .clip
        }
    }

    func isArrangementClipSelected(kind: String, id: UUID) -> Bool {
        selectedArrangementClipKeys.contains("\(kind):\(id.uuidString)") || (kind == "midi" && selectedClipID == id) || (kind == "audio" && selectedAudioClipID == id)
    }

    func replaceArrangementClipSelection(keys: Set<String>) {
        selectedArrangementClipKeys = keys
        guard let first = keys.sorted().first else {
            selectedClipID = nil
            selectedAudioClipID = nil
            selectedAudioClipTrackID = nil
            return
        }
        let parts = first.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return }
        if parts[0] == "midi" {
            selectedClipID = id
            selectedAudioClipID = nil
            selectedAudioClipTrackID = nil
            selectedTrackID = project.tracks.first { $0.clips.contains { $0.id == id } }?.id
        } else {
            selectedClipID = nil
            selectedAudioClipID = id
            if let track = project.tracks.first(where: { $0.audioClips.contains { $0.id == id } }) {
                selectedAudioClipTrackID = track.id
                selectedTrackID = track.id
            }
        }
    }
    var videoPreviewURL: String {
        get { UserDefaults.standard.string(forKey: "videoPreviewURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "videoPreviewURL") }
    }

}

private enum ArrangementClipboard {
    case midi(clip: Clip, sourceTrackID: UUID)
    case audio(clip: AudioClip, sourceTrackID: UUID)

    var sourceTrackID: UUID {
        switch self {
        case .midi(_, let id), .audio(_, let id): return id
        }
    }
}

enum UndoContext: Equatable {
    case general
    case pianoRoll
}

private struct UndoableEdit {
    let name: String
    let context: UndoContext
    let undo: () -> Void
    let redo: () -> Void

    init(name: String, context: UndoContext = .general, undo: @escaping () -> Void, redo: @escaping () -> Void) {
        self.name = name
        self.context = context
        self.undo = undo
        self.redo = redo
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

enum WorkspaceTab: String, CaseIterable, Identifiable {
    case session = "Session", arrangement = "Arrangement", pianoRoll = "Piano Roll", step = "Step Sequencer"
    case devices = "Devices", automation = "Automation", mixer = "Mixer"
    var id: String { rawValue }
}
enum InspectorTab: String, CaseIterable, Identifiable {
    case circle = "Circle of 5ths", chords = "Chords", describe = "Sound Agent"
    case ai = "AI Producer", plugins = "Instruments", midi = "MIDI"
    case studio = "Studio", splice = "Splice"
    var id: String { rawValue }
}

// MARK: - Root layout


struct ProjectSetupSheet: View {
    @Environment(AppState.self) private var app
    var body: some View {
        @Bindable var project = app.project
        VStack(alignment: .leading, spacing: 16) {
            Text("🐾 New LemmingsStudio Project").font(.title2.bold())
            Text("Set sample rate, bit depth, channel format, and default swing before you record or import media.")
                .foregroundStyle(.secondary)
            Form {
                Picker("Sample Rate", selection: $project.sampleRate) {
                    Text("44.1 kHz").tag(44100.0); Text("48 kHz").tag(48000.0); Text("88.2 kHz").tag(88200.0); Text("96 kHz").tag(96000.0)
                }
                Picker("Bit Depth", selection: $project.bitDepth) { ForEach(ProjectBitDepth.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Channel Format", selection: $project.channelFormat) { ForEach(ProjectChannelFormat.allCases) { Text($0.rawValue).tag($0) } }
                if project.channelFormat == .custom { Stepper("Custom channels: \(project.customChannelCount)", value: $project.customChannelCount, in: 1...32) }
                Slider(value: $project.swingAmount, in: 0...0.75) { Text("Project Swing") }
                Text("Project swing: \(Int(project.swingAmount * 100))%").font(.caption).foregroundStyle(.secondary)
            }
            Text(app.projectSetupStatus).font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Use Defaults") { project.sampleRate = 48000; project.bitDepth = .float32; project.channelFormat = .stereo; app.confirmProjectSetup() }; Button("Create Project") { app.confirmProjectSetup() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 540)
    }
}


private enum MagmaVancePreSplashAsset {
    private static let supportedRefreshRates = [60, 75, 90, 120, 144, 165, 240]

    private static var detectedRefreshRate: Int {
        guard let screen = NSScreen.main else { return 60 }
        if #available(macOS 14.0, *) {
            let fps = screen.maximumFramesPerSecond
            if fps > 0 { return fps }
        }
        return 60
    }

    private static var selectedRefreshRate: Int {
        let detected = detectedRefreshRate
        return supportedRefreshRates.min { lhs, rhs in
            abs(lhs - detected) == abs(rhs - detected) ? lhs < rhs : abs(lhs - detected) < abs(rhs - detected)
        } ?? 60
    }

    static var url: URL? {
        let fps = selectedRefreshRate
        let candidates = [
            "MagmaVancePreSplash_\(fps)",
            "MagmaVancePreSplash_60",
            "MagmaVancePreSplash"
        ]
        for name in candidates {
            if let url = Bundle.module.url(forResource: name, withExtension: "mp4", subdirectory: "Resources") { return url }
            if let url = Bundle.module.url(forResource: name, withExtension: "mp4") { return url }
        }
        return nil
    }

    static var displayDuration: TimeInterval {
        guard let url else { return 3.8 }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return 3.8 }
        return min(max(seconds, 1.2), 5.0)
    }
}

private struct MagmaVancePreSplashPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(frame: .zero)
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

private struct MagmaVancePreSplashView: View {
    private let player: AVPlayer

    init(videoURL: URL) {
        let player = AVPlayer(url: videoURL)
        player.isMuted = true
        self.player = player
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.black.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.46), radius: 46, y: 18)
            MagmaVancePreSplashPlayerView(player: player)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(10)
                .onAppear {
                    player.seek(to: .zero)
                    player.play()
                }
                .onDisappear { player.pause() }
        }
        .frame(width: 360, height: 640)
        .accessibilityLabel("MagmaVance startup splash video")
    }
}

final class MagmaVancePreSplashWindowController: NSObject {
    private var window: NSWindow?
    private let videoURL: URL

    init(videoURL: URL) {
        self.videoURL = videoURL
        super.init()
    }

    func show(relativeTo parent: NSWindow?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.show(relativeTo: parent) }
            return
        }
        guard window == nil else { return }
        let hosting = NSHostingController(rootView: MagmaVancePreSplashView(videoURL: videoURL))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 640), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        if let parent {
            let frame = parent.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 180, y: frame.midY - 320))
            parent.addChildWindow(panel, ordered: .above)
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 180, y: frame.midY - 320))
        }
        window = panel
        panel.orderFrontRegardless()
    }

    func dismiss() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.dismiss() }
            return
        }
        guard let panel = window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.parent?.removeChildWindow(panel)
            panel.close()
        }
        window = nil
    }
}

private enum LemmingsSplashAsset {
    static var image: NSImage? {
        if let url = Bundle.module.url(forResource: "LemmingsSplash", withExtension: "png", subdirectory: "Resources") { return NSImage(contentsOf: url) }
        if let url = Bundle.module.url(forResource: "LemmingsSplash", withExtension: "png") { return NSImage(contentsOf: url) }
        return nil
    }
}

struct LemmingsSplashView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.black.opacity(0.78))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.42), radius: 42, y: 18)
            VStack(spacing: 14) {
                if let nsImage = LemmingsSplashAsset.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 320, height: 320)
                        .shadow(color: .cyan.opacity(0.24), radius: 28, y: 10)
                } else {
                    Image(systemName: "pawprint.circle.fill")
                        .font(.system(size: 150))
                        .foregroundStyle(.cyan, .purple)
                }
                Text("LemmingsStudio")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                Text("loading the chaos engine…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
                Text("© MagmaVance LLC. All rights reserved.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.top, 6)
            }
            .padding(28)
        }
        .frame(width: 460, height: 548)
        .accessibilityLabel("LemmingsStudio splash screen")
    }
}

final class LemmingsSplashWindowController: NSObject {
    private var window: NSWindow?

    func show(relativeTo parent: NSWindow?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.show(relativeTo: parent) }
            return
        }
        guard window == nil else { return }
        let hosting = NSHostingController(rootView: LemmingsSplashView())
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 548), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        if let parent {
            let frame = parent.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 230, y: frame.midY - 274))
            parent.addChildWindow(panel, ordered: .above)
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 230, y: frame.midY - 274))
        }
        window = panel
        panel.orderFrontRegardless()
    }

    func dismiss() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.dismiss() }
            return
        }
        guard let panel = window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.parent?.removeChildWindow(panel)
            panel.close()
        }
        window = nil
    }
}



struct LemmingsGenericAUEditorView: View {
    let title: String
    let parameters: [AUParameter]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title3.bold())
                    Text("Generic Audio Unit control surface")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("The plug-in did not return a vendor editor to the host, so Lemmings is showing a safe generic AU parameter panel instead. Use/target still loads the plug-in on the selected track.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            if parameters.isEmpty {
                ContentUnavailableView("No AU Parameters", systemImage: "dial.low", description: Text("This plug-in did not expose automatable AU parameters to the host. It may still run internally, or require its own standalone/desktop companion UI."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(parameters, id: \.address) { param in
                            LemmingsAUParameterRow(parameter: param)
                        }
                    }
                    .padding(.trailing, 8)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 640, minHeight: 440)
    }
}

struct LemmingsAUParameterRow: View {
    let parameter: AUParameter

    private var lower: Double { Double(parameter.minValue) }
    private var upper: Double { max(Double(parameter.maxValue), Double(parameter.minValue) + 0.0001) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(parameter.displayName.isEmpty ? parameter.identifier : parameter.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.3f", Double(parameter.value)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { Double(parameter.value) },
                set: { parameter.value = AUValue(min(max($0, lower), upper)) }
            ), in: lower...upper)
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}


final class LemmingsSpliceWebPreviewWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate {
    private weak var app: AppState?
    private let url: URL
    private let previewTitle: String
    private var window: NSWindow?
    private var webView: WKWebView?

    init(app: AppState, url: URL, title: String) {
        self.app = app
        self.url = url
        self.previewTitle = title
    }

    func show() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 980, height: 660), configuration: configuration)
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = true
        webView = web

        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        panel.title = "Splice Web Preview — \(previewTitle)"
        panel.contentView = web
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        window = panel
        web.load(URLRequest(url: url))
        Task { @MainActor [weak self] in self?.app?.captureSpliceWebPreviewURL(self?.url ?? url) }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        window?.close()
        webView = nil
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        Task { @MainActor [weak self] in self?.app?.spliceWebPreviewURL = nil }
        webView = nil
        window = nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url { Task { @MainActor [weak self] in self?.app?.captureSpliceWebPreviewURL(url) } }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { Task { @MainActor [weak self] in self?.app?.captureSpliceWebPreviewURL(url) } }
        let js = """
        JSON.stringify({
            url: window.location.href,
            title: document.title,
            html: document.documentElement ? document.documentElement.outerHTML : document.body.innerHTML
        })
        """
        webView.evaluateJavaScript(js) { [weak self, weak webView] value, _ in
            guard let self else { return }
            let currentURL = webView?.url
            var payload = ""
            if let text = value as? String, let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                payload = [json["url"] as? String, json["title"] as? String, json["html"] as? String]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            } else if let text = value as? String {
                payload = text
            }
            guard !payload.isEmpty else { return }
            Task { @MainActor [weak self] in self?.app?.captureSpliceWebPreviewHTML(payload, url: currentURL) }
        }
    }
}

final class LemmingsPluginEditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let audioUnit: AUAudioUnit
    private var onClose: (() -> Void)?

    init(title: String, audioUnit: AUAudioUnit) {
        self.title = title
        self.audioUnit = audioUnit
    }

    func show(onClose: @escaping () -> Void) {
        self.onClose = onClose
        audioUnit.requestViewController { [weak self] vendorController in
            DispatchQueue.main.async {
                guard let self else { return }
                if let vendorController {
                    self.openWindow(with: vendorController, mode: .vendor)
                } else {
                    self.openWindow(with: self.genericEditorController(), mode: .generic)
                }
            }
        }
    }

    private func genericEditorController() -> NSViewController {
        let params = audioUnit.parameterTree?.allParameters ?? []
        return NSHostingController(rootView: LemmingsGenericAUEditorView(title: title, parameters: params))
    }

    private func openWindow(with content: NSViewController, mode: EditorMode) {
        let panel = NSWindow(contentViewController: content)
        panel.title = mode == .vendor ? title : "\(title) · Generic Controls"
        panel.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        panel.setContentSize(mode == .vendor ? NSSize(width: 920, height: 680) : NSSize(width: 760, height: 620))
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        self.window = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
        window = nil
    }

    private enum EditorMode { case vendor, generic }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.title = title
            NSApp.mainWindow?.title = title
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ProDAWShell()
            .id(app.visualTheme.rawValue)
            .tint(LSTheme.focus)
            .accentColor(LSTheme.focus)
            .foregroundStyle(LSTheme.text)
            .sheet(isPresented: Binding(get: { app.showProjectSetupSheet }, set: { app.showProjectSetupSheet = $0 })) { ProjectSetupSheet().environment(app) }
            .background(GlobalShortcutCatcher(
                onSpace: { app.togglePlay() },
                onDelete: { app.deleteSelectedItem() },
                canDeleteInCurrentContext: { app.workspace == .arrangement },
                onUndo: { app.undoLastAction() },
                onRedo: { app.redoLastAction() },
                onTab: { app.cycleWorkspace() }
            ))
            .background(WindowTitleUpdater(title: app.windowTitle))
            .onAppear {
                app.showStartupSplashIfNeeded()
                app.requestInitialFullscreenIfNeeded()
            }
    }

    @ViewBuilder private var workspaceBody: some View {
        switch app.workspace {
        case .session:     SessionMatrixView()
        case .arrangement: ArrangementView()
        case .pianoRoll:   PianoRollView()
        case .step:        StepSequencerView()
        case .devices:     DeviceRackView()
        case .automation:  AutomationView()
        case .mixer:       MixerView()
        }
    }
}

struct WorkspaceTabBar: View {
    @Environment(AppState.self) private var app
    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceTab.allCases) { tab in
                Button { app.workspace = tab } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(app.workspace == tab ? Color.accentColor.opacity(0.25) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

private enum StandardMIDIImporter {
    struct Parsed { var notes: [ClipNote]; var lengthBeats: Double }

    static func parse(url: URL) throws -> Parsed {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        var i = 0
        func readString(_ count: Int) -> String {
            guard i + count <= bytes.count else { return "" }
            let s = String(bytes: bytes[i..<i+count], encoding: .ascii) ?? ""
            i += count
            return s
        }
        func readU16() -> Int { defer { i += 2 }; guard i + 1 < bytes.count else { return 0 }; return (Int(bytes[i]) << 8) | Int(bytes[i+1]) }
        func readU32() -> Int { defer { i += 4 }; guard i + 3 < bytes.count else { return 0 }; return (Int(bytes[i]) << 24) | (Int(bytes[i+1]) << 16) | (Int(bytes[i+2]) << 8) | Int(bytes[i+3]) }
        guard readString(4) == "MThd" else { return Parsed(notes: [], lengthBeats: 4) }
        let headerLen = readU32()
        let _ = readU16()
        let trackCount = max(1, readU16())
        let divisionRaw = readU16()
        if headerLen > 6 { i += max(0, headerLen - 6) }
        let tpq = (divisionRaw & 0x8000) == 0 ? max(1, divisionRaw) : 480
        var notes: [ClipNote] = []
        var maxBeat = 4.0

        for _ in 0..<trackCount where i + 8 <= bytes.count {
            guard readString(4) == "MTrk" else { break }
            let trackEnd = min(bytes.count, i + readU32())
            var tick = 0
            var runningStatus: UInt8 = 0
            var open: [String: (tick: Int, velocity: Float)] = [:]

            func readVarLen() -> Int {
                var value = 0
                while i < trackEnd {
                    let b = bytes[i]; i += 1
                    value = (value << 7) | Int(b & 0x7F)
                    if (b & 0x80) == 0 { break }
                }
                return value
            }
            func readByte() -> UInt8 { defer { i += 1 }; return i < trackEnd ? bytes[i] : 0 }

            while i < trackEnd {
                tick += readVarLen()
                if i >= trackEnd { break }
                var status = readByte()
                if status < 0x80 {
                    i -= 1
                    status = runningStatus
                } else {
                    runningStatus = status
                }

                if status == 0xFF {
                    _ = readByte()
                    let len = readVarLen()
                    i = min(trackEnd, i + len)
                    continue
                }
                if status == 0xF0 || status == 0xF7 {
                    let len = readVarLen()
                    i = min(trackEnd, i + len)
                    continue
                }

                let command = status & 0xF0
                let channel = Int(status & 0x0F)
                switch command {
                case 0x80, 0x90:
                    let note = Int(readByte())
                    let vel = Int(readByte())
                    let key = "\(channel):\(note)"
                    if command == 0x90 && vel > 0 {
                        open[key] = (tick, Float(vel) / 127.0)
                    } else if let start = open.removeValue(forKey: key) {
                        let startBeat = Double(start.tick) / Double(tpq)
                        let length = max(0.03, Double(tick - start.tick) / Double(tpq))
                        notes.append(ClipNote(pitch: note, start: startBeat, length: length, velocity: start.velocity))
                        maxBeat = max(maxBeat, startBeat + length)
                    }
                case 0xA0, 0xB0, 0xE0:
                    _ = readByte(); _ = readByte()
                case 0xC0, 0xD0:
                    _ = readByte()
                default:
                    break
                }
            }
            i = trackEnd
        }
        notes.sort { $0.start == $1.start ? $0.pitch < $1.pitch : $0.start < $1.start }
        return Parsed(notes: notes, lengthBeats: max(1, ceil(maxBeat)))
    }
}
