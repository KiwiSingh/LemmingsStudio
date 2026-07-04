import Foundation

// MARK: - Warp modes
//
// Ableton-style time-stretch of audio clips to the project tempo. These are real
// algorithms (OLA + phase vocoder with optional phase-locking), tuned to be
// musical but not claimed to match Ableton/élastique quality. Warping is computed
// offline (on tempo/warp change) and cached on the clip, so the audio thread just
// plays a pre-stretched buffer.

public enum WarpMode: String, CaseIterable, Identifiable, Sendable {
    case beat = "Beat"             // OLA — punchy, great for drums/rhythmic loops
    case complex = "Complex"       // phase vocoder — good for full mixes/pads
    case complexPro = "Complex Pro" // phase-locked vocoder — fewer artifacts
    public var id: String { rawValue }
}

public enum WarpEngine {
    /// Recompute a clip's warped buffer for the given project tempo.
    public static func warp(_ clip: AudioClip, projectTempo: Double) {
        guard clip.warpEnabled, clip.originalTempo > 0 else { clip.warpedSamples = nil; return }
        let ratio = clip.originalTempo / projectTempo      // output length / input length
        if abs(ratio - 1) < 1e-3 { clip.warpedSamples = clip.samples; return }
        clip.warpedSamples = stretch(clip.samples, ratio: ratio, mode: clip.warpMode)
    }

    public static func stretch(_ input: [Float], ratio: Double, mode: WarpMode) -> [Float] {
        guard input.count > 4096, ratio > 0 else { return input }
        switch mode {
        case .beat:       return ola(input, ratio: ratio)
        case .complex:    return phaseVocoder(input, ratio: ratio, locked: false)
        case .complexPro: return phaseVocoder(input, ratio: ratio, locked: true)
        }
    }

    // MARK: OLA (overlap-add granular)

    private static func ola(_ x: [Float], ratio: Double) -> [Float] {
        let frame = 2048, analysisHop = 512
        let synthHop = max(1, Int(Double(analysisHop) * ratio))
        let win = hann(frame)
        let outLen = Int(Double(x.count) * ratio) + frame
        var out = [Float](repeating: 0, count: outLen)
        var norm = [Float](repeating: 0, count: outLen)
        var aPos = 0, sPos = 0
        while aPos + frame < x.count {
            for i in 0..<frame {
                let w = win[i]
                out[sPos + i] += x[aPos + i] * w
                norm[sPos + i] += w
            }
            aPos += analysisHop; sPos += synthHop
        }
        for i in 0..<outLen where norm[i] > 1e-6 { out[i] /= norm[i] }
        return out
    }

    // MARK: Phase vocoder

    private static func phaseVocoder(_ x: [Float], ratio: Double, locked: Bool) -> [Float] {
        let N = 2048, hopA = 512
        let hopS = max(1, Int(Double(hopA) * ratio))
        let win = hann(N)
        let bins = N / 2 + 1
        let outLen = Int(Double(x.count) * ratio) + N
        var out = [Float](repeating: 0, count: outLen)
        var norm = [Float](repeating: 0, count: outLen)

        var lastPhase = [Double](repeating: 0, count: bins)
        var sumPhase = [Double](repeating: 0, count: bins)
        let expct = (2.0 * .pi * Double(hopA)) / Double(N)

        var re = [Double](repeating: 0, count: N)
        var im = [Double](repeating: 0, count: N)

        var aPos = 0, sPos = 0
        while aPos + N <= x.count {
            for i in 0..<N { re[i] = Double(x[aPos + i]) * Double(win[i]); im[i] = 0 }
            fft(&re, &im, inverse: false)

            var mag = [Double](repeating: 0, count: bins)
            var freq = [Double](repeating: 0, count: bins)
            for k in 0..<bins {
                let m = sqrt(re[k]*re[k] + im[k]*im[k])
                let phase = atan2(im[k], re[k])
                var delta = phase - lastPhase[k]
                lastPhase[k] = phase
                delta -= Double(k) * expct
                delta = wrap(delta)
                let trueFreq = Double(k) * expct + delta
                mag[k] = m; freq[k] = trueFreq
            }

            if locked { phaseLock(&freq, mag: mag) }

            for k in 0..<bins {
                sumPhase[k] += freq[k] * Double(hopS) / Double(hopA)
                let p = sumPhase[k]
                re[k] = mag[k] * cos(p); im[k] = mag[k] * sin(p)
            }
            // hermitian mirror
            for k in 1..<(N/2) { re[N - k] = re[k]; im[N - k] = -im[k] }
            fft(&re, &im, inverse: true)
            for i in 0..<N {
                let w = Double(win[i])
                out[sPos + i] += Float(re[i] / Double(N) * w)
                norm[sPos + i] += Float(w * w)
            }
            aPos += hopA; sPos += hopS
        }
        for i in 0..<outLen where norm[i] > 1e-6 { out[i] /= norm[i] }
        return out
    }

    /// Identity phase locking: snap each region around a spectral peak to the
    /// peak bin's frequency so partials stay phase-coherent (less "phasiness").
    private static func phaseLock(_ freq: inout [Double], mag: [Double]) {
        let bins = mag.count
        var k = 1
        while k < bins - 1 {
            if mag[k] > mag[k-1] && mag[k] >= mag[k+1] {
                var lo = k - 1; while lo > 0 && mag[lo] >= mag[lo-1] { lo -= 1 }
                var hi = k + 1; while hi < bins - 1 && mag[hi] >= mag[hi+1] { hi += 1 }
                for j in lo...min(hi, bins - 1) { freq[j] = freq[k] }
                k = hi + 1
            } else { k += 1 }
        }
    }

    // MARK: helpers

    private static func hann(_ n: Int) -> [Float] {
        (0..<n).map { 0.5 - 0.5 * Float(cos(2 * .pi * Double($0) / Double(n - 1))) }
    }
    @inline(__always) private static func wrap(_ x: Double) -> Double {
        var p = x
        while p > .pi { p -= 2 * .pi }
        while p < -(.pi) { p += 2 * .pi }
        return p
    }

    /// In-place iterative radix-2 Cooley–Tukey FFT (N must be a power of two).
    private static func fft(_ re: inout [Double], _ im: inout [Double], inverse: Bool) {
        let n = re.count
        var j = 0
        for i in 0..<n - 1 {
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
            var m = n >> 1
            while m >= 1 && j >= m { j -= m; m >>= 1 }
            j += m
        }
        var len = 2
        while len <= n {
            let ang = (inverse ? 2.0 : -2.0) * .pi / Double(len)
            let wlenRe = cos(ang), wlenIm = sin(ang)
            var i = 0
            while i < n {
                var wRe = 1.0, wIm = 0.0
                for k in 0..<(len / 2) {
                    let uRe = re[i + k], uIm = im[i + k]
                    let vRe = re[i + k + len/2] * wRe - im[i + k + len/2] * wIm
                    let vIm = re[i + k + len/2] * wIm + im[i + k + len/2] * wRe
                    re[i + k] = uRe + vRe; im[i + k] = uIm + vIm
                    re[i + k + len/2] = uRe - vRe; im[i + k + len/2] = uIm - vIm
                    let nwRe = wRe * wlenRe - wIm * wlenIm
                    wIm = wRe * wlenIm + wIm * wlenRe; wRe = nwRe
                }
                i += len
            }
            len <<= 1
        }
    }
}
