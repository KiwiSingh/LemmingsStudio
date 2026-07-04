import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public var id: String { uid }
    public var uid: String
    public var name: String
    public var channelCount: Int
    public var isDefault: Bool
}

// MARK: - Audio recorder (microphones / line-in)
//
// Opens an input-only capture stream, accumulates mono samples from the selected
// channel while armed, and on stop commits them as an `AudioClip` on the target
// audio track. This deliberately keeps recording separate from the playback
// graph, closer to Audacity/PortAudio's callback-buffer model, so selecting an
// input device cannot reset the arrangement playback engine mid-record.
//
// AVAudioEngine input nodes follow the current CoreAudio default input, so when
// a non-default device is chosen we temporarily promote that device to the
// default input before opening a fresh capture stream. Tracks still choose the
// exact channel manually, which is important for interfaces like Revelator.

public final class AudioRecorder {
    public static let systemDefaultDeviceUID = "__lemmings_system_default_input__"

    private unowned let engine: AudioEngine
    private var recording = false
    private var captured: [Float] = []
    private let captureLock = NSLock()
    private var captureRate: Double = 44100
    private var startBeat: Double = 0
    /// Standalone CoreAudio HAL output unit configured for INPUT (AUHAL) — the
    /// exact mechanism PortAudio/Audacity use under the hood (Apple TN2091). It
    /// binds one device by AudioDeviceID and pulls float buffers in a render
    /// callback, completely independent of AVAudioEngine, so nothing in the
    /// playback graph (or a second engine) can contend for the input device.
    private var captureUnit: AudioUnit?
    private var captureABL: UnsafeMutableAudioBufferListPointer?
    private var captureMaxFrames: UInt32 = 4096
    private var captureRestartAttempted = false
    private var lastPreviewPushTime: CFAbsoluteTime = 0
    private var captureChannels: Int = 1
    private var captureChannelIndex: Int = 0
    private weak var activeTrack: Track?
    private weak var activeClip: AudioClip?
    private var selectedDeviceUID: String = AudioRecorder.systemDefaultDeviceUID
    private var recordingStartedAt: Date?
    private var progressTimer: Timer?
    private var receivedInputBuffers = 0

    public private(set) var inputName: String = "Default Input"
    public private(set) var selectedInputDeviceName: String = "System Default"
    public private(set) var inputDevices: [AudioInputDevice] = []
    public var isRecording: Bool { recording }
    public var level: Float = 0      // live input meter 0...1
    /// Set whenever the recorder reports something — hard errors, device-binding
    /// fallbacks, and the async silent-stream / "no callbacks" warnings from the
    /// background watchdog timers. The didSet fires `onDiagnostic` on the main
    /// queue so the GUI status bar shows it (the recorder itself isn't Observable).
    public private(set) var lastError: String? = nil {
        didSet {
            guard let lastError, lastError != oldValue else { return }
            let cb = onDiagnostic
            DispatchQueue.main.async { cb?(lastError) }
        }
    }
    /// GUI hook: AppState assigns this to mirror recorder diagnostics into an
    /// @Observable status string the status bar renders.
    public var onDiagnostic: ((String) -> Void)?

    public init(engine: AudioEngine) {
        self.engine = engine
        refreshInputDevices()
        refreshInputDescription()
    }

    public func refreshInputDevices() {
        let defaultUID = Self.currentDefaultInputDeviceUID()
        var devices = Self.enumerateInputDevices(defaultUID: defaultUID)
        let defaultChannels = devices.first(where: { $0.isDefault })?.channelCount ?? max(1, Int(engine.avEngine.inputNode.outputFormat(forBus: 0).channelCount))
        devices.insert(AudioInputDevice(uid: Self.systemDefaultDeviceUID, name: "System Default", channelCount: defaultChannels, isDefault: selectedDeviceUID == Self.systemDefaultDeviceUID), at: 0)
        inputDevices = devices
        if selectedDeviceUID != Self.systemDefaultDeviceUID, !inputDevices.contains(where: { $0.uid == selectedDeviceUID }) {
            selectedDeviceUID = Self.systemDefaultDeviceUID
        }
        selectedInputDeviceName = device(for: selectedDeviceUID).name
    }

    @discardableResult
    public func selectInputDevice(uid: String?) -> AudioInputDevice {
        refreshInputDevices()
        let normalized = (uid?.isEmpty == false) ? uid! : Self.systemDefaultDeviceUID
        let selected = device(for: normalized)
        selectedDeviceUID = selected.uid
        selectedInputDeviceName = selected.name
        // We no longer promote the chosen device to the global system-default input
        // (that hijacked the user's mic system-wide). The capture engine binds the
        // exact device on its own input AUHAL instead — see startHALCapture.
        lastError = nil
        refreshInputDescription()
        return selected
    }

    public func device(for uid: String?) -> AudioInputDevice {
        let normalized = (uid?.isEmpty == false) ? uid! : Self.systemDefaultDeviceUID
        if let found = inputDevices.first(where: { $0.uid == normalized }) { return found }
        if normalized != Self.systemDefaultDeviceUID, let found = Self.enumerateInputDevices(defaultUID: Self.currentDefaultInputDeviceUID()).first(where: { $0.uid == normalized }) { return found }
        return inputDevices.first ?? AudioInputDevice(uid: Self.systemDefaultDeviceUID, name: "System Default", channelCount: availableChannelCount, isDefault: true)
    }

    public func refreshInputDescription() {
        let fmt = engine.avEngine.inputNode.outputFormat(forBus: 0)
        let selected = device(for: selectedDeviceUID)
        inputName = "\(selected.name) · \(Int(fmt.sampleRate)) Hz · \(max(1, Int(fmt.channelCount)))ch"
    }

    public var availableChannelCount: Int {
        channelCount(for: selectedDeviceUID)
    }

    public func channelCount(for deviceUID: String?) -> Int {
        let device = device(for: deviceUID)
        if device.uid == Self.systemDefaultDeviceUID {
            let fmtCount = Int(engine.avEngine.inputNode.outputFormat(forBus: 0).channelCount)
            return max(1, max(device.channelCount, fmtCount))
        }
        return max(1, device.channelCount)
    }

    public func channelLabel(for index: Int, deviceUID: String? = nil) -> String {
        let count = channelCount(for: deviceUID ?? selectedDeviceUID)
        if count <= 1 { return "Mono Input 1" }
        return "Input \(min(max(index, 0), count - 1) + 1)"
    }

    /// Begin capturing into `track` at the current beat. `track.kind` should be `.audio`.
    public func start(into track: Track, monitor: Bool) {
        guard !recording else { return }
        let targetDeviceUID = track.audioInputDeviceUID ?? selectedDeviceUID
        let selectedDevice = selectInputDevice(uid: targetDeviceUID)
        track.audioInputDeviceName = selectedDevice.name
        lastError = nil

        // Kill any previous half-open capture session before creating a new
        // visible take. The old path could leave two tiny empty regions when the
        // input stream failed to deliver buffers.
        cancel()
        removeStaleEmptyRecordingClips(on: track, nearBeat: engine.currentBeat)

        let advertisedChannels = max(1, selectedDevice.channelCount)
        let requestedChannel = min(max(0, track.audioInputChannelIndex), advertisedChannels - 1)
        track.audioInputChannelIndex = requestedChannel
        captureChannels = advertisedChannels
        captureChannelIndex = requestedChannel
        captureRate = max(8000, engine.sampleRate)

        captureLock.lock()
        captured.removeAll(keepingCapacity: true)
        captureLock.unlock()
        receivedInputBuffers = 0
        captureRestartAttempted = false
        recordingStartedAt = Date()
        startBeat = engine.currentBeat

        let provisionalClip = AudioClip(startBeat: startBeat, samples: [], sampleRate: captureRate)
        let deviceName = track.audioInputDeviceName.isEmpty ? selectedInputDeviceName : track.audioInputDeviceName
        provisionalClip.displayName = "Recording · \(deviceName) · \(channelLabel(for: track.audioInputChannelIndex, deviceUID: track.audioInputDeviceUID))"
        provisionalClip.loopEnabled = false
        provisionalClip.lengthBeatsOverride = 0.25
        track.audioClips.append(provisionalClip)
        activeTrack = track
        activeClip = provisionalClip
        recording = true
        startProgressTimer(for: provisionalClip)

        if monitor {
            lastError = [lastError, "Software input loopback is disabled while recording; use direct monitoring on the interface if you need live voice monitoring."]
                .compactMap { $0 }.joined(separator: " ")
        }

        do {
            try startHALCapture(device: selectedDevice, channel: requestedChannel)
        } catch {
            recording = false
            stopProgressTimer()
            stopCaptureEngine()
            track.audioClips.removeAll { $0.id == provisionalClip.id }
            activeClip = nil
            activeTrack = nil
            lastError = "Could not start audio input stream for \(selectedDevice.name): \(error.localizedDescription)"
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.restartSilentCaptureStreamIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) { [weak self] in
            guard let self, self.recording, self.receivedInputBuffers == 0 else { return }
            self.lastError = "No audio input callbacks received from \(self.selectedInputDeviceName). Check mic permission, selected device/channel, and whether another app is holding the interface."
        }
    }

    private func startHALCapture(device: AudioInputDevice, channel: Int) throws {
        stopCaptureEngine()

        // 1) Instantiate the HAL output unit (AUHAL).
        var acd = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &acd) else { throw AudioRecorderError.noComponent }
        var unitOpt: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &unitOpt), "AudioComponentInstanceNew")
        guard let unit = unitOpt else { throw AudioRecorderError.noComponent }
        captureUnit = unit

        // 2) Enable input (element/bus 1), disable output (element/bus 0).
        var enable: UInt32 = 1
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, UInt32(MemoryLayout<UInt32>.size)), "EnableIO input")
        var disable: UInt32 = 0
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable, UInt32(MemoryLayout<UInt32>.size)), "DisableIO output")

        // 3) Bind the exact device (must come AFTER EnableIO). Falls back to the
        //    current default input device when no specific one is chosen/resolved.
        var deviceID: AudioDeviceID = 0
        if device.uid != Self.systemDefaultDeviceUID, let resolved = Self.deviceID(forUID: device.uid) {
            deviceID = resolved
        } else {
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
            if device.uid != Self.systemDefaultDeviceUID {
                lastError = "Could not resolve \(device.name); capturing from the current default input instead."
            }
        }
        guard deviceID != 0 else { throw AudioRecorderError.noInputFormat }
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)), "CurrentDevice")

        // 4) Discover the device's hardware input format (input scope, bus 1).
        var hwFormat = AudioStreamBasicDescription()
        var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hwFormat, &fmtSize), "get hw StreamFormat")
        let hwChannels = max(1, Int(hwFormat.mChannelsPerFrame))
        let rate = hwFormat.mSampleRate > 0 ? hwFormat.mSampleRate : max(8000, engine.sampleRate)
        captureChannels = hwChannels
        captureChannelIndex = min(max(0, channel), hwChannels - 1)
        captureRate = rate

        // 5) Ask the AUHAL's built-in converter for de-interleaved Float32 at the
        //    device rate (one buffer per channel). Set on the OUTPUT scope of bus 1.
        let bytesPerSample = UInt32(MemoryLayout<Float>.size)
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: rate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: bytesPerSample,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerSample,
            mChannelsPerFrame: UInt32(hwChannels),
            mBitsPerChannel: bytesPerSample * 8,
            mReserved: 0)
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &clientFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "set client StreamFormat")

        // 6) Bound the slice size and pre-allocate the render buffer list.
        var maxFrames: UInt32 = 4096
        var mfSize = UInt32(MemoryLayout<UInt32>.size)
        AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, &mfSize)
        captureMaxFrames = max(512, maxFrames)
        let abl = AudioBufferList.allocate(maximumBuffers: hwChannels)
        for i in 0..<hwChannels {
            let bytes = Int(captureMaxFrames) * Int(bytesPerSample)
            abl[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes),
                                 mData: malloc(bytes))
        }
        captureABL = abl

        // 7) Install the input callback and start.
        var cb = AURenderCallbackStruct(inputProc: captureInputCallback,
                                        inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "SetInputCallback")
        try check(AudioUnitInitialize(unit), "AudioUnitInitialize")
        try check(AudioOutputUnitStart(unit), "AudioOutputUnitStart")
    }

    /// Called from the realtime render-callback thread. Pulls the available input
    /// into our buffer list, copies the selected channel, appends it to the take.
    fileprivate func renderInput(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                                 timestamp: UnsafePointer<AudioTimeStamp>,
                                 bus: UInt32, frames: UInt32) -> OSStatus {
        guard recording, let unit = captureUnit, let abl = captureABL else { return noErr }
        guard frames > 0, frames <= captureMaxFrames else { return noErr }
        let byteSize = frames * UInt32(MemoryLayout<Float>.size)
        for i in 0..<abl.count { abl[i].mDataByteSize = byteSize }
        let status = AudioUnitRender(unit, flags, timestamp, bus, frames, abl.unsafeMutablePointer)
        guard status == noErr else { return status }
        let src = min(max(0, captureChannelIndex), abl.count - 1)
        guard let raw = abl[src].mData else { return noErr }
        let ptr = raw.bindMemory(to: Float.self, capacity: Int(frames))
        receivedInputBuffers += 1
        var block = [Float](repeating: 0, count: Int(frames))
        var peak: Float = 0
        for f in 0..<Int(frames) {
            let s = ptr[f]
            block[f] = s
            let a = abs(s); if a > peak { peak = a }
        }
        appendCapturedBlock(block, peak: peak)
        return noErr
    }

    private func appendCapturedBlock(_ block: [Float], peak: Float) {
        guard !block.isEmpty else { return }
        captureLock.lock()
        captured.append(contentsOf: block)
        let sampleCount = captured.count
        // Throttle the live-waveform push to ~12 Hz. We show the FULL take so far
        // (not just the last 0.7s tail) so the start of the take is visible while
        // recording — otherwise a short take like "Bankai!" displays as "ankai!".
        let now = CFAbsoluteTimeGetCurrent()
        let shouldPush = (now - lastPreviewPushTime) > 0.08
        let preview: [Float]? = shouldPush ? captured : nil
        if shouldPush { lastPreviewPushTime = now }
        captureLock.unlock()
        level = level * 0.8 + peak * 0.2
        if let preview, let clip = activeClip {
            let seconds = Double(sampleCount) / max(1.0, captureRate)
            DispatchQueue.main.async { [weak self, weak clip] in
                // Only update while this exact clip is still the active take, so a
                // late callback can't clobber the committed take after stop().
                guard let self, let clip, self.recording, clip === self.activeClip else { return }
                clip.samples = preview
                clip.sampleRate = self.captureRate
                clip.lengthBeatsOverride = max(0.25, seconds * self.engine.transport.tempo / 60.0)
            }
        }
    }

    private func recentSamplesPreview(limit: Int) -> ArraySlice<Float> {
        captureLock.lock(); defer { captureLock.unlock() }
        let start = max(0, captured.count - limit)
        return captured[start..<captured.count]
    }

    private func restartSilentCaptureStreamIfNeeded() {
        guard recording, receivedInputBuffers == 0, !captureRestartAttempted else { return }
        captureRestartAttempted = true
        guard let track = activeTrack else { return }
        let selected = device(for: track.audioInputDeviceUID ?? selectedDeviceUID)
        stopCaptureEngine()
        do {
            try startHALCapture(device: selected, channel: track.audioInputChannelIndex)
            lastError = [lastError, "Input stream was silent at start; reopened capture once on \(selected.name)."].compactMap { $0 }.joined(separator: " ")
        } catch {
            lastError = "Could not reopen silent input stream: \(error.localizedDescription)"
        }
    }

    private func stopCaptureEngine() {
        if let unit = captureUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        captureUnit = nil
        if let abl = captureABL {
            for i in 0..<abl.count { free(abl[i].mData) }
            free(abl.unsafeMutablePointer)
        }
        captureABL = nil
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else {
            lastError = "Recorder \(what) failed (CoreAudio \(status))."
            throw AudioRecorderError.coreAudioStatus(status)
        }
    }

    private func removeStaleEmptyRecordingClips(on track: Track, nearBeat: Double) {
        track.audioClips.removeAll { clip in
            clip.displayName.hasPrefix("Recording ·") &&
            clip.samples.isEmpty &&
            abs(clip.startBeat - nearBeat) < 1.0 &&
            (clip.lengthBeatsOverride ?? 0.25) <= 0.35
        }
    }

    /// Stop and append the captured audio to `track`.
    @discardableResult
    public func stop(commitTo track: Track) -> AudioClip? {
        guard recording else { return nil }
        recording = false
        stopProgressTimer()
        stopCaptureEngine()
        level = 0
        let commitTrack = activeTrack ?? track
        let clip = activeClip ?? AudioClip(startBeat: startBeat, samples: [], sampleRate: captureRate)
        if activeClip == nil { commitTrack.audioClips.append(clip) }
        captureLock.lock()
        let finalSamples = captured
        captureLock.unlock()
        clip.samples = finalSamples
        clip.sampleRate = captureRate
        let deviceName = track.audioInputDeviceName.isEmpty ? selectedInputDeviceName : track.audioInputDeviceName
        clip.displayName = "Recording · \(deviceName) · \(channelLabel(for: track.audioInputChannelIndex, deviceUID: track.audioInputDeviceUID))"
        let audioSeconds = Double(finalSamples.count) / max(1.0, captureRate)
        let wallSeconds = max(0, Date().timeIntervalSince(recordingStartedAt ?? Date()))
        let seconds = max(audioSeconds, wallSeconds)
        clip.lengthBeatsOverride = max(0.25, seconds * engine.transport.tempo / 60.0)
        activeClip = nil
        activeTrack = nil
        recordingStartedAt = nil
        // No audio actually arrived → remove the provisional region entirely rather
        // than leaving an empty "twin blank" clip on the timeline, and surface why.
        if finalSamples.isEmpty {
            commitTrack.audioClips.removeAll { $0.id == clip.id }
            let detail = receivedInputBuffers == 0
                ? "No input was received from \(deviceName). Check macOS mic permission (System Settings ▸ Privacy ▸ Microphone), the selected device/channel, and that no other app holds the interface."
                : "The selected channel was silent on \(deviceName)."
            lastError = "Recording created an empty take — discarded it. \(detail)"
            return nil
        }
        return clip
    }

    public func cancel() {
        guard recording else { return }
        recording = false
        stopProgressTimer()
        stopCaptureEngine()
        if let clip = activeClip, let track = activeTrack {
            track.audioClips.removeAll { $0.id == clip.id }
        }
        activeClip = nil
        activeTrack = nil
        captureLock.lock()
        captured.removeAll()
        captureLock.unlock()
        recordingStartedAt = nil
        level = 0
    }

    private func startProgressTimer(for clip: AudioClip) {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self, weak clip] _ in
            guard let self, self.recording, let clip else { return }
            self.captureLock.lock()
            let sampleCount = self.captured.count
            self.captureLock.unlock()
            let audioSeconds = Double(sampleCount) / max(1.0, self.captureRate)
            let wallSeconds = max(0, Date().timeIntervalSince(self.recordingStartedAt ?? Date()))
            let seconds = max(audioSeconds, wallSeconds)
            clip.lengthBeatsOverride = max(0.25, seconds * self.engine.transport.tempo / 60.0)
        }
        RunLoop.main.add(progressTimer!, forMode: .common)
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}


private enum AudioRecorderError: LocalizedError {
    case coreAudioStatus(OSStatus)
    case noInputFormat
    case noComponent
    var errorDescription: String? {
        switch self {
        case .coreAudioStatus(let status): return "CoreAudio status \(status)"
        case .noInputFormat: return "The selected input device reported no usable audio format."
        case .noComponent: return "Could not create the CoreAudio HAL input unit."
        }
    }
}

/// C-ABI render callback for the AUHAL input unit. CoreAudio invokes this on its
/// realtime input thread; we hop straight into the recorder instance carried in
/// `inRefCon` and pull the available frames.
private let captureInputCallback: AURenderCallback = { inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, _ in
    let recorder = Unmanaged<AudioRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
    return recorder.renderInput(flags: ioActionFlags, timestamp: inTimeStamp, bus: inBusNumber, frames: inNumberFrames)
}

private extension AudioRecorder {
    static func enumerateInputDevices(defaultUID: String?) -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let channels = inputChannelCount(for: id)
            guard channels > 0 else { return nil }
            let uid = stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceUID) ?? "coreaudio-device-\(id)"
            let name = stringProperty(deviceID: id, selector: kAudioObjectPropertyName) ?? "Input Device \(id)"
            return AudioInputDevice(uid: uid, name: name, channelCount: channels, isDefault: uid == defaultUID)
        }
        .sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault && !rhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func currentDefaultInputDeviceUID() -> String? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &deviceID) == noErr, deviceID != 0 else { return nil }
        return stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    static func makeDefaultInputDevice(uid: String) -> Bool {
        guard let deviceID = deviceID(forUID: uid) else { return false }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var mutableID = deviceID
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID)
        return status == noErr
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        enumerateInputDevices(defaultUID: nil).first { $0.uid == uid }.flatMap { device in
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var dataSize: UInt32 = 0
            let system = AudioObjectID(kAudioObjectSystemObject)
            guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return nil }
            let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
            var ids = [AudioDeviceID](repeating: 0, count: count)
            guard AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, &ids) == noErr else { return nil }
            return ids.first { stringProperty(deviceID: $0, selector: kAudioDevicePropertyDeviceUID) == device.uid }
        }
    }

    static func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value as String
    }

    static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, abl) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
