import Foundation
import AVFoundation
import AudioToolbox

// Resolve Audio Units by their actual component identity. A bundle filename such
// as iZNeutron5AUHook is not the registered display name "iZotope: Neutron 5".
public enum AudioUnitCatalog {
    private static var retainedBundles:[String:CFBundle]=[:]
    private static var localIDs=Set<String>()
    private static func key(_ d:AudioComponentDescription)->String {"\(d.componentType).\(d.componentSubType).\(d.componentManufacturer)"}
    public static func isLocal(_ d:AudioComponentDescription)->Bool {localIDs.contains(key(d))}
    public static func fourCC(_ text:String)->UInt32 {text.utf8.prefix(4).reduce(0){($0<<8)|UInt32($1)}}
    public static func compact(_ text:String)->String {text.lowercased().filter{$0.isLetter || $0.isNumber}}
    public static func description(name:String,path:String?,identifier:String="")->AudioComponentDescription? {
        if let path,let bundle=Bundle(path:path),let entries=bundle.infoDictionary?["AudioComponents"] as? [[String:Any]],!entries.isEmpty {
            let wanted=compact(name)
            let selected=entries.first {compact($0["name"] as? String ?? "")==wanted} ?? entries.first!
            if let type=selected["type"] as? String,let subtype=selected["subtype"] as? String,let maker=selected["manufacturer"] as? String {
                var d=AudioComponentDescription(componentType:fourCC(type),componentSubType:fourCC(subtype),componentManufacturer:fourCC(maker),componentFlags:0,componentFlagsMask:0)
                if AudioComponentFindNext(nil,&d)==nil,let factoryName=selected["factoryFunction"] as? String,
                   let cf=CFBundleCreate(nil,URL(fileURLWithPath:path) as CFURL),CFBundleLoadExecutable(cf),
                   let ptr=CFBundleGetFunctionPointerForName(cf,factoryName as CFString) {
                    let factory=unsafeBitCast(ptr,to:AudioComponentFactoryFunction.self)
                    if AudioComponentRegister(&d,(selected["name"] as? String ?? name) as CFString,UInt32((selected["version"] as? NSNumber)?.uint32Value ?? 0),factory) != nil {
                        retainedBundles[path]=cf;localIDs.insert(key(d))
                    }
                }
                if AudioComponentFindNext(nil,&d) != nil {return d}
            }
        }
        let wanted=compact(name),short=compact(name.components(separatedBy:":").last ?? name)
        for type in [kAudioUnitType_MusicDevice,kAudioUnitType_MusicEffect,kAudioUnitType_Effect,kAudioUnitType_Generator] {
            var d=AudioComponentDescription();d.componentType=type
            if let component=AVAudioUnitComponentManager.shared().components(matching:d).first(where:{
                let c=compact($0.name),s=compact($0.name.components(separatedBy:":").last ?? $0.name)
                return !wanted.isEmpty && (c==wanted || s==short)
            }) {return component.audioComponentDescription}
        }
        return nil
    }
}
