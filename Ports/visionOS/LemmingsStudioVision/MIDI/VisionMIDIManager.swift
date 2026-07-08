import CoreMIDI
import Foundation

@MainActor
final class VisionMIDIManager {
    var onNoteOn: ((UInt8, UInt8) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?
    var onCC: ((UInt8, UInt8) -> Void)?
    var onPitchBend: ((UInt16) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private(set) var sourceNames: [String] = []
    private(set) var deviceSummaries: [VisionMIDIDeviceSummary] = []

    func start() {
        guard client == 0 else { refreshSources(); return }
        MIDIClientCreateWithBlock("LemmingsStudioVision" as CFString, &client) { [weak self] _ in
            Task { @MainActor in self?.refreshSources() }
        }
        MIDIInputPortCreateWithBlock(client, "Vision MIDI Input" as CFString, &inputPort) { [weak self] packetList, _ in
            guard let self else { return }
            var packet = packetList.pointee.packet
            for _ in 0..<packetList.pointee.numPackets {
                let length = Int(packet.length)
                withUnsafePointer(to: &packet.data) { tuplePtr in
                    tuplePtr.withMemoryRebound(to: UInt8.self, capacity: length) { bytes in
                        var index = 0
                        while index + 2 < length {
                            let status = bytes[index]
                            guard status >= 0x80 else { index += 1; continue }
                            let d1 = bytes[index + 1], d2 = bytes[index + 2]
                            Task { @MainActor [weak self] in self?.handle(status: status, d1: d1, d2: d2) }
                            index += 3
                        }
                    }
                }
                packet = MIDIPacketNext(&packet).pointee
            }
        }
        refreshSources()
    }

    func stop() {
        if inputPort != 0 { MIDIPortDispose(inputPort); inputPort = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
        sourceNames = []
        deviceSummaries = []
    }

    func refreshSources() {
        sourceNames.removeAll()
        deviceSummaries.removeAll()
        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            MIDIPortConnectSource(inputPort, endpoint, nil)
            let name = displayName(for: endpoint, fallback: "MIDI Source \(index + 1)")
            let lower = name.lowercased()
            let bluetoothLikely = lower.contains("bluetooth") || lower.contains("bt") || lower.contains("lumi") || lower.contains("roli") || lower.contains("seaboard")
            sourceNames.append(name)
            deviceSummaries.append(.init(name: name, kind: bluetoothLikely ? "Bluetooth/CoreMIDI" : "CoreMIDI", isBluetoothLikely: bluetoothLikely, isConnected: true))
        }
    }

    private func displayName(for endpoint: MIDIEndpointRef, fallback: String) -> String {
        var property: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &property)
        if let value = property?.takeRetainedValue() as String?, !value.isEmpty { return value }
        var nameProperty: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &nameProperty)
        if let value = nameProperty?.takeRetainedValue() as String?, !value.isEmpty { return value }
        return fallback
    }

    private func handle(status: UInt8, d1: UInt8, d2: UInt8) {
        switch status & 0xF0 {
        case 0x90: d2 == 0 ? onNoteOff?(d1) : onNoteOn?(d1, d2)
        case 0x80: onNoteOff?(d1)
        case 0xB0: onCC?(d1, d2)
        case 0xE0: onPitchBend?(UInt16(d1) | (UInt16(d2) << 7))
        default: break
        }
    }
}
