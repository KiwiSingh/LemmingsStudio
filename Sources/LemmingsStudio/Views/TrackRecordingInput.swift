import SwiftUI

struct TrackRecordingInput:View {
    @Environment(AppState.self) private var app
    @Bindable var track:Track
    var body:some View {
        Menu {
            if track.kind == .audio {
                Button("Refresh audio inputs"){app.refreshAudioInputDevices()}
                Divider()
                ForEach(app.recorder.inputDevices){device in
                    Menu(device.name){
                        ForEach(0..<max(1,device.channelCount),id:\.self){channel in
                            Button("Input \(channel+1)"){
                                app.setAudioInputDevice(for:track,uid:device.uid);app.setAudioInputChannel(for:track,channelIndex:channel)
                            }
                        }
                    }
                }
            }else{
                Button("All MIDI Inputs"){app.setMIDIInput("*",for:track)}
                ForEach(app.midi.sources){source in Button(source.name){app.setMIDIInput(source.id,for:track)}}
                if app.midi.sources.isEmpty {Text("No MIDI keyboards connected")}
            }
        } label:{
            Text(track.kind == .audio ? "Mic: \(track.audioInputDeviceName) · \(track.audioInputChannelIndex+1)" : "MIDI: \(app.midiInputLabel(for:track))")
                .lineLimit(1).truncationMode(.middle)
        }
        .id(app.midiSourcesRevision)
        .menuStyle(.borderlessButton)
        .font(.caption2)
        .disabled(app.recorder.isRecording || app.midiOverdubRecording)
        .help(track.kind == .audio ? "Choose a microphone or audio-interface input channel" : "Choose the connected MIDI keyboard for this track. Microphones record on Audio tracks.")
        .accessibilityIdentifier("record-input-\(track.id.uuidString)")
    }
}
