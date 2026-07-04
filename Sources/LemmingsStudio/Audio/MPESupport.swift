import Foundation

public enum MPEMode: String, CaseIterable, Identifiable, Sendable {
    case off = "Off"
    case singleChannel = "Pitch Bend"
    case lowerZone = "MPE Lower Zone"
    case upperZone = "MPE Upper Zone"

    public var id: String { rawValue }
    public var isMPE: Bool { self == .lowerZone || self == .upperZone }
}

public struct MPEZoneSettings: Hashable, Sendable {
    public var mode: MPEMode
    public var bendRangeSemitones: Int
    public var masterChannel: Int
    public var memberChannelStart: Int
    public var memberChannelEnd: Int
    public var mapCC74ToTimbre: Bool
    public var pressureEnabled: Bool

    public init(mode: MPEMode = .singleChannel,
                bendRangeSemitones: Int = 48,
                masterChannel: Int = 0,
                memberChannelStart: Int = 1,
                memberChannelEnd: Int = 15,
                mapCC74ToTimbre: Bool = true,
                pressureEnabled: Bool = true) {
        self.mode = mode
        self.bendRangeSemitones = bendRangeSemitones
        self.masterChannel = masterChannel
        self.memberChannelStart = memberChannelStart
        self.memberChannelEnd = memberChannelEnd
        self.mapCC74ToTimbre = mapCC74ToTimbre
        self.pressureEnabled = pressureEnabled
    }

    public func accepts(channel: Int) -> Bool {
        switch mode {
        case .off, .singleChannel:
            return true
        case .lowerZone, .upperZone:
            return channel >= memberChannelStart && channel <= memberChannelEnd
        }
    }

    public func displayChannel(_ zeroBased: Int) -> Int { zeroBased + 1 }
}
