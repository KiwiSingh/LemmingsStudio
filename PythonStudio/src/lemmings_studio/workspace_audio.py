"""Conservative rendering boundary: unported processing is never substituted."""
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
import json,math,os,sys
import numpy as np
from .audio import Renderer
from .native_audio import NativeAudio
from .stock_contract import ANALOG_DEVICES

REFERENCE=json.loads((Path(__file__).parent/'qml/WorkspaceReference.json').read_text(encoding='utf-8'))
NOTES={36:0,35:1,38:2,39:3,37:4,42:5,46:6,45:7,51:8,49:9}


def library_path():
    configured=os.environ.get('LEMMINGS_NATIVE_LIBRARY')
    if configured: return Path(configured)
    name='lemmings_audio.dll' if sys.platform=='win32' else 'liblemmings_audio.dylib'
    if getattr(sys,'frozen',False): return Path(sys._MEIPASS)/'native-audio'/name
    return Path(__file__).resolve().parents[4]/'Artifacts/native-audio'/name


@dataclass
class Snapshot:
    data: dict
    master_gain: float = 1.
    @property
    def tempo(self): return self.data.get('bpm',self.data.get('tempo',124.))


class WorkspaceRenderer(Renderer):
    def __init__(self,snapshot,base=None):
        data=deepcopy(snapshot.data)
        self.rate=int(data.get('sampleRate',48000))
        if not 8000<=self.rate<=192000:raise ValueError('Unsupported sample rate')
        if data.get('channelFormat','Stereo')!='Stereo' or data.get('swingAmount',0):raise ValueError('Multichannel/swing playback awaits the native graph')
        tempo=snapshot.tempo; self.length=round(data.get('lengthBars',32)*data.get('beatsPerBar',4)*60/tempo*self.rate)
        if self.length>self.rate*600: raise ValueError('The development renderer currently supports sessions up to ten minutes')
        if data.get('tempoAutomationEnabled'): raise ValueError('Tempo-automation rendering awaits the native graph; project state is preserved')
        if any(not d.get('bypassed',False) and d['kind']!='Peak Limiter' for d in data.get('masterDevices',[])):
            raise ValueError('Master processors await native graph integration; no substitute effect was applied')
        self.sources=[]; solo=any(t.get('solo',False) for t in data['tracks'])
        engine=None
        for track in data['tracks']:
            if track.get('mute') or (solo and not track.get('solo')): continue
            active_audio=[c for c in track.get('audioClips',[]) if c.get('isActive',True)]
            events=[]
            for clip in track.get('clips',[]):
                if not clip.get('isActive',True): continue
                for note in clip.get('notes',[]):
                    events.append((clip['startBeat']+note['start'],note['pitch'],note['velocity'],max(.02,note['length'])))
            if track.get('useStepSequencer'):
                pattern=track.get('stepPattern',{});steps=pattern.get('steps',[]);spb=pattern.get('stepsPerBeat',4)
                if steps:
                    span=pattern.get('stepCount',len(steps))/spb
                    if span<=0: raise ValueError('Invalid step pattern length')
                    for loop in np.arange(0,data.get('lengthBars',32)*data.get('beatsPerBar',4),span):
                        for i,step in enumerate(steps):
                            for note in step.get('hits') or ([step['note']] if step.get('on') else []):
                                events.append((float(loop)+i/spb,note,step.get('velocity',.9),1/spb*.92))
            if track.get('frozen') or any(l.get('enabled',True) and l.get('points') for l in track.get('automationLanes',[])):
                raise ValueError('Freeze/automation playback awaits native graph integration; state is preserved')
            if not events and not active_audio: continue
            controls=[d for d in track.get('devices',[]) if track['kind']=='Analog Synth' and d['kind'] in ANALOG_DEVICES]
            if any(not d.get('bypassed',False) for d in track.get('devices',[]) if d not in controls) or track.get('externalPluginSlots') or track.get('pluginTargetID') or any(s.get('amount',0)>0 for s in track.get('sends',[])):
                raise ValueError(f"{track['name']}: device/routing rendering awaits the native graph; nothing was substituted")
            if track.get('sequencerLayers') and any(x.get('samplePath') or x.get('source')=='Plug-in' or x.get('volume',1)!=1 or x.get('pan',0)!=0 for x in track['sequencerLayers']):
                raise ValueError('Sample/plugin sequencer layers await their native renderer')
            if track.get('stereoWidth',1)!=1 or track.get('panMode','Stereo Balance')!='Stereo Balance':
                raise ValueError('Advanced pan/stereo rendering awaits the native graph')
            if track.get('groupID') or track.get('outputMode','Master')!='Master':
                raise ValueError('Group/external routing awaits the native graph')
            mono=np.zeros(self.length,dtype=np.float32)
            if events:
                if track['kind'] not in ('Drum Machine','Sequencer','Analog Synth','Guitar'):
                    raise ValueError(f"{track['kind']} DSP is not yet ported; the saved instrument was not replaced")
                engine=engine or NativeAudio(library_path())
                if track['kind'] in ('Drum Machine','Sequencer'):
                    messages=sorted(((round(b*60/tempo*self.rate),NOTES[n],v) for b,n,v,_ in events if n in NOTES and b>=0),key=lambda e:e[0])
                    kit=REFERENCE['drumKits'][track.get('drumGenre','Tech House')]
                    mono+=engine.render_kit(self.rate,self.length,messages,kit)
                else:
                    parameters={}
                    for device in controls:parameters.update(device.get('params',{}))
                    messages=[]
                    for b,n,v,duration in events:
                        if b<0:continue
                        messages.append((round(b*60/tempo*self.rate),1,n,v))
                        messages.append((round((b+duration)*60/tempo*self.rate),0,n,0.))
                    messages.sort(key=lambda e:(e[0],e[1])) # release before retrigger
                    mono+=engine.render_instrument(track['kind'],self.rate,self.length,messages,parameters,
                                                   seed=int(track.get('guitarExcitationSeed',0xC0FFEE)))
            for clip in active_audio:
                if clip.get('warpEnabled') or clip.get('pitchSemitones') or clip.get('pitchCents') or clip.get('devices'):
                    raise ValueError('Audio warp/pitch/clip effects await the native graph')
                samples=np.asarray(clip.get('samples',[]),dtype=np.float32)
                source_rate=clip['sampleRate'];start=round(clip['startBeat']*60/tempo*self.rate)
                duration=clip.get('lengthBeatsOverride',len(samples)/source_rate*tempo/60)
                count=max(0,min(round(duration*60/tempo*self.rate),len(mono)-start))
                if count and len(samples):
                    times=np.arange(count)/self.rate+clip.get('trimStartBeats',0)*60/tempo
                    if clip.get('loopEnabled'):times=np.remainder(times,len(samples)/source_rate)
                    indices=(times*source_rate).astype(np.int64)
                    valid=(indices>=0)&(indices<len(samples))
                    audio=np.zeros(count,dtype=np.float32);audio[valid]=samples[indices[valid]]
                    mono[start:start+count]+=audio*10**(clip.get('gainDB',0)/20)
            self.sources.append((track,mono))

        out=np.zeros((self.length,2),dtype=np.float32)
        for track,mono in self.sources:
            pan=track.get('pan',0);gain=track.get('volume',.8)
            levels=np.asarray([math.sqrt((1-pan)/2),math.sqrt((1+pan)/2)])*gain
            out+=mono[:,None]*levels
        for device in data.get('masterDevices',[]):
            if device.get('bypassed'):continue
            engine=engine or NativeAudio(library_path())
            if device.get('mono'):out[:]=out.mean(axis=1)[:,None]
            out=engine.apply_limiter(out,self.rate,device['params'])
        self.output=out*snapshot.master_gain

    def block(self,frame,count):
        return self.output[frame:frame+count]
