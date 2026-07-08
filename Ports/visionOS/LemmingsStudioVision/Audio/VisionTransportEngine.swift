import Foundation

final class VisionTransportEngine: @unchecked Sendable {
    private var timer: DispatchSourceTimer?
    private var tempo: Double = 124
    private var beat: Double = 0
    private var lastTick = ContinuousClock.now
    private var callback: (@Sendable (Double) -> Void)?

    func start(tempo: Double, fromBeat: Double, onBeat: @escaping @Sendable (Double) -> Void) {
        stopTimerOnly()
        self.tempo = max(20, tempo)
        beat = max(0, fromBeat)
        callback = onBeat
        lastTick = .now

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(16), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    func pause() { stopTimerOnly() }

    func stop() {
        stopTimerOnly()
        beat = 0
    }

    func seek(to beat: Double) {
        self.beat = max(0, beat)
        lastTick = .now
    }

    private func tick() {
        let now = ContinuousClock.now
        let elapsed = lastTick.duration(to: now)
        lastTick = now
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        beat += seconds * tempo / 60.0
        callback?(beat)
    }

    private func stopTimerOnly() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}
