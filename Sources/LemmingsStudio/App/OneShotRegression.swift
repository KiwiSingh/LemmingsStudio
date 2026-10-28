import Foundation
import AVFoundation

extension AppState {
    @MainActor func checkOneShotReplacement(output:URL)throws {
        let track=Track(name:"One-shot regression",kind:.sequencer,color:.orange)
        project.tracks=[track];selectedTrackID=track.id;engine.attach(project:project)
        func write(_ name:String,_ level:Float)throws->URL {
            let url=output.appendingPathComponent(name)
            let format=AVAudioFormat(standardFormatWithSampleRate:engine.sampleRate,channels:1)!
            let file=try AVAudioFile(forWriting:url,settings:format.settings)
            let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:256)!
            buffer.frameLength=256;buffer.floatChannelData![0].update(repeating:level,count:256)
            try file.write(from:buffer);return url
        }
        let a=try write("old one shot.wav",0.1),b=try write("replacement one shot.wav",0.7)
        guard addSampleLayer(a,to:track,step:0,preferredNote:36) != nil else {throw NSError(domain:"OneShotRegression",code:1)}
        let samples=UnsafeMutablePointer<Float>.allocate(capacity:8);defer{samples.deallocate()};samples.initialize(repeating:0,count:8)
        let first=engine.liveInstrument(for:track)!;first.noteOn(36,velocity:1);first.render(into:samples,frames:8);let old=samples[0]
        guard handleSampleDropText(PluginDragPasteboard.samplePrefix+b.path,on:track,step:0,note:36),let second=engine.liveInstrument(for:track) else {throw NSError(domain:"OneShotRegression",code:2)}
        second.noteOn(36,velocity:1);second.render(into:samples,frames:8)
        guard old>0.001,samples[0]>old*3,track.stepPattern.isOn(step:0,note:36),track.sequencerLayers.first(where:{$0.note==36})?.samplePath==b.path else {throw NSError(domain:"OneShotRegression",code:3,userInfo:[NSLocalizedDescriptionKey:"One-shot did not replace the old lane voice"])}
        let saved=track.sequencerLayers
        guard addSampleLayer(output.appendingPathComponent("missing.wav"),to:track,step:0,preferredNote:36)==nil,track.sequencerLayers==saved else {throw NSError(domain:"OneShotRegression",code:4,userInfo:[NSLocalizedDescriptionKey:"Failed drop changed the lane"])}
    }
}
