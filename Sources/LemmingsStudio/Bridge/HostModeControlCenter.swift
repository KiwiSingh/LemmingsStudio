import Foundation
import Observation
import AppKit

enum HostModeAccessLevel: String, CaseIterable, Identifiable {
    case readOnly = "Read Only"
    case fullControl = "Full Control"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .readOnly:
            return "Vision Pro may discover the Mac, inspect plug-ins and parameters, and receive status, but cannot instantiate, automate, send MIDI, stream editors, or request renders."
        case .fullControl:
            return "Vision Pro may instantiate hosted plug-ins, send MIDI and automation, stream editor input/audio, restore state, and request offline/project renders."
        }
    }
}

@MainActor
@Observable
final class HostModeControlCenter {
    static let shared = HostModeControlCenter()

    var autoStart: Bool {
        didSet {
            UserDefaults.standard.set(autoStart, forKey: Self.autoStartKey)
            if autoStart { start() }
        }
    }

    var accessLevel: HostModeAccessLevel {
        didSet {
            UserDefaults.standard.set(accessLevel.rawValue, forKey: Self.accessKey)
            DesktopPluginBridgeServer.shared.fullControlEnabled = accessLevel == .fullControl
            refresh()
        }
    }

    private(set) var isRunning = false
    private(set) var statusText = "Host Mode is stopped"
    private(set) var pairingCode = "------"
    private(set) var connectedDeviceNames: [String] = []
    private(set) var pairedDeviceNames: [String] = []
    private(set) var hostedInstanceCount = 0
    private(set) var trustedDeviceNames: [String] = []
    private(set) var lastError: String?
    private(set) var serviceName = "_lemmings-plugin._tcp"

    private static let autoStartKey = "lemmingsHostModeAutoStartV1"
    private static let accessKey = "lemmingsHostModeAccessV1"
    private var timer: Timer?

    private init() {
        autoStart = UserDefaults.standard.object(forKey: Self.autoStartKey) as? Bool ?? true
        accessLevel = HostModeAccessLevel(
            rawValue: UserDefaults.standard.string(forKey: Self.accessKey) ?? ""
        ) ?? .fullControl

        DesktopPluginBridgeServer.shared.fullControlEnabled = accessLevel == .fullControl
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func start() {
        DesktopPluginBridgeServer.shared.fullControlEnabled = accessLevel == .fullControl
        DesktopPluginBridgeServer.shared.start()
        refresh()
    }

    func stop() {
        DesktopPluginBridgeServer.shared.stop()
        refresh()
    }

    func toggle() { isRunning ? stop() : start() }

    func regeneratePairingCode() {
        DesktopPluginBridgeServer.shared.regeneratePairingCode()
        refresh()
    }

    func disconnectAll() {
        DesktopPluginBridgeServer.shared.disconnectAllClients()
        refresh()
    }

    func forgetTrustedDevice(_ name: String) {
        DesktopPluginBridgeServer.shared.forgetTrustedDevice(named: name)
        refresh()
    }

    func forgetAllTrustedDevices() {
        DesktopPluginBridgeServer.shared.forgetAllTrustedDevices()
        refresh()
    }

    func copyPairingCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingCode, forType: .string)
    }

    func refresh() {
        let snapshot = DesktopPluginBridgeServer.shared.statusSnapshot()
        isRunning = snapshot.isRunning
        pairingCode = snapshot.pairingCode
        connectedDeviceNames = snapshot.connectedDeviceNames
        pairedDeviceNames = snapshot.pairedDeviceNames
        hostedInstanceCount = snapshot.hostedInstanceCount
        trustedDeviceNames = snapshot.trustedDeviceNames
        lastError = snapshot.lastError
        serviceName = snapshot.serviceName

        if let lastError, !lastError.isEmpty {
            statusText = "Host Mode error: \(lastError)"
        } else if !isRunning {
            statusText = "Host Mode is stopped"
        } else if pairedDeviceNames.isEmpty {
            statusText = "Advertising on the local network · waiting for Vision Pro"
        } else {
            statusText = "\(pairedDeviceNames.count) paired device\(pairedDeviceNames.count == 1 ? "" : "s") · \(hostedInstanceCount) hosted instance\(hostedInstanceCount == 1 ? "" : "s")"
        }
    }
}
