import Foundation
@preconcurrency import AVFAudio
@preconcurrency import AudioToolbox
import Observation

struct VisionAudioUnitDescriptor: Identifiable, @unchecked Sendable {
    let id: String
    let name: String
    let manufacturer: String
    let versionString: String
    let type: VisionAudioUnitKind
    let description: AudioComponentDescription

    static func makeID(_ d: AudioComponentDescription) -> String {
        "\(d.componentType)-\(d.componentSubType)-\(d.componentManufacturer)"
    }
}

enum VisionAudioUnitKind: String, Codable, Sendable {
    case instrument = "Instrument"
    case effect = "Effect"
    case generator = "Generator"
    case other = "Other"

    init(componentType: OSType) {
        switch componentType {
        case kAudioUnitType_MusicDevice, kAudioUnitType_RemoteInstrument:
            self = .instrument
        case kAudioUnitType_Effect, kAudioUnitType_MusicEffect:
            self = .effect
        case kAudioUnitType_Generator:
            self = .generator
        default:
            self = .other
        }
    }
}

struct VisionAudioUnitParameter: Identifiable, Hashable, Sendable {
    let id: UInt64
    let identifier: String
    let name: String
    let minValue: Float
    let maxValue: Float
    let unitName: String
    var value: Float
}

@MainActor
@Observable
final class VisionAudioUnitHost {
    var availableUnits: [VisionAudioUnitDescriptor] = []
    var activeDescriptor: VisionAudioUnitDescriptor?
    var parameters: [VisionAudioUnitParameter] = []
    var statusMessage = "No Audio Unit loaded"
    var isScanning = false
    var isLoading = false
    var customViewController: AnyObject?

    private(set) var activeUnit: AVAudioUnit?
    var hasActiveInstrument: Bool { activeDescriptor?.type == .instrument || activeDescriptor?.type == .generator }
    private var parameterObserver: AUParameterObserverToken?
    private weak var audioEngine: VisionAudioEngine?

    init(audioEngine: VisionAudioEngine) {
        self.audioEngine = audioEngine
    }

    func scan() {
        isScanning = true
        defer { isScanning = false }
        let manager = AVAudioUnitComponentManager.shared()
        let components = manager.components { component, _ in
            let type = component.audioComponentDescription.componentType
            return type == kAudioUnitType_MusicDevice ||
                   type == kAudioUnitType_RemoteInstrument ||
                   type == kAudioUnitType_Effect ||
                   type == kAudioUnitType_MusicEffect ||
                   type == kAudioUnitType_Generator
        }
        availableUnits = components.map { component in
            let description = component.audioComponentDescription
            return VisionAudioUnitDescriptor(
                id: VisionAudioUnitDescriptor.makeID(description),
                name: component.name,
                manufacturer: component.manufacturerName,
                versionString: component.versionString,
                type: VisionAudioUnitKind(componentType: description.componentType),
                description: description
            )
        }
        .sorted { lhs, rhs in
            if lhs.type.rawValue == rhs.type.rawValue { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
            return lhs.type.rawValue < rhs.type.rawValue
        }
        statusMessage = availableUnits.isEmpty ? "No compatible Audio Units found" : "Found \(availableUnits.count) Audio Units"
    }

    func instantiate(_ descriptor: VisionAudioUnitDescriptor, restoring stateData: Data? = nil) async {
        isLoading = true
        statusMessage = "Loading \(descriptor.name)…"
        defer { isLoading = false }

        do {
            let unit = try await instantiateAsync(description: descriptor.description)
            if let stateData,
               let dictionary = try PropertyListSerialization.propertyList(from: stateData, options: [], format: nil) as? [String: Any] {
                unit.auAudioUnit.fullStateForDocument = dictionary
            }
            try audioEngine?.hostAudioUnit(unit, kind: descriptor.type)
            activeUnit = unit
            activeDescriptor = descriptor
            observeParameters(unit)
            await requestCustomViewController(unit)
            statusMessage = "Loaded \(descriptor.name)"
        } catch {
            statusMessage = "Load failed: \(error.localizedDescription)"
        }
    }

    func unload() {
        if let token = parameterObserver, let tree = activeUnit?.auAudioUnit.parameterTree {
            tree.removeParameterObserver(token)
        }
        parameterObserver = nil
        audioEngine?.unhostAudioUnit()
        activeUnit = nil
        activeDescriptor = nil
        parameters = []
        customViewController = nil
        statusMessage = "Audio Unit unloaded"
    }

    func setParameter(id: UInt64, value: Float) {
        guard let parameter = activeUnit?.auAudioUnit.parameterTree?.allParameters.first(where: { UInt64($0.address) == id }) else { return }
        parameter.setValue(value, originator: parameterObserver)
        refreshParameters()
    }

    func snapshotState() -> VisionHostedAudioUnitState? {
        guard let descriptor = activeDescriptor,
              let fullState = activeUnit?.auAudioUnit.fullStateForDocument,
              PropertyListSerialization.propertyList(fullState, isValidFor: .binary),
              let data = try? PropertyListSerialization.data(fromPropertyList: fullState, format: .binary, options: 0)
        else { return nil }
        return VisionHostedAudioUnitState(
            componentType: descriptor.description.componentType,
            componentSubType: descriptor.description.componentSubType,
            componentManufacturer: descriptor.description.componentManufacturer,
            name: descriptor.name,
            kind: descriptor.type,
            stateBase64: data.base64EncodedString()
        )
    }

    func restore(_ saved: VisionHostedAudioUnitState) async {
        let target = availableUnits.first { descriptor in
            descriptor.description.componentType == saved.componentType &&
            descriptor.description.componentSubType == saved.componentSubType &&
            descriptor.description.componentManufacturer == saved.componentManufacturer
        }
        guard let target else {
            statusMessage = "Missing Audio Unit: \(saved.name)"
            return
        }
        await instantiate(target, restoring: Data(base64Encoded: saved.stateBase64))
    }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        guard let instrument = activeUnit as? AVAudioUnitMIDIInstrument else { return }
        instrument.sendMIDIEvent(0x90 | (channel & 0x0F), data1: note, data2: velocity)
    }

    func sendNoteOff(note: UInt8, channel: UInt8 = 0) {
        guard let instrument = activeUnit as? AVAudioUnitMIDIInstrument else { return }
        instrument.sendMIDIEvent(0x80 | (channel & 0x0F), data1: note, data2: 0)
    }

    func sendCC(_ cc: UInt8, value: UInt8, channel: UInt8 = 0) {
        guard let instrument = activeUnit as? AVAudioUnitMIDIInstrument else { return }
        instrument.sendMIDIEvent(0xB0 | (channel & 0x0F), data1: cc, data2: value)
    }

    func sendPitchBend(lsb: UInt8, msb: UInt8, channel: UInt8 = 0) {
        guard let instrument = activeUnit as? AVAudioUnitMIDIInstrument else { return }
        instrument.sendMIDIEvent(0xE0 | (channel & 0x0F), data1: lsb, data2: msb)
    }

    private func instantiateAsync(description: AudioComponentDescription) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: []) { unit, error in
                if let unit { continuation.resume(returning: unit) }
                else { continuation.resume(throwing: error ?? NSError(domain: "LemmingsStudio.AUv3", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio Unit instantiation returned no unit"])) }
            }
        }
    }

    private func observeParameters(_ unit: AVAudioUnit) {
        if let token = parameterObserver, let tree = activeUnit?.auAudioUnit.parameterTree {
            tree.removeParameterObserver(token)
        }
        guard let tree = unit.auAudioUnit.parameterTree else {
            parameters = []
            return
        }
        parameterObserver = tree.token(byAddingParameterObserver: { [weak self] _, _ in
            Task { @MainActor in self?.refreshParameters() }
        })
        refreshParameters()
    }

    private func refreshParameters() {
        guard let all = activeUnit?.auAudioUnit.parameterTree?.allParameters else { parameters = []; return }
        parameters = all.map { parameter in
            VisionAudioUnitParameter(
                id: UInt64(parameter.address),
                identifier: parameter.identifier,
                name: parameter.displayName,
                minValue: parameter.minValue,
                maxValue: parameter.maxValue,
                unitName: parameter.unitName ?? "",
                value: parameter.value
            )
        }
    }

    private func requestCustomViewController(_ unit: AVAudioUnit) async {
        customViewController = await withCheckedContinuation { continuation in
            unit.auAudioUnit.requestViewController { controller in
                continuation.resume(returning: controller)
            }
        }
    }
}
