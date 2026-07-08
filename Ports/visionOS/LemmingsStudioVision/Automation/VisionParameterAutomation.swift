import Foundation
import Observation

enum VisionAutomationWriteMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case read = "Read"
    case write = "Write"
    case touch = "Touch"
    case latch = "Latch"
    var id: String { rawValue }
}


enum VisionSpatialAutomationGesture: String, Codable, CaseIterable, Identifiable, Sendable {
    case sway = "Sway"
    case pulse = "Pulse"
    case glide = "Glide"
    case strike = "Strike"
    case press = "Press"
    case sculpt = "Sculpt"
    var id: String { rawValue }

    var help: String {
        switch self {
        case .sway: return "Horizontal movement across the performance field."
        case .pulse: return "Vertical movement for rises, falls, and rhythmic modulation."
        case .glide: return "Depth movement for continuous travel through a parameter range."
        case .strike: return "Gesture speed converted into a transient control signal."
        case .press: return "Sustained gesture intensity for dynamics and effect depth."
        case .sculpt: return "Two-axis spread/shape gesture for broad timbral movement."
        }
    }
}

enum VisionAutomationCurve: String, Codable, CaseIterable, Identifiable, Sendable {
    case hold = "Hold"
    case linear = "Linear"
    case smooth = "Smooth"
    case exponential = "Exponential"
    var id: String { rawValue }
}

struct VisionAutomationParameterAddress: Codable, Hashable, Sendable {
    var backendID: String
    var instanceID: String
    var parameterID: String
    var displayName: String
}

struct VisionAutomationPoint: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var beat: Double
    var value: Float
    var curve: VisionAutomationCurve = .linear
    /// -1...1. Positive values bias the segment toward the destination, negative toward the source.
    var curveHandle: Float = 0

    enum CodingKeys: String, CodingKey { case id, beat, value, curve, curveHandle }
    init(id: UUID = UUID(), beat: Double, value: Float, curve: VisionAutomationCurve = .linear, curveHandle: Float = 0) {
        self.id = id; self.beat = beat; self.value = value; self.curve = curve; self.curveHandle = curveHandle
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        beat = try c.decode(Double.self, forKey: .beat)
        value = try c.decode(Float.self, forKey: .value)
        if let typed = try? c.decode(VisionAutomationCurve.self, forKey: .curve) { curve = typed }
        else if let legacy = try? c.decode(String.self, forKey: .curve) { curve = VisionAutomationCurve(rawValue: legacy.capitalized) ?? .linear }
        else { curve = .linear }
        curveHandle = try c.decodeIfPresent(Float.self, forKey: .curveHandle) ?? 0
    }
}

struct VisionAutomationLane: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var address: VisionAutomationParameterAddress
    var points: [VisionAutomationPoint]
    var visible: Bool
    var armed: Bool
    var writeMode: VisionAutomationWriteMode = .read
    /// visionOS-only expressive input mapping. The recorded result remains ordinary breakpoint automation.
    var spatialGesture: VisionSpatialAutomationGesture? = nil
    var spatialMinimum: Float = 0
    var spatialMaximum: Float = 1
    var spatialInverted: Bool = false

    enum CodingKeys: String, CodingKey { case id, address, points, visible, armed, writeMode, spatialGesture, spatialMinimum, spatialMaximum, spatialInverted }
    init(id: UUID = UUID(), address: VisionAutomationParameterAddress, points: [VisionAutomationPoint], visible: Bool, armed: Bool, writeMode: VisionAutomationWriteMode = .read, spatialGesture: VisionSpatialAutomationGesture? = nil, spatialMinimum: Float = 0, spatialMaximum: Float = 1, spatialInverted: Bool = false) {
        self.id = id; self.address = address; self.points = points; self.visible = visible; self.armed = armed; self.writeMode = writeMode
        self.spatialGesture = spatialGesture; self.spatialMinimum = spatialMinimum; self.spatialMaximum = spatialMaximum; self.spatialInverted = spatialInverted
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        address = try c.decode(VisionAutomationParameterAddress.self, forKey: .address)
        points = try c.decodeIfPresent([VisionAutomationPoint].self, forKey: .points) ?? []
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        armed = try c.decodeIfPresent(Bool.self, forKey: .armed) ?? false
        writeMode = try c.decodeIfPresent(VisionAutomationWriteMode.self, forKey: .writeMode) ?? .read
        spatialGesture = try c.decodeIfPresent(VisionSpatialAutomationGesture.self, forKey: .spatialGesture)
        spatialMinimum = try c.decodeIfPresent(Float.self, forKey: .spatialMinimum) ?? 0
        spatialMaximum = try c.decodeIfPresent(Float.self, forKey: .spatialMaximum) ?? 1
        spatialInverted = try c.decodeIfPresent(Bool.self, forKey: .spatialInverted) ?? false
    }

    func mappedSpatialValue(_ input: Float) -> Float {
        let x = max(0, min(1, spatialInverted ? 1 - input : input))
        return max(0, min(1, spatialMinimum + (spatialMaximum - spatialMinimum) * x))
    }
}

@MainActor
@Observable
final class VisionAutomationParityState {
    var lanes: [VisionAutomationLane] = []
    var status = "Automation parity idle"
    var selectedLaneID: UUID?
    var selectedPointID: UUID?
    private var touchedLaneIDs: Set<UUID> = []
    private var latchedLaneIDs: Set<UUID> = []
    private var lastRecordedBeatByLane: [UUID: Double] = [:]

    func restore(_ saved: [VisionAutomationLane]?) {
        lanes = saved ?? []
        selectedLaneID = lanes.first?.id
        touchedLaneIDs.removeAll(); latchedLaneIDs.removeAll(); lastRecordedBeatByLane.removeAll()
        status = lanes.isEmpty ? "No saved automation lanes." : "Restored \(lanes.count) automation lanes."
    }

    func expose(parameters: [VisionCompanionParameter], backendID: String, instanceID: String) {
        for parameter in parameters where parameter.isAutomatable {
            let address = VisionAutomationParameterAddress(backendID: backendID, instanceID: instanceID, parameterID: parameter.address, displayName: parameter.name)
            if !lanes.contains(where: { $0.address == address }) {
                lanes.append(.init(address: address, points: [.init(beat: 0, value: parameter.value, curve: .hold)], visible: false, armed: false))
            }
        }
        status = "Exposed \(parameters.filter { $0.isAutomatable }.count) automatable parameters."
    }

    func exposeMixer(project: LemmingsProject) {
        for track in project.tracks {
            let id = track.id.uuidString
            let candidates: [(String, String, Float)] = [("volume", "\(track.name) Volume", track.volume ?? 1), ("pan", "\(track.name) Pan", ((track.pan ?? 0) + 1) * 0.5)]
            for (parameterID, name, value) in candidates {
                let address = VisionAutomationParameterAddress(backendID: "visionMixer", instanceID: id, parameterID: parameterID, displayName: name)
                if !lanes.contains(where: { $0.address == address }) {
                    lanes.append(.init(address: address, points: [.init(beat: 0, value: value, curve: .hold)], visible: true, armed: false))
                }
            }
        }
        status = "Exposed mixer volume and pan automation for \(project.tracks.count) tracks."
    }


    func exposeProjectTempo(project: LemmingsProject) {
        let normalized = Float(max(0, min(1, (project.effectiveTempo - 20.0) / 380.0)))
        let address = VisionAutomationParameterAddress(
            backendID: "visionProject",
            instanceID: "project",
            parameterID: "tempo",
            displayName: "Project Tempo"
        )
        if !lanes.contains(where: { $0.address == address }) {
            lanes.append(.init(address: address, points: [.init(beat: 0, value: normalized, curve: .smooth)], visible: true, armed: false))
        }
        selectedLaneID = lanes.first(where: { $0.address == address })?.id
        status = "Exposed global project tempo automation."
    }

    func exposeStockFX(track: VisionTrack) {
        let rack = track.stockFXRack ?? .defaults
        for parameter in VisionStockFXParameterRegistry.all {
            let address = VisionAutomationParameterAddress(
                backendID: "visionTrackStockFX",
                instanceID: "\((track.automationID ?? track.id).uuidString)::\(parameter.effect.rawValue)",
                parameterID: parameter.parameterID,
                displayName: "\(track.name) • \(parameter.effect.rawValue) • \(parameter.name)"
            )
            if !lanes.contains(where: { $0.address == address }) {
                lanes.append(.init(
                    address: address,
                    points: [.init(beat: 0, value: rack.value(effect: parameter.effect, parameterID: parameter.parameterID), curve: .smooth)],
                    visible: true,
                    armed: false
                ))
            }
        }
        status = "Exposed \(VisionStockFXParameterRegistry.all.count) stock FX parameters for \(track.name)."
    }

    func exposeSpatial(object: VisionSpatialObject) {
        let id = object.id.uuidString
        let values: [(String, String, Float)] = [
            ("position.x", "\(object.name) X", normalizeSpatial(object.transform.position.x)),
            ("position.y", "\(object.name) Y", normalizeSpatial(object.transform.position.y)),
            ("position.z", "\(object.name) Z", normalizeSpatial(object.transform.position.z))
        ]
        for (parameterID, name, value) in values {
            let address = VisionAutomationParameterAddress(backendID: "visionSpatial", instanceID: id, parameterID: parameterID, displayName: name)
            if !lanes.contains(where: { $0.address == address }) {
                lanes.append(.init(address: address, points: [.init(beat: 0, value: value, curve: .smooth)], visible: true, armed: false))
            }
        }
        status = "Exposed spatial X/Y/Z gesture automation for \(object.name)."
    }

    func addPoint(laneID: UUID, beat: Double, value: Float) {
        guard let index = lanes.firstIndex(where: { $0.id == laneID }) else { return }
        upsertPoint(index: index, beat: beat, value: value, curve: .linear)
        status = "Added automation point at beat \(String(format: "%.2f", beat))."
    }

    func removePoint(laneID: UUID, pointID: UUID) {
        guard let index = lanes.firstIndex(where: { $0.id == laneID }) else { return }
        lanes[index].points.removeAll { $0.id == pointID }
    }

    func setCurve(laneID: UUID, pointID: UUID, curve: VisionAutomationCurve, handle: Float) {
        guard let laneIndex = lanes.firstIndex(where: { $0.id == laneID }), let pointIndex = lanes[laneIndex].points.firstIndex(where: { $0.id == pointID }) else { return }
        lanes[laneIndex].points[pointIndex].curve = curve
        lanes[laneIndex].points[pointIndex].curveHandle = max(-1, min(1, handle))
    }

    func beginTouch(laneID: UUID) { touchedLaneIDs.insert(laneID) }
    func endTouch(laneID: UUID) {
        touchedLaneIDs.remove(laneID)
        if let lane = lanes.first(where: { $0.id == laneID }), lane.writeMode != .latch { latchedLaneIDs.remove(laneID) }
    }
    func releaseAllLatches() { latchedLaneIDs.removeAll(); status = "Released all automation latches." }

    func captureGesture(backendID: String, instanceID: String, parameterID: String, beat: Double, normalizedValue: Float) {
        guard let index = lanes.firstIndex(where: { $0.address.backendID == backendID && $0.address.instanceID == instanceID && $0.address.parameterID == parameterID }), lanes[index].armed else { return }
        let lane = lanes[index]
        let shouldRecord: Bool
        switch lane.writeMode {
        case .read: shouldRecord = false
        case .write: shouldRecord = true
        case .touch: shouldRecord = touchedLaneIDs.contains(lane.id)
        case .latch:
            if touchedLaneIDs.contains(lane.id) { latchedLaneIDs.insert(lane.id) }
            shouldRecord = latchedLaneIDs.contains(lane.id)
        }
        guard shouldRecord else { return }
        let quantizedBeat = (beat * 16).rounded() / 16
        if let last = lastRecordedBeatByLane[lane.id], abs(last - quantizedBeat) < 0.0001 {
            if let p = lanes[index].points.indices.last { lanes[index].points[p].value = clamp(normalizedValue) }
        } else {
            upsertPoint(index: index, beat: quantizedBeat, value: normalizedValue, curve: .smooth)
            lastRecordedBeatByLane[lane.id] = quantizedBeat
        }
        status = "Recording \(lane.address.displayName) automation (\(lane.writeMode.rawValue))."
    }

    func lanes(mappedTo gesture: VisionSpatialAutomationGesture) -> [VisionAutomationLane] {
        lanes.filter { $0.spatialGesture == gesture }
    }

    func beginSpatialGesture(_ gesture: VisionSpatialAutomationGesture) {
        for lane in lanes where lane.spatialGesture == gesture { beginTouch(laneID: lane.id) }
        status = "Spatial gesture begun: \(gesture.rawValue)."
    }

    func endSpatialGesture(_ gesture: VisionSpatialAutomationGesture) {
        for lane in lanes where lane.spatialGesture == gesture { endTouch(laneID: lane.id) }
        status = "Spatial gesture ended: \(gesture.rawValue)."
    }

    func captureSpatialGesture(_ gesture: VisionSpatialAutomationGesture, beat: Double, normalizedValue: Float, apply: (VisionAutomationLane, Float) -> Void) {
        let input = clamp(normalizedValue)
        let mapped = lanes.indices.filter { lanes[$0].spatialGesture == gesture }
        guard !mapped.isEmpty else {
            status = "Map a lane to \(gesture.rawValue) before performing."
            return
        }
        for index in mapped {
            let lane = lanes[index]
            let value = lane.mappedSpatialValue(input)
            apply(lane, value)
            captureGesture(backendID: lane.address.backendID, instanceID: lane.address.instanceID, parameterID: lane.address.parameterID, beat: beat, normalizedValue: value)
        }
    }

    func value(for lane: VisionAutomationLane, at beat: Double) -> Float? {
        let points = lane.points.sorted { $0.beat < $1.beat }
        guard let first = points.first else { return nil }
        if beat <= first.beat { return first.value }
        guard let last = points.last else { return first.value }
        if beat >= last.beat { return last.value }
        for (a, b) in zip(points, points.dropFirst()) where beat >= a.beat && beat <= b.beat {
            let rawT = Float((beat - a.beat) / max(0.000001, b.beat - a.beat))
            let t: Float
            switch a.curve {
            case .hold: return a.value
            case .linear: t = bias(rawT, handle: a.curveHandle)
            case .smooth:
                let x = bias(rawT, handle: a.curveHandle); t = x * x * (3 - 2 * x)
            case .exponential:
                let power = powf(2, a.curveHandle * 3); t = powf(max(0, rawT), power)
            }
            return a.value + (b.value - a.value) * t
        }
        return last.value
    }

    private func upsertPoint(index: Int, beat: Double, value: Float, curve: VisionAutomationCurve) {
        let safeBeat = max(0, beat), safeValue = clamp(value)
        if let existing = lanes[index].points.firstIndex(where: { abs($0.beat - safeBeat) < 0.0001 }) {
            lanes[index].points[existing].value = safeValue
        } else {
            lanes[index].points.append(.init(beat: safeBeat, value: safeValue, curve: curve))
            lanes[index].points.sort { $0.beat < $1.beat }
        }
    }
    private func clamp(_ value: Float) -> Float { max(0, min(1, value)) }
    private func bias(_ t: Float, handle: Float) -> Float {
        let h = max(-0.95, min(0.95, handle))
        if abs(h) < 0.001 { return t }
        let exponent = powf(2, h * -3)
        return powf(max(0, min(1, t)), exponent)
    }
    private func normalizeSpatial(_ value: Double) -> Float { Float(max(0, min(1, (value + 2) / 4))) }
    func denormalizeSpatial(_ value: Float) -> Double { Double(value) * 4 - 2 }
}

extension VisionStudioModel {
    func exposeSelectedCompanionParametersForAutomation() {
        guard let instance = companionParity.selectedInstance else { statusMessage = "No Companion instance selected for automation exposure."; return }
        automationParity.expose(parameters: instance.parameters, backendID: "macCompanion", instanceID: instance.id)
        statusMessage = "Exposed \(instance.parameters.count) Companion parameters to visionOS automation."
    }
    func exposeVisionMixerAutomation() { automationParity.exposeMixer(project: project); statusMessage = automationParity.status }
    func exposeStockFXAutomation(trackID: UUID? = nil) {
        ensureTrackStockFXDefaults()
        if let trackID, let track = project.tracks.first(where: { $0.id == trackID }) {
            automationParity.exposeStockFX(track: track)
        } else {
            for track in project.tracks { automationParity.exposeStockFX(track: track) }
        }
        statusMessage = automationParity.status
    }
    func exposeProjectTempoAutomation() { automationParity.exposeProjectTempo(project: project); statusMessage = automationParity.status }
    func exposeSelectedSpatialAutomation() {
        guard let object = selectedSpatialObject else { statusMessage = "Select a spatial surface first."; return }
        automationParity.exposeSpatial(object: object); statusMessage = automationParity.status
    }
    func beginSpatialAutomationTouch(objectID: UUID, parameterID: String) {
        if let lane = automationParity.lanes.first(where: { $0.address.backendID == "visionSpatial" && $0.address.instanceID == objectID.uuidString && $0.address.parameterID == parameterID }) { automationParity.beginTouch(laneID: lane.id) }
    }
    func endSpatialAutomationTouch(objectID: UUID, parameterID: String) {
        if let lane = automationParity.lanes.first(where: { $0.address.backendID == "visionSpatial" && $0.address.instanceID == objectID.uuidString && $0.address.parameterID == parameterID }) { automationParity.endTouch(laneID: lane.id) }
    }

    func persistAutomationIntoProject() { project.automationLanes = automationParity.lanes }
    func restoreAutomationFromProject() { automationParity.restore(project.automationLanes) }

    func recordSpatialTransformAutomation(objectID: UUID, transform: VisionSpatialTransform) {
        let beat = playheadBeat
        let values: [(String, Float)] = [
            ("position.x", Float(max(0, min(1, (transform.position.x + 2) / 4)))),
            ("position.y", Float(max(0, min(1, (transform.position.y + 2) / 4)))),
            ("position.z", Float(max(0, min(1, (transform.position.z + 2) / 4))))
        ]
        for (parameterID, value) in values { automationParity.captureGesture(backendID: "visionSpatial", instanceID: objectID.uuidString, parameterID: parameterID, beat: beat, normalizedValue: value) }
    }

    func beginSpatialPerformanceGesture(_ gesture: VisionSpatialAutomationGesture) { automationParity.beginSpatialGesture(gesture) }
    func endSpatialPerformanceGesture(_ gesture: VisionSpatialAutomationGesture) { automationParity.endSpatialGesture(gesture) }
    func performSpatialAutomationGesture(_ gesture: VisionSpatialAutomationGesture, normalizedValue: Float) {
        automationParity.captureSpatialGesture(gesture, beat: playheadBeat, normalizedValue: normalizedValue) { [weak self] lane, value in
            self?.applyAutomationValue(value, to: lane)
        }
    }

    private func applyAutomationValue(_ value: Float, to lane: VisionAutomationLane) {
        switch lane.address.backendID {
        case "visionProject":
            if lane.address.parameterID == "tempo" {
                let bpm = 20.0 + Double(value) * 380.0
                project.bpm = bpm
                project.tempo = bpm
            }
        case "visionMixer":
            guard let trackID = UUID(uuidString: lane.address.instanceID), let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
            if lane.address.parameterID == "volume" { project.tracks[index].volume = value }
            if lane.address.parameterID == "pan" { project.tracks[index].pan = value * 2 - 1 }
        case "visionTrackStockFX":
            let components = lane.address.instanceID.components(separatedBy: "::")
            guard components.count == 2,
                  let trackID = UUID(uuidString: components[0]),
                  let effect = VisionStockFXKind(rawValue: components[1]) else { return }
            guard let runtimeTrackID = project.tracks.first(where: { ($0.automationID ?? $0.id) == trackID })?.id else { return }
            setTrackStockFXParameter(trackID: runtimeTrackID, effect: effect, parameterID: lane.address.parameterID, normalizedValue: value)
        case "macCompanion": desktopBridge.setParameter(id: lane.address.parameterID, normalizedValue: Double(value))
        case "visionSpatial":
            guard let objectID = UUID(uuidString: lane.address.instanceID), let objectIndex = project.spatialScene?.objects.firstIndex(where: { $0.id == objectID }) else { return }
            let v = automationParity.denormalizeSpatial(value)
            if lane.address.parameterID == "position.x" { project.spatialScene?.objects[objectIndex].transform.position.x = v }
            if lane.address.parameterID == "position.y" { project.spatialScene?.objects[objectIndex].transform.position.y = v }
            if lane.address.parameterID == "position.z" { project.spatialScene?.objects[objectIndex].transform.position.z = v }
        default: break
        }
    }

    func applyAutomation(at beat: Double) {
        for lane in automationParity.lanes where lane.visible || lane.armed {
            guard let value = automationParity.value(for: lane, at: beat) else { continue }
            applyAutomationValue(value, to: lane)
        }
    }
}


extension VisionStudioModel {
    func ensureTrackStockFXDefaults() {
        for index in project.tracks.indices {
            if project.tracks[index].stockFXRack == nil { project.tracks[index].stockFXRack = .defaults }
            if project.tracks[index].automationID == nil { project.tracks[index].automationID = project.tracks[index].id }
        }
    }

    func trackStockFXValue(trackID: UUID, effect: VisionStockFXKind, parameterID: String) -> Float {
        guard let track = project.tracks.first(where: { $0.id == trackID }) else {
            return VisionStockFXRackState.defaults.value(effect: effect, parameterID: parameterID)
        }
        return (track.stockFXRack ?? .defaults).value(effect: effect, parameterID: parameterID)
    }

    func setTrackStockFXParameter(trackID: UUID, effect: VisionStockFXKind, parameterID: String, normalizedValue: Float) {
        ensureTrackStockFXDefaults()
        guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let value = max(0, min(1, normalizedValue))
        project.tracks[index].stockFXRack?.values["\(effect.rawValue).\(parameterID)"] = value
        audioEngine.setTrackStockFXParameter(trackIndex: index, effect: effect, parameterID: parameterID, normalizedValue: value)
    }

    func syncTrackStockFXRacksToAudioEngine() {
        ensureTrackStockFXDefaults()
        for (index, track) in project.tracks.enumerated() {
            let rack = track.stockFXRack ?? .defaults
            for parameter in VisionStockFXParameterRegistry.all {
                audioEngine.setTrackStockFXParameter(
                    trackIndex: index,
                    effect: parameter.effect,
                    parameterID: parameter.parameterID,
                    normalizedValue: rack.value(effect: parameter.effect, parameterID: parameter.parameterID)
                )
            }
        }
    }
}
