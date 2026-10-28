import Foundation
import AppKit
import AVFoundation

private enum HostRegressionState {static var started=false}

extension AppState {
    @MainActor func runHostingRegression() {
        guard !HostRegressionState.started else {return};HostRegressionState.started=true
        guard let index=CommandLine.arguments.firstIndex(of:"--validate-hosting"),CommandLine.arguments.count>index+1 else {return}
        let output=URL(fileURLWithPath:CommandLine.arguments[index+1],isDirectory:true)
        try? FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var report:[String:Any]=["status":"running","physical_audio_device_tested":false]
        func require(_ value:Bool,_ message:String)throws {if !value {throw NSError(domain:"PluginRegression",code:1,userInfo:[NSLocalizedDescriptionKey:message])}}
        func finish(_ error:Error?=nil) {
            report["status"]=error==nil ? "passed":"failed"
            if let error {report["error"]=error.localizedDescription}
            if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("report.json"))}
            engine.stop();DispatchQueue.main.asyncAfter(deadline:.now()+0.1){exit(error==nil ? 0:1)}
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { [self] in
            do {
                try checkOneShotReplacement(output:output)
                report["one_shot_replacement_audio"]=true
                let au=CommandLine.arguments.contains("--format-au")
                scanPlugins()
                let format:PluginFormat=au ? .audioUnit:.vst3
                var serumMatch:DiscoveredPlugin?=nil
                var neutronMatch:DiscoveredPlugin?=nil
                for item:DiscoveredPlugin in discoveredPlugins {
                    if item.format != format {continue}
                    let compactName:String=AudioUnitCatalog.compact(item.name)
                    if item.role == PluginRole.instrument && compactName.contains("serum2") && !compactName.contains("fx") {serumMatch=item}
                    if item.role == PluginRole.effect && compactName.hasSuffix("neutron5") {neutronMatch=item}
                }
                guard let serum:DiscoveredPlugin=serumMatch,let neutron:DiscoveredPlugin=neutronMatch else {
                    throw NSError(domain:"PluginRegression",code:2,userInfo:[NSLocalizedDescriptionKey:"Serum 2/Neutron 5 not discovered with correct roles in the requested format"])
                }
                report["format"]=format.rawValue;report["serum_path"]=serum.path ?? "registered AU";report["neutron_path"]=neutron.path ?? "registered AU"
                let track=Track(name:"Hosting regression",kind:.analog,color:.blue)
                project.tracks=[track];project.returnBuses=[];project.lengthBars=1;selectedTrackID=track.id
                engine.attach(project:project)
                _=dropPlugin(serum,on:track);_=dropPlugin(neutron,on:track)
                guard let synth=engine.liveInstrument(for:track),let effectSlot=track.externalPluginSlots.first(where:{$0.role == .effect}),let effect=engine.liveNode(track:track,nodeID:effectSlot.nodeID) as? AudioEffect else {throw NSError(domain:"PluginRegression",code:3,userInfo:[NSLocalizedDescriptionKey:"Track plugin processors not connected"])}
                try require(!(synth is UnavailablePluginInstrument),"Synth failed to instantiate")
                try require(!(effect is RackPassThroughEffect),"Insert is a placeholder")
                let left=UnsafeMutablePointer<Float>.allocate(capacity:512),right=UnsafeMutablePointer<Float>.allocate(capacity:512)
                defer{left.deallocate();right.deallocate()};left.initialize(repeating:0,count:512);right.initialize(repeating:0,count:512)
                synth.noteOn(60,velocity:0.8);var sourcePeak:Float=0,insertPeak:Float=0
                for _ in 0..<128 {
                    _=synth.renderStereo(left:left,right:right,frames:512)
                    for i in 0..<512 {sourcePeak=max(sourcePeak,abs(left[i]),abs(right[i]))}
                    effect.process(left,right,frames:512)
                    for i in 0..<512 {insertPeak=max(insertPeak,abs(left[i]),abs(right[i]));try require(left[i].isFinite && right[i].isFinite,"Nonfinite plugin output")}
                }
                synth.noteOff(60)
                try require(sourcePeak>0.00001,"Serum produced no MIDI audio")
                try require(insertPeak>0.00001,"Neutron insert produced no audio")
                report["source_peak"]=sourcePeak;report["insert_peak"]=insertPeak
                if let native=synth as? NativeHostedPlugin {
                    guard let param=native.automatableParams.first,let state=native.capturedPresetStateBase64() else {throw NSError(domain:"PluginRegression",code:4,userInfo:[NSLocalizedDescriptionKey:"Missing VST3 parameters/state"])}
                    let before=native.getParam(param.id);native.setParam(param.id,before<0.5 ? 1:0);native.restorePresetStateBase64(state)
                    try require(abs(native.getParam(param.id)-before)<0.001,"VST3 state restore failed")
                    try require(native.showEditor(),"Serum VST3 editor creation failed")
                    native.hideEditor();try require(native.showEditor(),"Serum editor reopen failed");native.hideEditor()
                    try require((effect as? NativeHostedPlugin)?.showEditor()==true,"Neutron VST3 editor creation failed")
                    (effect as? NativeHostedPlugin)?.hideEditor()
                    let held=engine.liveNativePlugin(for:effectSlot);engine.refreshDevices(for:track)
                    try require(held === engine.liveNativePlugin(for:effectSlot),"Device refresh replaced the live insert instance")
                    report["native_editor_open_reopen"]=true;report["vst3_state_round_trip"]=true
                }else{
                    try require(synth is HostedAUInstrument && effect is HostedAUAudioEffect,"Unexpected AU implementation")
                    report["au_live_processor_types"]=true
                    for slot in track.externalPluginSlots {openPluginGUI(slot)}
                    // Return to the main event loop before checking asynchronously
                    // requested AU views; a nested run loop cannot drain main GCD.

                }
                for i in track.externalPluginSlots.indices {
                    let slot=track.externalPluginSlots[i]
                    if let state=engine.capturedExternalState(for:slot) {track.externalPluginSlots[i].presetStateBase64=state}
                    else if let host=synth as? HostedAUInstrument,slot.role == .instrument {track.externalPluginSlots[i].presetStateBase64=host.capturedPresetStateBase64()}
                }
                let data=try ProjectDocument(project:project).encoded();try data.write(to:output.appendingPathComponent("plugins.lemmingsproject"))
                let restored=try JSONDecoder().decode(ProjectDocument.self,from:data).makeProject()
                try require(restored.tracks[0].externalPluginSlots.count==2,"Plugin slots did not survive project reopen")
                report["plugin_project_state"]=true
                // Test the real armed MIDI record path with a selected source,
                // rejecting another source without opening the microphone.
                let midiTrack=Track(name:"MIDI input regression",kind:.analog,color:.green)
                project.tracks=[midiTrack];selectedTrackID=midiTrack.id;engine.attach(project:project)
                countInEnabled=false;midiInputEnabled=true;trackMIDIInputs[midiTrack.id.uuidString]="wanted"
                toggleTrackArm(midiTrack);toggleRecord()
                handleMIDI(.noteOn(note:61,velocity:0.8,channel:0),sourceID:"other")
                handleMIDI(.noteOn(note:60,velocity:0.8,channel:0),sourceID:"wanted")
                engine.transport.setBeat(0.5)
                handleMIDI(.noteOff(note:60,channel:0),sourceID:"wanted");toggleRecord()
                let notes=midiTrack.clips.flatMap(\.notes)
                try require(notes.count==1 && notes[0].pitch==60,"Armed MIDI input filtering/recording failed")
                report["armed_midi_source_recording"]=true
                let audio=Track(name:"Microphone input regression",kind:.audio,color:.red)
                project.tracks.append(audio);refreshAudioInputDevices();setAudioInputDevice(for:audio,uid:AudioRecorder.systemDefaultDeviceUID);setAudioInputChannel(for:audio,channelIndex:0);toggleTrackArm(audio)
                try require(audio.armed && audio.audioInputChannelIndex==0,"Audio arm/input selection failed")
                report["audio_arm_input_selection"]=true
                // Set up visible Piano Roll notes; deliver actual AppKit keys
                // through its local event monitor, including function-key flags.
                let clip=midiTrack.clips[0];clip.notes.append(ClipNote(pitch:64,start:1,length:0.25,velocity:0.8))
                selectedTrackID=midiTrack.id;selectedClipID=clip.id;PianoRollState.shared.clipID=clip.id;workspace = .pianoRoll
                let original=clip.notes.map(\.pitch)
                DispatchQueue.main.asyncAfter(deadline:.now()+0.6){
                    guard let window=NSApp.windows.first(where:{$0.title.contains("Lemmings")}) else {finish(NSError(domain:"PluginRegression",code:5,userInfo:[NSLocalizedDescriptionKey:"Main window missing"]));return}
                    window.makeKeyAndOrderFront(nil);window.makeFirstResponder(nil)
                    func key(_ code:UInt16,_ chars:String,_ flags:NSEvent.ModifierFlags){
                        if let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:code){NSApp.postEvent(event,atStart:false)}
                    }
                    key(0,"a",[.command])
                    DispatchQueue.main.asyncAfter(deadline:.now()+0.2){
                        do{try require(PianoRollState.shared.selectedNoteIDs.count==clip.notes.count,"Cmd+A did not select all notes")}catch{finish(error);return}
                        key(126,String(UnicodeScalar(0xF700)!),[.shift,.function,.numericPad])
                        DispatchQueue.main.asyncAfter(deadline:.now()+0.2){
                            do{try require(clip.notes.map(\.pitch)==original.map{$0+12},"Shift+Up did not transpose selected notes")}catch{finish(error);return}
                            key(125,String(UnicodeScalar(0xF701)!),[.shift,.function,.numericPad])
                            DispatchQueue.main.asyncAfter(deadline:.now()+0.2){
                                do{try require(clip.notes.map(\.pitch)==original,"Shift+Down did not transpose selected notes");report["piano_roll_actual_keyboard_shortcuts"]=true
                                    if au {
                                        DispatchQueue.main.asyncAfter(deadline:.now()+1){
                                            do {
                                                let visible=NSApp.windows.filter{$0.isVisible && ($0.title.lowercased().contains("serum") || $0.title.lowercased().contains("neutron"))}
                                                report["editor_window_titles"]=NSApp.windows.filter{$0.isVisible}.map(\.title)
                                                try require(visible.count>=2,"AU plugin editors did not open")
                                                try require(!visible.contains{$0.title.contains("Generic Controls")},"AU returned generic controls instead of the vendor editor")
                                                report["au_vendor_editors"]=true
                                                for window in visible {window.performClose(nil)}
                                                finish()
                                            }catch{finish(error)}
                                        }
                                    }else{finish()}}catch{finish(error)}
                            }
                        }
                    }
                }
            }catch{finish(error)}
        }
    }
}
