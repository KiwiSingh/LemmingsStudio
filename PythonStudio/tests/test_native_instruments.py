"""Original Mac instrument oracle and stateful native block contract."""
import json,os
from pathlib import Path
import numpy as np
import pytest
from lemmings_studio.native_audio import NativeAudio

@pytest.fixture(scope='module')
def engine():
    path=os.environ.get('LEMMINGS_NATIVE_LIBRARY')
    if not path:pytest.skip('Requires compiled native engine')
    return NativeAudio(Path(path))

@pytest.mark.parametrize('rate',[44100,48000,96000])
@pytest.mark.parametrize('profile',range(6))
def test_actual_swift_instrument(engine,rate,profile):
    root=os.environ.get('LEMMINGS_SWIFT_INSTRUMENT_REFERENCE')
    if not root:pytest.skip('Requires actual Swift instrument references')
    root=Path(root);manifest=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
    item=next(x for x in manifest if x['file']==(f'analog-{rate}-{profile}' if profile<5 else f'guitar-{rate}'))
    excitation={int(k):np.fromfile(root/v,dtype='<f4') for k,v in item.get('excitations',{}).items()}
    expected=np.fromfile(root/(item['file']+'.f32'),dtype='<f4')
    for block in (128,511):
        actual=engine.render_instrument(item['kind'],rate,item['frames'],item['events'],item['parameters'],block_size=block,excitations=excitation or None)
        np.testing.assert_allclose(actual,expected,atol=3e-6,rtol=3e-5)
        assert np.isfinite(actual).all() and np.max(np.abs(actual))>.01

@pytest.mark.parametrize('kind',['Analog Synth','Guitar'])
def test_independent_seeded_instances_and_release(engine,kind):
    events=[(0,1,60,.8),(12000,0,60,0)]
    a=engine.render_instrument(kind,48000,48000,events,block_size=127)
    b=engine.render_instrument(kind,48000,48000,events,block_size=512)
    np.testing.assert_array_equal(a,b)
    assert np.max(np.abs(a[:12000]))>.01
    assert np.max(np.abs(a[-1000:]))==0
    if kind=='Analog Synth':
        assert not engine.render_instrument(kind,48000,48000,events,{'gain':0}).any()
    else:
        assert not np.array_equal(a,engine.render_instrument(kind,48000,48000,events,seed=123))

def test_invalid_and_closed_instrument(engine):
    for event in [(0,1,2**40,.8),(9999,1,60,float('nan')),(0,2,0,.5),(0,1,60,2)]:
        with pytest.raises(ValueError):engine.render_instrument('Analog Synth',48000,128,[event])
    for parameters in ({'gain':float('nan')},{'osc1':2.5},{'osc2':2**40}):
        with pytest.raises(ValueError):engine.instrument('Analog Synth',48000,parameters)
    with engine.instrument('Guitar',48000) as instance:
        with pytest.raises(ValueError):instance.process_into(np.zeros(65537,dtype=np.float32))
    with pytest.raises(ValueError):instance.event(1,60,.8)

@pytest.mark.parametrize('kind',['Analog Synth','Guitar'])
def test_shared_project_notes_parameters_and_export(engine,kind,tmp_path,monkeypatch):
    from lemmings_studio.workspace_document import WorkspaceDocument
    from lemmings_studio.project_contract import ProjectFile
    from lemmings_studio.workspace_audio import WorkspaceRenderer,Snapshot,REFERENCE
    doc=WorkspaceDocument();doc.data['lengthBars']=1;doc.data['tempo']=doc.data['bpm']=120
    tid=doc.data['tracks'][0]['id'];doc.track(doc.data,tid)['kind']=kind
    cid=doc.create_clip(tid);doc.add_note(tid,cid,.25,60)
    if kind=='Analog Synth':
        definition=next(d for d in REFERENCE['devices'] if d['kind']=='Subtractive Synth')
        did=doc.add_device(tid,definition)
        doc.device_param(tid,did,'cutoff',850,definition)
        doc.device_param(tid,did,'release',.05,definition)
    rendered=WorkspaceRenderer(Snapshot(doc.data)).output
    assert not rendered[:5000].any() # note must respect its position
    assert np.max(np.abs(rendered))>.01
    path=tmp_path/'musical.lemmingsproject';ProjectFile(doc.data).save(path)
    loaded=ProjectFile.load(path);assert loaded.data==doc.data
    reopened=WorkspaceRenderer(Snapshot(loaded.data))
    np.testing.assert_array_equal(rendered,reopened.output)
    reopened.export(tmp_path/'musical.wav');assert (tmp_path/'musical.wav').stat().st_size>10000
    if kind=='Analog Synth':
        doc.device_param(tid,did,'gain',0,definition)
        assert not WorkspaceRenderer(Snapshot(doc.data)).output.any()
    doc.track(doc.data,tid)['pluginTargetID']='unavailable-third-party'
    with pytest.raises(ValueError,match='nothing was substituted'):WorkspaceRenderer(Snapshot(doc.data))
