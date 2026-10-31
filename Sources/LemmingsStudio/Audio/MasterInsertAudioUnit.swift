import AVFoundation
import AudioToolbox

/// An actual pull-through effect node: the same master chain runs live and offline.
final class MasterInsertAudioUnit: AUAudioUnit {
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    private var scratch: AVAudioPCMBuffer?
    var process: ((UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>, Int, Double) -> Void)?
    override var inputBusses: AUAudioUnitBusArray { inputs }
    override var outputBusses: AUAudioUnitBusArray { outputs }
    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format); outputBus = try AUAudioUnitBus(format: format)
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        maximumFramesToRender = 4096
    }
    override func allocateRenderResources() throws {
        scratch = AVAudioPCMBuffer(pcmFormat: outputBus.format, frameCapacity: maximumFramesToRender)
        try super.allocateRenderResources()
    }
    override func deallocateRenderResources() { scratch = nil; super.deallocateRenderResources() }
    override var internalRenderBlock: AUInternalRenderBlock {
        { [weak self] flags, stamp, frames, _, data, _, pull in
            guard let self, let pull else { return kAudioUnitErr_NoConnection }
            let buffers = UnsafeMutableAudioBufferListPointer(data)
            if buffers.first?.mData == nil, let scratch = self.scratch {
                let own = UnsafeMutableAudioBufferListPointer(scratch.mutableAudioBufferList)
                for i in 0..<min(buffers.count, own.count) { buffers[i].mData = own[i].mData; buffers[i].mDataByteSize = frames * 4 }
            }
            let status = pull(flags, stamp, frames, 0, data)
            guard status == noErr else { return status }
            guard buffers.count == 2, let l = buffers[0].mData, let r = buffers[1].mData else { return kAudioUnitErr_FormatNotSupported }
            self.process?(l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), Int(frames), stamp.pointee.mSampleTime)
            // Inserts may produce reverb/delay tails even after silent input.
            flags.pointee.remove(.unitRenderAction_OutputIsSilence)
            return noErr
        }
    }
    static let component: AudioComponentDescription = {
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: 0x4c6d4d73, componentManufacturer: 0x4c6d5374, componentFlags: 0, componentFlagsMask: 0)
        AUAudioUnit.registerSubclass(MasterInsertAudioUnit.self, as: desc, name: "LemmingsStudio: Master Inserts", version: 1)
        return desc
    }()
}

public protocol GainReductionMetering: AnyObject {
    /// Positive attenuation in dB, before makeup/output gain; zero when bypassed.
    var gainReductionDB: Double { get }
}
