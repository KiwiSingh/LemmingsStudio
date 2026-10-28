"""Real native ring, recovery files and the actual Qt recording/document lifecycle."""
from copy import deepcopy
from pathlib import Path
from threading import Event,Thread
import ctypes as C
import json,os,time
import numpy as np
import pytest
import soundfile as sf
from lemmings_studio.native_capture import NativeCapture,bind
from lemmings_studio.recording import DryRecorder,take_clip
from lemmings_studio.project_contract import ProjectFile

@pytest.fixture
def library():
    value=os.environ.get('LEMMINGS_NATIVE_LIBRARY')
    if not value:pytest.skip('Native capture binary required')
    return Path(value)

def push(capture,data,flags=0):
    data=np.ascontiguousarray(data,dtype=np.float32)
    return capture.lib.ls_capture_test_push(capture.handle,data.ctypes.data_as(C.POINTER(C.c_float)),len(data),flags)

@pytest.mark.parametrize('rate',[44100,48000,96000])
@pytest.mark.parametrize('channels',[1,2,8])
def test_ring_wrap_keeps_channels_and_exact_frames(library,rate,channels):
    with NativeCapture(library,test_format=(rate,channels,17)) as capture:
        expected=np.arange(55*channels,dtype=np.float32).reshape(-1,channels)/128
        actual=[]
        for start in range(0,len(expected),7):
            part=expected[start:start+7];assert push(capture,part)==0
            actual.append(capture.read().copy())
        np.testing.assert_array_equal(np.concatenate(actual),expected)
        assert capture.info()['received']==55 and capture.info()['dropped']==0
        capture.stop();assert not len(capture.read())
    with pytest.raises(RuntimeError,match='closed'):capture.read()


def test_overflow_fails_explicitly_and_preserves_queued_source(library):
    with NativeCapture(library,test_format=(48000,2,8)) as capture:
        source=np.arange(12,dtype=np.float32).reshape(-1,2)
        assert push(capture,source)==0
        assert push(capture,source)==-2
        stats=capture.info();assert stats['error']==-2 and stats['dropped']==6
        np.testing.assert_array_equal(capture.read(),source)
        assert push(capture,source)==-1


def test_initial_discontinuity_silence_and_invalid_sample_are_reported(library):
    with NativeCapture(library,test_format=(48000,1,16)) as capture:
        assert push(capture,np.ones((3,1)),3)==0
        np.testing.assert_array_equal(capture.read(),0)
        assert capture.info()['discontinuities']==0 # WASAPI may flag the initial packet
        assert push(capture,np.ones((3,1)),2)==0
        assert capture.info()['discontinuities']==1
        capture.read();assert push(capture,np.array([[float('nan')]]))==0
        assert capture.info()['error']==-3
        assert np.isfinite(capture.read()).all()


def test_concurrent_native_producer_and_consumer(library):
    with NativeCapture(library,test_format=(48000,2,48000)) as capture:
        source=np.random.default_rng(13).normal(size=(40000,2)).astype('float32')
        finished=Event()
        def producer():
            for start in range(0,len(source),113):assert push(capture,source[start:start+113])==0
            finished.set()
        thread=Thread(target=producer);thread.start();actual=[]
        while not finished.is_set() or capture.info()['received']>sum(len(b) for b in actual):
            block=capture.read().copy()
            if len(block):actual.append(block)
            else:time.sleep(.001)
        thread.join();np.testing.assert_array_equal(np.concatenate(actual),source)


def test_invalid_native_configurations(library):
    lib=bind(library)
    for params in [(0,2,10),(48000,0,10),(48000,33,10),(48000,2,0),(48000,2,48000*9)]:
        assert not lib.ls_capture_test_open(*params)
    assert lib.ls_capture_read(None,None,0)==-1


def run_take(library,tmp_path,*,fault=False):
    expected=np.column_stack([np.linspace(-.8,.8,240),np.linspace(.4,-.4,240)]).astype('float32')
    class Capture(NativeCapture):
        def __init__(self,path,endpoint):
            super().__init__(path,test_format=(48000,2,48000))
            assert push(self,expected)==0
            if fault:
                push(self,np.ones((1,2)),2)
    result=[];done=Event();recorder=DryRecorder()
    recorder.on_finished=lambda value:(result.append(value),done.set())
    recorder.start(library,'',{'trackID':'test','startBeat':4.,'bpm':120.,'epoch':0},tmp_path,capture_factory=Capture,max_seconds=.005 if not fault else 241/48000)
    assert done.wait(5);recorder.thread.join()
    return expected,result[0]


def test_disk_take_is_recoverable_portable_and_retains_full_channel_source(library,tmp_path):
    source,result=run_take(library,tmp_path)
    assert result['error'] is None
    take=result['take'];assert take['state']=='complete' and take['limitReached']
    actual,rate=sf.read(take['path'],dtype='float32',always_2d=True)
    np.testing.assert_array_equal(actual,source);assert rate==48000
    clip=take_clip(take);np.testing.assert_array_equal(clip['samples'],source.mean(axis=1))
    assert clip['startBeat']==4 and not clip['warpEnabled'] and not clip['loopEnabled']
    info=json.loads(Path(take['path']).with_suffix('.json').read_text())
    assert info['state']=='complete' and info['frames']==240 and info['native']['dropped']==0


def test_discontinuous_take_retained_but_not_automatically_accepted(library,tmp_path):
    # Enough frames to stop at the deterministic duration after a flagged packet.
    source,result=run_take(library,tmp_path,fault=True)
    assert 'discontinuities' in result['error']
    assert result['take']['state']=='recoverable' and Path(result['take']['path']).is_file()


def test_input_open_failure_keeps_recovery_manifest(library,tmp_path):
    done=Event();results=[];recorder=DryRecorder()
    def fail(*args):raise RuntimeError('Microphone denied')
    recorder.on_finished=lambda value:(results.append(value),done.set())
    recorder.start(library,'missing',{},tmp_path,capture_factory=fail)
    assert done.wait(5);recorder.thread.join()
    assert 'Microphone denied' in results[0]['error']
    info=json.loads(next(tmp_path.glob('*.json')).read_text());assert info['state']=='recoverable'


def test_user_stop_drains_all_native_input_before_closing(library,tmp_path):
    ready=Event();done=Event();results=[]
    class Capture(NativeCapture):
        def __init__(self,path,endpoint):
            super().__init__(path,test_format=(48000,1,48000));push(self,np.ones((123,1))*.25);ready.set()
    recorder=DryRecorder();recorder.on_finished=lambda value:(results.append(value),done.set())
    recorder.start(library,'',{'startBeat':0,'bpm':120},tmp_path,capture_factory=Capture)
    assert ready.wait(5);recorder.stop();assert done.wait(5);recorder.thread.join()
    assert results[0]['error'] is None
    assert sf.info(results[0]['take']['path']).frames==123


def test_qt_recorded_take_is_one_undoable_shared_project_edit(library,tmp_path,monkeypatch):
    from PySide6.QtWidgets import QApplication
    from PySide6.QtTest import QTest
    from lemmings_studio.workspace import WorkspaceController
    app=QApplication.instance() or QApplication([])
    monkeypatch.setenv('LEMMINGS_DIAGNOSTICS_DIR',str(tmp_path/'diagnostics'))
    c=WorkspaceController(persist_preferences=False)
    track=c.document.data['tracks'][-1];track['armed']=True;c.track_id=track['id'];c.beat=4
    original=deepcopy(c.document.data)
    source,result=run_take(library,tmp_path/'takes');result['take'].update(trackID=track['id'],epoch=c.epoch)
    c.record_state='recording';c._recording_finished(result)
    deadline=time.monotonic()+5
    while c.pending and time.monotonic()<deadline:QTest.qWait(10)
    assert c.record_state=='idle' and c.pending==0
    assert len(c.track()['audioClips'])==1
    clip=c.track()['audioClips'][0];np.testing.assert_array_equal(clip['samples'],source.mean(axis=1))
    path=tmp_path/'recording.lemmingsproject';ProjectFile(c.document.data).save(path)
    assert ProjectFile.load(path).data['tracks'][-1]['audioClips'][0]==clip
    c.document.undo();assert c.document.data==original
    assert Path(result['take']['path']).exists()
    c.document.redo();assert c.track()['audioClips'][0]==clip
    c.document.saved=deepcopy(c.document.data);c.requestClose();app.processEvents()


def test_recording_blocks_session_replacement_and_close(tmp_path,monkeypatch):
    from PySide6.QtWidgets import QApplication
    from lemmings_studio.workspace import WorkspaceController
    app=QApplication.instance() or QApplication([])
    monkeypatch.setenv('LEMMINGS_DIAGNOSTICS_DIR',str(tmp_path/'diagnostics'))
    c=WorkspaceController(persist_preferences=False);before=deepcopy(c.document.data)
    c.record_state='recording'
    for name in ('new','open','undo','seek','play','tempo','inputDevice'):
        c.command(name,{})
        assert c.document.data==before and 'Stop recording' in c.status
    assert not c.requestClose();assert c.record_state=='finishing'
    c.record_state='idle';c.requestClose();app.processEvents()


def test_actual_record_command_captures_and_inserts_after_stop(library,tmp_path,monkeypatch):
    from types import SimpleNamespace
    from PySide6.QtWidgets import QApplication
    from PySide6.QtTest import QTest
    import lemmings_studio.workspace as workspace
    app=QApplication.instance() or QApplication([])
    monkeypatch.setenv('LEMMINGS_DIAGNOSTICS_DIR',str(tmp_path/'diagnostics'))
    monkeypatch.setattr(workspace,'sys',SimpleNamespace(platform='win32'))
    c=workspace.WorkspaceController(persist_preferences=False)
    c.track_id=c.document.data['tracks'][-1]['id'];c.track()['armed']=True
    original=deepcopy(c.document.data);ready=Event()
    class Capture(NativeCapture):
        def __init__(self,path,endpoint):
            super().__init__(path,test_format=(48000,2,48000));push(self,np.ones((256,2))*.25);ready.set()
    start=c.recorder.start
    monkeypatch.setattr(c.recorder,'start',lambda *args,**kwargs:start(*args,**kwargs,capture_factory=Capture))
    c.command('record',{});assert c.record_state=='opening'
    assert ready.wait(5)
    deadline=time.monotonic()+5
    while c.record_state=='opening' and time.monotonic()<deadline:
        QTest.qWait(10);time.sleep(.001)
    assert c.state['recordState']=='recording' and c.state['inputPeak']==.25
    assert c.document.data==original
    c.command('stop',{});assert c.record_state=='finishing'
    deadline=time.monotonic()+5
    while c.record_state!='idle' and time.monotonic()<deadline:QTest.qWait(10)
    assert c.record_state=='idle' and c.pending==0 and not c.recorder.running
    assert len(c.track()['audioClips'])==1 and c.track()['audioClips'][0]['samples']==[.25]*256
    c.document.undo();assert c.document.data==original
    c.document.saved=deepcopy(c.document.data);c.requestClose();app.processEvents()


def test_record_command_requires_armed_audio_and_preserves_project_on_open_failure(tmp_path,monkeypatch):
    from types import SimpleNamespace
    from PySide6.QtWidgets import QApplication
    from PySide6.QtTest import QTest
    import lemmings_studio.workspace as workspace
    app=QApplication.instance() or QApplication([])
    monkeypatch.setenv('LEMMINGS_DIAGNOSTICS_DIR',str(tmp_path/'diagnostics'))
    monkeypatch.setattr(workspace,'sys',SimpleNamespace(platform='win32'))
    c=workspace.WorkspaceController(persist_preferences=False)
    before=deepcopy(c.document.data);c.command('record',{})
    assert 'Arm' in c.status and c.record_state=='idle' and c.document.data==before
    c.track_id=c.document.data['tracks'][-1]['id'];c.track()['armed']=True
    before=deepcopy(c.document.data)
    def fail(*args):raise RuntimeError('Input denied')
    monkeypatch.setattr(c.recorder,'start',fail);c.command('record',{})
    assert c.record_state=='idle' and c.document.data==before and 'Input denied' in c.status
    c.document.saved=deepcopy(c.document.data);c.requestClose();app.processEvents()


@pytest.mark.parametrize('bits',[16,24,32])
def test_actual_wasapi_integer_conversion(library,bits):
    lib=bind(library);fn=lib.ls_capture_decode
    fn.argtypes=[C.POINTER(C.c_uint8),C.c_uint32,C.c_uint32,C.c_uint32,C.POINTER(C.c_float)];fn.restype=C.c_int
    half=2**(bits-1);integers=[-half,-half//2,-1,0,1,half//2,half-1]
    raw=b''.join(i.to_bytes(bits//8,'little',signed=True) for i in integers)
    data=(C.c_uint8*len(raw)).from_buffer_copy(raw);out=np.zeros(len(integers),dtype='float32')
    assert fn(data,len(out),bits,0,out.ctypes.data_as(C.POINTER(C.c_float)))==0
    np.testing.assert_array_equal(out,np.asarray(integers,dtype='float64').__truediv__(half).astype('float32'))


def test_actual_wasapi_float_conversion_and_invalid_format(library):
    lib=bind(library);fn=lib.ls_capture_decode
    fn.argtypes=[C.POINTER(C.c_uint8),C.c_uint32,C.c_uint32,C.c_uint32,C.POINTER(C.c_float)];fn.restype=C.c_int
    source=np.array([-1,-.1,0,.3,1],dtype='float32');out=np.zeros_like(source)
    data=source.ctypes.data_as(C.POINTER(C.c_uint8));target=out.ctypes.data_as(C.POINTER(C.c_float))
    assert fn(data,len(source),32,1,target)==0;np.testing.assert_array_equal(out,source)
    for bits,floating in [(8,0),(64,1),(16,1),(32,2)]:assert fn(data,len(source),bits,floating,target)==-1


def test_disk_worker_drains_large_queued_take_even_after_native_overflow(library,tmp_path):
    source=np.random.default_rng(7).normal(size=(100000,1)).astype('float32')
    class Capture(NativeCapture):
        def __init__(self,path,endpoint):
            super().__init__(path,test_format=(48000,1,100000))
            assert push(self,source)==0
            assert push(self,np.zeros((1,1)))==-2
    done=Event();results=[];recorder=DryRecorder()
    recorder.on_finished=lambda value:(results.append(value),done.set())
    recorder.start(library,'',{},tmp_path,capture_factory=Capture)
    assert done.wait(5);recorder.thread.join()
    result=results[0];assert result['error'] and result['take']['native']['dropped']==1
    actual,_=sf.read(result['take']['path'],dtype='float32',always_2d=True)
    np.testing.assert_array_equal(actual,source)
