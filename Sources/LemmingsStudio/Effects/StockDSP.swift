import Foundation

// MARK: - Practical stock-device DSP tier
// These are intentionally original implementations with generic DAW behaviour.
// They are not emulations of any vendor device, but they make the stock-device
// registry audible/useful instead of transparent placeholders.

@inline(__always) private func lclamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(x, lo), hi) }
@inline(__always) private func fclamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float { Swift.min(Swift.max(x, lo), hi) }
@inline(__always) private func fsign(_ x: Float) -> Float { x > 0 ? 1 : (x < 0 ? -1 : 0) }
@inline(__always) private func dbToGain(_ db: Double) -> Float { Float(pow(10.0, db / 20.0)) }

// MARK: Time alignment / utility

public final class AlignDelayEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.alignDelay
    public var bypassed = false
    private var sr = 44100.0
    private var bufL = [Float](repeating: 0, count: 65536)
    private var bufR = [Float](repeating: 0, count: 65536)
    private var idx = 0
    public var delayMS = 0.0
    public var polarity = 0.0
    public init() {}
    func setSampleRate(_ s: Double) { sr = s; let c = max(1024, Int(sr * 0.25)); bufL = .init(repeating:0,count:c); bufR = .init(repeating:0,count:c) }
    public func reset() { bufL = .init(repeating:0,count:bufL.count); bufR = .init(repeating:0,count:bufR.count); idx = 0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let d = min(bufL.count - 1, max(0, Int(delayMS * 0.001 * sr)))
        let inv: Float = polarity >= 0.5 ? -1 : 1
        for i in 0..<frames {
            bufL[idx] = left[i]; bufR[idx] = right[i]
            let r = (idx - d + bufL.count) % bufL.count
            left[i] = bufL[r] * inv; right[i] = bufR[r] * inv
            idx = (idx + 1) % bufL.count
        }
    }
    public var automatableParams: [ParamInfo] { [ParamInfo("delay", "Delay", 0, 20, unit: "ms"), ParamInfo("polarity", "Polarity", 0, 1)] }
    public func setParam(_ id: String, _ v: Double) { if id == "delay" { delayMS = v }; if id == "polarity" { polarity = v } }
    public func getParam(_ id: String) -> Double { id == "delay" ? delayMS : (id == "polarity" ? polarity : 0) }
}

public final class UtilityEffect: AudioEffect {
    public let kind = DeviceKind.utility
    public var bypassed = false
    public var gainDB = 0.0, width = 1.0, balance = 0.0, mono = 0.0
    public var invertLeft = 0.0, invertRight = 0.0, swap = 0.0
    public init() {}
    public func reset() {}
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let g = dbToGain(gainDB)
        let w = Float(width)
        let bal = Float(balance)
        let makeMono = mono >= 0.5
        let invL: Float = invertLeft >= 0.5 ? -1 : 1
        let invR: Float = invertRight >= 0.5 ? -1 : 1
        let doSwap = swap >= 0.5
        for i in 0..<frames {
            var l = left[i], r = right[i]
            if doSwap { Swift.swap(&l, &r) }
            let mid = (l + r) * 0.5
            let side = (l - r) * 0.5 * w
            l = mid + side; r = mid - side
            if makeMono { l = mid; r = mid }
            let lg: Float = bal > 0 ? 1 - bal : 1
            let rg: Float = bal < 0 ? 1 + bal : 1
            left[i] = l * g * lg * invL
            right[i] = r * g * rg * invR
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("gain","Gain",-36,36,unit:"dB"),
         ParamInfo("width","Width",0,2),
         ParamInfo("balance","Balance",-1,1),
         ParamInfo("mono","Mono",0,1),
         ParamInfo("invertL","Invert L",0,1),
         ParamInfo("invertR","Invert R",0,1),
         ParamInfo("swap","Swap L/R",0,1)]
    }
    public func setParam(_ id: String, _ v: Double) {
        switch id {
        case "gain": gainDB=v
        case "width": width=v
        case "balance": balance=v
        case "mono": mono=v
        case "invertL": invertLeft=v
        case "invertR": invertRight=v
        case "swap": swap=v
        default: break
        }
    }
    public func getParam(_ id: String) -> Double {
        switch id {
        case "gain": return gainDB
        case "width": return width
        case "balance": return balance
        case "mono": return mono
        case "invertL": return invertLeft
        case "invertR": return invertRight
        case "swap": return swap
        default: return 0
        }
    }
}

// MARK: Saturation / amp family

public final class SaturatorEffect: AudioEffect {
    public let kind: DeviceKind
    public var bypassed = false
    public var driveDB = 6.0, tone = 0.5, mix = 1.0, outputDB = 0.0
    private var lpL: Float = 0, lpR: Float = 0
    public init(kind: DeviceKind = .saturator, drive: Double = 6.0) { self.kind = kind; self.driveDB = drive }
    public func reset() { lpL = 0; lpR = 0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let drive = dbToGain(driveDB), out = dbToGain(outputDB), wet = Float(mix), dry = 1 - Float(mix)
        let a = Float(lclamp(tone, 0, 1))
        for i in 0..<frames {
            let dl = left[i], dr = right[i]
            var wl = tanh(dl * drive), wr = tanh(dr * drive)
            lpL += (wl - lpL) * (0.03 + 0.35 * a); lpR += (wr - lpR) * (0.03 + 0.35 * a)
            wl = lpL + (wl - lpL) * (0.25 + 1.5 * a)
            wr = lpR + (wr - lpR) * (0.25 + 1.5 * a)
            left[i] = (dl * dry + wl * wet) * out
            right[i] = (dr * dry + wr * wet) * out
        }
    }
    public var automatableParams: [ParamInfo] { [ParamInfo("drive","Drive",0,36,unit:"dB"), ParamInfo("tone","Tone",0,1), ParamInfo("mix","Dry/Wet",0,1), ParamInfo("output","Output",-24,12,unit:"dB")] }
    public func setParam(_ id: String, _ v: Double) { switch id { case "drive": driveDB=v; case "tone": tone=v; case "mix": mix=v; case "output": outputDB=v; default: break } }
    public func getParam(_ id: String) -> Double { switch id { case "drive": return driveDB; case "tone": return tone; case "mix": return mix; case "output": return outputDB; default: return 0 } }
}

public final class CabinetEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.cabinet
    public var bypassed = false
    private var sr = 44100.0
    private var hpL = Biquad(), hpR = Biquad(), lpL = Biquad(), lpR = Biquad(), midL = Biquad(), midR = Biquad()
    public var size = 0.5, character = 0.5, mix = 1.0
    public init() { recompute() }
    func setSampleRate(_ s: Double) { sr = s; recompute() }
    private func recompute() {
        hpL.update(kind:.highpass,freq:70+size*120,q:0.7,gainDB:0,sr:sr); hpR=hpL
        lpL.update(kind:.lowpass,freq:3200+size*4500,q:0.8,gainDB:0,sr:sr); lpR=lpL
        midL.update(kind:.peaking,freq:650+character*1700,q:0.9,gainDB:2+character*5,sr:sr); midR=midL
    }
    public func reset() { hpL.reset(); hpR.reset(); lpL.reset(); lpR.reset(); midL.reset(); midR.reset() }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }; recompute(); let wet = Float(mix), dry = 1-wet
        for i in 0..<frames { let l=left[i], r=right[i]; var wl=hpL.process(Double(l)); wl=midL.process(wl); wl=lpL.process(wl); var wr=hpR.process(Double(r)); wr=midR.process(wr); wr=lpR.process(wr); left[i]=l*dry+Float(wl)*wet; right[i]=r*dry+Float(wr)*wet }
    }
    public var automatableParams: [ParamInfo] { [ParamInfo("size","Size",0,1), ParamInfo("character","Character",0,1), ParamInfo("mix","Dry/Wet",0,1)] }
    public func setParam(_ id: String, _ v: Double) { if id=="size"{size=v}; if id=="character"{character=v}; if id=="mix"{mix=v} }
    public func getParam(_ id: String) -> Double { id=="size" ? size : (id=="character" ? character : (id=="mix" ? mix : 0)) }
}

// MARK: Modulation / time family

public final class AutoPanEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.autoPan
    public var bypassed = false
    private var sr = 44100.0, phase = 0.0
    public var rate = 0.5, amount = 0.75, shape = 0.0
    public init() {}
    func setSampleRate(_ s: Double) { sr = s }
    public func reset() { phase = 0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        for i in 0..<frames { phase += rate/sr; if phase >= 1 { phase -= 1 }; var lfo = sin(2 * .pi * phase); if shape > 0.5 { lfo = lfo >= 0 ? 1 : -1 }; let pan = Float(lfo * amount); let lg: Float = pan > 0 ? 1-pan : 1; let rg: Float = pan < 0 ? 1+pan : 1; left[i] *= lg; right[i] *= rg }
    }
    public var automatableParams: [ParamInfo] { [ParamInfo("rate","Rate",0.02,20,unit:"Hz"), ParamInfo("amount","Amount",0,1), ParamInfo("shape","Shape",0,1)] }
    public func setParam(_ id: String, _ v: Double) { if id=="rate"{rate=v}; if id=="amount"{amount=v}; if id=="shape"{shape=v} }
    public func getParam(_ id: String) -> Double { id=="rate" ? rate : (id=="amount" ? amount : (id=="shape" ? shape : 0)) }
}

public final class ChorusFlangerEffect: AudioEffect, SampleRateAware {
    public let kind: DeviceKind
    public var bypassed = false
    private var sr = 44100.0, phase = 0.0, idx = 0
    private var bufL = [Float](repeating:0,count:96000), bufR = [Float](repeating:0,count:96000)
    public var rate = 0.25, depthMS = 8.0, baseMS = 12.0, feedback = 0.08, mix = 0.35
    public init(kind: DeviceKind = .chorusEnsemble) { self.kind = kind; if kind == .phaserFlanger { baseMS=2; depthMS=1.7; feedback=0.35 } }
    func setSampleRate(_ s: Double) { sr=s; let c=max(2048, Int(sr*2)); bufL = .init(repeating:0,count:c); bufR = .init(repeating:0,count:c) }
    public func reset() { bufL = .init(repeating:0,count:bufL.count); bufR = .init(repeating:0,count:bufR.count); phase=0; idx=0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }; let cap=bufL.count; let wet=Float(mix), dry=1-wet, fb=Float(feedback)
        for i in 0..<frames { phase += rate/sr; if phase>=1{phase-=1}; let dms = baseMS + depthMS*(0.5+0.5*sin(2 * .pi * phase)); let d = min(cap-2, max(1, Int(dms*0.001*sr))); let r=(idx-d+cap)%cap; let dl=bufL[r], dr=bufR[r]; bufL[idx]=left[i]+dl*fb; bufR[idx]=right[i]+dr*fb; idx=(idx+1)%cap; left[i]=left[i]*dry+dl*wet; right[i]=right[i]*dry+dr*wet }
    }
    public var automatableParams: [ParamInfo] { [ParamInfo("rate","Rate",0.02,8,unit:"Hz"), ParamInfo("depth","Depth",0,20,unit:"ms"), ParamInfo("base","Base",0.2,30,unit:"ms"), ParamInfo("feedback","Feedback",0,0.9), ParamInfo("mix","Dry/Wet",0,1)] }
    public func setParam(_ id: String, _ v: Double) { switch id { case "rate": rate=v; case "depth": depthMS=v; case "base": baseMS=v; case "feedback": feedback=v; case "mix": mix=v; default: break } }
    public func getParam(_ id: String) -> Double { switch id { case "rate": return rate; case "depth": return depthMS; case "base": return baseMS; case "feedback": return feedback; case "mix": return mix; default: return 0 } }
}

public final class BeatRepeatEffect: AudioEffect, SampleRateAware, TempoAware {
    public let kind = DeviceKind.beatRepeat
    public var bypassed = false
    private var sr = 44100.0
    private var tempo = 124.0
    private var captureL = [Float](), captureR = [Float](), play = 0, write = 0
    private var stutterOffset = 0
    public var interval = 1.0, grid = 0.125, chance = 0.35, mix = 1.0
    public init() { resize() }
    func setSampleRate(_ s: Double) { sr = max(8000, s); resize() }
    func setTempo(_ bpm: Double) { tempo = max(20, min(400, bpm)) }
    private func samplesPerBeat() -> Double { sr * 60.0 / max(20.0, tempo) }
    private func resize(){
        let c = max(4096, Int(samplesPerBeat() * 8.0))
        if captureL.count != c { captureL = .init(repeating:0,count:c); captureR = .init(repeating:0,count:c); write = 0; play = 0; stutterOffset = 0 }
    }
    public func reset() { play=0; write=0; stutterOffset=0; captureL = .init(repeating:0,count:captureL.count); captureR = .init(repeating:0,count:captureR.count) }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        resize()
        let wet = Float(lclamp(mix, 0, 1)), dry = 1 - wet
        let spb = samplesPerBeat()
        let slice = max(1, Int(max(0.03125, grid) * spb))
        let period = max(slice, Int(max(0.03125, interval) * spb))
        let activeSamples = Int(Double(slice) * lclamp(chance, 0, 1))
        let cap = captureL.count
        for i in 0..<frames {
            let dryL = left[i], dryR = right[i]
            let phaseInPeriod = write % period
            let shouldGate = activeSamples > 0 && phaseInPeriod < activeSamples && write > slice
            if phaseInPeriod == 0 { stutterOffset = (write - slice + cap) % cap; play = 0 }
            captureL[write % cap] = dryL
            captureR[write % cap] = dryR
            if shouldGate {
                let read = (stutterOffset + (play % slice)) % cap
                left[i] = dryL * dry + captureL[read] * wet
                right[i] = dryR * dry + captureR[read] * wet
                play += 1
            } else {
                left[i] = dryL
                right[i] = dryR
                play = 0
            }
            write = (write + 1) % max(1, period * 128)
        }
    }
    public var automatableParams: [ParamInfo] { [ParamInfo("interval","Interval",0.125,4,unit:"beats"), ParamInfo("grid","Grid",0.03125,1,unit:"beats"), ParamInfo("chance","Chance",0,1), ParamInfo("mix","Dry/Wet",0,1)] }
    public func setParam(_ id: String, _ v: Double) { if id=="interval"{interval=v}; if id=="grid"{grid=v}; if id=="chance"{chance=v}; if id=="mix"{mix=v} }
    public func getParam(_ id: String) -> Double { id=="interval" ? interval : (id=="grid" ? grid : (id=="chance" ? chance : (id=="mix" ? mix : 0))) }
}

// MARK: Dynamics / EQ / destructive utilities

public final class GateEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.gate
    public var bypassed = false
    private var sr = 44100.0, env: Float = 0
    public var thresholdDB = -45.0, attackMS = 2.0, releaseMS = 100.0, floorDB = -80.0
    public init() {}
    func setSampleRate(_ s: Double) { sr=s }
    public func reset(){ env=0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int){ guard !bypassed else{return}; let th=dbToGain(thresholdDB); let floor=dbToGain(floorDB); let atk=Float(exp(-1/(max(0.1,attackMS)*0.001*sr))); let rel=Float(exp(-1/(max(1,releaseMS)*0.001*sr))); for i in 0..<frames{ let level=max(abs(left[i]),abs(right[i])); let target: Float = level > th ? 1 : floor; let c = target > env ? atk : rel; env = target + c*(env-target); left[i]*=env; right[i]*=env } }
    public var automatableParams:[ParamInfo]{[ParamInfo("threshold","Threshold",-80,0,unit:"dB"),ParamInfo("attack","Attack",0.1,100,unit:"ms"),ParamInfo("release","Release",5,1000,unit:"ms"),ParamInfo("floor","Floor",-100,0,unit:"dB")]}
    public func setParam(_ id:String,_ v:Double){switch id{case"threshold":thresholdDB=v;case"attack":attackMS=v;case"release":releaseMS=v;case"floor":floorDB=v;default:break}}
    public func getParam(_ id:String)->Double{switch id{case"threshold":return thresholdDB;case"attack":return attackMS;case"release":return releaseMS;case"floor":return floorDB;default:return 0}}
}

public final class LimiterEffect: AudioEffect, SampleRateAware, GainReductionMetering {
    public let kind = DeviceKind.limiter
    public var bypassed = false
    public var ceilingDB = -0.3
    public var thresholdDB = -1.0
    public var releaseMS = 90.0
    public var lookaheadMS = 3.0
    public var softClip = 0.15
    public var outputDB = 0.0
    private var sr = 44100.0
    private var lookL = [Float](repeating: 0, count: 2048)
    private var lookR = [Float](repeating: 0, count: 2048)
    private var index = 0
    public var gainReductionDB: Double { bypassed ? 0 : max(0, -20 * log10(Double(max(0.000001, envGain)))) }
    private var envGain: Float = 1

    public init() { resizeLookahead() }
    func setSampleRate(_ s: Double) { sr = max(8000, s); resizeLookahead() }

    private func resizeLookahead() {
        let samples = max(1, min(8192, Int(sr * max(0, lookaheadMS) * 0.001)))
        if lookL.count != samples { lookL = .init(repeating: 0, count: samples); lookR = .init(repeating: 0, count: samples); index = 0 }
    }

    public func reset() { lookL = .init(repeating: 0, count: lookL.count); lookR = .init(repeating: 0, count: lookR.count); index = 0; envGain = 1 }

    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        resizeLookahead()
        let ceiling = dbToGain(ceilingDB)
        let threshold = dbToGain(thresholdDB)
        let out = dbToGain(outputDB)
        let relCoeff = Float(exp(-1.0 / (max(1.0, releaseMS) * 0.001 * sr)))
        let driveIntoLimit = Float(max(0.0001, ceiling / max(0.0001, threshold)))
        let clipAmt = Float(lclamp(softClip, 0, 1))

        for i in 0..<frames {
            let inL = left[i]
            let inR = right[i]
            let delayedL = lookL[index]
            let delayedR = lookR[index]
            lookL[index] = inL
            lookR[index] = inR
            index = (index + 1) % lookL.count

            let detectorPeak = max(abs(inL), abs(inR)) * driveIntoLimit
            let targetGain: Float = detectorPeak > ceiling ? ceiling / max(detectorPeak, 0.000001) : 1
            if targetGain < envGain { envGain = targetGain } else { envGain = targetGain + relCoeff * (envGain - targetGain) }

            var l = delayedL * driveIntoLimit * envGain
            var r = delayedR * driveIntoLimit * envGain
            if clipAmt > 0 {
                let blend = clipAmt
                let cl = tanh(l / max(0.0001, ceiling)) * ceiling
                let cr = tanh(r / max(0.0001, ceiling)) * ceiling
                l = l * (1 - blend) + cl * blend
                r = r * (1 - blend) + cr * blend
            }
            left[i] = fclamp(l, -ceiling, ceiling) * out
            right[i] = fclamp(r, -ceiling, ceiling) * out
        }
    }

    public var automatableParams: [ParamInfo] {
        [ParamInfo("ceiling", "Ceiling", -12, 0, unit: "dB"),
         ParamInfo("threshold", "Threshold", -24, 0, unit: "dB"),
         ParamInfo("release", "Release", 5, 500, unit: "ms"),
         ParamInfo("lookahead", "Lookahead", 0, 10, unit: "ms"),
         ParamInfo("softclip", "Soft Clip", 0, 1),
         ParamInfo("output", "Output", -12, 6, unit: "dB")]
    }

    public func setParam(_ id: String, _ v: Double) {
        switch id {
        case "ceiling": ceilingDB = v
        case "threshold": thresholdDB = v
        case "release": releaseMS = v
        case "lookahead": lookaheadMS = v; resizeLookahead()
        case "softclip": softClip = v
        case "output": outputDB = v
        default: break
        }
    }

    public func getParam(_ id: String) -> Double {
        switch id {
        case "ceiling": return ceilingDB
        case "threshold": return thresholdDB
        case "release": return releaseMS
        case "lookahead": return lookaheadMS
        case "softclip": return softClip
        case "output": return outputDB
        default: return 0
        }
    }
}

public final class EQThreeEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.eqThree
    public var bypassed = false
    private var sr=44100.0, lowL=Biquad(), lowR=Biquad(), highL=Biquad(), highR=Biquad()
    public var lowDB=0.0, midDB=0.0, highDB=0.0, lowFreq=250.0, highFreq=2500.0
    public init(){ recompute() }
    func setSampleRate(_ s: Double){ sr=s; recompute() }
    private func recompute(){ lowL.update(kind:.lowShelf,freq:lowFreq,q:0.7,gainDB:lowDB,sr:sr); lowR=lowL; highL.update(kind:.highShelf,freq:highFreq,q:0.7,gainDB:highDB,sr:sr); highR=highL }
    public func reset(){ lowL.reset();lowR.reset();highL.reset();highR.reset() }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int){ guard !bypassed else{return}; recompute(); let mg=dbToGain(midDB); for i in 0..<frames{ var l=lowL.process(Double(left[i])); l=highL.process(l); var r=lowR.process(Double(right[i])); r=highR.process(r); left[i]=Float(l)*mg; right[i]=Float(r)*mg } }
    public var automatableParams:[ParamInfo]{[ParamInfo("low","Low",-24,24,unit:"dB"),ParamInfo("mid","Mid",-24,24,unit:"dB"),ParamInfo("high","High",-24,24,unit:"dB"),ParamInfo("lowFreq","Low X",60,800,unit:"Hz",isLog:true),ParamInfo("highFreq","High X",800,10000,unit:"Hz",isLog:true)]}
    public func setParam(_ id:String,_ v:Double){switch id{case"low":lowDB=v;case"mid":midDB=v;case"high":highDB=v;case"lowFreq":lowFreq=v;case"highFreq":highFreq=v;default:break}}
    public func getParam(_ id:String)->Double{switch id{case"low":return lowDB;case"mid":return midDB;case"high":return highDB;case"lowFreq":return lowFreq;case"highFreq":return highFreq;default:return 0}}
}

public final class ReduxEffect: AudioEffect {
    public let kind = DeviceKind.redux
    public var bypassed = false
    public var bitDepth = 12.0, downsample = 1.0, mix = 1.0
    private var holdL: Float = 0, holdR: Float = 0, counter = 0
    public init() {}
    public func reset(){ counter=0; holdL=0; holdR=0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int){ guard !bypassed else{return}; let wet=Float(mix), dry=1-wet; let steps=Float(pow(2,lclamp(bitDepth,2,24))-1); let ds=max(1,Int(downsample)); for i in 0..<frames{ if counter == 0 { holdL = round(left[i]*steps)/steps; holdR = round(right[i]*steps)/steps }; counter=(counter+1)%ds; left[i]=left[i]*dry+holdL*wet; right[i]=right[i]*dry+holdR*wet } }
    public var automatableParams:[ParamInfo]{[ParamInfo("bits","Bits",2,24),ParamInfo("downsample","Downsample",1,64),ParamInfo("mix","Dry/Wet",0,1)]}
    public func setParam(_ id:String,_ v:Double){if id=="bits"{bitDepth=v};if id=="downsample"{downsample=v};if id=="mix"{mix=v}}
    public func getParam(_ id:String)->Double{id=="bits" ? bitDepth : (id=="downsample" ? downsample : (id=="mix" ? mix : 0))}
}

// MARK: Resonant/spectral-ish processors

public final class ResonatorEffect: AudioEffect, SampleRateAware {
    public let kind: DeviceKind
    public var bypassed = false
    private var sr=44100.0, bqL=[Biquad](), bqR=[Biquad]()
    public var root=110.0, decay=0.6, mix=0.35
    public init(kind: DeviceKind = .resonators){ self.kind=kind; rebuild() }
    func setSampleRate(_ s: Double){ sr=s; rebuild() }
    private func rebuild(){ bqL = Array(repeating:Biquad(),count:5); bqR=bqL; let ratios=[1.0,1.5,2.0,2.5,3.0]; for i in 0..<5{ let f=min(sr*0.45,root*ratios[i]); bqL[i].update(kind:.peaking,freq:f,q:4+decay*30,gainDB:6+decay*10,sr:sr); bqR[i]=bqL[i] } }
    public func reset(){ for i in bqL.indices{bqL[i].reset();bqR[i].reset()} }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int){ guard !bypassed else{return}; rebuild(); let wet=Float(mix), dry=1-wet; for i in 0..<frames{ var l=Double(left[i]), r=Double(right[i]); var rl=0.0, rr=0.0; for b in bqL.indices{ rl += bqL[b].process(l); rr += bqR[b].process(r) }; left[i]=left[i]*dry+Float(rl/5)*wet; right[i]=right[i]*dry+Float(rr/5)*wet } }
    public var automatableParams:[ParamInfo]{[ParamInfo("root","Root",40,1000,unit:"Hz",isLog:true),ParamInfo("decay","Decay",0,1),ParamInfo("mix","Dry/Wet",0,1)]}
    public func setParam(_ id:String,_ v:Double){if id=="root"{root=v};if id=="decay"{decay=v};if id=="mix"{mix=v}}
    public func getParam(_ id:String)->Double{id=="root" ? root : (id=="decay" ? decay : (id=="mix" ? mix : 0))}
}

/// MIDI-only / generator-style devices use this shell for UI, automation, and project persistence.
/// The audio engine reads Pattern Arp params while scheduling MIDI notes; this object itself is transparent.
public final class MIDIUtilityEffect: AudioEffect, SampleRateAware {
    public let kind: DeviceKind
    public var bypassed = false
    private var values: [String: Double]
    private let infos: [ParamInfo]
    public init(kind: DeviceKind, params: [ParamInfo]) {
        self.kind = kind
        self.infos = params
        self.values = Dictionary(uniqueKeysWithValues: params.map { ($0.id, ($0.min + $0.max) * 0.5) })
        switch kind {
        case .arpeggiator:
            values["rate"] = 0.25; values["octaves"] = 2; values["gate"] = 0.45; values["swing"] = 0.0
        case .chord:
            values["third"] = 1; values["fifth"] = 1; values["seventh"] = 0; values["octave"] = 0
        case .pitch:
            values["transpose"] = 0; values["octave"] = 0; values["fold"] = 1
        case .tune, .scale:
            values["amount"] = 1; values["strict"] = 1
        case .velocity:
            values["gain"] = 1; values["compress"] = 0; values["random"] = 0
        case .noteLength:
            values["gate"] = 0.9; values["minimum"] = 0.08
        case .random:
            values["chance"] = 0; values["choices"] = 3; values["scale"] = 1
        case .bouncyNotes:
            values["octave"] = 0.5; values["fifth"] = 0.0; values["velocity"] = 0.75
        default:
            break
        }
    }
    func setSampleRate(_ sr: Double) {}
    public func reset() {}
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {}
    public var automatableParams: [ParamInfo] { infos }
    public func setParam(_ id: String, _ v: Double) { values[id] = v }
    public func getParam(_ id: String) -> Double { values[id] ?? 0 }
}


// MARK: - LMMS-inspired stock-device polish (original DSP, no copied code)

public final class DrumBussPolishEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.drumBuss
    public var bypassed = false
    private var sr = 44100.0
    private var envL: Float = 0, envR: Float = 0
    private var hpL = Biquad(), hpR = Biquad(), boomL = Biquad(), boomR = Biquad(), airL = Biquad(), airR = Biquad()
    public var drive = 0.28, boom = 0.32, transient = 0.38, crunch = 0.18, outputDB = 0.0
    public init() { recompute() }
    func setSampleRate(_ s: Double) { sr = s; recompute() }
    private func recompute() {
        hpL.update(kind: .highpass, freq: 28, q: 0.65, gainDB: 0, sr: sr); hpR = hpL
        boomL.update(kind: .peaking, freq: 64, q: 1.1, gainDB: boom * 8.0, sr: sr); boomR = boomL
        airL.update(kind: .highShelf, freq: 7200, q: 0.8, gainDB: 1.5 + crunch * 4.0, sr: sr); airR = airL
    }
    public func reset() { envL = 0; envR = 0; hpL.reset(); hpR.reset(); boomL.reset(); boomR.reset(); airL.reset(); airR.reset() }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        recompute()
        let d = Float(1.0 + drive * 6.0)
        let c = Float(crunch)
        let tr = Float(transient)
        let out = dbToGain(outputDB)
        for i in 0..<frames {
            let dl = left[i], dr = right[i]
            let peakL = abs(dl), peakR = abs(dr)
            envL += (peakL - envL) * (peakL > envL ? 0.25 : 0.0025)
            envR += (peakR - envR) * (peakR > envR ? 0.25 : 0.0025)
            let snapL = fclamp((peakL - envL) * 3.0, -0.25, 0.45) * tr
            let snapR = fclamp((peakR - envR) * 3.0, -0.25, 0.45) * tr
            var l = Float(hpL.process(Double(dl + fsign(dl) * snapL)))
            var r = Float(hpR.process(Double(dr + fsign(dr) * snapR)))
            l = Float(boomL.process(Double(l))); r = Float(boomR.process(Double(r)))
            let crushedL = round(l * 96) / 96
            let crushedR = round(r * 96) / 96
            l = l * (1 - c) + crushedL * c
            r = r * (1 - c) + crushedR * c
            l = tanh(l * d) / max(1, d * 0.52)
            r = tanh(r * d) / max(1, d * 0.52)
            l = Float(airL.process(Double(l))); r = Float(airR.process(Double(r)))
            left[i] = fclamp(l * out, -1.2, 1.2)
            right[i] = fclamp(r * out, -1.2, 1.2)
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("drive", "Drive", 0, 1), ParamInfo("boom", "Boom", 0, 1), ParamInfo("transient", "Transient", 0, 1), ParamInfo("crunch", "Crunch", 0, 1), ParamInfo("output", "Output", -18, 12, unit: "dB")]
    }
    public func setParam(_ id: String, _ v: Double) { switch id { case "drive": drive = v; case "boom": boom = v; case "transient": transient = v; case "crunch": crunch = v; case "output": outputDB = v; default: break } }
    public func getParam(_ id: String) -> Double { switch id { case "drive": return drive; case "boom": return boom; case "transient": return transient; case "crunch": return crunch; case "output": return outputDB; default: return 0 } }
}

public final class ErosionNoiseEffect: AudioEffect, SampleRateAware {
    public let kind: DeviceKind
    public var bypassed = false
    private var sr = 44100.0
    private var rng: UInt64 = 0x726f6775656c656d
    private var toneL = Biquad(), toneR = Biquad()
    public var amount = 0.18, frequency = 5200.0, width = 0.45, mode = 0.0, mix = 0.38
    public init(kind: DeviceKind = .erosion) { self.kind = kind; recompute() }
    func setSampleRate(_ s: Double) { sr = s; recompute() }
    private func recompute() {
        let q = 0.45 + width * 8.0
        toneL.update(kind: .peaking, freq: frequency, q: q, gainDB: 9.0, sr: sr); toneR = toneL
    }
    private func noise() -> Float {
        rng = rng &* 2862933555777941757 &+ 3037000493
        return Float(Int64(bitPattern: rng) >> 40) / Float(1 << 23)
    }
    public func reset() { toneL.reset(); toneR.reset() }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        recompute()
        let wet = Float(mix), dry = 1 - wet, amt = Float(amount)
        let ring = mode >= 0.5
        for i in 0..<frames {
            let n1 = Float(toneL.process(Double(noise())))
            let n2 = Float(toneR.process(Double(noise())))
            let l = left[i], r = right[i]
            let el = ring ? l * (1 + n1 * amt * 2.5) : l + n1 * amt
            let er = ring ? r * (1 + n2 * amt * 2.5) : r + n2 * amt
            left[i] = l * dry + tanh(el) * wet
            right[i] = r * dry + tanh(er) * wet
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("amount", "Amount", 0, 1), ParamInfo("frequency", "Frequency", 250, 14000, unit: "Hz", isLog: true), ParamInfo("width", "Width", 0, 1), ParamInfo("mode", "Mode", 0, 1), ParamInfo("mix", "Dry/Wet", 0, 1)]
    }
    public func setParam(_ id: String, _ v: Double) { switch id { case "amount": amount = v; case "frequency": frequency = v; case "width": width = v; case "mode": mode = v; case "mix": mix = v; default: break } }
    public func getParam(_ id: String) -> Double { switch id { case "amount": return amount; case "frequency": return frequency; case "width": return width; case "mode": return mode; case "mix": return mix; default: return 0 } }
}

public final class VinylPolishEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.vinylDistortion
    public var bypassed = false
    private var sr = 44100.0, phase = 0.0
    private var rng: UInt64 = 0x76696e796c6c656d
    private var dustL = Biquad(), dustR = Biquad(), toneL = Biquad(), toneR = Biquad()
    public var drive = 0.12, dust = 0.10, warp = 0.08, age = 0.25, mix = 0.55
    public init() { recompute() }
    func setSampleRate(_ s: Double) { sr = s; recompute() }
    private func recompute() {
        toneL.update(kind: .lowpass, freq: 10500 - age * 5500, q: 0.7, gainDB: 0, sr: sr); toneR = toneL
        dustL.update(kind: .highpass, freq: 1800, q: 0.7, gainDB: 0, sr: sr); dustR = dustL
    }
    private func noise() -> Float { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: rng) >> 40) / Float(1 << 23) }
    public func reset() { phase = 0; dustL.reset(); dustR.reset(); toneL.reset(); toneR.reset() }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        recompute()
        let wet = Float(mix), dry = 1 - wet, d = Float(1 + drive * 5)
        for i in 0..<frames {
            phase += 1 / max(1, sr)
            let wow = Float(1.0 + sin(2 * .pi * 0.45 * phase) * warp * 0.04 + sin(2 * .pi * 3.2 * phase) * warp * 0.012)
            let crackL = (abs(noise()) > 0.985 ? noise() * 0.45 : noise() * 0.012) * Float(dust)
            let crackR = (abs(noise()) > 0.985 ? noise() * 0.45 : noise() * 0.012) * Float(dust)
            var l = Float(toneL.process(Double(left[i] * wow)))
            var r = Float(toneR.process(Double(right[i] / max(0.9, wow))))
            l = tanh(l * d) / max(1, d * 0.6) + Float(dustL.process(Double(crackL)))
            r = tanh(r * d) / max(1, d * 0.6) + Float(dustR.process(Double(crackR)))
            left[i] = left[i] * dry + l * wet
            right[i] = right[i] * dry + r * wet
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("drive", "Drive", 0, 1), ParamInfo("dust", "Dust", 0, 1), ParamInfo("warp", "Warp", 0, 1), ParamInfo("age", "Age", 0, 1), ParamInfo("mix", "Dry/Wet", 0, 1)]
    }
    public func setParam(_ id: String, _ v: Double) { switch id { case "drive": drive = v; case "dust": dust = v; case "warp": warp = v; case "age": age = v; case "mix": mix = v; default: break } }
    public func getParam(_ id: String) -> Double { switch id { case "drive": return drive; case "dust": return dust; case "warp": return warp; case "age": return age; case "mix": return mix; default: return 0 } }
}

public final class ChannelShaperEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.channelEQ
    public var bypassed = false
    private var sr = 44100.0, hpL = Biquad(), hpR = Biquad(), midL = Biquad(), midR = Biquad(), airL = Biquad(), airR = Biquad()
    public var highpass = 30.0, body = 0.0, air = 0.0, drive = 0.0, outputDB = 0.0
    public init() { recompute() }
    func setSampleRate(_ s: Double) { sr = s; recompute() }
    private func recompute() {
        hpL.update(kind: .highpass, freq: highpass, q: 0.7, gainDB: 0, sr: sr); hpR = hpL
        midL.update(kind: .peaking, freq: 720, q: 0.9, gainDB: body, sr: sr); midR = midL
        airL.update(kind: .highShelf, freq: 9000, q: 0.7, gainDB: air, sr: sr); airR = airL
    }
    public func reset() { hpL.reset(); hpR.reset(); midL.reset(); midR.reset(); airL.reset(); airR.reset() }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        recompute()
        let d = Float(1 + drive * 3), out = dbToGain(outputDB)
        for i in 0..<frames {
            var l = Float(hpL.process(Double(left[i]))); var r = Float(hpR.process(Double(right[i])))
            l = Float(midL.process(Double(l))); r = Float(midR.process(Double(r)))
            l = Float(airL.process(Double(l))); r = Float(airR.process(Double(r)))
            left[i] = tanh(l * d) / max(1, d * 0.7) * out
            right[i] = tanh(r * d) / max(1, d * 0.7) * out
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("highpass", "HP", 20, 400, unit: "Hz", isLog: true), ParamInfo("body", "Body", -12, 12, unit: "dB"), ParamInfo("air", "Air", -12, 12, unit: "dB"), ParamInfo("drive", "Drive", 0, 1), ParamInfo("output", "Output", -18, 12, unit: "dB")]
    }
    public func setParam(_ id: String, _ v: Double) { switch id { case "highpass": highpass = v; case "body": body = v; case "air": air = v; case "drive": drive = v; case "output": outputDB = v; default: break } }
    public func getParam(_ id: String) -> Double { switch id { case "highpass": return highpass; case "body": return body; case "air": return air; case "drive": return drive; case "output": return outputDB; default: return 0 } }
}


public final class FXArchitectEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.fxArchitect
    public var bypassed = false
    private var sr = 44100.0
    private var phase = 0.0
    private var oscPhase = 0.0
    private var subPhase = 0.0
    private var delayIndex = 0
    private var rng: UInt64 = 0x6678617263686974
    private var hpL = Biquad(), hpR = Biquad(), lpL = Biquad(), lpR = Biquad(), peakL = Biquad(), peakR = Biquad()
    private var tailL = [Float](repeating: 0, count: 65536)
    private var tailR = [Float](repeating: 0, count: 65536)

    // Preset map: 0 Riser, 1 Tonal Riser, 2 Impact, 3 Downlifter, 4 Noise Sweep.
    public var preset = 0.0
    public var length = 4.0
    public var intensity = 0.72
    public var rootHz = 130.81
    public var sweep = 0.78
    public var tone = 0.55
    public var stereo = 0.42
    public var outputDB = -8.0
    public var mix = 1.0

    public init() { recompute() }
    func setSampleRate(_ s: Double) {
        sr = max(8000, s)
        let cap = max(2048, min(262144, Int(sr * 2.0)))
        tailL = .init(repeating: 0, count: cap)
        tailR = .init(repeating: 0, count: cap)
        delayIndex = 0
        recompute()
    }
    private var presetIndex: Int { Int(lclamp(round(preset), 0, 4)) }
    private func recompute() {
        let bright = 900.0 + tone * 15000.0
        hpL.update(kind: .highpass, freq: 35.0 + tone * 260.0, q: 0.72, gainDB: 0, sr: sr); hpR = hpL
        lpL.update(kind: .lowpass, freq: bright, q: 0.7 + sweep * 1.4, gainDB: 0, sr: sr); lpR = lpL
        peakL.update(kind: .peaking, freq: max(80, rootHz * (1.0 + tone * 8.0)), q: 0.7 + sweep * 7.0, gainDB: 2 + intensity * 8, sr: sr); peakR = peakL
    }
    private func noise() -> Float {
        rng = rng &* 2862933555777941757 &+ 3037000493
        return Float(Int64(bitPattern: rng) >> 40) / Float(1 << 23)
    }
    private func softSaw(_ phase: Double) -> Float {
        let s = 2.0 * (phase - floor(phase + 0.5))
        return Float(tanh(s * 2.0))
    }
    public func reset() {
        phase = 0; oscPhase = 0; subPhase = 0; delayIndex = 0; rng = 0x6678617263686974
        hpL.reset(); hpR.reset(); lpL.reset(); lpR.reset(); peakL.reset(); peakR.reset()
        tailL = .init(repeating: 0, count: tailL.count); tailR = .init(repeating: 0, count: tailR.count)
    }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        recompute()
        let cycleSeconds = max(0.25, length)
        let wet = Float(mix), dry = 1 - wet
        let out = dbToGain(outputDB)
        let idx = presetIndex
        let st = Float(stereo)
        let drive = Float(1.0 + intensity * 2.5)
        let tailFeedback = Float(0.18 + intensity * 0.38)
        let tailTap = max(1, min(tailL.count - 1, Int(sr * (0.045 + stereo * 0.12))))
        for i in 0..<frames {
            phase += 1.0 / (sr * cycleSeconds)
            if phase >= 1.0 { phase -= floor(phase) }
            let p = phase
            let rise = Float(pow(p, 0.55 + (1 - sweep) * 1.2))
            let fall = Float(pow(1.0 - p, 1.2))
            let click = Float(exp(-p * (18.0 + intensity * 34.0)))
            let shimmer = Float(sin(2 * .pi * (p * (8.0 + sweep * 40.0) + p * p * (12.0 + sweep * 80.0))))
            let sweepFreq = max(35.0, rootHz * pow(2.0, (idx == 3 ? 4.0 * (1 - p) : 0.25 + 4.75 * p) * sweep))
            oscPhase += sweepFreq / sr
            subPhase += max(18.0, sweepFreq * 0.5) / sr
            if oscPhase >= 1.0 { oscPhase -= floor(oscPhase) }
            if subPhase >= 1.0 { subPhase -= floor(subPhase) }

            let n = noise()
            let n2 = noise()
            var fxL: Float = 0
            var fxR: Float = 0
            switch idx {
            case 1: // Tonal Riser
                let env = rise * Float(0.18 + intensity)
                let toneSig = sin(Float(2 * .pi * oscPhase)) * 0.62 + softSaw(oscPhase) * 0.22 + sin(Float(2 * .pi * subPhase)) * 0.16
                fxL = toneSig * env + n * env * Float(0.05 + tone * 0.08)
                fxR = (toneSig * (1 - st * 0.18) + n2 * st * 0.22) * env
            case 2: // Impact
                let body = sin(Float(2 * .pi * subPhase)) * click * Float(1.8 + intensity)
                let thwack = (abs(n) > 0.78 ? n : n * 0.25) * click * Float(1.2 + intensity)
                fxL = body + thwack
                fxR = body * 0.95 + (abs(n2) > 0.80 ? n2 : n2 * 0.25) * click * Float(1.1 + intensity)
            case 3: // Downlifter
                let env = fall * Float(0.20 + intensity)
                fxL = (n * 0.55 + shimmer * 0.30 + softSaw(oscPhase) * 0.15) * env
                fxR = (n2 * 0.55 - shimmer * 0.24 + softSaw(oscPhase + 0.015) * 0.15) * env
            case 4: // Noise Sweep
                let env = sin(Float(.pi * p)) * Float(0.24 + intensity)
                fxL = (n * 0.70 + shimmer * 0.20) * env
                fxR = (n2 * 0.70 - shimmer * 0.16) * env
            default: // Riser
                let env = rise * Float(0.22 + intensity)
                fxL = (n * 0.60 + shimmer * 0.26 + softSaw(oscPhase) * 0.14) * env
                fxR = (n2 * 0.60 - shimmer * 0.20 + softSaw(oscPhase + 0.01) * 0.14) * env
            }

            fxL = Float(hpL.process(Double(fxL))); fxR = Float(hpR.process(Double(fxR)))
            fxL = Float(peakL.process(Double(fxL))); fxR = Float(peakR.process(Double(fxR)))
            fxL = Float(lpL.process(Double(fxL))); fxR = Float(lpR.process(Double(fxR)))
            fxL = tanh(fxL * drive) / max(1, drive * 0.7)
            fxR = tanh(fxR * drive) / max(1, drive * 0.7)

            let read = (delayIndex - tailTap + tailL.count) % tailL.count
            let dl = tailL[read], dr = tailR[read]
            tailL[delayIndex] = fxL + dr * tailFeedback * st
            tailR[delayIndex] = fxR + dl * tailFeedback * st
            delayIndex = (delayIndex + 1) % tailL.count
            let finalL = (fxL + dl * Float(0.28 + stereo * 0.45)) * out
            let finalR = (fxR + dr * Float(0.28 + stereo * 0.45)) * out
            left[i] = left[i] * dry + finalL * wet
            right[i] = right[i] * dry + finalR * wet
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("preset", "Preset", 0, 4),
         ParamInfo("length", "Length", 0.5, 16, unit: "s"),
         ParamInfo("intensity", "Intensity", 0, 1),
         ParamInfo("root", "Root", 32.7, 523.25, unit: "Hz", isLog: true),
         ParamInfo("sweep", "Sweep", 0, 1),
         ParamInfo("tone", "Tone", 0, 1),
         ParamInfo("stereo", "Stereo", 0, 1),
         ParamInfo("output", "Output", -30, 6, unit: "dB"),
         ParamInfo("mix", "Dry/Wet", 0, 1)]
    }
    public func setParam(_ id: String, _ v: Double) {
        switch id {
        case "preset": preset = lclamp(round(v), 0, 4)
        case "length": length = max(0.25, v)
        case "intensity": intensity = lclamp(v, 0, 1)
        case "root": rootHz = max(16.0, v)
        case "sweep": sweep = lclamp(v, 0, 1)
        case "tone": tone = lclamp(v, 0, 1)
        case "stereo": stereo = lclamp(v, 0, 1)
        case "output": outputDB = v
        case "mix": mix = lclamp(v, 0, 1)
        default: break
        }
    }
    public func getParam(_ id: String) -> Double {
        switch id {
        case "preset": return preset
        case "length": return length
        case "intensity": return intensity
        case "root": return rootHz
        case "sweep": return sweep
        case "tone": return tone
        case "stereo": return stereo
        case "output": return outputDB
        case "mix": return mix
        default: return 0
        }
    }
}




// MARK: - Non-stub stock fallback processors

/// Generic but audible processor used for stock audio devices that do not have a
/// bespoke model yet. This keeps the browser honest: adding a stock audio effect
/// must never create a silent transparent stub.
public final class StockCharacterEffect: AudioEffect, SampleRateAware {
    public let kind: DeviceKind
    public var bypassed = false
    private var sr = 44100.0
    private var phase = 0.0
    private var lpL = Biquad(), lpR = Biquad(), hpL = Biquad(), hpR = Biquad(), peakL = Biquad(), peakR = Biquad()
    public var intensity = 0.5
    public var tone = 0.55
    public var motion = 0.0
    public var mix = 0.65
    public var outputDB = 0.0

    public init(kind: DeviceKind) {
        self.kind = kind
        switch kind {
        case .vectorDelay: mix = 0.35; motion = 0.25
        case .spectralTime, .granulator: mix = 0.45; intensity = 0.65; motion = 0.35
        case .filterDelay, .grainDelay: mix = 0.40; tone = 0.65; motion = 0.20
        case .shifter: mix = 0.45; motion = 0.35
        default: break
        }
        recompute()
    }

    func setSampleRate(_ s: Double) { sr = max(8000, s); recompute() }
    public func reset() { phase = 0; lpL.reset(); lpR.reset(); hpL.reset(); hpR.reset(); peakL.reset(); peakR.reset() }

    private func recompute() {
        let t = lclamp(tone, 0, 1)
        let i = lclamp(intensity, 0, 1)
        hpL.update(kind: .highpass, freq: 28 + 120 * i, q: 0.7, gainDB: 0, sr: sr); hpR = hpL
        lpL.update(kind: .lowpass, freq: 1800 + t * 15000, q: 0.75 + i * 0.6, gainDB: 0, sr: sr); lpR = lpL
        peakL.update(kind: .peaking, freq: 180 + t * 4200, q: 0.8 + i * 4.0, gainDB: -2 + i * 8, sr: sr); peakR = peakL
    }

    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        recompute()
        let wet = Float(lclamp(mix, 0, 1))
        let dry = 1 - wet
        let out = dbToGain(outputDB)
        let drive = Float(1.0 + lclamp(intensity, 0, 1) * 3.5)
        let motionDepth = Float(lclamp(motion, 0, 1))
        let lfoRate = 0.10 + lclamp(motion, 0, 1) * 6.0
        for n in 0..<frames {
            phase += lfoRate / sr
            if phase >= 1 { phase -= 1 }
            let lfo = Float(0.5 + 0.5 * sin(2 * .pi * phase))
            let sourceL = left[n]
            let sourceR = right[n]
            var wl = Float(lpL.process(peakL.process(hpL.process(Double(sourceL)))))
            var wr = Float(lpR.process(peakR.process(hpR.process(Double(sourceR)))))
            let mod = 1.0 - motionDepth * 0.45 + motionDepth * 0.9 * lfo
            wl = tanh(wl * drive) / max(1, drive * 0.55)
            wr = tanh(wr * drive) / max(1, drive * 0.55)
            left[n] = (sourceL * dry + wl * wet * mod) * out
            right[n] = (sourceR * dry + wr * wet * (1.0 - motionDepth * 0.25 + motionDepth * 0.5 * (1 - lfo))) * out
        }
    }

    public var automatableParams: [ParamInfo] {
        [ParamInfo("intensity", "Intensity", 0, 1),
         ParamInfo("tone", "Tone", 0, 1),
         ParamInfo("motion", "Motion", 0, 1),
         ParamInfo("mix", "Dry/Wet", 0, 1),
         ParamInfo("output", "Output", -24, 12, unit: "dB")]
    }
    public func setParam(_ id: String, _ v: Double) {
        switch id {
        case "intensity": intensity = lclamp(v, 0, 1)
        case "tone": tone = lclamp(v, 0, 1)
        case "motion": motion = lclamp(v, 0, 1)
        case "mix": mix = lclamp(v, 0, 1)
        case "output": outputDB = v
        default: break
        }
    }
    public func getParam(_ id: String) -> Double {
        switch id {
        case "intensity": return intensity
        case "tone": return tone
        case "motion": return motion
        case "mix": return mix
        case "output": return outputDB
        default: return 0
        }
    }
}

/// Transfer-curve shaper for the stock Shaper / Mod Shaper slot.
public final class ShaperEffect: AudioEffect {
    public let kind = DeviceKind.shaper
    public var bypassed = false
    public var driveDB = 12.0
    public var curve = 0.6
    public var symmetry = 0.0
    public var mix = 1.0
    public var outputDB = 0.0
    public init() {}
    public func reset() {}
    @inline(__always) private func shape(_ x: Float) -> Float {
        let sym = Float(lclamp(symmetry, -1, 1)) * 0.35
        let d = dbToGain(driveDB)
        let c = Float(lclamp(curve, 0, 1))
        let y = (x + sym) * d
        let soft = tanh(y)
        let hard = fclamp(y, -1, 1)
        return (soft * (1 - c) + hard * c) - sym * 0.5
    }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        let wet = Float(lclamp(mix, 0, 1)), dry = 1 - wet, out = dbToGain(outputDB)
        for i in 0..<frames {
            let l = left[i], r = right[i]
            left[i] = (l * dry + shape(l) * wet) * out
            right[i] = (r * dry + shape(r) * wet) * out
        }
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("drive", "Drive", 0, 36, unit: "dB"), ParamInfo("curve", "Curve", 0, 1), ParamInfo("symmetry", "Symmetry", -1, 1), ParamInfo("mix", "Dry/Wet", 0, 1), ParamInfo("output", "Output", -24, 12, unit: "dB")]
    }
    public func setParam(_ id: String, _ v: Double) { switch id { case "drive": driveDB = v; case "curve": curve = v; case "symmetry": symmetry = v; case "mix": mix = v; case "output": outputDB = v; default: break } }
    public func getParam(_ id: String) -> Double { switch id { case "drive": return driveDB; case "curve": return curve; case "symmetry": return symmetry; case "mix": return mix; case "output": return outputDB; default: return 0 } }
}

/// Lightweight insert vocoder/robotizer. It does not require a sidechain carrier;
/// instead it derives an envelope from the input and imposes it onto an internal
/// carrier plus formant filters, so the device is immediately audible on audio or MIDI tracks.
public final class VocoderEffect: AudioEffect, SampleRateAware {
    public let kind = DeviceKind.vocoder
    public var bypassed = false
    private var sr = 44100.0
    private var phase = 0.0
    private var env: Float = 0
    private var bpL = Biquad(), bpR = Biquad(), airL = Biquad(), airR = Biquad()
    public var carrierHz = 110.0
    public var formant = 0.55
    public var robot = 0.75
    public var mix = 0.65
    public init() { recompute() }
    func setSampleRate(_ s: Double) { sr = max(8000, s); recompute() }
    private func recompute() {
        let f = 250 + lclamp(formant, 0, 1) * 3200
        bpL.update(kind: .peaking, freq: f, q: 3.0, gainDB: 9.0, sr: sr); bpR = bpL
        airL.update(kind: .highShelf, freq: 4500, q: 0.8, gainDB: -3 + formant * 8, sr: sr); airR = airL
    }
    public func reset() { phase = 0; env = 0; bpL.reset(); bpR.reset(); airL.reset(); airR.reset() }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        recompute()
        let wet = Float(lclamp(mix, 0, 1)), dry = 1 - wet
        let rob = Float(lclamp(robot, 0, 1))
        for i in 0..<frames {
            let l = left[i], r = right[i]
            let mono = (abs(l) + abs(r)) * 0.5
            env += (mono - env) * (mono > env ? 0.08 : 0.006)
            phase += carrierHz / sr
            if phase >= 1 { phase -= 1 }
            let saw = Float(2.0 * phase - 1.0)
            let pulse: Float = phase < 0.5 ? 1 : -1
            let carrier = saw * (1 - rob) + pulse * rob
            var wl = Float(airL.process(bpL.process(Double(carrier * env * 2.4 + l * 0.18))))
            var wr = Float(airR.process(bpR.process(Double(carrier * env * 2.4 + r * 0.18))))
            wl = tanh(wl * 1.6); wr = tanh(wr * 1.6)
            left[i] = l * dry + wl * wet
            right[i] = r * dry + wr * wet
        }
    }
    public var automatableParams: [ParamInfo] { [ParamInfo("carrier", "Carrier", 40, 880, unit: "Hz", isLog: true), ParamInfo("formant", "Formant", 0, 1), ParamInfo("robot", "Robot", 0, 1), ParamInfo("mix", "Dry/Wet", 0, 1)] }
    public func setParam(_ id: String, _ v: Double) { switch id { case "carrier": carrierHz = max(20, v); case "formant": formant = lclamp(v, 0, 1); case "robot": robot = lclamp(v, 0, 1); case "mix": mix = lclamp(v, 0, 1); default: break } }
    public func getParam(_ id: String) -> Double { switch id { case "carrier": return carrierHz; case "formant": return formant; case "robot": return robot; case "mix": return mix; default: return 0 } }
}

public final class AnalyzerUtilityEffect: AudioEffect, SampleRateAware {
    public let kind: DeviceKind
    public var bypassed = false
    private var sr = 44100.0
    private var peak: Float = 0
    private var rms: Float = 0
    private var zeroCrossings: Double = 0
    public init(kind: DeviceKind) { self.kind = kind }
    func setSampleRate(_ s: Double) { sr = max(8000, s) }
    public func reset() { peak = 0; rms = 0; zeroCrossings = 0 }
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {
        guard !bypassed else { return }
        var sum: Float = 0
        var p: Float = 0
        var zc = 0
        var prev: Float = 0
        for i in 0..<frames {
            let m = (left[i] + right[i]) * 0.5
            sum += m * m
            p = max(p, abs(m))
            if (m >= 0) != (prev >= 0) { zc += 1 }
            prev = m
        }
        peak = peak * 0.85 + p * 0.15
        rms = rms * 0.85 + sqrt(sum / Float(max(1, frames))) * 0.15
        zeroCrossings = zeroCrossings * 0.85 + Double(zc) * 0.15
    }
    public var automatableParams: [ParamInfo] {
        [ParamInfo("peak", "Peak", 0, 1), ParamInfo("rms", "RMS", 0, 1), ParamInfo("activity", "Activity", 0, 1), ParamInfo("rate", "Rate", 0.01, 20, unit: "Hz")]
    }
    public func setParam(_ id: String, _ v: Double) {}
    public func getParam(_ id: String) -> Double {
        switch id {
        case "peak": return Double(peak)
        case "rms": return Double(rms)
        case "activity": return min(1.0, zeroCrossings / max(1.0, sr * 0.02))
        case "rate": return 1.0
        default: return 0
        }
    }
}

public final class RackPassThroughEffect: AudioEffect, SampleRateAware {
    public let kind: DeviceKind
    public var bypassed = false
    public var chain = 0.0
    public var macro1 = 0.0
    public var macro2 = 0.0
    public var macro3 = 0.0
    public var macro4 = 0.0
    public init(kind: DeviceKind) { self.kind = kind }
    func setSampleRate(_ sr: Double) {}
    public func reset() {}
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int) {}
    public var automatableParams: [ParamInfo] {
        [ParamInfo("chain", "Chain", 0, 7), ParamInfo("macro1", "Macro 1", 0, 1), ParamInfo("macro2", "Macro 2", 0, 1), ParamInfo("macro3", "Macro 3", 0, 1), ParamInfo("macro4", "Macro 4", 0, 1)]
    }
    public func setParam(_ id: String, _ v: Double) {
        switch id { case "chain": chain = v; case "macro1": macro1 = v; case "macro2": macro2 = v; case "macro3": macro3 = v; case "macro4": macro4 = v; default: break }
    }
    public func getParam(_ id: String) -> Double {
        switch id { case "chain": return chain; case "macro1": return macro1; case "macro2": return macro2; case "macro3": return macro3; case "macro4": return macro4; default: return 0 }
    }
}

// MARK: Device factory extension hook

public enum StockDSPFactory {
    public static func make(_ kind: DeviceKind) -> AudioEffect? {
        switch kind {
        case .arpeggiator: return MIDIUtilityEffect(kind: .arpeggiator, params: [ParamInfo("rate", "Rate", 0.125, 1.0, unit: "beats"), ParamInfo("octaves", "Octaves", 1, 4), ParamInfo("gate", "Gate", 0.05, 0.95), ParamInfo("swing", "Swing", 0, 0.75)])
        case .chord: return MIDIUtilityEffect(kind: .chord, params: [ParamInfo("third", "Third", 0, 1), ParamInfo("fifth", "Fifth", 0, 1), ParamInfo("seventh", "Seventh", 0, 1), ParamInfo("octave", "Octave", 0, 1)])
        case .pitch: return MIDIUtilityEffect(kind: .pitch, params: [ParamInfo("transpose", "Transpose", -24, 24, unit: "st"), ParamInfo("octave", "Octave", -2, 2), ParamInfo("fold", "Fold 0-127", 0, 1)])
        case .tune, .scale: return MIDIUtilityEffect(kind: kind, params: [ParamInfo("amount", "Amount", 0, 1), ParamInfo("strict", "Strict", 0, 1)])
        case .velocity: return MIDIUtilityEffect(kind: .velocity, params: [ParamInfo("gain", "Gain", 0, 2), ParamInfo("compress", "Compress", 0, 1), ParamInfo("random", "Humanize", 0, 0.35)])
        case .noteLength: return MIDIUtilityEffect(kind: .noteLength, params: [ParamInfo("gate", "Gate", 0.05, 2.0), ParamInfo("minimum", "Minimum", 0.03, 1.0, unit: "beats")])
        case .random: return MIDIUtilityEffect(kind: .random, params: [ParamInfo("chance", "Chance", 0, 1), ParamInfo("choices", "Choices", 1, 7), ParamInfo("scale", "Scale Safe", 0, 1)])
        case .bouncyNotes: return MIDIUtilityEffect(kind: .bouncyNotes, params: [ParamInfo("octave", "Octave Pop", 0, 1), ParamInfo("fifth", "Fifth Pop", 0, 1), ParamInfo("velocity", "Bounce Vel", 0, 1)])
        case .dubstepWrangler: return MIDIUtilityEffect(kind: .dubstepWrangler, params: [ParamInfo("wobble", "Wobble", 0, 1), ParamInfo("growl", "Growl", 0, 1), ParamInfo("space", "Space", 0, 1)])
        case .alignDelay: return AlignDelayEffect()
        case .amp: return SaturatorEffect(kind: .amp, drive: 18)
        case .overdrive: return SaturatorEffect(kind: .overdrive, drive: 14)
        case .pedal: return SaturatorEffect(kind: .pedal, drive: 10)
        case .dynamicTube: return SaturatorEffect(kind: .dynamicTube, drive: 8)
        case .saturator: return SaturatorEffect(kind: .saturator, drive: 6)
        case .roar: return SaturatorEffect(kind: .roar, drive: 20)
        case .vinylDistortion: return VinylPolishEffect()
        case .cabinet: return CabinetEffect()
        case .autoPan: return AutoPanEffect()
        case .chorusEnsemble: return ChorusFlangerEffect(kind: .chorusEnsemble)
        case .phaserFlanger: return ChorusFlangerEffect(kind: .phaserFlanger)
        case .beatRepeat: return BeatRepeatEffect()
        case .echo: return DelayEffect()
        case .filterDelay: return DelayEffect()
        case .fxArchitect: return FXArchitectEffect()
        case .grainDelay: return DelayEffect()
        case .vectorDelay: return DelayEffect()
        case .hybridReverb: return ReverbEffect()
        case .gate: return GateEffect()
        case .glueCompressor: return GlueBusCompressorEffect()
        case .limiter: return LimiterEffect()
        case .drumBuss: return DrumBussPolishEffect()
        case .multibandDynamics: return CompressorEffect()
        case .channelEQ: return ChannelShaperEffect()
        case .eqThree: return EQThreeEffect()
        case .redux: return ReduxEffect()
        case .erosion: return ErosionNoiseEffect(kind: .erosion)
        case .resonators: return ResonatorEffect(kind: .resonators)
        case .corpus: return ResonatorEffect(kind: .corpus)
        case .spectralResonator: return ResonatorEffect(kind: .spectralResonator)
        case .shifter: return ChorusFlangerEffect(kind: .shifter)
        case .shaper: return ShaperEffect()
        case .vocoder: return VocoderEffect()
        case .spectralTime: return StockCharacterEffect(kind: .spectralTime)
        case .granulator: return StockCharacterEffect(kind: .granulator)
        case .looper: return BeatRepeatEffect()
        case .lfo, .envelopeFollower, .spectrum, .tuner: return AnalyzerUtilityEffect(kind: kind)
        case .audioEffectRack, .instrumentRack, .midiEffectRack: return RackPassThroughEffect(kind: kind)
        case .externalAudioEffect, .externalInstrument, .cvInstrument, .cvTriggers: return RackPassThroughEffect(kind: kind)
        case .utility: return UtilityEffect()
        default:
            if kind.role == .audioEffect { return StockCharacterEffect(kind: kind) }
            return nil
        }
    }
}
