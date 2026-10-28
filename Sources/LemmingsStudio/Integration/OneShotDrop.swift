import Foundation
import AppKit
import UniformTypeIdentifiers

// A file URL has priority over a provider's display-name text. Promised files
// are copied while the provider callback still owns their temporary location.
enum OneShotDrop {
    static var library:URL {
        if let configured=ProcessInfo.processInfo.environment["LEMMINGS_SAMPLE_LIBRARY"] {return URL(fileURLWithPath:configured,isDirectory:true)}
        let parts=Bundle.main.bundleURL.pathComponents
        if parts.count>2 && parts[1]=="Volumes" {return URL(fileURLWithPath:"/Volumes/\(parts[2])/LemmingsStudio/Content/OneShots",isDirectory:true)}
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LemmingsStudio/OneShots",isDirectory:true)
    }
    static func stabilize(_ url:URL)throws->URL {
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        guard url.isFileURL,try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile==true else {throw NSError(domain:"OneShotDrop",code:1,userInfo:[NSLocalizedDescriptionKey:"Drop an audio file, not a folder or web link"])}
        let folder=library.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let copy=folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at:url,to:copy);return copy
    }
    static func accept(_ providers:[NSItemProvider],onURL:@escaping(URL)->Void,onText:@escaping(String)->Void,onError:@escaping(String)->Void)->Bool {
        func fail(_ error:Error?){DispatchQueue.main.async{onError(error?.localizedDescription ?? "The drop did not contain a readable audio file")}}
        func deliver(_ url:URL){do {let stable=try stabilize(url);DispatchQueue.main.async{onURL(stable)}}catch{fail(error)}}
        func text(_ provider:NSItemProvider){
            provider.loadObject(ofClass:NSString.self){object,error in
                guard let value=object as? String else {fail(error);return}
                DispatchQueue.main.async{onText(value.trimmingCharacters(in:.whitespacesAndNewlines.union(.controlCharacters)))}
            }
        }
        func file(_ provider:NSItemProvider){
            guard let type=provider.registeredTypeIdentifiers.first(where:{UTType($0)?.conforms(to:.audio)==true}) else {text(provider);return}
            provider.loadFileRepresentation(forTypeIdentifier:type){url,error in guard let url else {fail(error);return};deliver(url)}
        }
        func objectURL(_ provider:NSItemProvider){
            guard provider.canLoadObject(ofClass:NSURL.self) else {file(provider);return}
            provider.loadObject(ofClass:NSURL.self){object,_ in
                if let url=object as? URL,url.isFileURL {deliver(url)}else{file(provider)}
            }
        }
        if let provider=providers.first(where:{$0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)}) {
            provider.loadDataRepresentation(forTypeIdentifier:UTType.fileURL.identifier){data,_ in
                if let data,let raw=String(data:data,encoding:.utf8){
                    let clean=raw.trimmingCharacters(in:.whitespacesAndNewlines.union(.controlCharacters))
                    if let url=URL(string:clean),url.isFileURL {deliver(url);return}
                    if FileManager.default.fileExists(atPath:clean) {deliver(URL(fileURLWithPath:clean));return}
                }
                objectURL(provider)
            };return true
        }
        if let provider=providers.first(where:{$0.hasItemConformingToTypeIdentifier(UTType.audio.identifier)}) {file(provider);return true}
        if let provider=providers.first(where:{$0.canLoadObject(ofClass:NSString.self)}) {text(provider);return true}
        return false
    }
}
