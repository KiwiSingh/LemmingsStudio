"""Installed-app checks for the actual workspace, run only in explicit check mode."""
from copy import deepcopy
from PySide6.QtCore import QEventLoop,QTimer
from PySide6.QtQuick import QQuickItem
from .workspace import WORKSPACES,REFERENCE
from .project_contract import ProjectFile
from .workspace_document import identity
from .workspace_audio import WorkspaceRenderer,Snapshot


def settle():
    loop=QEventLoop();QTimer.singleShot(80,loop.quit);loop.exec()


def verify(window,output):
    output.mkdir(parents=True,exist_ok=True)
    c=window.controller;original=deepcopy(c.document.data);original_theme=c.theme
    tid=c.document.data['tracks'][1]['id']
    c.command('selectTrack',{'track':tid});c.command('createClip',{})
    c.command('addNote',{'beat':0,'pitch':36});c.command('step',{'pitch':42,'step':0})
    edited=deepcopy(c.document.data);c.command('undo',{});assert c.document.data!=edited
    c.command('redo',{});assert c.document.data==edited
    path=output/'workspace-check.lemmingsproject';ProjectFile(edited).save(path)
    assert ProjectFile.load(path).data==edited
    checks={'shared_project_edit_undo_reopen':True};captures=[];viewports=[]
    # Explicit finite maximum overrides Windows' default monitor-sized tracking
    # limit on the small Hyper-V CI display. The actual client size is asserted.
    window.window.setMaximumWidth(4096);window.window.setMaximumHeight(4096)
    for size in [(1600,900),(1024,768)]:
        window.window.resize(*size);settle()
        assert (window.window.width(),window.window.height())==size,f'Requested {size}, actual {(window.window.width(),window.window.height())}'
        viewports.append({'logical_width':window.window.width(),'logical_height':window.window.height()})
        for page in WORKSPACES:
            c.command('workspace',{'value':page});settle()
            loader=window.window.findChild(QQuickItem,'workspacePage')
            assert loader.property('ready') and loader.width()>300 and loader.height()>100,page
            filename=f'{size[0]}x{size[1]}-{page.replace(" ","-")}.png'
            capture=window.window.grabWindow()
            ratio=capture.devicePixelRatio()
            assert (capture.width(),capture.height())==(round(size[0]*ratio),round(size[1]*ratio)),filename
            assert capture.save(str(output/filename)),filename
            captures.append(filename)
    window.window.resize(1600,900);c.workspace='Arrangement'
    for theme in REFERENCE['themes']:
        c.theme=theme['name'];c.notify();settle()
        filename='theme-'+''.join(x if x.isalnum() else '-' for x in c.theme)+'.png'
        assert window.window.grabWindow().save(str(output/filename))
        captures.append(filename)
    snapshot=Snapshot(deepcopy(edited));snapshot.data['lengthBars']=1
    renderer=WorkspaceRenderer(snapshot)
    import numpy as np
    assert np.max(np.abs(renderer.block(0,min(renderer.rate,renderer.length))))>.01
    renderer.export(output/'original-drum-workspace.wav')
    for kind in ('Analog Synth','Guitar','LemmingBass','Oscillatron','Indian Percussion','Bhangra Dhol','Bhangra Architect','Drum Machine','Sequencer','2C','Bailaton','Dubstep Wrangler'):
        musical=deepcopy(original);musical['lengthBars']=1
        track=musical['tracks'][0];track['kind']=kind
        track['clips']=[{'id':identity(),'startBeat':0,'lengthBeats':4,'isActive':True,'notes':[{'id':identity(),'start':.25,'length':.5,'pitch':36 if kind in ('Drum Machine','Sequencer','2C','Bailaton','Dubstep Wrangler') else 60,'velocity':.8}]}]
        saved=output/(kind.replace(' ','-')+'-check.lemmingsproject');ProjectFile(musical).save(saved)
        native=WorkspaceRenderer(Snapshot(ProjectFile.load(saved).data))
        assert np.max(np.abs(native.output))>.01
        assert not native.output[:1000].any()
        native.export(output/(kind.replace(' ','-')+'-workspace.wav'))
        checks[kind.replace(' ','_').lower()+'_render_reopen']=True
    from .native_audio import NativeAudio
    from .native_effects import render_effect
    from .workspace_audio import library_path
    from .stock_contract import EFFECT_FAMILIES
    native_engine=NativeAudio(library_path());signal=np.column_stack([np.sin(np.arange(4096)*.07)*.2,np.cos(np.arange(4096)*.13)*.15]).astype(np.float32)
    for kind in EFFECT_FAMILIES:
        actual=render_effect(native_engine,kind,signal,48000)
        assert actual.shape==signal.shape and np.isfinite(actual).all(),kind
    checks['all_stock_effect_binaries']=len(EFFECT_FAMILIES)
    # Exercise the installed input ABI and dry-file path without requiring or
    # opening a CI user's microphone. Hardware acceptance is a separate gate.
    from .native_capture import NativeCapture
    from .recording import DryRecorder,take_clip
    from threading import Event
    import ctypes as C
    class Capture(NativeCapture):
        def __init__(self,path,endpoint):
            super().__init__(path,test_format=(48000,2,48000))
            assert self.lib.ls_capture_test_push(self.handle,signal.ctypes.data_as(C.POINTER(C.c_float)),len(signal),0)==0
    done=Event();results=[];recorder=DryRecorder()
    recorder.on_finished=lambda result:(results.append(result),done.set())
    recorder.start(library_path(),'',{'startBeat':0.,'bpm':124.},output/'recording',capture_factory=Capture,max_seconds=len(signal)/48000)
    assert done.wait(10),'Native recording disk worker timed out'
    recorder.thread.join();assert results[0]['error'] is None,results[0]['error']
    clip=take_clip(results[0]['take']);np.testing.assert_array_equal(clip['samples'],signal.mean(axis=1))
    recording=deepcopy(original);recording['tracks'][-1]['audioClips']=[clip]
    ProjectFile(recording).save(output/'recorded-take.lemmingsproject')
    assert ProjectFile.load(output/'recorded-take.lemmingsproject').data==recording
    checks['native_input_ring_disk_take_and_project_reopen']=True
    checks.update(seven_workspaces_two_sizes=True,eleven_original_palettes=True,native_drum_render=True,
                  qml_errors_absent=not window.warnings)
    if window.warnings:raise RuntimeError('\n'.join(window.warnings))
    c.document.data=original;c.document.saved=deepcopy(original);c.theme=original_theme;c.notify()
    return {'checks':checks,'captures':captures,'viewports':viewports,'directory':str(output)}
