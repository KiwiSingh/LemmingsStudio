import Foundation

struct VisionSpatialVec3: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = VisionSpatialVec3(x: 0, y: 0, z: 0)
    static let one = VisionSpatialVec3(x: 1, y: 1, z: 1)
}

struct VisionSpatialTransform: Codable, Hashable, Sendable {
    var position: VisionSpatialVec3
    var rotationDegrees: VisionSpatialVec3
    var scale: VisionSpatialVec3

    static let identity = VisionSpatialTransform(position: .zero, rotationDegrees: .zero, scale: .one)

    mutating func quantize(positionStep: Double, rotationStep: Double, scaleStep: Double) {
        position.x = Self.snapped(position.x, step: positionStep)
        position.y = Self.snapped(position.y, step: positionStep)
        position.z = Self.snapped(position.z, step: positionStep)
        rotationDegrees.x = Self.snapped(rotationDegrees.x, step: rotationStep)
        rotationDegrees.y = Self.snapped(rotationDegrees.y, step: rotationStep)
        rotationDegrees.z = Self.snapped(rotationDegrees.z, step: rotationStep)
        scale.x = max(0.15, Self.snapped(scale.x, step: scaleStep))
        scale.y = max(0.15, Self.snapped(scale.y, step: scaleStep))
        scale.z = max(0.15, Self.snapped(scale.z, step: scaleStep))
    }

    private static func snapped(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }
}

enum VisionSpatialObjectKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case arrangement
    case mixer
    case pluginRack
    case pianoRoll
    case stepSequencer
    case inspector
    case bridge
    case agentPanel
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arrangement: return "Arrangement"
        case .mixer: return "Mixer"
        case .pluginRack: return "Plug-in Rack"
        case .pianoRoll: return "Piano Roll"
        case .stepSequencer: return "Step Sequencer"
        case .inspector: return "Inspector"
        case .bridge: return "Desktop Bridge"
        case .agentPanel: return "Agent Panel"
        case .custom: return "Custom Surface"
        }
    }

    var systemImage: String {
        switch self {
        case .arrangement: return "timeline.selection"
        case .mixer: return "slider.horizontal.3"
        case .pluginRack: return "puzzlepiece.extension"
        case .pianoRoll: return "pianokeys"
        case .stepSequencer: return "square.grid.4x3.fill"
        case .inspector: return "sidebar.right"
        case .bridge: return "desktopcomputer.and.arrow.down"
        case .agentPanel: return "brain.head.profile"
        case .custom: return "cube"
        }
    }
}

struct VisionSpatialObject: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var kind: VisionSpatialObjectKind
    var linkedID: UUID?
    var transform: VisionSpatialTransform
    var isLocked: Bool
    var isVisible: Bool

    init(id: UUID = UUID(), name: String, kind: VisionSpatialObjectKind, linkedID: UUID? = nil, transform: VisionSpatialTransform = .identity, isLocked: Bool = false, isVisible: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.linkedID = linkedID
        self.transform = transform
        self.isLocked = isLocked
        self.isVisible = isVisible
    }
}

struct VisionSpatialScene: Codable, Sendable {
    var objects: [VisionSpatialObject]
    var snapPositionStep: Double
    var snapRotationStep: Double
    var snapScaleStep: Double

    static let `default` = VisionSpatialScene(
        objects: [
            .init(name: "Arrangement", kind: .arrangement, transform: .init(position: .init(x: 0, y: 0, z: -1.2), rotationDegrees: .zero, scale: .one)),
            .init(name: "Mixer", kind: .mixer, transform: .init(position: .init(x: 0.8, y: -0.15, z: -0.95), rotationDegrees: .init(x: 0, y: -18, z: 0), scale: .init(x: 0.82, y: 0.82, z: 0.82))),
            .init(name: "Plug-in Rack", kind: .pluginRack, transform: .init(position: .init(x: -0.8, y: -0.08, z: -0.95), rotationDegrees: .init(x: 0, y: 18, z: 0), scale: .init(x: 0.82, y: 0.82, z: 0.82))),
            .init(name: "Agent Panel", kind: .agentPanel, transform: .init(position: .init(x: 0, y: 0.45, z: -0.85), rotationDegrees: .zero, scale: .init(x: 0.72, y: 0.72, z: 0.72)))
        ],
        snapPositionStep: 0.05,
        snapRotationStep: 5,
        snapScaleStep: 0.05
    )
}

struct VisionSpatialUndoRecord: Identifiable, Hashable, Sendable {
    var id = UUID()
    var objectID: UUID
    var before: VisionSpatialTransform
    var after: VisionSpatialTransform
    var label: String
}
