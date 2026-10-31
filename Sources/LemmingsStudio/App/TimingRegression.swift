import Foundation
import AppKit
import AVFoundation

private final class TimingGateInstrument: Instrument {
    let name = "Timing validation gate"
    private var held = Set<Int>()
    func noteOn(_ note: Int, velocity: Float) { held.insert(note) }
    func noteOff(_ note: Int) { held.remove(note) }
    func allNotesOff() { held.removeAll() }
    func render(into out: UnsafeMutablePointer<Float>, frames: Int) { out.update(repeating: held.isEmpty ? 0 : 0.4, count: frames) }
}
private enum TimingRegressionState { static var started = false }
extension AppState {
    @MainActor func runTimingRegression() {
        guard !TimingRegressionState.started else { return }; TimingRegressionState.started = true
        if CommandLine.arguments.contains("--headless-validation") { NSApp.hide(nil) }
        guard let i = CommandLine.arguments.firstIndex(of: "--validate-timing"), CommandLine.arguments.count > i + 1 else { return }
        let output = URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var report: [String:Any] = ["status":"running", "physical_audio_output":false]
        func check(_ value:Bool,_ message:String) throws { if !value { throw ExportError.renderFailed(message) } }
        func finish(_ error:Error? = nil) {
            report["status"] = error == nil ? "passed":"failed"
            if let error { report["error"] = error.localizedDescription }
            if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:output.appendingPathComponent("report.json")) }
            engine.stop(); DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { exit(error == nil ? 0:1) }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { [self] in
            do {
                project = Project(); project.tempo = 140; project.lengthBars = 2; project.keySnapEnabled = false
                project.masterDevices = []; project.masterExternalPluginSlots = []
                let track = Track(name:"Exact MIDI events",kind:.analog,color:.blue)
                let notes = [ClipNote(pitch:60,start:0.13,length:0.007), ClipNote(pitch:62,start:0.59,length:0.047), ClipNote(pitch:64,start:1.37,length:0.09), ClipNote(pitch:65,start:3.91,length:0.021)]
                track.clips = [Clip(name:"Timing",startBeat:0,lengthBeats:4,notes:notes)]
                project.tracks = [track]
                engine.validationInstrumentFactory = { _ in TimingGateInstrument() }; engine.attach(project:project)
                func edges(_ samples:[Float]) -> (on:[Int],off:[Int]) {
                    var on:[Int]=[],off:[Int]=[]; var previous=false
                    for (i,value) in samples.enumerated() {
                        let active=abs(value)>0.01
                        if active && !previous { on.append(i) }
                        if !active && previous { off.append(i) }
                        previous=active
                    }
                    return (on,off)
                }
                let expectedOn=notes.map{Int(($0.start * 60 / 140 * engine.sampleRate).rounded())}
                let expectedOff=notes.map{Int((($0.start + $0.length) * 60 / 140 * engine.sampleRate).rounded())}
                var sizes:[String:Any]=[:]
                for block in [97,512,4096] {
                    let audio=try offline.renderStereo(project:project,forcedPlaybackScope:.arrangement,renderBlockSize:block)
                    let measured=edges(audio.l)
                    try check(measured.on.count==notes.count && measured.off.count==notes.count,"Missing notes/releases with export block \(block)")
                    let error=zip(measured.on,expectedOn).map{abs($0-$1)} + zip(measured.off,expectedOff).map{abs($0-$1)}
                    try check((error.max() ?? 999)<=1,"MIDI timing shifts with render block \(block): \(measured)")
                    sizes[String(block)]=["note_on_samples":measured.on,"note_off_samples":measured.off,"maximum_error_samples":error.max() ?? 0]
                }
                report["sample_accurate_midi"] = sizes
                // Snap is an editing-placement setting, never a note quantizer.
                snapToGridEnabled = true; gridSubdivisionBeats = 4
                let source=Track(name:"Step fixture",kind:.sequencer,color:.orange)
                source.stepPattern.clearAll()
                for step in [1,3,7,12,15] { source.stepPattern.setHit(step:step,note:42,enabled:true,velocity:0.9) }
                project.tracks=[source];engine.attach(project:project)
                let printed=createArrangementClipFromStepPattern(on:source,name:"One-bar snap print",startBeat:8,endBeat:12,openArrangement:false)
                try check(printed.notes.map(\.start)==[0.25,0.75,1.75,3,3.75],"Bar snap mangled internal step note positions")
                let audio=try offline.renderStereo(project:project,forcedPlaybackScope:.arrangement)
                let printedEdges=edges(audio.l)
                let expected=printed.notes.map{Int(((printed.startBeat+$0.start)*60/140*engine.sampleRate).rounded())}
                try check(printedEdges.on.count==expected.count && zip(printedEdges.on,expected).allSatisfy{abs($0-$1)<=1},"Printed step export timing differs from print notes")
                report["one_bar_snap_print_onsets"] = printedEdges.on
                // A half-bar source must not acquire a bar of repeated material.
                source.stepPattern = StepPattern(stepCount:8, stepsPerBeat:4)
                source.stepPattern.setHit(step:1,note:42,enabled:true,velocity:0.9)
                source.stepPattern.setHit(step:7,note:42,enabled:true,velocity:0.9)
                engine.transport.stop(at:16)
                let destination=printStepPatternToNewArrangementTrack(from:source)
                guard let half=destination.clips.last else { throw ExportError.renderFailed("Half-bar print missing") }
                try check(half.lengthBeats==2 && half.notes.map(\.start)==[0.25,1.75],"Half-bar print was expanded by one-bar snap")
                let unit=try MasterInsertAudioUnit(componentDescription:MasterInsertAudioUnit.component)
                let clock=HostedMusicalClock();clock.install(on:unit,sampleRate:engine.sampleRate);clock.update(bpm:140,beat:12.375,playing:true)
                var bpm=0.0,num=0.0,den=0,beat=0.0,next=0,downbeat=0.0
                try check(unit.musicalContextBlock?(&bpm,&num,&den,&beat,&next,&downbeat)==true && bpm==140 && beat==12.375,"AU musical time unavailable/incorrect")
                report["au_host_musical_context"] = ["bpm":bpm,"beat":beat,"downbeat":downbeat]
                let map=TempoMap(points:[TempoPoint(beat:0,bpm:90),TempoPoint(beat:16,bpm:180)],lengthBeats:32)
                engine.transport.tempoMap=map;engine.transport.stop(at:8);engine.transport.play();engine.transport.anchorSampleTime=1000
                try check(abs(engine.transport.beat(at:1000)-8)<0.000001,"Tempo map restart uses wrong beat origin")
                let offset=engine.transport.sampleOffset(forBeat:12,from:1000)
                try check(abs(engine.transport.beat(at:1000+Double(offset))-12)<0.0001,"Tempo map sample/beat inverse mismatch")
                report["tempo_map_restart_and_inverse"] = true
                engine.transport.stop();engine.transport.tempoMap=nil
                if let index=CommandLine.arguments.firstIndex(of:"--katyusha-project"),CommandLine.arguments.count>index+1 {
                    let url=URL(fileURLWithPath:CommandLine.arguments[index+1])
                    let doc=try ProjectDocument.decode(Data(contentsOf:url))
                    let loaded=doc.makeProject()
                    engine.validationInstrumentFactory=nil
                    project=loaded;rebuildTempoMap();engine.attach(project:loaded)
                    for track in loaded.tracks {
                        try check(!(engine.liveInstrument(for:track) is UnavailablePluginInstrument),"Katyusha missing instrument on \(track.name)")
                        for slot in track.externalPluginSlots where slot.format == .vst3 {
                            try check(engine.liveNativePlugin(for:slot) != nil,"Katyusha missing plugin: \(slot.name)")
                        }
                    }
                    let wav=output.appendingPathComponent("Katyusha-timing-fixed.wav")
                    let result=try offline.exportWithReport(project:loaded,to:wav,format:.wav)
                    try check(result.peak>0.001,"Katyusha render is silent")
                    report["katyusha_render"]=["url":wav.path,"frames":result.frames,"bpm":loaded.tempo,"peak":result.peak,"track_count":loaded.tracks.count]
                }
                finish()
            } catch { finish(error) }
        }
    }
}
