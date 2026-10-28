import Foundation
#if canImport(CoreMIDI)
import CoreMIDI
#endif

public enum MIDITransportCommand: String, Sendable {
    case play, stop, record, rewind, fastForward, loop
}

public enum MIDITransportProfile: String, CaseIterable, Identifiable, Sendable {
    case automatic = "Automatic"
    case presonusATOM = "PreSonus ATOM"
    case akaiMPKMiniIV = "AKAI MPK Mini IV"
    case generic = "Generic MIDI Transport"
    public var id: String { rawValue }
}

// MARK: - MIDI messages

public struct MIDIInputSource:Identifiable,Sendable { public var id:String;public var name:String }

public enum MIDIMessage: Sendable {
    case noteOn(note: Int, velocity: Float, channel: Int)
    case noteOff(note: Int, channel: Int)
    case cc(number: Int, value: Float, channel: Int)   // value 0...1
    case pitchBend(value: Float, channel: Int)         // -1...1, 0 == centered
    case channelPressure(value: Float, channel: Int)   // aftertouch, 0...1
    case polyPressure(note: Int, value: Float, channel: Int)
}

// MARK: - MIDI mapping (CC / pitch bend → automatable target)

public enum MIDIControlKind: String, Hashable, Sendable, Codable {
    case cc
    case pitchBend

    public var label: String {
        switch self {
        case .cc: return "CC"
        case .pitchBend: return "Pitch Bend"
        }
    }
}

public struct MIDIControlDescriptor: Hashable, Sendable, Codable {
    public var kind: MIDIControlKind
    /// CC number for `.cc`; nil for pitch bend.
    public var number: Int?
    /// Zero-based MIDI channel, or 0 for omni in mappings.
    public var channel: Int

    public init(kind: MIDIControlKind, number: Int? = nil, channel: Int) {
        self.kind = kind
        self.number = number
        self.channel = channel
    }

    public var displayName: String {
        switch kind {
        case .cc:
            return "CC \(number ?? 0) ch \(channel + 1)"
        case .pitchBend:
            return "Pitch Bend ch \(channel + 1)"
        }
    }
}

public struct MIDIMapping: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var controlKind: MIDIControlKind
    public var cc: Int
    public var channel: Int            // 0 == omni for mappings
    public var trackName: String?      // resolved to a track by name when applied
    public var nodeID: String          // "instrument" or device node id / well-known key
    public var paramID: String
    public var source: String          // "learn", "Ableton", "Logic"

    public init(cc: Int, channel: Int = 0, trackName: String? = nil,
                nodeID: String, paramID: String, source: String) {
        self.controlKind = .cc
        self.cc = cc
        self.channel = channel
        self.trackName = trackName
        self.nodeID = nodeID
        self.paramID = paramID
        self.source = source
    }

    public init(pitchBendChannel channel: Int = 0, trackName: String? = nil,
                nodeID: String, paramID: String, source: String) {
        self.controlKind = .pitchBend
        self.cc = -1
        self.channel = channel
        self.trackName = trackName
        self.nodeID = nodeID
        self.paramID = paramID
        self.source = source
    }

    public var controlLabel: String {
        switch controlKind {
        case .cc: return "CC \(cc)"
        case .pitchBend: return "Pitch Bend"
        }
    }
}

public struct MIDILearnTarget: Hashable, Sendable {
    public var trackID: UUID
    public var trackName: String
    public var nodeID: String
    public var paramID: String
    public var paramName: String

    public init(trackID: UUID, trackName: String, nodeID: String, paramID: String, paramName: String) {
        self.trackID = trackID
        self.trackName = trackName
        self.nodeID = nodeID
        self.paramID = paramID
        self.paramName = paramName
    }
}

@Observable public final class MIDIMappingStore {
    public var mappings: [MIDIMapping] = []
    public init() {}
    public func add(_ m: MIDIMapping) {
        mappings.removeAll { old in
            old.controlKind == m.controlKind && old.cc == m.cc && old.channel == m.channel && old.trackName == m.trackName
        }
        mappings.append(m)
    }
    public func matches(cc: Int, channel: Int) -> [MIDIMapping] {
        mappings.filter { $0.controlKind == .cc && $0.cc == cc && ($0.channel == 0 || $0.channel == channel) }
    }
    public func matchesPitchBend(channel: Int) -> [MIDIMapping] {
        mappings.filter { $0.controlKind == .pitchBend && ($0.channel == 0 || $0.channel == channel) }
    }
    public func merge(_ incoming: [MIDIMapping]) { for m in incoming { add(m) } }
}

// MARK: - CoreMIDI input

public final class MIDIInputManager {
    public private(set) var sourceNames: [String] = []
    public private(set) var sources:[MIDIInputSource]=[]
    public var onSourcedEvent: ((MIDIMessage,String)->Void)?
    public var onSourcesChanged:(()->Void)?
    public var onEvent: ((MIDIMessage) -> Void)?
    /// Learns the next useful MIDI control gesture. This includes classic CCs and pitch bend,
    /// because several compact keyboards expose joystick/touch-strip/pitch controls that users
    /// expect to map like Ableton macros.
    public var learnControl: ((_ control: MIDIControlDescriptor) -> Void)?
    /// Lightweight monitor hook for sanity-checking hardware input payloads.
    public var onDebugEvent: ((_ line: String) -> Void)?
    public var onTransportCommand: ((_ command: MIDITransportCommand) -> Void)?
    public var transportProfile: MIDITransportProfile = .automatic

    #if canImport(CoreMIDI)
    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var started = false
    private var connectedSourceIDs: Set<MIDIUniqueID> = []

    public init() {}

    public func start() {
        guard !started else { return }
        var status = MIDIClientCreateWithBlock("LemmingsStudio" as CFString, &client) { [weak self] notif in
            DispatchQueue.main.async {self?.refreshSources()}
        }
        guard status == noErr else { return }

        // Modern UMP input port.
        status = MIDIInputPortCreateWithProtocol(client, "In" as CFString, ._1_0, &inPort) { [weak self] evtList, source in
            self?.handle(evtList,sourceID:String(Int32(truncatingIfNeeded:Int(bitPattern:source))))
        }
        guard status == noErr else { return }
        connectAllSources()
        started = true
    }

    private func connectAllSources() {
        let count = MIDIGetNumberOfSources()
        var names: [String] = [];var devices:[MIDIInputSource]=[]
        for i in 0..<count {
            let src = MIDIGetSource(i)
            let uid = Self.uniqueID(of: src)
            if !connectedSourceIDs.contains(uid) {
                MIDIPortConnectSource(inPort, src, UnsafeMutableRawPointer(bitPattern:Int(uid)))
                connectedSourceIDs.insert(uid)
            }
            names.append(Self.displayName(of: src));devices.append(MIDIInputSource(id:String(uid),name:Self.displayName(of:src)))
        }
        let live=Set(devices.compactMap{Int32($0.id)})
        for uid in connectedSourceIDs.subtracting(live) {
            // The source has gone away. Keep no stale connected IDs so the same
            // keyboard can reconnect and be wired again on the next notification.
            connectedSourceIDs.remove(uid)
        }
        sourceNames = names;sources=devices;onSourcesChanged?()
    }
    private func refreshSources() { connectAllSources() }

    private static func uniqueID(of obj: MIDIObjectRef) -> MIDIUniqueID {
        var uid = MIDIUniqueID(0)
        MIDIObjectGetIntegerProperty(obj, kMIDIPropertyUniqueID, &uid)
        if uid == 0 { return MIDIUniqueID(obj) }
        return uid
    }

    private static func displayName(of obj: MIDIObjectRef) -> String {
        var param: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &param)
        return (param?.takeRetainedValue() as String?) ?? "MIDI Source"
    }

    private func handle(_ evtList: UnsafePointer<MIDIEventList>,sourceID:String) {
        let list = evtList.pointee
        var packet = list.packet
        for _ in 0..<list.numPackets {
            let words = withUnsafeBytes(of: packet.words) { raw -> [UInt32] in
                let ptr = raw.bindMemory(to: UInt32.self)
                return Array(ptr.prefix(Int(packet.wordCount)))
            }
            for w in words { decodeUMP(w,sourceID:sourceID) }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func effectiveTransportProfile() -> MIDITransportProfile {
        guard transportProfile == .automatic else { return transportProfile }
        let names = sourceNames.joined(separator: " ").lowercased()
        if names.contains("atom") || names.contains("presonus") { return .presonusATOM }
        if names.contains("mpk mini iv") || names.contains("mpk mini 4") || names.contains("mpk mini mk4") { return .akaiMPKMiniIV }
        return .generic
    }

    private func transportCommandForCC(_ number: Int, value: Int) -> MIDITransportCommand? {
        guard value >= 64 else { return nil }
        switch effectiveTransportProfile() {
        case .presonusATOM:
            return [85: .rewind, 86: .fastForward, 87: .stop, 88: .play, 89: .record, 90: .loop][number]
        case .akaiMPKMiniIV:
            return [114: .loop, 115: .rewind, 116: .fastForward, 117: .stop, 118: .play, 119: .record][number]
        case .generic, .automatic:
            return [115: .rewind, 116: .fastForward, 117: .stop, 118: .play, 119: .record][number]
        }
    }

    private func transportCommandForNote(_ note: Int, velocity: Int) -> MIDITransportCommand? {
        guard velocity > 0 else { return nil }
        switch effectiveTransportProfile() {
        case .presonusATOM:
            return [85: .rewind, 86: .fastForward, 87: .stop, 88: .play, 89: .record, 90: .loop][note]
        case .akaiMPKMiniIV, .generic, .automatic:
            return nil
        }
    }

    private func decodeUMP(_ word: UInt32,sourceID:String) {
        func emit(_ message:MIDIMessage){onSourcedEvent?(message,sourceID);onEvent?(message)}
        let mt = (word >> 28) & 0xF
        guard mt == 0x2 else { return }                 // MIDI 1.0 channel voice
        let status = UInt8((word >> 16) & 0xFF)
        let d1 = Int((word >> 8) & 0x7F)
        let d2 = Int(word & 0x7F)
        let cmd = status & 0xF0
        let ch = Int(status & 0x0F)
        switch cmd {
        case 0x90:
            if d2 == 0 {
                onDebugEvent?("NoteOff note=\(d1) ch=\(ch + 1) via NoteOn velocity 0")
                emit(.noteOff(note: d1, channel: ch))
            } else {
                onDebugEvent?("NoteOn note=\(d1) velocity=\(d2) ch=\(ch + 1)")
                if let command = transportCommandForNote(d1, velocity: d2) {
                    onTransportCommand?(command)
                } else {
                    emit(.noteOn(note: d1, velocity: Float(d2) / 127, channel: ch))
                }
            }
        case 0x80:
            onDebugEvent?("NoteOff note=\(d1) velocity=\(d2) ch=\(ch + 1)")
            emit(.noteOff(note: d1, channel: ch))
        case 0xB0:
            onDebugEvent?("CC \(d1) value=\(d2) ch=\(ch + 1)")
            if let command = transportCommandForCC(d1, value: d2) {
                onTransportCommand?(command)
            } else {
                learnControl?(MIDIControlDescriptor(kind: .cc, number: d1, channel: ch))
                emit(.cc(number: d1, value: Float(d2) / 127, channel: ch))
            }
        case 0xA0:
            onDebugEvent?("PolyPressure note=\(d1) value=\(d2) ch=\(ch + 1)")
            emit(.polyPressure(note: d1, value: Float(d2) / 127, channel: ch))
        case 0xD0:
            onDebugEvent?("ChannelPressure value=\(d1) ch=\(ch + 1)")
            emit(.channelPressure(value: Float(d1) / 127, channel: ch))
        case 0xE0:
            let raw = (d2 << 7) | d1
            let v = max(-1, min(1, (Float(raw) - 8192.0) / 8192.0))
            onDebugEvent?("PitchBend raw=\(raw) value=\(String(format: "%.4f", Double(v))) ch=\(ch + 1)")
            learnControl?(MIDIControlDescriptor(kind: .pitchBend, channel: ch))
            emit(.pitchBend(value: v, channel: ch))
        default: break
        }
    }
    #else
    public init() {}
    public func start() {}
    #endif
}
