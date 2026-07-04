import Foundation

// MARK: - Tempo automation
//
// A piecewise-linear tempo curve over beats. The audio thread can't afford to
// integrate a varying tempo per sample, so we precompute a dense time→beat table
// once (on edit) and the transport does a cheap lookup + interpolation.

public struct TempoPoint: Hashable, Sendable {
    public var beat: Double
    public var bpm: Double
    public init(beat: Double, bpm: Double) { self.beat = beat; self.bpm = bpm }
}

public final class TempoMap {
    public private(set) var points: [TempoPoint]
    public private(set) var lengthBeats: Double

    // Precomputed table: cumulative seconds at each beat grid step.
    private var beatGrid: [Double] = []      // beats (uniform)
    private var secAtBeat: [Double] = []     // seconds elapsed at that beat
    private let step = 0.0625                 // 1/16-beat resolution

    public init(points: [TempoPoint], lengthBeats: Double) {
        self.points = points.sorted { $0.beat < $1.beat }
        self.lengthBeats = max(lengthBeats, 1)
        rebuild()
    }

    public func setPoints(_ p: [TempoPoint], lengthBeats: Double) {
        points = p.sorted { $0.beat < $1.beat }
        self.lengthBeats = max(lengthBeats, 1)
        rebuild()
    }

    /// Tempo (bpm) at a given beat (linear between points).
    public func bpm(atBeat beat: Double) -> Double {
        guard let first = points.first else { return 120 }
        if beat <= first.beat { return first.bpm }
        guard let last = points.last else { return 120 }
        if beat >= last.beat { return last.bpm }
        for i in 1..<points.count {
            let a = points[i-1], b = points[i]
            if beat >= a.beat && beat <= b.beat {
                let span = b.beat - a.beat
                let t = span > 0 ? (beat - a.beat) / span : 0
                return a.bpm + (b.bpm - a.bpm) * t
            }
        }
        return last.bpm
    }

    private func rebuild() {
        beatGrid.removeAll(); secAtBeat.removeAll()
        var sec = 0.0
        var beat = 0.0
        beatGrid.append(0); secAtBeat.append(0)
        while beat < lengthBeats {
            let bpmMid = bpm(atBeat: beat + step / 2)
            sec += (60.0 / max(bpmMid, 1)) * step
            beat += step
            beatGrid.append(beat); secAtBeat.append(sec)
        }
    }

    /// Map elapsed seconds → beat (inverse of the table). Binary search + lerp.
    public func beat(atSeconds seconds: Double) -> Double {
        guard let lastSec = secAtBeat.last, seconds > 0 else { return 0 }
        if seconds >= lastSec {
            // extrapolate at the final tempo
            let tailBpm = points.last?.bpm ?? 120
            return (beatGrid.last ?? 0) + (seconds - lastSec) * tailBpm / 60.0
        }
        var lo = 0, hi = secAtBeat.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if secAtBeat[mid] <= seconds { lo = mid } else { hi = mid }
        }
        let s0 = secAtBeat[lo], s1 = secAtBeat[hi]
        let t = s1 > s0 ? (seconds - s0) / (s1 - s0) : 0
        return beatGrid[lo] + (beatGrid[hi] - beatGrid[lo]) * t
    }
}
