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
