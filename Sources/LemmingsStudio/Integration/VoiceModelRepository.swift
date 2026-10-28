import Foundation
import Observation

public enum VoiceModelLicense: String, CaseIterable, Identifiable, Codable, Sendable { case consentVerified="Consent-verified", publicDomain="Public domain", userOwned="User-owned import", researchOnly="Research-only"; public var id:String{rawValue} }
public struct SingingVoiceModel: Identifiable, Hashable, Codable, Sendable {
    public let id:String; public var name:String; public var style:String; public var languageHints:[String]; public var license:VoiceModelLicense; public var sourceURL:String; public var sha256:String?; public var installedPath:String?; public var notes:String
    public init(id:String,name:String,style:String,languageHints:[String],license:VoiceModelLicense,sourceURL:String,sha256:String?=nil,installedPath:String?=nil,notes:String){self.id=id;self.name=name;self.style=style;self.languageHints=languageHints;self.license=license;self.sourceURL=sourceURL;self.sha256=sha256;self.installedPath=installedPath;self.notes=notes}
}

@MainActor @Observable public final class VoiceModelStore {
    public var repository:[SingingVoiceModel]=VoiceModelStore.ethicalStarterRepository
    public var imported:[SingingVoiceModel]=[]
    public var status="Voice model system ready"
    public var cloneConsentChecked=false
    public var cloneDatasetGuidanceAccepted=false
    public var runtime=RVCRuntimeManager.shared
    private let manifestURL:URL
    public init(){manifestURL=RVCRuntimeManager.shared.rootURL.appendingPathComponent("models.json");loadImportedModels()}
    public static let ethicalStarterRepository:[SingingVoiceModel]=[
        SingingVoiceModel(id:"starter-neutral-pop",name:"Neutral Pop Guide",style:"clean pop guide vocal",languageHints:["en"],license:.consentVerified,sourceURL:"builtin://neutral-pop-guide",notes:"Catalogue slot only. Import a consent-cleared RVC .pth model before rendering."),
        SingingVoiceModel(id:"starter-classical-a",name:"Classical Aakar Guide",style:"open vowel classical guide",languageHints:["hi","sa","en"],license:.consentVerified,sourceURL:"builtin://classical-aakar-guide",notes:"Catalogue slot only. Import a consent-cleared RVC .pth model before rendering."),
        SingingVoiceModel(id:"starter-folk-dhol-vocal",name:"Folk Call Guide",style:"folk call-and-response",languageHints:["pa","hi"],license:.consentVerified,sourceURL:"builtin://folk-call-guide",notes:"Catalogue slot only. Import a consent-cleared RVC .pth model before rendering.")]
    public func importModel(at url:URL){
        do{let src=url.standardizedFileURL;let pth=try findModelFile(in:src);let idx=findIndexFile(near:pth,sourceRoot:src);let dest=uniqueModelDirectory(named:sanitizedName(src.deletingPathExtension().lastPathComponent));try FileManager.default.createDirectory(at:dest,withIntermediateDirectories:true);try FileManager.default.copyItem(at:pth,to:dest.appendingPathComponent(pth.lastPathComponent));if let idx{try FileManager.default.copyItem(at:idx,to:dest.appendingPathComponent(idx.lastPathComponent))};let model=SingingVoiceModel(id:"user-"+UUID().uuidString.lowercased(),name:src.deletingPathExtension().lastPathComponent,style:"Imported RVC",languageHints:[],license:.userOwned,sourceURL:src.absoluteString,installedPath:dest.path,notes:idx==nil ? "Managed .pth import without a retrieval index." : "Managed RVC model and retrieval index.");imported.append(model);persistImportedModels();status="Imported RVC model: \(model.name)"}catch{status="⚠️ RVC model import failed: \(error.localizedDescription)"}
    }
    public func removeImportedModel(_ model:SingingVoiceModel){if let p=model.installedPath{try? FileManager.default.removeItem(at:URL(fileURLWithPath:p))};imported.removeAll{$0.id==model.id};persistImportedModels();status="Removed voice model: \(model.name)"}
    public func transform(inputAudio:URL,using model:SingingVoiceModel,outputDirectory:URL,bundledPython:URL?) async -> URL? {
        guard cloneConsentChecked else{status="Confirm rights/consent before voice conversion.";return nil};guard let path=model.installedPath,FileManager.default.fileExists(atPath:path) else{status="Import a real consent-cleared RVC .pth model before rendering.";return nil}
        let out=outputDirectory.appendingPathComponent(inputAudio.deletingPathExtension().lastPathComponent+"_"+sanitizedName(model.name)+"_RVC.wav");var o=RVCConversionOptions();o.pitchShift=runtime.pitchShift;o.f0Method=runtime.selectedF0Method;o.indexRate=runtime.indexRate;o.filterRadius=runtime.filterRadius;o.rmsMixRate=runtime.rmsMixRate;o.protect=runtime.protect
        do{let r=try await runtime.convert(inputAudio:inputAudio,modelPath:URL(fileURLWithPath:path),outputURL:out,options:o);status="Rendered RVC voice transform: \(r.lastPathComponent)";return r}catch{status="⚠️ RVC voice transform failed: \(error.localizedDescription)";return nil}
    }
    private func loadImportedModels(){guard let d=try? Data(contentsOf:manifestURL),let x=try? JSONDecoder().decode([SingingVoiceModel].self,from:d) else{return};imported=x.filter{if let p=$0.installedPath{return FileManager.default.fileExists(atPath:p)};return false}}
    private func persistImportedModels(){if let d=try? JSONEncoder().encode(imported){try? d.write(to:manifestURL,options:.atomic)}}
    private func findModelFile(in src:URL)throws->URL{if src.pathExtension.lowercased()=="pth"{return src};guard let e=FileManager.default.enumerator(at:src,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles]) else{throw NSError(domain:"RVC",code:1,userInfo:[NSLocalizedDescriptionKey:"No .pth model found"])};while let u=e.nextObject() as? URL{if u.pathExtension.lowercased()=="pth"{return u}};throw NSError(domain:"RVC",code:1,userInfo:[NSLocalizedDescriptionKey:"No .pth model found"])}
    private func findIndexFile(near model:URL,sourceRoot:URL)->URL?{for root in [model.deletingLastPathComponent(),sourceRoot] where root.hasDirectoryPath{if let fs=try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil),let i=fs.first(where:{$0.pathExtension.lowercased()=="index"}){return i}};return nil}
    private func uniqueModelDirectory(named base:String)->URL{var u=runtime.modelsURL.appendingPathComponent(base,isDirectory:true);var n=2;while FileManager.default.fileExists(atPath:u.path){u=runtime.modelsURL.appendingPathComponent("\(base)-\(n)",isDirectory:true);n+=1};return u}
    private func sanitizedName(_ s:String)->String{let a=CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-_"));return String(s.unicodeScalars.map{a.contains($0) ? Character(String($0)) : "_"}).trimmingCharacters(in:CharacterSet(charactersIn:"_"))}
}
public enum VoiceCloneGuide { public static let minimumGuidance="Record at least 10 minutes of clean, consented singing; 30 minutes is recommended. Keep takes dry and mono."; public static let requiredConsent="Only clone your own voice or a vocalist who gave explicit, written permission." }
