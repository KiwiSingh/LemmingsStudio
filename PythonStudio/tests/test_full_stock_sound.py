"""Numerical comparisons to compiled original Swift, plus production graph checks."""
from pathlib import Path
from copy import deepcopy
from contextlib import ExitStack
import json,os
import numpy as np
import pytest
from lemmings_studio.native_audio import NativeAudio
from lemmings_studio.native_effects import NativeEffect,render_effect
from lemmings_studio.native_sources import NativeKit,NativeSamples,warp
from lemmings_studio.stock_contract import *
from lemmings_studio.workspace_audio import WorkspaceRenderer,Snapshot,REFERENCE
from lemmings_studio.workspace_document import WorkspaceDocument,make_device,make_track,identity
from lemmings_studio.project_contract import ProjectFile
from lemmings_studio.musical_timeline import Timeline,midi_plan

@pytest.fixture(scope='module')
def engine():
    path=os.environ.get('LEMMINGS_NATIVE_LIBRARY')
    if not path:pytest.skip('Requires compiled native engine')
    return NativeAudio(Path(path))

def manifest(variable,file):
    root=os.environ.get(variable)
    return json.loads((Path(root)/file).read_text(encoding='utf-8')) if root else []

EFFECTS=manifest('LEMMINGS_SWIFT_EFFECT_REFERENCE','manifest.json')
STOCK=manifest('LEMMINGS_SWIFT_INSTRUMENT_REFERENCE','stock-manifest.json')
SAMPLES=manifest('LEMMINGS_SWIFT_INSTRUMENT_REFERENCE','sample-manifest.json')

@pytest.mark.parametrize('item',[i for i in EFFECTS if i['kind'] in EFFECT_FAMILIES],ids=lambda i:i['file'])
def test_original_effect_registry(engine,item):
    root=Path(os.environ['LEMMINGS_SWIFT_EFFECT_REFERENCE']);rate=item['rate']
    source=np.fromfile(root/f'input-{rate}.f32',dtype='<f4').reshape(-1,2)
    expected=np.fromfile(root/(item['file']+'.f32'),dtype='<f4').reshape(-1,2)
    actual=render_effect(engine,item['kind'],source,rate,item['parameters'],item['tempo'],sidechain=source*np.float32(3) if item.get('sidechain') else None)
    np.testing.assert_allclose(actual,expected,atol=4e-6,rtol=4e-5)
    assert np.isfinite(actual).all()

@pytest.mark.parametrize('item',STOCK,ids=lambda i:i['file'])
def test_original_stock_sources(engine,item):
    root=Path(os.environ['LEMMINGS_SWIFT_INSTRUMENT_REFERENCE'])
    actual=engine.render_instrument(item['kind'],item['rate'],item['frames'],item['events'],item['parameters'],block_size=128)
    expected=np.fromfile(root/(item['file']+'.f32'),dtype='<f4')
    np.testing.assert_allclose(actual,expected,atol=4e-6,rtol=4e-5)

@pytest.mark.parametrize('mode',['Beat','Complex','Complex Pro'])
@pytest.mark.parametrize('ratio',[.7,1.,1.35])
def test_original_warp(engine,mode,ratio):
    root=os.environ.get('LEMMINGS_SWIFT_WARP_REFERENCE')
    if not root:pytest.skip('Requires real Swift warp references')
    root=Path(root);source=np.fromfile(root/'input.f32',dtype='<f4')
    expected=np.fromfile(root/f'{mode}-{ratio}.f32',dtype='<f4')
    np.testing.assert_allclose(warp(engine,source,ratio,mode),expected,atol=4e-6,rtol=4e-5)

@pytest.mark.parametrize('item',SAMPLES,ids=lambda i:i['file'])
def test_original_sample_layer_polyphony(engine,item,tmp_path):
    root=Path(os.environ['LEMMINGS_SWIFT_INSTRUMENT_REFERENCE']);rate=item['rate'];hybrid=item['hybrid']
    with ExitStack() as stack:
        instrument=stack.enter_context(engine.instrument('Bhangra Architect',rate)) if hybrid else stack.enter_context(NativeKit(engine,rate,REFERENCE['drumKits']['Rock']))
        samples=stack.enter_context(NativeSamples(engine,[{'note':60,'embeddedSamples':item['samples'],'velocity':item['level']}],tmp_path,48 if hybrid else 32))
        actual=np.zeros(item['frames'],dtype=np.float32);events=item['events'];index=0
        for frame in range(0,len(actual),128):
            while index<len(events) and events[index][0]==frame:
                _,t,n,v=events[index];(samples if n==60 else instrument).event(t,n,v);index+=1
            part=actual[frame:frame+128];instrument.process_into(part);samples.process_into(part)
    expected=np.fromfile(root/(item['file']+'.f32'),dtype='<f4')
    np.testing.assert_allclose(actual,expected,atol=4e-6,rtol=4e-5)

def small_project(kind='Analog Synth'):
    doc=WorkspaceDocument();doc.data['lengthBars']=1;doc.data['bpm']=doc.data['tempo']=120;doc.data['masterDevices']=[]
    doc.data['keySnapEnabled']=False;doc.data['tracks']=[make_track('Source',kind)]
    tid=doc.data['tracks'][0]['id'];cid=doc.create_clip(tid);doc.add_note(tid,cid,0,60,1,.8)
    return doc,tid

@pytest.mark.parametrize('kind',['Analog Synth','Guitar','LemmingBass','Oscillatron','Indian Percussion','Bhangra Dhol','Bhangra Architect','Drum Machine','Sequencer','2C','Bailaton','Dubstep Wrangler'])
def test_all_track_sources_restore_and_export(engine,kind,tmp_path):
    doc,tid=small_project(kind)
    if kind in ('Drum Machine','Sequencer','2C','Bailaton','Dubstep Wrangler'):doc.data['tracks'][0]['clips'][0]['notes'][0]['pitch']=36
    doc.data['tracks'][0]['devices'].append(make_device('Room Space'))
    original=deepcopy(doc.data);a=WorkspaceRenderer(Snapshot(doc.data));assert np.max(abs(a.output))>.01
    assert doc.data==original
    file=tmp_path/'test.lemmingsproject';ProjectFile(doc.data).save(file)
    b=WorkspaceRenderer(Snapshot(ProjectFile.load(file).data));np.testing.assert_array_equal(a.output,b.output)
    b.export(tmp_path/'test.wav');assert (tmp_path/'test.wav').stat().st_size>1000

def test_gain_pan_sends_groups_and_no_double_freeze_fx(engine):
    doc,tid=small_project();t=doc.data['tracks'][0];a=WorkspaceRenderer(Snapshot(doc.data)).output
    t['volume']*=.5;t['pan']=.5
    b=WorkspaceRenderer(Snapshot(doc.data)).output
    np.testing.assert_allclose(b,a*np.array([.25,.5],dtype=np.float32),atol=1e-7)
    group={'id':identity(),'name':'Bus','volume':.5,'pan':-.5,'mute':False,'trackIDs':[tid],'devices':[]}
    doc.data['groups']=[group];t['groupID']=group['id'];c=WorkspaceRenderer(Snapshot(doc.data)).output
    np.testing.assert_allclose(c,a*.25,atol=1e-7)
    t['groupID']=None;t['pan']=0;t['volume']=1;t['devices']=[make_device('Gain Utility')];t['devices'][0]['params']['gain']=6
    t['frozen']=True;t['bounced']={'id':identity(),'startBeat':0,'samples':[.1]*1000,'sampleRate':48000,'loopEnabled':False}
    frozen=WorkspaceRenderer(Snapshot(doc.data)).output
    assert np.max(abs(frozen))==np.float32(.1)
    t['frozen']=False;t['devices']=[];t['volume']=.8
    doc.data['returnBuses']=[{'id':identity(),'name':'Return','devices':[],'volume':1,'pan':0}]
    t['sends']=[{'id':identity(),'returnBusID':doc.data['returnBuses'][0]['id'],'amount':.5,'preFader':False}]
    sends=WorkspaceRenderer(Snapshot(doc.data)).output;np.testing.assert_allclose(sends,a*1.5,atol=1e-7)
    t['outputMode']='Sends Only';t['sends'][0]['preFader']=True
    np.testing.assert_allclose(WorkspaceRenderer(Snapshot(doc.data)).output,a*(.5/.8),atol=1e-7)

def test_effect_automation_order_mono_bypass_and_sidechain(engine):
    doc,tid=small_project();track=doc.data['tracks'][0];track['devices']=[make_device('Gain Utility')];device=track['devices'][0]
    original=WorkspaceRenderer(Snapshot(doc.data)).output
    track['automationLanes']=[{'id':identity(),'nodeID':device['id'],'paramID':'gain','enabled':True,'points':[{'beat':0,'value':-12},{'beat':4,'value':-12}]}]
    before=deepcopy(doc.data);automated=WorkspaceRenderer(Snapshot(doc.data)).output
    np.testing.assert_allclose(automated,original*np.float32(10**(-12/20)),atol=1e-7);assert before==doc.data
    track['automationLanes'][0]['paramID']='__device_on__';track['automationLanes'][0]['points']=[{'beat':0,'value':0}]
    device['params']['gain']=-24
    np.testing.assert_array_equal(WorkspaceRenderer(Snapshot(doc.data)).output,original)
    source=np.ones((20000,2),dtype=np.float32)*.1
    with NativeEffect(engine,'Dynamics Compressor',48000,{'threshold':-30,'attack':.1}) as effect:
        loud=source.copy();effect.process_into(loud,np.ones_like(loud));effect.reset();quiet=source.copy();effect.process_into(quiet,np.zeros_like(quiet))
        assert np.mean(abs(loud[-1000:]))<np.mean(abs(quiet[-1000:]))*.2

def test_tempo_and_original_midi_effect_rules(engine):
    doc,tid=small_project();track=doc.data['tracks'][0]
    track['devices']=[make_device(k) for k in ('Pitch Tool','Chord Builder','Note Gate Length','Velocity Mapper')]
    track['devices'][0]['params']['transpose']=2
    pitches,velocity,duration=midi_plan(60,.8,1,track,doc.data,REFERENCE)
    assert pitches==[62,66,69] and velocity==pytest.approx(.8) and duration==.9
    doc.data['tempoAutomationEnabled']=True;doc.data['tempoPoints']=[{'beat':0,'bpm':60},{'beat':4,'bpm':120}]
    timeline=Timeline(doc.data,48000)
    assert timeline.frame(4)>96000 and timeline.beat(timeline.frame(2))==pytest.approx(2,abs=1e-5)
    assert WorkspaceRenderer(Snapshot(doc.data)).length==timeline.frame(4)

def test_portable_one_shot_replaces_lane_and_preserves_source(engine,tmp_path):
    import soundfile as sf
    doc,tid=small_project('Drum Machine');track=doc.data['tracks'][0];track['clips'][0]['notes'][0]['pitch']=36
    path=tmp_path/'original.wav';sample=np.sin(np.arange(3000)*.2).astype(np.float32)*.3;sf.write(path,sample,48000,subtype='FLOAT')
    track['sequencerLayers']=[{'id':identity(),'note':36,'source':'Splice Sample','velocity':.7,'samplePath':'original.wav','volume':1,'pan':0,'steps':[]}]
    original=deepcopy(doc.data);portable=ProjectFile(doc.data).portable(tmp_path);assert doc.data==original
    before=WorkspaceRenderer(Snapshot(portable.data),tmp_path).output;path.rename(tmp_path/'retained.wav')
    after=WorkspaceRenderer(Snapshot(portable.data),tmp_path/'unavailable').output
    np.testing.assert_array_equal(before,after)
    assert portable.data['tracks'][0]['sequencerLayers'][0]['samplePath']=='original.wav'
    with pytest.raises((RuntimeError,OSError)):WorkspaceRenderer(Snapshot(doc.data),tmp_path)

def test_registry_is_accounted_for_without_unknown_sound_substitution(engine):
    assert {d['kind'] for d in REFERENCE['devices']}==EFFECT_FAMILIES.keys()|BUILTIN_DEVICES|MIDI_DEVICES|RACK_DEVICES|BRIDGE_DEVICES
    doc,tid=small_project();doc.data['tracks'][0]['devices']=[{'id':identity(),'kind':'Unknown Effect','params':{}}]
    with pytest.raises(ValueError,match='nothing was substituted'):WorkspaceRenderer(Snapshot(doc.data))
    doc.data['tracks'][0]['devices']=[];doc.data['tracks'][0]['pluginTargetID']='Missing plugin'
    with pytest.raises(ValueError,match='nothing was substituted'):WorkspaceRenderer(Snapshot(doc.data))

def test_workspace_scope_never_double_triggers_grid_and_print(engine):
    doc,tid=small_project('Drum Machine');track=doc.data['tracks'][0];track['clips'][0]['notes'][0]['pitch']=36
    doc.toggle_step(tid,36,0);track=doc.data['tracks'][0];track['useStepSequencer']=True
    arrangement=WorkspaceRenderer(Snapshot(doc.data)).output
    grid=WorkspaceRenderer(Snapshot(doc.data,scope='stepSequencer')).output
    track['clips']=[]
    assert not WorkspaceRenderer(Snapshot(doc.data)).output.any()
    np.testing.assert_array_equal(grid,WorkspaceRenderer(Snapshot(doc.data,scope='stepSequencer')).output)
    assert np.max(abs(arrangement))>.01 and np.max(abs(grid))>.01
    other=make_track('No arrangement bleed','Analog Synth');other['clips']=[{'startBeat':0,'isActive':True,'notes':[{'pitch':60,'start':0,'length':1,'velocity':1}]}]
    doc.data['tracks'].append(other)
    np.testing.assert_array_equal(grid,WorkspaceRenderer(Snapshot(doc.data,scope='stepSequencer')).output)

def test_render_cancellation_and_tail_metronome(engine):
    from threading import Event
    doc,_=small_project();stop=Event();stop.set();original=deepcopy(doc.data)
    with pytest.raises(InterruptedError):WorkspaceRenderer(Snapshot(doc.data),cancelled=stop)
    assert doc.data==original
    plain=WorkspaceRenderer(Snapshot(doc.data));tail=WorkspaceRenderer(Snapshot(doc.data,tail_seconds=1))
    assert tail.length==plain.length+plain.rate
    click=WorkspaceRenderer(Snapshot(doc.data,metronome=True))
    assert not np.array_equal(click.output,plain.output)
    assert np.max(abs(click.output-plain.output))>.1

@pytest.mark.parametrize('item',[i for i in EFFECTS if i['kind'] in MIDI_DEVICES|RACK_DEVICES|BRIDGE_DEVICES],ids=lambda i:i['file'])
def test_reference_transparent_registry_slots_are_not_claimed_as_new_dsp(item):
    root=Path(os.environ['LEMMINGS_SWIFT_EFFECT_REFERENCE'])
    source=np.fromfile(root/f'input-{item["rate"]}.f32',dtype='<f4')
    expected=np.fromfile(root/(item['file']+'.f32'),dtype='<f4')
    np.testing.assert_array_equal(source,expected)

def test_background_playback_swap_and_failed_update_preserve_writer(monkeypatch,tmp_path):
    import sys,time
    from types import SimpleNamespace
    from threading import Event
    from lemmings_studio.audio import AudioEngine
    first=Event();changed=Event();failure=Event();values=[]
    class Stream:
        def __init__(self,**_):pass
        def __enter__(self):return self
        def __exit__(self,*_):pass
        def write(self,audio):
            values.append(float(audio[-1,0]));first.set()
            if values[-1]>1.9:changed.set()
            time.sleep(.002)
    class Render:
        supports_cancellation=True
        def __init__(self,project,base,cancelled=None):
            if project.value<0:raise ValueError('Test invalid graph')
            self.value=project.value;self.rate=48000;self.length=10000000
        def block(self,position,count):return np.full((count,2),self.value,dtype=np.float32)
        def frame_at_beat(self,beat):return round(beat*24000)
        def beat_at_frame(self,frame):return frame/24000
    monkeypatch.setitem(sys.modules,'sounddevice',SimpleNamespace(OutputStream=Stream))
    audio=AudioEngine();audio.on_finished=lambda _,message:failure.set() if 'update failed' in message else None
    try:
        audio.play(SimpleNamespace(value=1,tempo=120),tmp_path,renderer_factory=Render)
        assert first.wait(3);generation=audio.generation
        audio.replace(SimpleNamespace(value=2,tempo=120),tmp_path,Render)
        assert changed.wait(3);assert audio.generation==generation and audio.running
        audio.replace(SimpleNamespace(value=-1,tempo=120),tmp_path,Render)
        assert failure.wait(3);assert audio.generation==generation and audio.running
        assert values[0]==1 and values[-1]==2
    finally:
        audio.stop();audio._thread.join(3)
    assert not audio.running

def test_effect_boundaries_closed_instances_and_native_schema(engine):
    import ctypes as C
    from lemmings_studio.native_effects import Parameter
    with NativeEffect(engine,'Tempo Delay',48000) as effect:
        with pytest.raises(ValueError):effect.set('feedback',2)
        with pytest.raises(ValueError):effect.set('time',float('inf'))
        with pytest.raises(ValueError):effect.process_into(np.zeros((70000,2),dtype=np.float32))
        bad=(Parameter*1)(Parameter(b'time',1e100))
        assert not engine.library.ls_effect_create(b'delay',48000,120,bad,1)
    with pytest.raises(ValueError):effect.process_into(np.zeros((128,2),dtype=np.float32))


def test_native_analyzer_measurements_are_readable(engine):
    with NativeEffect(engine,'Spectrum Analyzer',48000) as effect:
        signal=np.full((128,2),.2,dtype=np.float32);original=signal.copy();effect.process_into(signal)
        np.testing.assert_array_equal(signal,original)
        assert effect.get('peak')==pytest.approx(.03,abs=1e-6)
        assert effect.get('rms')==pytest.approx(.03,abs=1e-6)
        assert effect.get('activity')==0 and effect.get('rate')==1
