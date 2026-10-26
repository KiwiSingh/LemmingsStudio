import Foundation

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
