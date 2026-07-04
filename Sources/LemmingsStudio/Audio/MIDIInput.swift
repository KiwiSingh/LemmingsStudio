import Foundation
#if canImport(CoreMIDI)
import CoreMIDI
#endif

// MARK: - MIDI messages

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
    public var onEvent: ((MIDIMessage) -> Void)?
    /// Learns the next useful MIDI control gesture. This includes classic CCs and pitch bend,
    /// because several compact keyboards expose joystick/touch-strip/pitch controls that users
    /// expect to map like Ableton macros.
    public var learnControl: ((_ control: MIDIControlDescriptor) -> Void)?
    /// Lightweight monitor hook for sanity-checking hardware input payloads.
    public var onDebugEvent: ((_ line: String) -> Void)?

    #if canImport(CoreMIDI)
    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var started = false
    private var connectedSourceIDs: Set<MIDIUniqueID> = []

    public init() {}

    public func start() {
        guard !started else { return }
        var status = MIDIClientCreateWithBlock("LemmingsStudio" as CFString, &client) { [weak self] notif in
            self?.refreshSources()
        }
        guard status == noErr else { return }

        // Modern UMP input port.
        status = MIDIInputPortCreateWithProtocol(client, "In" as CFString, ._1_0, &inPort) { [weak self] evtList, _ in
            self?.handle(evtList)
        }
        guard status == noErr else { return }
        connectAllSources()
        started = true
    }

    private func connectAllSources() {
        let count = MIDIGetNumberOfSources()
        var names: [String] = []
        for i in 0..<count {
            let src = MIDIGetSource(i)
            let uid = Self.uniqueID(of: src)
            if !connectedSourceIDs.contains(uid) {
                MIDIPortConnectSource(inPort, src, nil)
                connectedSourceIDs.insert(uid)
            }
            names.append(Self.displayName(of: src))
        }
        sourceNames = names
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

    private func handle(_ evtList: UnsafePointer<MIDIEventList>) {
        let list = evtList.pointee
        var packet = list.packet
        for _ in 0..<list.numPackets {
            let words = withUnsafeBytes(of: packet.words) { raw -> [UInt32] in
                let ptr = raw.bindMemory(to: UInt32.self)
                return Array(ptr.prefix(Int(packet.wordCount)))
            }
            for w in words { decodeUMP(w) }
            packet = MIDIEventPacketNext(&packet).pointee
        }
    }

    private func decodeUMP(_ word: UInt32) {
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
                onEvent?(.noteOff(note: d1, channel: ch))
            } else {
                onDebugEvent?("NoteOn note=\(d1) velocity=\(d2) ch=\(ch + 1)")
                onEvent?(.noteOn(note: d1, velocity: Float(d2) / 127, channel: ch))
            }
        case 0x80:
            onDebugEvent?("NoteOff note=\(d1) velocity=\(d2) ch=\(ch + 1)")
            onEvent?(.noteOff(note: d1, channel: ch))
        case 0xB0:
            onDebugEvent?("CC \(d1) value=\(d2) ch=\(ch + 1)")
            learnControl?(MIDIControlDescriptor(kind: .cc, number: d1, channel: ch))
            onEvent?(.cc(number: d1, value: Float(d2) / 127, channel: ch))
        case 0xA0:
            onDebugEvent?("PolyPressure note=\(d1) value=\(d2) ch=\(ch + 1)")
            onEvent?(.polyPressure(note: d1, value: Float(d2) / 127, channel: ch))
        case 0xD0:
            onDebugEvent?("ChannelPressure value=\(d1) ch=\(ch + 1)")
            onEvent?(.channelPressure(value: Float(d1) / 127, channel: ch))
        case 0xE0:
            let raw = (d2 << 7) | d1
            let v = max(-1, min(1, (Float(raw) - 8192.0) / 8192.0))
            onDebugEvent?("PitchBend raw=\(raw) value=\(String(format: "%.4f", Double(v))) ch=\(ch + 1)")
            learnControl?(MIDIControlDescriptor(kind: .pitchBend, channel: ch))
            onEvent?(.pitchBend(value: v, channel: ch))
        default: break
        }
    }
    #else
    public init() {}
    public func start() {}
    #endif
}
