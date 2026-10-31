import AVFoundation
import AudioToolbox

/// Host-owned musical time, supplied before each audio render, never wall time.
final class HostedMusicalClock {
    var bpm = 120.0, beat = 0.0, sampleRate = 44100.0
    var playing = false
    var timelineSeconds = 0.0
    func install(on unit: AUAudioUnit, sampleRate: Double) {
        self.sampleRate = sampleRate
        unit.musicalContextBlock = { [weak self] tempo, numerator, denominator, position, nextBeat, downbeat in
            guard let self else { return false }
            tempo?.pointee = self.bpm; numerator?.pointee = 4; denominator?.pointee = 4
            position?.pointee = self.beat
            nextBeat?.pointee = Int(((ceil(self.beat) - self.beat) * 60 / max(20,self.bpm) * self.sampleRate).rounded())
            downbeat?.pointee = floor(self.beat / 4) * 4
            return true
        }
        unit.transportStateBlock = { [weak self] flags, samplePosition, cycleStart, cycleEnd in
            guard let self else { return false }
            flags?.pointee = AUHostTransportStateFlags(rawValue: self.playing ? 2 : 0)
            samplePosition?.pointee = self.timelineSeconds * self.sampleRate
            cycleStart?.pointee = 0; cycleEnd?.pointee = 0
            return true
        }
    }
    func update(bpm: Double, beat: Double, playing: Bool, timelineSeconds: Double? = nil) { self.bpm = bpm; self.beat = beat; self.playing = playing; self.timelineSeconds = timelineSeconds ?? beat * 60 / max(20,bpm) }
}
