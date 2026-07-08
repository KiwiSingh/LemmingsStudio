import Foundation

enum VisionStockFXKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case lemmingsFilter = "LemmingsFilter"
    case lemmingCrusher = "LemmingCrusher"
    case burrowDelay = "BurrowDelay"
    case lemmingVerb = "LemmingVerb"
    case lemmingDrive = "LemmingDrive"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .lemmingsFilter: return "line.3.horizontal.decrease.circle"
        case .lemmingCrusher: return "waveform.path.ecg.rectangle"
        case .burrowDelay: return "repeat.circle"
        case .lemmingVerb: return "water.waves"
        case .lemmingDrive: return "flame.fill"
        }
    }
}

struct VisionStockFXParameterDefinition: Identifiable, Hashable, Sendable {
    let effect: VisionStockFXKind
    let parameterID: String
    let name: String
    let unit: String
    let defaultValue: Float
    var id: String { "\(effect.rawValue).\(parameterID)" }
}

enum VisionStockFXParameterRegistry {
    static let all: [VisionStockFXParameterDefinition] = [
        .init(effect: .lemmingsFilter, parameterID: "cutoff", name: "Cutoff", unit: "Hz", defaultValue: 1.0),
        .init(effect: .lemmingsFilter, parameterID: "resonance", name: "Resonance", unit: "%", defaultValue: 0.0),
        .init(effect: .lemmingCrusher, parameterID: "crush", name: "Crush", unit: "%", defaultValue: 0.0),
        .init(effect: .lemmingCrusher, parameterID: "mix", name: "Mix", unit: "%", defaultValue: 0.0),
        .init(effect: .burrowDelay, parameterID: "time", name: "Time", unit: "s", defaultValue: 0.18),
        .init(effect: .burrowDelay, parameterID: "feedback", name: "Feedback", unit: "%", defaultValue: 0.20),
        .init(effect: .burrowDelay, parameterID: "mix", name: "Mix", unit: "%", defaultValue: 0.0),
        .init(effect: .lemmingVerb, parameterID: "mix", name: "Wet", unit: "%", defaultValue: 0.0),
        .init(effect: .lemmingDrive, parameterID: "drive", name: "Drive", unit: "dB", defaultValue: 0.0),
        .init(effect: .lemmingDrive, parameterID: "mix", name: "Mix", unit: "%", defaultValue: 0.0)
    ]

    static func parameters(for effect: VisionStockFXKind) -> [VisionStockFXParameterDefinition] {
        all.filter { $0.effect == effect }
    }

    static func definition(effectID: String, parameterID: String) -> VisionStockFXParameterDefinition? {
        all.first { $0.effect.rawValue == effectID && $0.parameterID == parameterID }
    }
}

struct VisionStockFXRackState: Codable, Sendable {
    var values: [String: Float]
    var enabledEffects: Set<VisionStockFXKind>

    static var defaults: VisionStockFXRackState {
        var values: [String: Float] = [:]
        for parameter in VisionStockFXParameterRegistry.all { values[parameter.id] = parameter.defaultValue }
        return .init(values: values, enabledEffects: Set(VisionStockFXKind.allCases))
    }

    func value(effect: VisionStockFXKind, parameterID: String) -> Float {
        values["\(effect.rawValue).\(parameterID)"] ?? VisionStockFXParameterRegistry.definition(effectID: effect.rawValue, parameterID: parameterID)?.defaultValue ?? 0
    }
}
