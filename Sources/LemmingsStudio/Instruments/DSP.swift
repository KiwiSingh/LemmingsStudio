import Foundation

// MARK: - Oscillator

public enum Waveform: String, CaseIterable, Identifiable {
    case sine, triangle, saw, square
    public var id: String { rawValue }
}

/// Band-limited oscillator using PolyBLEP for saw/square edges.
public struct Oscillator {
    public var waveform: Waveform = .saw
    private var phase: Double = 0
    private var sampleRate: Double

    public init(sampleRate: Double) { self.sampleRate = sampleRate }
    public mutating func reset() { phase = 0 }

    @inline(__always)
    private func polyBlep(_ t: Double, _ dt: Double) -> Double {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1.0
        } else if t > 1.0 - dt {
            let x = (t - 1.0) / dt
            return x * x + x + x + 1.0
        }
        return 0
    }

    public mutating func next(frequency: Double) -> Float {
        let dt = frequency / sampleRate
        var value: Double
        switch waveform {
        case .sine:
            value = sin(2.0 * .pi * phase)
        case .triangle:
            // integrate a square; cheap approximation that stays band-friendly
            value = 2.0 * abs(2.0 * (phase - floor(phase + 0.5))) - 1.0
        case .saw:
            value = 2.0 * phase - 1.0
            value -= polyBlep(phase, dt)
        case .square:
            value = phase < 0.5 ? 1.0 : -1.0
            value += polyBlep(phase, dt)
            let t2 = phase + 0.5 - floor(phase + 0.5)
            value -= polyBlep(t2, dt)
        }
        phase += dt
        if phase >= 1.0 { phase -= 1.0 }
        return Float(value)
    }
}

// MARK: - ADSR envelope

public struct ADSR {
    public var attack: Double  = 0.005   // seconds
    public var decay: Double   = 0.12
    public var sustain: Double = 0.7     // 0...1
    public var release: Double = 0.25

    private enum Stage { case idle, attack, decay, sustain, release }
    private var stage: Stage = .idle
    private var level: Double = 0
    private let sampleRate: Double

    public init(sampleRate: Double) { self.sampleRate = sampleRate }

    public var isActive: Bool { stage != .idle }

    public mutating func gateOn()  { stage = .attack }
    public mutating func gateOff() { if stage != .idle { stage = .release } }

    public mutating func next() -> Float {
        switch stage {
        case .idle:
            level = 0
        case .attack:
            level += 1.0 / max(attack * sampleRate, 1)
            if level >= 1.0 { level = 1.0; stage = .decay }
        case .decay:
            level -= (1.0 - sustain) / max(decay * sampleRate, 1)
            if level <= sustain { level = sustain; stage = .sustain }
        case .sustain:
            level = sustain
        case .release:
            level -= sustain / max(release * sampleRate, 1)
            if level <= 0 { level = 0; stage = .idle }
        }
        return Float(level)
    }
}

// MARK: - State-variable filter (TPT, Cytomic-style)

public enum FilterMode { case lowpass, highpass, bandpass }

public struct SVFilter {
    public var cutoff: Double = 1200    // Hz
    public var resonance: Double = 0.3  // 0...1
    public var mode: FilterMode = .lowpass

    private var ic1eq: Double = 0
    private var ic2eq: Double = 0
    private let sampleRate: Double

    public init(sampleRate: Double) { self.sampleRate = sampleRate }
    public mutating func reset() { ic1eq = 0; ic2eq = 0 }

    public mutating func process(_ input: Float) -> Float {
        let fc = min(max(cutoff, 20), sampleRate * 0.45)
        let g = tan(.pi * fc / sampleRate)
        let k = 2.0 - 1.98 * min(max(resonance, 0), 1)   // higher resonance -> lower k
        let a1 = 1.0 / (1.0 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2

        let v0 = Double(input)
        let v3 = v0 - ic2eq
        let v1 = a1 * ic1eq + a2 * v3
        let v2 = ic2eq + a2 * ic1eq + a3 * v3
        ic1eq = 2.0 * v1 - ic1eq
        ic2eq = 2.0 * v2 - ic2eq

        switch mode {
        case .lowpass:  return Float(v2)
        case .bandpass: return Float(v1)
        case .highpass: return Float(v0 - k * v1 - v2)
        }
    }
}

// MARK: - Karplus-Strong (plucked string -> guitar)

public final class KarplusStrong {
    private var buffer: [Float]
    private var index = 0
    private var length: Int
    private let sampleRate: Double
    public var damping: Float = 0.996   // sustain/brightness
    private var active = false

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.length = 64
        self.buffer = [Float](repeating: 0, count: max(1, length))
    }

    public func pluck(frequency: Double, velocity: Float = 1.0) {
        length = max(2, Int(sampleRate / max(frequency, 1)))
        buffer = (0..<length).map { _ in Float.random(in: -1...1) * velocity }
        index = 0
        active = true
    }

    public func stop() { damping = 0.90 }   // quick decay on note-off

    public func next() -> Float {
        guard active else { return 0 }
        let current = buffer[index]
        let nextIndex = (index + 1) % length
        let averaged = damping * 0.5 * (current + buffer[nextIndex])
        buffer[index] = averaged
        index = nextIndex
        if abs(averaged) < 1e-5 { active = false }
        return current
    }

    public var isActive: Bool { active }
}
