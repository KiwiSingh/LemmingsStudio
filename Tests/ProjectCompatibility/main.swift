import Foundation
import SwiftUI
import AppKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let project = Project()
let track = Track(name: "Same name", kind: .drums, color: .blue)
let other = Track(name: "Same name", kind: .analog, color: .green)
let device = DeviceModel(kind: .compressor)
device.sidechainEnabled = true
device.sidechainInputTrackID = other.id
track.devices = [device]
track.clips = [Clip(name: "Pattern", startBeat: 0, lengthBeats: 4,
                    notes: [ClipNote(pitch: 36, start: 0, length: 0.25)])]
track.automationLanes = [AutomationLane(nodeID: device.nodeID, paramID: "threshold", points: [])]
track.sequencerPrintTargetTrackID = other.id
project.tracks = [track, other]
project.groups = [TrackGroup(name: "Group", trackIDs: [track.id, other.id])]
track.groupID = project.groups[0].id
track.drumGenre = .rock
track.stepPattern.setHit(step: 0, note: 36, enabled: true)
track.stepPattern.setHit(step: 0, note: 42, enabled: true)
project.swingAmount = 0.2
project.customChannelCount = 12
project.channelNames = ["Front L", "Front R"]
project.masterDevices = [DeviceModel(kind: .utility, params: ["gain": -3])]
let encoded = try ProjectDocument(project: project).encoded()
let restored = try ProjectDocument.decode(encoded).makeProject()
require(restored.tracks[0].id == track.id, "Track ID lost")
require(restored.tracks[0].devices[0].id == device.id, "Device ID lost")
require(restored.tracks[0].devices[0].sidechainInputTrackID == restored.tracks[1].id, "Sidechain disconnected")
require(restored.tracks[0].automationLanes[0].nodeID == restored.tracks[0].devices[0].nodeID, "Automation disconnected")
require(restored.groups[0].trackIDs == restored.tracks.map { $0.id }, "Group disconnected")
require(restored.tracks[0].groupID == restored.groups[0].id, "Group audio routing disconnected")
require(restored.tracks[0].drumGenre == .rock, "Drum kit changed on reopen")
require(restored.tracks[0].stepPattern.notes(atStep: 0) == [36, 42], "Simultaneous drum hits lost")
require(restored.tracks[0].clips[0].id == track.clips[0].id, "Clip ID lost")
require(restored.tracks[0].clips[0].notes[0].id == track.clips[0].notes[0].id, "Note ID lost")
require(restored.tracks[0].sequencerLayers[0].id == track.sequencerLayers[0].id, "Layer ID lost")
require(restored.tracks[0].sequencerPrintTargetTrackID == other.id, "Print target lost")
require(restored.masterDevices[0].id == project.masterDevices[0].id, "Master device lost")
require(restored.swingAmount == project.swingAmount && restored.customChannelCount == 12, "Global state lost")
require(restored.channelNames == project.channelNames, "Channel names lost")
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try encoded.write(to: output)
// A v2 document without IDs remains readable; there is no safe inference for lost references.
var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
legacy["version"] = 2
var tracks = legacy["tracks"] as! [[String: Any]]
tracks[0].removeValue(forKey: "id")
legacy["tracks"] = tracks
let legacyData = try JSONSerialization.data(withJSONObject: legacy)
let old = try ProjectDocument.decode(legacyData).makeProject()
require(old.tracks.count == 2, "Legacy document rejected")
legacy["version"] = 999
let future = try JSONSerialization.data(withJSONObject: legacy)
do {
    _ = try ProjectDocument.decode(future)
    fatalError("Future document version accepted")
} catch { }
print("PASS: Swift identity, relationships, master state, legacy read and future-version rejection")

// Unknown data follows object identity through reorder and optional-field clearing.
var extended = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
extended["futureRoot"] = ["preserve": true]
var extendedTracks = extended["tracks"] as! [[String: Any]]
extendedTracks[0]["futureTrack"] = "first track"
var extendedDevices = extendedTracks[0]["devices"] as! [[String: Any]]
extendedDevices[0]["futureDevice"] = ["opaque": "state"]
extendedTracks[0]["devices"] = extendedDevices
extended["tracks"] = extendedTracks
let input = try JSONSerialization.data(withJSONObject: extended)
let editable = try ProjectDocument.decode(input).makeProject()
editable.tracks[0].devices[0].sidechainInputTrackID = nil
editable.tracks.reverse()
let preserved = try ProjectDocument(project: editable).encoded()
let tree = try JSONSerialization.jsonObject(with: preserved) as! [String: Any]
require(tree["futureRoot"] != nil, "Unknown root field lost")
let savedTracks = tree["tracks"] as! [[String: Any]]
require(savedTracks[1]["futureTrack"] as? String == "first track", "Unknown data followed array index")
let savedDevice = (savedTracks[1]["devices"] as! [[String: Any]])[0]
require(savedDevice["futureDevice"] != nil, "Unknown device state lost")
require(savedDevice["sidechainInputTrackID"] == nil, "Cleared optional reference resurrected")
if CommandLine.arguments.count == 4 {
    let received = try ProjectDocument.decode(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))).makeProject()
    try ProjectDocument(project: received).encoded().write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
}
print("PASS: Unknown fields, reordered identities and cleared optional state")
// Exact Swift audio references; no reimplementation inside the test oracle.
let audioDirectory = output.deletingLastPathComponent().appendingPathComponent("drum-reference")
try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
for rate in [44100.0, 48000.0, 96000.0] {
    for profile in 0...1 {
        var params = DrumVoiceParams()
        if profile == 1 { params.tune = 0.83; params.decay = 0.7; params.tone = 1.2; params.drive = 1.7; params.level = 0.6 }
        for id in DrumVoiceID.allCases {
            let voice = DrumVoice(sampleRate: rate)
            voice.trigger(id, params: params, velocity: 0.8)
            let samples = (0..<Int(rate * 1.5)).map { _ in voice.render() }
            let bytes = samples.withUnsafeBufferPointer { Data(buffer: $0) }
            try bytes.write(to: audioDirectory.appendingPathComponent("\(Int(rate))-\(profile)-\(id.rawValue).f32"))
        }
    }
}
print("PASS: Exported all ten actual Swift drum voices at three sample rates and two parameter profiles")

// Export exact visual/parameter reference values for the Python presentation.
var workspaceReference: [String: Any] = ["referenceSystemMajor":ProcessInfo.processInfo.operatingSystemVersion.majorVersion]
var themeRows: [[String: Any]] = []
for theme in LemmingsVisualTheme.allCases {
    let p = LSTheme.palette(for: theme)
    let fields: [(String, Color)] = [("backgroundA",p.backgroundA),("backgroundB",p.backgroundB),("backgroundC",p.backgroundC),("glowA",p.glowA),("glowB",p.glowB),("panel",p.panel),("panel2",p.panel2),("grid",p.grid),("text",p.text),("dim",p.dim),("play",p.play),("record",p.record),("focus",p.focus),("glassStroke",p.glassStroke),("glassHighlight",p.glassHighlight)]
    var palette: [String: String] = [:]
    for (key, value) in fields {
        let color = NSColor(value).usingColorSpace(.sRGB)!
        palette[key] = String(format: "#%02x%02x%02x%02x", Int((color.alphaComponent*255).rounded()), Int((color.redComponent*255).rounded()), Int((color.greenComponent*255).rounded()), Int((color.blueComponent*255).rounded()))
    }
    themeRows.append(["name":theme.rawValue,"glyph":theme.logoGlyph,"palette":palette])
}
workspaceReference["semanticPaletteFields"] = [
    "Liquid Glass":["glowA":"cyan","glowB":"purple"],
    LemmingsVisualTheme.cyberpunkNightCity.rawValue:["grid":"yellow","glassStroke":"yellow","glassHighlight":"cyan"]
]
let semanticColors: [(String,Color)] = [("blue",.blue),("orange",.orange),("green",.green),("pink",.pink),("purple",.purple),("teal",.teal),("red",.red),("yellow",.yellow),("cyan",.cyan)]
workspaceReference["systemColors"] = Dictionary(uniqueKeysWithValues: semanticColors.map { name,color in
    let c=NSColor(color).usingColorSpace(.sRGB)!
    return (name,String(format:"#%02x%02x%02x",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded())))
})
workspaceReference["themes"] = themeRows
workspaceReference["trackColors"] = [Color.blue,Color.orange,Color.green,Color.pink,Color.purple,Color.teal,Color.red,Color.yellow].map { value -> String in
    let c=NSColor(value).usingColorSpace(.sRGB)!
    return String(format:"#%02x%02x%02x",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded()))
}
workspaceReference["devices"] = DeviceKind.allCases.map { kind -> [String: Any] in
    let params = kind.isBuiltInTrackInstrument ? DeviceFactory.builtInInstrumentParams(for: kind) : DeviceFactory.make(kind).automatableParams
    return ["kind":kind.rawValue,"role":kind.role.rawValue,"category":kind.browserCategory,
            "defaults":DeviceFactory.defaults(for: kind),"params":params.map { ["id":$0.id,"name":$0.name,"min":$0.min,"max":$0.max,"unit":$0.unit,"log":$0.isLog] as [String: Any] }]
}
workspaceReference["scales"] = ScaleLibrary.all.map { ["name": $0.name, "intervals": $0.intervals] as [String: Any] }
workspaceReference["drumKits"] = Dictionary(uniqueKeysWithValues: DrumGenre.allCases.map { genre in
    (genre.rawValue, Dictionary(uniqueKeysWithValues: DrumKitLibrary.params(for: genre).map { id, p in
        (String(id.rawValue), ["tune":p.tune,"decay":p.decay,"tone":p.tone,"drive":Double(p.drive),"level":Double(p.level)])
    }))
})
workspaceReference["percussionLanes"] = BhangraToolkit.layers.map { ["name":$0.name,"note":$0.note,"source":$0.source.rawValue,"velocity":Double($0.velocity),"pan":Double($0.pan),"volume":Double($0.volume),"octaveOffset":$0.octaveOffset] as [String:Any] }
workspaceReference["percussionGrooves"] = BhangraToolkit.all.map { groove -> [String:Any] in
    ["name":groove.name,"bpm":groove.bpm,"notes":groove.steps.map { stroke in stroke.map {60+IndianStroke.allCases.firstIndex(of:$0)!} ?? -1 }]
}
let referenceBytes = try JSONSerialization.data(withJSONObject: workspaceReference, options: [.prettyPrinted, .sortedKeys])
try referenceBytes.write(to: output.deletingLastPathComponent().appendingPathComponent("workspace-reference.json"))
print("PASS: Exported original themes, device parameters and drum kits")

// Reused 24-voice slots retain noise RNG; repeated hits must match real kit behavior.
for rate in [44100.0,48000.0,96000.0] {
    let kit = DrumKit(genre: .rock, sampleRate: rate)
    let strideFrames = Int(rate * 0.007)
    var samples: [Float] = []
    for frame in 0..<Int(rate) {
        if frame % strideFrames == 0 && frame / strideFrames < 80 {
            let hit = frame / strideFrames
            kit.hit(DrumVoiceID(rawValue: hit % 10)!, velocity: Float(0.5 + Double(hit % 5) * 0.1))
        }
        var value: Float = 0
        kit.render(into: &value, frames: 1)
        samples.append(value)
    }
    try samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: audioDirectory.appendingPathComponent("kit-\(Int(rate)).f32"))
}
print("PASS: Exported actual Swift kit with 80 overlapping/retriggered hits")

for rate in [44100.0,48000.0,96000.0] {
    for profile in 0...1 {
        let limiter=LimiterEffect();limiter.setSampleRate(rate)
        if profile == 1 {limiter.ceilingDB = -2;limiter.thresholdDB = -8;limiter.releaseMS = 120;limiter.lookaheadMS = 5;limiter.softClip = 0.7;limiter.outputDB = -1}
        var left=(0..<Int(rate / 4)).map { Float(sin(Double($0) * 0.13) * 2.1) }
        var right=(0..<left.count).map { Float(cos(Double($0) * 0.17) * 1.8) }
        let input=zip(left,right).flatMap { [$0,$1] }
        try input.withUnsafeBufferPointer { Data(buffer:$0) }.write(to:audioDirectory.appendingPathComponent("limiter-input-\(Int(rate)).f32"))
        left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in limiter.process(l.baseAddress!,r.baseAddress!,frames:l.count) } }
        let stereo=zip(left,right).flatMap { [$0,$1] }
        try stereo.withUnsafeBufferPointer { Data(buffer:$0) }.write(to:audioDirectory.appendingPathComponent("limiter-\(Int(rate))-\(profile).f32"))
    }
}
print("PASS: Exported original stereo master limiter at three rates/two profiles")

// Original melodic instruments, including the actual random guitar excitations.
// Reflection is confined to this test harness; production Swift source is unchanged.
let melodicDirectory=output.deletingLastPathComponent().appendingPathComponent("instrument-reference")
try FileManager.default.createDirectory(at:melodicDirectory,withIntermediateDirectories:true)
var melodicManifest: [[String:Any]]=[]
for rate in [44100.0,48000.0,96000.0] {
    var events: [(Int,Int,Int,Float)] = [
        (0,1,48,0.8),(0,1,55,0.6),(0,1,60,0.9),
        (Int(rate*0.025),0,55,0),(Int(rate*0.05),1,60,0.3),
        (Int(rate*0.10),2,12,0.35)
    ]
    for note in 40..<60 { events.append((Int(rate*0.125),1,note,Float(0.5+Double(note%5)*0.1))) }
    for note in 40...72 { events.append((Int(rate*0.20),0,note,0)) }
    events += [(Int(rate*0.30),3,0,0),(Int(rate*0.45),1,72,0.8),(Int(rate*0.53),0,72,0)]
    for profile in 0...4 {
        let analog=AnalogSynth(sampleRate:rate)
        if profile>0 {
            analog.preset.osc1 = Waveform.allCases[(profile-1)%4]
            analog.preset.osc2 = Waveform.allCases[profile%4]
            analog.preset.cutoff=3400;analog.preset.resonance=0.88
            analog.preset.attack=0.02;analog.preset.decay=0.09;analog.preset.sustain=0.4
            analog.preset.release=0.07;analog.preset.detuneCents=23;analog.preset.osc2Mix=0.73;analog.preset.gain=0.42
        }
        let filename="analog-\(Int(rate))-\(profile)";var samples=[Float](repeating:0,count:Int(rate*1.5))
        var frame=0;var index=0
        while frame<samples.count {
            while index<events.count && events[index].0==frame {
                let e=events[index]
                if e.1==1 {analog.noteOn(e.2,velocity:e.3)}
                else if e.1==0 {analog.noteOff(e.2)}
                else if e.1==2 {analog.pitchBend(e.3,channel:0,rangeSemitones:e.2)}
                else {analog.allNotesOff()}
                index+=1
            }
            let end=min(samples.count,frame+128,index<events.count ? events[index].0 : samples.count)
            samples.withUnsafeMutableBufferPointer { analog.render(into:$0.baseAddress!.advanced(by:frame),frames:end-frame) };frame=end
        }
        try samples.withUnsafeBufferPointer { Data(buffer:$0) }.write(to:melodicDirectory.appendingPathComponent(filename+".f32"))
        var parameters=Dictionary(uniqueKeysWithValues:analog.automatableParams.map { ($0.id,analog.getParam($0.id)) })
        parameters["osc1"]=Double(Waveform.allCases.firstIndex(of:analog.preset.osc1)!)
        parameters["osc2"]=Double(Waveform.allCases.firstIndex(of:analog.preset.osc2)!)
        melodicManifest.append(["file":filename,"kind":"Analog Synth","rate":Int(rate),"frames":samples.count,"parameters":parameters,
            "events":events.map { [$0.0,$0.1,$0.2,Double($0.3)] as [Any] }])
    }
    let guitar=GuitarInstrument(sampleRate:rate);let filename="guitar-\(Int(rate))"
    var samples=[Float](repeating:0,count:Int(rate*1.5));var frame=0;var index=0;var excitationFiles: [String:String]=[:]
    while frame<samples.count {
        while index<events.count && events[index].0==frame {
            let e=events[index]
            if e.1==1 {
                guitar.noteOn(e.2,velocity:e.3)
                let strings=Mirror(reflecting:guitar).children.first { $0.label=="strings" }!.value as! [Int:KarplusStrong]
                let excitation=Mirror(reflecting:strings[e.2]!).children.first { $0.label=="buffer" }!.value as! [Float]
                let name="\(filename)-excitation-\(index).f32"
                try excitation.withUnsafeBufferPointer { Data(buffer:$0) }.write(to:melodicDirectory.appendingPathComponent(name))
                excitationFiles[String(index)]=name
            }else if e.1==0 {guitar.noteOff(e.2)}
            else if e.1==2 {guitar.pitchBend(e.3,channel:0,rangeSemitones:e.2)}
            else {guitar.allNotesOff()}
            index+=1
        }
        let end=min(samples.count,frame+128,index<events.count ? events[index].0 : samples.count)
        samples.withUnsafeMutableBufferPointer { guitar.render(into:$0.baseAddress!.advanced(by:frame),frames:end-frame) };frame=end
    }
    try samples.withUnsafeBufferPointer { Data(buffer:$0) }.write(to:melodicDirectory.appendingPathComponent(filename+".f32"))
    melodicManifest.append(["file":filename,"kind":"Guitar","rate":Int(rate),"frames":samples.count,"parameters":[:],"excitations":excitationFiles,
        "events":events.map { [$0.0,$0.1,$0.2,Double($0.3)] as [Any] }])
}
try JSONSerialization.data(withJSONObject:melodicManifest,options:[.prettyPrinted,.sortedKeys]).write(to:melodicDirectory.appendingPathComponent("manifest.json"))
print("PASS: Actual AnalogSynth/Guitar references: polyphony, retrigger, release, bend and panic")

// Every actual registered post-instrument processor, including aliases/no-ops.
let effectsDirectory=output.deletingLastPathComponent().appendingPathComponent("effect-reference")
try FileManager.default.createDirectory(at:effectsDirectory,withIntermediateDirectories:true)
var effectsManifest:[[String:Any]]=[]
for rate in [44100.0,48000.0,96000.0] {
    let count=Int(rate*0.65)
    var sourceL=[Float](repeating:0,count:count),sourceR=sourceL
    for i in 0..<count {
        let t=Double(i)/rate
        sourceL[i]=Float(sin(2 * .pi * 110*t)*0.35 + sin(2 * .pi * 3117*t)*0.12)
        sourceR[i]=Float(sin(2 * .pi * 173*t)*0.23 + cos(2 * .pi * 5271*t)*0.09)
        if i%4096<4 { sourceL[i]+=0.7;sourceR[i]-=0.5 }
        if i>count*3/4 {sourceL[i]=0;sourceR[i]=0}
    }
    var interleaved=[Float](repeating:0,count:count*2)
    for i in 0..<count {interleaved[2*i]=sourceL[i];interleaved[2*i+1]=sourceR[i]}
    try interleaved.withUnsafeBufferPointer {Data(buffer:$0)}.write(to:effectsDirectory.appendingPathComponent("input-\(Int(rate)).f32"))
    for (deviceIndex,kind) in DeviceKind.allCases.enumerated() where !kind.isBuiltInTrackInstrument {
        for profile in 0...2 {
            let effect=DeviceFactory.make(kind)
            if profile==2 && !(effect is SidechainAudioEffect) {continue}
            (effect as? SampleRateAware)?.setSampleRate(rate)
            (effect as? TempoAware)?.setTempo(137)
            var parameters=DeviceFactory.defaults(for:kind)
            if profile>0 { for info in effect.automatableParams { parameters[info.id]=info.min+(info.max-info.min)*0.37 } }
            for (key,value) in parameters {effect.setParam(key,value)}
            var left=sourceL,right=sourceR
            for start in stride(from:0,to:count,by:128) {
                left.withUnsafeMutableBufferPointer {l in right.withUnsafeMutableBufferPointer {r in
                    if profile==2, let sc=effect as? SidechainAudioEffect {
                        let detectorL=sourceL.map{$0*3},detectorR=sourceR.map{$0*3}
                        detectorL.withUnsafeBufferPointer {dl in detectorR.withUnsafeBufferPointer {dr in
                            sc.processSidechain(l.baseAddress!.advanced(by:start),r.baseAddress!.advanced(by:start),sidechainL:dl.baseAddress!.advanced(by:start),sidechainR:dr.baseAddress!.advanced(by:start),frames:min(128,count-start))
                        }}
                    }else {effect.process(l.baseAddress!.advanced(by:start),r.baseAddress!.advanced(by:start),frames:min(128,count-start))}
                }}
            }
            for i in 0..<count {interleaved[2*i]=left[i];interleaved[2*i+1]=right[i]}
            let file="\(Int(rate))-\(deviceIndex)-\(profile)"
            try interleaved.withUnsafeBufferPointer {Data(buffer:$0)}.write(to:effectsDirectory.appendingPathComponent(file+".f32"))
            effectsManifest.append(["file":file,"kind":kind.rawValue,"rate":Int(rate),"frames":count,"parameters":parameters,"tempo":137,"profile":profile,"sidechain":profile==2])
        }
    }
}
try JSONSerialization.data(withJSONObject:effectsManifest,options:[.sortedKeys]).write(to:effectsDirectory.appendingPathComponent("manifest.json"))
print("PASS: Original effect registry audio references at three rates/two profiles")

// Remaining original instruments; only unseeded percussion noise is instrumented
// in the external test-source copy. See noise-oracle.json for source checksum.
var stockManifest:[[String:Any]]=[]
for rate in [44100.0,48000.0,96000.0] {
    for kind in ["LemmingBass","Oscillatron","Indian Percussion","Bhangra Architect"] {
        for profile in 0...1 {
            let instrument:Instrument
            switch kind {
            case "LemmingBass":instrument=LemmingBassInstrument(sampleRate:rate)
            case "Oscillatron":instrument=OscillatronInstrument(sampleRate:rate)
            case "Bhangra Architect":instrument=BhangraArchitectInstrument(sampleRate:rate)
            default:instrument=IndianPercussion(sampleRate:rate)
            }
            var parameters:[String:Double]=[:]
            if let auto=instrument as? Automatable {
                if profile==1 {for p in auto.automatableParams {auto.setParam(p.id,p.min+(p.max-p.min)*0.42)}}
                for p in auto.automatableParams {parameters[p.id]=auto.getParam(p.id)}
            }
            parityNoiseSeed=0xC0FFEE
            var events:[(Int,Int,Int,Float)]=[]
            for j in 0..<40 {events.append((Int(Double(j)*rate*0.004),1,kind=="Bhangra Architect" ? [60,69,84,86,90][j%5] : (kind=="Indian Percussion" ? 60+j%12 : 36+j%35),Float(0.4+Double(j%5)*0.1)))}
            events += [(Int(rate*0.18),2,12,0.3),(Int(rate*0.25),3,0,0),(Int(rate*0.35),1,60,0.7),(Int(rate*0.45),0,60,0)]
            var samples=[Float](repeating:0,count:Int(rate*1.2)),frame=0,index=0
            while frame<samples.count {
                while index<events.count && events[index].0==frame {
                    let e=events[index]
                    if e.1==1 {
                        instrument.noteOn(e.2,velocity:e.3)
                    }else if e.1==0 {instrument.noteOff(e.2)}
                    else if e.1==2 {instrument.pitchBend(e.3,channel:0,rangeSemitones:e.2)}
                    else {instrument.allNotesOff()}
                    index+=1
                }
                let end=min(samples.count,frame+128,index<events.count ? events[index].0 : samples.count)
                samples.withUnsafeMutableBufferPointer {instrument.render(into:$0.baseAddress!.advanced(by:frame),frames:end-frame)};frame=end
            }
            let file="stock-\(kind.replacingOccurrences(of:" ",with:"-"))-\(Int(rate))-\(profile)"
            try samples.withUnsafeBufferPointer {Data(buffer:$0)}.write(to:melodicDirectory.appendingPathComponent(file+".f32"))
            stockManifest.append(["file":file,"kind":kind,"rate":Int(rate),"frames":samples.count,"parameters":parameters,"events":events.map{[$0.0,$0.1,$0.2,Double($0.3)] as [Any]}])
        }
    }
}
try JSONSerialization.data(withJSONObject:stockManifest,options:[.sortedKeys]).write(to:melodicDirectory.appendingPathComponent("stock-manifest.json"))

let warpDirectory=output.deletingLastPathComponent().appendingPathComponent("warp-reference")
try FileManager.default.createDirectory(at:warpDirectory,withIntermediateDirectories:true)
let warpInput=(0..<16384).map { i -> Float in let t=Double(i)/48000;return Float(sin(2 * .pi * 220*t)*0.3+cos(2 * .pi * 715*t)*0.13) }
try warpInput.withUnsafeBufferPointer{Data(buffer:$0)}.write(to:warpDirectory.appendingPathComponent("input.f32"))
for ratio in [0.7,1.0,1.35] {for mode in WarpMode.allCases {
    let result=WarpEngine.stretch(warpInput,ratio:ratio,mode:mode)
    try result.withUnsafeBufferPointer{Data(buffer:$0)}.write(to:warpDirectory.appendingPathComponent("\(mode.rawValue)-\(ratio).f32"))
}}
print("PASS: All three original warp algorithms")

// Real sample-layer processors, with portable payload rather than local paths.
var sampleData=[Float]()
for i in 0..<6000 {let t=Double(i);let tone=sin(t*0.061);let envelope=exp(-t/1800.0);sampleData.append(Float(tone*0.45*envelope))}
var sampleLayer=SequencerLayer(name:"Portable one-shot",source:.splice,note:60,velocity:0.73)
sampleLayer.embeddedSamples=sampleData
var sampleManifest:[[String:Any]]=[]
for rate in [44100.0,48000.0,96000.0] {for hybrid in [false,true] {
    parityNoiseSeed=0xC0FFEE
    let instrument:Instrument=hybrid ? SampleLayerHybridInstrument(name:"Test",base:BhangraArchitectInstrument(sampleRate:rate),layers:[sampleLayer],sampleRate:rate) : SampleLayerDrumKit(name:"Test",genre:.rock,layers:[sampleLayer],sampleRate:rate)
    let events=(0..<54).map { j in (j*128,1,j%3==0 ? (hybrid ? 84 : 36):60,Float(0.6)) }
    var samples=[Float](repeating:0,count:Int(rate*0.5));var frame=0,index=0
    while frame<samples.count {
        while index<events.count && events[index].0==frame {let e=events[index];instrument.noteOn(e.2,velocity:e.3);index+=1}
        let end=min(samples.count,frame+128,index<events.count ? events[index].0 : samples.count)
        samples.withUnsafeMutableBufferPointer {instrument.render(into:$0.baseAddress!.advanced(by:frame),frames:end-frame)};frame=end
    }
    let file="samples-\(Int(rate))-\(hybrid ? "hybrid":"drums")"
    try samples.withUnsafeBufferPointer{Data(buffer:$0)}.write(to:melodicDirectory.appendingPathComponent(file+".f32"))
    sampleManifest.append(["file":file,"rate":Int(rate),"hybrid":hybrid,"frames":samples.count,"events":events.map{[$0.0,$0.1,$0.2,Double($0.3)] as [Any]},"samples":sampleData,"level":Double(sampleLayer.velocity)])
}}
try JSONSerialization.data(withJSONObject:sampleManifest,options:[.sortedKeys]).write(to:melodicDirectory.appendingPathComponent("sample-manifest.json"))
let sampleProject=Project();let sampleTrack=Track(name:"Portable",kind:.drums,color:.blue);sampleTrack.sequencerLayers=[sampleLayer];sampleProject.tracks=[sampleTrack]
let sampleDocument=try ProjectDocument.decode(ProjectDocument(project:sampleProject).encoded()).makeProject()
require(sampleDocument.tracks[0].sequencerLayers[0].embeddedSamples==sampleData,"Portable layer payload lost")
try ProjectDocument(project:sampleProject).encoded().write(to:output.deletingLastPathComponent().appendingPathComponent("portable-sample.lemmingsproject"))
print("PASS: Original drum/hybrid sample voices and portable layer document")
