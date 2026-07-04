import Foundation
import Darwin

public struct DiscordRichPresencePayload: Codable, Sendable {
    public var details: String
    public var state: String
    public var largeImageKey: String
    public var smallImageKey: String
    public var startTimestamp: Int?
    public var trackName: String
    public var trackKind: String
    public var transportStatus: String
    public var pluginSummary: String
    public var tempo: Double
    public var key: String
}

public enum DiscordPresenceConfig {
    public static let applicationID = "1518760745016365098"
}

public enum DiscordRichPresenceGuide {
    public static let requiredPortalSteps = [
        "Create an application in the Discord Developer Portal",
        "Application ID is now hardcoded: \(DiscordPresenceConfig.applicationID)",
        "Rich Presence assets: upload lemmings_large, lemmings_small, bhangra_architect, two_c, bailaton, oscillatron, lemmingbass, transport_play, transport_stop, transport_record, project, mixer",
        "Keep asset names lowercase; Discord can take a few minutes to propagate uploads"
    ]

    public static func payload(projectName: String, tempo: Double, key: String, workspace: String, playing: Bool, recording: Bool = false, trackName: String = "No track", trackKind: String = "None", pluginSummary: String = "No inserts") -> DiscordRichPresencePayload {
        let transport = recording ? "Recording" : (playing ? "Playing" : "Stopped")
        let details = "\(projectName) · \(Int(tempo)) BPM · \(key)"
        let state = "\(transport) · \(workspace) · \(trackName) · \(trackKind) · \(pluginSummary)"
        return DiscordRichPresencePayload(
            details: details,
            state: state,
            largeImageKey: "lemmings_large",
            smallImageKey: recording ? "transport_record" : (playing ? "transport_play" : "transport_stop"),
            startTimestamp: playing || recording ? Int(Date().timeIntervalSince1970) : nil,
            trackName: trackName,
            trackKind: trackKind,
            transportStatus: transport,
            pluginSummary: pluginSummary,
            tempo: tempo,
            key: key
        )
    }
}

public final class DiscordRichPresenceClient {
    private let applicationID: String
    private var socketFD: Int32 = -1
    private var connectedPath: String?
    private var lastPayloadHash = ""

    public init(applicationID: String = DiscordPresenceConfig.applicationID) {
        self.applicationID = applicationID
    }

    deinit { disconnect() }

    @discardableResult
    public func updatePresence(_ payload: DiscordRichPresencePayload) -> Bool {
        guard ensureConnected() else { return false }
        let hash = "\(payload.details)|\(payload.state)|\(payload.smallImageKey)|\(payload.startTimestamp ?? 0)"
        if hash == lastPayloadHash { return true }
        lastPayloadHash = hash
        let activity = activityJSON(from: payload)
        return send(opcode: 1, object: [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": Int(ProcessInfo.processInfo.processIdentifier),
                "activity": activity
            ],
            "nonce": UUID().uuidString
        ])
    }

    public func disconnect() {
        if socketFD >= 0 { close(socketFD) }
        socketFD = -1
        connectedPath = nil
        lastPayloadHash = ""
    }

    private func ensureConnected() -> Bool {
        if socketFD >= 0 { return true }
        for path in socketCandidates() {
            if connect(to: path) {
                connectedPath = path
                if send(opcode: 0, object: ["v": 1, "client_id": applicationID]) { return true }
                disconnect()
            }
        }
        return false
    }

    private func socketCandidates() -> [String] {
        var dirs: [String] = []
        let env = ProcessInfo.processInfo.environment
        for key in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"] {
            if let value = env[key], !value.isEmpty { dirs.append(value) }
        }
        dirs.append("/tmp")
        dirs.append("/var/tmp")
        dirs.append(NSHomeDirectory() + "/Library/Application Support/discord")
        dirs.append(NSHomeDirectory() + "/Library/Application Support/Vesktop")
        dirs.append(NSHomeDirectory() + "/Library/Application Support/VencordDesktop")

        var candidates: [String] = []
        var seen = Set<String>()
        for rawDir in dirs {
            let dir = (rawDir as NSString).expandingTildeInPath
            for name in discordSocketNames() {
                let path = (dir as NSString).appendingPathComponent(name)
                if seen.insert(path).inserted { candidates.append(path) }
            }
        }
        return candidates
    }

    private func discordSocketNames() -> [String] {
        (0..<10).flatMap { index in
            [
                "discord-ipc-\(index)",
                "discord-ipc-\(index).sock",
                "app/com.discordapp.Discord/discord-ipc-\(index)",
                "app/com.discordapp.DiscordCanary/discord-ipc-\(index)",
                "app/com.discordapp.DiscordPTB/discord-ipc-\(index)",
                "app/dev.vencord.Vesktop/discord-ipc-\(index)",
                "app/Vesktop/discord-ipc-\(index)"
            ]
        }
    }

    private func connect(to path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else { close(fd); return false }
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            path.withCString { cstr in
                raw.baseAddress?.copyMemory(from: cstr, byteCount: min(strlen(cstr) + 1, maxLen))
            }
        }
        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 {
            socketFD = fd
            return true
        }
        close(fd)
        return false
    }

    private func send(opcode: UInt32, object: Any) -> Bool {
        guard socketFD >= 0,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return false }
        var packet = Data()
        var opLE = opcode.littleEndian
        var lenLE = UInt32(data.count).littleEndian
        withUnsafeBytes(of: &opLE) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: &lenLE) { packet.append(contentsOf: $0) }
        packet.append(data)
        let ok = packet.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var sent = 0
            while sent < packet.count {
                let n = Darwin.write(socketFD, base.advanced(by: sent), packet.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
        if !ok { disconnect() }
        return ok
    }

    private func activityJSON(from payload: DiscordRichPresencePayload) -> [String: Any] {
        var activity: [String: Any] = [
            "details": payload.details,
            "state": payload.state,
            "assets": [
                "large_image": payload.largeImageKey,
                "large_text": "Lemmings Studio",
                "small_image": payload.smallImageKey,
                "small_text": payload.transportStatus
            ],
            "instance": false
        ]
        if let start = payload.startTimestamp { activity["timestamps"] = ["start": start] }
        return activity
    }
}
