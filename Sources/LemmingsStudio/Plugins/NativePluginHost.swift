import Foundation
import Darwin

private final class PluginHostABI {
    typealias Open = @convention(c) (UnsafePointer<CChar>?, Int32, Double, Int32, UnsafeMutablePointer<CChar>?, Int32) -> UnsafeMutableRawPointer?
    typealias Close = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Process = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?, Int32, Int32) -> Int32
    typealias Midi = @convention(c) (UnsafeMutableRawPointer?, UInt8, UInt8, UInt8) -> Int32
    typealias Count = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias Info = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafeMutablePointer<CChar>?, Int32, UnsafeMutablePointer<CChar>?, Int32) -> Int32
    typealias Get = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Float
    typealias Set = @convention(c) (UnsafeMutableRawPointer?, Int32, Float) -> Int32
    typealias State = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32) -> Int32
    typealias Restore = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32) -> Int32
    typealias Transport = @convention(c) (UnsafeMutableRawPointer?, Double, Double, Int32) -> Void
    let open: Open; let close: Close; let process: Process; let midi: Midi; let editor: Count
    let isInstrument:Count;let hide:Close; let count: Count; let info: Info; let get: Get; let set: Set; let state: State; let restore: Restore; let latency: Count; let transport: Transport
    private let library: UnsafeMutableRawPointer
    init() throws {
        let path = ProcessInfo.processInfo.environment["LEMMINGS_PLUGIN_HOST_LIBRARY"] ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/liblemmings_plugin_host.dylib").path
        guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { throw NSError(domain:"LemmingsPluginHost",code:1,userInfo:[NSLocalizedDescriptionKey:"Native plugin host could not load: \(String(cString:dlerror()))"]) }
        self.library = library
        func symbol<T>(_ name:String,_ type:T.Type) throws -> T {
            guard let ptr=dlsym(library,name) else {throw NSError(domain:"LemmingsPluginHost",code:2,userInfo:[NSLocalizedDescriptionKey:"Missing native plugin host symbol: \(name)"])}
            return unsafeBitCast(ptr,to:type)
        }
        open=try symbol("lp_open",Open.self);close=try symbol("lp_close",Close.self);process=try symbol("lp_process",Process.self);midi=try symbol("lp_midi",Midi.self);editor=try symbol("lp_editor",Count.self)
        isInstrument=try symbol("lp_is_instrument",Count.self);hide=try symbol("lp_hide_editor",Close.self);count=try symbol("lp_param_count",Count.self);info=try symbol("lp_param_info",Info.self);get=try symbol("lp_get",Get.self);set=try symbol("lp_set",Set.self);state=try symbol("lp_state",State.self);restore=try symbol("lp_restore",Restore.self);latency=try symbol("lp_latency",Count.self);transport=try symbol("lp_transport",Transport.self)
        let abi=try symbol("lp_abi",(@convention(c) () -> UInt32).self)
        guard abi()==1 else {throw NSError(domain:"LemmingsPluginHost",code:3,userInfo:[NSLocalizedDescriptionKey:"Native plugin host ABI mismatch"])}
        // The library remains loaded for the lifetime of the application. Vendor
        // editors and pending GUI callbacks may reference its code after a close.
    }
    static let shared: Result<PluginHostABI,Error> = Result { try PluginHostABI() }
}

public final class NativeHostedPlugin: Instrument, AudioEffect, InstrumentTarget {
    public let name:String
    public var displayName:String {name}
    public let kind:DeviceKind = .externalAudioEffect
    public var bypassed=false
    public let slotID:UUID
    public let slotPath:String
    public let maximum:Int
    public private(set) var automatableParams:[ParamInfo]=[]
    public var parameters:[PluginParam] {automatableParams.map{PluginParam(id:$0.id,name:$0.name,min:0,max:1)}}
    public var isInstrument:Bool {api.isInstrument(handle)==1}
    public var latencyFrames:Int {Int(api.latency(handle))}
    private let api:PluginHostABI
    private let handle:UnsafeMutableRawPointer
    private var indices:[String:Int32]=[:]
    private let monoRight:UnsafeMutablePointer<Float>
    public static var loadErrors:[UUID:String]=[:]

    public init?(slot:ExternalPluginSlot,sampleRate:Double,maxFrames:Int=4096) {
        guard Thread.isMainThread else {Self.loadErrors[slot.id]="Plugin creation requires the main thread";return nil}
        guard slot.format == .vst3 else {return nil}
        do {
            let api=try PluginHostABI.shared.get()
            var path=slot.path ?? ""
            if !FileManager.default.fileExists(atPath:path),slot.name.caseInsensitiveCompare("VoxGarden") == .orderedSame {
                path=Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/VoxGarden.vst3").path
            }
            guard !path.isEmpty,FileManager.default.fileExists(atPath:path) else {Self.loadErrors[slot.id]="Missing VST3: \(path)";return nil}
            var error=[CChar](repeating:0,count:2048)
            guard let handle=path.withCString({api.open($0,1,sampleRate,Int32(maxFrames),&error,Int32(error.count))}) else {Self.loadErrors[slot.id]=String(cString:error);return nil}
            self.api=api;self.handle=handle;self.name=slot.name;self.slotID=slot.id;self.slotPath=path;self.maximum=maxFrames
            self.monoRight = .allocate(capacity:maxFrames);monoRight.initialize(repeating:0,count:maxFrames)
            for i in 0..<api.count(handle) {
                var id=[CChar](repeating:0,count:512),label=[CChar](repeating:0,count:512)
                guard api.info(handle,i,&id,512,&label,512)==0 else {continue}
                let key=String(cString:id),title=String(cString:label)
                indices[key]=i;indices[title.lowercased()]=i
                automatableParams.append(ParamInfo(key,title,0,1))
            }
            if let saved=slot.presetStateBase64 {restorePresetStateBase64(saved)}
            Self.loadErrors.removeValue(forKey:slot.id)
        } catch {Self.loadErrors[slot.id]=error.localizedDescription;return nil}
    }
    deinit {api.close(handle);monoRight.deallocate()}
    public func hideEditor(){api.hide(handle)}
    public func showEditor() -> Bool {api.editor(handle)==0}
    public func capturedPresetStateBase64() -> String? {
        var size=api.state(handle,nil,0)
        for _ in 0..<3 {
            guard size>0 && size<=64*1024*1024 else {return nil}
            var data=Data(count:Int(size))
            let actual=data.withUnsafeMutableBytes{api.state(handle,$0.baseAddress,size)}
            if actual>0 && actual<=size {data.count=Int(actual);return data.base64EncodedString()}
            size=actual
        }
        return nil
    }
    public func restorePresetStateBase64(_ text:String?) {
        guard let text,let data=Data(base64Encoded:text),!data.isEmpty else {return}
        _=data.withUnsafeBytes{api.restore(handle,$0.baseAddress,Int32(data.count))}
    }
    public func setParam(_ id:String,_ value:Double) {guard value.isFinite,let index=indices[id] ?? indices[id.lowercased()] else {return};_ = api.set(handle,index,Float(value))}
    public func getParam(_ id:String)->Double {guard let index=indices[id] ?? indices[id.lowercased()] else {return 0};return Double(api.get(handle,index))}
    public func apply(_ design:SoundDesign)throws->String {for (id,value) in design.params {setParam(id,value)};return "Applied \(design.params.count) normalized parameters to the live \(name) instance"}
    public func setTransport(bpm:Double,beat:Double,playing:Bool){api.transport(handle,bpm,beat,playing ? 1:0)}
    public func renderStereo(left:UnsafeMutablePointer<Float>,right:UnsafeMutablePointer<Float>,frames:Int)->Bool {
        guard frames<=maximum else {return false}
        left.update(repeating:0,count:frames);right.update(repeating:0,count:frames)
        _=api.process(handle,left,right,Int32(frames),1);return true
    }
    public func render(into out:UnsafeMutablePointer<Float>,frames:Int){guard frames<=maximum else {out.update(repeating:0,count:frames);return};_ = renderStereo(left:out,right:monoRight,frames:frames);for i in 0..<frames {out[i]=(out[i]+monoRight[i]) * 0.5}}
    public func process(_ left:UnsafeMutablePointer<Float>,_ right:UnsafeMutablePointer<Float>,frames:Int){guard !bypassed,frames<=maximum else {return};_ = api.process(handle,left,right,Int32(frames),0)}
    private func send(_ status:UInt8,_ a:Int,_ b:Int){_ = api.midi(handle,status,UInt8(clamping:a),UInt8(clamping:b))}
    public func noteOn(_ note:Int,velocity:Float){noteOn(note,velocity:velocity,channel:0)}
    public func noteOff(_ note:Int){noteOff(note,channel:0)}
    public func noteOn(_ note:Int,velocity:Float,channel:Int){send(0x90|UInt8(channel&15),note,Int(max(0,min(1,velocity))*127))}
    public func noteOff(_ note:Int,channel:Int){send(0x80|UInt8(channel&15),note,0)}
    public func allNotesOff(){for ch in 0..<16 {send(0xB0|UInt8(ch),120,0);send(0xB0|UInt8(ch),123,0)}}
    public func pitchBend(_ value:Float,channel:Int,rangeSemitones:Int){let v=Int((max(-1,min(1,value))+1)*8191.5);send(0xE0|UInt8(channel&15),v&127,(v>>7)&127)}
    public func pressure(_ value:Float,note:Int?,channel:Int){if let note {send(0xA0|UInt8(channel&15),note,Int(value*127))}else{send(0xD0|UInt8(channel&15),Int(value*127),0)}}
    public func timbre(_ value:Float,channel:Int){send(0xB0|UInt8(channel&15),74,Int(value*127))}
    public func reset(){allNotesOff()}
}

public final class UnavailablePluginInstrument:Instrument {
    public let name:String
    public init(name:String){self.name=name}
    public func render(into out:UnsafeMutablePointer<Float>,frames:Int){out.update(repeating:0,count:frames)}
    public func noteOn(_ note:Int,velocity:Float){}
    public func noteOff(_ note:Int){}
    public func allNotesOff(){}
}
