"""Original native stock audio, evaluated on a worker for playback and export.

This is a deterministic offline graph, not a Python real-time audio callback.
Unavailable external processors/endpoints are reported before rendering.
"""
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from contextlib import ExitStack
import json,math,os,sys
import ctypes as C
import numpy as np
from .audio import Renderer
from .native_audio import NativeAudio
from .native_effects import NativeEffect,DEFINITIONS
from .native_sources import NativeKit,NativeSamples,warp
from .stock_contract import BUILTIN_DEVICES,EFFECT_FAMILIES,MIDI_DEVICES,RACK_DEVICES,BRIDGE_DEVICES
from .musical_timeline import Timeline,midi_plan,lane_value,rounded,NONPITCHED

REFERENCE=json.loads((Path(__file__).parent/'qml/WorkspaceReference.json').read_text(encoding='utf-8'))
NOTES={36:0,35:1,38:2,39:3,37:4,42:5,46:6,45:7,51:8,49:9}
DRUM_KINDS={'Drum Machine','Sequencer','2C','Bailaton','Dubstep Wrangler'}
NATIVE_KINDS=DRUM_KINDS|{'Analog Synth','Guitar','LemmingBass','Oscillatron','Indian Percussion','Bhangra Dhol','Bhangra Architect','Audio (Recorded)'}
QUANTUM=128

def library_path():
    configured=os.environ.get('LEMMINGS_NATIVE_LIBRARY')
    if configured:return Path(configured)
    name='lemmings_audio.dll' if sys.platform=='win32' else 'liblemmings_audio.dylib'
    if getattr(sys,'frozen',False):return Path(sys._MEIPASS)/'native-audio'/name
    return Path(__file__).resolve().parents[4]/'Artifacts/native-audio'/name

@dataclass
class Snapshot:
    data:dict
    master_gain:float=1.
    scope:str="arrangement"
    tail_seconds:float=0.
    metronome:bool=False
    @property
    def tempo(self):return self.data.get('bpm',self.data.get('tempo',124.))

class EffectChain:
    def __init__(self,stack,engine,devices,rate,tempo,lanes=(),fresh=False,honor_mono=True):
        self.items=[];self.lanes=lanes;self.fresh=fresh;self.honor_mono=honor_mono
        for model in devices:
            kind=model['kind']
            if kind in BUILTIN_DEVICES or kind in MIDI_DEVICES or kind in RACK_DEVICES:continue
            if kind not in EFFECT_FAMILIES:
                if model.get('bypassed'):continue
                raise ValueError(f'{kind}: external or unknown processor unavailable; nothing was substituted')
            effect=stack.enter_context(NativeEffect(engine,kind,rate,model.get('params'),tempo))
            self.items.append((model,effect))
    def process(self,audio,beat,tempo,sidechains=None):
        for model,effect in self.items:
            effect.tempo(tempo)
            # Static baseline precedes automation on every host block. Fresh
            # clip/group nodes reset after restoring manual parameters.
            for key,value in model.get('params',{}).items():effect.set(key,value)
            if self.fresh:effect.reset()
            bypass=model.get('bypassed',False)
            for lane in self.lanes:
                if lane.get('nodeID') not in (model['id'],'device:'+model['id']):continue
                value=lane_value(lane,beat)
                if value is None:continue
                if lane['paramID']=='__device_on__':bypass=value<.5
                else:effect.set(lane['paramID'],value)
            if bypass or self.fresh and model.get('bypassed'):continue
            side=None
            if model.get('sidechainEnabled') and model.get('sidechainInputTrackID'):
                if effect.kind not in ('Dynamics Compressor','Multiband Processor','Bus Compressor'):raise ValueError('Sidechain is not supported by this processor')
                side=(sidechains or {}).get(model['sidechainInputTrackID'])
                if side is None:raise ValueError('Missing sidechain source; original state is preserved')
            # Mac sidechain branch precedes per-device mono collapse.
            if side is None and self.honor_mono and model.get('mono'):audio[:]=audio.mean(axis=1,dtype=np.float32)[:,None]
            effect.process_into(audio,side)

class WorkspaceRenderer(Renderer):
    supports_cancellation=True
    def __init__(self,snapshot,base=None,cancelled=None):
        self.cancelled=cancelled;self.scope=snapshot.scope
        data=deepcopy(snapshot.data);self.rate=int(data.get('sampleRate',48000));base=Path(base or Path.cwd())
        if not 8000<=self.rate<=192000:raise ValueError('Unsupported sample rate')
        if data.get('channelFormat','Stereo')!='Stereo':raise ValueError('Multichannel export awaits endpoint integration')
        timeline=self.timeline=Timeline(data,self.rate);self.length=timeline.frame(timeline.length)+rounded(self.rate*snapshot.tail_seconds)
        if self.length>self.rate*600:raise ValueError('Render at most ten minutes at a time')
        self.output=np.zeros((self.length,2),dtype=np.float32);self.sources=[]
        tracks={t['id']:t for t in data['tracks']};groups={g['id']:g for g in data.get('groups',[])}
        any_solo=any(t.get('solo') for t in tracks.values());engine=NativeAudio(library_path())
        with ExitStack() as stack:
            returns={b['id']:(b,np.zeros_like(self.output),EffectChain(stack,engine,b.get('devices',[]),self.rate,timeline.bpm(0),honor_mono=False)) for b in data.get('returnBuses',[])}
            master=EffectChain(stack,engine,data.get('masterDevices',[]),self.rate,timeline.bpm(0))
            processed={};visiting=set()
            def render_track(tid):
                if tid in processed:return processed[tid]
                if tid in visiting:raise ValueError('Cyclic sidechain routing cannot be rendered safely')
                visiting.add(tid);track=tracks[tid]
                self.check_cancelled()
                if self.scope=='stepSequencer' and not (track['kind'] in NONPITCHED and track.get('useStepSequencer')):
                    processed[tid]=np.zeros_like(self.output);visiting.remove(tid);return processed[tid]
                if track.get('outputMode')=='External / Multichannel':raise ValueError('External output is unavailable in offline rendering')
                group=groups.get(track.get('groupID'))
                if track.get('groupID') and group is None:raise ValueError('Missing group routing target')
                # A muted track may still feed a pre-fader send or a detector.
                frozen=bool(track.get('frozen') and track.get('bounced'))
                source=self.render_source(stack,engine,track,data,timeline,base,frozen)
                chain=EffectChain(stack,engine,[] if frozen else track.get('devices',[]),self.rate,timeline.bpm(0),track.get('automationLanes',[]))
                group_chain=EffectChain(stack,engine,group.get('devices',[]) if group and not frozen else [],self.rate,timeline.bpm(0),group.get('automationLanes',[]) if group else [],fresh=True)
                dependencies={m['sidechainInputTrackID'] for m in track.get('devices',[]) if m.get('sidechainEnabled') and m.get('sidechainInputTrackID') and not m.get('bypassed')}
                for dependency in dependencies:
                    if dependency not in tracks:raise ValueError('Missing sidechain track')
                    render_track(dependency)
                for frame in range(0,self.length,QUANTUM):
                    self.check_cancelled()
                    end=min(frame+QUANTUM,self.length);beat=timeline.beat(frame);tempo=timeline.bpm(beat)
                    detectors={key:processed[key][frame:end] for key in dependencies}
                    chain.process(source[frame:end],beat,tempo,detectors)
                    group_chain.process(source[frame:end],beat,tempo)
                processed[tid]=source;visiting.remove(tid)
                return source
            for tid in tracks:render_track(tid)
            for tid,track in tracks.items():
                source=processed[tid];self.sources.append((track,source))
                group=groups.get(track.get('groupID'),{})
                audible=not track.get('mute') and not group.get('mute') and (not any_solo or track.get('solo'))
                volume=np.float32(track.get('volume',.8))*np.float32(group.get('volume',1))*np.float32(1 if audible else 0)
                pan=np.float32(max(-1,min(1,track.get('pan',0)+group.get('pan',0))))
                width=np.float32(max(0,min(2,track.get('stereoWidth',1)))) if track.get('panMode')=='True Stereo' else np.float32(1)
                dry=np.float32(0 if track.get('outputMode')=='Sends Only' else 1)
                levels=np.asarray([volume*dry*(1-pan if pan>0 else 1)*width,volume*dry*(1+pan if pan<0 else 1)*width],dtype=np.float32)
                self.output+=source*levels
                for send in track.get('sends',[]):
                    if send.get('amount',0)<=.0001:continue
                    if send['returnBusID'] not in returns:raise ValueError('Missing return bus')
                    gain=np.float32(send['amount'])
                    returns[send['returnBusID']][1][:]+=source*(gain if send.get('preFader') else gain*levels)
            for bus,audio,chain in returns.values():
                for frame in range(0,self.length,QUANTUM):
                    beat=timeline.beat(frame);chain.process(audio[frame:frame+QUANTUM],beat,timeline.bpm(beat))
                if not bus.get('mute'):
                    pan=bus.get('pan',0);vol=bus.get('volume',.8)
                    self.output+=audio*np.asarray([vol*(1-pan if pan>0 else 1),vol*(1+pan if pan<0 else 1)],dtype=np.float32)
            for frame in range(0,self.length,QUANTUM):
                beat=timeline.beat(frame);master.process(self.output[frame:frame+QUANTUM],beat,timeline.bpm(beat))
        if snapshot.metronome:
            click=engine.library.ls_metronome
            click.argtypes=[C.POINTER(C.c_double),C.c_uint32,C.c_double,C.c_double,C.c_double,C.c_uint32,C.c_float,C.POINTER(C.c_float)];click.restype=C.c_int
            for frame in range(0,self.length,QUANTUM):
                end=min(self.length,frame+QUANTUM);beats=np.asarray([timeline.beat(i) for i in range(frame,end)],dtype=np.float64);mono=np.zeros(end-frame,dtype=np.float32)
                if click(beats.ctypes.data_as(C.POINTER(C.c_double)),len(beats),timeline.beat(end),self.rate,timeline.bpm(beats[0]),data.get('beatsPerBar',4),.55,mono.ctypes.data_as(C.POINTER(C.c_float))):raise ValueError('Invalid metronome state')
                self.output[frame:end]+=mono[:,None]
        self.output*=np.float32(snapshot.master_gain)
        if not np.isfinite(self.output).all():raise ValueError('Nonfinite native render was rejected')

    def render_source(self,stack,engine,track,data,timeline,base,frozen):
        if not frozen and track['kind'] not in NATIVE_KINDS:raise ValueError(f"{track['kind']} DSP is not ported; the saved instrument was not replaced")
        if not frozen and (track.get('externalPluginSlots') or track.get('pluginTargetID') not in (None,'Built-in Analog','Vital')):
            raise ValueError('Unavailable third-party plugin; nothing was substituted')
        audio=np.zeros((self.length,2),dtype=np.float32)
        clips=[track['bounced']] if frozen else [c for c in track.get('audioClips',[]) if c.get('isActive',True)] if track['kind']=='Audio (Recorded)' else []
        for clip in clips:self.render_audio_clip(stack,engine,audio,clip,timeline,base)
        if frozen or track['kind']=='Audio (Recorded)':return audio
        events=self.note_events(track,data,timeline)
        # Process FX Architect and source instruments even when a track has no notes.
        if track['kind'] in DRUM_KINDS:
            genre='Guaracha' if track['kind']=='2C' else 'Dubstep' if track['kind']=='Dubstep Wrangler' else track.get('drumGenre','Tech House')
            instrument=stack.enter_context(NativeKit(engine,self.rate,REFERENCE['drumKits'][genre]))
            allowed={'master'}|{f'{i}_{p}' for i in range(10) for p in ('tune','decay','level')}
        else:
            instrument=stack.enter_context(engine.instrument(track['kind'],self.rate,seed=track.get('guitarExcitationSeed',0xC0FFEE)))
            definition=DEFINITIONS.get({'Analog Synth':'Subtractive Synth'}.get(track['kind'],track['kind']))
            allowed={p['id'] for p in definition['params']} if definition and track['kind'] in ('Analog Synth','Oscillatron','LemmingBass') else set()
            if track['kind']=='Oscillatron':allowed|={'osc2Mix','detuneCents'}
            elif track['kind']=='LemmingBass':allowed.add('osc2Mix')
        for device in track.get('devices',[]):
            if device['kind'] in BUILTIN_DEVICES:
                for key,value in device.get('params',{}).items():
                    if key in allowed:instrument.set(key,value)
        layers=track.get('sequencerLayers',[])
        if any(l.get('source')=='Plug-in' for l in layers):raise ValueError('Unavailable plugin sequencer lane; nothing was substituted')
        samples=stack.enter_context(NativeSamples(engine,layers,base,32 if track['kind'] in DRUM_KINDS else 48)) if any(l.get('samplePath') or l.get('embeddedSamples') is not None for l in layers) else None
        index=0;mono=np.zeros(self.length,dtype=np.float32);frame=0
        lanes=[l for l in track.get('automationLanes',[]) if l.get('nodeID') in {'instrument'}|{d['id'] for d in track.get('devices',[]) if d['kind'] in BUILTIN_DEVICES}]
        while frame<self.length:
            self.check_cancelled()
            if frame%QUANTUM==0:
                beat=timeline.beat(frame)
                for lane in lanes:
                    value=lane_value(lane,beat)
                    if value is not None and lane['paramID'] in allowed:instrument.set(lane['paramID'],value)
            while index<len(events) and events[index][0]==frame:
                _,event_type,note,velocity=events[index]
                if samples and (note in samples.notes or event_type==3):samples.event(event_type,note,velocity)
                if not samples or note not in samples.notes or event_type==3:instrument.event(event_type,note,velocity)
                index+=1
            end=min(self.length,((frame//QUANTUM)+1)*QUANTUM,events[index][0] if index<len(events) else self.length)
            instrument.process_into(mono[frame:end])
            if samples:samples.process_into(mono[frame:end])
            frame=end
        audio+=mono[:,None]
        return audio

    def note_events(self,track,data,timeline):
        messages=[]
        arp=next((d for d in track.get('devices',[]) if d['kind']=='Pattern Arp' and not d.get('bypassed')),None)
        def add(beat,note,velocity,length,step=False,layer=None):
            if beat<0:return
            if layer:
                if layer.get('source')=='Plug-in':raise ValueError('Unavailable plugin lane')
                if not (layer.get('source')=='Built-in Drum' and note in NOTES or layer.get('source')=='Splice Sample' or layer.get('samplePath') or layer.get('embeddedSamples') is not None):note=max(0,min(127,note+layer.get('octaveOffset',0)*12))
                velocity=max(0,min(1,velocity*layer.get('volume',1)))
            pitches,velocity,duration=midi_plan(note,velocity,length,track,data,REFERENCE)
            if step:duration=length # original live grid releases at the next boundary
            if arp and not (step and layer and (layer.get('source') in ('Built-in Drum','Splice Sample') or layer.get('samplePath') or layer.get('embeddedSamples') is not None)):
                p=arp.get('params',{});octaves=max(1,min(4,rounded(p.get('octaves',2))));pool=[max(0,min(127,n+12*o)) for n in pitches for o in range(octaves)]
                if step:
                    hits=[(beat,n,duration) for n in pool]
                else:
                    rate=max(.03125,min(4,p.get('rate',.25)));gate=max(.02,min(1,p.get('gate',.45)))
                    hits=[(beat+j*rate,pool[j%len(pool)],min(rate*gate,length-j*rate)) for j in range(math.ceil(length/rate))]
            else:hits=[(beat,n,duration) for n in pitches]
            for b,n,d in hits:
                messages.append((timeline.frame(b),1,n,velocity));messages.append((timeline.frame(b+d),0,n,0.))
        for clip in (track.get('clips',[]) if self.scope!='stepSequencer' and not (self.scope=='all' and track.get('useStepSequencer')) else []):
            if clip.get('isActive',True):
                for n in clip.get('notes',[]):add(clip['startBeat']+n['start'],n['pitch'],n['velocity'],max(.02,n['length']))
        if track.get('useStepSequencer') and self.scope in ('stepSequencer','all'):
            pattern=track.get('stepPattern',{});steps=pattern.get('steps',[]);spb=pattern.get('stepsPerBeat',4);count=pattern.get('stepCount',len(steps))
            if not 1<=spb<=64 or not 0<count<=4096 or count!=len(steps):raise ValueError('Invalid step pattern')
            span=count/spb;layers={l['note']:l for l in track.get('sequencerLayers',[])}
            for loop in np.arange(0,timeline.length,span):
                for i,step in enumerate(steps):
                    for note in step.get('hits') or ([step.get('note',36)] if step.get('on') else []):add(float(loop)+i/spb,note,step.get('velocity',.9),1/spb,True,layers.get(note))
        messages.sort(key=lambda e:(e[0],e[1]))
        return messages

    def render_audio_clip(self,stack,engine,target,clip,timeline,base):
        if clip.get('externalPluginSlots'):raise ValueError('Unavailable clip plugin; nothing was substituted')
        source=np.asarray(clip.get('samples',[]),dtype=np.float32);rate=clip.get('sampleRate',self.rate)
        if source.ndim!=1 or not np.isfinite(source).all() or not 8000<=rate<=192000:raise ValueError('Invalid embedded audio')
        if clip.get('warpEnabled'):
            original=clip.get('originalTempo',120)
            if original>0 and abs(original/timeline.tempo-1)>=.001:source=warp(engine,source,original/timeline.tempo,clip.get('warpMode','Beat'))
        start_beat=clip['startBeat'];natural=max(.25,len(source)/rate*timeline.bpm(0)/60-clip.get('trimStartBeats',0));length=max(.25,clip['lengthBeatsOverride'] if clip.get('lengthBeatsOverride') is not None else natural)
        start=max(0,timeline.frame(start_beat));end=min(self.length,timeline.frame(start_beat+length))
        if end<=start:return
        rendered=np.zeros_like(target);pitch=max(.03125,min(32,2**((clip.get('pitchSemitones',0)*100+clip.get('pitchCents',0))/1200)));gain=np.float32(10**(clip.get('gainDB',0)/20))
        chain=EffectChain(stack,engine,clip.get('devices',[]),self.rate,timeline.bpm(0),fresh=True)
        for frame in range(0 if clip.get('devices') else (start//QUANTUM)*QUANTUM,self.length if clip.get('devices') else end,QUANTUM):
            finish=min(self.length,frame+QUANTUM);tempo=timeline.bpm(timeline.beat(frame));sec_per=60/tempo
            times=np.asarray([timeline.beat(i) for i in range(frame,finish)])*sec_per-start_beat*sec_per+clip.get('trimStartBeats',0)*sec_per
            valid_time=times>=0
            if clip.get('loopEnabled',True) and len(source):times=np.remainder(times,len(source)/rate/pitch)
            indices=np.trunc(times*rate*pitch).astype(np.int64);mask=valid_time&(indices>=0)&(indices<len(source))&(np.arange(frame,finish)>=start)&(np.arange(frame,finish)<end)
            part=rendered[frame:finish];part[mask]=source[indices[mask],None]*gain
            chain.process(part,timeline.beat(frame),tempo)
        target+=rendered

    def check_cancelled(self):
        if self.cancelled is not None and self.cancelled.is_set():raise InterruptedError('Rendering cancelled; source project preserved')
    def frame_at_beat(self,beat):return self.timeline.frame(beat)
    def beat_at_frame(self,frame):return self.timeline.beat(frame)
    def block(self,frame,count):return self.output[frame:frame+count]
